library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity coeff_bias_shift_regfile is
    generic (
        C_K : integer range 1 to 64 := CFG_K;
        C_N : integer range 1 to 15 := CFG_N
    );
    port (
        clk    : in std_logic;
        resetn : in std_logic;

        -- Simple committed-write interface.
        --
        -- Under CVH1, axi_lite_ctrl validates address, WSTRB, state and data
        -- before asserting wr_en. Therefore wr_en represents one complete,
        -- atomic parameter write.
        wr_en   : in std_logic;
        wr_addr : in std_logic_vector(13 downto 2);
        wr_data : in std_logic_vector(31 downto 0);

        -- Simple memory-mapped read interface.
        rd_en   : in std_logic;
        rd_addr : in std_logic_vector(13 downto 2);
        rd_data : out std_logic_vector(31 downto 0);

        -- Parallel outputs to datapath.
        coeffs_out  : out coeff_array_t(0 to C_K * C_N * C_N - 1);
        bias_out    : out bias_array_t(0 to C_K - 1);
        shift_out   : out shift_array_t(0 to C_K - 1);
        relu_en_out : out std_logic_vector(0 to C_K - 1)
    );
end entity coeff_bias_shift_regfile;


architecture rtl of coeff_bias_shift_regfile is

    constant C_BUS_WORD_WIDTH  : positive := 32;
    constant C_COEFFS_PER_WORD : positive :=
        C_BUS_WORD_WIDTH / CFG_WEIGHT_WIDTH;

    constant C_COEFF_WORDS : positive :=
        (C_N * C_N + C_COEFFS_PER_WORD - 1) / C_COEFFS_PER_WORD;

    constant C_BIAS_WORD    : natural := 62;
    constant C_CONTROL_WORD : natural := 63;

    function final_coeff_word_mask return std_logic_vector is
        variable mask :
            std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0) :=
                (others => '0');
    begin
        for lane in 0 to C_COEFFS_PER_WORD - 1 loop
            if (C_COEFF_WORDS - 1) * C_COEFFS_PER_WORD + lane
                    < C_N * C_N then
                mask(
                    (lane + 1) * CFG_WEIGHT_WIDTH - 1
                    downto
                    lane * CFG_WEIGHT_WIDTH
                ) := (others => '1');
            end if;
        end loop;

        return mask;
    end function final_coeff_word_mask;

    constant C_FINAL_COEFF_WORD_MASK :
        std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0) :=
            final_coeff_word_mask;

    -- Coefficients remain stored in their software-visible packed-word form.
    type coeff_word_storage_t is
        array (0 to C_K - 1, 0 to C_COEFF_WORDS - 1) of
            std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0);

    signal coeff_words_reg : coeff_word_storage_t;

    -- bias_array_t follows CFG_BIAS_WIDTH. For the default CVH1 build this
    -- is exactly signed 24-bit storage.
    signal bias_reg    : bias_array_t(0 to C_K - 1);
    signal shift_reg   : shift_array_t(0 to C_K - 1);
    signal relu_en_reg : std_logic_vector(0 to C_K - 1);

begin

    assert C_COEFF_WORDS <= C_BIAS_WORD
        report "Kernel configuration does not fit before the bias register"
        severity failure;

    assert CFG_BIAS_WIDTH <= C_BUS_WORD_WIDTH
        report "Bias width exceeds AXI-Lite register width"
        severity failure;

    assert C_BUS_WORD_WIDTH mod CFG_WEIGHT_WIDTH = 0
        report "Weight width must divide the 32-bit packed coefficient word"
        severity failure;


    -- ========================================================================
    -- Parallel datapath outputs
    -- ========================================================================

    gen_coeff_output_channel :
        for channel in 0 to C_K - 1 generate

            gen_coeff_output_word :
                for word in 0 to C_COEFF_WORDS - 1 generate

                    gen_coeff_output_lane :
                        for lane in 0 to C_COEFFS_PER_WORD - 1 generate

                            gen_valid_coeff_lane :
                                if word * C_COEFFS_PER_WORD + lane
                                        < C_N * C_N generate

                                    coeffs_out(
                                        channel * C_N * C_N
                                        + word * C_COEFFS_PER_WORD
                                        + lane
                                    ) <=
                                        coeff_words_reg(channel, word)(
                                            (lane + 1) * CFG_WEIGHT_WIDTH - 1
                                            downto
                                            lane * CFG_WEIGHT_WIDTH
                                        );

                                end generate gen_valid_coeff_lane;

                        end generate gen_coeff_output_lane;

                end generate gen_coeff_output_word;

        end generate gen_coeff_output_channel;

    bias_out    <= bias_reg;
    shift_out   <= shift_reg;
    relu_en_out <= relu_en_reg;


    -- ========================================================================
    -- Address map per channel
    -- ========================================================================
    --
    -- Channel C base = C * 0x100
    --
    --   words 0 .. C_COEFF_WORDS-1 : packed signed8 coefficients
    --   word 62 (+0xF8)             : signed bias
    --   word 63 (+0xFC)             : shift[4:0], ReLU[8]
    --
    -- AXI legality is intentionally NOT decided here. axi_lite_ctrl owns:
    --
    --   * alignment
    --   * implemented/inactive channel checking
    --   * reserved-word checking
    --   * atomic WSTRB rules
    --   * BUSY write rejection
    --   * final coefficient tail validation
    --   * canonical signed-bias validation
    --   * control reserved-bit validation
    --
    -- Therefore wr_en means the complete write has already been admitted.


    -- ========================================================================
    -- Atomic committed-write storage
    -- ========================================================================

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

                -- Static loops retain per-register enables after elaboration.
                for channel in 0 to C_K - 1 loop
                    if wr_addr(13 downto 8) =
                            std_logic_vector(to_unsigned(channel, 6)) then

                        -- ----------------------------------------------------
                        -- Packed coefficient words
                        -- ----------------------------------------------------
                        for word in 0 to C_COEFF_WORDS - 1 loop
                            if wr_addr(7 downto 2) =
                                    std_logic_vector(to_unsigned(word, 6)) then

                                if word = C_COEFF_WORDS - 1 then
                                    -- Unused tail lanes remain physically zero.
                                    -- axi_lite_ctrl separately rejects any
                                    -- nonzero value in those lanes.
                                    coeff_words_reg(channel, word) <=
                                        wr_data and C_FINAL_COEFF_WORD_MASK;
                                else
                                    coeff_words_reg(channel, word) <= wr_data;
                                end if;

                            end if;
                        end loop;

                        -- ----------------------------------------------------
                        -- Bias
                        -- ----------------------------------------------------
                        if wr_addr(7 downto 2) =
                                std_logic_vector(
                                    to_unsigned(C_BIAS_WORD, 6)
                                ) then

                            -- Store exactly the selected bias width.
                            -- For CVH1 default: bits 23:0.
                            --
                            -- Canonical sign-extension validation is performed
                            -- by axi_lite_ctrl before wr_en is asserted.
                            bias_reg(channel) <=
                                wr_data(CFG_BIAS_WIDTH - 1 downto 0);

                        -- ----------------------------------------------------
                        -- Shift / ReLU control
                        -- ----------------------------------------------------
                        elsif wr_addr(7 downto 2) =
                                std_logic_vector(
                                    to_unsigned(C_CONTROL_WORD, 6)
                                ) then

                            -- Controller has already verified that every
                            -- reserved bit is zero.
                            shift_reg(channel) <=
                                wr_data(CFG_SHIFT_WIDTH - 1 downto 0);

                            relu_en_reg(channel) <= wr_data(8);

                        end if;

                    end if;
                end loop;

            end if;
        end if;
    end process;


    -- ========================================================================
    -- Readback
    -- ========================================================================

    process(
        rd_en,
        rd_addr,
        coeff_words_reg,
        bias_reg,
        shift_reg,
        relu_en_reg
    )
        variable channel_index :
            natural range 0 to 63;

        variable word_index :
            natural range 0 to 63;

        variable coeff_mask :
            std_logic_vector(C_BUS_WORD_WIDTH - 1 downto 0);
    begin
        rd_data <= (others => '0');

        channel_index :=
            to_integer(unsigned(rd_addr(13 downto 8)));

        word_index :=
            to_integer(unsigned(rd_addr(7 downto 2)));

        if rd_en = '1' and channel_index < C_K then

            if word_index < C_COEFF_WORDS then

                coeff_mask := (others => '1');

                if word_index = C_COEFF_WORDS - 1 then
                    coeff_mask := C_FINAL_COEFF_WORD_MASK;
                end if;

                rd_data <=
                    coeff_words_reg(channel_index, word_index)
                    and coeff_mask;

            elsif word_index = C_BIAS_WORD then

                -- CVH1 exposes the selected internal signed bias as a
                -- canonical signed32 AXI value.
                rd_data <= std_logic_vector(
                    resize(
                        signed(bias_reg(channel_index)),
                        C_BUS_WORD_WIDTH
                    )
                );

            elsif word_index = C_CONTROL_WORD then

                rd_data(CFG_SHIFT_WIDTH - 1 downto 0) <=
                    shift_reg(channel_index);

                rd_data(8) <=
                    relu_en_reg(channel_index);

            end if;

        end if;
    end process;

end architecture rtl;