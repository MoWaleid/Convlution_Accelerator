-- ============================================================================
-- axi_stream_output_serializer.vhd
-- CVH1 Kxint16 result-vector -> 64-bit AXI4-Stream serializer
-- ============================================================================
--
-- Key lifecycle rule:
--
--   production_enable = 1
--       New core result vectors may be accepted and formatted.
--
--   production_enable = 0
--       No new vector may be accepted.
--       Formatter state freezes.
--       No new FIFO word may be enqueued.
--       Already queued FIFO words remain externally drainable.
--
-- This is what allows ABORT/FAULT to stop new production without retracting
-- an already offered AXI4-Stream output beat.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;
use work.conv_pkg.all;


entity axi_stream_output_serializer is
    generic (
        C_K : positive := CFG_K;

        C_IMAGE_WIDTH :
            positive := CFG_UNPADDED_WIDTH;

        C_IMAGE_HEIGHT :
            positive := CFG_UNPADDED_HEIGHT;

        C_FIFO_DEPTH :
            positive := 16
    );
    port (
        clk    : in std_logic;
        resetn : in std_logic;

        -- ====================================================================
        -- CVH1 lifecycle
        -- ====================================================================

        -- High only while new output production is permitted.
        -- ABORT/FAULT removes this signal, freezing the formatter while
        -- leaving already queued FIFO words available for drain.
        production_enable : in std_logic;

        -- ====================================================================
        -- K-channel result-vector input
        -- ====================================================================

        in_results :
            in output_array_t(0 to C_K - 1);

        in_valid :
            in std_logic;

        in_ready :
            out std_logic;

        -- Pulses whenever one complete K-channel result vector is accepted.
        -- This is the architectural CORE_ACCEPT_PIXELS event.
        core_accept_pulse :
            out std_logic;

        -- ====================================================================
        -- FIFO observability
        -- ====================================================================

        -- Indicates that no complete AXIS word remains queued for external
        -- output. Formatter state is intentionally not part of this signal.
        fifo_empty :
            out std_logic;

        -- ====================================================================
        -- 64-bit AXI4-Stream output
        -- ====================================================================

        m_axis_tdata :
            out std_logic_vector(63 downto 0);

        m_axis_tkeep :
            out std_logic_vector(7 downto 0);

        m_axis_tvalid :
            out std_logic;

        m_axis_tready :
            in std_logic;

        m_axis_tlast :
            out std_logic
    );
end entity axi_stream_output_serializer;


architecture rtl of axi_stream_output_serializer is

    constant C_FIFO_WORD_WIDTH :
        positive := 73;

    constant C_NUM_POSITIONS :
        positive :=
            C_IMAGE_WIDTH * C_IMAGE_HEIGHT;

    -- ========================================================================
    -- Output FIFO
    -- ========================================================================

    signal fifo_push_ready :
        std_logic;

    signal fifo_push_valid :
        std_logic;

    signal fifo_push_data :
        std_logic_vector(
            C_FIFO_WORD_WIDTH - 1 downto 0
        );

    signal fifo_pop_valid :
        std_logic;

    signal fifo_pop_data :
        std_logic_vector(
            C_FIFO_WORD_WIDTH - 1 downto 0
        );

    signal fifo_level :
        natural range 0 to C_FIFO_DEPTH;

    -- ========================================================================
    -- Formatter state
    -- ========================================================================

    signal vector_active :
        std_logic := '0';

    signal vector_data :
        output_array_t(0 to C_K - 1);

    signal channel_index :
        natural range 0 to C_K - 1 := 0;

    signal position_index :
        natural range 0 to C_NUM_POSITIONS - 1 := 0;

    signal packed_data :
        std_logic_vector(63 downto 0) :=
            (others => '0');

    signal packed_count :
        natural range 0 to 3 := 0;

    signal vector_remaining :
        natural range 1 to C_K;

    signal take_count :
        natural range 1 to 4;

    signal next_packed_count :
        natural range 1 to 4;

    signal vector_finishes :
        std_logic;

    signal frame_finishes :
        std_logic;

    signal emit_word :
        std_logic;

    signal formatter_fire :
        std_logic;

    signal in_fire :
        std_logic;

    signal assembled_word :
        std_logic_vector(63 downto 0);

    -- ========================================================================
    -- Helpers
    -- ========================================================================

    function min_natural(
        a : natural;
        b : natural
    ) return natural is
    begin
        if a < b then
            return a;
        else
            return b;
        end if;
    end function min_natural;


    function tkeep_for_scalar_count(
        count : natural
    ) return std_logic_vector is
    begin
        case count is

            when 1 =>
                return x"03";

            when 2 =>
                return x"0F";

            when 3 =>
                return x"3F";

            when others =>
                return x"FF";

        end case;
    end function tkeep_for_scalar_count;

begin

    -- ========================================================================
    -- Output FIFO
    --
    -- IMPORTANT:
    -- fifo pop is NOT gated by production_enable.
    --
    -- Therefore after ABORT/FAULT, already queued output remains drainable
    -- through normal AXI TVALID/TREADY handshakes.
    -- ========================================================================

    fifo_inst :
        entity work.sync_fifo
        generic map (
            C_DATA_WIDTH =>
                C_FIFO_WORD_WIDTH,

            C_DEPTH =>
                C_FIFO_DEPTH
        )
        port map (
            clk =>
                clk,

            resetn =>
                resetn,

            push_valid =>
                fifo_push_valid,

            push_ready =>
                fifo_push_ready,

            push_data =>
                fifo_push_data,

            pop_valid =>
                fifo_pop_valid,

            pop_ready =>
                m_axis_tready,

            pop_data =>
                fifo_pop_data,

            level =>
                fifo_level
        );


    -- ========================================================================
    -- External AXI output
    -- ========================================================================

    m_axis_tdata <=
        fifo_pop_data(72 downto 9);

    m_axis_tkeep <=
        fifo_pop_data(8 downto 1);

    m_axis_tlast <=
        fifo_pop_data(0);

    m_axis_tvalid <=
        fifo_pop_valid;


    fifo_empty <=
        '1'
        when fifo_level = 0
        else '0';


    -- ========================================================================
    -- Formatter geometry
    -- ========================================================================

    vector_remaining <=
        C_K - channel_index;


    take_count <=
        min_natural(
            4 - packed_count,
            vector_remaining
        );


    next_packed_count <=
        packed_count + take_count;


    vector_finishes <=
        '1'
        when take_count = vector_remaining
        else '0';


    frame_finishes <=
        '1'
        when
            vector_finishes = '1'
            and position_index =
                C_NUM_POSITIONS - 1
        else '0';


    emit_word <=
        '1'
        when
            vector_active = '1'
            and
            (
                next_packed_count = 4
                or frame_finishes = '1'
            )
        else '0';


    -- ========================================================================
    -- FIFO enqueue
    --
    -- Once production_enable goes low, no new formatter word may enter the
    -- FIFO. A word that was accepted on the same clock edge as an ABORT commit
    -- is naturally retained because production_enable was still high before
    -- that edge; from the following cycle production is frozen.
    -- ========================================================================

    fifo_push_valid <=
        '1'
        when
            production_enable = '1'
            and emit_word = '1'
        else '0';


    -- A non-emitting formatter operation can always advance.
    --
    -- An emitting operation advances only when the FIFO accepts the completed
    -- word. When production_enable is low the formatter does not move at all.
    formatter_fire <=
        '1'
        when
            production_enable = '1'
            and vector_active = '1'
            and
            (
                emit_word = '0'
                or fifo_push_ready = '1'
            )
        else '0';


    -- ========================================================================
    -- Result-vector admission
    --
    -- The serializer may accept a replacement vector on the same edge that
    -- finishes the previous one, preserving the existing no-reload-bubble path.
    -- ========================================================================

    in_ready <=
        '1'
        when
            production_enable = '1'
            and
            (
                vector_active = '0'
                or
                (
                    vector_finishes = '1'
                    and formatter_fire = '1'
                )
            )
        else '0';


    in_fire <=
        in_valid and in_ready;


    core_accept_pulse <=
        in_fire;


    -- ========================================================================
    -- Assemble up to four signed16 scalar results into one 64-bit AXIS word.
    --
    -- Scalar order remains:
    --
    --   channel fastest
    --   then x
    --   then y
    --
    -- Low scalar occupies bits 15:0.
    -- ========================================================================

    assemble_process : process(all)

        variable next_word :
            std_logic_vector(63 downto 0);

        variable local_take_count :
            natural range 1 to 4;

    begin

        local_take_count :=
            min_natural(
                4 - packed_count,
                C_K - channel_index
            );

        next_word :=
            packed_data;


        for scalar_offset in 0 to 3 loop

            if scalar_offset < local_take_count then

                case packed_count + scalar_offset is

                    when 0 =>
                        next_word(15 downto 0) :=
                            vector_data(
                                channel_index
                                + scalar_offset
                            );

                    when 1 =>
                        next_word(31 downto 16) :=
                            vector_data(
                                channel_index
                                + scalar_offset
                            );

                    when 2 =>
                        next_word(47 downto 32) :=
                            vector_data(
                                channel_index
                                + scalar_offset
                            );

                    when 3 =>
                        next_word(63 downto 48) :=
                            vector_data(
                                channel_index
                                + scalar_offset
                            );

                    when others =>
                        null;

                end case;

            end if;

        end loop;


        assembled_word <=
            next_word;

    end process assemble_process;


    -- ========================================================================
    -- FIFO word metadata
    -- ========================================================================

    fifo_push_data <=
        assembled_word
        & tkeep_for_scalar_count(
            next_packed_count
        )
        & frame_finishes;


    -- ========================================================================
    -- Formatter state machine
    -- ========================================================================

    formatter_process : process(clk)
    begin

        if rising_edge(clk) then

            if resetn = '0' then

                vector_active <=
                    '0';

                channel_index <=
                    0;

                position_index <=
                    0;

                packed_data <=
                    (others => '0');

                packed_count <=
                    0;


            elsif production_enable = '1' then

                -- ============================================================
                -- Existing active vector advances
                -- ============================================================

                if formatter_fire = '1' then

                    if emit_word = '1' then

                        packed_data <=
                            (others => '0');

                        packed_count <=
                            0;

                    else

                        packed_data <=
                            assembled_word;

                        packed_count <=
                            next_packed_count;

                    end if;


                    if vector_finishes = '1' then

                        -- One complete K-channel output pixel has now been
                        -- consumed by the serializer.
                        if
                            position_index =
                            C_NUM_POSITIONS - 1
                        then

                            position_index <=
                                0;

                        else

                            position_index <=
                                position_index + 1;

                        end if;


                        -- Bubble-free replacement vector.
                        if in_fire = '1' then

                            vector_data <=
                                in_results;

                            vector_active <=
                                '1';

                            channel_index <=
                                0;

                        else

                            vector_active <=
                                '0';

                            channel_index <=
                                0;

                        end if;


                    else

                        channel_index <=
                            channel_index + take_count;

                    end if;


                -- ============================================================
                -- Formatter idle: load first vector
                -- ============================================================

                elsif
                    vector_active = '0'
                    and in_fire = '1'
                then

                    vector_data <=
                        in_results;

                    vector_active <=
                        '1';

                    channel_index <=
                        0;

                end if;


            end if;
            -- production_enable = 0:
            --
            -- Intentionally no formatter state modification.
            -- Partial packed word / active vector is frozen until local RESET.

        end if;

    end process formatter_process;

end architecture rtl;