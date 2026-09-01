library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity axi_lite_ctrl is
    generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 32;
        C_K                : integer := CFG_K;
        C_N                : integer := CFG_N
    );
    port (
        -- AXI4-Lite Interface
        S_AXI_ACLK    : in std_logic;
        S_AXI_ARESETN : in std_logic;
        
        -- Write Address Channel
        S_AXI_AWADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_AWPROT  : in std_logic_vector(2 downto 0);
        S_AXI_AWVALID : in std_logic;
        S_AXI_AWREADY : out std_logic;
        
        -- Write Data Channel
        S_AXI_WDATA   : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_WSTRB   : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        S_AXI_WVALID  : in std_logic;
        S_AXI_WREADY  : out std_logic;
        
        -- Write Response Channel
        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in std_logic;
        
        -- Read Address Channel
        S_AXI_ARADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_ARPROT  : in std_logic_vector(2 downto 0);
        S_AXI_ARVALID : in std_logic;
        S_AXI_ARREADY : out std_logic;
        
        -- Read Data Channel
        S_AXI_RDATA   : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in std_logic;
        
        -- Outputs to Accelerator Datapath
        coeffs_out    : out coeff_array_t(0 to C_K * C_N * C_N - 1);
        bias_out      : out bias_array_t(0 to C_K - 1);
        shift_out     : out shift_array_t(0 to C_K - 1);
        relu_en_out   : out std_logic_vector(0 to C_K - 1)
    );
end entity axi_lite_ctrl;

architecture rtl of axi_lite_ctrl is

    -- Internal AXI signals
    signal axi_awready : std_logic;
    signal axi_wready  : std_logic;
    signal axi_bvalid  : std_logic;
    signal axi_arready : std_logic;
    signal axi_rvalid  : std_logic;
    
    -- Internal Register File Interface
    signal rf_wr_en   : std_logic;
    signal rf_wr_addr : std_logic_vector(31 downto 0);
    signal rf_wr_data : std_logic_vector(31 downto 0);
    signal rf_rd_en   : std_logic;
    signal rf_rd_addr : std_logic_vector(31 downto 0);
    signal rf_rd_data : std_logic_vector(31 downto 0);

    -- Helper state for reading
    type read_state_t is (IDLE, WAIT_RD);
    signal read_state : read_state_t;

begin

    -- Assign AXI outputs
    S_AXI_AWREADY <= axi_awready;
    S_AXI_WREADY  <= axi_wready;
    S_AXI_BRESP   <= "00"; -- Always OKAY
    S_AXI_BVALID  <= axi_bvalid;
    S_AXI_ARREADY <= axi_arready;
    S_AXI_RRESP   <= "00"; -- Always OKAY
    S_AXI_RVALID  <= axi_rvalid;

    -- =========================================================================
    -- AXI Write Channel Logic
    -- =========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                axi_awready <= '0';
                axi_wready  <= '0';
                axi_bvalid  <= '0';
                rf_wr_en    <= '0';
                rf_wr_addr  <= (others => '0');
                rf_wr_data  <= (others => '0');
            else
                -- Default: de-assert write enable
                rf_wr_en <= '0';
                
                -- Accept Address and Data simultaneously
                if axi_awready = '0' and axi_wready = '0' and S_AXI_AWVALID = '1' and S_AXI_WVALID = '1' then
                    axi_awready <= '1';
                    axi_wready  <= '1';
                    
                    -- Trigger write to register file
                    rf_wr_en   <= '1';
                    rf_wr_addr <= std_logic_vector(resize(unsigned(S_AXI_AWADDR), 32));
                    rf_wr_data <= S_AXI_WDATA;
                else
                    axi_awready <= '0';
                    axi_wready  <= '0';
                end if;
                
                -- Response Channel
                if axi_awready = '1' and S_AXI_AWVALID = '1' and axi_wready = '1' and S_AXI_WVALID = '1' and axi_bvalid = '0' then
                    axi_bvalid <= '1';
                elsif S_AXI_BREADY = '1' and axi_bvalid = '1' then
                    axi_bvalid <= '0';
                end if;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- AXI Read Channel Logic
    -- =========================================================================
    process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                axi_arready <= '0';
                axi_rvalid  <= '0';
                S_AXI_RDATA <= (others => '0');
                rf_rd_en    <= '0';
                rf_rd_addr  <= (others => '0');
                read_state  <= IDLE;
            else
                -- Default: de-assert read enable
                rf_rd_en <= '0';
                
                case read_state is
                    when IDLE =>
                        if S_AXI_ARVALID = '1' and axi_arready = '0' then
                            axi_arready <= '1';
                            rf_rd_en    <= '1';
                            rf_rd_addr  <= std_logic_vector(resize(unsigned(S_AXI_ARADDR), 32));
                            read_state  <= WAIT_RD;
                        else
                            axi_arready <= '0';
                        end if;
                        
                    when WAIT_RD =>
                        -- ARREADY is de-asserted
                        axi_arready <= '0';
                        
                        -- The data from regfile is available this cycle (1 cycle latency)
                        S_AXI_RDATA <= rf_rd_data;
                        axi_rvalid  <= '1';
                        
                        -- Wait for master to accept data
                        if S_AXI_RREADY = '1' and axi_rvalid = '1' then
                            axi_rvalid <= '0';
                            read_state <= IDLE;
                        end if;
                end case;
            end if;
        end if;
    end process;

    -- =========================================================================
    -- Instantiate Register File
    -- =========================================================================
    regfile_inst : entity work.coeff_bias_shift_regfile
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk         => S_AXI_ACLK,
            resetn      => S_AXI_ARESETN,
            wr_en       => rf_wr_en,
            wr_addr     => rf_wr_addr,
            wr_data     => rf_wr_data,
            rd_en       => rf_rd_en,
            rd_addr     => rf_rd_addr,
            rd_data     => rf_rd_data,
            coeffs_out  => coeffs_out,
            bias_out    => bias_out,
            shift_out   => shift_out,
            relu_en_out => relu_en_out
        );

end architecture rtl;
