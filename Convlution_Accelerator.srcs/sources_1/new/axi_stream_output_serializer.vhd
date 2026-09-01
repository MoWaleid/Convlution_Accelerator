-- ============================================================================
-- axi_stream_output_serializer.vhd -- Kxint16 result-vector AXI4-Stream output
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;

entity axi_stream_output_serializer is
    generic (
        C_K            : positive := CFG_K;
        C_IMAGE_WIDTH  : positive := CFG_IMAGE_WIDTH;
        C_IMAGE_HEIGHT : positive := CFG_IMAGE_WIDTH;
        C_FIFO_DEPTH   : positive := 16
    );
    port (
        clk    : in  std_logic;
        resetn : in  std_logic;

        in_results : in  output_array_t(0 to C_K - 1);
        in_valid   : in  std_logic;
        in_ready   : out std_logic;

        m_axis_tdata  : out std_logic_vector(63 downto 0);
        m_axis_tkeep  : out std_logic_vector(7 downto 0);
        m_axis_tvalid : out std_logic;
        m_axis_tready : in  std_logic;
        m_axis_tlast  : out std_logic
    );
end entity axi_stream_output_serializer;

architecture rtl of axi_stream_output_serializer is
    constant C_FIFO_WORD_WIDTH : positive := 73;
    constant C_NUM_POSITIONS   : positive := C_IMAGE_WIDTH * C_IMAGE_HEIGHT;

    signal fifo_push_ready : std_logic;
    signal fifo_push_valid : std_logic;
    signal fifo_push_data  : std_logic_vector(C_FIFO_WORD_WIDTH - 1 downto 0);
    signal fifo_pop_valid  : std_logic;
    signal fifo_pop_data   : std_logic_vector(C_FIFO_WORD_WIDTH - 1 downto 0);
    signal fifo_level      : natural range 0 to C_FIFO_DEPTH;

    signal vector_active : std_logic := '0';
    signal vector_data   : output_array_t(0 to C_K - 1);
    signal channel_index : natural range 0 to C_K - 1 := 0;
    signal position_index : natural range 0 to C_NUM_POSITIONS - 1 := 0;

    signal packed_data  : std_logic_vector(63 downto 0) := (others => '0');
    signal packed_count : natural range 0 to 3 := 0;

    signal vector_remaining : natural range 1 to C_K;
    signal take_count       : natural range 1 to 4;
    signal next_packed_count : natural range 1 to 4;
    signal vector_finishes  : std_logic;
    signal frame_finishes   : std_logic;
    signal emit_word        : std_logic;
    signal formatter_fire   : std_logic;
    signal in_fire          : std_logic;
    signal assembled_word   : std_logic_vector(63 downto 0);

    function min_natural(a : natural; b : natural) return natural is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function min_natural;

    function tkeep_for_scalar_count(count : natural) return std_logic_vector is
    begin
        case count is
            when 1 => return x"03";
            when 2 => return x"0F";
            when 3 => return x"3F";
            when others => return x"FF";
        end case;
    end function tkeep_for_scalar_count;
begin
    fifo_inst : entity work.sync_fifo
        generic map (
            C_DATA_WIDTH => C_FIFO_WORD_WIDTH,
            C_DEPTH      => C_FIFO_DEPTH
        )
        port map (
            clk        => clk,
            resetn     => resetn,
            push_valid => fifo_push_valid,
            push_ready => fifo_push_ready,
            push_data  => fifo_push_data,
            pop_valid  => fifo_pop_valid,
            pop_ready  => m_axis_tready,
            pop_data   => fifo_pop_data,
            level      => fifo_level
        );

    m_axis_tdata  <= fifo_pop_data(72 downto 9);
    m_axis_tkeep  <= fifo_pop_data(8 downto 1);
    m_axis_tlast  <= fifo_pop_data(0);
    m_axis_tvalid <= fifo_pop_valid;

    vector_remaining <= C_K - channel_index;
    take_count <= min_natural(4 - packed_count, vector_remaining);
    next_packed_count <= packed_count + take_count;
    vector_finishes <= '1' when take_count = vector_remaining else '0';
    frame_finishes <= '1' when vector_finishes = '1' and
                               position_index = C_NUM_POSITIONS - 1 else '0';
    emit_word <= '1' when vector_active = '1' and
                          (next_packed_count = 4 or frame_finishes = '1') else '0';

    -- A completed formatter word remains asserted until the output FIFO
    -- accepts it. Partial words never require FIFO space until they complete.
    fifo_push_valid <= emit_word;
    formatter_fire <= '1' when vector_active = '1' and
                               (emit_word = '0' or fifo_push_ready = '1') else '0';

    -- Input may replace a vector on the same edge that consumes its final
    -- scalar group, avoiding a permanent reload bubble for K divisible by 4.
    in_ready <= '1' when vector_active = '0' or
                         (vector_finishes = '1' and formatter_fire = '1') else '0';
    in_fire <= in_valid and in_ready;

    process(packed_data, vector_data, packed_count, channel_index)
        variable next_word : std_logic_vector(63 downto 0);
        variable local_take_count : natural range 1 to 4;
    begin
        local_take_count := min_natural(4 - packed_count, C_K - channel_index);
        next_word := packed_data;
        for scalar_offset in 0 to local_take_count - 1 loop
            next_word((packed_count + scalar_offset + 1) * 16 - 1 downto
                      (packed_count + scalar_offset) * 16) :=
                vector_data(channel_index + scalar_offset);
        end loop;
        assembled_word <= next_word;
    end process;

    fifo_push_data <= assembled_word &
                      tkeep_for_scalar_count(next_packed_count) &
                      frame_finishes;

    process(clk)
    begin
        if rising_edge(clk) then
            if resetn = '0' then
                vector_active <= '0';
                channel_index <= 0;
                position_index <= 0;
                packed_data <= (others => '0');
                packed_count <= 0;
            elsif formatter_fire = '1' then
                if emit_word = '1' then
                    packed_data  <= (others => '0');
                    packed_count <= 0;
                else
                    packed_data  <= assembled_word;
                    packed_count <= next_packed_count;
                end if;

                if vector_finishes = '1' then
                    if position_index = C_NUM_POSITIONS - 1 then
                        position_index <= 0;
                    else
                        position_index <= position_index + 1;
                    end if;

                    if in_fire = '1' then
                        vector_data   <= in_results;
                        vector_active <= '1';
                        channel_index <= 0;
                    else
                        vector_active <= '0';
                        channel_index <= 0;
                    end if;
                else
                    channel_index <= channel_index + take_count;
                end if;
            elsif vector_active = '0' and in_fire = '1' then
                vector_data   <= in_results;
                vector_active <= '1';
                channel_index <= 0;
            end if;
        end if;
    end process;
end architecture rtl;