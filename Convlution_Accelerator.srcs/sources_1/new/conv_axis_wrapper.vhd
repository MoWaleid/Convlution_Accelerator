-- ============================================================================
-- conv_axis_wrapper.vhd
-- CVH1 AXI4-Lite-controlled convolution accelerator with AXI4-Stream I/O
-- ============================================================================
--
-- Integration responsibilities:
--
--   * Connect the strict CVH1 input frontend to the convolution core.
--   * Connect the convolution core to the CVH1 output serializer.
--   * Route stream acceptance/consumption events into axi_lite_ctrl.
--   * Route START / RUN / RESET / production controls back outward.
--   * Preserve queued output draining during FAULT/ABORT.
--
-- Lifecycle authority remains entirely inside axi_lite_ctrl.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;


entity conv_axis_wrapper is
    generic (
        C_WINDOW_PREFETCH : boolean := true;
        C_K :
            positive := CFG_K;

        C_N :
            positive := CFG_N;

        C_IMAGE_WIDTH :
            positive := CFG_IMAGE_WIDTH;

        C_IMAGE_HEIGHT :
            positive := CFG_IMAGE_HEIGHT;

        C_OUTPUT_IMAGE_WIDTH :
            positive := CFG_UNPADDED_WIDTH;

        C_OUTPUT_IMAGE_HEIGHT :
            positive := CFG_UNPADDED_HEIGHT;

        C_S_AXI_DATA_WIDTH :
            positive := 32;

        C_S_AXI_ADDR_WIDTH :
            positive := 32;

        C_BUILD_ID :
            std_logic_vector(127 downto 0) :=
            CFG_BUILD_ID;

        C_DMA_LENGTH_WIDTH :
            positive := 22
    );
    port (
        clk    : in std_logic;
        resetn : in std_logic;

        -- ====================================================================
        -- AXI4-Lite control plane
        -- ====================================================================

        S_AXI_AWADDR :
            in std_logic_vector(
                C_S_AXI_ADDR_WIDTH - 1 downto 0
            );

        S_AXI_AWPROT :
            in std_logic_vector(2 downto 0);

        S_AXI_AWVALID :
            in std_logic;

        S_AXI_AWREADY :
            out std_logic;


        S_AXI_WDATA :
            in std_logic_vector(
                C_S_AXI_DATA_WIDTH - 1 downto 0
            );

        S_AXI_WSTRB :
            in std_logic_vector(
                (C_S_AXI_DATA_WIDTH / 8) - 1
                downto 0
            );

        S_AXI_WVALID :
            in std_logic;

        S_AXI_WREADY :
            out std_logic;


        S_AXI_BRESP :
            out std_logic_vector(1 downto 0);

        S_AXI_BVALID :
            out std_logic;

        S_AXI_BREADY :
            in std_logic;


        S_AXI_ARADDR :
            in std_logic_vector(
                C_S_AXI_ADDR_WIDTH - 1 downto 0
            );

        S_AXI_ARPROT :
            in std_logic_vector(2 downto 0);

        S_AXI_ARVALID :
            in std_logic;

        S_AXI_ARREADY :
            out std_logic;


        S_AXI_RDATA :
            out std_logic_vector(
                C_S_AXI_DATA_WIDTH - 1 downto 0
            );

        S_AXI_RRESP :
            out std_logic_vector(1 downto 0);

        S_AXI_RVALID :
            out std_logic;

        S_AXI_RREADY :
            in std_logic;


        -- ====================================================================
        -- 64-bit AXI4-Stream input
        -- ====================================================================

        s_axis_tdata :
            in std_logic_vector(63 downto 0);

        s_axis_tkeep :
            in std_logic_vector(7 downto 0);

        s_axis_tvalid :
            in std_logic;

        s_axis_tready :
            out std_logic;

        s_axis_tlast :
            in std_logic;


        -- ====================================================================
        -- 64-bit AXI4-Stream output
        -- ====================================================================

        m_axis_tdata :
            out std_logic_vector(63 downto 0);

        m_axis_tkeep :
            out std_logic_vector(7 downto 0);

        m_axis_tvalid :
            out std_logic;

        m_axis_tready :
            in std_logic;

        m_axis_tlast :
            out std_logic
    );
end entity conv_axis_wrapper;


architecture rtl of conv_axis_wrapper is

    constant C_EXPECTED_INPUT_BYTES :
        positive :=
            C_IMAGE_WIDTH * C_IMAGE_HEIGHT;

    -- ========================================================================
    -- Input frontend -> convolution core
    -- ========================================================================

    signal input_pixel :
        std_logic_vector(
            CFG_PIXEL_WIDTH - 1 downto 0
        );

    signal input_pixel_valid :
        std_logic;

    signal input_pixel_last :
        std_logic;

    -- ========================================================================
    -- Input frontend -> lifecycle controller events
    -- ========================================================================

    signal input_accept_valid_wire :
        std_logic;

    signal input_accept_bytes_wire :
        std_logic_vector(3 downto 0);

    signal input_frame_error_wire :
        std_logic;

    signal input_consumed_pulse_wire :
        std_logic;

    -- ========================================================================
    -- Core -> serializer
    -- ========================================================================

    signal core_results :
        output_array_t(0 to C_K - 1);

    signal core_valid_out :
        std_logic;

    signal core_ce :
        std_logic;
    signal input_pixel_ready : std_logic;

    signal serializer_in_ready :
        std_logic;

    signal core_accept_pulse_wire :
        std_logic;

    -- ========================================================================
    -- Lifecycle control
    -- ========================================================================

    signal start_pulse_wire :
        std_logic;

    signal local_reset_wire :
        std_logic;

    signal run_enable_wire :
        std_logic;

    signal production_enable_wire :
        std_logic;

    signal stream_resetn :
        std_logic;

    -- ========================================================================
    -- Serializer / external output
    -- ========================================================================

    signal serializer_fifo_empty :
        std_logic;

    signal serialized_tdata :
        std_logic_vector(63 downto 0);

    signal serialized_tkeep :
        std_logic_vector(7 downto 0);

    signal serialized_tvalid :
        std_logic;

    signal serialized_tlast :
        std_logic;

    -- ========================================================================
    -- External output -> lifecycle controller events
    -- ========================================================================

    signal output_accept_valid_wire :
        std_logic;

    signal output_accept_bytes_wire :
        std_logic_vector(3 downto 0);

    signal output_accept_last_wire :
        std_logic;

    -- No separate external invariant source exists yet. axi_lite_ctrl itself
    -- still detects its own counter/protocol invariants.
    signal internal_error_wire :
        std_logic;

    -- ========================================================================
    -- Helper
    -- ========================================================================

    function popcount8(
        value : std_logic_vector(7 downto 0)
    ) return natural is
        variable count :
            natural range 0 to 8 := 0;
    begin

        for lane in 0 to 7 loop

            if value(lane) = '1' then
                count := count + 1;
            end if;

        end loop;

        return count;

    end function popcount8;

begin

    -- ========================================================================
    -- Geometry consistency
    --
    -- CVH1 software supplies external zero padding:
    --
    --   padded W = logical W + N - 1
    --   padded H = logical H + N - 1
    --
    -- Keep the streamed frontend and controller discovery mathematically
    -- identical.
    -- ========================================================================

    assert
        C_IMAGE_WIDTH =
        C_OUTPUT_IMAGE_WIDTH + C_N - 1
        report
            "CVH1 padded image width does not match logical width + N - 1"
        severity failure;


    assert
        C_IMAGE_HEIGHT =
        C_OUTPUT_IMAGE_HEIGHT + C_N - 1
        report
            "CVH1 padded image height does not match logical height + N - 1"
        severity failure;


    -- ========================================================================
    -- Local RESET
    --
    -- Only an admitted COMMAND.RESET drives this pulse.
    --
    -- ABORT/FAULT must NOT reset either stream FIFO because already queued
    -- output is allowed to drain during FAULT.
    -- ========================================================================

    stream_resetn <=
        resetn and not local_reset_wire;


    -- ========================================================================
    -- Core backpressure
    --
    -- Retain the original rule: freeze the compute pipeline only when it is
    -- presenting a valid result vector that the serializer cannot accept.
    --
    -- conv_top additionally gates its internal datapath CE with RUN, so an
    -- ABORT/FAULT also freezes compute from the following cycle.
    -- ========================================================================

    core_ce <=
        '0'
        when
            core_valid_out = '1'
            and serializer_in_ready = '0'
        else '1';


    -- ========================================================================
    -- External AXI output
    --
    -- Do NOT mask TVALID with RUN or production_enable.
    --
    -- During FAULT the serializer's formatter is frozen, but already queued
    -- FIFO words must remain visible and drain normally.
    -- ========================================================================

    m_axis_tdata <=
        serialized_tdata;

    m_axis_tkeep <=
        serialized_tkeep;

    m_axis_tvalid <=
        serialized_tvalid;

    m_axis_tlast <=
        serialized_tlast;


    -- ========================================================================
    -- External output acceptance events
    -- ========================================================================

    output_accept_valid_wire <=
        '1'
        when
            serialized_tvalid = '1'
            and m_axis_tready = '1'
        else '0';


    output_accept_bytes_wire <=
        std_logic_vector(
            to_unsigned(
                popcount8(serialized_tkeep),
                output_accept_bytes_wire'length
            )
        );


    output_accept_last_wire <=
        '1'
        when
            output_accept_valid_wire = '1'
            and serialized_tlast = '1'
        else '0';


    internal_error_wire <=
        '0';


    -- ========================================================================
    -- Strict CVH1 input frontend
    -- ========================================================================

    input_frontend_inst :
        entity work.axi_stream_input_frontend
        generic map (
            C_FIFO_DEPTH =>
                16,

            C_EXPECTED_INPUT_BYTES =>
                C_EXPECTED_INPUT_BYTES
        )
        port map (
            clk =>
                clk,

            resetn =>
                stream_resetn,

            start_pulse =>
                start_pulse_wire,

            run_enable =>
                run_enable_wire,

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

            accept_valid =>
                input_accept_valid_wire,

            accept_bytes =>
                input_accept_bytes_wire,

            frame_error =>
                input_frame_error_wire,

            consumed_pulse =>
                input_consumed_pulse_wire,

            out_pixel =>
                input_pixel,

            out_valid =>
                input_pixel_valid,

            out_ready =>
                input_pixel_ready,

            out_last =>
                input_pixel_last
        );


    -- ========================================================================
    -- Core + AXI-Lite lifecycle controller
    -- ========================================================================

    conv_top_inst :
        entity work.conv_top
        generic map (
            C_WINDOW_PREFETCH => C_WINDOW_PREFETCH,
            C_K =>
                C_K,

            C_N =>
                C_N,

            C_IMAGE_WIDTH =>
                C_IMAGE_WIDTH,

            C_IMAGE_HEIGHT =>
                C_IMAGE_HEIGHT,

            C_LOGICAL_IMAGE_WIDTH =>
                C_OUTPUT_IMAGE_WIDTH,

            C_LOGICAL_IMAGE_HEIGHT =>
                C_OUTPUT_IMAGE_HEIGHT,

            C_S_AXI_DATA_WIDTH =>
                C_S_AXI_DATA_WIDTH,

            C_S_AXI_ADDR_WIDTH =>
                C_S_AXI_ADDR_WIDTH,

            C_BUILD_ID =>
                C_BUILD_ID,

            C_DMA_LENGTH_WIDTH =>
                C_DMA_LENGTH_WIDTH
        )
        port map (
            clk =>
                clk,

            resetn =>
                resetn,

            ce =>
                core_ce,

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
                input_accept_valid_wire,

            input_accept_bytes =>
                input_accept_bytes_wire,

            input_consumed_pulse =>
                input_consumed_pulse_wire,

            input_frame_error =>
                input_frame_error_wire,

            core_accept_pulse =>
                core_accept_pulse_wire,

            output_accept_valid =>
                output_accept_valid_wire,

            output_accept_bytes =>
                output_accept_bytes_wire,

            output_accept_last =>
                output_accept_last_wire,

            output_fifo_empty =>
                serializer_fifo_empty,

            output_tvalid =>
                serialized_tvalid,

            internal_error_in =>
                internal_error_wire,

            start_pulse_out =>
                start_pulse_wire,

            local_reset_out =>
                local_reset_wire,

            run_enable_out =>
                run_enable_wire,

            production_enable_out =>
                production_enable_wire,

            pixel_in =>
                input_pixel,

            pixel_ready => input_pixel_ready,

            valid_in =>
                input_pixel_valid,

            results_out =>
                core_results,

            valid_out =>
                core_valid_out
        );


    -- ========================================================================
    -- CVH1 output serializer
    -- ========================================================================

    output_serializer_inst :
        entity work.axi_stream_output_serializer
        generic map (
            C_K =>
                C_K,

            C_IMAGE_WIDTH =>
                C_OUTPUT_IMAGE_WIDTH,

            C_IMAGE_HEIGHT =>
                C_OUTPUT_IMAGE_HEIGHT,

            C_FIFO_DEPTH =>
                16
        )
        port map (
            clk =>
                clk,

            resetn =>
                stream_resetn,

            production_enable =>
                production_enable_wire,

            in_results =>
                core_results,

            in_valid =>
                core_valid_out,

            in_ready =>
                serializer_in_ready,

            core_accept_pulse =>
                core_accept_pulse_wire,

            fifo_empty =>
                serializer_fifo_empty,

            m_axis_tdata =>
                serialized_tdata,

            m_axis_tkeep =>
                serialized_tkeep,

            m_axis_tvalid =>
                serialized_tvalid,

            m_axis_tready =>
                m_axis_tready,

            m_axis_tlast =>
                serialized_tlast
        );

end architecture rtl;
