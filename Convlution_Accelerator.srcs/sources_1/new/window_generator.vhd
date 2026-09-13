library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity window_generator is
    generic (
        C_N            : integer := CFG_N;
        C_IMAGE_WIDTH  : integer := CFG_IMAGE_WIDTH;
        C_IMAGE_HEIGHT : integer := CFG_IMAGE_HEIGHT
    );
    port (
        clk        : in std_logic;
        resetn     : in std_logic;
        ce         : in std_logic;
        
        -- Input Stream
        pixel_in   : in std_logic_vector(7 downto 0);
        valid_in   : in std_logic;
        
        -- Output Sliding Window
        window_out : out pixel_array_t(0 to C_N * C_N - 1);
        valid_out  : out std_logic
    );
end entity window_generator;

architecture rtl of window_generator is

    -- Line buffers: (C_N - 1) buffers, each of depth C_IMAGE_WIDTH
    -- Using a flat array of std_logic_vectors to allow Vivado to easily infer SRL32 primitives
    type line_buffer_t is array (0 to C_IMAGE_WIDTH - 1) of std_logic_vector(7 downto 0);
    type line_buffers_array_t is array (0 to C_N - 2) of line_buffer_t;
    signal line_buffers : line_buffers_array_t := (others => (others => (others => '0')));
    
    -- Window registers: C_N rows, each of depth C_N
    type window_row_t is array (0 to C_N - 1) of std_logic_vector(7 downto 0);
    type window_regs_t is array (0 to C_N - 1) of window_row_t;
    signal window_regs : window_regs_t := (others => (others => (others => '0')));

    -- Channel fanout is handled by the engine's local registered window
    -- banks. Do not replicate the complete line-buffer arrays here.

    -- Counters to track image boundaries for valid_out generation
    signal col_cnt : integer range 0 to C_IMAGE_WIDTH - 1 := 0;
    signal row_cnt : integer range 0 to C_IMAGE_HEIGHT - 1 := 0;

    signal valid_out_reg : std_logic := '0';

begin

    -- =========================================================================
    -- Shift Register Updates (Line Buffers & Window Registers)
    -- =========================================================================
    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                line_buffers <= (others => (others => (others => '0')));
                window_regs  <= (others => (others => (others => '0')));
                col_cnt      <= 0;
                row_cnt      <= 0;
                valid_out_reg <= '0';
            elsif ce = '1' then
                if valid_in = '1' then
                    
                    -- Update valid_out_reg (delay by 1 cycle to match window_regs update)
                    if col_cnt >= C_N - 1 and row_cnt >= C_N - 1 then
                        valid_out_reg <= '1';
                    else
                        valid_out_reg <= '0';
                    end if;

                    -- 1. Shift Line Buffers
                    for i in 0 to C_N - 2 loop
                        for j in 0 to C_IMAGE_WIDTH - 2 loop
                            line_buffers(i)(j+1) <= line_buffers(i)(j);
                        end loop;
                        -- The input to line buffer i is the output of line buffer i-1, or pixel_in
                        if i = 0 then
                            line_buffers(i)(0) <= pixel_in;
                        else
                            line_buffers(i)(0) <= line_buffers(i-1)(C_IMAGE_WIDTH - 1);
                        end if;
                    end loop;
                    
                    -- 2. Shift Window Registers
                    for r in 0 to C_N - 1 loop
                        for c in 0 to C_N - 2 loop
                            window_regs(r)(c+1) <= window_regs(r)(c);
                        end loop;
                        
                        -- The input to window register row r is the output of the corresponding line buffer
                        if r = C_N - 1 then
                            window_regs(r)(0) <= pixel_in; -- Newest row (bottom of window)
                        else
                            window_regs(r)(0) <= line_buffers(C_N - 2 - r)(C_IMAGE_WIDTH - 1);
                        end if;
                    end loop;
                    
                    -- 3. Update Image Coordinate Counters
                    if col_cnt = C_IMAGE_WIDTH - 1 then
                        col_cnt <= 0;
                        if row_cnt = C_IMAGE_HEIGHT - 1 then
                            row_cnt <= 0; -- End of frame
                        else
                            row_cnt <= row_cnt + 1;
                        end if;
                    else
                        col_cnt <= col_cnt + 1;
                    end if;
                    
                else
                    valid_out_reg <= '0';
                end if;
            end if;
        end if;
    end process;

    valid_out <= valid_out_reg;

    -- =========================================================================
    -- Flatten Output Window
    -- =========================================================================
    process(window_regs)
    begin
        for r in 0 to C_N - 1 loop
            for c in 0 to C_N - 1 loop
                -- window_regs(r)(0) is the newest pixel in row r (right side of window).
                -- Coeff(0,0) multiplies the top-left (oldest) pixel of the window.
                -- So window_out(0) should be window_regs(0)(C_N-1).
                window_out(r * C_N + c) <= window_regs(r)(C_N - 1 - c);
            end loop;
        end loop;
    end process;

end architecture rtl;
