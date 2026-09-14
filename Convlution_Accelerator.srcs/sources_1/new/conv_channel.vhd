-- ============================================================================
-- conv_channel.vhd -- Exact CFGLUT5 3x3/5x5 convolution channel
-- ============================================================================
-- The two radix-16 partial products from every tap are sent directly into a
-- column-aware Dadda bit heap.  It compresses only occupied columns and uses
-- two-output LUT6_2 primitives, avoiding the sign-extension waste of a uniform
-- width CSA tree.
--
-- Pipeline:
--   BH  CFGLUT lookup + generated Dadda compressor (one registered boundary
--       for 3x3, two for 5x5)
--   S2  two-row register
--   S3  final carry-propagate sum + bias
--   S4  arithmetic shift + discarded half-bit register
--   S5  round-half-up increment, saturation and optional ReLU
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity conv_channel is
    generic (
        C_N : integer := CFG_N
    );
    port (
        clk        : in  std_logic;
        resetn     : in  std_logic;
        ce         : in  std_logic;
        window_in  : in  pixel_array_t(0 to C_N * C_N - 1);
        cfg_ce     : in  std_logic_vector(0 to C_N * C_N - 1);
        cfg_data   : in  std_logic_vector(5 downto 0);
        bias_in    : in  std_logic_vector(CFG_BIAS_WIDTH - 1 downto 0);
        shift_in   : in  std_logic_vector(CFG_SHIFT_WIDTH - 1 downto 0);
        relu_en_in : in  std_logic;
        valid_in   : in  std_logic;
        result_out : out std_logic_vector(CFG_OUTPUT_WIDTH - 1 downto 0);
        valid_out  : out std_logic
    );
end entity conv_channel;

architecture rtl of conv_channel is
    constant C_TAPS   : positive := C_N * C_N;
    constant C_TREE_W : positive :=
        CFG_PRODUCT_WIDTH + clog2(C_N * C_N);
    constant C_FULL_W : positive :=
        max_int(C_TREE_W, CFG_BIAS_WIDTH) + 1;
    constant C_OUT_W  : positive := CFG_OUTPUT_WIDTH;

    type pp_array_t is
        array (natural range <>) of std_logic_vector(11 downto 0);
    type tree_array_t is
        array (natural range <>) of signed(C_TREE_W - 1 downto 0);

    signal pp_lo : pp_array_t(0 to C_TAPS - 1);
    signal pp_hi : pp_array_t(0 to C_TAPS - 1);
    signal pp_lo_flat : std_logic_vector(12 * C_TAPS - 1 downto 0);
    signal pp_hi_flat : std_logic_vector(12 * C_TAPS - 1 downto 0);

    signal bitheap_row_a : std_logic_vector(C_TREE_W - 1 downto 0);
    signal bitheap_row_b : std_logic_vector(C_TREE_W - 1 downto 0);
    signal bitheap_valid_s1 : std_logic;

    signal tree_s2  : tree_array_t(0 to 1) :=
        (others => (others => '0'));
    signal valid_s2 : std_logic := '0';
    signal acc_s3   : signed(C_FULL_W - 1 downto 0) :=
        (others => '0');
    signal valid_s3 : std_logic := '0';
    signal shifted_s4 : signed(C_FULL_W - 1 downto 0) := (others => '0');
    signal round_s4 : std_logic := '0';
    signal relu_s4 : std_logic := '0';
    signal valid_s4 : std_logic := '0';
    signal result_s5 : std_logic_vector(C_OUT_W - 1 downto 0) :=
        (others => '0');
    signal valid_s5  : std_logic := '0';
begin
    assert C_N = 3 or C_N = 5
        report "The exact CFGLUT5 bit heap supports only N=3 or N=5"
        severity failure;
    assert CFG_PIXEL_WIDTH = 8 and CFG_WEIGHT_WIDTH = 8
        report "cfglut5_kcm requires uint8 pixels and signed-int8 weights"
        severity failure;

    gen_kcm_taps : for tap in 0 to C_TAPS - 1 generate
    begin
        kcm_inst : entity work.cfglut5_kcm
            port map (
                clk       => clk,
                cfg_ce    => cfg_ce(tap),
                cfg_data  => cfg_data,
                pixel_in  => window_in(tap),
                pp_lo_out => pp_lo(tap),
                pp_hi_out => pp_hi(tap)
            );

        gen_flatten_bits : for bit_index in 0 to 11 generate
        begin
            pp_lo_flat(12 * tap + bit_index) <= pp_lo(tap)(bit_index);
            pp_hi_flat(12 * tap + bit_index) <= pp_hi(tap)(bit_index);
        end generate gen_flatten_bits;
    end generate gen_kcm_taps;

    gen_bitheap_3x3 : if C_N = 3 generate
    begin
        bitheap_inst : entity work.cfglut5_bitheap_3x3
            port map (
                clk        => clk,
                resetn     => resetn,
                ce         => ce,
                valid_in   => valid_in,
                pp_lo_flat => pp_lo_flat,
                pp_hi_flat => pp_hi_flat,
                row_a_out  => bitheap_row_a,
                row_b_out  => bitheap_row_b,
                valid_out  => bitheap_valid_s1
            );
    end generate gen_bitheap_3x3;

    gen_bitheap_5x5 : if C_N = 5 generate
    begin
        bitheap_inst : entity work.cfglut5_bitheap_5x5
            port map (
                clk        => clk,
                resetn     => resetn,
                ce         => ce,
                valid_in   => valid_in,
                pp_lo_flat => pp_lo_flat,
                pp_hi_flat => pp_hi_flat,
                row_a_out  => bitheap_row_a,
                row_b_out  => bitheap_row_b,
                valid_out  => bitheap_valid_s1
            );
    end generate gen_bitheap_5x5;

    pipeline_process : process(clk)
        variable acc_tmp   : signed(C_FULL_W - 1 downto 0);
        variable shift_val : integer range 0 to 31;
        variable shifted   : signed(C_FULL_W - 1 downto 0);
        variable saturated : signed(C_OUT_W - 1 downto 0);
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                tree_s2   <= (others => (others => '0'));
                valid_s2  <= '0';
                acc_s3    <= (others => '0');
                valid_s3  <= '0';
                shifted_s4 <= (others => '0');
                round_s4 <= '0';
                relu_s4 <= '0';
                valid_s4  <= '0';
                result_s5 <= (others => '0');
                valid_s5 <= '0';
            elsif ce = '1' then
                -- S2: register the two rows produced by the selected bit heap.
                tree_s2(0) <= signed(bitheap_row_a);
                tree_s2(1) <= signed(bitheap_row_b);
                valid_s2 <= bitheap_valid_s1;

                -- S3: sole carry-propagate product sum followed by bias.
                acc_tmp :=
                    resize(tree_s2(0), C_FULL_W)
                    + resize(tree_s2(1), C_FULL_W)
                    + resize(signed(bias_in), C_FULL_W);
                acc_s3 <= acc_tmp;
                valid_s3 <= valid_s2;

                -- S4: isolate the barrel shifter from the rounding carry
                -- chain and output clamp. Every new register shares CE, so
                -- backpressure holds data and its metadata together.
                shift_val := to_integer(unsigned(shift_in));
                -- Exact round-half-up, expressed as arithmetic quotient plus
                -- its discarded half bit.  This is algebraically identical to
                -- adding 2**(shift-1) before shifting, but removes the wide
                -- one-hot rounding adder ahead of the barrel shifter.
                shifted_s4 <= shift_right(acc_s3, shift_val);
                round_s4 <= '0';
                if shift_val > 0 and shift_val <= C_FULL_W then
                    round_s4 <= acc_s3(shift_val - 1);
                elsif shift_val > C_FULL_W then
                    -- For shifts beyond the accumulator width the discarded
                    -- half bit is sign extension, not an out-of-range index.
                    round_s4 <= acc_s3(C_FULL_W - 1);
                end if;
                relu_s4 <= relu_en_in;
                valid_s4 <= valid_s3;

                -- S5: unchanged exact half-up rounding and clipping.
                shifted := shifted_s4;
                if round_s4 = '1' then
                    shifted := shifted + 1;
                end if;

                -- A signed value fits in 16 bits exactly when every bit from
                -- the full-width sign down through output bit 15 is all zero
                -- (positive) or all one (negative).  Reduction comparisons
                -- avoid two full-width magnitude comparators.
                if
                    shifted(C_FULL_W - 1 downto C_OUT_W - 1) =
                    (C_FULL_W - 1 downto C_OUT_W - 1 => '0')
                then
                    saturated := shifted(C_OUT_W - 1 downto 0);
                elsif
                    shifted(C_FULL_W - 1 downto C_OUT_W - 1) =
                    (C_FULL_W - 1 downto C_OUT_W - 1 => '1')
                then
                    saturated := shifted(C_OUT_W - 1 downto 0);
                elsif shifted(C_FULL_W - 1) = '0' then
                    saturated := to_signed(32767, C_OUT_W);
                else
                    saturated := to_signed(-32768, C_OUT_W);
                end if;

                if relu_s4 = '1' and saturated(C_OUT_W - 1) = '1' then
                    result_s5 <= (others => '0');
                else
                    result_s5 <= std_logic_vector(saturated);
                end if;
                valid_s5 <= valid_s4;
            end if;
        end if;
    end process pipeline_process;

    result_out <= result_s5;
    valid_out  <= valid_s5;
end architecture rtl;
