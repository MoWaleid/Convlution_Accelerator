-- ============================================================================
-- axi_stream_input_frontend.vhd -- 64-bit AXI4-Stream input and byte unpacker
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

entity axi_stream_input_frontend is
    generic (
        C_FIFO_DEPTH : positive := 16
    );
    port (
        clk    : in  std_logic;
        resetn : in  std_logic;

        s_axis_tdata  : in  std_logic_vector(63 downto 0);
        s_axis_tkeep  : in  std_logic_vector(7 downto 0);
        s_axis_tvalid : in  std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in  std_logic;

        out_pixel : out std_logic_vector(7 downto 0);
        out_valid : out std_logic;
        out_ready : in  std_logic;
        out_last  : out std_logic
    );
end entity axi_stream_input_frontend;

architecture rtl of axi_stream_input_frontend is
    constant C_FIFO_WORD_WIDTH : positive := 73;

    signal fifo_push_ready : std_logic;
    signal fifo_pop_valid  : std_logic;
    signal fifo_pop_ready  : std_logic;
    signal fifo_pop_data   : std_logic_vector(C_FIFO_WORD_WIDTH - 1 downto 0);
    signal fifo_level      : natural range 0 to C_FIFO_DEPTH;

    signal beat_active : std_logic := '0';
    signal beat_data   : std_logic_vector(63 downto 0) := (others => '0');
    signal beat_keep   : std_logic_vector(7 downto 0) := (others => '0');
    signal beat_tlast  : std_logic := '0';
    signal lane_index  : natural range 0 to 8 := 0;
    signal current_lane : integer range -1 to 7 := -1;
    signal out_valid_int : std_logic;
    signal final_pixel_fire : std_logic;

    function has_valid_lane(keep : std_logic_vector(7 downto 0)) return boolean is
    begin
        for lane in 0 to 7 loop
            if keep(lane) = '1' then
                return true;
            end if;
        end loop;
        return false;
    end function has_valid_lane;

    function first_valid_lane(
        keep       : std_logic_vector(7 downto 0);
        start_lane : natural
    ) return integer is
    begin
        for lane in 0 to 7 loop
            if lane >= start_lane and keep(lane) = '1' then
                return lane;
            end if;
        end loop;
        return -1;
    end function first_valid_lane;

    function is_final_valid_lane(
        keep : std_logic_vector(7 downto 0);
        lane : integer
    ) return boolean is
    begin
        for later_lane in 0 to 7 loop
            if later_lane > lane and keep(later_lane) = '1' then
                return false;
            end if;
        end loop;
        return true;
    end function is_final_valid_lane;
begin
    fifo_inst : entity work.sync_fifo
        generic map (
            C_DATA_WIDTH => C_FIFO_WORD_WIDTH,
            C_DEPTH      => C_FIFO_DEPTH
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            push_valid => s_axis_tvalid,
            push_ready => fifo_push_ready,
            push_data  => s_axis_tdata & s_axis_tkeep & s_axis_tlast,
            pop_valid  => fifo_pop_valid,
            pop_ready  => fifo_pop_ready,
            pop_data   => fifo_pop_data,
            level      => fifo_level
        );

    s_axis_tready <= fifo_push_ready;

    current_lane <= first_valid_lane(beat_keep, lane_index) when beat_active = '1' else -1;
    out_valid_int <= '1' when beat_active = '1' and current_lane >= 0 else '0';
    final_pixel_fire <= '1' when out_valid_int = '1' and out_ready = '1' and
                                   is_final_valid_lane(beat_keep, current_lane) else '0';

    -- Pop the next FIFO word on the same edge that accepts the current beat's
    -- final valid byte. This removes the inter-beat output bubble.
    fifo_pop_ready <= '1' when beat_active = '0' or final_pixel_fire = '1' else '0';
    out_valid <= out_valid_int;

    process(beat_data, current_lane, out_valid_int)
    begin
        out_pixel <= (others => '0');
        if out_valid_int = '1' then
            case current_lane is
                when 0 => out_pixel <= beat_data(7 downto 0);
                when 1 => out_pixel <= beat_data(15 downto 8);
                when 2 => out_pixel <= beat_data(23 downto 16);
                when 3 => out_pixel <= beat_data(31 downto 24);
                when 4 => out_pixel <= beat_data(39 downto 32);
                when 5 => out_pixel <= beat_data(47 downto 40);
                when 6 => out_pixel <= beat_data(55 downto 48);
                when 7 => out_pixel <= beat_data(63 downto 56);
                when others => null;
            end case;
        end if;
    end process;

    process(beat_keep, beat_tlast, current_lane, out_valid_int)
    begin
        out_last <= '0';
        if out_valid_int = '1' and beat_tlast = '1' and
           is_final_valid_lane(beat_keep, current_lane) then
            out_last <= '1';
        end if;
    end process;

    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                beat_active <= '0';
                beat_data   <= (others => '0');
                beat_keep   <= (others => '0');
                beat_tlast  <= '0';
                lane_index  <= 0;
            elsif beat_active = '0' or final_pixel_fire = '1' then
                if fifo_pop_valid = '1' then
                    beat_data  <= fifo_pop_data(72 downto 9);
                    beat_keep  <= fifo_pop_data(8 downto 1);
                    beat_tlast <= fifo_pop_data(0);
                    lane_index <= 0;
                    if has_valid_lane(fifo_pop_data(8 downto 1)) then
                        beat_active <= '1';
                    else
                        beat_active <= '0';
                    end if;
                elsif final_pixel_fire = '1' then
                    beat_active <= '0';
                    lane_index  <= 0;
                end if;
            elsif out_valid_int = '1' and out_ready = '1' then
                lane_index <= current_lane + 1;
            end if;
        end if;
    end process;
end architecture rtl;