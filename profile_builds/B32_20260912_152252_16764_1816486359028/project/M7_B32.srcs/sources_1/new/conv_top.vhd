-- ============================================================================
-- conv_top.vhd — CVH1 Convolution Core Top
-- ============================================================================
-- Wires together:
--
--   AXI4-Lite ──► axi_lite_ctrl ──► parameter registers
--                       │
--                       ├── lifecycle control / status
--                       │
--   pixel_in ──► window_generator ──► conv_engine ──► results_out
--
-- Lifecycle policy belongs to axi_lite_ctrl.
-- This file remains primarily an integration/wiring layer.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;


entity conv_top is
    generic (
        C_K : integer := CFG_K;
        C_N : integer := CFG_N;

        C_IMAGE_WIDTH  : integer := CFG_IMAGE_WIDTH;
        C_IMAGE_HEIGHT : integer := CFG_IMAGE_HEIGHT;

        C_LOGICAL_IMAGE_WIDTH  : integer := CFG_UNPADDED_WIDTH;
        C_LOGICAL_IMAGE_HEIGHT : integer := CFG_UNPADDED_HEIGHT;

        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 32;

        -- Frozen identity of the explicitly selected integrated profile.
        C_BUILD_ID : std_logic_vector(127 downto 0) :=
            CFG_BUILD_ID;

        C_DMA_LENGTH_WIDTH : integer := 22
    );
    port (
        -- ====================================================================
        -- Clock / hard reset
        -- ====================================================================
        clk    : in std_logic;
        resetn : in std_logic;

        -- Datapath backpressure advance request from streamed wrapper.
        -- Actual compute advance is additionally gated by CVH1 RUN state.
        ce : in std_logic;

        -- ====================================================================
        -- AXI4-Lite slave — configuration / lifecycle interface
        -- ====================================================================
        S_AXI_AWADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_AWPROT  : in std_logic_vector(2 downto 0);
        S_AXI_AWVALID : in std_logic;
        S_AXI_AWREADY : out std_logic;

        S_AXI_WDATA   : in std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        S_AXI_WSTRB   : in std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
        S_AXI_WVALID  : in std_logic;
        S_AXI_WREADY  : out std_logic;

        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in std_logic;

        S_AXI_ARADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_ARPROT  : in std_logic_vector(2 downto 0);
        S_AXI_ARVALID : in std_logic;
        S_AXI_ARREADY : out std_logic;

        S_AXI_RDATA   : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in std_logic;

        -- ====================================================================
        -- CVH1 stream/lifecycle observations
        --
        -- These originate in the streamed wrapper/frontend/serializer and are
        -- passed directly to axi_lite_ctrl, which owns lifecycle policy.
        -- ====================================================================

        -- External input AXIS beat accepted.
        input_accept_valid : in std_logic;
        input_accept_bytes : in std_logic_vector(3 downto 0);

        -- One pixel byte accepted from frontend into the convolution datapath.
        input_consumed_pulse : in std_logic;

        -- Accepted malformed input framing event.
        input_frame_error : in std_logic;

        -- One complete K-channel output vector accepted by serializer.
        core_accept_pulse : in std_logic;

        -- External output AXIS beat accepted.
        output_accept_valid : in std_logic;
        output_accept_bytes : in std_logic_vector(3 downto 0);
        output_accept_last  : in std_logic;

        -- Required to derive CVH1 QUIESCENT.
        output_fifo_empty : in std_logic;
        output_tvalid     : in std_logic;

        -- Datapath/stream invariant failure.
        internal_error_in : in std_logic;

        -- ====================================================================
        -- CVH1 lifecycle controls toward streamed wrapper
        -- ====================================================================

        -- Admitted COMMAND.START pulse.
        start_pulse_out : out std_logic;

        -- Admitted COMMAND.RESET pulse.
        -- Used here to clear window/engine history and exported upward so the
        -- wrapper can reset frontend/serializer history on the same command.
        local_reset_out : out std_logic;

        -- High only while controller state is RUN.
        run_enable_out : out std_logic;

        -- High only while new output production is permitted.
        -- Currently follows RUN; separated architecturally for serializer use.
        production_enable_out : out std_logic;

        -- ====================================================================
        -- Pixel stream from input frontend
        -- ====================================================================
        pixel_in : in std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0);
        valid_in : in std_logic;

        -- ====================================================================
        -- K-channel convolution output
        -- ====================================================================
        results_out : out output_array_t(0 to C_K - 1);
        valid_out   : out std_logic
    );
end entity conv_top;


architecture rtl of conv_top is

    -- ========================================================================
    -- Parameter register file -> compute engine
    -- ========================================================================

    signal coeffs_wire :
        coeff_array_t(0 to C_K * C_N * C_N - 1);

    signal bias_wire :
        bias_array_t(0 to C_K - 1);

    signal shift_wire :
        shift_array_t(0 to C_K - 1);

    signal relu_en_wire :
        std_logic_vector(0 to C_K - 1);

    -- ========================================================================
    -- Window generator -> compute engine
    -- ========================================================================

    signal window_wire :
        pixel_array_t(0 to C_N * C_N - 1);

    signal window_valid_wire :
        std_logic;

    -- ========================================================================
    -- Lifecycle wiring
    -- ========================================================================

    signal start_pulse_wire :
        std_logic;

    signal local_reset_wire :
        std_logic;

    signal run_enable_wire :
        std_logic;

    signal production_enable_wire :
        std_logic;

    signal datapath_resetn :
        std_logic;

    signal datapath_ce :
        std_logic;

    signal datapath_valid_in :
        std_logic;

begin

    -- ========================================================================
    -- Lifecycle routing
    -- ========================================================================

    start_pulse_out <=
        start_pulse_wire;

    local_reset_out <=
        local_reset_wire;

    run_enable_out <=
        run_enable_wire;

    production_enable_out <=
        production_enable_wire;


    -- Local RESET clears only streamed compute history.
    --
    -- The AXI-Lite controller and parameter register file remain on the hard
    -- peripheral reset so COMMAND.RESET preserves installed parameters and
    -- PARAM_COMPLETE admission state.
    datapath_resetn <=
        resetn and not local_reset_wire;


    -- ABORT / FAULT removes RUN on the command/fault edge. Therefore from the
    -- following cycle the window generator and convolution pipeline cannot
    -- advance, even if the downstream wrapper would otherwise assert ce.
    datapath_ce <=
        ce and run_enable_wire;


    -- Defensive RUN gate. Under normal operation the frontend already prevents
    -- pixel production outside RUN, but conv_top does not rely on that alone.
    datapath_valid_in <=
        valid_in and run_enable_wire;


    -- ========================================================================
    -- AXI4-Lite controller + parameter register file
    -- ========================================================================

    axi_ctrl_inst :
        entity work.axi_lite_ctrl
        generic map (
            C_S_AXI_DATA_WIDTH =>
                C_S_AXI_DATA_WIDTH,

            C_S_AXI_ADDR_WIDTH =>
                C_S_AXI_ADDR_WIDTH,

            C_K =>
                C_K,

            C_N =>
                C_N,

            C_LOGICAL_IMAGE_WIDTH =>
                C_LOGICAL_IMAGE_WIDTH,

            C_LOGICAL_IMAGE_HEIGHT =>
                C_LOGICAL_IMAGE_HEIGHT,

            C_BUILD_ID =>
                C_BUILD_ID,

            C_DMA_LENGTH_WIDTH =>
                C_DMA_LENGTH_WIDTH
        )
        port map (
            S_AXI_ACLK =>
                clk,

            S_AXI_ARESETN =>
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

            start_pulse =>
                start_pulse_wire,

            local_reset_pulse =>
                local_reset_wire,

            run_enable =>
                run_enable_wire,

            production_enable =>
                production_enable_wire,

            coeffs_out =>
                coeffs_wire,

            bias_out =>
                bias_wire,

            shift_out =>
                shift_wire,

            relu_en_out =>
                relu_en_wire
        );


    -- ========================================================================
    -- Sliding window generator
    -- ========================================================================

    wingen_inst :
        entity work.window_generator
        generic map (
            C_N =>
                C_N,

            C_IMAGE_WIDTH =>
                C_IMAGE_WIDTH,

            C_IMAGE_HEIGHT =>
                C_IMAGE_HEIGHT
        )
        port map (
            clk =>
                clk,

            resetn =>
                datapath_resetn,

            ce =>
                datapath_ce,

            pixel_in =>
                pixel_in,

            valid_in =>
                datapath_valid_in,

            window_out =>
                window_wire,

            valid_out =>
                window_valid_wire
        );


    -- ========================================================================
    -- K-channel parallel convolution engine
    -- ========================================================================

    engine_inst :
        entity work.conv_engine
        generic map (
            C_K =>
                C_K,

            C_N =>
                C_N
        )
        port map (
            clk =>
                clk,

            resetn =>
                datapath_resetn,

            ce =>
                datapath_ce,

            window_in =>
                window_wire,

            valid_in =>
                window_valid_wire,

            coeffs_all =>
                coeffs_wire,

            bias_all =>
                bias_wire,

            shift_all =>
                shift_wire,

            relu_en_all =>
                relu_en_wire,

            results_out =>
                results_out,

            valid_out =>
                valid_out
        );

end architecture rtl;