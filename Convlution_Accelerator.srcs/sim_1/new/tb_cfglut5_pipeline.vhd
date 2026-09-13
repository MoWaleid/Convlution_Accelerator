-- Four-stage 100 MHz engine CE/valid alignment and all legal shifts.
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.env.all;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_cfglut5_pipeline is end;
architecture sim of tb_cfglut5_pipeline is
    constant PERIOD : time := 10 ns;
    signal clk : std_logic := '0';
    signal resetn : std_logic := '0';
    signal ce : std_logic := '1';
    signal vin, vout, cfg_pulse, cfg_ready : std_logic := '0';
    signal cfg_addr : std_logic_vector(31 downto 0) := (others => '0');
    signal pixels : pixel_array_t(0 to 8) := (others => (others => '0'));
    signal biases : bias_array_t(0 to 0) := (others => (others => '0'));
    signal shifts : shift_array_t(0 to 0) := (others => (others => '0'));
    signal relus : std_logic_vector(0 to 0) := (others => '0');
    signal result : output_array_t(0 to 0);
    signal expected : integer := 0;
    signal received : natural := 0;
    type int_array is array(natural range <>) of integer;
    constant BIASES_TO_TEST : int_array :=
        (-8388608, -8388607, -65537, -32769, -32768, -32767, -3, -1,
          0, 1, 3, 32766, 32767, 32768, 65535, 8388607);

    function reference(b, sh, relu : integer) return integer is
        variable wide : signed(63 downto 0);
        variable limited : integer;
    begin
        wide := to_signed(b, 64);
        if sh > 0 then
            wide := wide + shift_left(to_signed(1, 64), sh - 1);
        end if;
        wide := shift_right(wide, sh);
        if wide > to_signed(32767, 64) then limited := 32767;
        elsif wide < to_signed(-32768, 64) then limited := -32768;
        else limited := to_integer(wide);
        end if;
        if relu = 1 and limited < 0 then return 0; end if;
        return limited;
    end;
begin
    clk <= not clk after PERIOD / 2;
    dut : entity work.conv_engine
        generic map(C_K => 1, C_N => 3)
        port map(clk => clk, resetn => resetn, cfg_resetn => resetn,
            ce => ce, window_in => pixels, valid_in => vin,
            bias_all => biases, shift_all => shifts, relu_en_all => relus,
            coeff_write_pulse => cfg_pulse, coeff_write_addr => cfg_addr,
            coeff_write_data => x"00000000", cfg_ready => cfg_ready,
            results_out => result, valid_out => vout);

    monitor : process
        variable valids : std_logic_vector(3 downto 0) := (others => '0');
        variable last_result : std_logic_vector(CFG_OUTPUT_WIDTH-1 downto 0);
        variable old_valid : std_logic;
        variable enabled : boolean;
    begin
        wait until rising_edge(clk);
        enabled := ce = '1';
        last_result := result(0);
        old_valid := vout;
        if resetn = '0' then valids := (others => '0');
        elsif enabled then valids := valids(2 downto 0) & vin;
        end if;
        wait for 1 ns;
        assert vout = valids(3)
            report "Four-stage CE-relative valid latency mismatch" severity failure;
        if resetn = '1' and not enabled then
            assert vout = old_valid and result(0) = last_result
                report "Pipeline changed while CE was low" severity failure;
        end if;
        if vout = '1' then
            assert to_integer(signed(result(0))) = expected
                report "Postprocessing mismatch expected=" & integer'image(expected) &
                       " actual=" & integer'image(to_integer(signed(result(0)))) severity failure;
            if enabled then received <= received + 1; end if;
        end if;
    end process;

    stimulus : process
        variable sent : natural := 0;
    begin
        wait for 4 * PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';
        -- Program all 9 weights to zero: accumulator is the selected signed24
        -- bias, independently covering output clipping/rounding corner cases.
        for word in 0 to 2 loop
            wait until falling_edge(clk);
            cfg_addr <= std_logic_vector(to_unsigned(4 * word, 32));
            cfg_pulse <= '1';
            wait until falling_edge(clk);
            cfg_pulse <= '0';
            wait until cfg_ready = '1';
        end loop;
        for sh in 0 to 31 loop
            for r in 0 to 1 loop
                for b in BIASES_TO_TEST'range loop
                    wait until falling_edge(clk);
                    biases(0) <= std_logic_vector(to_signed(BIASES_TO_TEST(b), CFG_BIAS_WIDTH));
                    shifts(0) <= std_logic_vector(to_unsigned(sh, CFG_SHIFT_WIDTH));
                    if r = 1 then relus(0) <= '1'; else relus(0) <= '0'; end if;
                    expected <= reference(BIASES_TO_TEST(b), sh, r);
                    for tick in 0 to 17 loop
                        wait until falling_edge(clk);
                        if tick = 2 or tick = 3 or tick = 8 then ce <= '0';
                        else ce <= '1'; end if;
                        if tick < 7 then
                            vin <= '1';
                            if tick /= 2 and tick /= 3 then sent := sent + 1; end if;
                        else vin <= '0'; end if;
                    end loop;
                    wait until falling_edge(clk);
                    assert vout = '0' report "Pipeline did not drain" severity failure;
                    assert received = sent report "Dropped/duplicated pipeline output" severity failure;
                end loop;
            end loop;
        end loop;
        -- Flush a valid in-flight item with reset and check no stale output.
        vin <= '1';
        wait until falling_edge(clk);
        resetn <= '0';
        vin <= '0';
        wait until falling_edge(clk);
        resetn <= '1';
        for tick in 0 to 7 loop wait until falling_edge(clk); end loop;
        assert vout = '0' report "Reset left a stale pipeline result" severity failure;
        report "PIPELINE_100_PASS shifts=32 bias_cases=16 relu_modes=2 outputs=" & integer'image(received);
        stop(0);
        wait;
    end process;

    watchdog : process
    begin
        wait for 300 us;
        assert false report "Pipeline regression timeout" severity failure;
    end process;
end;
