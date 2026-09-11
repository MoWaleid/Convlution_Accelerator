-- ============================================================================
-- tb_axi_stream_output_serializer.vhd
--
-- M4 comprehensive unit regression for axi_stream_output_serializer.
--
-- Coverage:
--   A. K=6 signed packing / ordering / TKEEP / TLAST
--   B. AXIS stall stability / core_accept_pulse / fifo_empty
--   C. K=16 sustained formatter throughput + FIFO backpressure
--   D. Queued FIFO output drains while production_enable = 0
--   E. Partial formatter state freezes while production_enable = 0
--   F. fifo_empty intentionally excludes frozen partial formatter state
--   G. RESET discards frozen partial state and clean recovery follows
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

    signal clk : std_logic := '0';


    -- ========================================================================
    -- DUT A/B: K=6 ordinary packing + stalls
    --
    -- 3 positions * 6 scalars = 18 scalars
    -- => four full 64-bit beats + one final two-scalar beat.
    -- ========================================================================

    constant C_MAIN_K      : positive := 6;
    constant C_MAIN_W      : positive := 3;
    constant C_MAIN_H      : positive := 1;
    constant C_MAIN_POS    : positive := C_MAIN_W * C_MAIN_H;
    constant C_MAIN_SCALARS:
        positive := C_MAIN_K * C_MAIN_POS;

    constant C_MAIN_FULL_BEATS :
        natural := C_MAIN_SCALARS / 4;


    signal main_resetn :
        std_logic := '0';

    signal main_production_enable :
        std_logic;

    signal main_results :
        output_array_t(0 to C_MAIN_K - 1) :=
            (others => (others => '0'));

    signal main_in_valid :
        std_logic := '0';

    signal main_in_ready :
        std_logic;

    signal main_core_accept_pulse :
        std_logic;

    signal main_fifo_empty :
        std_logic;

    signal main_tdata :
        std_logic_vector(63 downto 0);

    signal main_tkeep :
        std_logic_vector(7 downto 0);

    signal main_tvalid :
        std_logic;

    signal main_tready :
        std_logic := '0';

    signal main_tlast :
        std_logic;

    signal main_input_accept_count :
        natural := 0;

    signal main_core_accept_count :
        natural := 0;

    signal main_done :
        std_logic := '0';


    -- ========================================================================
    -- DUT C: K=16 sustained formatter / FIFO backpressure
    --
    -- Six vectors * 16 scalars = 96 scalars = 24 full AXIS beats.
    -- ========================================================================

    constant C_K16 :
        positive := 16;

    constant C_K16_POS :
        positive := 6;


    signal k16_resetn :
        std_logic := '0';

    signal k16_production_enable :
        std_logic;

    signal k16_results :
        output_array_t(0 to C_K16 - 1) :=
            (others => (others => '0'));

    signal k16_in_valid :
        std_logic := '0';

    signal k16_in_ready :
        std_logic;

    signal k16_core_accept_pulse :
        std_logic;

    signal k16_fifo_empty :
        std_logic;

    signal k16_tdata :
        std_logic_vector(63 downto 0);

    signal k16_tkeep :
        std_logic_vector(7 downto 0);

    signal k16_tvalid :
        std_logic;

    signal k16_tready :
        std_logic := '0';

    signal k16_tlast :
        std_logic;

    signal k16_fill_reached :
        std_logic := '0';

    signal k16_input_done :
        std_logic := '0';

    signal k16_done :
        std_logic := '0';

    signal k16_input_accept_count :
        natural := 0;

    signal k16_core_accept_count :
        natural := 0;


    -- ========================================================================
    -- DUT D: queued output drain after production disable
    --
    -- K=8 gives exactly two full 64-bit beats for one vector.
    -- ========================================================================

    constant C_DRAIN_K :
        positive := 8;


    signal drain_resetn :
        std_logic := '0';

    signal drain_production_enable :
        std_logic := '0';

    signal drain_results :
        output_array_t(0 to C_DRAIN_K - 1) :=
            (others => (others => '0'));

    signal drain_in_valid :
        std_logic := '0';

    signal drain_in_ready :
        std_logic;

    signal drain_core_accept_pulse :
        std_logic;

    signal drain_fifo_empty :
        std_logic;

    signal drain_tdata :
        std_logic_vector(63 downto 0);

    signal drain_tkeep :
        std_logic_vector(7 downto 0);

    signal drain_tvalid :
        std_logic;

    signal drain_tready :
        std_logic := '0';

    signal drain_tlast :
        std_logic;

    signal drain_core_accept_count :
        natural := 0;

    signal drain_done :
        std_logic := '0';


    -- ========================================================================
    -- DUT E/F/G: partial formatter freeze + RESET recovery
    --
    -- K=6:
    --   first vector -> one full beat + two retained scalars.
    --
    -- production_enable is then removed.  The FIFO may become empty while
    -- those two scalars deliberately remain frozen in formatter state.
    --
    -- RESET must discard them.  A fresh two-vector frame must then produce
    -- exactly 12 fresh scalars = three full beats.
    -- ========================================================================

    constant C_FREEZE_K :
        positive := 6;


    signal freeze_resetn :
        std_logic := '0';

    signal freeze_production_enable :
        std_logic := '0';

    signal freeze_results :
        output_array_t(0 to C_FREEZE_K - 1) :=
            (others => (others => '0'));

    signal freeze_in_valid :
        std_logic := '0';

    signal freeze_in_ready :
        std_logic;

    signal freeze_core_accept_pulse :
        std_logic;

    signal freeze_fifo_empty :
        std_logic;

    signal freeze_tdata :
        std_logic_vector(63 downto 0);

    signal freeze_tkeep :
        std_logic_vector(7 downto 0);

    signal freeze_tvalid :
        std_logic;

    signal freeze_tready :
        std_logic := '1';

    signal freeze_tlast :
        std_logic;

    signal freeze_core_accept_count :
        natural := 0;

    signal freeze_done :
        std_logic := '0';


    -- ========================================================================
    -- Helpers
    -- ========================================================================

    function make_results_k6(
        base_value : integer
    ) return output_array_t is

        variable result :
            output_array_t(0 to C_MAIN_K - 1);

    begin

        for channel in 0 to C_MAIN_K - 1 loop

            result(channel) :=
                std_logic_vector(
                    to_signed(
                        base_value + channel,
                        16
                    )
                );

        end loop;

        return result;

    end function make_results_k6;


    function make_results_k16(
        base_value : integer
    ) return output_array_t is

        variable result :
            output_array_t(0 to C_K16 - 1);

    begin

        for channel in 0 to C_K16 - 1 loop

            result(channel) :=
                std_logic_vector(
                    to_signed(
                        base_value + channel,
                        16
                    )
                );

        end loop;

        return result;

    end function make_results_k16;


    function make_results_k8(
        base_value : integer
    ) return output_array_t is

        variable result :
            output_array_t(0 to C_DRAIN_K - 1);

    begin

        for channel in 0 to C_DRAIN_K - 1 loop

            result(channel) :=
                std_logic_vector(
                    to_signed(
                        base_value + channel,
                        16
                    )
                );

        end loop;

        return result;

    end function make_results_k8;


    function scalar_count_from_keep(
        keep : std_logic_vector(7 downto 0)
    ) return natural is

    begin

        case keep is

            when x"03" =>
                return 1;

            when x"0F" =>
                return 2;

            when x"3F" =>
                return 3;

            when x"FF" =>
                return 4;

            when others =>
                return 0;

        end case;

    end function scalar_count_from_keep;


begin

    -- ========================================================================
    -- Clock
    -- ========================================================================

    clk_gen : process
    begin

        loop

            clk <= '0';
            wait for CLK_PERIOD / 2;

            clk <= '1';
            wait for CLK_PERIOD / 2;

        end loop;

    end process clk_gen;


    -- ========================================================================
    -- DUT A/B
    -- ========================================================================

    main_production_enable <=
        main_resetn;


    dut_main :
        entity work.axi_stream_output_serializer
        generic map (
            C_K =>
                C_MAIN_K,

            C_IMAGE_WIDTH =>
                C_MAIN_W,

            C_IMAGE_HEIGHT =>
                C_MAIN_H,

            C_FIFO_DEPTH =>
                16
        )
        port map (
            clk =>
                clk,

            resetn =>
                main_resetn,

            production_enable =>
                main_production_enable,

            in_results =>
                main_results,

            in_valid =>
                main_in_valid,

            in_ready =>
                main_in_ready,

            core_accept_pulse =>
                main_core_accept_pulse,

            fifo_empty =>
                main_fifo_empty,

            m_axis_tdata =>
                main_tdata,

            m_axis_tkeep =>
                main_tkeep,

            m_axis_tvalid =>
                main_tvalid,

            m_axis_tready =>
                main_tready,

            m_axis_tlast =>
                main_tlast
        );


    -- ========================================================================
    -- DUT C
    -- ========================================================================

    k16_production_enable <=
        k16_resetn;


    dut_k16 :
        entity work.axi_stream_output_serializer
        generic map (
            C_K =>
                C_K16,

            C_IMAGE_WIDTH =>
                C_K16_POS,

            C_IMAGE_HEIGHT =>
                1,

            C_FIFO_DEPTH =>
                16
        )
        port map (
            clk =>
                clk,

            resetn =>
                k16_resetn,

            production_enable =>
                k16_production_enable,

            in_results =>
                k16_results,

            in_valid =>
                k16_in_valid,

            in_ready =>
                k16_in_ready,

            core_accept_pulse =>
                k16_core_accept_pulse,

            fifo_empty =>
                k16_fifo_empty,

            m_axis_tdata =>
                k16_tdata,

            m_axis_tkeep =>
                k16_tkeep,

            m_axis_tvalid =>
                k16_tvalid,

            m_axis_tready =>
                k16_tready,

            m_axis_tlast =>
                k16_tlast
        );


    -- ========================================================================
    -- DUT D
    -- ========================================================================

    dut_drain :
        entity work.axi_stream_output_serializer
        generic map (
            C_K =>
                C_DRAIN_K,

            C_IMAGE_WIDTH =>
                1,

            C_IMAGE_HEIGHT =>
                1,

            C_FIFO_DEPTH =>
                4
        )
        port map (
            clk =>
                clk,

            resetn =>
                drain_resetn,

            production_enable =>
                drain_production_enable,

            in_results =>
                drain_results,

            in_valid =>
                drain_in_valid,

            in_ready =>
                drain_in_ready,

            core_accept_pulse =>
                drain_core_accept_pulse,

            fifo_empty =>
                drain_fifo_empty,

            m_axis_tdata =>
                drain_tdata,

            m_axis_tkeep =>
                drain_tkeep,

            m_axis_tvalid =>
                drain_tvalid,

            m_axis_tready =>
                drain_tready,

            m_axis_tlast =>
                drain_tlast
        );


    -- ========================================================================
    -- DUT E/F/G
    -- ========================================================================

    dut_freeze :
        entity work.axi_stream_output_serializer
        generic map (
            C_K =>
                C_FREEZE_K,

            C_IMAGE_WIDTH =>
                2,

            C_IMAGE_HEIGHT =>
                1,

            C_FIFO_DEPTH =>
                4
        )
        port map (
            clk =>
                clk,

            resetn =>
                freeze_resetn,

            production_enable =>
                freeze_production_enable,

            in_results =>
                freeze_results,

            in_valid =>
                freeze_in_valid,

            in_ready =>
                freeze_in_ready,

            core_accept_pulse =>
                freeze_core_accept_pulse,

            fifo_empty =>
                freeze_fifo_empty,

            m_axis_tdata =>
                freeze_tdata,

            m_axis_tkeep =>
                freeze_tkeep,

            m_axis_tvalid =>
                freeze_tvalid,

            m_axis_tready =>
                freeze_tready,

            m_axis_tlast =>
                freeze_tlast
        );


    -- ========================================================================
    -- A/B reset
    -- ========================================================================

    main_reset_proc : process
    begin

        main_resetn <= '0';

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);

        main_resetn <= '1';

        wait;

    end process main_reset_proc;


    -- ========================================================================
    -- A/B deterministic pseudo-random output stalls
    -- ========================================================================

    main_ready_driver : process

        variable lfsr :
            std_logic_vector(7 downto 0) := x"A5";

        variable feedback :
            std_logic;

    begin

        wait until main_resetn = '1';


        while main_done = '0' loop

            wait until falling_edge(clk);

            feedback :=
                lfsr(7)
                xor lfsr(5)
                xor lfsr(4)
                xor lfsr(3);

            lfsr :=
                lfsr(6 downto 0)
                & feedback;

            main_tready <=
                lfsr(0)
                or lfsr(2);

        end loop;


        main_tready <= '1';

        wait;

    end process main_ready_driver;


    -- ========================================================================
    -- A/B input / core-accept event counters
    -- ========================================================================

    main_event_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if main_resetn = '0' then

                main_input_accept_count <= 0;
                main_core_accept_count  <= 0;

            else

                if
                    main_in_valid = '1'
                    and main_in_ready = '1'
                then

                    main_input_accept_count <=
                        main_input_accept_count + 1;

                end if;


                if main_core_accept_pulse = '1' then

                    main_core_accept_count <=
                        main_core_accept_count + 1;

                end if;

            end if;

        end if;

    end process main_event_monitor;


    -- ========================================================================
    -- B: AXIS payload must remain stable while stalled
    -- ========================================================================

    main_stall_monitor : process

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

        wait until main_resetn = '1';


        loop

            wait until rising_edge(clk);


            if stalled then

                assert main_tvalid = '1'
                    report
                        "MAIN: TVALID dropped while stalled"
                    severity failure;

                assert main_tdata = held_data
                    report
                        "MAIN: TDATA changed while stalled"
                    severity failure;

                assert main_tkeep = held_keep
                    report
                        "MAIN: TKEEP changed while stalled"
                    severity failure;

                assert main_tlast = held_last
                    report
                        "MAIN: TLAST changed while stalled"
                    severity failure;

            end if;


            stalled :=
                (
                    main_tvalid = '1'
                    and main_tready = '0'
                );


            if stalled then

                held_data :=
                    main_tdata;

                held_keep :=
                    main_tkeep;

                held_last :=
                    main_tlast;

            end if;


            exit when main_done = '1';

        end loop;

        wait;

    end process main_stall_monitor;


    -- ========================================================================
    -- A: K=6 source
    -- ========================================================================

    main_input_driver : process
    begin

        wait until main_resetn = '1';


        report
            "--- SERIALIZER A: K=6 packing / signed order / TKEEP / TLAST ---";


        for position in 0 to C_MAIN_POS - 1 loop

            wait until falling_edge(clk);

            main_results <=
                make_results_k6(
                    -12
                    + position * C_MAIN_K
                );

            main_in_valid <= '1';


            loop

                wait until rising_edge(clk);

                exit when main_in_ready = '1';

            end loop;


            wait until falling_edge(clk);

            main_in_valid <= '0';

        end loop;


        wait;

    end process main_input_driver;


    -- ========================================================================
    -- A: K=6 output checker
    -- ========================================================================

    main_output_monitor : process

        variable scalar_index :
            natural := 0;

        variable beat_index :
            natural := 0;

        variable scalar_count :
            natural;

        variable last_count :
            natural := 0;

        variable expected_scalar :
            std_logic_vector(15 downto 0);

    begin

        wait until main_resetn = '1';


        loop

            wait until rising_edge(clk);


            if
                main_tvalid = '1'
                and main_tready = '1'
            then

                scalar_count :=
                    scalar_count_from_keep(
                        main_tkeep
                    );


                assert scalar_count /= 0
                    report
                        "MAIN: invalid TKEEP"
                    severity failure;


                if beat_index < C_MAIN_FULL_BEATS then

                    assert main_tkeep = x"FF"
                        report
                            "MAIN: premature partial TKEEP"
                        severity failure;

                else

                    assert main_tkeep = x"0F"
                        report
                            "MAIN: final K=6 beat must contain two scalars"
                        severity failure;

                end if;


                for lane in 0 to scalar_count - 1 loop

                    expected_scalar :=
                        std_logic_vector(
                            to_signed(
                                -12
                                + integer(scalar_index),
                                16
                            )
                        );


                    assert
                        main_tdata(
                            (lane + 1) * 16 - 1
                            downto lane * 16
                        ) = expected_scalar

                        report
                            "MAIN: scalar ordering / signed packing mismatch"
                        severity failure;


                    scalar_index :=
                        scalar_index + 1;

                end loop;


                if main_tlast = '1' then

                    last_count :=
                        last_count + 1;

                end if;


                if scalar_index = C_MAIN_SCALARS then

                    assert main_tlast = '1'
                        report
                            "MAIN: final scalar beat missing TLAST"
                        severity failure;

                    assert last_count = 1
                        report
                            "MAIN: frame did not contain exactly one TLAST"
                        severity failure;

                    assert beat_index = C_MAIN_FULL_BEATS
                        report
                            "MAIN: unexpected number of AXIS beats"
                        severity failure;


                    main_done <= '1';

                    exit;

                else

                    assert main_tlast = '0'
                        report
                            "MAIN: TLAST asserted before final scalar"
                        severity failure;

                end if;


                beat_index :=
                    beat_index + 1;

            end if;

        end loop;


        report
            "--- SERIALIZER A PASS ---";

        wait;

    end process main_output_monitor;


    -- ========================================================================
    -- B: event/fifo completion checks
    -- ========================================================================

    main_status_check : process
    begin

        wait until main_done = '1';

        wait until rising_edge(clk);
        wait for 1 ns;


        assert main_input_accept_count = C_MAIN_POS
            report
                "MAIN: input handshake count was not three"
            severity failure;


        assert main_core_accept_count = C_MAIN_POS
            report
                "MAIN: core_accept_pulse count did not match accepted vectors"
            severity failure;


        assert main_fifo_empty = '1'
            report
                "MAIN: fifo_empty did not assert after complete drain"
            severity failure;


        report
            "--- SERIALIZER B PASS: stalls / core_accept / fifo_empty ---";

        wait;

    end process main_status_check;


    -- ========================================================================
    -- C reset
    -- ========================================================================

    k16_reset_proc : process
    begin

        k16_resetn <= '0';

        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);

        k16_resetn <= '1';

        wait;

    end process k16_reset_proc;


    -- ========================================================================
    -- C event monitor
    -- ========================================================================

    k16_event_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if k16_resetn = '0' then

                k16_input_accept_count <= 0;
                k16_core_accept_count  <= 0;

            else

                if
                    k16_in_valid = '1'
                    and k16_in_ready = '1'
                then

                    k16_input_accept_count <=
                        k16_input_accept_count + 1;

                end if;


                if k16_core_accept_pulse = '1' then

                    k16_core_accept_count <=
                        k16_core_accept_count + 1;

                end if;

            end if;

        end if;

    end process k16_event_monitor;


    -- ========================================================================
    -- C: continuous K=16 source
    --
    -- Before FIFO pressure reaches the formatter, consecutive vectors must
    -- be accepted every four formatter clocks.
    -- ========================================================================

    k16_input_driver : process

        variable accepted_count :
            natural := 0;

        variable previous_accept_time :
            time := 0 ns;

    begin

        wait until k16_resetn = '1';


        report
            "--- SERIALIZER C: K=16 throughput + FIFO backpressure ---";


        wait until falling_edge(clk);

        k16_results <=
            make_results_k16(-48);

        k16_in_valid <=
            '1';


        loop

            wait until rising_edge(clk);


            if
                k16_in_valid = '1'
                and k16_in_ready = '1'
            then

                if
                    accepted_count > 0
                    and accepted_count < 5
                then

                    assert
                        now - previous_accept_time =
                        4 * CLK_PERIOD

                        report
                            "K16: extra vector reload bubble"
                        severity failure;

                end if;


                previous_accept_time :=
                    now;

                accepted_count :=
                    accepted_count + 1;


                if accepted_count = 5 then

                    k16_fill_reached <=
                        '1';

                end if;


                if accepted_count = C_K16_POS then

                    k16_in_valid <=
                        '0';

                    k16_input_done <=
                        '1';

                    exit;

                else

                    k16_results <=
                        make_results_k16(
                            -48
                            + integer(
                                accepted_count
                            ) * C_K16
                        );

                end if;

            end if;

        end loop;

        wait;

    end process k16_input_driver;


    -- ========================================================================
    -- C: FIFO-full source backpressure
    -- ========================================================================

    k16_backpressure_check : process
    begin

        wait until k16_fill_reached = '1';


        for stalled_cycle in 1 to 3 loop

            wait until rising_edge(clk);

            assert k16_in_ready = '0'
                report
                    "K16: in_ready did not deassert under FIFO pressure"
                severity failure;

        end loop;


        wait until falling_edge(clk);

        k16_tready <=
            '1';

        wait;

    end process k16_backpressure_check;


    -- ========================================================================
    -- C: K=16 packed output checker
    -- ========================================================================

    k16_output_monitor : process

        variable scalar_index :
            natural := 0;

        variable beat_index :
            natural := 0;

        variable last_count :
            natural := 0;

        variable expected_scalar :
            std_logic_vector(15 downto 0);

    begin

        wait until k16_resetn = '1';


        loop

            wait until rising_edge(clk);


            if
                k16_tvalid = '1'
                and k16_tready = '1'
            then

                assert k16_tkeep = x"FF"
                    report
                        "K16: every output beat must contain four scalars"
                    severity failure;


                for lane in 0 to 3 loop

                    expected_scalar :=
                        std_logic_vector(
                            to_signed(
                                -48
                                + integer(scalar_index),
                                16
                            )
                        );


                    assert
                        k16_tdata(
                            (lane + 1) * 16 - 1
                            downto lane * 16
                        ) = expected_scalar

                        report
                            "K16: scalar ordering / signed packing mismatch"
                        severity failure;


                    scalar_index :=
                        scalar_index + 1;

                end loop;


                if k16_tlast = '1' then

                    last_count :=
                        last_count + 1;

                end if;


                if
                    scalar_index =
                    C_K16 * C_K16_POS
                then

                    assert k16_tlast = '1'
                        report
                            "K16: final beat missing TLAST"
                        severity failure;

                    assert last_count = 1
                        report
                            "K16: frame did not contain exactly one TLAST"
                        severity failure;

                    assert beat_index = 23
                        report
                            "K16: output did not contain exactly 24 beats"
                        severity failure;


                    k16_done <=
                        '1';

                    exit;

                else

                    assert k16_tlast = '0'
                        report
                            "K16: premature TLAST"
                        severity failure;

                end if;


                beat_index :=
                    beat_index + 1;

            end if;

        end loop;


        report
            "--- SERIALIZER C DATA PASS ---";

        wait;

    end process k16_output_monitor;


    k16_status_check : process
    begin

        wait until
            k16_done = '1'
            and k16_input_done = '1';

        wait until rising_edge(clk);
        wait for 1 ns;


        assert k16_input_accept_count = C_K16_POS
            report
                "K16: wrong number of accepted vectors"
            severity failure;


        assert k16_core_accept_count = C_K16_POS
            report
                "K16: core_accept_pulse count mismatch"
            severity failure;


        assert k16_fifo_empty = '1'
            report
                "K16: fifo_empty did not assert after drain"
            severity failure;


        report
            "--- SERIALIZER C PASS ---";

        wait;

    end process k16_status_check;


    -- ========================================================================
    -- D core-accept pulse monitor
    -- ========================================================================

    drain_event_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if drain_resetn = '0' then

                drain_core_accept_count <=
                    0;

            elsif drain_core_accept_pulse = '1' then

                drain_core_accept_count <=
                    drain_core_accept_count + 1;

            end if;

        end if;

    end process drain_event_monitor;


    -- ========================================================================
    -- D: queued FIFO output must continue draining after production stops
    -- ========================================================================

    drain_test : process

        variable expected_scalar :
            std_logic_vector(15 downto 0);

    begin

        report
            "--- SERIALIZER D: queued drain with production disabled ---";


        drain_resetn <=
            '0';

        drain_production_enable <=
            '0';

        drain_tready <=
            '0';

        drain_in_valid <=
            '0';


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);


        drain_resetn <=
            '1';

        drain_production_enable <=
            '1';


        -- ------------------------------------------------------------
        -- Admit exactly one K=8 vector.
        -- ------------------------------------------------------------

        wait until falling_edge(clk);

        drain_results <=
            make_results_k8(100);

        drain_in_valid <=
            '1';


        loop

            wait until rising_edge(clk);

            exit when drain_in_ready = '1';

        end loop;


        wait until falling_edge(clk);

        drain_in_valid <=
            '0';


        -- Allow both four-scalar beats to reach the FIFO while the
        -- downstream is blocked.
        for cycle in 1 to 4 loop

            wait until rising_edge(clk);

        end loop;

        wait for 1 ns;


        assert drain_fifo_empty = '0'
            report
                "DRAIN: formatter failed to queue output before disable"
            severity failure;


        assert drain_tvalid = '1'
            report
                "DRAIN: expected queued TVALID before production disable"
            severity failure;


        -- ------------------------------------------------------------
        -- Simulate FAULT/ABORT production shutdown.
        --
        -- New production/input must stop, but already queued FIFO
        -- words must remain externally drainable.
        -- ------------------------------------------------------------

        wait until falling_edge(clk);

        drain_production_enable <=
            '0';

        drain_tready <=
            '1';

        wait for 1 ns;


        assert drain_in_ready = '0'
            report
                "DRAIN: in_ready remained high after production disable"
            severity failure;


        -- ------------------------------------------------------------
        -- Drain exactly two already-queued K=8 words.
        -- ------------------------------------------------------------

        for beat in 0 to 1 loop

            loop

                wait until rising_edge(clk);

                exit when
                    drain_tvalid = '1'
                    and drain_tready = '1';

            end loop;


            assert drain_tkeep = x"FF"
                report
                    "DRAIN: queued K=8 word had invalid TKEEP"
                severity failure;


            for lane in 0 to 3 loop

                expected_scalar :=
                    std_logic_vector(
                        to_signed(
                            100
                            + beat * 4
                            + lane,
                            16
                        )
                    );


                assert
                    drain_tdata(
                        (lane + 1) * 16 - 1
                        downto lane * 16
                    ) = expected_scalar

                    report
                        "DRAIN: queued output changed after production disable"
                    severity failure;

            end loop;


            if beat = 0 then

                assert drain_tlast = '0'
                    report
                        "DRAIN: premature TLAST"
                    severity failure;

            else

                assert drain_tlast = '1'
                    report
                        "DRAIN: final queued beat missing TLAST"
                    severity failure;

            end if;

        end loop;


        wait until rising_edge(clk);
        wait for 1 ns;


        assert drain_fifo_empty = '1'
            report
                "DRAIN: FIFO did not become empty after queued drain"
            severity failure;


        assert drain_tvalid = '0'
            report
                "DRAIN: TVALID remained asserted after FIFO drained"
            severity failure;


        assert drain_core_accept_count = 1
            report
                "DRAIN: core_accept_pulse count was not exactly one"
            severity failure;


        drain_done <=
            '1';


        report
            "--- SERIALIZER D PASS ---";

        wait;

    end process drain_test;


    -- ========================================================================
    -- E/F/G core-accept monitor
    -- ========================================================================

    freeze_event_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if freeze_resetn = '0' then

                freeze_core_accept_count <=
                    0;

            elsif freeze_core_accept_pulse = '1' then

                freeze_core_accept_count <=
                    freeze_core_accept_count + 1;

            end if;

        end if;

    end process freeze_event_monitor;


    -- ========================================================================
    -- E/F/G partial-state freeze and RESET recovery
    -- ========================================================================

    freeze_test : process

        procedure send_vector(
            constant base_value :
                in integer
        ) is

        begin

            wait until falling_edge(clk);

            freeze_results <=
                make_results_k6(
                    base_value
                );

            freeze_in_valid <=
                '1';


            loop

                wait until rising_edge(clk);

                exit when freeze_in_ready = '1';

            end loop;


            wait until falling_edge(clk);

            freeze_in_valid <=
                '0';

        end procedure send_vector;


        variable expected_scalar :
            std_logic_vector(15 downto 0);

    begin

        report
            "--- SERIALIZER E: partial formatter freeze ---";


        freeze_resetn <=
            '0';

        freeze_production_enable <=
            '0';

        freeze_tready <=
            '1';

        freeze_in_valid <=
            '0';


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);


        freeze_resetn <=
            '1';

        freeze_production_enable <=
            '1';


        -- ------------------------------------------------------------
        -- One K=6 vector:
        --
        -- [200 201 202 203] enters FIFO.
        -- [204 205] remains partial inside the formatter.
        -- ------------------------------------------------------------

        send_vector(200);


        -- Consume the one complete beat.
        loop

            wait until rising_edge(clk);

            exit when
                freeze_tvalid = '1'
                and freeze_tready = '1';

        end loop;


        assert freeze_tkeep = x"FF"
            report
                "FREEZE: first K=6 word was not full"
            severity failure;


        assert freeze_tlast = '0'
            report
                "FREEZE: single first vector incorrectly asserted TLAST"
            severity failure;


        for lane in 0 to 3 loop

            expected_scalar :=
                std_logic_vector(
                    to_signed(
                        200 + lane,
                        16
                    )
                );


            assert
                freeze_tdata(
                    (lane + 1) * 16 - 1
                    downto lane * 16
                ) = expected_scalar

                report
                    "FREEZE: first complete word packed incorrectly"
                severity failure;

        end loop;


        wait until rising_edge(clk);
        wait for 1 ns;


        -- FIFO is empty even though two scalars remain in formatter state.
        assert freeze_fifo_empty = '1'
            report
                "FREEZE: fifo_empty must exclude retained partial formatter state"
            severity failure;


        assert freeze_tvalid = '0'
            report
                "FREEZE: partial formatter state leaked as an AXIS word"
            severity failure;


        -- ------------------------------------------------------------
        -- Disable further production.
        -- ------------------------------------------------------------

        wait until falling_edge(clk);

        freeze_production_enable <=
            '0';


        for frozen_cycle in 1 to 4 loop

            wait until rising_edge(clk);
            wait for 1 ns;


            assert freeze_in_ready = '0'
                report
                    "FREEZE: in_ready remained high with production disabled"
                severity failure;


            assert freeze_tvalid = '0'
                report
                    "FREEZE: partial formatter state escaped while frozen"
                severity failure;


            assert freeze_fifo_empty = '1'
                report
                    "FREEZE: fifo_empty changed because of frozen partial state"
                severity failure;

        end loop;


        assert freeze_core_accept_count = 1
            report
                "FREEZE: expected exactly one accepted vector before RESET"
            severity failure;


        report
            "--- SERIALIZER E/F PASS: partial frozen; fifo_empty semantics correct ---";


        -- ====================================================================
        -- G. RESET RECOVERY
        --
        -- The frozen [204,205] must be destroyed by RESET.
        -- A clean two-vector frame starts with 300 and must contain no stale
        -- values from the abandoned frame.
        -- ====================================================================

        report
            "--- SERIALIZER G: RESET recovery from frozen partial formatter ---";


        wait until falling_edge(clk);

        freeze_resetn <=
            '0';

        freeze_production_enable <=
            '0';

        freeze_tready <=
            '0';

        freeze_in_valid <=
            '0';


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait until rising_edge(clk);

        wait until falling_edge(clk);


        freeze_resetn <=
            '1';

        freeze_production_enable <=
            '1';


        wait until rising_edge(clk);
        wait for 1 ns;


        assert freeze_fifo_empty = '1'
            report
                "RECOVERY: FIFO was not empty immediately after RESET"
            severity failure;


        assert freeze_tvalid = '0'
            report
                "RECOVERY: stale output survived RESET"
            severity failure;


        -- Keep downstream blocked while both fresh vectors are packed.
        freeze_tready <=
            '0';


        send_vector(300);
        send_vector(306);


        -- Three complete words must now be queued:
        --
        -- beat 0 = 300 301 302 303
        -- beat 1 = 304 305 306 307
        -- beat 2 = 308 309 310 311, TLAST
        for settle_cycle in 1 to 6 loop

            wait until rising_edge(clk);

        end loop;

        wait for 1 ns;


        assert freeze_fifo_empty = '0'
            report
                "RECOVERY: fresh frame produced no queued output"
            severity failure;


        -- Release downstream.
        wait until falling_edge(clk);

        freeze_tready <=
            '1';


        for beat in 0 to 2 loop

            loop

                wait until rising_edge(clk);

                exit when
                    freeze_tvalid = '1'
                    and freeze_tready = '1';

            end loop;


            assert freeze_tkeep = x"FF"
                report
                    "RECOVERY: two K=6 vectors must produce three full words"
                severity failure;


            for lane in 0 to 3 loop

                expected_scalar :=
                    std_logic_vector(
                        to_signed(
                            300
                            + beat * 4
                            + lane,
                            16
                        )
                    );


                assert
                    freeze_tdata(
                        (lane + 1) * 16 - 1
                        downto lane * 16
                    ) = expected_scalar

                    report
                        "RECOVERY: stale/faulted formatter data survived RESET"
                    severity failure;

            end loop;


            if beat < 2 then

                assert freeze_tlast = '0'
                    report
                        "RECOVERY: premature TLAST"
                    severity failure;

            else

                assert freeze_tlast = '1'
                    report
                        "RECOVERY: final fresh beat missing TLAST"
                    severity failure;

            end if;

        end loop;


        wait until rising_edge(clk);
        wait for 1 ns;


        assert freeze_fifo_empty = '1'
            report
                "RECOVERY: FIFO not empty after fresh frame drained"
            severity failure;


        assert freeze_tvalid = '0'
            report
                "RECOVERY: unexpected output remained after fresh frame"
            severity failure;


        -- freeze_event_monitor was reset by local RESET, so this must now
        -- describe only the new frame.
        assert freeze_core_accept_count = 2
            report
                "RECOVERY: expected exactly two fresh core_accept pulses"
            severity failure;


        freeze_done <=
            '1';


        report
            "--- SERIALIZER G PASS ---";

        wait;

    end process freeze_test;


    -- ========================================================================
    -- FINAL
    -- ========================================================================

    finish_proc : process
    begin

        wait until
            main_done = '1'
            and k16_input_done = '1'
            and k16_done = '1'
            and drain_done = '1'
            and freeze_done = '1';


        -- Give the independent status-check processes one final clock.
        wait until rising_edge(clk);
        wait for 1 ns;


        report
            "============================================================";

        report
            " AXI_STREAM_OUTPUT_SERIALIZER COMPLETE UNIT REGRESSION PASS ";

        report
            "============================================================";


        finish;
        wait;

    end process finish_proc;


    -- ========================================================================
    -- Timeout
    -- ========================================================================

    timeout_proc : process
    begin

        wait for 100 us;


        assert false
            report
                "AXI stream output serializer comprehensive regression timed out"
            severity failure;


        wait;

    end process timeout_proc;


end architecture sim;