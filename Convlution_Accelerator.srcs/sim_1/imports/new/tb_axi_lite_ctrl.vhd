library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_axi_lite_ctrl is
-- Testbench has no ports
end tb_axi_lite_ctrl;

architecture sim of tb_axi_lite_ctrl is

    -- Component Declaration
    component axi_lite_ctrl is
        generic (
            C_S_AXI_DATA_WIDTH : integer := 32;
            C_S_AXI_ADDR_WIDTH : integer := 32;
            C_K                : integer := CFG_K;
            C_N                : integer := CFG_N
        );
        port (
            S_AXI_ACLK    : in std_logic;
            S_AXI_ARESETN : in std_logic;
            S_AXI_AWADDR  : in std_logic_vector(31 downto 0);
            S_AXI_AWPROT  : in std_logic_vector(2 downto 0);
            S_AXI_AWVALID : in std_logic;
            S_AXI_AWREADY : out std_logic;
            S_AXI_WDATA   : in std_logic_vector(31 downto 0);
            S_AXI_WSTRB   : in std_logic_vector(3 downto 0);
            S_AXI_WVALID  : in std_logic;
            S_AXI_WREADY  : out std_logic;
            S_AXI_BRESP   : out std_logic_vector(1 downto 0);
            S_AXI_BVALID  : out std_logic;
            S_AXI_BREADY  : in std_logic;
            S_AXI_ARADDR  : in std_logic_vector(31 downto 0);
            S_AXI_ARPROT  : in std_logic_vector(2 downto 0);
            S_AXI_ARVALID : in std_logic;
            S_AXI_ARREADY : out std_logic;
            S_AXI_RDATA   : out std_logic_vector(31 downto 0);
            S_AXI_RRESP   : out std_logic_vector(1 downto 0);
            S_AXI_RVALID  : out std_logic;
            S_AXI_RREADY  : in std_logic;
            coeffs_out    : out coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
            bias_out      : out bias_array_t(0 to CFG_K - 1);
            shift_out     : out shift_array_t(0 to CFG_K - 1);
            relu_en_out   : out std_logic_vector(0 to CFG_K - 1)
        );
    end component;

    -- Signals
    signal S_AXI_ACLK    : std_logic := '0';
    signal S_AXI_ARESETN : std_logic := '0';
    
    signal S_AXI_AWADDR  : std_logic_vector(31 downto 0) := (others => '0');
    signal S_AXI_AWPROT  : std_logic_vector(2 downto 0) := (others => '0');
    signal S_AXI_AWVALID : std_logic := '0';
    signal S_AXI_AWREADY : std_logic;
    
    signal S_AXI_WDATA   : std_logic_vector(31 downto 0) := (others => '0');
    signal S_AXI_WSTRB   : std_logic_vector(3 downto 0) := (others => '1');
    signal S_AXI_WVALID  : std_logic := '0';
    signal S_AXI_WREADY  : std_logic;
    
    signal S_AXI_BRESP   : std_logic_vector(1 downto 0);
    signal S_AXI_BVALID  : std_logic;
    signal S_AXI_BREADY  : std_logic := '0';
    
    signal S_AXI_ARADDR  : std_logic_vector(31 downto 0) := (others => '0');
    signal S_AXI_ARPROT  : std_logic_vector(2 downto 0) := (others => '0');
    signal S_AXI_ARVALID : std_logic := '0';
    signal S_AXI_ARREADY : std_logic;
    
    signal S_AXI_RDATA   : std_logic_vector(31 downto 0);
    signal S_AXI_RRESP   : std_logic_vector(1 downto 0);
    signal S_AXI_RVALID  : std_logic;
    signal S_AXI_RREADY  : std_logic := '0';
    
    signal coeffs_out    : coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
    signal bias_out      : bias_array_t(0 to CFG_K - 1);
    signal shift_out     : shift_array_t(0 to CFG_K - 1);
    signal relu_en_out   : std_logic_vector(0 to CFG_K - 1);

    constant CLK_PERIOD : time := 10 ns;

    -- AXI4-Lite Write Transaction Procedure
    procedure axi_write(
        signal clk      : in std_logic;
        address         : in std_logic_vector(31 downto 0);
        data            : in std_logic_vector(31 downto 0);
        signal awaddr   : out std_logic_vector(31 downto 0);
        signal awvalid  : out std_logic;
        signal awready  : in std_logic;
        signal wdata    : out std_logic_vector(31 downto 0);
        signal wvalid   : out std_logic;
        signal wready   : in std_logic;
        signal bvalid   : in std_logic;
        signal bready   : out std_logic
    ) is
    begin
        wait until rising_edge(clk);
        awaddr  <= address;
        awvalid <= '1';
        wdata   <= data;
        wvalid  <= '1';
        bready  <= '1';
        
        -- Wait for address and data to be accepted
        loop
            wait until rising_edge(clk);
            if awready = '1' and wready = '1' then
                awvalid <= '0';
                wvalid  <= '0';
                exit;
            end if;
        end loop;
        
        -- Wait for response
        loop
            wait until rising_edge(clk);
            if bvalid = '1' then
                bready <= '0';
                exit;
            end if;
        end loop;
    end procedure;

    -- AXI4-Lite Read Transaction Procedure
    procedure axi_read(
        signal clk      : in std_logic;
        address         : in std_logic_vector(31 downto 0);
        signal araddr   : out std_logic_vector(31 downto 0);
        signal arvalid  : out std_logic;
        signal arready  : in std_logic;
        signal rdata    : in std_logic_vector(31 downto 0);
        signal rvalid   : in std_logic;
        signal rready   : out std_logic;
        data_out        : out std_logic_vector(31 downto 0)
    ) is
    begin
        wait until rising_edge(clk);
        araddr  <= address;
        arvalid <= '1';
        rready  <= '1';
        
        -- Wait for address to be accepted
        loop
            wait until rising_edge(clk);
            if arready = '1' then
                arvalid <= '0';
                exit;
            end if;
        end loop;
        
        -- Wait for data
        loop
            wait until rising_edge(clk);
            if rvalid = '1' then
                data_out := rdata;
                rready <= '0';
                exit;
            end if;
        end loop;
    end procedure;

begin

    -- Instantiate the UUT
    uut: axi_lite_ctrl
        port map (
            S_AXI_ACLK    => S_AXI_ACLK,
            S_AXI_ARESETN => S_AXI_ARESETN,
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
            coeffs_out    => coeffs_out,
            bias_out      => bias_out,
            shift_out     => shift_out,
            relu_en_out   => relu_en_out
        );

    -- Clock generation
    clk_process :process
    begin
        S_AXI_ACLK <= '0';
        wait for CLK_PERIOD/2;
        S_AXI_ACLK <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus
    stim_proc: process
        variable read_back : std_logic_vector(31 downto 0);
    begin
        S_AXI_ARESETN <= '0';
        wait for 20 ns;
        S_AXI_ARESETN <= '1';
        wait for 20 ns;
        
        report "--- Starting AXI-Lite Wrapper Testbench ---";

        -- Write to Channel 0 Bias (Address 0x0080)
        axi_write(S_AXI_ACLK, x"00000080", x"DEADBEEF", S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY, S_AXI_WDATA, S_AXI_WVALID, S_AXI_WREADY, S_AXI_BVALID, S_AXI_BREADY);
        
        -- Write to Channel 1 Shift/ReLU (Address 0x0184)
        axi_write(S_AXI_ACLK, x"00000184", x"00000115", S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY, S_AXI_WDATA, S_AXI_WVALID, S_AXI_WREADY, S_AXI_BVALID, S_AXI_BREADY);

        -- Read back Channel 0 Bias
        axi_read(S_AXI_ACLK, x"00000080", S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY, S_AXI_RDATA, S_AXI_RVALID, S_AXI_RREADY, read_back);
        assert read_back = x"DEADBEEF" report "Readback error on Channel 0 Bias" severity error;

        -- Read back Channel 1 Shift/ReLU
        axi_read(S_AXI_ACLK, x"00000184", S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY, S_AXI_RDATA, S_AXI_RVALID, S_AXI_RREADY, read_back);
        assert read_back = x"00000115" report "Readback error on Channel 1 Shift/ReLU" severity error;

        wait for 100 ns;
        report "--- All AXI-Lite tests completed successfully ---";
        wait;
    end process;

end sim;
