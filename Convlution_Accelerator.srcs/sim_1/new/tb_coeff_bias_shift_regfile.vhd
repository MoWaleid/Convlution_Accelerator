library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_coeff_bias_shift_regfile is
-- Testbench has no ports
end tb_coeff_bias_shift_regfile;

architecture sim of tb_coeff_bias_shift_regfile is

    -- Component Declaration
    component coeff_bias_shift_regfile is
        generic (
            C_K : integer range 1 to 64 := CFG_K;
            C_N : integer range 1 to 15 := CFG_N
        );
        port (
            clk         : in std_logic;
            resetn      : in std_logic;
            wr_en       : in std_logic;
            wr_addr     : in std_logic_vector(31 downto 0);
            wr_data     : in std_logic_vector(31 downto 0);
            rd_en       : in std_logic;
            rd_addr     : in std_logic_vector(31 downto 0);
            rd_data     : out std_logic_vector(31 downto 0);
            coeffs_out  : out coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
            bias_out    : out bias_array_t(0 to CFG_K - 1);
            shift_out   : out shift_array_t(0 to CFG_K - 1);
            relu_en_out : out std_logic_vector(0 to CFG_K - 1)
        );
    end component;

    -- Signals
    signal clk         : std_logic := '0';
    signal resetn      : std_logic := '0';
    signal wr_en       : std_logic := '0';
    signal wr_addr     : std_logic_vector(31 downto 0) := (others => '0');
    signal wr_data     : std_logic_vector(31 downto 0) := (others => '0');
    signal rd_en       : std_logic := '0';
    signal rd_addr     : std_logic_vector(31 downto 0) := (others => '0');
    signal rd_data     : std_logic_vector(31 downto 0);
    
    signal coeffs_out  : coeff_array_t(0 to CFG_K * CFG_N * CFG_N - 1);
    signal bias_out    : bias_array_t(0 to CFG_K - 1);
    signal shift_out   : shift_array_t(0 to CFG_K - 1);
    signal relu_en_out : std_logic_vector(0 to CFG_K - 1);

    constant CLK_PERIOD : time := 10 ns;

    -- Procedure for writing to a register
    procedure write_reg(
        signal clk : in std_logic;
        address    : in integer;
        data       : in std_logic_vector(31 downto 0);
        signal w_en : out std_logic;
        signal w_addr : out std_logic_vector(31 downto 0);
        signal w_data : out std_logic_vector(31 downto 0)
    ) is
    begin
        wait until falling_edge(clk);
        w_addr <= std_logic_vector(to_unsigned(address, 32));
        w_data <= data;
        w_en <= '1';
        wait until rising_edge(clk);
        wait for 1 ns;
        w_en <= '0';
    end procedure;

    -- Procedure for reading a register
    procedure read_reg(
        signal clk : in std_logic;
        address    : in integer;
        signal r_en : out std_logic;
        signal r_addr : out std_logic_vector(31 downto 0);
        signal r_data : in std_logic_vector(31 downto 0);
        expected : in std_logic_vector(31 downto 0);
        message  : in string
    ) is
    begin
        wait until falling_edge(clk);
        r_addr <= std_logic_vector(to_unsigned(address, 32));
        r_en <= '1';
        wait for 1 ns;
        assert r_data = expected report message severity error;
        r_en <= '0';
        wait for 1 ns;
    end procedure;

begin

    -- Instantiate the Unit Under Test (UUT)
    uut: coeff_bias_shift_regfile
        generic map (
            C_K => CFG_K,
            C_N => CFG_N
        )
        port map (
            clk         => clk,
            resetn      => resetn,
            wr_en       => wr_en,
            wr_addr     => wr_addr,
            wr_data     => wr_data,
            rd_en       => rd_en,
            rd_addr     => rd_addr,
            rd_data     => rd_data,
            coeffs_out  => coeffs_out,
            bias_out    => bias_out,
            shift_out   => shift_out,
            relu_en_out => relu_en_out
        );

    -- Clock process definitions
    clk_process :process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus process
    stim_proc: process
    begin
        -- Hold reset state
        resetn <= '0';
        wait for 20 ns;
        resetn <= '1';
        wait for 20 ns;

        report "--- Starting coeff_bias_shift_regfile Testbench ---";

        -- Test Case 1: A packed coefficient write populates four consecutive entries.
        -- Word 0: coefficient 0 = 0x7F, 1 = 0x02, 2 = 0xFF, 3 = 0x80.
        write_reg(clk, 16#00#, x"80FF027F", wr_en, wr_addr, wr_data);
        assert coeffs_out(0) = x"7F" report "Test 1 Failed: coefficient 0 mismatch" severity error;
        assert coeffs_out(1) = x"02" report "Test 1 Failed: coefficient 1 mismatch" severity error;
        assert coeffs_out(2) = x"FF" report "Test 1 Failed: coefficient 2 mismatch" severity error;
        assert coeffs_out(3) = x"80" report "Test 1 Failed: coefficient 3 mismatch" severity error;
        read_reg(clk, 16#00#, rd_en, rd_addr, rd_data, x"80FF027F", "Test 1 Failed: packed coefficient readback mismatch");

        -- Test Case 2: The final partial packed word stores coefficient 8 only.
        write_reg(clk, 16#08#, x"000000AB", wr_en, wr_addr, wr_data);
        assert coeffs_out(8) = x"AB" report "Test 2 Failed: coefficient 8 mismatch" severity error;
        read_reg(clk, 16#08#, rd_en, rd_addr, rd_data, x"000000AB", "Test 2 Failed: final packed coefficient readback mismatch");

        -- Test Case 3: Channel 2 bias is located at word 62 (byte offset 0xF8).
        write_reg(clk, 16#200# + 16#F8#, x"12345678", wr_en, wr_addr, wr_data);
        assert bias_out(2) = x"12345678" report "Test 3 Failed: parallel bias mismatch" severity error;
        read_reg(clk, 16#200# + 16#F8#, rd_en, rd_addr, rd_data, x"12345678", "Test 3 Failed: bias readback mismatch");

        -- Test Case 4: Channel 15 control is located at word 63 (byte offset 0xFC).
        -- Shift = 12 in bits 4:0; ReLU enable = 1 in bit 8.
        write_reg(clk, 16#F00# + 16#FC#, x"0000010C", wr_en, wr_addr, wr_data);
        assert shift_out(15) = "01100" report "Test 4 Failed: parallel shift mismatch" severity error;
        assert relu_en_out(15) = '1' report "Test 4 Failed: parallel ReLU mismatch" severity error;
        read_reg(clk, 16#F00# + 16#FC#, rd_en, rd_addr, rd_data, x"0000010C", "Test 4 Failed: shift/ReLU readback mismatch");

        report "--- All tests completed successfully ---";
        wait;
    end process;

end sim;
