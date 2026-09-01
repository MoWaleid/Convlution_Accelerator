-- ============================================================================
-- conv_axis_wrapper.vhd -- AXI4-Lite-controlled convolution with AXI4-Stream I/O
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity conv_axis_wrapper is
    generic (
        C_K                  : positive := CFG_K;
        C_N                  : positive := CFG_N;
        C_IMAGE_WIDTH        : positive := CFG_IMAGE_WIDTH;
        C_IMAGE_HEIGHT       : positive := CFG_IMAGE_HEIGHT;
        C_OUTPUT_IMAGE_WIDTH : positive := CFG_UNPADDED_WIDTH;
        C_OUTPUT_IMAGE_HEIGHT : positive := CFG_UNPADDED_HEIGHT;
        C_S_AXI_DATA_WIDTH   : positive := 32;
        C_S_AXI_ADDR_WIDTH   : positive := 32
    );
    port (
        clk    : in  std_logic;
        resetn : in  std_logic;

        -- AXI4-Lite control plane (unchanged from conv_top).
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

        -- 64-bit AXI4-Stream input.
        s_axis_tdata  : in  std_logic_vector(63 downto 0);
        s_axis_tkeep  : in  std_logic_vector(7 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic;

        -- 64-bit AXI4-Stream output.
        m_axis_tdata  : out std_logic_vector(63 downto 0);
        m_axis_tkeep  : out std_logic_vector(7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end entity conv_axis_wrapper;

architecture rtl of conv_axis_wrapper is
    signal input_pixel      : std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0);
    signal input_pixel_valid : std_logic;
    signal input_pixel_last  : std_logic;

    signal core_results   : output_array_t(0 to C_K - 1);
    signal core_valid_out : std_logic;
    signal core_ce        : std_logic;
    signal serializer_in_ready : std_logic;
    signal frame_busy     : std_logic := '0';
begin
    -- Freeze only an occupied core output that the serializer cannot accept.
    -- This dependency is acyclic: serializer_in_ready is independent of core_ce.
    core_ce <= '0' when core_valid_out = '1' and serializer_in_ready = '0' else '1';

    -- A frame begins with the first accepted AXI input beat and remains busy
    -- until its final serialized AXI output beat is accepted. Starting a new
    -- frame as the previous frame completes keeps BUSY asserted.
    frame_busy_process : process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                frame_busy <= '0';
            elsif s_axis_tvalid = '1' and s_axis_tready = '1' then
                frame_busy <= '1';
            elsif m_axis_tvalid = '1' and m_axis_tready = '1' and m_axis_tlast = '1' then
                frame_busy <= '0';
            end if;
        end if;
    end process frame_busy_process;

    input_frontend_inst : entity work.axi_stream_input_frontend
        port map (
            clk           => clk,
            resetn        => resetn,
            s_axis_tdata  => s_axis_tdata,
            s_axis_tkeep  => s_axis_tkeep,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            out_pixel     => input_pixel,
            out_valid     => input_pixel_valid,
            out_ready     => core_ce,
            -- Retained as input-frame boundary information only; geometry is static.
            out_last      => input_pixel_last
        );

    conv_top_inst : entity work.conv_top
        generic map (
            C_K                => C_K,
            C_N                => C_N,
            C_IMAGE_WIDTH          => C_IMAGE_WIDTH,
            C_IMAGE_HEIGHT         => C_IMAGE_HEIGHT,
            C_LOGICAL_IMAGE_WIDTH  => C_OUTPUT_IMAGE_WIDTH,
            C_LOGICAL_IMAGE_HEIGHT => C_OUTPUT_IMAGE_HEIGHT,
            C_S_AXI_DATA_WIDTH     => C_S_AXI_DATA_WIDTH,
            C_S_AXI_ADDR_WIDTH => C_S_AXI_ADDR_WIDTH
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            ce            => core_ce,
            busy_in       => frame_busy,
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
            pixel_in      => input_pixel,
            valid_in      => input_pixel_valid,
            results_out   => core_results,
            valid_out     => core_valid_out
        );

    output_serializer_inst : entity work.axi_stream_output_serializer
        generic map (
            C_K            => C_K,
            C_IMAGE_WIDTH  => C_OUTPUT_IMAGE_WIDTH,
            C_IMAGE_HEIGHT => C_OUTPUT_IMAGE_HEIGHT
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            in_results    => core_results,
            in_valid      => core_valid_out,
            in_ready      => serializer_in_ready,
            m_axis_tdata  => m_axis_tdata,
            m_axis_tkeep  => m_axis_tkeep,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast  => m_axis_tlast
        );
end architecture rtl;