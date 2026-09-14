-- ============================================================================
-- tb_cfglut5_exact_n5.vhd -- Exact 5x5 CFGLUT5 reload/backpressure regression
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_cfglut5_exact_n5 is
end entity tb_cfglut5_exact_n5;

architecture sim of tb_cfglut5_exact_n5 is
    constant C_N        : positive := 5;
    constant C_K        : positive := 1;
    constant C_TAPS     : positive := C_N * C_N;
    constant C_PHASE    : positive := 96;
    constant C_SAMPLES  : positive := 2 * C_PHASE;
    constant CLK_PERIOD : time := 8 ns;

    type integer_array_t is array (natural range <>) of integer;
    constant C_WEIGHTS_A : integer_array_t(0 to C_TAPS - 1) := (
        -128, -97, -64, -31, -1,
           0,   1,   2,   7, 15,
          16,  23,  31,  47, 63,
          64,  79,  95, 111, 127,
        -113, -73, -39, -17,  53
    );
    constant C_WEIGHTS_B : integer_array_t(0 to C_TAPS - 1) := (
         127,  96,  65,  34,   3,
         -28, -59, -90, -121, -7,
          11,  22,  33,  44,  55,
         -66, -77, -88, -99, -110,
         120, -127, 81, -45,  19
    );
    type expected_array_t is array (0 to C_SAMPLES - 1) of integer;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal ce     : std_logic := '1';
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
    signal expected_values : expected_array_t := (others => 0);
    signal expected_count : natural range 0 to C_SAMPLES := 0;
    signal observed_count : natural range 0 to C_SAMPLES := 0;

    function pack_word(
        weights    : integer_array_t;
        word_index : natural
    ) return std_logic_vector is
        variable packed : std_logic_vector(31 downto 0) := (others => '0');
        variable tap    : natural;
    begin
        for lane in 0 to 3 loop
            tap := 4 * word_index + lane;
            if tap <= weights'high then
                packed(8 * lane + 7 downto 8 * lane) :=
                    std_logic_vector(to_signed(weights(tap), 8));
            end if;
        end loop;
        return packed;
    end function pack_word;

    function rounded_saturated_relu(
        accumulator : integer;
        shift_value : natural;
        relu_enable : boolean
    ) return integer is
        variable wide : signed(63 downto 0);
        variable result : integer;
    begin
        wide := to_signed(accumulator, wide'length);
        if shift_value > 0 then
            wide := wide + shift_left(to_signed(1, wide'length), shift_value - 1);
        end if;
        wide := shift_right(wide, shift_value);
        if wide > to_signed(32767, wide'length) then
            result := 32767;
        elsif wide < to_signed(-32768, wide'length) then
            result := -32768;
        else
            result := to_integer(wide);
        end if;
        if relu_enable and result < 0 then
            return 0;
        end if;
        return result;
    end function rounded_saturated_relu;
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
        procedure program_weights(constant weights : in integer_array_t) is
        begin
            for word_index in 0 to (C_TAPS + 3) / 4 - 1 loop
                wait until falling_edge(clk);
                coeff_write_addr <=
                    std_logic_vector(to_unsigned(4 * word_index, 32));
                coeff_write_data <= pack_word(weights, word_index);
                coeff_write_pulse <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                coeff_write_pulse <= '0';
                wait until cfg_ready = '1';
            end loop;
        end procedure program_weights;

        procedure send_phase(
            constant first_sample : in natural;
            constant weights      : in integer_array_t;
            constant bias_value   : in integer;
            constant shift_value  : in natural;
            constant relu_enable  : in boolean
        ) is
            variable accumulator : integer;
            variable pixel_value : natural;
        begin
            biases(0) <= std_logic_vector(to_signed(bias_value, CFG_BIAS_WIDTH));
            shifts(0) <= std_logic_vector(to_unsigned(shift_value, CFG_SHIFT_WIDTH));
            if relu_enable then relus(0) <= '1'; else relus(0) <= '0'; end if;

            for local_sample in 0 to C_PHASE - 1 loop
                -- Periodic backpressure proves that both generated register
                -- boundaries and their valid state freeze together.
                if local_sample mod 11 = 4 then
                    wait until falling_edge(clk);
                    ce <= '0';
                    valid_in <= '0';
                    wait until falling_edge(clk);
                    wait until falling_edge(clk);
                    ce <= '1';
                end if;

                wait until falling_edge(clk);
                accumulator := bias_value;
                for tap in 0 to C_TAPS - 1 loop
                    pixel_value :=
                        (first_sample * 17 + local_sample * 37
                         + tap * 29 + tap * local_sample) mod 256;
                    window_in(tap) <=
                        std_logic_vector(to_unsigned(pixel_value, 8));
                    accumulator := accumulator + pixel_value * weights(tap);
                end loop;
                expected_values(first_sample + local_sample) <=
                    rounded_saturated_relu(
                        accumulator, shift_value, relu_enable
                    );
                expected_count <= first_sample + local_sample + 1;
                valid_in <= '1';
                wait until rising_edge(clk);
            end loop;
            wait until falling_edge(clk);
            valid_in <= '0';
        end procedure send_phase;
    begin
        resetn <= '0';
        wait for 4 * CLK_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';

        program_weights(C_WEIGHTS_A);
        send_phase(0, C_WEIGHTS_A, 123456, 3, false);
        wait until observed_count = C_PHASE;

        program_weights(C_WEIGHTS_B);
        send_phase(C_PHASE, C_WEIGHTS_B, -654321, 5, true);
        wait until observed_count = C_SAMPLES;

        report "Exact 5x5 CFGLUT5 reload/backpressure regression passed";
        stop(0);
        wait;
    end process stimulus;

    scoreboard : process(clk)
        variable actual : integer;
    begin
        if falling_edge(clk) and ce = '1' and valid_out = '1' then
            assert observed_count < expected_count
                report "5x5 output arrived before its reference value"
                severity failure;
            actual := to_integer(signed(results_out(0)));
            assert actual = expected_values(observed_count)
                report "5x5 mismatch at sample " & integer'image(observed_count)
                    & ": actual=" & integer'image(actual)
                    & " expected=" & integer'image(expected_values(observed_count))
                severity failure;
            observed_count <= observed_count + 1;
        end if;
    end process scoreboard;

    timeout : process
    begin
        wait for 100 us;
        assert false report "5x5 CFGLUT5 regression timed out" severity failure;
        wait;
    end process timeout;
end architecture sim;
