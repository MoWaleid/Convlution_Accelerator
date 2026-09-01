-- ============================================================================
-- tb_window_generator_nonsquare.vhd
-- Verifies independent padded image width and height across consecutive frames.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.conv_pkg.all;

entity tb_window_generator_nonsquare is
end entity tb_window_generator_nonsquare;

architecture sim of tb_window_generator_nonsquare is
    constant CLK_PERIOD          : time := 10 ns;
    constant C_N                 : integer := 3;
    constant C_IMAGE_WIDTH       : integer := 5;
    constant C_IMAGE_HEIGHT      : integer := 3;
    constant C_FRAME_PIXELS      : integer := C_IMAGE_WIDTH * C_IMAGE_HEIGHT;
    constant C_FRAME_COUNT       : integer := 2;
    constant C_WINDOWS_PER_FRAME : integer :=
        (C_IMAGE_WIDTH - C_N + 1) * (C_IMAGE_HEIGHT - C_N + 1);
    constant C_EXPECTED_WINDOWS  : integer := C_FRAME_COUNT * C_WINDOWS_PER_FRAME;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal pixel_in : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_in : std_logic := '0';
    signal window_out : pixel_array_t(0 to C_N * C_N - 1);
    signal valid_out : std_logic;
    signal input_complete : std_logic := '0';
    signal monitor_done   : std_logic := '0';
begin
    clk <= not clk after CLK_PERIOD / 2;

    dut : entity work.window_generator
        generic map (
            C_N            => C_N,
            C_IMAGE_WIDTH  => C_IMAGE_WIDTH,
            C_IMAGE_HEIGHT => C_IMAGE_HEIGHT
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            ce         => '1',
            pixel_in   => pixel_in,
            valid_in   => valid_in,
            window_out => window_out,
            valid_out  => valid_out
        );

    stimulus : process
        variable pixel_value : integer;
    begin
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        resetn <= '1';

        for frame in 0 to C_FRAME_COUNT - 1 loop
            for row in 0 to C_IMAGE_HEIGHT - 1 loop
                for column in 0 to C_IMAGE_WIDTH - 1 loop
                    wait until falling_edge(clk);
                    pixel_value := frame * C_FRAME_PIXELS + row * C_IMAGE_WIDTH + column + 1;
                    pixel_in <= std_logic_vector(to_unsigned(pixel_value, pixel_in'length));
                    valid_in <= '1';
                end loop;
            end loop;
        end loop;

        wait until falling_edge(clk);
        pixel_in <= (others => '0');
        valid_in <= '0';
        input_complete <= '1';

        wait until monitor_done = '1';
        report "--- Non-square window-generator regression completed successfully ---";
        stop(0);
        wait;
    end process stimulus;

    monitor : process
        variable window_count : integer := 0;
    begin
        wait until resetn = '1';
        loop
            wait until falling_edge(clk);
            if valid_out = '1' then
                window_count := window_count + 1;
                assert window_count <= C_EXPECTED_WINDOWS
                    report "5x3 window generator emitted too many valid windows" severity failure;

                case window_count is
                    when 1 =>
                        assert window_out(0) = std_logic_vector(to_unsigned(1, 8)) and
                               window_out(C_N * C_N - 1) = std_logic_vector(to_unsigned(13, 8))
                            report "First 5x3 frame window mismatch" severity failure;
                    when C_WINDOWS_PER_FRAME =>
                        assert window_out(0) = std_logic_vector(to_unsigned(3, 8)) and
                               window_out(C_N * C_N - 1) = std_logic_vector(to_unsigned(15, 8))
                            report "Last 5x3 frame window mismatch" severity failure;
                    when C_WINDOWS_PER_FRAME + 1 =>
                        assert window_out(0) = std_logic_vector(to_unsigned(16, 8)) and
                               window_out(C_N * C_N - 1) = std_logic_vector(to_unsigned(28, 8))
                            report "Second 5x3 frame did not restart at row zero" severity failure;
                    when C_EXPECTED_WINDOWS =>
                        assert window_out(0) = std_logic_vector(to_unsigned(18, 8)) and
                               window_out(C_N * C_N - 1) = std_logic_vector(to_unsigned(30, 8))
                            report "Last second-frame 5x3 window mismatch" severity failure;
                    when others =>
                        null;
                end case;
            end if;

            if input_complete = '1' and valid_out = '0' then
                assert window_count = C_EXPECTED_WINDOWS
                    report "5x3 window generator produced the wrong number of valid windows" severity failure;
                monitor_done <= '1';
                exit;
            end if;
        end loop;
        wait;
    end process monitor;
end architecture sim;