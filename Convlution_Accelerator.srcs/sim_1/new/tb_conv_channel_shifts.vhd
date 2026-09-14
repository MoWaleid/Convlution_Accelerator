-- ============================================================================
-- tb_conv_channel_shifts.vhd -- research-line numerical gauntlet
-- ============================================================================
-- Proves the CFGLUT5/Dadda channel against an independent 64-bit reference
-- across every encoded shift, signed-24 bias endpoints, exact half-rounding
-- boundaries, positive/negative nonzero products, saturation, and ReLU.
-- One item is kept in flight at a time so runtime parameters remain constant
-- for the complete arithmetic pipeline, matching the frame-level ABI.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_conv_channel_shifts is
end entity tb_conv_channel_shifts;

architecture sim of tb_conv_channel_shifts is
    constant C_N          : positive := 3;
    constant C_K          : positive := 1;
    constant C_TAPS       : positive := C_N * C_N;
    constant C_WEIGHT_SETS : positive := 5;
    constant C_BIAS_CASES : positive := 8;
    constant CLK_PERIOD   : time := 8 ns;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal window_in : pixel_array_t(0 to C_TAPS - 1) :=
        (others => (others => '0'));
    signal valid_in : std_logic := '0';

    signal biases : bias_array_t(0 to C_K - 1) :=
        (others => (others => '0'));
    signal shifts : shift_array_t(0 to C_K - 1) :=
        (others => (others => '0'));
    signal relus : std_logic_vector(0 to C_K - 1) := (others => '0');

    signal coeff_write_pulse : std_logic := '0';
    signal coeff_write_addr  : std_logic_vector(31 downto 0) :=
        (others => '0');
    signal coeff_write_data  : std_logic_vector(31 downto 0) :=
        (others => '0');
    signal cfg_ready   : std_logic;
    signal results_out : output_array_t(0 to C_K - 1);
    signal valid_out   : std_logic;

    function weight_for(
        set_index : natural;
        tap       : natural
    ) return integer is
    begin
        case set_index is
            when 0 =>
                return 0;
            when 1 =>
                return 127;
            when 2 =>
                return -128;
            when 3 =>
                case tap is
                    when 0 => return -128;
                    when 1 => return -127;
                    when 2 => return -1;
                    when 3 => return 0;
                    when 4 => return 1;
                    when 5 => return 2;
                    when 6 => return 63;
                    when 7 => return 126;
                    when others => return 127;
                end case;
            when others =>
                case tap is
                    when 0 => return 127;
                    when 1 => return -128;
                    when 2 => return 85;
                    when 3 => return -86;
                    when 4 => return 64;
                    when 5 => return -65;
                    when 6 => return 3;
                    when 7 => return -2;
                    when others => return -1;
                end case;
        end case;
    end function weight_for;

    function packed_word(
        set_index  : natural;
        word_index : natural
    ) return std_logic_vector is
        variable value : std_logic_vector(31 downto 0) := (others => '0');
        variable tap   : natural;
    begin
        for lane in 0 to 3 loop
            tap := word_index * 4 + lane;
            if tap < C_TAPS then
                value(8 * lane + 7 downto 8 * lane) :=
                    std_logic_vector(to_signed(weight_for(set_index, tap), 8));
            end if;
        end loop;
        return value;
    end function packed_word;

    function pixel_for(
        pattern_index : natural;
        tap           : natural
    ) return natural is
    begin
        case pattern_index mod 5 is
            when 0 => return 0;
            when 1 => return 255;
            when 2 => return (17 + tap * 29) mod 256;
            when 3 =>
                if tap mod 2 = 0 then return 255; else return 0; end if;
            when others => return (251 - tap * 23 + tap * tap * 7) mod 256;
        end case;
    end function pixel_for;

    function bias_for(
        case_index : natural;
        shift_value : natural
    ) return integer is
    begin
        case case_index is
            when 0 => return -8388608;
            when 1 => return  8388607;
            when 2 => return -32768;
            when 3 => return  32767;
            when 4 =>
                if shift_value = 0 then return 1;
                elsif shift_value <= 24 then
                    return (2 ** (shift_value - 1)) - 1;
                else return -1;
                end if;
            when 5 =>
                if shift_value = 0 then return -1;
                elsif shift_value <= 23 then
                    return 2 ** (shift_value - 1);
                elsif shift_value = 24 then return 8388607;
                else return -1;
                end if;
            when 6 =>
                if shift_value = 0 then return 0;
                elsif shift_value <= 24 then
                    return -(2 ** (shift_value - 1));
                else return -1;
                end if;
            when others =>
                if shift_value = 0 then return 0;
                elsif shift_value <= 23 then
                    return -(2 ** (shift_value - 1)) - 1;
                elsif shift_value = 24 then return -8388608;
                else return 1;
                end if;
        end case;
    end function bias_for;

    function reference_result(
        accumulator : integer;
        shift_value : natural;
        relu_enable : boolean
    ) return integer is
        variable wide    : signed(63 downto 0);
        variable limited : integer;
    begin
        wide := to_signed(accumulator, wide'length);
        if shift_value > 0 then
            wide := wide + shift_left(to_signed(1, wide'length), shift_value - 1);
        end if;
        wide := shift_right(wide, shift_value);

        if wide > to_signed(32767, wide'length) then
            limited := 32767;
        elsif wide < to_signed(-32768, wide'length) then
            limited := -32768;
        else
            limited := to_integer(wide);
        end if;

        if relu_enable and limited < 0 then
            return 0;
        end if;
        return limited;
    end function reference_result;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.conv_engine
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk               => clk,
            resetn            => resetn,
            cfg_resetn        => resetn,
            ce                => '1',
            window_in         => window_in,
            valid_in          => valid_in,
            bias_all          => biases,
            shift_all         => shifts,
            relu_en_all       => relus,
            coeff_write_pulse => coeff_write_pulse,
            coeff_write_addr  => coeff_write_addr,
            coeff_write_data  => coeff_write_data,
            cfg_ready         => cfg_ready,
            results_out       => results_out,
            valid_out         => valid_out
        );

    stimulus : process
        variable accumulator : integer;
        variable actual      : integer;
        variable expected    : integer;
        variable bias_value  : integer;
        variable pixel_value : natural;
        variable pattern     : natural;
        variable cases_run   : natural := 0;
    begin
        assert CFG_BIAS_WIDTH = 24
            report "Numerical gauntlet requires the approved signed-24 bias ABI"
            severity failure;
        assert CFG_SHIFT_WIDTH = 5 and CFG_OUTPUT_WIDTH = 16
            report "Numerical gauntlet requires the CVH1 shift/output ABI"
            severity failure;

        resetn <= '0';
        wait for 4 * CLK_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';

        for set_index in 0 to C_WEIGHT_SETS - 1 loop
            for word_index in 0 to 2 loop
                wait until falling_edge(clk);
                coeff_write_addr <= std_logic_vector(
                    to_unsigned(word_index * 4, 32)
                );
                coeff_write_data <= packed_word(set_index, word_index);
                coeff_write_pulse <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                coeff_write_pulse <= '0';
                wait until cfg_ready = '1';
            end loop;

            for shift_value in 0 to 31 loop
                for relu_mode in 0 to 1 loop
                    for bias_case in 0 to C_BIAS_CASES - 1 loop
                        bias_value := bias_for(bias_case, shift_value);
                        pattern := (set_index + shift_value + bias_case + relu_mode) mod 5;
                        accumulator := bias_value;

                        wait until falling_edge(clk);
                        for tap in 0 to C_TAPS - 1 loop
                            pixel_value := pixel_for(pattern, tap);
                            window_in(tap) <= std_logic_vector(
                                to_unsigned(pixel_value, CFG_PIXEL_WIDTH)
                            );
                            accumulator := accumulator
                                + pixel_value * weight_for(set_index, tap);
                        end loop;

                        biases(0) <= std_logic_vector(
                            to_signed(bias_value, CFG_BIAS_WIDTH)
                        );
                        shifts(0) <= std_logic_vector(
                            to_unsigned(shift_value, CFG_SHIFT_WIDTH)
                        );
                        if relu_mode = 1 then
                            relus(0) <= '1';
                        else
                            relus(0) <= '0';
                        end if;

                        expected := reference_result(
                            accumulator,
                            shift_value,
                            relu_mode = 1
                        );
                        valid_in <= '1';
                        wait until rising_edge(clk);
                        wait until falling_edge(clk);
                        valid_in <= '0';

                        loop
                            wait until falling_edge(clk);
                            exit when valid_out = '1';
                        end loop;

                        actual := to_integer(signed(results_out(0)));
                        assert actual = expected
                            report
                                "Numerical mismatch set=" & integer'image(set_index)
                                & " shift=" & integer'image(shift_value)
                                & " relu=" & integer'image(relu_mode)
                                & " bias_case=" & integer'image(bias_case)
                                & " acc=" & integer'image(accumulator)
                                & " actual=" & integer'image(actual)
                                & " expected=" & integer'image(expected)
                            severity failure;
                        cases_run := cases_run + 1;
                    end loop;
                end loop;
            end loop;
        end loop;

        assert cases_run = C_WEIGHT_SETS * 32 * 2 * C_BIAS_CASES
            report "Numerical gauntlet case-count mismatch"
            severity failure;

        report
            "NUMERICAL_GAUNTLET_PASS sets=" & integer'image(C_WEIGHT_SETS)
            & " shifts=32 bias_cases=" & integer'image(C_BIAS_CASES)
            & " relu_modes=2 outputs=" & integer'image(cases_run);
        stop(0);
        wait;
    end process stimulus;

    watchdog : process
    begin
        wait for 500 us;
        assert false report "Numerical gauntlet timeout" severity failure;
    end process watchdog;
end architecture sim;
