-- ============================================================================
-- tb_cfglut5_exact.vhd -- Exactness and runtime reload regression
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_cfglut5_exact is
end entity tb_cfglut5_exact;

architecture sim of tb_cfglut5_exact is
    constant C_N       : positive := 3;
    constant C_K       : positive := 1;
    constant C_TAPS    : positive := C_N * C_N;
    constant C_SAMPLES : positive := 128;
    constant CLK_PERIOD : time := 10 ns;

    constant C_WEIGHTS_A : coeff_array_t(0 to C_TAPS - 1) := (
        x"80", x"FF", x"00", x"01", x"02",
        x"07", x"10", x"40", x"7F"
    );

    constant C_WEIGHTS_B : coeff_array_t(0 to C_TAPS - 1) := (
        x"7F", x"81", x"55", x"AB", x"20",
        x"E0", x"03", x"FD", x"01"
    );

    type expected_array_t is array (0 to C_SAMPLES - 1) of integer;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal ce     : std_logic := '1';

    signal window_in : pixel_array_t(0 to C_TAPS - 1) :=
        (others => (others => '0'));
    signal valid_in : std_logic := '0';

    signal biases : bias_array_t(0 to C_K - 1) :=
        (others => std_logic_vector(to_signed(1234, CFG_BIAS_WIDTH)));
    signal shifts : shift_array_t(0 to C_K - 1) :=
        (others => std_logic_vector(to_unsigned(3, CFG_SHIFT_WIDTH)));
    signal relus : std_logic_vector(0 to C_K - 1) := (others => '0');

    signal coeff_write_pulse : std_logic := '0';
    signal coeff_write_addr  : std_logic_vector(31 downto 0) :=
        (others => '0');
    signal coeff_write_data  : std_logic_vector(31 downto 0) :=
        (others => '0');
    signal cfg_ready         : std_logic;
    signal results_out       : output_array_t(0 to C_K - 1);
    signal valid_out         : std_logic;

    signal expected_values : expected_array_t := (others => 0);
    signal expected_count   : natural range 0 to C_SAMPLES := 0;
    signal observed_count   : natural range 0 to C_SAMPLES := 0;

    function rounded_saturated(
        accumulator : integer;
        shift_value : natural
    ) return integer is
        variable rounded_value : integer;
        variable divisor       : positive;
        variable shifted_value : integer;
    begin
        if shift_value = 0 then
            shifted_value := accumulator;
        else
            divisor := 2 ** shift_value;
            rounded_value := accumulator + divisor / 2;

            -- Arithmetic right shift is floor division, including negatives.
            if rounded_value >= 0 then
                shifted_value := rounded_value / divisor;
            else
                shifted_value :=
                    -((-rounded_value + divisor - 1) / divisor);
            end if;
        end if;

        if shifted_value > 32767 then
            return 32767;
        elsif shifted_value < -32768 then
            return -32768;
        else
            return shifted_value;
        end if;
    end function rounded_saturated;
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
            ce                => ce,
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
        variable pixel_value : natural;
    begin
        resetn <= '0';
        wait for 4 * CLK_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';

        -- Program the three packed words exactly as AXI software does.
        for word_index in 0 to 2 loop
            wait until falling_edge(clk);
            coeff_write_addr <= std_logic_vector(to_unsigned(4 * word_index, 32));
            case word_index is
                when 0 => coeff_write_data <= x"0100FF80";
                when 1 => coeff_write_data <= x"40100702";
                when others => coeff_write_data <= x"0000007F";
            end case;
            coeff_write_pulse <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            coeff_write_pulse <= '0';
            wait until cfg_ready = '1';
        end loop;

        for sample in 0 to 63 loop
            wait until falling_edge(clk);
            accumulator := 1234;
            for tap in 0 to C_TAPS - 1 loop
                pixel_value := (sample * 37 + tap * 29 + tap * sample) mod 256;
                window_in(tap) <=
                    std_logic_vector(to_unsigned(pixel_value, 8));
                accumulator := accumulator
                    + pixel_value * to_integer(signed(C_WEIGHTS_A(tap)));
            end loop;
            expected_values(sample) <= rounded_saturated(accumulator, 3);
            expected_count <= sample + 1;
            valid_in <= '1';
            wait until rising_edge(clk);
        end loop;

        wait until falling_edge(clk);
        valid_in <= '0';
        wait until observed_count = 64;

        -- Reload all three packed words and prove that the same physical LUTs
        -- receive the new exact functions.
        for word_index in 0 to 2 loop
            wait until falling_edge(clk);
            coeff_write_addr <= std_logic_vector(to_unsigned(4 * word_index, 32));
            case word_index is
                when 0 => coeff_write_data <= x"AB55817F";
                when 1 => coeff_write_data <= x"FD03E020";
                when others => coeff_write_data <= x"00000001";
            end case;
            coeff_write_pulse <= '1';
            wait until rising_edge(clk);
            wait until falling_edge(clk);
            coeff_write_pulse <= '0';
            wait until cfg_ready = '1';
        end loop;

        biases(0) <= std_logic_vector(to_signed(-777, CFG_BIAS_WIDTH));
        shifts(0) <= std_logic_vector(to_unsigned(0, CFG_SHIFT_WIDTH));

        for sample in 64 to C_SAMPLES - 1 loop
            wait until falling_edge(clk);
            accumulator := -777;
            for tap in 0 to C_TAPS - 1 loop
                pixel_value :=
                    (sample * 19 + tap * 43 + 255 - tap * sample) mod 256;
                window_in(tap) <=
                    std_logic_vector(to_unsigned(pixel_value, 8));
                accumulator := accumulator
                    + pixel_value * to_integer(signed(C_WEIGHTS_B(tap)));
            end loop;
            expected_values(sample) <= rounded_saturated(accumulator, 0);
            expected_count <= sample + 1;
            valid_in <= '1';
            wait until rising_edge(clk);
        end loop;

        wait until falling_edge(clk);
        valid_in <= '0';
        wait until observed_count = C_SAMPLES;

        report "Exact CFGLUT5 KCM + fused compressor regression passed";
        stop(0);
        wait;
    end process stimulus;

    scoreboard : process(clk)
        variable actual : integer;
    begin
        if falling_edge(clk) then
            if valid_out = '1' then
                assert observed_count < expected_count
                    report "Output arrived before its reference value"
                    severity failure;

                actual := to_integer(signed(results_out(0)));
                assert actual = expected_values(observed_count)
                    report
                        "Exactness mismatch at sample "
                        & integer'image(observed_count)
                        & ": actual=" & integer'image(actual)
                        & " expected="
                        & integer'image(expected_values(observed_count))
                    severity failure;

                observed_count <= observed_count + 1;
            end if;
        end if;
    end process scoreboard;

    timeout : process
    begin
        wait for 20 us;
        assert false report "CFGLUT5 exactness regression timed out"
            severity failure;
        wait;
    end process timeout;
end architecture sim;
