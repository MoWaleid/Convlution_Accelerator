-- ============================================================================
-- tb_conv_datapath_stall.vhd
-- Verifies that one global ce freezes the complete streamed convolution path.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_conv_datapath_stall is
end entity tb_conv_datapath_stall;

architecture sim of tb_conv_datapath_stall is
    constant C_N                : integer := 3;
    constant C_IMAGE_WIDTH      : integer := 5;
    constant C_IMAGE_HEIGHT     : integer := 5;
    constant C_K               : integer := 1;
    constant C_WINDOW_PIXELS   : integer := C_N * C_N;
    constant C_EXPECTED_OUTPUTS : integer := 9;
    constant CLK_PERIOD        : time := 10 ns;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal pixel_baseline : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_baseline : std_logic := '0';
    signal window_baseline : pixel_array_t(0 to C_WINDOW_PIXELS - 1);
    signal window_valid_baseline : std_logic;
    signal result_baseline : output_array_t(0 to C_K - 1);
    signal result_valid_baseline : std_logic;

    signal ce_stalled    : std_logic := '1';
    signal pixel_stalled : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_stalled : std_logic := '0';
    signal window_stalled : pixel_array_t(0 to C_WINDOW_PIXELS - 1);
    signal window_valid_stalled : std_logic;
    signal result_stalled : output_array_t(0 to C_K - 1);
    signal result_valid_stalled : std_logic;

    signal coeffs : coeff_array_t(0 to C_WINDOW_PIXELS - 1) :=
        (4 => x"01", others => x"00");
    signal biases : bias_array_t(0 to C_K - 1) := (others => (others => '0'));
    signal shifts : shift_array_t(0 to C_K - 1) := (others => (others => '0'));
    signal relus  : std_logic_vector(0 to C_K - 1) := (others => '0');

    type result_mem_t is array (0 to C_EXPECTED_OUTPUTS - 1) of std_logic_vector(15 downto 0);
    constant EXPECTED_RESULTS : result_mem_t :=
        (x"0007", x"0008", x"0009", x"000C", x"000D", x"000E", x"0011", x"0012", x"0013");
    signal baseline_results : result_mem_t := (others => (others => '0'));
    signal baseline_done : std_logic := '0';
    signal stalled_done  : std_logic := '0';

begin
    clk <= not clk after CLK_PERIOD / 2;

    baseline_window_generator : entity work.window_generator
        generic map (
            C_N            => C_N,
            C_IMAGE_WIDTH  => C_IMAGE_WIDTH,
            C_IMAGE_HEIGHT => C_IMAGE_HEIGHT
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            ce         => '1',
            pixel_in   => pixel_baseline,
            valid_in   => valid_baseline,
            window_out => window_baseline,
            valid_out  => window_valid_baseline
        );

    baseline_conv_engine : entity work.conv_engine
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            ce          => '1',
            window_in   => window_baseline,
            valid_in    => window_valid_baseline,
            coeffs_all  => coeffs,
            bias_all    => biases,
            shift_all   => shifts,
            relu_en_all => relus,
            results_out => result_baseline,
            valid_out   => result_valid_baseline
        );

    stalled_window_generator : entity work.window_generator
        generic map (
            C_N            => C_N,
            C_IMAGE_WIDTH  => C_IMAGE_WIDTH,
            C_IMAGE_HEIGHT => C_IMAGE_HEIGHT
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            ce         => ce_stalled,
            pixel_in   => pixel_stalled,
            valid_in   => valid_stalled,
            window_out => window_stalled,
            valid_out  => window_valid_stalled
        );

    stalled_conv_engine : entity work.conv_engine
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            ce          => ce_stalled,
            window_in   => window_stalled,
            valid_in    => window_valid_stalled,
            coeffs_all  => coeffs,
            bias_all    => biases,
            shift_all   => shifts,
            relu_en_all => relus,
            results_out => result_stalled,
            valid_out   => result_valid_stalled
        );

    reset_proc : process
    begin
        resetn <= '0';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        resetn <= '1';
        wait;
    end process reset_proc;

    baseline_driver : process
    begin
        wait until resetn = '1';
        for pixel_value in 1 to C_IMAGE_WIDTH * C_IMAGE_HEIGHT loop
            wait until falling_edge(clk);
            pixel_baseline <= std_logic_vector(to_unsigned(pixel_value, pixel_baseline'length));
            valid_baseline <= '1';
            wait until rising_edge(clk);
        end loop;
        wait until falling_edge(clk);
        pixel_baseline <= (others => '0');
        valid_baseline <= '0';
        wait;
    end process baseline_driver;

    baseline_monitor : process
        variable output_count : integer := 0;
    begin
        wait until resetn = '1';
        loop
            wait until falling_edge(clk);
            if result_valid_baseline = '1' then
                assert output_count < C_EXPECTED_OUTPUTS
                    report "Baseline produced more than nine outputs" severity failure;
                assert result_baseline(0) = EXPECTED_RESULTS(output_count)
                    report "Continuously enabled reference result mismatch at output " &
                           integer'image(output_count) severity failure;
                baseline_results(output_count) <= result_baseline(0);
                output_count := output_count + 1;
                if output_count = C_EXPECTED_OUTPUTS then
                    baseline_done <= '1';
                    exit;
                end if;
            end if;
        end loop;
        assert output_count = C_EXPECTED_OUTPUTS
            report "Baseline did not produce the expected nine outputs" severity failure;
        wait;
    end process baseline_monitor;

    stalled_driver : process
        procedure freeze_for(constant cycles : positive; constant name : string) is
            variable window_snapshot : pixel_array_t(0 to C_WINDOW_PIXELS - 1);
            variable valid_snapshot  : std_logic;
            variable result_snapshot : std_logic_vector(15 downto 0);
            variable result_valid_snapshot : std_logic;
        begin
            window_snapshot := window_stalled;
            valid_snapshot := window_valid_stalled;
            result_snapshot := result_stalled(0);
            result_valid_snapshot := result_valid_stalled;
            ce_stalled <= '0';
            pixel_stalled <= x"FF";
            valid_stalled <= '1';

            for cycle in 1 to cycles loop
                wait until falling_edge(clk);
                assert window_stalled = window_snapshot
                    report name & ": sliding-window state changed while ce=0" severity failure;
                assert window_valid_stalled = valid_snapshot
                    report name & ": window valid changed while ce=0" severity failure;
                assert result_stalled(0) = result_snapshot
                    report name & ": result data changed while ce=0" severity failure;
                assert result_valid_stalled = result_valid_snapshot
                    report name & ": result valid changed while ce=0" severity failure;
            end loop;
            ce_stalled <= '1';
        end procedure freeze_for;
    begin
        wait until baseline_done = '1';

        for pixel_value in 1 to C_IMAGE_WIDTH * C_IMAGE_HEIGHT loop
            wait until falling_edge(clk);
            if pixel_value = 3 then
                freeze_for(3, "initial window fill");
            elsif pixel_value = 6 then
                freeze_for(2, "row-boundary entry");
            elsif pixel_value = 13 then
                freeze_for(2, "first valid window");
            elsif pixel_value = 15 then
                freeze_for(3, "arithmetic pipeline");
            elsif pixel_value = 16 then
                freeze_for(2, "row-boundary exit");
            end if;
            pixel_stalled <= std_logic_vector(to_unsigned(pixel_value, pixel_stalled'length));
            valid_stalled <= '1';
            wait until rising_edge(clk);
        end loop;

        -- Wait until an output is visible, then hold that output valid for
        -- several cycles. Deassert input valid before resuming so no pixel is replayed.
        wait until falling_edge(clk);
        while result_valid_stalled /= '1' loop
            wait until falling_edge(clk);
        end loop;
        freeze_for(3, "valid output hold");
        pixel_stalled <= (others => '0');
        valid_stalled <= '0';
        wait;
    end process stalled_driver;

    stalled_monitor : process
        variable output_count : integer := 0;
    begin
        wait until resetn = '1';
        wait until baseline_done = '1';
        loop
            wait until falling_edge(clk);
            if ce_stalled = '1' and result_valid_stalled = '1' then
                assert output_count < C_EXPECTED_OUTPUTS
                    report "Stalled run produced more than nine outputs" severity failure;
                assert result_stalled(0) = baseline_results(output_count)
                    report "Stalled result differs from ce=1 reference at output " &
                           integer'image(output_count) severity failure;
                output_count := output_count + 1;
                if output_count = C_EXPECTED_OUTPUTS then
                    stalled_done <= '1';
                    exit;
                end if;
            end if;
        end loop;
        assert output_count = C_EXPECTED_OUTPUTS
            report "Stalled run did not produce the expected nine outputs" severity failure;
        wait;
    end process stalled_monitor;

    finish_proc : process
    begin
        wait until baseline_done = '1';
        wait until stalled_done = '1';
        report "--- Datapath stall regression completed successfully ---";
        stop(0);
        wait;
    end process finish_proc;

    timeout_proc : process
    begin
        wait for 20 us;
        assert false report "Datapath stall regression timed out" severity failure;
        wait;
    end process timeout_proc;
end architecture sim;