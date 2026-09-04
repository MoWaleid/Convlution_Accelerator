library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity coeff_bias_shift_regfile is
    generic (
        C_K : integer range 1 to 64 := CFG_K; -- Number of channels (defaults to global config)
        C_N : integer range 1 to 15 := CFG_N  -- Kernel size (defaults to global config)
    );
    port (
        clk    : in std_logic;
        resetn : in std_logic;
        
        -- Simple memory-mapped write interface
        wr_en   : in std_logic;
        wr_addr : in std_logic_vector(31 downto 0);
        wr_data : in std_logic_vector(31 downto 0);
        wr_strb : in std_logic_vector(3 downto 0);
        
        -- Simple memory-mapped read interface
        rd_en   : in std_logic;
        rd_addr : in std_logic_vector(31 downto 0);
        rd_data : out std_logic_vector(31 downto 0);
        
        -- Parallel outputs to datapath
        coeffs_out  : out coeff_array_t(0 to C_K * C_N * C_N - 1);
        bias_out    : out bias_array_t(0 to C_K - 1);
        shift_out   : out shift_array_t(0 to C_K - 1);
        relu_en_out : out std_logic_vector(0 to C_K - 1)
    );
end entity coeff_bias_shift_regfile;

architecture rtl of coeff_bias_shift_regfile is

    constant C_BUS_WORD_WIDTH  : positive := 32;
    constant C_COEFFS_PER_WORD : positive := C_BUS_WORD_WIDTH / CFG_WEIGHT_WIDTH;
    constant C_COEFF_WORDS     : positive := (C_N * C_N + C_COEFFS_PER_WORD - 1) / C_COEFFS_PER_WORD;
    constant C_BIAS_WORD       : natural  := 62;
    constant C_CONTROL_WORD    : natural  := 63;

    function final_coeff_word_mask return std_logic_vector is
        variable mask : std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0) := (others => '0');
    begin
        for lane in 0 to C_COEFFS_PER_WORD - 1 loop
            if (C_COEFF_WORDS - 1) * C_COEFFS_PER_WORD + lane < C_N * C_N then
                mask((lane + 1) * CFG_WEIGHT_WIDTH - 1 downto lane * CFG_WEIGHT_WIDTH) := (others => '1');
            end if;
        end loop;
        return mask;
    end function final_coeff_word_mask;

    constant C_FINAL_COEFF_WORD_MASK : std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0) :=
        final_coeff_word_mask;

    -- Coefficients are stored in their software-visible packed-word form.
    -- Keeping channel and word as independent dimensions avoids a flattened
    -- runtime coefficient index in the AXI-Lite read/write decode path.
    type coeff_word_storage_t is array (0 to C_K - 1, 0 to C_COEFF_WORDS - 1) of
        std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0);

    signal coeff_words_reg : coeff_word_storage_t;
    signal bias_reg        : bias_array_t(0 to C_K - 1);
    signal shift_reg       : shift_array_t(0 to C_K - 1);
    signal relu_en_reg     : std_logic_vector(0 to C_K - 1);

begin

    assert C_COEFF_WORDS <= C_BIAS_WORD
        report "Kernel configuration does not fit before the bias register"
        severity failure;

    -- Each coefficient output is selected by elaboration-time indices. The
    -- invalid byte lanes of a final partial word have no corresponding output.
    gen_coeff_output_channel : for channel in 0 to C_K - 1 generate
        gen_coeff_output_word : for word in 0 to C_COEFF_WORDS - 1 generate
            gen_coeff_output_lane : for lane in 0 to C_COEFFS_PER_WORD - 1 generate
                gen_valid_coeff_lane : if word * C_COEFFS_PER_WORD + lane < C_N * C_N generate
                    coeffs_out(channel * C_N * C_N + word * C_COEFFS_PER_WORD + lane) <=
                        coeff_words_reg(channel, word)
                            ((lane + 1) * CFG_WEIGHT_WIDTH - 1 downto lane * CFG_WEIGHT_WIDTH);
                end generate gen_valid_coeff_lane;
            end generate gen_coeff_output_lane;
        end generate gen_coeff_output_word;
    end generate gen_coeff_output_channel;

    bias_out    <= bias_reg;
    shift_out   <= shift_reg;
    relu_en_out <= relu_en_reg;

    -- Address map per channel (256 bytes = 64 words per channel block):
    -- Base address for channel C: C * 0x100
    -- Address bits 15:14 are reserved; bits 13:8 select one of 64 channels.
    -- Words 0 to C_COEFF_WORDS-1: Packed coefficients (C_COEFFS_PER_WORD values per word)
    -- Word 62: Bias
    -- Word 63: Shift (bits 4:0) and ReLU Enable (bit 8)

    -- Write Process
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                for channel in 0 to C_K - 1 loop
                    for word in 0 to C_COEFF_WORDS - 1 loop
                        coeff_words_reg(channel, word) <= (others => '0');
                    end loop;
                    bias_reg(channel)    <= (others => '0');
                    shift_reg(channel)   <= (others => '0');
                    relu_en_reg(channel) <= '0';
                end loop;
            elsif wr_en = '1' then
                -- Both loop ranges are static generic ranges. The direct
                -- address comparisons therefore elaborate to per-register
                -- enables rather than a runtime flattened coefficient index.
                for channel in 0 to C_K - 1 loop
                    if wr_addr(13 downto 8) = std_logic_vector(to_unsigned(channel, 6)) then
                        for word in 0 to C_COEFF_WORDS - 1 loop
                            if wr_addr(7 downto 2) = std_logic_vector(to_unsigned(word, 6)) then
                                -- Byte enables are intentionally explicit. A
                                -- final partial word only updates its valid
                                -- coefficient lanes; the rest remain zero.
                                if wr_strb(0) = '1' then
                                    coeff_words_reg(channel, word)(7 downto 0) <= wr_data(7 downto 0);
                                end if;
                                if word * C_COEFFS_PER_WORD + 1 < C_N * C_N and wr_strb(1) = '1' then
                                    coeff_words_reg(channel, word)(15 downto 8) <= wr_data(15 downto 8);
                                end if;
                                if word * C_COEFFS_PER_WORD + 2 < C_N * C_N and wr_strb(2) = '1' then
                                    coeff_words_reg(channel, word)(23 downto 16) <= wr_data(23 downto 16);
                                end if;
                                if word * C_COEFFS_PER_WORD + 3 < C_N * C_N and wr_strb(3) = '1' then
                                    coeff_words_reg(channel, word)(31 downto 24) <= wr_data(31 downto 24);
                                end if;
                            end if;
                        end loop;

                        if wr_addr(7 downto 2) = std_logic_vector(to_unsigned(C_BIAS_WORD, 6)) then
                            -- Bias register with byte enables.
                            if wr_strb(0) = '1' then
                                bias_reg(channel)(7 downto 0) <= wr_data(7 downto 0);
                            end if;
                            if wr_strb(1) = '1' then
                                bias_reg(channel)(15 downto 8) <= wr_data(15 downto 8);
                            end if;
                            if wr_strb(2) = '1' then
                                bias_reg(channel)(23 downto 16) <= wr_data(23 downto 16);
                            end if;
                            if wr_strb(3) = '1' then
                                bias_reg(channel)(31 downto 24) <= wr_data(31 downto 24);
                            end if;
                        elsif wr_addr(7 downto 2) = std_logic_vector(to_unsigned(C_CONTROL_WORD, 6)) then
                            -- Shift occupies byte 0 and ReLU enable occupies
                            -- byte 1, so each field obeys its corresponding strobe.
                            if wr_strb(0) = '1' then
                                shift_reg(channel) <= wr_data(CFG_SHIFT_WIDTH - 1 downto 0);
                            end if;
                            if wr_strb(1) = '1' then
                                relu_en_reg(channel) <= wr_data(8);
                            end if;
                        end if;
                    end if;
                end loop;
            end if;
        end if;
    end process;

    -- Read Process (Combinatorial)
    process(rd_en, rd_addr, coeff_words_reg, bias_reg, shift_reg, relu_en_reg)
        variable channel_index : natural range 0 to 63;
        variable word_index    : natural range 0 to 63;
        variable coeff_mask    : std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0);
    begin
        rd_data <= (others => '0');

        channel_index := to_integer(unsigned(rd_addr(13 downto 8)));
        word_index    := to_integer(unsigned(rd_addr(7 downto 2)));

        if rd_en = '1' and channel_index < C_K then
            if word_index < C_COEFF_WORDS then
                -- This is a bounded two-dimensional packed-word lookup. The
                -- final-word mask retains zero readback for unused lanes.
                coeff_mask := (others => '1');
                if word_index = C_COEFF_WORDS - 1 then
                    coeff_mask := C_FINAL_COEFF_WORD_MASK;
                end if;
                rd_data <= coeff_words_reg(channel_index, word_index) and coeff_mask;
            elsif word_index = C_BIAS_WORD then
                rd_data <= bias_reg(channel_index);
            elsif word_index = C_CONTROL_WORD then
                rd_data(CFG_SHIFT_WIDTH - 1 downto 0) <= shift_reg(channel_index);
                rd_data(8)          <= relu_en_reg(channel_index);
            end if;
        end if;
    end process;

end architecture rtl;
