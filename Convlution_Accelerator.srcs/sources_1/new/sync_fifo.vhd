-- ============================================================================
-- sync_fifo.vhd -- Reusable synchronous valid/ready FIFO
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity sync_fifo is
    generic (
        C_DATA_WIDTH : positive := 73;
        C_DEPTH      : positive := 16
    );
    port (
        clk    : in  std_logic;
        resetn : in  std_logic;

        push_valid : in  std_logic;
        push_ready : out std_logic;
        push_data  : in  std_logic_vector(C_DATA_WIDTH - 1 downto 0);

        pop_valid : out std_logic;
        pop_ready : in  std_logic;
        pop_data  : out std_logic_vector(C_DATA_WIDTH - 1 downto 0);

        level : out natural range 0 to C_DEPTH
    );
end entity sync_fifo;

architecture rtl of sync_fifo is
    type memory_t is array (0 to C_DEPTH - 1) of std_logic_vector(C_DATA_WIDTH - 1 downto 0);

    signal memory  : memory_t;
    signal rd_ptr  : natural range 0 to C_DEPTH - 1 := 0;
    signal wr_ptr  : natural range 0 to C_DEPTH - 1 := 0;
    signal used    : natural range 0 to C_DEPTH := 0;
    signal push_fire : std_logic;
    signal pop_fire  : std_logic;

    function next_ptr(ptr : natural) return natural is
    begin
        if ptr = C_DEPTH - 1 then
            return 0;
        else
            return ptr + 1;
        end if;
    end function next_ptr;
begin
    assert C_DEPTH >= 2
        report "sync_fifo requires C_DEPTH >= 2" severity failure;

    -- A full FIFO can accept a push in the same cycle as a pop. An empty FIFO
    -- has no fall-through path, so a simultaneous push is stored for a later pop.
    pop_valid <= '1' when used /= 0 else '0';
    push_ready <= '1' when used < C_DEPTH or (pop_ready = '1' and used /= 0) else '0';
    pop_data <= memory(rd_ptr) when used /= 0 else (others => '0');
    level <= used;

    push_fire <= push_valid and push_ready;
    pop_fire  <= pop_valid and pop_ready;

    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                rd_ptr <= 0;
                wr_ptr <= 0;
                used   <= 0;
            else
                if push_fire = '1' then
                    memory(wr_ptr) <= push_data;
                    wr_ptr <= next_ptr(wr_ptr);
                end if;

                if pop_fire = '1' then
                    rd_ptr <= next_ptr(rd_ptr);
                end if;

                if push_fire = '1' and pop_fire = '0' then
                    used <= used + 1;
                elsif push_fire = '0' and pop_fire = '1' then
                    used <= used - 1;
                end if;
            end if;
        end if;
    end process;
end architecture rtl;