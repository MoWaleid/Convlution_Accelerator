-- ============================================================================
-- tb_axi_stream_input_frontend.vhd
-- Covers the depth-16 synchronous FIFO and 64-bit AXI4-Stream byte unpacker.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

entity tb_axi_stream_input_frontend is
end entity tb_axi_stream_input_frontend;

architecture sim of tb_axi_stream_input_frontend is
    constant CLK_PERIOD : time := 10 ns;
    constant C_FIFO_DEPTH : integer := 16;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    -- Direct synchronous-FIFO test signals.
    signal unit_push_valid : std_logic := '0';
    signal unit_push_ready : std_logic;
    signal unit_push_data  : std_logic_vector(7 downto 0) := (others => '0');
    signal unit_pop_valid  : std_logic;
    signal unit_pop_ready  : std_logic := '0';
    signal unit_pop_data   : std_logic_vector(7 downto 0);
    signal unit_level      : natural range 0 to C_FIFO_DEPTH;
    signal unit_fifo_done  : std_logic := '0';

    -- AXI4-Stream frontend signals.
    signal s_axis_tdata  : std_logic_vector(63 downto 0) := (others => '0');
    signal s_axis_tkeep  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';

    signal out_pixel : std_logic_vector(7 downto 0);
    signal out_valid : std_logic;
    signal out_ready : std_logic;
    signal out_last  : std_logic;

    signal ready_phase_a : std_logic := '0';
    signal ready_phase_b : std_logic := '0';
    signal phase_b_mode  : std_logic := '0';
    signal phase_a_release : std_logic := '0';
    signal phase_a_throughput_done : std_logic := '0';
    signal phase_a_done  : std_logic := '0';
    signal phase_b_done  : std_logic := '0';

    function make_beat(base_value : natural) return std_logic_vector is
        variable result : std_logic_vector(63 downto 0) := (others => '0');
    begin
        for lane in 0 to 7 loop
            result((lane + 1) * 8 - 1 downto lane * 8) :=
                std_logic_vector(to_unsigned(base_value + lane, 8));
        end loop;
        return result;
    end function make_beat;
begin
    clk <= not clk after CLK_PERIOD / 2;
    out_ready <= ready_phase_b when phase_b_mode = '1' else ready_phase_a;

    unit_fifo : entity work.sync_fifo
        generic map (
            C_DATA_WIDTH => 8,
            C_DEPTH      => C_FIFO_DEPTH
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            push_valid => unit_push_valid,
            push_ready => unit_push_ready,
            push_data  => unit_push_data,
            pop_valid  => unit_pop_valid,
            pop_ready  => unit_pop_ready,
            pop_data   => unit_pop_data,
            level      => unit_level
        );

    dut : entity work.axi_stream_input_frontend
        generic map (
            C_FIFO_DEPTH => C_FIFO_DEPTH
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tkeep  => s_axis_tkeep,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            out_pixel     => out_pixel,
            out_valid     => out_valid,
            out_ready     => out_ready,
            out_last      => out_last
        );

    reset_proc : process
    begin
        resetn <= '0';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        resetn <= '1';
        wait;
    end process reset_proc;

    -- Fill the FIFO, demonstrate ready deassertion, then use a full FIFO
    -- simultaneous push/pop transfer. The queued sequence must remain ordered.
    unit_fifo_stimulus : process
    begin
        wait until resetn = '1';
        for value in 0 to C_FIFO_DEPTH - 1 loop
            wait until falling_edge(clk);
            unit_push_data  <= std_logic_vector(to_unsigned(value, 8));
            unit_push_valid <= '1';
            wait until rising_edge(clk);
            assert unit_push_ready = '1'
                report "Unit FIFO rejected a push before it became full" severity failure;
        end loop;

        wait until falling_edge(clk);
        unit_push_valid <= '0';
        assert unit_level = C_FIFO_DEPTH
            report "Unit FIFO did not reach depth 16" severity failure;
        assert unit_push_ready = '0'
            report "Unit FIFO push_ready did not deassert when full" severity failure;

        -- At full depth, push 16 and pop 0 on the same active edge.
        unit_push_data  <= std_logic_vector(to_unsigned(C_FIFO_DEPTH, 8));
        unit_push_valid <= '1';
        unit_pop_ready  <= '1';
        assert unit_pop_valid = '1' and unit_pop_data = x"00"
            report "Unit FIFO head data incorrect before simultaneous push/pop" severity failure;
        wait until rising_edge(clk);

        wait until falling_edge(clk);
        unit_push_valid <= '0';
        assert unit_level = C_FIFO_DEPTH
            report "Unit FIFO level changed during simultaneous push/pop" severity failure;

        for expected in 1 to C_FIFO_DEPTH loop
            assert unit_pop_valid = '1'
                report "Unit FIFO became empty too early" severity failure;
            assert unit_pop_data = std_logic_vector(to_unsigned(expected, 8))
                report "Unit FIFO ordering failure after simultaneous push/pop" severity failure;
            wait until rising_edge(clk);
            if expected < C_FIFO_DEPTH then
                wait until falling_edge(clk);
            end if;
        end loop;

        wait until falling_edge(clk);
        assert unit_level = 0 and unit_pop_valid = '0'
            report "Unit FIFO did not drain after ordered pops" severity failure;
        unit_pop_ready <= '0';
        unit_fifo_done <= '1';
        wait;
    end process unit_fifo_stimulus;

    -- Queue the initial beats before allowing output consumption. Keep ready
    -- asserted until the first two full beats prove zero-bubble throughput,
    -- then introduce stalls for the remaining partial beat.
    phase_a_ready_driver : process
        variable cycle_count : integer := 0;
    begin
        wait until phase_a_release = '1';
        ready_phase_a <= '1';
        wait until phase_a_throughput_done = '1';
        while phase_a_done = '0' loop
            wait until falling_edge(clk);
            if (cycle_count mod 5) = 1 or (cycle_count mod 5) = 2 then
                ready_phase_a <= '0';
            else
                ready_phase_a <= '1';
            end if;
            cycle_count := cycle_count + 1;
        end loop;
        ready_phase_a <= '1';
        wait;
    end process phase_a_ready_driver;

    -- With two complete beats already buffered and out_ready held high, every
    -- one of their sixteen pixel transfers must occur on consecutive clocks.
    phase_a_throughput_monitor : process
        variable pixel_count : integer := 0;
        variable previous_handshake_time : time := 0 ns;
    begin
        wait until phase_a_release = '1';
        while pixel_count < 16 loop
            wait until rising_edge(clk);
            if out_valid = '1' and out_ready = '1' then
                if pixel_count > 0 then
                    assert now - previous_handshake_time = CLK_PERIOD
                        report "Inter-beat pixel-output bubble detected" severity failure;
                end if;
                assert out_last = '0'
                    report "TLAST asserted during the queued full-beat throughput check" severity failure;
                previous_handshake_time := now;
                pixel_count := pixel_count + 1;
            end if;
        end loop;
        phase_a_throughput_done <= '1';
        wait;
    end process phase_a_throughput_monitor;

    -- Assert data and TLAST stability through cycles in which out_ready is low.
    output_stall_monitor : process
        variable held_valid : boolean := false;
        variable held_pixel : std_logic_vector(7 downto 0) := (others => '0');
        variable held_last  : std_logic := '0';
    begin
        wait until resetn = '1';
        loop
            wait until falling_edge(clk);
            if held_valid then
                assert out_valid = '1' and out_pixel = held_pixel and out_last = held_last
                    report "Unpacker output changed while out_ready was low" severity failure;
            end if;
            -- Ready drivers update on this falling edge. Sample after the delta
            -- cycle so held_valid describes the following rising edge.
            wait for 1 ps;
            held_valid := (out_valid = '1' and out_ready = '0');
            if held_valid then
                held_pixel := out_pixel;
                held_last  := out_last;
            end if;
            if phase_b_done = '1' then
                exit;
            end if;
        end loop;
        wait;
    end process output_stall_monitor;

    -- Check exact byte ordering, no loss/duplication, and TLAST on only the
    -- final valid byte of each AXI frame.
    output_monitor : process
        variable phase_a_count : integer := 0;
        variable phase_b_count : integer := 0;
        variable expected_value : integer;
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);
            if out_valid = '1' and out_ready = '1' then
                if phase_b_mode = '0' then
                    assert phase_a_count < 21
                        report "Phase A emitted too many pixels" severity failure;
                    expected_value := phase_a_count;
                    assert out_pixel = std_logic_vector(to_unsigned(expected_value, 8))
                        report "Phase A byte ordering failure" severity failure;
                    if phase_a_count = 20 then
                        assert out_last = '1'
                            report "Phase A final partial-beat pixel did not assert TLAST" severity failure;
                        phase_a_done <= '1';
                    else
                        assert out_last = '0'
                            report "Phase A asserted TLAST before its final valid pixel" severity failure;
                    end if;
                    phase_a_count := phase_a_count + 1;
                else
                    assert phase_b_count < 144
                        report "Phase B emitted too many pixels" severity failure;
                    expected_value := 32 + phase_b_count;
                    assert out_pixel = std_logic_vector(to_unsigned(expected_value, 8))
                        report "Phase B byte ordering/loss/duplication failure" severity failure;
                    if phase_b_count = 143 then
                        assert out_last = '1'
                            report "Phase B final pixel did not assert TLAST" severity failure;
                        phase_b_done <= '1';
                    else
                        assert out_last = '0'
                            report "Phase B asserted TLAST before its final pixel" severity failure;
                    end if;
                    phase_b_count := phase_b_count + 1;
                end if;
            end if;
        end loop;
    end process output_monitor;

    stream_stimulus : process
        procedure send_beat(
            data : in std_logic_vector(63 downto 0);
            keep : in std_logic_vector(7 downto 0);
            last : in std_logic
        ) is
        begin
            wait until falling_edge(clk);
            s_axis_tdata  <= data;
            s_axis_tkeep  <= keep;
            s_axis_tlast  <= last;
            s_axis_tvalid <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_axis_tready = '1';
            end loop;
            wait until falling_edge(clk);
            s_axis_tvalid <= '0';
        end procedure send_beat;
    begin
        wait until resetn = '1';

        -- Frame A: queue two full beats and a contiguous five-byte final beat
        -- before allowing output consumption.
        send_beat(make_beat(0),  x"FF", '0');
        send_beat(make_beat(8),  x"FF", '0');
        send_beat(make_beat(16), x"1F", '1');
        wait until falling_edge(clk);
        phase_a_release <= '1';
        wait until phase_a_done = '1';

        -- Frame B: hold output ready low, accept one active beat plus all 16
        -- FIFO entries, then prove TREADY remains low for the held 18th beat.
        wait until falling_edge(clk);
        phase_b_mode  <= '1';
        ready_phase_b <= '0';
        for beat in 0 to 16 loop
            send_beat(make_beat(32 + beat * 8), x"FF", '0');
        end loop;

        wait until falling_edge(clk);
        s_axis_tdata  <= make_beat(32 + 17 * 8);
        s_axis_tkeep  <= x"FF";
        s_axis_tlast  <= '1';
        s_axis_tvalid <= '1';
        for stalled_cycle in 1 to 3 loop
            wait until rising_edge(clk);
            assert s_axis_tready = '0'
                report "Input TREADY reasserted while active beat plus FIFO were full" severity failure;
        end loop;

        wait until falling_edge(clk);
        ready_phase_b <= '1';
        loop
            wait until rising_edge(clk);
            exit when s_axis_tready = '1';
        end loop;
        wait until falling_edge(clk);
        s_axis_tvalid <= '0';
        s_axis_tlast  <= '0';

        wait until phase_b_done = '1';
        wait;
    end process stream_stimulus;

    finish_proc : process
    begin
        wait until unit_fifo_done = '1';
        wait until phase_b_done = '1';
        report "--- AXI4-Stream input frontend regression completed successfully ---";
        stop(0);
        wait;
    end process finish_proc;

    timeout_proc : process
    begin
        wait for 30 us;
        assert false report "AXI4-Stream input frontend regression timed out" severity failure;
        wait;
    end process timeout_proc;
end architecture sim;