-- ============================================================================
-- conv_channel.vhd — Single-Channel 4-Stage Pipelined Convolution Unit
-- ============================================================================
-- Computes one output feature-map pixel per clock (once pipeline is full):
--   result = ReLU( saturate_int16( round_half_up( Σ(pixel×weight) + bias, shift )))
--
-- Pipeline stages (4 clocks total latency):
--   S1  MULTIPLY     : N² unsigned×signed multiplications → N² products
--   S2  ADD-TREE L1  : Reduce N² products → N partial sums (groups of N)
--   S3  ADD-TREE L2  : Reduce N partial sums → 1, add 32-bit bias
--   S4  POST-PROCESS : Round-half-up, saturate to int16, ReLU
--
-- The arithmetic matches golden_conv.py bit-for-bit.
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

        -- Pixel window (from window_generator, shared across channels)
        window_in  : in  pixel_array_t(0 to C_N * C_N - 1);

        -- Per-channel parameters (from register file, static during streaming)
        coeffs_in  : in  coeff_array_t(0 to C_N * C_N - 1);
        bias_in    : in  std_logic_vector(CFG_BIAS_WIDTH - 1 downto 0);
        shift_in   : in  std_logic_vector(4 downto 0);
        relu_en_in : in  std_logic;

        -- Handshake
        valid_in   : in  std_logic;
        result_out : out std_logic_vector(CFG_OUTPUT_WIDTH - 1 downto 0);
        valid_out  : out std_logic
    );
end entity conv_channel;

architecture rtl of conv_channel is

    -- ========================================================================
    -- Local width constants (derived from global config)
    -- ========================================================================
    constant C_PROD_W : integer := CFG_PRODUCT_WIDTH;      -- 17 for N=3
    constant C_PSUM_W : integer := CFG_PSUM_WIDTH;          -- 19 for N=3
    constant C_FULL_W : integer := CFG_FULL_ACCUM_WIDTH;    -- 33 for N=3
    constant C_OUT_W  : integer := CFG_OUTPUT_WIDTH;        -- 16

    -- ========================================================================
    -- Pipeline register types
    -- ========================================================================
    type product_array_t is array (0 to C_N * C_N - 1) of signed(C_PROD_W - 1 downto 0);
    type psum_array_t    is array (0 to C_N - 1)        of signed(C_PSUM_W - 1 downto 0);

    -- Stage 1 outputs (multiply)
    signal products_s1 : product_array_t := (others => (others => '0'));
    signal valid_s1    : std_logic := '0';

    -- Stage 2 outputs (partial sums)
    signal psum_s2  : psum_array_t := (others => (others => '0'));
    signal valid_s2 : std_logic := '0';

    -- Stage 3 outputs (full accumulator)
    signal acc_s3   : signed(C_FULL_W - 1 downto 0) := (others => '0');
    signal valid_s3 : std_logic := '0';

    -- Stage 4 outputs (final result)
    signal result_s4 : std_logic_vector(C_OUT_W - 1 downto 0) := (others => '0');
    signal valid_s4  : std_logic := '0';

    -- Synthesis directive: force LUT-based multipliers (spec decision #11)
    attribute use_dsp : string;
    attribute use_dsp of products_s1 : signal is "no";

begin

    -- ========================================================================
    -- 4-Stage Pipeline
    -- ========================================================================
    process(clk)
        -- Stage 2 temporaries
        variable psum_tmp : signed(C_PSUM_W - 1 downto 0);

        -- Stage 3 temporaries
        variable acc_tmp : signed(C_FULL_W - 1 downto 0);

        -- Stage 4 temporaries
        variable shift_val : integer range 0 to 31;
        variable rounded   : signed(C_FULL_W - 1 downto 0);
        variable shifted   : signed(C_FULL_W - 1 downto 0);
        variable saturated : signed(C_OUT_W - 1 downto 0);
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                products_s1 <= (others => (others => '0'));
                valid_s1    <= '0';
                psum_s2     <= (others => (others => '0'));
                valid_s2    <= '0';
                acc_s3      <= (others => '0');
                valid_s3    <= '0';
                result_s4   <= (others => '0');
                valid_s4    <= '0';
            elsif ce = '1' then

                -- ==============================================================
                -- Stage 1: MULTIPLY
                -- unsigned(8) pixel × signed(8) weight → signed(17) product
                -- Zero-extend pixel to signed(9), multiply by signed(8) weight.
                -- ==============================================================
                for i in 0 to C_N * C_N - 1 loop
                    products_s1(i) <= signed('0' & window_in(i))
                                    * signed(coeffs_in(i));
                end loop;
                valid_s1 <= valid_in;

                -- ==============================================================
                -- Stage 2: ADD-TREE Level 1
                -- Reduce N² products → N partial sums (groups of N).
                -- Each group sums N signed(17) values → signed(19).
                -- ==============================================================
                for g in 0 to C_N - 1 loop
                    psum_tmp := (others => '0');
                    for i in 0 to C_N - 1 loop
                        psum_tmp := psum_tmp
                                  + resize(products_s1(g * C_N + i), C_PSUM_W);
                    end loop;
                    psum_s2(g) <= psum_tmp;
                end loop;
                valid_s2 <= valid_s1;

                -- ==============================================================
                -- Stage 3: ADD-TREE Level 2 + BIAS
                -- Sum N partial sums → 1 total, then add 32-bit bias.
                -- Result: signed(33) full accumulator.
                -- ==============================================================
                acc_tmp := resize(signed(bias_in), C_FULL_W);
                for g in 0 to C_N - 1 loop
                    acc_tmp := acc_tmp + resize(psum_s2(g), C_FULL_W);
                end loop;
                acc_s3 <= acc_tmp;
                valid_s3 <= valid_s2;

                -- ==============================================================
                -- Stage 4: POST-PROCESS  (round-half-up → saturate → ReLU)
                -- Matches golden_conv.py round_half_up() and saturate_int16().
                -- ==============================================================
                shift_val := to_integer(unsigned(shift_in));

                -- Round-half-up: add 0.5 ULP then arithmetic right-shift
                if shift_val = 0 then
                    shifted := acc_s3;
                else
                    rounded := acc_s3
                             + shift_left(to_signed(1, C_FULL_W), shift_val - 1);
                    shifted := shift_right(rounded, shift_val);
                end if;

                -- Saturate to signed int16 [-32768, +32767]
                if shifted > to_signed(32767, C_FULL_W) then
                    saturated := to_signed(32767, C_OUT_W);
                elsif shifted < to_signed(-32768, C_FULL_W) then
                    saturated := to_signed(-32768, C_OUT_W);
                else
                    saturated := shifted(C_OUT_W - 1 downto 0);
                end if;

                -- ReLU: clamp negative to zero (per-channel enable)
                if relu_en_in = '1' and saturated(C_OUT_W - 1) = '1' then
                    result_s4 <= (others => '0');
                else
                    result_s4 <= std_logic_vector(saturated);
                end if;

                valid_s4 <= valid_s3;

            end if;
        end if;
    end process;

    -- ========================================================================
    -- Output assignments
    -- ========================================================================
    result_out <= result_s4;
    valid_out  <= valid_s4;

end architecture rtl;
