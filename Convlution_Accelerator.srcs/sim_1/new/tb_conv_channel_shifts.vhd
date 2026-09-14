-- ============================================================================
-- tb_conv_channel_shifts.vhd — R14-01 simulation confirmation (M10 Gate 1 D4)
-- ============================================================================
-- Drives the baseline conv_channel S4 post-processing with the minimal legal
-- R14-01 counterexamples and compares against the golden reference
-- (round_half_up on unbounded arithmetic, computed by hand for zero windows):
--
--   reference(acc, s) = (acc + 2^(s-1)) >> s   for s > 0, else acc
--   reference(acc, 0) = acc                     (then saturate int16, ReLU)
--
-- Cases (window = all-zero pixels, all-zero coefficients):
--   c0: acc =  0, shift  8 -> reference  0   (in-range sanity, must PASS)
--   c1: acc =  0, shift 25 -> reference  0   (R14-01: RTL wraps the rounding
--       constant negative -> -1; the shipped zero-input counterexample)
--   c2: acc = -1, shift 26 -> reference  0   (R14-01: constant shifted out,
--       no round-up; RTL arithmetic-shifts -1 -> -1)
--   c3: acc = -1, shift 31 -> reference  0   (same class at the 5-bit top)
--
-- EXPECTED OUTCOME ON THE BASELINE: c1/c2/c3 MISMATCH (defect CONFIRMED by
-- simulation); c0 OK. A mismatch here is the documented R14-01 defect, not a
-- broken testbench. The final report line states the verdict explicitly.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_conv_channel_shifts is
end entity tb_conv_channel_shifts;

architecture sim of tb_conv_channel_shifts is
    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    signal ce         : std_logic := '1';
    signal window_in  : pixel_array_t(0 to 8)  := (others => (others => '0'));
    signal coeffs_in  : coeff_array_t(0 to 8)  := (others => (others => '0'));
    signal bias_in    : std_logic_vector(CFG_BIAS_WIDTH - 1 downto 0) := (others => '0');
    signal shift_in   : std_logic_vector(4 downto 0) := (others => '0');
    signal relu_en_in : std_logic := '0';
    signal valid_in   : std_logic := '0';
    signal result_out : std_logic_vector(CFG_OUTPUT_WIDTH - 1 downto 0);
    signal valid_out  : std_logic;
    signal done       : boolean := false;

    type case_t is record
        bias   : integer;
        shift  : natural;
        expect : integer;  -- golden reference value
    end record;
    type cases_t is array (natural range <>) of case_t;
    constant CASES : cases_t := (
        0 => (bias =>  0, shift =>  8, expect => 0),
        1 => (bias =>  0, shift => 25, expect => 0),
        2 => (bias => -1, shift => 26, expect => 0),
        3 => (bias => -1, shift => 31, expect => 0)
    );
begin

    clk <= not clk after 5 ns when not done else '0';

    dut : entity work.conv_channel
        generic map (C_N => 3)
        port map (
            clk        => clk,
            resetn     => resetn,
            ce         => ce,
            window_in  => window_in,
            coeffs_in  => coeffs_in,
            bias_in    => bias_in,
            shift_in   => shift_in,
            relu_en_in => relu_en_in,
            valid_in   => valid_in,
            result_out => result_out,
            valid_out  => valid_out);

    stim : process
        variable failures : integer := 0;
        variable got      : integer;
    begin
        resetn <= '0';
        for i in 1 to 4 loop
            wait until rising_edge(clk);
        end loop;
        resetn <= '1';
        wait until rising_edge(clk);

        for c in CASES'range loop
            bias_in  <= std_logic_vector(to_signed(CASES(c).bias, bias_in'length));
            shift_in <= std_logic_vector(to_unsigned(CASES(c).shift, 5));
            valid_in <= '1';
            wait until rising_edge(clk);
            valid_in <= '0';
            loop
                wait until rising_edge(clk);
                exit when valid_out = '1';
            end loop;
            got := to_integer(signed(result_out));
            if got /= CASES(c).expect then
                report "case " & integer'image(c) & " (bias " &
                       integer'image(CASES(c).bias) & ", shift " &
                       integer'image(CASES(c).shift) & "): MISMATCH got " &
                       integer'image(got) & ", reference " &
                       integer'image(CASES(c).expect) severity error;
                failures := failures + 1;
            else
                report "case " & integer'image(c) & " (bias " &
                       integer'image(CASES(c).bias) & ", shift " &
                       integer'image(CASES(c).shift) & "): OK (" &
                       integer'image(got) & ")" severity note;
            end if;
            wait until rising_edge(clk);
        end loop;

        if failures > 0 then
            report "TB_R14_01_SIM: DEFECT CONFIRMED BY SIMULATION - baseline " &
                   "conv_channel deviates from the golden reference in " &
                   integer'image(failures) & " of " & integer'image(CASES'length) &
                   " large-shift cases (R14-01 as documented)" severity error;
        else
            report "TB_R14_01_SIM: baseline matches the reference in all cases - " &
                   "R14-01 NOT reproduced (unexpected; investigate before release)" severity warning;
        end if;
        done <= true;
        wait;
    end process;

end architecture sim;
