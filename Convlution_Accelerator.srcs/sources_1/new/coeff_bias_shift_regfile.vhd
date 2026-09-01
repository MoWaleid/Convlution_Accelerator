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

    -- Internal storage
    signal coeffs_reg  : coeff_array_t(0 to C_K * C_N * C_N - 1);
    signal bias_reg    : bias_array_t(0 to C_K - 1);
    signal shift_reg   : shift_array_t(0 to C_K - 1);
    signal relu_en_reg : std_logic_vector(0 to C_K - 1);

    -- Helper signals for address decoding
    signal ch_idx_wr : integer range 0 to 63;
    signal word_offset_wr : integer range 0 to 63;
    
    signal ch_idx_rd : integer range 0 to 63;
    signal word_offset_rd : integer range 0 to 63;

begin

    assert C_COEFF_WORDS <= C_BIAS_WORD
        report "Kernel configuration does not fit before the bias register"
        severity failure;

    -- Drive parallel outputs directly from registers
    coeffs_out  <= coeffs_reg;
    bias_out    <= bias_reg;
    shift_out   <= shift_reg;
    relu_en_out <= relu_en_reg;

    -- Decode addresses
    -- Address map per channel (256 bytes = 64 words per channel block):
    -- Base address for channel C: C * 0x100
    -- Address bits 15:14 are reserved; bits 13:8 select one of 64 channels.
    -- Words 0 to C_COEFF_WORDS-1: Packed coefficients (C_COEFFS_PER_WORD values per word)
    -- Word 62: Bias
    -- Word 63: Shift (bits 4:0) and ReLU Enable (bit 8)
    
    ch_idx_wr <= to_integer(unsigned(wr_addr(13 downto 8)));
    word_offset_wr <= to_integer(unsigned(wr_addr(7 downto 2)));
    
    ch_idx_rd <= to_integer(unsigned(rd_addr(13 downto 8)));
    word_offset_rd <= to_integer(unsigned(rd_addr(7 downto 2)));

    -- Write Process
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                for i in 0 to C_K * C_N * C_N - 1 loop
                    coeffs_reg(i) <= (others => '0');
                end loop;
                for i in 0 to C_K - 1 loop
                    bias_reg(i)    <= (others => '0');
                    shift_reg(i)   <= (others => '0');
                    relu_en_reg(i) <= '0';
                end loop;
            else
                if wr_en = '1' then
                    if ch_idx_wr < C_K then
                        if word_offset_wr < C_COEFF_WORDS then
                            -- Store each packed coefficient only when its byte
                            -- lane is enabled by WSTRB.
                            for coeff_lane in 0 to C_COEFFS_PER_WORD - 1 loop
                                if wr_strb(coeff_lane) = '1' and
                                   word_offset_wr * C_COEFFS_PER_WORD + coeff_lane < C_N * C_N then
                                    coeffs_reg(ch_idx_wr * C_N * C_N + word_offset_wr * C_COEFFS_PER_WORD + coeff_lane) <=
                                        wr_data((coeff_lane + 1) * CFG_WEIGHT_WIDTH - 1 downto coeff_lane * CFG_WEIGHT_WIDTH);
                                end if;
                            end loop;
                        elsif word_offset_wr = C_BIAS_WORD then
                            -- Bias register with byte enables.
                            for byte_lane in 0 to C_BUS_WORD_WIDTH / 8 - 1 loop
                                if wr_strb(byte_lane) = '1' then
                                    bias_reg(ch_idx_wr)((byte_lane + 1) * 8 - 1 downto byte_lane * 8) <=
                                        wr_data((byte_lane + 1) * 8 - 1 downto byte_lane * 8);
                                end if;
                            end loop;
                        elsif word_offset_wr = C_CONTROL_WORD then
                            -- Shift occupies byte 0 and ReLU enable occupies
                            -- byte 1, so each field obeys its corresponding strobe.
                            if wr_strb(0) = '1' then
                                shift_reg(ch_idx_wr) <= wr_data(CFG_SHIFT_WIDTH - 1 downto 0);
                            end if;
                            if wr_strb(1) = '1' then
                                relu_en_reg(ch_idx_wr) <= wr_data(8);
                            end if;
                        end if;
                    end if;
                end if;
            end if;
        end if;
    end process;
    -- Read Process (Combinatorial)
    process(rd_en, rd_addr, coeffs_reg, bias_reg, shift_reg, relu_en_reg, ch_idx_rd, word_offset_rd)
    begin
        -- Default read data
        rd_data <= (others => '0');
        
        if rd_en = '1' then
            if ch_idx_rd < C_K then
                if word_offset_rd < C_COEFF_WORDS then
                    -- Return the packed coefficient word exactly as it was written.
                    for coeff_lane in 0 to C_COEFFS_PER_WORD - 1 loop
                        if word_offset_rd * C_COEFFS_PER_WORD + coeff_lane < C_N * C_N then
                            rd_data((coeff_lane + 1) * CFG_WEIGHT_WIDTH - 1 downto coeff_lane * CFG_WEIGHT_WIDTH) <=
                                coeffs_reg(ch_idx_rd * C_N * C_N + word_offset_rd * C_COEFFS_PER_WORD + coeff_lane);
                        end if;
                    end loop;
                elsif word_offset_rd = C_BIAS_WORD then
                    rd_data <= bias_reg(ch_idx_rd);
                elsif word_offset_rd = C_CONTROL_WORD then
                    rd_data(CFG_SHIFT_WIDTH - 1 downto 0) <= shift_reg(ch_idx_rd);
                    rd_data(8)          <= relu_en_reg(ch_idx_rd);
                end if;
            end if;
        end if;
    end process;

end architecture rtl;
