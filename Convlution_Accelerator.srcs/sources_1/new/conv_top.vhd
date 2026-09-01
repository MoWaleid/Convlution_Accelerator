-- ============================================================================
-- conv_top.vhd — Top-Level Convolution Accelerator
-- ============================================================================
-- Wires together all sub-modules into a single accelerator block:
--
--   AXI4-Lite  ──►  axi_lite_ctrl  ──►  coeff/bias/shift/relu registers
--                                                │
--   pixel_in   ──►  window_generator  ──►────────┤
--                                                ▼
--                                          conv_engine  ──►  results_out
--                                          (K parallel)      valid_out
--
-- The AXI4-Lite port is used by the PS to program filter coefficients,
-- biases, shift values, and ReLU enables before streaming begins.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity conv_top is
    generic (
        C_K                : integer := CFG_K;
        C_N                : integer := CFG_N;
        C_IMAGE_WIDTH      : integer := CFG_IMAGE_WIDTH;
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 32
    );
    port (
        -- Clock and Reset
        clk    : in  std_logic;
        resetn : in  std_logic;

        -- ================================================================
        -- AXI4-Lite Slave — Configuration Interface (from Zynq PS)
        -- ================================================================
        S_AXI_AWADDR  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_AWPROT  : in  std_logic_vector(2 downto 0);
        S_AXI_AWVALID : in  std_logic;
        S_AXI_AWREADY : out std_logic;

        S_AXI_WDATA   : in  std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        S_AXI_WSTRB   : in  std_logic_vector((C_S_AXI_DATA_WIDTH / 8) - 1 downto 0);
        S_AXI_WVALID  : in  std_logic;
        S_AXI_WREADY  : out std_logic;

        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in  std_logic;

        S_AXI_ARADDR  : in  std_logic_vector(C_S_AXI_ADDR_WIDTH - 1 downto 0);
        S_AXI_ARPROT  : in  std_logic_vector(2 downto 0);
        S_AXI_ARVALID : in  std_logic;
        S_AXI_ARREADY : out std_logic;

        S_AXI_RDATA   : out std_logic_vector(C_S_AXI_DATA_WIDTH - 1 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in  std_logic;

        -- ================================================================
        -- Pixel Input Stream (from DMA or testbench)
        -- ================================================================
        pixel_in  : in  std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0);
        valid_in  : in  std_logic;

        -- ================================================================
        -- Output Feature Maps (K channels in parallel)
        -- ================================================================
        results_out : out output_array_t(0 to C_K - 1);
        valid_out   : out std_logic
    );
end entity conv_top;

architecture rtl of conv_top is

    -- Internal wiring: register file → compute engine
    signal coeffs_wire  : coeff_array_t(0 to C_K * C_N * C_N - 1);
    signal bias_wire    : bias_array_t(0 to C_K - 1);
    signal shift_wire   : shift_array_t(0 to C_K - 1);
    signal relu_en_wire : std_logic_vector(0 to C_K - 1);

    -- Internal wiring: window generator → compute engine
    signal window_wire       : pixel_array_t(0 to C_N * C_N - 1);
    signal window_valid_wire : std_logic;

begin

    -- ========================================================================
    -- AXI4-Lite Controller + Register File
    -- ========================================================================
    axi_ctrl_inst : entity work.axi_lite_ctrl
        generic map (
            C_S_AXI_DATA_WIDTH => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH,
            C_K                => C_K,
            C_N                => C_N
        )
        port map (
            S_AXI_ACLK    => clk,
            S_AXI_ARESETN => resetn,
            S_AXI_AWADDR  => S_AXI_AWADDR,
            S_AXI_AWPROT  => S_AXI_AWPROT,
            S_AXI_AWVALID => S_AXI_AWVALID,
            S_AXI_AWREADY => S_AXI_AWREADY,
            S_AXI_WDATA   => S_AXI_WDATA,
            S_AXI_WSTRB   => S_AXI_WSTRB,
            S_AXI_WVALID  => S_AXI_WVALID,
            S_AXI_WREADY  => S_AXI_WREADY,
            S_AXI_BRESP   => S_AXI_BRESP,
            S_AXI_BVALID  => S_AXI_BVALID,
            S_AXI_BREADY  => S_AXI_BREADY,
            S_AXI_ARADDR  => S_AXI_ARADDR,
            S_AXI_ARPROT  => S_AXI_ARPROT,
            S_AXI_ARVALID => S_AXI_ARVALID,
            S_AXI_ARREADY => S_AXI_ARREADY,
            S_AXI_RDATA   => S_AXI_RDATA,
            S_AXI_RRESP   => S_AXI_RRESP,
            S_AXI_RVALID  => S_AXI_RVALID,
            S_AXI_RREADY  => S_AXI_RREADY,
            coeffs_out    => coeffs_wire,
            bias_out      => bias_wire,
            shift_out     => shift_wire,
            relu_en_out   => relu_en_wire
        );

    -- ========================================================================
    -- Sliding Window Generator
    -- ========================================================================
    wingen_inst : entity work.window_generator
        generic map (
            C_N           => C_N,
            C_IMAGE_WIDTH => C_IMAGE_WIDTH
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            pixel_in   => pixel_in,
            valid_in   => valid_in,
            window_out => window_wire,
            valid_out  => window_valid_wire
        );

    -- ========================================================================
    -- K-Channel Parallel Convolution Engine
    -- ========================================================================
    engine_inst : entity work.conv_engine
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            window_in   => window_wire,
            valid_in    => window_valid_wire,
            coeffs_all  => coeffs_wire,
            bias_all    => bias_wire,
            shift_all   => shift_wire,
            relu_en_all => relu_en_wire,
            results_out => results_out,
            valid_out   => valid_out
        );

end architecture rtl;
