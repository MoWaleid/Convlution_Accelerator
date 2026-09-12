-- ============================================================================
-- tb_cfglut5_k16_smoke.vhd -- 16-channel configuration/decode smoke test
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_cfglut5_k16_smoke is
end entity tb_cfglut5_k16_smoke;

architecture sim of tb_cfglut5_k16_smoke is
    constant C_N        : positive := 3;
    constant C_K        : positive := 16;
    constant C_TAPS     : positive := C_N * C_N;
    constant C_SAMPLES  : positive := 8;
    constant CLK_PERIOD : time := 10 ns;

    type expected_matrix_t is array
        (0 to C_SAMPLES - 1, 0 to C_K - 1) of integer;

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

    signal expected_values : expected_matrix_t := (others => (others => 0));
    signal expected_count  : natural range 0 to C_SAMPLES := 0;
    signal observed_count  : natural range 0 to C_SAMPLES := 0;

    function weight_for(channel : natural; tap : natural) return integer is
    begin
        case tap is
            when 0 =>
                if channel = 0 then
                    return -128;
                elsif channel = C_K - 1 then
                    return 127;
                else
                    return integer(channel) - 8;
                end if;
            when 1 => return 127 - integer(channel);
            when 2 => return -1;
            when 3 => return 2;
            when 4 => return 0;
            when 5 => return -3;
            when 6 => return 4;
            when 7 => return -5;
            when others => return integer(channel);
        end case;
    end function weight_for;

    function packed_word(
        channel    : natural;
        word_index : natural
    ) return std_logic_vector is
        variable value : std_logic_vector(31 downto 0) := (others => '0');
        variable tap   : natural;
    begin
        for lane in 0 to 3 loop
            tap := word_index * 4 + lane;
            if tap < C_TAPS then
                value(8 * lane + 7 downto 8 * lane) :=
                    std_logic_vector(to_signed(weight_for(channel, tap), 8));
            end if;
        end loop;
        return value;
    end function packed_word;

    function rounded_saturated_relu(
        accumulator : integer;
        shift_value : natural;
        relu_enable : boolean
    ) return integer is
        variable divisor : positive;
        variable rounded : integer;
        variable shifted : integer;
        variable limited : integer;
    begin
        if shift_value = 0 then
            shifted := accumulator;
        else
            divisor := 2 ** shift_value;
            rounded := accumulator + divisor / 2;
            if rounded >= 0 then
                shifted := rounded / divisor;
            else
                shifted := -((-rounded + divisor - 1) / divisor);
            end if;
        end if;

        if shifted > 32767 then
            limited := 32767;
        elsif shifted < -32768 then
            limited := -32768;
        else
            limited := shifted;
        end if;

        if relu_enable and limited < 0 then
            return 0;
        end if;
        return limited;
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
        variable pixel_value : natural;
        variable shift_value : natural;
    begin
        resetn <= '0';
        wait for 4 * CLK_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';

        for channel in 0 to C_K - 1 loop
            biases(channel) <=
                std_logic_vector(to_signed(channel * 23 - 170, CFG_BIAS_WIDTH));
            shifts(channel) <=
                std_logic_vector(to_unsigned(channel mod 4, CFG_SHIFT_WIDTH));
            if channel mod 2 = 0 then
                relus(channel) <= '1';
            else
                relus(channel) <= '0';
            end if;

            for word_index in 0 to 2 loop
                wait until falling_edge(clk);
                coeff_write_addr <= std_logic_vector(
                    to_unsigned(channel * 256 + word_index * 4, 32)
                );
                coeff_write_data <= packed_word(channel, word_index);
                coeff_write_pulse <= '1';
                wait until rising_edge(clk);
                wait until falling_edge(clk);
                coeff_write_pulse <= '0';
                wait until cfg_ready = '1';
            end loop;
        end loop;

        for sample in 0 to C_SAMPLES - 1 loop
            wait until falling_edge(clk);

            for tap in 0 to C_TAPS - 1 loop
                pixel_value := (sample * 61 + tap * 37 + sample * tap * 3) mod 256;
                window_in(tap) <= std_logic_vector(to_unsigned(pixel_value, 8));
            end loop;

            for channel in 0 to C_K - 1 loop
                accumulator := channel * 23 - 170;
                for tap in 0 to C_TAPS - 1 loop
                    pixel_value :=
                        (sample * 61 + tap * 37 + sample * tap * 3) mod 256;
                    accumulator := accumulator
                        + pixel_value * weight_for(channel, tap);
                end loop;
                shift_value := channel mod 4;
                expected_values(sample, channel) <=
                    rounded_saturated_relu(
                        accumulator,
                        shift_value,
                        channel mod 2 = 0
                    );
            end loop;

            expected_count <= sample + 1;
            valid_in <= '1';
            wait until rising_edge(clk);
        end loop;

        wait until falling_edge(clk);
        valid_in <= '0';
        wait until observed_count = C_SAMPLES;

        report "Exact CFGLUT5 K=16 channel/configuration smoke test passed";
        stop(0);
        wait;
    end process stimulus;

    scoreboard : process(clk)
        variable actual : integer;
    begin
        if falling_edge(clk) then
            if valid_out = '1' then
                assert observed_count < expected_count
                    report "K16 output arrived before its reference"
                    severity failure;

                for channel in 0 to C_K - 1 loop
                    actual := to_integer(signed(results_out(channel)));
                    assert actual = expected_values(observed_count, channel)
                        report
                            "K16 mismatch sample="
                            & integer'image(observed_count)
                            & " channel=" & integer'image(channel)
                            & " actual=" & integer'image(actual)
                            & " expected="
                            & integer'image(expected_values(observed_count, channel))
                        severity failure;
                end loop;

                observed_count <= observed_count + 1;
            end if;
        end if;
    end process scoreboard;
end architecture sim;
