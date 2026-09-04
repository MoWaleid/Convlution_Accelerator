library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_axi_lite_ctrl is
end tb_axi_lite_ctrl;

architecture sim of tb_axi_lite_ctrl is

    component axi_lite_ctrl is
        generic (
            C_S_AXI_DATA_WIDTH : integer := 32;
            C_S_AXI_ADDR_WIDTH : integer := 32;
            C_K                    : integer := CFG_K;
            C_N                    : integer := CFG_N;
            C_LOGICAL_IMAGE_WIDTH  : integer := CFG_UNPADDED_WIDTH;
            C_LOGICAL_IMAGE_HEIGHT : integer := CFG_UNPADDED_HEIGHT
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
            status_busy   : in std_logic;
            soft_reset    : out std_logic;
            coeffs_out    : out coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
            bias_out      : out bias_array_t(0 to CFG_K - 1);
            shift_out     : out shift_array_t(0 to CFG_K - 1);
            relu_en_out   : out std_logic_vector(0 to CFG_K - 1)
        );
    end component;

    signal S_AXI_ACLK    : std_logic := '0';
    signal S_AXI_ARESETN : std_logic := '0';

    signal S_AXI_AWADDR  : std_logic_vector(31 downto 0) := (others => '0');
    signal S_AXI_AWPROT  : std_logic_vector(2 downto 0) := (others => '0');
    signal S_AXI_AWVALID : std_logic := '0';
    signal S_AXI_AWREADY : std_logic;

    signal S_AXI_WDATA   : std_logic_vector(31 downto 0) := (others => '0');
    signal S_AXI_WSTRB   : std_logic_vector(3 downto 0) := (others => '0');
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
    signal status_busy   : std_logic := '0';
    signal soft_reset    : std_logic;

    signal coeffs_out    : coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
    signal bias_out      : bias_array_t(0 to CFG_K - 1);
    signal shift_out     : shift_array_t(0 to CFG_K - 1);
    signal relu_en_out   : std_logic_vector(0 to CFG_K - 1);

    constant CLK_PERIOD : time := 10 ns;

    -- Authoritative per-channel map: coefficients at +0x00, bias at +0xF8,
    -- and shift/ReLU control at +0xFC.
    constant CH0_COEFF0_ADDR : std_logic_vector(31 downto 0) := x"00000000";
    constant CH0_COEFF1_ADDR : std_logic_vector(31 downto 0) := x"00000004";
    constant CH0_BIAS_ADDR   : std_logic_vector(31 downto 0) := x"000000F8";
    constant CH1_CTRL_ADDR   : std_logic_vector(31 downto 0) := x"000001FC";
    constant STATUS_ADDR       : std_logic_vector(31 downto 0) := x"00004000";
    constant CONTROL_ADDR      : std_logic_vector(31 downto 0) := x"00004004";
    constant BUILD_CONFIG_ADDR : std_logic_vector(31 downto 0) := x"00004008";
    constant IMAGE_DIMS_ADDR   : std_logic_vector(31 downto 0) := x"0000400C";
    constant BUILD_CONFIG_EXPECTED : std_logic_vector(31 downto 0) :=
        std_logic_vector(to_unsigned(0, 16)) &
        std_logic_vector(to_unsigned(CFG_K, 8)) &
        std_logic_vector(to_unsigned(CFG_N, 8));

    procedure send_aw(
        signal clk     : in std_logic;
        constant addr  : in std_logic_vector(31 downto 0);
        signal awaddr  : out std_logic_vector(31 downto 0);
        signal awvalid : out std_logic;
        signal awready : in std_logic
    ) is
    begin
        awaddr <= addr;
        loop
            wait until falling_edge(clk);
            exit when awready = '1';
        end loop;
        awvalid <= '1';
        wait until rising_edge(clk);
        awvalid <= '0';
    end procedure;

    procedure send_w(
        signal clk    : in std_logic;
        constant data : in std_logic_vector(31 downto 0);
        constant strb : in std_logic_vector(3 downto 0);
        signal wdata  : out std_logic_vector(31 downto 0);
        signal wstrb  : out std_logic_vector(3 downto 0);
        signal wvalid : out std_logic;
        signal wready : in std_logic
    ) is
    begin
        wdata <= data;
        wstrb <= strb;
        loop
            wait until falling_edge(clk);
            exit when wready = '1';
        end loop;
        wvalid <= '1';
        wait until rising_edge(clk);
        wvalid <= '0';
    end procedure;

    procedure write_same_cycle(
        signal clk     : in std_logic;
        constant addr  : in std_logic_vector(31 downto 0);
        constant data  : in std_logic_vector(31 downto 0);
        constant strb  : in std_logic_vector(3 downto 0);
        signal awaddr  : out std_logic_vector(31 downto 0);
        signal awvalid : out std_logic;
        signal awready : in std_logic;
        signal wdata   : out std_logic_vector(31 downto 0);
        signal wstrb   : out std_logic_vector(3 downto 0);
        signal wvalid  : out std_logic;
        signal wready  : in std_logic
    ) is
    begin
        awaddr <= addr;
        wdata <= data;
        wstrb <= strb;
        loop
            wait until falling_edge(clk);
            exit when awready = '1' and wready = '1';
        end loop;
        awvalid <= '1';
        wvalid <= '1';
        wait until rising_edge(clk);
        awvalid <= '0';
        wvalid <= '0';
    end procedure;

    procedure complete_write_response(
        signal clk         : in std_logic;
        signal bvalid      : in std_logic;
        signal bresp       : in std_logic_vector(1 downto 0);
        signal bready      : out std_logic;
        constant hold_cycles : in natural;
        constant tag       : in string
    ) is
    begin
        bready <= '0';
        loop
            wait until falling_edge(clk);
            exit when bvalid = '1';
        end loop;
        assert bresp = "00" report tag & ": BRESP was not OKAY" severity error;

        for i in 1 to hold_cycles loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert bvalid = '1' report tag & ": BVALID dropped before BREADY" severity error;
            assert bresp = "00" report tag & ": BRESP changed while BVALID was held" severity error;
        end loop;

        wait until falling_edge(clk);
        assert bvalid = '1' report tag & ": missing write response" severity error;
        bready <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        bready <= '0';
        wait until falling_edge(clk);
        assert bvalid = '0' report tag & ": BVALID did not clear after B handshake" severity error;
        wait until rising_edge(clk);
        wait for 1 ns;
        assert bvalid = '0' report tag & ": duplicate write response observed" severity error;
    end procedure;

    procedure send_ar(
        signal clk     : in std_logic;
        constant addr  : in std_logic_vector(31 downto 0);
        signal araddr  : out std_logic_vector(31 downto 0);
        signal arvalid : out std_logic;
        signal arready : in std_logic
    ) is
    begin
        araddr <= addr;
        loop
            wait until falling_edge(clk);
            exit when arready = '1';
        end loop;
        arvalid <= '1';
        wait until rising_edge(clk);
        arvalid <= '0';
    end procedure;

    procedure complete_read_response(
        signal clk          : in std_logic;
        signal rvalid       : in std_logic;
        signal rresp        : in std_logic_vector(1 downto 0);
        signal rdata        : in std_logic_vector(31 downto 0);
        signal rready       : out std_logic;
        constant expected   : in std_logic_vector(31 downto 0);
        constant hold_cycles : in natural;
        constant tag        : in string
    ) is
    begin
        rready <= '0';
        loop
            wait until falling_edge(clk);
            exit when rvalid = '1';
        end loop;
        assert rresp = "00" report tag & ": RRESP was not OKAY" severity error;
        assert rdata = expected report tag & ": incorrect RDATA" severity error;

        for i in 1 to hold_cycles loop
            wait until rising_edge(clk);
            wait for 1 ns;
            assert rvalid = '1' report tag & ": RVALID dropped before RREADY" severity error;
            assert rresp = "00" report tag & ": RRESP changed while RVALID was held" severity error;
            assert rdata = expected report tag & ": RDATA changed while RVALID was held" severity error;
        end loop;

        wait until falling_edge(clk);
        assert rvalid = '1' report tag & ": missing read response" severity error;
        rready <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        rready <= '0';
        wait until falling_edge(clk);
        assert rvalid = '0' report tag & ": RVALID did not clear after R handshake" severity error;
        wait until rising_edge(clk);
        wait for 1 ns;
        assert rvalid = '0' report tag & ": duplicate read response observed" severity error;
    end procedure;

begin

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
            status_busy   => status_busy,
            soft_reset    => soft_reset,
            coeffs_out    => coeffs_out,
            bias_out      => bias_out,
            shift_out     => shift_out,
            relu_en_out   => relu_en_out
        );

    clk_process : process
    begin
        S_AXI_ACLK <= '0';
        wait for CLK_PERIOD / 2;
        S_AXI_ACLK <= '1';
        wait for CLK_PERIOD / 2;
    end process;

    stim_proc : process
    begin
        S_AXI_ARESETN <= '0';
        wait for 30 ns;
        wait until falling_edge(S_AXI_ACLK);
        S_AXI_ARESETN <= '1';
        wait until falling_edge(S_AXI_ACLK);

        report "--- Starting AXI4-Lite protocol regression ---";

        -- Global read-only registers are outside the frozen 64-channel space.
        send_ar(S_AXI_ACLK, STATUS_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000001", 1, "idle status readback");
        send_ar(S_AXI_ACLK, BUILD_CONFIG_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               BUILD_CONFIG_EXPECTED, 0, "build configuration readback");
        send_ar(S_AXI_ACLK, IMAGE_DIMS_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00200020", 0, "logical image dimensions readback");
        status_busy <= '1';
        wait until falling_edge(S_AXI_ACLK);
        send_ar(S_AXI_ACLK, STATUS_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000002", 1, "busy status readback");
        status_busy <= '0';

        -- CONTROL reads as zero. Bit 0 only resets with byte lane 0 enabled.
        send_ar(S_AXI_ACLK, CONTROL_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000000", 0, "CONTROL readback before writes");
        write_same_cycle(S_AXI_ACLK, CONTROL_ADDR, x"00000000", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        wait for 1 ns;
        assert soft_reset = '0'
            report "CONTROL bit 0 clear unexpectedly triggered soft reset" severity error;
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "CONTROL bit-0-clear write response");
        write_same_cycle(S_AXI_ACLK, CONTROL_ADDR, x"00000001", "0010",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        wait for 1 ns;
        assert soft_reset = '0'
            report "CONTROL write without WSTRB[0] unexpectedly triggered soft reset" severity error;
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "CONTROL unstrobed byte-0 write response");
        write_same_cycle(S_AXI_ACLK, CONTROL_ADDR, x"00000001", "0001",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        wait for 1 ns;
        assert soft_reset = '1'
            report "CONTROL bit-0 command did not generate soft reset pulse" severity error;
        wait until rising_edge(S_AXI_ACLK);
        wait for 1 ns;
        assert soft_reset = '0'
            report "CONTROL soft reset command lasted longer than one clock" severity error;
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "CONTROL soft reset command response");
        send_ar(S_AXI_ACLK, CONTROL_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000000", 0, "CONTROL readback after writes");

        -- Global registers are read-only and must not alias channel 0. The
        -- reserved 0x4004 location likewise reads as zero.
        write_same_cycle(S_AXI_ACLK, STATUS_ADDR, x"DEADBEEF", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "read-only STATUS write response");
        assert coeffs_out(0) = x"00"
            report "global STATUS write aliased channel-0 coefficient storage" severity error;
        send_ar(S_AXI_ACLK, STATUS_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000001", 0, "read-only STATUS preserved");
        send_ar(S_AXI_ACLK, x"00004004", S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000000", 0, "reserved CONTROL readback");

        -- 1, 4, and 7: AW/W together, full strobe, and delayed BREADY.
        write_same_cycle(S_AXI_ACLK, CH0_BIAS_ADDR, x"11223344", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                3, "same-cycle full-word bias write");

        -- 2 and 8: AW arrives several cycles before a byte-0 W transaction.
        send_aw(S_AXI_ACLK, CH0_BIAS_ADDR, S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY);
        for i in 1 to 3 loop
            wait until rising_edge(S_AXI_ACLK);
        end loop;
        wait until falling_edge(S_AXI_ACLK);
        assert S_AXI_AWREADY = '0' report "AW channel accepted a second address while one was pending" severity error;
        assert S_AXI_WREADY = '1' report "W channel was not available while awaiting data" severity error;
        send_w(S_AXI_ACLK, x"000000AA", "0001", S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                1, "AW-before-W byte-0 write");

        -- 3 and 8: W arrives several cycles before a byte-1 AW transaction.
        send_w(S_AXI_ACLK, x"0000BB00", "0010", S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        for i in 1 to 3 loop
            wait until rising_edge(S_AXI_ACLK);
        end loop;
        wait until falling_edge(S_AXI_ACLK);
        assert S_AXI_WREADY = '0' report "W channel accepted a second data beat while one was pending" severity error;
        assert S_AXI_AWREADY = '1' report "AW channel was not available while awaiting address" severity error;
        send_aw(S_AXI_ACLK, CH0_BIAS_ADDR, S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                1, "W-before-AW byte-1 write");

        -- 8 and 9: byte-2 and byte-3 writes preserve all other bytes.
        write_same_cycle(S_AXI_ACLK, CH0_BIAS_ADDR, x"00CC0000", "0100",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "byte-2 bias write");
        write_same_cycle(S_AXI_ACLK, CH0_BIAS_ADDR, x"DD000000", "1000",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "byte-3 bias write");
        assert bias_out(0) = x"DDCCBBAA" report "partial WSTRB writes did not preserve disabled bias bytes" severity error;

        -- 5 and 10: hold a read response while RREADY is delayed, then confirm readback.
        send_ar(S_AXI_ACLK, CH0_BIAS_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"DDCCBBAA", 3, "delayed-RREADY bias readback");

        -- Current map control register: channel 1 base 0x100 plus 0xFC.
        write_same_cycle(S_AXI_ACLK, CH1_CTRL_ADDR, x"00000115", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "channel-1 control write");
        assert shift_out(1) = "10101" report "control shift field was not updated at +0xFC" severity error;
        assert relu_en_out(1) = '1' report "control ReLU bit was not updated at +0xFC" severity error;
        send_ar(S_AXI_ACLK, CH1_CTRL_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"00000115", 1, "channel-1 control readback");

        -- 6: back-to-back legal write transactions using packed coefficient words.
        write_same_cycle(S_AXI_ACLK, CH0_COEFF0_ADDR, x"44332211", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "first back-to-back coefficient write");
        write_same_cycle(S_AXI_ACLK, CH0_COEFF1_ADDR, x"88776655", "1111",
                         S_AXI_AWADDR, S_AXI_AWVALID, S_AXI_AWREADY,
                         S_AXI_WDATA, S_AXI_WSTRB, S_AXI_WVALID, S_AXI_WREADY);
        complete_write_response(S_AXI_ACLK, S_AXI_BVALID, S_AXI_BRESP, S_AXI_BREADY,
                                0, "second back-to-back coefficient write");
        assert coeffs_out(0) = x"11" and coeffs_out(1) = x"22" and
               coeffs_out(2) = x"33" and coeffs_out(3) = x"44"
            report "first packed coefficient word was not stored correctly" severity error;
        assert coeffs_out(4) = x"55" and coeffs_out(5) = x"66" and
               coeffs_out(6) = x"77" and coeffs_out(7) = x"88"
            report "second packed coefficient word was not stored correctly" severity error;
        send_ar(S_AXI_ACLK, CH0_COEFF0_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"44332211", 0, "first packed coefficient readback");
        send_ar(S_AXI_ACLK, CH0_COEFF1_ADDR, S_AXI_ARADDR, S_AXI_ARVALID, S_AXI_ARREADY);
        complete_read_response(S_AXI_ACLK, S_AXI_RVALID, S_AXI_RRESP, S_AXI_RDATA, S_AXI_RREADY,
                               x"88776655", 0, "second packed coefficient readback");

        report "--- AXI4-Lite protocol regression completed successfully ---";
        wait;
    end process;

end sim;