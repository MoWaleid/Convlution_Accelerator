library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;


entity tb_axi_stream_input_frontend is
end entity;


architecture sim of tb_axi_stream_input_frontend is

    constant CLK_PERIOD : time := 10 ns;

    -- Small enough for fast simulation, large enough to fill the FIFO.
    -- 68 = 8 full 64-bit beats + one final 4-byte beat.
    constant C_FIFO_DEPTH           : positive := 4;
    constant C_EXPECTED_INPUT_BYTES : positive := 68;


    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal start_pulse : std_logic := '0';
    signal run_enable  : std_logic := '0';


    signal s_axis_tdata :
        std_logic_vector(63 downto 0) := (others => '0');

    signal s_axis_tkeep :
        std_logic_vector(7 downto 0) := (others => '0');

    signal s_axis_tvalid :
        std_logic := '0';

    signal s_axis_tready :
        std_logic;

    signal s_axis_tlast :
        std_logic := '0';


    signal out_pixel :
        std_logic_vector(7 downto 0);

    signal out_valid :
        std_logic;

    signal out_ready :
        std_logic := '0';

    signal out_last :
        std_logic;


    signal input_accept_valid :
        std_logic;

    signal input_accept_bytes :
        std_logic_vector(3 downto 0);

    signal input_frame_error :
        std_logic;

    signal input_consumed_pulse :
        std_logic;


    -- Event-scoreboard counters.
    signal accept_event_count :
        natural := 0;

    signal accept_byte_sum :
        natural := 0;

    signal frame_error_count :
        natural := 0;

    signal consumed_event_count :
        natural := 0;

    signal output_handshake_count :
        natural := 0;


    function make_beat(
        base_value : natural
    ) return std_logic_vector is

        variable result :
            std_logic_vector(63 downto 0) := (others => '0');

    begin

        for lane in 0 to 7 loop

            result(
                (lane + 1) * 8 - 1 downto lane * 8
            ) :=
                std_logic_vector(
                    to_unsigned(
                        (base_value + lane) mod 256,
                        8
                    )
                );

        end loop;

        return result;

    end function;


begin

    -- ========================================================================
    -- Clock
    -- ========================================================================

    clk <= not clk after CLK_PERIOD / 2;


    -- ========================================================================
    -- DUT
    -- ========================================================================

    dut :
        entity work.axi_stream_input_frontend
        generic map (
            C_FIFO_DEPTH =>
                C_FIFO_DEPTH,

            C_EXPECTED_INPUT_BYTES =>
                C_EXPECTED_INPUT_BYTES
        )
        port map (
            clk =>
                clk,

            resetn =>
                resetn,

            start_pulse =>
                start_pulse,

            run_enable =>
                run_enable,

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

            out_pixel =>
                out_pixel,

            out_valid =>
                out_valid,

            out_ready =>
                out_ready,

            out_last =>
                out_last,

            accept_valid =>
    input_accept_valid,

accept_bytes =>
    input_accept_bytes,

frame_error =>
    input_frame_error,

consumed_pulse =>
    input_consumed_pulse
        );


    -- ========================================================================
    -- Event monitor
    --
    -- Works whether the frontend events are combinational handshakes or
    -- registered one-cycle pulses: totals are checked only after settling.
    -- ========================================================================

    event_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                accept_event_count     <= 0;
                accept_byte_sum        <= 0;
                frame_error_count      <= 0;
                consumed_event_count   <= 0;
                output_handshake_count <= 0;

            else

                if input_accept_valid = '1' then

                    accept_event_count <=
                        accept_event_count + 1;

                    accept_byte_sum <=
                        accept_byte_sum +
                        to_integer(
                            unsigned(input_accept_bytes)
                        );

                end if;


                if input_frame_error = '1' then

                    frame_error_count <=
                        frame_error_count + 1;

                end if;


                if input_consumed_pulse = '1' then

                    consumed_event_count <=
                        consumed_event_count + 1;

                end if;


                if out_valid = '1' and out_ready = '1' then

                    output_handshake_count <=
                        output_handshake_count + 1;

                end if;

            end if;

        end if;

    end process;


    -- ========================================================================
    -- Main comprehensive regression
    -- ========================================================================

    stim_proc : process

        ------------------------------------------------------------------------
        -- Hard reset and return to stopped state.
        ------------------------------------------------------------------------

        procedure hard_reset is
        begin

            run_enable  <= '0';
            start_pulse <= '0';

            s_axis_tvalid <= '0';
            s_axis_tlast  <= '0';
            s_axis_tkeep  <= (others => '0');
            s_axis_tdata  <= (others => '0');

            out_ready <= '0';

            resetn <= '0';

            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait until rising_edge(clk);

            wait until falling_edge(clk);

            resetn <= '1';

            wait until rising_edge(clk);
            wait for 1 ns;


            assert s_axis_tready = '0'
                report "TREADY asserted while RUN was disabled"
                severity failure;

        end procedure;


        ------------------------------------------------------------------------
        -- START a fresh frontend frame.
        --
        -- In the integrated design START and RUN become active together.
        ------------------------------------------------------------------------

        procedure begin_frame is
        begin

            wait until falling_edge(clk);

            start_pulse <= '1';
            run_enable  <= '1';

            wait until rising_edge(clk);
            wait for 1 ns;

            start_pulse <= '0';

            wait until falling_edge(clk);
            wait for 1 ns;


            assert s_axis_tready = '1'
                report "TREADY did not open after START"
                severity failure;

        end procedure;


        ------------------------------------------------------------------------
        -- Send one external AXI beat.
        ------------------------------------------------------------------------

        procedure send_beat(
            constant data :
                in std_logic_vector(63 downto 0);

            constant keep :
                in std_logic_vector(7 downto 0);

            constant last :
                in std_logic
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
            s_axis_tlast  <= '0';
            s_axis_tkeep  <= (others => '0');

        end procedure;


        ------------------------------------------------------------------------
        -- Consume and verify an ordered run of output pixels.
        ------------------------------------------------------------------------

        procedure consume_pixels(
            constant base_value :
                in natural;

            constant count :
                in positive;

            constant final_pixel_is_last :
                in boolean
        ) is

            variable expected :
                std_logic_vector(7 downto 0);

        begin

            out_ready <= '1';


            for index in 0 to count - 1 loop

                loop

                    wait until falling_edge(clk);

                    exit when out_valid = '1';

                end loop;


                expected :=
                    std_logic_vector(
                        to_unsigned(
                            (base_value + index) mod 256,
                            8
                        )
                    );


                assert out_pixel = expected
                    report "Frontend byte ordering/value mismatch"
                    severity failure;


                if final_pixel_is_last and
                   index = count - 1 then

                    assert out_last = '1'
                        report "Final valid input byte did not assert out_last"
                        severity failure;

                else

                    assert out_last = '0'
                        report "out_last asserted before final valid byte"
                        severity failure;

                end if;


                wait until rising_edge(clk);

            end loop;


            wait for 1 ns;

        end procedure;


        ------------------------------------------------------------------------
        -- Wait a few cycles for registered event pulses/counters to settle.
        ------------------------------------------------------------------------

        procedure settle_events is
        begin

            wait until rising_edge(clk);
            wait until rising_edge(clk);
            wait for 1 ns;

        end procedure;


        variable held_pixel :
            std_logic_vector(7 downto 0);

        variable held_last :
            std_logic;

        variable accepted_before :
            natural;

    begin

        -- ====================================================================
        -- A. RESET / START / RUN GATING
        -- ====================================================================

        report
            "--- INPUT FRONTEND A: reset + START/RUN gating ---";


        hard_reset;


        -- Offer a perfectly valid beat before START.
        -- It must simply wait; nothing may be accepted.
        wait until falling_edge(clk);

        s_axis_tdata  <= make_beat(0);
        s_axis_tkeep  <= x"FF";
        s_axis_tlast  <= '0';
        s_axis_tvalid <= '1';


        for cycle in 1 to 3 loop

            wait until rising_edge(clk);

            assert s_axis_tready = '0'
                report "Frontend accepted input before START/RUN"
                severity failure;

        end loop;


        wait until falling_edge(clk);

        s_axis_tvalid <= '0';

        settle_events;


        assert accept_event_count = 0
            report "Input acceptance event occurred before START"
            severity failure;

        assert accept_byte_sum = 0
            report "Input byte counter moved before START"
            severity failure;


        report
            "--- INPUT FRONTEND A PASS ---";


        -- ====================================================================
        -- B. COMPLETE LEGAL FRAME
        --
        -- 8 * 8 + 4 = 68 bytes.
        -- ====================================================================

        report
            "--- INPUT FRONTEND B: legal frame + exact quota ---";


        begin_frame;

        out_ready <= '1';


        for beat in 0 to 7 loop

            send_beat(
                make_beat(beat * 8),
                x"FF",
                '0'
            );

            consume_pixels(
                beat * 8,
                8,
                false
            );

        end loop;


        -- Exact final beat:
        --
        -- bytes 64..67
        -- TKEEP = 00001111
        -- TLAST = 1
        send_beat(
            make_beat(64),
            x"0F",
            '1'
        );

        consume_pixels(
            64,
            4,
            true
        );


        settle_events;


        assert accept_event_count = 9
            report "Legal frame accepted wrong number of AXI beats"
            severity failure;

        assert accept_byte_sum = 68
            report "Legal frame physical accepted-byte total was not 68"
            severity failure;

        assert frame_error_count = 0
            report "Legal frame incorrectly raised INPUT_FRAME_ERROR"
            severity failure;

        assert output_handshake_count = 68
            report "Legal frame emitted wrong number of pixels"
            severity failure;

        assert consumed_event_count = 68
            report "input_consumed_pulse total did not match 68 pixels"
            severity failure;


        -- Quota is exhausted. TREADY must close.
        wait until falling_edge(clk);
        wait for 1 ns;


        assert s_axis_tready = '0'
            report "TREADY remained high after exact input quota"
            severity failure;


        -- Extra beat must NOT be accepted or counted.
        accepted_before := accept_event_count;

        s_axis_tdata  <= make_beat(100);
        s_axis_tkeep  <= x"FF";
        s_axis_tlast  <= '0';
        s_axis_tvalid <= '1';


        for cycle in 1 to 3 loop

            wait until rising_edge(clk);

            assert s_axis_tready = '0'
                report "Frontend accepted an extra post-quota beat"
                severity failure;

        end loop;


        wait until falling_edge(clk);

        s_axis_tvalid <= '0';

        settle_events;


        assert accept_event_count = accepted_before
            report "Extra post-quota beat changed acceptance count"
            severity failure;

        assert accept_byte_sum = 68
            report "Extra post-quota beat changed accepted-byte total"
            severity failure;


        report
            "--- INPUT FRONTEND B PASS ---";


        -- ====================================================================
        -- C. REPEATED START WITHOUT RESET
        --
        -- START must reopen the quota.
        -- ====================================================================

        report
            "--- INPUT FRONTEND C: repeated START quota reset ---";


        begin_frame;


        assert s_axis_tready = '1'
            report "Repeated START failed to reopen input quota"
            severity failure;


        send_beat(
            make_beat(128),
            x"FF",
            '0'
        );

        consume_pixels(
            128,
            8,
            false
        );


        report
            "--- INPUT FRONTEND C PASS ---";


        -- Clear this intentionally incomplete isolated frame.
        hard_reset;


        -- ====================================================================
        -- D. OUTPUT STALL STABILITY
        -- ====================================================================

        report
            "--- INPUT FRONTEND D: output stall stability ---";


        begin_frame;

        out_ready <= '0';


        send_beat(
            make_beat(32),
            x"FF",
            '0'
        );


        -- Wait until byte 32 reaches the unpacker.
        loop

            wait until falling_edge(clk);

            exit when out_valid = '1';

        end loop;


        held_pixel := out_pixel;
        held_last  := out_last;


        assert held_pixel = x"20"
            report "First stalled output pixel was incorrect"
            severity failure;

        assert held_last = '0'
            report "Nonfinal stalled beat incorrectly asserted out_last"
            severity failure;


        -- It must remain completely stable until accepted.
        for stalled_cycle in 1 to 4 loop

            wait until falling_edge(clk);

            assert out_valid = '1'
                report "out_valid dropped while output was stalled"
                severity failure;

            assert out_pixel = held_pixel
                report "out_pixel changed while output was stalled"
                severity failure;

            assert out_last = held_last
                report "out_last changed while output was stalled"
                severity failure;

        end loop;


       -- Release the already-visible stalled pixel 32.
        out_ready <= '1';

wait until rising_edge(clk);
wait for 1 ns;

-- Pixel 32 has now handshaken; verify the remaining seven bytes.
consume_pixels(
    33,
    7,
    false
);

        settle_events;


        assert consumed_event_count = 8
            report "Stalled beat did not produce exactly eight consume events"
            severity failure;


        report
            "--- INPUT FRONTEND D PASS ---";


        hard_reset;


        -- ====================================================================
        -- E. PREMATURE TLAST
        --
        -- Malformed beat is physically accepted and counted,
        -- INPUT_FRAME_ERROR is raised,
        -- but the beat must NOT enter the pixel pipeline.
        -- ====================================================================

        report
            "--- INPUT FRONTEND E: premature TLAST rejection ---";


        begin_frame;

        out_ready <= '1';


        send_beat(
            make_beat(0),
            x"FF",
            '1'
        );


        settle_events;


        assert accept_event_count = 1
            report "Premature-TLAST beat was not physically accepted"
            severity failure;

        assert accept_byte_sum = 8
            report "Premature-TLAST physical-byte count was not eight"
            severity failure;

        assert frame_error_count = 1
            report "Premature TLAST did not raise INPUT_FRAME_ERROR"
            severity failure;

        assert output_handshake_count = 0
            report "Malformed premature-TLAST beat leaked pixels"
            severity failure;

        assert consumed_event_count = 0
            report "Malformed premature-TLAST beat was consumed by core side"
            severity failure;


        report
            "--- INPUT FRONTEND E PASS ---";


        hard_reset;


        -- ====================================================================
        -- F. PARTIAL NONFINAL TKEEP
        -- ====================================================================

        report
            "--- INPUT FRONTEND F: partial nonfinal TKEEP rejection ---";


        begin_frame;

        out_ready <= '1';


        send_beat(
            make_beat(0),
            x"0F",
            '0'
        );


        settle_events;


        assert accept_event_count = 1
            report "Malformed partial beat was not physically accepted"
            severity failure;

        assert accept_byte_sum = 4
            report "Malformed partial beat physical-byte count was not four"
            severity failure;

        assert frame_error_count = 1
            report "Partial nonfinal TKEEP did not raise frame error"
            severity failure;

        assert output_handshake_count = 0
            report "Malformed partial nonfinal beat leaked pixels"
            severity failure;


        report
            "--- INPUT FRONTEND F PASS ---";


        hard_reset;


        -- ====================================================================
        -- G. MALFORMED FINAL TKEEP
        --
        -- First 64 bytes are valid.
        -- Final beat should be x0F, but we present non-contiguous x05.
        -- Physical accepted bytes = 64 + 2 = 66.
        -- Malformed final beat must not be released as pixels.
        -- ====================================================================

        report
            "--- INPUT FRONTEND G: malformed final TKEEP ---";


        begin_frame;

        out_ready <= '1';


        for beat in 0 to 7 loop

            send_beat(
                make_beat(beat * 8),
                x"FF",
                '0'
            );

            consume_pixels(
                beat * 8,
                8,
                false
            );

        end loop;


        send_beat(
            make_beat(64),
            x"05",
            '1'
        );


        settle_events;


        assert accept_event_count = 9
            report "Malformed-final test accepted wrong number of beats"
            severity failure;

        assert accept_byte_sum = 66
            report "Malformed-final physical-byte count was not 66"
            severity failure;

        assert frame_error_count = 1
            report "Non-contiguous final TKEEP did not raise frame error"
            severity failure;

        assert output_handshake_count = 64
            report "Malformed final beat leaked output pixels"
            severity failure;

        assert consumed_event_count = 64
            report "Malformed final beat leaked consume events"
            severity failure;


        report
            "--- INPUT FRONTEND G PASS ---";


        hard_reset;


        -- ====================================================================
        -- H. MISSING FINAL TLAST
        -- ====================================================================

        report
            "--- INPUT FRONTEND H: missing final TLAST ---";


        begin_frame;

        out_ready <= '1';


        for beat in 0 to 7 loop

            send_beat(
                make_beat(beat * 8),
                x"FF",
                '0'
            );

            consume_pixels(
                beat * 8,
                8,
                false
            );

        end loop;


        -- Byte quota/keep are correct, but TLAST is missing.
        send_beat(
            make_beat(64),
            x"0F",
            '0'
        );


        settle_events;


        assert accept_event_count = 9
            report "Missing-TLAST test accepted wrong beat count"
            severity failure;

        assert accept_byte_sum = 68
            report "Missing-TLAST test physical-byte count was not 68"
            severity failure;

        assert frame_error_count = 1
            report "Missing final TLAST did not raise frame error"
            severity failure;

        assert output_handshake_count = 64
            report "Missing-TLAST final beat leaked pixels"
            severity failure;


        report
            "--- INPUT FRONTEND H PASS ---";


        hard_reset;


        -- ====================================================================
        -- I. FIFO FULL / AXI BACKPRESSURE
        --
        -- out_ready=0 leaves one active beat plus four FIFO entries.
        -- The sixth offered beat must stall until downstream progress occurs.
        -- ====================================================================

        report
            "--- INPUT FRONTEND I: FIFO-full AXI backpressure ---";


        begin_frame;

        out_ready <= '0';


        -- One beat can become active; four more fill C_FIFO_DEPTH=4.
        for beat in 0 to 4 loop

            send_beat(
                make_beat(beat * 8),
                x"FF",
                '0'
            );

        end loop;


        settle_events;


        assert accept_event_count = 5
            report "FIFO-full setup did not accept five beats"
            severity failure;

        assert accept_byte_sum = 40
            report "FIFO-full setup accepted-byte sum was not 40"
            severity failure;


        -- Sixth beat is now held by the source.
        wait until falling_edge(clk);

        s_axis_tdata  <= make_beat(40);
        s_axis_tkeep  <= x"FF";
        s_axis_tlast  <= '0';
        s_axis_tvalid <= '1';


        for stalled_cycle in 1 to 3 loop

            wait until rising_edge(clk);

            assert s_axis_tready = '0'
                report "TREADY did not deassert with active beat + full FIFO"
                severity failure;

        end loop;


        -- Release the downstream. Eventually FIFO space appears and the held
        -- sixth beat must be accepted without changing the source beat.
        wait until falling_edge(clk);

        out_ready <= '1';


        loop

            wait until rising_edge(clk);

            exit when s_axis_tready = '1';

        end loop;


        wait until falling_edge(clk);

        s_axis_tvalid <= '0';

        settle_events;


        assert accept_event_count = 6
            report "Held beat was not accepted after backpressure released"
            severity failure;

        assert accept_byte_sum = 48
            report "Backpressure test accepted-byte total was not 48"
            severity failure;

        assert frame_error_count = 0
            report "Valid backpressure traffic generated frame error"
            severity failure;


        report
            "--- INPUT FRONTEND I PASS ---";


        hard_reset;


        -- ====================================================================
        -- J. RUN DISABLE CLOSES EXTERNAL INPUT
        -- ====================================================================

        report
            "--- INPUT FRONTEND J: RUN disable ---";


        begin_frame;

        out_ready <= '0';


        send_beat(
            make_beat(0),
            x"FF",
            '0'
        );


        -- Let the accepted beat become active.
        loop

            wait until falling_edge(clk);

            exit when out_valid = '1';

        end loop;


        held_pixel := out_pixel;


        -- Stop RUN while downstream also remains stalled.
        run_enable <= '0';


        for frozen_cycle in 1 to 4 loop

            wait until falling_edge(clk);

            assert s_axis_tready = '0'
                report "TREADY remained asserted after RUN disable"
                severity failure;

            if out_valid = '1' then

                assert out_pixel = held_pixel
                    report "Frontend lane state advanced while RUN disabled"
                    severity failure;

            end if;

        end loop;


        report
            "--- INPUT FRONTEND J PASS ---";


        -- ====================================================================
        -- FINAL
        -- ====================================================================

        report
            "============================================================";

        report
            " AXI_STREAM_INPUT_FRONTEND COMPLETE UNIT REGRESSION PASS ";

        report
            "============================================================";


        finish;
        wait;

    end process;


    -- ========================================================================
    -- Timeout
    -- ========================================================================

    timeout_proc : process
    begin

        wait for 100 us;

        assert false
            report "AXI stream input frontend comprehensive regression timed out"
            severity failure;

        wait;

    end process;


end architecture;