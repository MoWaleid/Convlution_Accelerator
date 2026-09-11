-- ============================================================================
-- tb_conv_top.vhd
--
-- M4 comprehensive conv_top integration regression.
--
-- Uses the ACTUAL compiled config_pkg profile:
--   N = CFG_N                  = 3
--   K = CFG_K                  = 8
--   padded geometry            = 34 x 34
--   logical output geometry    = 32 x 32
--
-- All pixels       = +1
-- All coefficients = +1
-- Bias             = 0
-- Shift            = 0
-- ReLU             = 0
--
-- Therefore every channel of every output vector must equal:
--
--      9
--
-- Coverage:
--   A. Hard reset / RUN gating
--   B. Complete K=8 parameter admission through real AXI-Lite
--   C. First complete numerical frame
--   D. CRITICAL: second START with NO RESET
--   E. Local RESET preserves parameters/admission
--   F. Successful frame after local RESET
--   G. Mid-frame ABORT / FAULT / drain-to-QUIESCENT
--   H. RESET recovery from FAULT
--   I. Successful frame after recovery
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;


entity tb_conv_top is
end entity;


architecture sim of tb_conv_top is

    constant CLK_PERIOD :
        time := 10 ns;

    constant C_K :
        integer := CFG_K;

    constant C_N :
        integer := CFG_N;

    constant C_PAD_W :
        integer := CFG_IMAGE_WIDTH;

    constant C_PAD_H :
        integer := CFG_IMAGE_HEIGHT;

    constant C_LOG_W :
        integer := CFG_UNPADDED_WIDTH;

    constant C_LOG_H :
        integer := CFG_UNPADDED_HEIGHT;

    constant C_INPUT_PIXELS :
        integer := C_PAD_W * C_PAD_H;

    constant C_OUTPUT_PIXELS :
        integer := C_LOG_W * C_LOG_H;

    constant C_EXPECTED_INPUT_BYTES :
        integer := C_INPUT_PIXELS;

    constant C_EXPECTED_OUTPUT_BYTES :
        integer :=
            C_OUTPUT_PIXELS * C_K * 2;

    constant C_EXPECTED_OUTPUT_BEATS :
        integer :=
            C_EXPECTED_OUTPUT_BYTES / 8;


    -- ========================================================================
    -- Clock / hard reset
    -- ========================================================================

    signal clk :
        std_logic := '0';

    signal resetn :
        std_logic := '0';

    signal ce :
        std_logic := '1';


    -- ========================================================================
    -- AXI4-Lite
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
    -- Controller observation inputs
    -- ========================================================================

    signal input_accept_valid :
        std_logic;

    signal input_accept_bytes :
        std_logic_vector(3 downto 0);

    signal input_consumed_pulse :
        std_logic;

    signal input_frame_error :
        std_logic := '0';


    signal core_accept_pulse :
        std_logic := '0';

    signal output_accept_valid :
        std_logic := '0';

    signal output_accept_bytes :
        std_logic_vector(3 downto 0) :=
            (others => '0');

    signal output_accept_last :
        std_logic := '0';

    signal output_fifo_empty :
        std_logic := '1';

    signal output_tvalid :
        std_logic := '0';

    signal internal_error_in :
        std_logic := '0';


    -- ========================================================================
    -- Lifecycle outputs
    -- ========================================================================

    signal start_pulse_out :
        std_logic;

    signal local_reset_out :
        std_logic;

    signal run_enable_out :
        std_logic;

    signal production_enable_out :
        std_logic;


    -- ========================================================================
    -- Datapath
    -- ========================================================================

    signal pixel_in :
        std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0) :=
            (others => '0');

    signal valid_in :
        std_logic := '0';


    signal results_out :
        output_array_t(0 to C_K - 1);

    signal valid_out :
        std_logic;


    -- ========================================================================
    -- Bookkeeping
    -- ========================================================================

    signal start_pulse_count :
        natural := 0;

    signal local_reset_count :
        natural := 0;

    signal completed_numerical_frames :
        natural := 0;


begin

    -- ========================================================================
    -- Clock
    -- ========================================================================

    clk <=
        not clk after CLK_PERIOD / 2;


    -- ========================================================================
    -- DUT
    --
    -- Deliberately use the same configuration as config_pkg.
    -- ========================================================================

    dut :
        entity work.conv_top
        generic map (
            C_K =>
                CFG_K,

            C_N =>
                CFG_N,

            C_IMAGE_WIDTH =>
                CFG_IMAGE_WIDTH,

            C_IMAGE_HEIGHT =>
                CFG_IMAGE_HEIGHT,

            C_LOGICAL_IMAGE_WIDTH =>
                CFG_UNPADDED_WIDTH,

            C_LOGICAL_IMAGE_HEIGHT =>
                CFG_UNPADDED_HEIGHT,

            C_S_AXI_DATA_WIDTH =>
                32,

            C_S_AXI_ADDR_WIDTH =>
                32,

            C_BUILD_ID =>
                x"4D344E334B385733322D323630393131",

            C_DMA_LENGTH_WIDTH =>
                22
        )
        port map (
            clk =>
                clk,

            resetn =>
                resetn,

            ce =>
                ce,


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


            input_accept_valid =>
                input_accept_valid,

            input_accept_bytes =>
                input_accept_bytes,

            input_consumed_pulse =>
                input_consumed_pulse,

            input_frame_error =>
                input_frame_error,

            core_accept_pulse =>
                core_accept_pulse,

            output_accept_valid =>
                output_accept_valid,

            output_accept_bytes =>
                output_accept_bytes,

            output_accept_last =>
                output_accept_last,

            output_fifo_empty =>
                output_fifo_empty,

            output_tvalid =>
                output_tvalid,

            internal_error_in =>
                internal_error_in,


            start_pulse_out =>
                start_pulse_out,

            local_reset_out =>
                local_reset_out,

            run_enable_out =>
                run_enable_out,

            production_enable_out =>
                production_enable_out,


            pixel_in =>
                pixel_in,

            valid_in =>
                valid_in,

            results_out =>
                results_out,

            valid_out =>
                valid_out
        );


    -- ========================================================================
    -- Synthetic input-frontend observation model
    --
    -- Every valid pixel is one physical input byte and is immediately consumed
    -- because CE is permanently high in this conv_top-level test.
    -- ========================================================================

    input_accept_valid <=
        valid_in and run_enable_out;

    input_accept_bytes <=
        "0001"
        when
            valid_in = '1'
            and run_enable_out = '1'
        else
            "0000";

    input_consumed_pulse <=
        valid_in and run_enable_out;


    -- ========================================================================
    -- Lifecycle monitor
    -- ========================================================================

    lifecycle_monitor : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                start_pulse_count <=
                    0;

                local_reset_count <=
                    0;

            else

                if start_pulse_out = '1' then

                    start_pulse_count <=
                        start_pulse_count + 1;

                end if;


                if local_reset_out = '1' then

                    local_reset_count <=
                        local_reset_count + 1;

                end if;

            end if;

        end if;

    end process lifecycle_monitor;


    -- ========================================================================
    -- Numerical checker
    --
    -- This does NOT reset DUT state on START.
    --
    -- Every active output vector must contain eight copies of signed16 value 9.
    -- A complete successful numerical frame contains exactly 1024 vectors.
    -- ========================================================================

    numerical_checker : process(clk)

        variable frame_output_count :
            natural := 0;

        variable actual :
            integer;

    begin

        if rising_edge(clk) then

            if resetn = '0' then

                frame_output_count :=
                    0;

                completed_numerical_frames <=
                    0;

            else

                if
                    start_pulse_out = '1'
                    or local_reset_out = '1'
                then

                    frame_output_count :=
                        0;

                end if;


                if
                    valid_out = '1'
                    and production_enable_out = '1'
                then

                    for channel in 0 to C_K - 1 loop

                        actual :=
                            to_integer(
                                signed(results_out(channel))
                            );


                        assert actual = 9
                            report
                                "conv_top numerical mismatch: channel "
                                & integer'image(channel)
                                & ", vector "
                                & integer'image(frame_output_count)
                                & ", expected 9, got "
                                & integer'image(actual)
                            severity failure;

                    end loop;


                    if
                        frame_output_count =
                        C_OUTPUT_PIXELS - 1
                    then

                        completed_numerical_frames <=
                            completed_numerical_frames + 1;

                        frame_output_count :=
                            0;

                    else

                        frame_output_count :=
                            frame_output_count + 1;

                    end if;

                end if;

            end if;

        end if;

    end process numerical_checker;


    -- ========================================================================
    -- Synthetic serializer/output model
    --
    -- The real serializer has already passed its comprehensive unit regression.
    --
    -- For K=8 each core vector contains:
    --
    --      8 channels * 2 bytes = 16 bytes
    --
    -- therefore each accepted core vector creates TWO 64-bit AXIS output beats.
    --
    -- One queued external beat is drained per clock.  This intentionally means
    -- the controller stays RUN after computation finishes until the synthetic
    -- output queue has completely drained.
    --
    -- ABORT stops NEW production, but queued beats keep draining.
    -- ========================================================================

    output_model : process(clk)

        variable pending_beats :
            integer range 0 to 4096 := 0;

        variable emitted_beats :
            integer range 0 to C_EXPECTED_OUTPUT_BEATS := 0;

        variable next_pending :
            integer range 0 to 4096;

    begin

        if rising_edge(clk) then

            if resetn = '0' then

                core_accept_pulse <=
                    '0';

                output_accept_valid <=
                    '0';

                output_accept_bytes <=
                    (others => '0');

                output_accept_last <=
                    '0';

                output_fifo_empty <=
                    '1';

                output_tvalid <=
                    '0';

                pending_beats :=
                    0;

                emitted_beats :=
                    0;

            else

                core_accept_pulse <=
                    '0';

                output_accept_valid <=
                    '0';

                output_accept_bytes <=
                    (others => '0');

                output_accept_last <=
                    '0';

                output_tvalid <=
                    '0';


                -- Local RESET discards all serializer/FIFO history.
                if local_reset_out = '1' then

                    pending_beats :=
                        0;

                    emitted_beats :=
                        0;

                    output_fifo_empty <=
                        '1';


                else

                    -- A normal new START must occur only after the prior frame
                    -- has completely drained.
                    if start_pulse_out = '1' then

                        assert pending_beats = 0
                            report
                                "New START occurred with synthetic output still queued"
                            severity failure;

                        emitted_beats :=
                            0;

                    end if;


                    next_pending :=
                        pending_beats;


                    -- Serializer accepts one K-channel vector.
                    if
                        valid_out = '1'
                        and production_enable_out = '1'
                    then

                        core_accept_pulse <=
                            '1';

                        next_pending :=
                            next_pending + 2;

                    end if;


                    -- External output continues draining regardless of whether
                    -- new production remains enabled.
                    if next_pending > 0 then

                        output_tvalid <=
                            '1';

                        output_fifo_empty <=
                            '0';

                        output_accept_valid <=
                            '1';

                        output_accept_bytes <=
                            "1000";


                        if
                            emitted_beats =
                            C_EXPECTED_OUTPUT_BEATS - 1
                        then

                            output_accept_last <=
                                '1';

                            emitted_beats :=
                                0;

                        else

                            emitted_beats :=
                                emitted_beats + 1;

                        end if;


                        next_pending :=
                            next_pending - 1;


                    else

                        output_fifo_empty <=
                            '1';

                    end if;


                    pending_beats :=
                        next_pending;

                end if;

            end if;

        end if;

    end process output_model;


    -- ========================================================================
    -- Main regression
    -- ========================================================================

    stim_proc : process

        ------------------------------------------------------------------------
        -- AXI full-word write
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
                    to_unsigned(address, 32)
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
        -- AXI read
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
                    to_unsigned(address, 32)
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
        -- Program all K channels.
        ------------------------------------------------------------------------

        procedure program_all_channels is

            variable base :
                natural;

        begin

            for channel in 0 to C_K - 1 loop

                base :=
                    channel * 16#100#;


                -- coeffs 0..3
                axi_write(
                    base + 16#00#,
                    x"01010101"
                );


                -- coeffs 4..7
                axi_write(
                    base + 16#04#,
                    x"01010101"
                );


                -- coeff 8 only; nonexistent lanes must be zero.
                axi_write(
                    base + 16#08#,
                    x"00000001"
                );


                -- signed24 bias = 0
                axi_write(
                    base + 16#F8#,
                    x"00000000"
                );


                -- shift=0, relu=0
                axi_write(
                    base + 16#FC#,
                    x"00000000"
                );

            end loop;

        end procedure program_all_channels;


        ------------------------------------------------------------------------
        -- Send N input pixels, every pixel value exactly +1.
        ------------------------------------------------------------------------

        procedure send_pixels(
            constant count :
                in positive
        ) is

        begin

            for index in 1 to count loop

                wait until falling_edge(clk);

                pixel_in <=
                    std_logic_vector(
                        to_unsigned(
                            1,
                            CFG_PIXEL_WIDTH
                        )
                    );

                valid_in <=
                    '1';


                wait until rising_edge(clk);

            end loop;


            wait until falling_edge(clk);

            valid_in <=
                '0';

            pixel_in <=
                (others => '0');

        end procedure send_pixels;


        ------------------------------------------------------------------------
        -- Full 34x34 input frame.
        ------------------------------------------------------------------------

        procedure send_full_frame is
        begin

            send_pixels(
                C_INPUT_PIXELS
            );

        end procedure send_full_frame;


        ------------------------------------------------------------------------
        -- Confirm traffic cannot enter while not RUN.
        ------------------------------------------------------------------------

        procedure test_stopped_input is
        begin

            for index in 1 to 20 loop

                wait until falling_edge(clk);

                pixel_in <=
                    std_logic_vector(
                        to_unsigned(
                            1,
                            CFG_PIXEL_WIDTH
                        )
                    );

                valid_in <=
                    '1';


                wait until rising_edge(clk);
                wait for 1 ns;


                assert run_enable_out = '0'
                    report
                        "RUN unexpectedly asserted during stopped-input test"
                    severity failure;


                assert production_enable_out = '0'
    report
        "Production remained enabled while RUN was disabled"
    severity failure;

assert input_consumed_pulse = '0'
    report
        "Input pixel was consumed while RUN was disabled"
    severity failure;

assert core_accept_pulse = '0'
    report
        "Frozen core output was accepted while production was disabled"
    severity failure;

            end loop;


            wait until falling_edge(clk);

            valid_in <=
                '0';

            pixel_in <=
                (others => '0');

        end procedure test_stopped_input;


        ------------------------------------------------------------------------
        -- Wait until one successful frame is completely drained.
        ------------------------------------------------------------------------

        procedure wait_for_success(
            constant expected_numerical_frames :
                in natural
        ) is

            variable status_word :
                std_logic_vector(31 downto 0);

        begin

            while
                completed_numerical_frames <
                expected_numerical_frames
            loop

                wait until rising_edge(clk);

            end loop;


            -- Poll until DONE + IDLE + QUIESCENT.
            loop

                axi_read(
                    16#410C#,
                    status_word
                );


                assert status_word(5) = '0'
                    report
                        "ERROR asserted during expected-success frame"
                    severity failure;


                assert status_word(6) = '0'
                    report
                        "FAULT asserted during expected-success frame"
                    severity failure;


                exit when
                    status_word(0) = '1'
                    and status_word(4) = '1'
                    and status_word(8) = '1';

            end loop;


            assert status_word(1) = '0'
                report
                    "BUSY remained high after successful frame"
                severity failure;

            assert status_word(2) = '1'
                report
                    "CORE_COMPLETE missing"
                severity failure;

            assert status_word(3) = '1'
                report
                    "OUTPUT_DRAINED missing"
                severity failure;

            assert status_word(7) = '1'
                report
                    "PARAM_COMPLETE lost"
                severity failure;

        end procedure wait_for_success;


        ------------------------------------------------------------------------
        -- Verify the four architectural counters after successful completion.
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
                C_OUTPUT_PIXELS
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
        -- Wait for FAULT to become locally QUIESCENT after queued output drains.
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

        variable reset_count_before :
            natural;

    begin

        -- ====================================================================
        -- A. HARD RESET / STOPPED DATAPATH
        -- ====================================================================

        report
            "--- CONV_TOP A: hard reset + RUN gating ---";


        resetn <=
            '0';

        valid_in <=
            '0';

        ce <=
            '1';


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
            16#410C#,
            rd
        );


        assert rd = x"00000101"
            report
                "Unexpected power-on STATUS"
            severity failure;


        test_stopped_input;


        report
            "--- CONV_TOP A PASS ---";


        -- ====================================================================
        -- B. COMPLETE PARAMETER ADMISSION
        -- ====================================================================

        report
            "--- CONV_TOP B: K=8 CVH1 parameter admission ---";


        program_all_channels;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(7) = '1'
            report
                "PARAM_COMPLETE did not assert"
            severity failure;


        -- Spot-check first and final channel.
        axi_read(
            16#0008#,
            rd
        );

        assert rd = x"00000001"
            report
                "Channel 0 final coefficient word mismatch"
            severity failure;


        axi_read(
            7 * 16#100# + 16#0008#,
            rd
        );

        assert rd = x"00000001"
            report
                "Channel 7 final coefficient word mismatch"
            severity failure;


        report
            "--- CONV_TOP B PASS ---";


        -- ====================================================================
        -- C. FIRST COMPLETE FRAME
        -- ====================================================================

        report
            "--- CONV_TOP C: first full numerical frame ---";


        axi_write(
            16#4110#,
            x"00000001"
        );


        while run_enable_out = '0' loop

            wait until rising_edge(clk);

        end loop;


        assert production_enable_out = '1'
            report
                "production_enable missing after START"
            severity failure;


        send_full_frame;


        wait_for_success(
            1
        );


        check_success_counters;


        assert start_pulse_count = 1
            report
                "First START pulse count mismatch"
            severity failure;


        assert local_reset_count = 0
            report
                "Unexpected RESET during first frame"
            severity failure;


        report
            "--- CONV_TOP C PASS ---";


        -- ====================================================================
        -- D. CRITICAL REPEATED FRAME — NO RESET
        -- ====================================================================

        report
            "--- CONV_TOP D: repeated START with NO RESET ---";


        reset_count_before :=
            local_reset_count;


        axi_write(
            16#4110#,
            x"00000001"
        );


        while run_enable_out = '0' loop

            wait until rising_edge(clk);

        end loop;


        assert
            local_reset_count =
            reset_count_before
        report
            "Repeated START unexpectedly generated RESET"
        severity failure;


        send_full_frame;


        wait_for_success(
            2
        );


        check_success_counters;


        assert start_pulse_count = 2
            report
                "Second START pulse missing"
            severity failure;


        assert
            local_reset_count =
            reset_count_before
        report
            "Second normal frame used a RESET"
        severity failure;


        report
            "--- CONV_TOP D PASS: repeated frame works WITHOUT RESET ---";


        -- ====================================================================
        -- E. LOCAL RESET AFTER SUCCESS
        -- ====================================================================

        report
            "--- CONV_TOP E: local RESET preserves parameters ---";


        reset_count_before :=
            local_reset_count;


        axi_write(
            16#4110#,
            x"00000002"
        );


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;


        assert
            local_reset_count =
            reset_count_before + 1
        report
            "Local RESET pulse missing"
        severity failure;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(0) = '1'
            report "RESET did not leave IDLE"
            severity failure;

        assert rd(2) = '0'
            report "RESET did not clear CORE_COMPLETE"
            severity failure;

        assert rd(3) = '0'
            report "RESET did not clear OUTPUT_DRAINED"
            severity failure;

        assert rd(4) = '0'
            report "RESET did not clear DONE"
            severity failure;

        assert rd(5) = '0'
            report "RESET left ERROR set"
            severity failure;

        assert rd(6) = '0'
            report "RESET left FAULT set"
            severity failure;

        assert rd(7) = '1'
            report "RESET cleared PARAM_COMPLETE"
            severity failure;

        assert rd(8) = '1'
            report "RESET did not leave QUIESCENT"
            severity failure;


        axi_read(
            16#0000#,
            rd
        );


        assert rd = x"01010101"
            report
                "Local RESET corrupted coefficient storage"
            severity failure;


        report
            "--- CONV_TOP E PASS ---";


        -- ====================================================================
        -- F. SUCCESSFUL FRAME AFTER LOCAL RESET
        -- ====================================================================

        report
            "--- CONV_TOP F: post-RESET numerical frame ---";


        axi_write(
            16#4110#,
            x"00000001"
        );


        while run_enable_out = '0' loop

            wait until rising_edge(clk);

        end loop;


        send_full_frame;


        wait_for_success(
            3
        );


        check_success_counters;


        report
            "--- CONV_TOP F PASS ---";


        -- ====================================================================
        -- G. MID-FRAME ABORT
        --
        -- We intentionally let enough pixels through to create some convolution
        -- output, so the synthetic serializer has queued output to drain after
        -- production is disabled.
        -- ====================================================================

        report
            "--- CONV_TOP G: ABORT + FAULT drain ---";


        axi_write(
            16#4110#,
            x"00000001"
        );


        while run_enable_out = '0' loop

            wait until rising_edge(clk);

        end loop;


        send_pixels(
            200
        );


        axi_write(
            16#4110#,
            x"00000004"
        );


        while run_enable_out = '1' loop

            wait until rising_edge(clk);

        end loop;


        assert production_enable_out = '0'
            report
                "ABORT did not disable production"
            severity failure;


        wait_for_fault_quiescent;


        axi_read(
            16#410C#,
            rd
        );


        assert rd(1) = '1'
            report
                "FAULT did not retain BUSY"
            severity failure;

        assert rd(5) = '1'
            report
                "FAULT did not assert ERROR"
            severity failure;

        assert rd(6) = '1'
            report
                "ABORT did not assert FAULT"
            severity failure;

        assert rd(8) = '1'
            report
                "FAULT did not reach QUIESCENT after drain"
            severity failure;


        axi_read(
            16#4118#,
            rd
        );


        assert rd(8) = '1'
            report
                "ABORTED flag missing"
            severity failure;


        test_stopped_input;


        report
            "--- CONV_TOP G PASS ---";


        -- ====================================================================
        -- H. RESET RECOVERY FROM FAULT
        -- ====================================================================

        report
            "--- CONV_TOP H: RESET recovery from FAULT ---";


        reset_count_before :=
            local_reset_count;


        axi_write(
            16#4110#,
            x"00000002"
        );


        wait until rising_edge(clk);
        wait until rising_edge(clk);
        wait for 1 ns;


        assert
            local_reset_count =
            reset_count_before + 1
        report
            "FAULT recovery RESET pulse missing"
        severity failure;


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
                "Recovery RESET left BUSY"
            severity failure;

        assert rd(5) = '0'
            report
                "Recovery RESET left ERROR"
            severity failure;

        assert rd(6) = '0'
            report
                "Recovery RESET left FAULT"
            severity failure;

        assert rd(7) = '1'
            report
                "Recovery RESET cleared PARAM_COMPLETE"
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


        report
            "--- CONV_TOP H PASS ---";


        -- ====================================================================
        -- I. FINAL SUCCESSFUL FRAME AFTER RECOVERY
        -- ====================================================================

        report
            "--- CONV_TOP I: post-recovery numerical frame ---";


        axi_write(
            16#4110#,
            x"00000001"
        );


        while run_enable_out = '0' loop

            wait until rising_edge(clk);

        end loop;


        send_full_frame;


        wait_for_success(
            4
        );


        check_success_counters;


        assert start_pulse_count = 5
            report
                "Unexpected total START pulse count"
            severity failure;


        assert completed_numerical_frames = 4
            report
                "Wrong number of complete verified numerical frames"
            severity failure;


        report
            "--- CONV_TOP I PASS ---";


        -- ====================================================================
        -- FINAL
        -- ====================================================================

        report
            "============================================================";

        report
            " CONV_TOP COMPLETE INTEGRATION REGRESSION PASS ";

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

        wait for 200 us;


        assert false
            report
                "conv_top comprehensive integration regression timed out"
            severity failure;


        wait;

    end process;


end architecture;