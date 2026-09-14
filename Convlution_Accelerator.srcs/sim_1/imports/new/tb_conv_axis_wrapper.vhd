-- ============================================================================
-- tb_conv_axis_wrapper.vhd
--
-- M4 FINAL comprehensive RTL integration regression.
--
-- Compiled profile (all geometry from config_pkg; supports the released
-- N in {3, 5} x K in {4, 8, 16} profile matrix, 2026-09-14):
--   N = CFG_N
--   K = CFG_K
--   padded input  = CFG_IMAGE_WIDTH x CFG_IMAGE_HEIGHT bytes
--   logical output = CFG_UNPADDED_WIDTH x CFG_UNPADDED_HEIGHT
--   output = positions * K * int16 bytes
--
-- Numerical setup:
--   pixel(r,c)        = r + c
--   every coefficient = +1
--   bias              = 0
--   shift             = 0
--   ReLU              = 0
--
-- Therefore every channel at logical output (r,c) must be signed16 value
-- N*N * (r + c) + N*N.  The spatially varying result makes a dropped,
-- duplicated, or reordered position at any row-edge bubble visible to the
-- scoreboard.
--
-- Coverage
-- --------
-- A. Reset, discovery, pre-START stream gating
-- B. Complete parameter admission through AXI-Lite
-- C. Full frame through REAL frontend/core/serializer under backpressure
--      * strict padded-input-byte framing
--      * numerical output
--      * output ordering/packing
--      * input/output backpressure
--      * exact counters
--      * DONE only after final external output acceptance
-- D. Repeated successful frame with new START and NO RESET
-- E. Malformed accepted input beat -> INPUT_FRAME_ERROR / FAULT
--      * malformed bytes counted physically
--      * malformed beat not released as pixels
--      * no successful completion
--      * safe local RESET recovery
-- F. ABORT while real serializer output is stalled
--      * offered output remains stable
--      * production stops
--      * queued output remains externally visible
--      * queued FIFO drains during FAULT
--      * DONE remains clear
-- G. RESET recovery after ABORT preserves installed parameters
-- H. Complete successful post-recovery frame
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;


entity tb_conv_axis_wrapper is
    generic (
        G_WINDOW_PREFETCH : boolean := true;
        G_REQUIRE_CONTINUOUS : boolean := true;
        G_STRESS : boolean := false;
        G_CLK_PERIOD_PS : positive := 8000
    );
end entity tb_conv_axis_wrapper;


architecture sim of tb_conv_axis_wrapper is

    constant CLK_PERIOD :
        time := G_CLK_PERIOD_PS * 1 ps;


    constant C_K :
        positive := CFG_K;

    constant C_N :
        positive := CFG_N;

    constant C_PAD_W :
        positive := CFG_IMAGE_WIDTH;

    constant C_PAD_H :
        positive := CFG_IMAGE_HEIGHT;

    constant C_LOG_W :
        positive := CFG_UNPADDED_WIDTH;

    constant C_LOG_H :
        positive := CFG_UNPADDED_HEIGHT;


    constant C_EXPECTED_INPUT_BYTES :
        positive :=
            C_PAD_W * C_PAD_H;

    constant C_EXPECTED_OUTPUT_PIXELS :
        positive :=
            C_LOG_W * C_LOG_H;

    constant C_EXPECTED_OUTPUT_BYTES :
        positive :=
            C_EXPECTED_OUTPUT_PIXELS
            * C_K
            * 2;

    constant C_EXPECTED_OUTPUT_BEATS :
        positive :=
            C_EXPECTED_OUTPUT_BYTES / 8;

    constant C_OUTPUT_BEATS_PER_POSITION :
        positive :=
            (C_K * 2) / 8;

    constant C_FULL_INPUT_BEATS :
        natural :=
            C_EXPECTED_INPUT_BYTES / 8;

    constant C_FINAL_INPUT_BYTES :
        natural :=
            C_EXPECTED_INPUT_BYTES mod 8;

    -- AXI-Lite coefficient words per channel slot: N*N int8 taps packed four
    -- per 32-bit word (N=3 -> 3 words, N=5 -> 7 words).
    constant C_COEFF_WORDS :
        positive :=
            (C_N * C_N + 3) / 4;

    -- Minimum whole input beats that must be accepted before the very first
    -- output position can exist: (N-1) full padded rows plus one window row's
    -- worth of leading pixels.  Used by the partial-frame ABORT fixture so it
    -- scales with the compiled geometry instead of assuming 34-wide padding.
    constant C_FIRST_OUTPUT_MIN_BEATS :
        positive :=
            ((C_N - 1) * C_PAD_W + C_N + 7) / 8 + 1;


    function input_pixel_value(
        pixel_index : natural
    ) return natural is
    begin
        if G_STRESS then
            return (pixel_index*73 + (pixel_index/7)*29 + (pixel_index mod 11)*113) mod 256;
        end if;
        return
            (pixel_index / C_PAD_W)
            + (pixel_index mod C_PAD_W);
    end function input_pixel_value;


    function coefficient_value(channel : natural; tap : natural) return integer is
    begin
        if not G_STRESS then return 1; end if;
        if channel = 0 and tap = 0 then return -128; end if;
        if channel = C_K-1 and tap = C_N*C_N-1 then return 127; end if;
        return ((channel*13 + tap*7) mod 17)-8;
    end function;

    function coefficient_word(channel : natural; word_index : natural) return std_logic_vector is
        variable word : std_logic_vector(31 downto 0) := (others => '0');
    begin
        for lane in 0 to 3 loop
            if word_index*4+lane < C_N*C_N then
                word(lane*8+7 downto lane*8) := std_logic_vector(to_signed(coefficient_value(channel,word_index*4+lane),8));
            end if;
        end loop;
        return word;
    end function;

    function expected_output_value(
        position_index : natural;
        channel : natural := 0
    ) return integer is

        variable output_row :
            natural;

        variable output_column :
            natural;
        variable total : integer := 0;

    begin

        output_row :=
            position_index / C_LOG_W;

        output_column :=
            position_index mod C_LOG_W;

        for r in 0 to C_N-1 loop
            for c in 0 to C_N-1 loop
                total := total + input_pixel_value((output_row+r)*C_PAD_W+output_column+c)*coefficient_value(channel,r*C_N+c);
            end loop;
        end loop;
        if total > 32767 then return 32767; end if;
        if total < -32768 then return -32768; end if;
        return total;

    end function expected_output_value;


    -- ========================================================================
    -- Clock / reset
    -- ========================================================================

    signal clk :
        std_logic := '0';

    signal resetn :
        std_logic := '0';


    -- ========================================================================
    -- AXI-Lite
    -- ========================================================================

    signal S_AXI_AWADDR :
        std_logic_vector(31 downto 0) :=
            (others => '0');

    signal S_AXI_AWPROT :
        std_logic_vector(2 downto 0) :=
            (others => '0');

    signal S_AXI_AWVALID :
        std_logic := '0';

    signal S_AXI_AWREADY :
        std_logic;


    signal S_AXI_WDATA :
        std_logic_vector(31 downto 0) :=
            (others => '0');

    signal S_AXI_WSTRB :
        std_logic_vector(3 downto 0) :=
            (others => '0');

    signal S_AXI_WVALID :
        std_logic := '0';

    signal S_AXI_WREADY :
        std_logic;


    signal S_AXI_BRESP :
        std_logic_vector(1 downto 0);

    signal S_AXI_BVALID :
        std_logic;

    signal S_AXI_BREADY :
        std_logic := '0';


    signal S_AXI_ARADDR :
        std_logic_vector(31 downto 0) :=
            (others => '0');

    signal S_AXI_ARPROT :
        std_logic_vector(2 downto 0) :=
            (others => '0');

    signal S_AXI_ARVALID :
        std_logic := '0';

    signal S_AXI_ARREADY :
        std_logic;


    signal S_AXI_RDATA :
        std_logic_vector(31 downto 0);

    signal S_AXI_RRESP :
        std_logic_vector(1 downto 0);

    signal S_AXI_RVALID :
        std_logic;

    signal S_AXI_RREADY :
        std_logic := '0';


    -- ========================================================================
    -- AXI-Stream input
    -- ========================================================================

    signal s_axis_tdata :
        std_logic_vector(63 downto 0) :=
            (others => '0');

    signal s_axis_tkeep :
        std_logic_vector(7 downto 0) :=
            (others => '0');

    signal s_axis_tvalid :
        std_logic := '0';

    signal s_axis_tready :
        std_logic;

    signal s_axis_tlast :
        std_logic := '0';


    -- ========================================================================
    -- AXI-Stream output
    -- ========================================================================

    signal m_axis_tdata :
        std_logic_vector(63 downto 0);

    signal m_axis_tkeep :
        std_logic_vector(7 downto 0);

    signal m_axis_tvalid :
        std_logic;

    signal m_axis_tready :
        std_logic := '0';

    signal m_axis_tlast :
        std_logic;


    -- ========================================================================
    -- Output-ready control
    --
    -- 0 = permanently stalled
    -- 1 = permanently ready
    -- 2 = deterministic pseudo-random backpressure
    -- ========================================================================

    signal output_ready_mode :
        natural range 0 to 2 := 0;

    -- Frames driven with guaranteed gapless input supply and a permanently
    -- ready sink.  Only these frames may be held to the no-output-gap rule.
    signal continuous_frame :
        std_logic := '0';

    -- Timestamp of the most recent accepted COMMAND.START write, used for
    -- START-to-first-output and START-to-DONE latency measurements.
    signal start_command_time :
        time := 0 ns;


    -- ========================================================================
    -- Regression bookkeeping
    -- ========================================================================

    signal output_success_frames :
        natural := 0;

    signal output_stall_count :
        natural := 0;

    signal input_stall_count :
        natural := 0;

    signal monitor_clear :
        std_logic := '0';


begin

    -- ========================================================================
    -- Basic geometry sanity for this regression
    -- ========================================================================

    assert C_N = 3 or C_N = 5
        report
            "tb_conv_axis_wrapper supports the released N=3 and N=5 profiles"
        severity failure;

    assert C_K = 4 or C_K = 8 or C_K = 16
        report
            "tb_conv_axis_wrapper supports the released K=4/K=8/K=16 profiles"
        severity failure;

    assert C_FINAL_INPUT_BYTES = 0 or C_FINAL_INPUT_BYTES = 4
        report
            "Input framing fixture supports full or 4-byte-final frames only"
        severity failure;

    assert C_K mod 4 = 0
        report
            "Regression requires an integral number of AXIS64 beats per output position"
        severity failure;

    assert C_OUTPUT_BEATS_PER_POSITION * 8 = C_K * 2
        report
            "Output beat geometry inconsistency"
        severity failure;


    -- ========================================================================
    -- Clock
    -- ========================================================================

    clk <=
        not clk after CLK_PERIOD / 2;


    -- ========================================================================
    -- DUT
    -- ========================================================================

    dut :
        entity work.conv_axis_wrapper
        generic map (
            C_WINDOW_PREFETCH => G_WINDOW_PREFETCH,
            C_K =>
                CFG_K,

            C_N =>
                CFG_N,

            C_IMAGE_WIDTH =>
                CFG_IMAGE_WIDTH,

            C_IMAGE_HEIGHT =>
                CFG_IMAGE_HEIGHT,

            C_OUTPUT_IMAGE_WIDTH =>
                CFG_UNPADDED_WIDTH,

            C_OUTPUT_IMAGE_HEIGHT =>
                CFG_UNPADDED_HEIGHT,

            C_S_AXI_DATA_WIDTH =>
                32,

            C_S_AXI_ADDR_WIDTH =>
                32,

            C_BUILD_ID =>
                CFG_BUILD_ID,

            C_DMA_LENGTH_WIDTH =>
                22
        )
        port map (
            clk =>
                clk,

            resetn =>
                resetn,


            S_AXI_AWADDR =>
                S_AXI_AWADDR,

            S_AXI_AWPROT =>
                S_AXI_AWPROT,

            S_AXI_AWVALID =>
                S_AXI_AWVALID,

            S_AXI_AWREADY =>
                S_AXI_AWREADY,


            S_AXI_WDATA =>
                S_AXI_WDATA,

            S_AXI_WSTRB =>
                S_AXI_WSTRB,

            S_AXI_WVALID =>
                S_AXI_WVALID,

            S_AXI_WREADY =>
                S_AXI_WREADY,


            S_AXI_BRESP =>
                S_AXI_BRESP,

            S_AXI_BVALID =>
                S_AXI_BVALID,

            S_AXI_BREADY =>
                S_AXI_BREADY,


            S_AXI_ARADDR =>
                S_AXI_ARADDR,

            S_AXI_ARPROT =>
                S_AXI_ARPROT,

            S_AXI_ARVALID =>
                S_AXI_ARVALID,

            S_AXI_ARREADY =>
                S_AXI_ARREADY,


            S_AXI_RDATA =>
                S_AXI_RDATA,

            S_AXI_RRESP =>
                S_AXI_RRESP,

            S_AXI_RVALID =>
                S_AXI_RVALID,

            S_AXI_RREADY =>
                S_AXI_RREADY,


            s_axis_tdata =>
                s_axis_tdata,

            s_axis_tkeep =>
                s_axis_tkeep,

            s_axis_tvalid =>
                s_axis_tvalid,

            s_axis_tready =>
                s_axis_tready,

            s_axis_tlast =>
                s_axis_tlast,


            m_axis_tdata =>
                m_axis_tdata,

            m_axis_tkeep =>
                m_axis_tkeep,

            m_axis_tvalid =>
                m_axis_tvalid,

            m_axis_tready =>
                m_axis_tready,

            m_axis_tlast =>
                m_axis_tlast
        );


    -- ========================================================================
    -- Output-ready driver
    -- ========================================================================

    output_ready_driver : process

        variable lfsr :
            std_logic_vector(7 downto 0) :=
                x"A5";

        variable feedback :
            std_logic;

    begin

        loop

            wait until falling_edge(clk);


            if resetn = '0' then

                m_axis_tready <=
                    '0';

                lfsr :=
                    x"A5";


            else

                case output_ready_mode is

                    when 0 =>

                        m_axis_tready <=
                            '0';


                    when 1 =>

                        m_axis_tready <=
                            '1';


                    when others =>

                        feedback :=
                            lfsr(7)
                            xor lfsr(5)
                            xor lfsr(4)
                            xor lfsr(3);

                        lfsr :=
                            lfsr(6 downto 0)
                            & feedback;


                        -- Deterministic stalls, but more ready cycles
                        -- than stalled cycles.
                        m_axis_tready <=
                            lfsr(0)
                            or lfsr(2);

                end case;

            end if;

        end loop;

    end process output_ready_driver;


    -- ========================================================================
    -- Input backpressure monitor
    -- ========================================================================

    input_stall_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                input_stall_count <=
                    0;

            elsif
                s_axis_tvalid = '1'
                and s_axis_tready = '0'
            then

                input_stall_count <=
                    input_stall_count + 1;

            end if;

        end if;

    end process input_stall_monitor;


    -- ========================================================================
    -- Output protocol + numerical monitor
    --
    -- Every emitted scalar is checked against its logical (row,column)
    -- position.  The monitor advances only on a real AXIS handshake, so the
    -- window generator's row-edge valid bubbles and output backpressure are
    -- both tolerated without weakening ordering coverage.
    --
    -- K multiple of 4 means every logical output pixel becomes exactly
    -- C_OUTPUT_BEATS_PER_POSITION full 64-bit beats, so a complete frame
    -- contains exactly C_EXPECTED_OUTPUT_BEATS beats, all TKEEP=FF.
    -- ========================================================================

    output_monitor : process(clk)

        variable frame_beat_count :
            natural := 0;

        variable position_index :
            natural := 0;

        variable expected_scalar :
            std_logic_vector(15 downto 0) :=
                (others => '0');

        variable row_transitions_seen :
            natural := 0;
        variable output_gap_cycles : natural := 0;
        variable first_output_time : time := 0 ns;

    begin

        if rising_edge(clk) then

            if resetn = '0' then

                frame_beat_count :=
                    0;

                row_transitions_seen :=
                    0;

                output_success_frames <=
                    0;
                output_gap_cycles := 0;


            else

                if monitor_clear = '1' then
                    output_gap_cycles := 0;

                    frame_beat_count :=
                        0;

                    row_transitions_seen :=
                        0;

                end if;


                -- Ready-but-invalid cycles between the first and last accepted
                -- output beat, measured on EVERY monitored frame.  The
                -- zero-gap requirement is asserted only for the adequately
                -- supplied, continuously ready benchmark (frame D); other
                -- frames report the measured count without asserting.
                if frame_beat_count > 0 and
                   m_axis_tready = '1' and m_axis_tvalid = '0' then
                    output_gap_cycles := output_gap_cycles + 1;
                    if continuous_frame = '1' and output_ready_mode = 1 then
                        assert not G_REQUIRE_CONTINUOUS
                            report "Unexpected output gap at beat " & integer'image(frame_beat_count)
                            severity failure;
                    end if;
                end if;

                if
                    m_axis_tvalid = '1'
                    and m_axis_tready = '1'
                then

                    assert m_axis_tkeep = x"FF"
                        report
                            "Wrapper emitted non-full output beat"
                        severity failure;


                    position_index :=
                        frame_beat_count /
                        C_OUTPUT_BEATS_PER_POSITION;
                    if frame_beat_count = 0 then
                        first_output_time := now;
                        output_gap_cycles := 0;
                    end if;


                    expected_scalar :=
                        std_logic_vector(
                            to_signed(
                                expected_output_value(position_index),
                                16
                            )
                        );


                    for lane in 0 to 3 loop
                        expected_scalar := std_logic_vector(to_signed(expected_output_value(
                            position_index, (frame_beat_count mod C_OUTPUT_BEATS_PER_POSITION)*4+lane),16));

                        assert
                            m_axis_tdata(
                                (lane + 1) * 16 - 1 downto lane * 16
                            ) = expected_scalar
                        report
                            "" &
                            "Wrapper numerical/order mismatch at output position "
                            & integer'image(position_index)
                            & ", channel group "
                            & integer'image(
                                frame_beat_count mod
                                C_OUTPUT_BEATS_PER_POSITION
                            )
                        severity failure;

                    end loop;


                    if
                        frame_beat_count mod
                        C_OUTPUT_BEATS_PER_POSITION = 0
                        and position_index > 0
                        and position_index mod C_LOG_W = 0
                    then

                        row_transitions_seen :=
                            row_transitions_seen + 1;

                    end if;


                    if m_axis_tlast = '1' then
                        report "EDGE_METRICS prefetch=" & boolean'image(G_WINDOW_PREFETCH) &
                            " ready_mode=" & integer'image(output_ready_mode) &
                            " gaps=" & integer'image(output_gap_cycles) &
                            " first_to_last=" & time'image(now - first_output_time);

                        report "EDGE_LATENCY start_to_first_output=" &
                            time'image(first_output_time - start_command_time);

                        assert
                            frame_beat_count =
                            C_EXPECTED_OUTPUT_BEATS - 1
                        report
                            "Wrapper TLAST arrived at incorrect output beat"
                        severity failure;


                        assert
                            row_transitions_seen = C_LOG_H - 1
                        report
                            "Wrapper did not preserve all logical row transitions across row-edge bubbles"
                        severity failure;


                        output_success_frames <=
                            output_success_frames + 1;

                        frame_beat_count :=
                            0;

                        row_transitions_seen :=
                            0;


                    else

                        assert
                            frame_beat_count <
                            C_EXPECTED_OUTPUT_BEATS - 1
                        report
                            "Wrapper reached expected final beat without TLAST"
                        severity failure;


                        frame_beat_count :=
                            frame_beat_count + 1;

                    end if;

                end if;

            end if;

        end if;

    end process output_monitor;


    -- ========================================================================
    -- Output stability monitor
    --
    -- Once TVALID is offered while TREADY=0, all payload fields must remain
    -- stable until acceptance.
    -- ========================================================================

    output_stability_monitor : process(clk)

        variable stalled :
            boolean := false;

        variable held_data :
            std_logic_vector(63 downto 0) :=
                (others => '0');

        variable held_keep :
            std_logic_vector(7 downto 0) :=
                (others => '0');

        variable held_last :
            std_logic := '0';

    begin

        if rising_edge(clk) then

            if resetn = '0' then

                stalled :=
                    false;

                output_stall_count <=
                    0;


            else

                if stalled then

                    assert m_axis_tvalid = '1'
                        report
                            "Wrapper retracted TVALID while externally stalled"
                        severity failure;

                    assert m_axis_tdata = held_data
                        report
                            "Wrapper changed TDATA while externally stalled"
                        severity failure;

                    assert m_axis_tkeep = held_keep
                        report
                            "Wrapper changed TKEEP while externally stalled"
                        severity failure;

                    assert m_axis_tlast = held_last
                        report
                            "Wrapper changed TLAST while externally stalled"
                        severity failure;

                end if;


                stalled :=
                    (
                        m_axis_tvalid = '1'
                        and m_axis_tready = '0'
                    );


                if stalled then

                    held_data :=
                        m_axis_tdata;

                    held_keep :=
                        m_axis_tkeep;

                    held_last :=
                        m_axis_tlast;

                    output_stall_count <=
                        output_stall_count + 1;

                end if;

            end if;

        end if;

    end process output_stability_monitor;


    -- ========================================================================
    -- Main regression
    -- ========================================================================

    stim_proc : process

        ------------------------------------------------------------------------
        -- AXI-Lite full-word write
        ------------------------------------------------------------------------

        procedure axi_write(
            constant address :
                in natural;

            constant data :
                in std_logic_vector(31 downto 0);

            constant expected_response :
                in std_logic_vector(1 downto 0) := "00"
        ) is

            variable aw_done :
                boolean := false;

            variable w_done :
                boolean := false;

        begin

            wait until falling_edge(clk);


            S_AXI_AWADDR <=
                std_logic_vector(
                    to_unsigned(
                        address,
                        32
                    )
                );

            S_AXI_AWVALID <=
                '1';


            S_AXI_WDATA <=
                data;

            S_AXI_WSTRB <=
                x"F";

            S_AXI_WVALID <=
                '1';

            S_AXI_BREADY <=
                '0';


            while not (aw_done and w_done) loop

                wait until rising_edge(clk);


                if
                    not aw_done
                    and S_AXI_AWREADY = '1'
                then

                    aw_done :=
                        true;

                end if;


                if
                    not w_done
                    and S_AXI_WREADY = '1'
                then

                    w_done :=
                        true;

                end if;


                wait for 1 ns;


                if aw_done then

                    S_AXI_AWVALID <=
                        '0';

                end if;


                if w_done then

                    S_AXI_WVALID <=
                        '0';

                end if;

            end loop;


            wait until falling_edge(clk);

            S_AXI_BREADY <=
                '1';


            loop

                wait until rising_edge(clk);

                exit when S_AXI_BVALID = '1';

            end loop;


            assert S_AXI_BRESP = expected_response
                report
                    "AXI write response mismatch at address "
                    & integer'image(address)
                severity failure;


            wait until falling_edge(clk);

            S_AXI_BREADY <=
                '0';

            S_AXI_AWADDR <=
                (others => '0');

            S_AXI_WDATA <=
                (others => '0');

            S_AXI_WSTRB <=
                (others => '0');

        end procedure axi_write;


        ------------------------------------------------------------------------
        -- AXI-Lite read
        ------------------------------------------------------------------------

        procedure axi_read(
            constant address :
                in natural;

            variable data :
                out std_logic_vector(31 downto 0);

            constant expected_response :
                in std_logic_vector(1 downto 0) := "00"
        ) is

        begin

            wait until falling_edge(clk);


            S_AXI_ARADDR <=
                std_logic_vector(
                    to_unsigned(
                        address,
                        32
                    )
                );

            S_AXI_ARVALID <=
                '1';

            S_AXI_RREADY <=
                '0';


            loop

                wait until rising_edge(clk);

                exit when S_AXI_ARREADY = '1';

            end loop;


            wait for 1 ns;

            S_AXI_ARVALID <=
                '0';


            wait until falling_edge(clk);

            S_AXI_RREADY <=
                '1';


            loop

                wait until rising_edge(clk);

                exit when S_AXI_RVALID = '1';

            end loop;


            data :=
                S_AXI_RDATA;


            assert S_AXI_RRESP = expected_response
                report
                    "AXI read response mismatch at address "
                    & integer'image(address)
                severity failure;


            wait until falling_edge(clk);

            S_AXI_RREADY <=
                '0';

            S_AXI_ARADDR <=
                (others => '0');

        end procedure axi_read;


        ------------------------------------------------------------------------
        -- Program all channels:
        --
        --   N*N coefficients   = +1 (packed into C_COEFF_WORDS words)
        --   bias               = 0
        --   shift              = 0
        --   ReLU               = 0
        ------------------------------------------------------------------------

        procedure program_all_channels is

            variable base :
                natural;

        begin

            for channel in 0 to C_K - 1 loop

                base :=
                    channel * 16#100#;


                for word_index in 0 to C_COEFF_WORDS - 1 loop

                    axi_write(
                        base + word_index * 4,
                        coefficient_word(channel, word_index)
                    );

                end loop;


                axi_write(
                    base + 16#F8#,
                    x"00000000"
                );


                axi_write(
                    base + 16#FC#,
                    x"00000000"
                );

            end loop;

        end procedure program_all_channels;


        ------------------------------------------------------------------------
        -- Send one external AXIS beat.
        --
        -- TVALID / TDATA / TKEEP / TLAST remain stable until handshake.
        ------------------------------------------------------------------------

        procedure send_input_beat(
            constant data :
                in std_logic_vector(63 downto 0);

            constant keep :
                in std_logic_vector(7 downto 0);

            constant last :
                in std_logic
        ) is

        begin

            wait until falling_edge(clk);


            s_axis_tdata <=
                data;

            s_axis_tkeep <=
                keep;

            s_axis_tlast <=
                last;

            s_axis_tvalid <=
                '1';


            loop

                wait until rising_edge(clk);

                exit when s_axis_tready = '1';

            end loop;


            wait until falling_edge(clk);

            s_axis_tvalid <=
                '0';

            s_axis_tdata <=
                (others => '0');

            s_axis_tkeep <=
                (others => '0');

            s_axis_tlast <=
                '0';

        end procedure send_input_beat;


        ------------------------------------------------------------------------
        -- Send one complete legal 1156-byte frame.
        ------------------------------------------------------------------------

        procedure send_full_input_frame is

            variable data_word :
                std_logic_vector(63 downto 0);

            variable pixel_index :
                natural := 0;
            variable gap_state : unsigned(15 downto 0) := x"ACE1";

        begin

            for beat in 0 to C_FULL_INPUT_BEATS - 1 loop
                if G_STRESS and continuous_frame = '0' then
                    gap_state := gap_state(14 downto 0) & (gap_state(15) xor gap_state(13) xor gap_state(12) xor gap_state(10));
                    for gap_cycle in 1 to to_integer(gap_state(5 downto 0)) loop
                        wait until falling_edge(clk);
                    end loop;
                end if;

                data_word :=
                    (others => '0');


                for lane in 0 to 7 loop

                    data_word(
                        (lane + 1) * 8 - 1 downto lane * 8
                    ) :=
                        std_logic_vector(
                            to_unsigned(
                                input_pixel_value(pixel_index),
                                8
                            )
                        );

                    pixel_index :=
                        pixel_index + 1;

                end loop;

                if C_FINAL_INPUT_BYTES = 0 and
                   beat = C_FULL_INPUT_BEATS - 1 then
                    -- Frame length is an exact multiple of the beat width:
                    -- the final full beat itself carries TLAST.
                    send_input_beat(
                        data_word,
                        x"FF",
                        '1'
                    );
                else
                    send_input_beat(
                        data_word,
                        x"FF",
                        '0'
                    );
                end if;

            end loop;


            -- Trailing partial beat, if the frame length requires one.
            --
            -- C_FINAL_INPUT_BYTES = 4:
            --
            -- lanes 0..3 valid, contiguous low-lane mask.
            if C_FINAL_INPUT_BYTES > 0 then

                data_word :=
                    (others => '0');


                for lane in 0 to C_FINAL_INPUT_BYTES - 1 loop

                    data_word(
                        (lane + 1) * 8 - 1 downto lane * 8
                    ) :=
                        std_logic_vector(
                            to_unsigned(
                                input_pixel_value(pixel_index),
                                8
                            )
                        );

                    pixel_index :=
                        pixel_index + 1;

                end loop;


                send_input_beat(
                    data_word,
                    x"0F",
                    '1'
                );

            end if;


            assert pixel_index = C_EXPECTED_INPUT_BYTES
                report
                    "Input generator did not pack exactly one padded frame"
                severity failure;


            send_input_beat(
                data_word,
                x"0F",
                '1'
            );

        end procedure send_full_input_frame;


        ------------------------------------------------------------------------
        -- Send N complete non-final input beats.
        ------------------------------------------------------------------------

        procedure send_full_input_beats(
            constant count :
                in positive
        ) is

            variable data_word :
                std_logic_vector(63 downto 0);

            variable pixel_index :
                natural := 0;

        begin

            for beat in 1 to count loop

                data_word :=
                    (others => '0');


                for lane in 0 to 7 loop

                    data_word(
                        (lane + 1) * 8 - 1 downto lane * 8
                    ) :=
                        std_logic_vector(
                            to_unsigned(
                                input_pixel_value(pixel_index),
                                8
                            )
                        );

                    pixel_index :=
                        pixel_index + 1;

                end loop;

                send_input_beat(
                    data_word,
                    x"FF",
                    '0'
                );

            end loop;

        end procedure send_full_input_beats;


        ------------------------------------------------------------------------
        -- Reset only the TB's partial external-output frame counter.
        --
        -- output_success_frames intentionally remains cumulative.
        ------------------------------------------------------------------------

        procedure clear_output_partial_monitor is
        begin

            wait until falling_edge(clk);

            monitor_clear <=
                '1';


            wait until rising_edge(clk);

            wait until falling_edge(clk);

            monitor_clear <=
                '0';

        end procedure clear_output_partial_monitor;


        ------------------------------------------------------------------------
        -- Wait for successful accelerator completion.
        ------------------------------------------------------------------------

        procedure wait_for_success(
            constant expected_output_frames :
                in natural
        ) is

            variable status_word :
                std_logic_vector(31 downto 0);

            variable status_poll_count :
                natural := 0;

        begin

            while
                output_success_frames <
                expected_output_frames
            loop

                wait until rising_edge(clk);

            end loop;


            loop

                axi_read(
                    16#410C#,
                    status_word
                );


                assert status_word(5) = '0'
                    report
                        "ERROR asserted during expected successful frame"
                    severity failure;


                assert status_word(6) = '0'
                    report
                        "FAULT asserted during expected successful frame"
                    severity failure;


                status_poll_count :=
                    status_poll_count + 1;


                assert status_poll_count <= 256
                    report
                        "Complete output frame did not transition the controller to DONE/IDLE; check input/output acceptance accounting"
                    severity failure;


                exit when
                    status_word(0) = '1'
                    and status_word(4) = '1'
                    and status_word(8) = '1';

            end loop;

            -- Software-visible completion latency for the benchmark frame
            -- (guaranteed supply, continuously ready sink).
            if continuous_frame = '1' and output_ready_mode = 1 then
                report "EDGE_LATENCY start_to_done=" &
                    time'image(now - start_command_time);
            end if;


            assert status_word(1) = '0'
                report
                    "BUSY remained asserted after successful frame"
                severity failure;

            assert status_word(2) = '1'
                report
                    "CORE_COMPLETE missing after successful frame"
                severity failure;

            assert status_word(3) = '1'
                report
                    "OUTPUT_DRAINED missing after successful frame"
                severity failure;

            assert status_word(4) = '1'
                report
                    "DONE missing after successful frame"
                severity failure;

            assert status_word(7) = '1'
                report
                    "PARAM_COMPLETE was lost"
                severity failure;

            assert status_word(8) = '1'
                report
                    "Successful frame did not become QUIESCENT"
                severity failure;

        end procedure wait_for_success;


        ------------------------------------------------------------------------
        -- Check exact successful-frame counters.
        ------------------------------------------------------------------------

        procedure check_success_counters is

            variable rd :
                std_logic_vector(31 downto 0);

        begin

            axi_read(
                16#4140#,
                rd
            );

            assert
                to_integer(unsigned(rd)) =
                C_EXPECTED_INPUT_BYTES
            report
                "INPUT_ACCEPT_BYTES mismatch"
            severity failure;


            axi_read(
                16#4144#,
                rd
            );

            assert
                to_integer(unsigned(rd)) =
                C_EXPECTED_INPUT_BYTES
            report
                "INPUT_CONSUMED_BYTES mismatch"
            severity failure;


            axi_read(
                16#4148#,
                rd
            );

            assert
                to_integer(unsigned(rd)) =
                C_EXPECTED_OUTPUT_PIXELS
            report
                "CORE_ACCEPT_PIXELS mismatch"
            severity failure;


            axi_read(
                16#414C#,
                rd
            );

            assert
                to_integer(unsigned(rd)) =
                C_EXPECTED_OUTPUT_BYTES
            report
                "OUTPUT_ACCEPT_BYTES mismatch"
            severity failure;

        end procedure check_success_counters;


        ------------------------------------------------------------------------
        -- Wait for FAULT + local QUIESCENT.
        ------------------------------------------------------------------------

        procedure wait_for_fault_quiescent is

            variable status_word :
                std_logic_vector(31 downto 0);

        begin

            loop

                axi_read(
                    16#410C#,
                    status_word
                );


                assert status_word(6) = '1'
                    report
                        "Expected FAULT state was lost"
                    severity failure;


                exit when status_word(8) = '1';

            end loop;

        end procedure wait_for_fault_quiescent;


        variable rd :
            std_logic_vector(31 downto 0);

        variable input_stalls_before :
            natural;

        variable output_stalls_before :
            natural;

        variable held_abort_data :
            std_logic_vector(63 downto 0);

        variable held_abort_keep :
            std_logic_vector(7 downto 0);

        variable held_abort_last :
            std_logic;

    begin

        -- ====================================================================
        -- A. RESET / DISCOVERY / PRE-START GATING
        -- ====================================================================

        report
            "--- WRAPPER A: reset / discovery / pre-START gating ---";


        resetn <=
            '0';

        output_ready_mode <=
            0;

        s_axis_tvalid <=
            '0';

        s_axis_tlast <=
            '0';


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);

        resetn <=
            '1';


        wait until rising_edge(clk);
        wait for 1 ns;


        axi_read(
            16#4100#,
            rd
        );

        assert rd = x"43564831"
            report
                "MAGIC mismatch through wrapper"
            severity failure;


        axi_read(
            16#4104#,
            rd
        );

        assert rd = x"00010000"
            report
                "ABI_VERSION mismatch"
            severity failure;


        axi_read(
            16#4108#,
            rd
        );

        assert rd = x"000001FF"
            report
                "CAPABILITIES mismatch"
            severity failure;


        axi_read(
            16#410C#,
            rd
        );

        assert rd = x"00000101"
            report
                "Unexpected reset STATUS"
            severity failure;


        axi_read(
            16#4120#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_LOG_W
        report
            "IMAGE_W discovery mismatch"
        severity failure;


        axi_read(
            16#4124#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_LOG_H
        report
            "IMAGE_H discovery mismatch"
        severity failure;


        axi_read(
            16#4128#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_N
        report
            "KERNEL_N discovery mismatch"
        severity failure;


        axi_read(
            16#412C#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_K
        report
            "CHANNEL_K discovery mismatch"
        severity failure;


        axi_read(
            16#4138#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_EXPECTED_INPUT_BYTES
        report
            "EXPECTED_INPUT_BYTES mismatch"
        severity failure;


        axi_read(
            16#413C#,
            rd
        );

        assert
            to_integer(unsigned(rd)) =
            C_EXPECTED_OUTPUT_BYTES
        report
            "EXPECTED_OUTPUT_BYTES mismatch"
        severity failure;


        axi_read(
            16#4160#,
            rd
        );

        assert rd = x"00000016"
            report
                "DMA_LENGTH_WIDTH is not 22"
            severity failure;


        axi_read(
            16#4150#,
            rd
        );

        assert rd = CFG_BUILD_ID(31 downto 0)
            report
                "K16 BUILD_ID word 0 mismatch"
            severity failure;


        axi_read(
            16#4154#,
            rd
        );

        assert rd = CFG_BUILD_ID(63 downto 32)
            report
                "K16 BUILD_ID word 1 mismatch"
            severity failure;


        axi_read(
            16#4158#,
            rd
        );

        assert rd = CFG_BUILD_ID(95 downto 64)
            report
                "K16 BUILD_ID word 2 mismatch"
            severity failure;


        axi_read(
            16#415C#,
            rd
        );

        assert rd = CFG_BUILD_ID(127 downto 96)
            report
                "K16 BUILD_ID word 3 mismatch"
            severity failure;


        -- ------------------------------------------------------------
        -- Offer legal-looking input BEFORE START.
        --
        -- It must not handshake.
        -- ------------------------------------------------------------

        wait until falling_edge(clk);

        s_axis_tdata <=
            x"0101010101010101";

        s_axis_tkeep <=
            x"FF";

        s_axis_tlast <=
            '0';

        s_axis_tvalid <=
            '1';


        for cycle in 1 to 5 loop

            wait until rising_edge(clk);
            wait for 1 ns;


            assert s_axis_tready = '0'
                report
                    "Input was admitted before START"
                severity failure;

        end loop;


        wait until falling_edge(clk);

        s_axis_tvalid <=
            '0';

        s_axis_tdata <=
            (others => '0');

        s_axis_tkeep <=
            (others => '0');


        report
            "--- WRAPPER A PASS ---";


        -- ====================================================================
        -- B. COMPLETE PARAMETER ADMISSION
        -- ====================================================================

        report
            "--- WRAPPER B: complete parameter admission ---";


        program_all_channels;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(7) = '1'
            report
                "PARAM_COMPLETE did not assert"
            severity failure;


        axi_read(
            16#0000#,
            rd
        );

        assert rd = coefficient_word(0,0)
            report
                "Channel 0 coefficient readback mismatch"
            severity failure;


        axi_read(
            (C_K - 1) * 16#100# + (C_COEFF_WORDS - 1) * 4,
            rd
        );

        assert rd = coefficient_word(C_K-1, C_COEFF_WORDS-1)
            report
                "Final channel coefficient tail readback mismatch"
            severity failure;


        report
            "--- WRAPPER B PASS ---";


        -- ====================================================================
        -- C. FIRST COMPLETE END-TO-END FRAME
        -- ====================================================================

        report
            "--- WRAPPER C: full real-chain frame under backpressure ---";


        input_stalls_before :=
            input_stall_count;

        output_stalls_before :=
            output_stall_count;


        output_ready_mode <=
            2;


        axi_write(
            16#4110#,
            x"00000001"
        );

        start_command_time <= now;


        send_full_input_frame;


        wait_for_success(
            1
        );


        check_success_counters;


        assert
            input_stall_count >
            input_stalls_before
        report
            "Full wrapper regression never exercised input backpressure"
        severity failure;


        assert
            output_stall_count >
            output_stalls_before
        report
            "Full wrapper regression never exercised output backpressure"
        severity failure;


        report
            "--- WRAPPER C PASS ---";


        -- ====================================================================
        -- D. REPEATED SUCCESSFUL FRAME — NO RESET
        -- ====================================================================

        report
            "--- WRAPPER D: repeated START with NO RESET ---";

        -- Sustained input bandwidth and no sink backpressure: once the first
        -- output appears, every subsequent clock must deliver the next beat.
        output_ready_mode <= 1;
        continuous_frame <= '1';


        axi_write(
            16#4110#,
            x"00000001"
        );

        start_command_time <= now;


        send_full_input_frame;


        wait_for_success(
            2
        );


        check_success_counters;


        report
            "--- WRAPPER D PASS: repeated full chain works WITHOUT RESET ---";
        continuous_frame <= '0';


        -- ====================================================================
        -- E. MALFORMED INPUT -> FRAME FAULT
        --
        -- First beat is accepted physically with four asserted TKEEP lanes,
        -- but it is illegal because a non-final beat must be FF.
        --
        -- Frontend contract:
        --   * four accepted physical bytes count
        --   * malformed beat is NOT released as pixels
        --   * INPUT_FRAME_ERROR faults the controller
        -- ====================================================================

        report
            "--- WRAPPER E: malformed input framing -> FAULT ---";


        output_ready_mode <=
            1;


        axi_write(
            16#4110#,
            x"00000001"
        );

        start_command_time <= now;


        send_input_beat(
            x"0101010101010101",
            x"0F",
            '0'
        );


        wait_for_fault_quiescent;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(0) = '0'
            report
                "Malformed frame incorrectly reported IDLE"
            severity failure;

        assert rd(1) = '1'
            report
                "Malformed frame FAULT did not report BUSY"
            severity failure;

        assert rd(4) = '0'
            report
                "Malformed frame incorrectly asserted DONE"
            severity failure;

        assert rd(5) = '1'
            report
                "Malformed frame did not assert ERROR"
            severity failure;

        assert rd(6) = '1'
            report
                "Malformed frame did not enter FAULT"
            severity failure;

        assert rd(8) = '1'
            report
                "Malformed empty-output fault did not become QUIESCENT"
            severity failure;


        axi_read(
            16#4118#,
            rd
        );


        assert rd(6) = '1'
            report
                "INPUT_FRAME_ERROR flag missing"
            severity failure;


        axi_read(
            16#4140#,
            rd
        );


        assert
            to_integer(unsigned(rd)) = 4
        report
            "Malformed physical input bytes were not counted as four"
        severity failure;


        axi_read(
            16#4144#,
            rd
        );


        assert rd = x"00000000"
            report
                "Malformed beat was incorrectly released as pixels"
            severity failure;


        axi_read(
            16#4148#,
            rd
        );


        assert rd = x"00000000"
            report
                "Malformed beat incorrectly produced a core result"
            severity failure;


        axi_read(
            16#414C#,
            rd
        );


        assert rd = x"00000000"
            report
                "Malformed beat incorrectly produced external output"
            severity failure;


        -- ------------------------------------------------------------
        -- Safe RESET from quiescent FAULT.
        -- ------------------------------------------------------------

        clear_output_partial_monitor;


        axi_write(
            16#4110#,
            x"00000002"
        );


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(0) = '1'
            report
                "Malformed-frame RESET did not return IDLE"
            severity failure;

        assert rd(5) = '0'
            report
                "Malformed-frame RESET did not clear ERROR"
            severity failure;

        assert rd(6) = '0'
            report
                "Malformed-frame RESET did not clear FAULT"
            severity failure;

        assert rd(7) = '1'
            report
                "Malformed-frame RESET lost PARAM_COMPLETE"
            severity failure;

        assert rd(8) = '1'
            report
                "Malformed-frame RESET did not restore QUIESCENT"
            severity failure;


        report
            "--- WRAPPER E PASS ---";


        -- ====================================================================
        -- F. ABORT WITH REAL SERIALIZER OUTPUT STALLED
        -- ====================================================================

        report
            "--- WRAPPER F: ABORT while queued output is externally stalled ---";


        output_ready_mode <=
            0;


        axi_write(
            16#4110#,
            x"00000001"
        );

        start_command_time <= now;


        -- C_FIRST_OUTPUT_MIN_BEATS whole input beats: just enough accepted
        -- pixels ((N-1) padded rows plus one window row) for the compiled
        -- geometry's window generator to produce initial convolution
        -- results, but nowhere near a complete frame.
        send_full_input_beats(
            C_FIRST_OUTPUT_MIN_BEATS
        );


        -- Wait until the real serializer is visibly offering output.
        while m_axis_tvalid = '0' loop

            wait until rising_edge(clk);

        end loop;


        wait for 1 ns;


        held_abort_data :=
            m_axis_tdata;

        held_abort_keep :=
            m_axis_tkeep;

        held_abort_last :=
            m_axis_tlast;


        assert held_abort_keep = x"FF"
            report
                "Unexpected partial output beat before ABORT"
            severity failure;

        assert held_abort_last = '0'
            report
                "Partial frame unexpectedly offered TLAST before ABORT"
            severity failure;


        -- Keep it stalled for several clocks before ABORT.
        for cycle in 1 to 3 loop

            wait until rising_edge(clk);
            wait for 1 ns;


            assert m_axis_tvalid = '1'
                report
                    "Offered output disappeared before ABORT"
                severity failure;

            assert m_axis_tdata = held_abort_data
                report
                    "Output changed while stalled before ABORT"
                severity failure;

            assert m_axis_tkeep = held_abort_keep
                report
                    "TKEEP changed while stalled before ABORT"
                severity failure;

            assert m_axis_tlast = held_abort_last
                report
                    "TLAST changed while stalled before ABORT"
                severity failure;

        end loop;


        -- ------------------------------------------------------------
        -- ABORT while that external beat is still stalled.
        -- ------------------------------------------------------------

        axi_write(
            16#4110#,
            x"00000004"
        );


        wait until rising_edge(clk);
        wait for 1 ns;


        assert m_axis_tvalid = '1'
            report
                "ABORT retracted already-offered external TVALID"
            severity failure;

        assert m_axis_tdata = held_abort_data
            report
                "ABORT changed already-offered external TDATA"
            severity failure;

        assert m_axis_tkeep = held_abort_keep
            report
                "ABORT changed already-offered external TKEEP"
            severity failure;

        assert m_axis_tlast = held_abort_last
            report
                "ABORT changed already-offered external TLAST"
            severity failure;


        -- While output is still blocked, FAULT must NOT claim QUIESCENT.
        axi_read(
            16#410C#,
            rd
        );


        assert rd(1) = '1'
            report
                "ABORT FAULT did not report BUSY"
            severity failure;

        assert rd(4) = '0'
            report
                "ABORT incorrectly asserted DONE"
            severity failure;

        assert rd(5) = '1'
            report
                "ABORT did not assert ERROR"
            severity failure;

        assert rd(6) = '1'
            report
                "ABORT did not enter FAULT"
            severity failure;

        assert rd(8) = '0'
            report
                "FAULT incorrectly claimed QUIESCENT with stalled TVALID"
            severity failure;


        axi_read(
            16#4118#,
            rd
        );


        assert rd(8) = '1'
            report
                "ABORTED flag missing"
            severity failure;


        -- ------------------------------------------------------------
        -- Release the external output.
        --
        -- Wrapper must NOT mask TVALID in FAULT. Queued serializer words
        -- continue to drain normally.
        -- ------------------------------------------------------------

        output_ready_mode <=
            1;


        wait_for_fault_quiescent;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(3) = '0'
            report
                "Aborted partial frame incorrectly asserted OUTPUT_DRAINED"
            severity failure;

        assert rd(4) = '0'
            report
                "Aborted partial frame incorrectly asserted DONE"
            severity failure;

        assert rd(6) = '1'
            report
                "FAULT disappeared before RESET"
            severity failure;

        assert rd(8) = '1'
            report
                "FAULT did not become QUIESCENT after queued output drained"
            severity failure;


        axi_read(
            16#414C#,
            rd
        );


        assert
            to_integer(unsigned(rd)) > 0
        report
            "Queued output did not drain/count after ABORT"
        severity failure;


        assert
            to_integer(unsigned(rd)) <
            C_EXPECTED_OUTPUT_BYTES
        report
            "Aborted partial frame somehow counted a full output frame"
        severity failure;


        report
            "--- WRAPPER F PASS ---";


        -- ====================================================================
        -- G. RESET RECOVERY AFTER ABORT
        -- ====================================================================

        report
            "--- WRAPPER G: RESET recovery after ABORT ---";


        -- Partial aborted output must not contaminate the next TB-side
        -- complete-frame beat count.
        clear_output_partial_monitor;


        axi_write(
            16#4110#,
            x"00000002"
        );


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(0) = '1'
            report
                "Recovery RESET did not return IDLE"
            severity failure;

        assert rd(1) = '0'
            report
                "Recovery RESET left BUSY set"
            severity failure;

        assert rd(2) = '0'
            report
                "Recovery RESET did not clear CORE_COMPLETE"
            severity failure;

        assert rd(3) = '0'
            report
                "Recovery RESET did not clear OUTPUT_DRAINED"
            severity failure;

        assert rd(4) = '0'
            report
                "Recovery RESET did not clear DONE"
            severity failure;

        assert rd(5) = '0'
            report
                "Recovery RESET did not clear ERROR"
            severity failure;

        assert rd(6) = '0'
            report
                "Recovery RESET did not clear FAULT"
            severity failure;

        assert rd(7) = '1'
            report
                "Recovery RESET lost parameter admission"
            severity failure;

        assert rd(8) = '1'
            report
                "Recovery RESET did not restore QUIESCENT"
            severity failure;


        axi_read(
            16#4118#,
            rd
        );


        assert rd = x"00000000"
            report
                "Recovery RESET did not clear ERROR_FLAGS"
            severity failure;


        -- Parameter storage must survive local RESET.
        axi_read(
            16#0000#,
            rd
        );


        assert rd = coefficient_word(0, 0)
            report
                "Recovery RESET corrupted parameter storage"
            severity failure;


        report
            "--- WRAPPER G PASS ---";


        -- ====================================================================
        -- H. COMPLETE POST-RECOVERY FRAME
        -- ====================================================================

        report
            "--- WRAPPER H: post-recovery full end-to-end frame ---";


        output_ready_mode <=
            2;


        axi_write(
            16#4110#,
            x"00000001"
        );

        start_command_time <= now;


        send_full_input_frame;


        wait_for_success(
            3
        );


        check_success_counters;


        report
            "--- WRAPPER H PASS ---";


        -- ====================================================================
        -- FINAL
        -- ====================================================================

        assert output_success_frames = 3
            report
                "Unexpected total number of successful external frames"
            severity failure;


        report
            "============================================================";

        report
            " CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS ";

        report
            "============================================================";


        finish;
        wait;

    end process stim_proc;


    -- ========================================================================
    -- Timeout
    -- ========================================================================

    timeout_proc : process
    begin

        -- Geometry-scaled hang detector: worst case is the stress fixture
        -- (up to ~64 idle cycles per input beat) over all regression frames.
        -- The K16/N3 32x32 profile therefore keeps a margin above its
        -- historical fixed 2 ms; large frames (D640) scale up accordingly.
        wait for C_EXPECTED_INPUT_BYTES * 512 * CLK_PERIOD;


        assert false
            report
                "conv_axis_wrapper comprehensive regression timed out"
            severity failure;


        wait;

    end process timeout_proc;


end architecture sim;
