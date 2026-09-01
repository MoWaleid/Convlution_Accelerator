-- ============================================================================
-- tb_axi_stream_output_serializer.vhd
-- Focused AXI4-Stream output serializer regression for K=6 and K=16.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity tb_axi_stream_output_serializer is
end entity tb_axi_stream_output_serializer;

architecture sim of tb_axi_stream_output_serializer is
    constant CLK_PERIOD : time := 10 ns;

    constant C_K6 : integer := 6;
    constant C_K6_IMAGE_WIDTH  : integer := 5;
    constant C_K6_IMAGE_HEIGHT : integer := 3;
    constant C_K6_POSITIONS : integer := C_K6_IMAGE_WIDTH * C_K6_IMAGE_HEIGHT;
    constant C_K6_FULL_BEATS : integer := (C_K6 * C_K6_POSITIONS) / 4;
    constant C_K16 : integer := 16;
    constant C_K16_POSITIONS : integer := 6;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal k6_results : output_array_t(0 to C_K6 - 1) := (others => (others => '0'));
    signal k6_in_valid : std_logic := '0';
    signal k6_in_ready : std_logic;
    signal k6_tdata  : std_logic_vector(63 downto 0);
    signal k6_tkeep  : std_logic_vector(7 downto 0);
    signal k6_tvalid : std_logic;
    signal k6_tready : std_logic := '1';
    signal k6_tlast  : std_logic;
    signal k6_done   : std_logic := '0';

    signal k16_results : output_array_t(0 to C_K16 - 1) := (others => (others => '0'));
    signal k16_in_valid : std_logic := '0';
    signal k16_in_ready : std_logic;
    signal k16_tdata  : std_logic_vector(63 downto 0);
    signal k16_tkeep  : std_logic_vector(7 downto 0);
    signal k16_tvalid : std_logic;
    signal k16_tready : std_logic := '0';
    signal k16_tlast  : std_logic;
    signal k16_fill_reached : std_logic := '0';
    signal k16_input_done : std_logic := '0';
    signal k16_done : std_logic := '0';

    function make_results_k6(base_value : integer) return output_array_t is
        variable result : output_array_t(0 to C_K6 - 1);
    begin
        for channel in 0 to C_K6 - 1 loop
            result(channel) := std_logic_vector(to_signed(base_value + channel, 16));
        end loop;
        return result;
    end function make_results_k6;

    function make_results_k16(base_value : integer) return output_array_t is
        variable result : output_array_t(0 to C_K16 - 1);
    begin
        for channel in 0 to C_K16 - 1 loop
            result(channel) := std_logic_vector(to_signed(base_value + channel, 16));
        end loop;
        return result;
    end function make_results_k16;

    function scalar_count_from_keep(keep : std_logic_vector(7 downto 0)) return natural is
    begin
        case keep is
            when x"03" => return 1;
            when x"0F" => return 2;
            when x"3F" => return 3;
            when x"FF" => return 4;
            when others => return 0;
        end case;
    end function scalar_count_from_keep;
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut_k6 : entity work.axi_stream_output_serializer
        generic map (
            C_K            => C_K6,
            C_IMAGE_WIDTH  => C_K6_IMAGE_WIDTH,
            C_IMAGE_HEIGHT => C_K6_IMAGE_HEIGHT,
            C_FIFO_DEPTH   => 16
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            in_results    => k6_results,
            in_valid      => k6_in_valid,
            in_ready      => k6_in_ready,
            m_axis_tdata  => k6_tdata,
            m_axis_tkeep  => k6_tkeep,
            m_axis_tvalid => k6_tvalid,
            m_axis_tready => k6_tready,
            m_axis_tlast  => k6_tlast
        );

    dut_k16 : entity work.axi_stream_output_serializer
        generic map (
            C_K            => C_K16,
            C_IMAGE_WIDTH  => C_K16_POSITIONS,
            C_IMAGE_HEIGHT => 1,
            C_FIFO_DEPTH   => 16
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            in_results    => k16_results,
            in_valid      => k16_in_valid,
            in_ready      => k16_in_ready,
            m_axis_tdata  => k16_tdata,
            m_axis_tkeep  => k16_tkeep,
            m_axis_tvalid => k16_tvalid,
            m_axis_tready => k16_tready,
            m_axis_tlast  => k16_tlast
        );

    reset_proc : process
    begin
        resetn <= '0';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        resetn <= '1';
        wait;
    end process reset_proc;

    -- Deterministic pseudo-random downstream readiness creates output stalls.
    k6_ready_driver : process
        variable lfsr : std_logic_vector(7 downto 0) := x"A5";
        variable feedback : std_logic;
    begin
        wait until resetn = '1';
        while k6_done = '0' loop
            wait until falling_edge(clk);
            feedback := lfsr(7) xor lfsr(5) xor lfsr(4) xor lfsr(3);
            lfsr := lfsr(6 downto 0) & feedback;
            k6_tready <= lfsr(0) or lfsr(2);
        end loop;
        k6_tready <= '1';
        wait;
    end process k6_ready_driver;

    -- AXI output data, keep, and last must remain stable during every stall.
    k6_stall_monitor : process
        variable held_valid : boolean := false;
        variable held_data  : std_logic_vector(63 downto 0) := (others => '0');
        variable held_keep  : std_logic_vector(7 downto 0) := (others => '0');
        variable held_last  : std_logic := '0';
    begin
        wait until resetn = '1';
        loop
            wait until falling_edge(clk);
            if held_valid then
                assert k6_tvalid = '1' and k6_tdata = held_data and
                       k6_tkeep = held_keep and k6_tlast = held_last
                    report "K=6 AXI output changed while stalled" severity failure;
            end if;
            wait for 1 ps;
            held_valid := (k6_tvalid = '1' and k6_tready = '0');
            if held_valid then
                held_data := k6_tdata;
                held_keep := k6_tkeep;
                held_last := k6_tlast;
            end if;
            if k6_done = '1' then
                exit;
            end if;
        end loop;
        wait;
    end process k6_stall_monitor;

    -- K=6 demonstrates scalar order across spatial positions: beat 1 contains
    -- P00.ch4, P00.ch5, P01.ch0, P01.ch1. The final two-scalar beat is 0x0F.
    k6_output_monitor : process
        variable scalar_index : integer := 0;
        variable beat_index   : integer := 0;
        variable scalar_count : natural;
        variable last_count   : integer := 0;
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);
            if k6_tvalid = '1' and k6_tready = '1' then
                scalar_count := scalar_count_from_keep(k6_tkeep);
                assert scalar_count /= 0
                    report "K=6 emitted an invalid TKEEP" severity failure;
                if beat_index < C_K6_FULL_BEATS then
                    assert k6_tkeep = x"FF"
                        report "K=6 emitted a premature partial TKEEP" severity failure;
                else
                    assert k6_tkeep = x"0F"
                        report "K=6 final TKEEP must encode two scalars" severity failure;
                end if;
                for lane in 0 to scalar_count - 1 loop
                    assert k6_tdata((lane + 1) * 16 - 1 downto lane * 16) =
                           std_logic_vector(to_signed(-9 + scalar_index, 16))
                        report "K=6 scalar ordering or signed packing failure" severity failure;
                    scalar_index := scalar_index + 1;
                end loop;
                if k6_tlast = '1' then
                    last_count := last_count + 1;
                end if;
                if scalar_index = C_K6 * C_K6_POSITIONS then
                    assert k6_tlast = '1' and last_count = 1
                        report "K=6 frame must end with exactly one TLAST" severity failure;
                    assert beat_index = C_K6_FULL_BEATS
                        report "K=6 emitted an unexpected number of packed beats" severity failure;
                    k6_done <= '1';
                    exit;
                else
                    assert k6_tlast = '0'
                        report "K=6 asserted TLAST before final scalar" severity failure;
                end if;
                beat_index := beat_index + 1;
            end if;
        end loop;
        wait;
    end process k6_output_monitor;

    k6_input_driver : process
    begin
        wait until resetn = '1';
        for position in 0 to C_K6_POSITIONS - 1 loop
            wait until falling_edge(clk);
            k6_results  <= make_results_k6(-9 + position * C_K6);
            k6_in_valid <= '1';
            loop
                wait until rising_edge(clk);
                exit when k6_in_ready = '1';
            end loop;
            wait until falling_edge(clk);
            k6_in_valid <= '0';
        end loop;
        wait;
    end process k6_input_driver;

    -- K=16 source keeps the next vector valid continuously. Before the output
    -- FIFO fills, new vectors must be accepted every four formatter clocks.
    k16_input_driver : process
        variable accepted_count : integer := 0;
        variable previous_accept_time : time := 0 ns;
    begin
        wait until resetn = '1';
        wait until falling_edge(clk);
        k16_results  <= make_results_k16(-48);
        k16_in_valid <= '1';
        loop
            wait until rising_edge(clk);
            if k16_in_valid = '1' and k16_in_ready = '1' then
                if accepted_count > 0 and accepted_count < 5 then
                    assert now - previous_accept_time = 4 * CLK_PERIOD
                        report "K=16 incurred an extra vector reload bubble" severity failure;
                end if;
                previous_accept_time := now;
                accepted_count := accepted_count + 1;
                if accepted_count = 5 then
                    k16_fill_reached <= '1';
                end if;
                if accepted_count = C_K16_POSITIONS then
                    k16_in_valid <= '0';
                    k16_input_done <= '1';
                    exit;
                else
                    k16_results <= make_results_k16(-48 + accepted_count * C_K16);
                end if;
            end if;
        end loop;
        wait;
    end process k16_input_driver;

    -- Four K=16 vectors create 16 output beats. With downstream ready low,
    -- the next vector must be held by in_ready backpressure until draining.
    k16_backpressure_check : process
    begin
        wait until k16_fill_reached = '1';
        for stalled_cycle in 1 to 3 loop
            wait until rising_edge(clk);
            assert k16_in_ready = '0'
                report "K=16 in_ready did not deassert when its output FIFO filled" severity failure;
        end loop;
        wait until falling_edge(clk);
        k16_tready <= '1';
        wait;
    end process k16_backpressure_check;

    k16_output_monitor : process
        variable scalar_index : integer := 0;
        variable beat_index   : integer := 0;
        variable scalar_count : natural;
        variable last_count   : integer := 0;
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);
            if k16_tvalid = '1' and k16_tready = '1' then
                scalar_count := scalar_count_from_keep(k16_tkeep);
                assert scalar_count = 4 and k16_tkeep = x"FF"
                    report "K=16 must emit only full four-scalar words" severity failure;
                for lane in 0 to 3 loop
                    assert k16_tdata((lane + 1) * 16 - 1 downto lane * 16) =
                           std_logic_vector(to_signed(-48 + scalar_index, 16))
                        report "K=16 scalar ordering or signed packing failure" severity failure;
                    scalar_index := scalar_index + 1;
                end loop;
                if k16_tlast = '1' then
                    last_count := last_count + 1;
                end if;
                if scalar_index = C_K16 * C_K16_POSITIONS then
                    assert k16_tlast = '1' and last_count = 1
                        report "K=16 frame must end with exactly one TLAST" severity failure;
                    assert beat_index = 23
                        report "K=16 emitted an unexpected number of packed beats" severity failure;
                    k16_done <= '1';
                    exit;
                else
                    assert k16_tlast = '0'
                        report "K=16 asserted TLAST before final scalar" severity failure;
                end if;
                beat_index := beat_index + 1;
            end if;
        end loop;
        wait;
    end process k16_output_monitor;

    finish_proc : process
    begin
        wait until k6_done = '1' and k16_input_done = '1' and k16_done = '1';
        report "--- AXI4-Stream output serializer regression completed successfully ---";
        stop(0);
        wait;
    end process finish_proc;

    timeout_proc : process
    begin
        wait for 40 us;
        assert false report "AXI4-Stream output serializer regression timed out" severity failure;
        wait;
    end process timeout_proc;
end architecture sim;