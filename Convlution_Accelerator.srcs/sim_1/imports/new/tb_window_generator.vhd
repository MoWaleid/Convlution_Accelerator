library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_window_generator is
-- Testbench has no ports
end tb_window_generator;

architecture sim of tb_window_generator is

    -- Component Declaration
    component window_generator is
        generic (
            C_N           : integer := CFG_N;
            C_IMAGE_WIDTH : integer := CFG_IMAGE_WIDTH
        );
        port (
            clk        : in std_logic;
            resetn     : in std_logic;
            pixel_in   : in std_logic_vector(7 downto 0);
            valid_in   : in std_logic;
            window_out : out pixel_array_t(0 to CFG_N * CFG_N - 1);
            valid_out  : out std_logic
        );
    end component;

    -- Constants for testbench
    constant TEST_N           : integer := 3;
    constant TEST_IMAGE_WIDTH : integer := 5; -- Small image for quick testing

    -- Signals
    signal clk        : std_logic := '0';
    signal resetn     : std_logic := '0';
    
    signal pixel_in   : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_in   : std_logic := '0';
    
    signal window_out : pixel_array_t(0 to TEST_N * TEST_N - 1);
    signal valid_out  : std_logic;

    constant CLK_PERIOD : time := 10 ns;

begin

    -- Instantiate the UUT with a small 5x5 image
    uut: window_generator
        generic map (
            C_N           => TEST_N,
            C_IMAGE_WIDTH => TEST_IMAGE_WIDTH
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            pixel_in   => pixel_in,
            valid_in   => valid_in,
            window_out => window_out,
            valid_out  => valid_out
        );

    -- Clock generation
    clk_process :process
    begin
        clk <= '0';
        wait for CLK_PERIOD/2;
        clk <= '1';
        wait for CLK_PERIOD/2;
    end process;

    -- Stimulus
    stim_proc: process
        variable expected_top_left : std_logic_vector(7 downto 0);
        variable expected_bot_right : std_logic_vector(7 downto 0);
        variable px_val : integer := 1;
        variable valid_windows_seen : integer := 0;
    begin
        resetn <= '0';
        valid_in <= '0';
        wait for 20 ns;
        resetn <= '1';
        wait for 20 ns;
        
        report "--- Starting Window Generator Testbench (5x5 Image) ---";

        -- Stream a 5x5 image. Pixels are numbered 1 to 25.
        for row in 0 to TEST_IMAGE_WIDTH - 1 loop
            for col in 0 to TEST_IMAGE_WIDTH - 1 loop
                wait until rising_edge(clk);
                valid_in <= '1';
                pixel_in <= std_logic_vector(to_unsigned(px_val, 8));
                
                -- Check valid_out in the same cycle?
                -- No, valid_out evaluates combinatorially based on current col_cnt/row_cnt,
                -- but those are updated on the clock edge. So the valid_out for the CURRENT pixel 
                -- is available immediately (0 cycle latency from valid_in).
                -- We'll check the outputs on the falling edge to ensure stability.
                
                px_val := px_val + 1;
            end loop;
        end loop;
        
        -- Stop streaming
        wait until rising_edge(clk);
        valid_in <= '0';
        pixel_in <= (others => '0');
        
        wait for 100 ns;
        report "--- All Window Generator tests completed successfully ---";
        wait;
    end process;
    
    -- Monitor process to check the windows
    monitor_proc: process
        variable valid_windows : integer := 0;
    begin
        wait until rising_edge(clk);
        if valid_out = '1' then
            valid_windows := valid_windows + 1;
            -- When we see the very first valid window (row 2, col 2 of the 5x5 image),
            -- The bottom right pixel (newest) should be 13 (row 2, col 2 -> 2*5+2 + 1 = 13).
            -- The top left pixel (oldest) should be 1 (row 0, col 0).
            if valid_windows = 1 then
                assert window_out(0) = std_logic_vector(to_unsigned(1, 8)) 
                    report "First window Top-Left mismatch" severity error;
                assert window_out(8) = std_logic_vector(to_unsigned(13, 8)) 
                    report "First window Bottom-Right mismatch" severity error;
            end if;
            
            -- When we see the LAST valid window (row 4, col 4)
            -- Bottom right should be 25
            -- Top left should be 13 (row 2, col 2 -> 13)
            if valid_windows = 9 then -- (5-3+1) * (5-3+1) = 3 * 3 = 9 valid windows expected
                assert window_out(0) = std_logic_vector(to_unsigned(13, 8)) 
                    report "Last window Top-Left mismatch" severity error;
                assert window_out(8) = std_logic_vector(to_unsigned(25, 8)) 
                    report "Last window Bottom-Right mismatch" severity error;
            end if;
        end if;
    end process;

end sim;
