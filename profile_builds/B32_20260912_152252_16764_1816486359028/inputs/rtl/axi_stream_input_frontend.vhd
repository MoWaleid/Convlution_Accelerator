-- ============================================================================
-- axi_stream_input_frontend.vhd
-- CVH1 64-bit AXI4-Stream input gate + byte unpacker
-- ============================================================================
--
-- Responsibilities:
--
--   * Accept input only while a CVH1 frame is RUNNING.
--   * Enforce the exact compiled input-byte quota.
--   * Enforce exact TKEEP/TLAST framing at the external AXIS boundary.
--   * Count the physical bytes of every accepted beat, including malformed
--     beats.
--   * Never release malformed beats into the pixel FIFO/core.
--   * Convert accepted valid 64-bit beats into one uint8 pixel per handshake.
--   * Freeze retained input state during FAULT/ABORT until local RESET.
--
-- A malformed beat is deliberately handshaken when FIFO capacity permits.
-- It raises frame_error, contributes to accept_bytes, and is NOT enqueued.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;


entity axi_stream_input_frontend is
    generic (
        C_FIFO_DEPTH : positive := 16;

        -- Exact number of externally supplied padded uint8 pixels.
        C_EXPECTED_INPUT_BYTES : positive :=
            CFG_IMAGE_WIDTH * CFG_IMAGE_HEIGHT
    );
    port (
        clk    : in std_logic;
        resetn : in std_logic;

        -- ====================================================================
        -- CVH1 lifecycle
        -- ====================================================================

        -- One-cycle pulse for an admitted START.
        -- Resets this frontend's per-frame acceptance quota.
        start_pulse : in std_logic;

        -- High only while the CVH1 controller is in RUN.
        run_enable : in std_logic;

        -- ====================================================================
        -- External 64-bit AXI4-Stream input
        -- ====================================================================

        s_axis_tdata  : in std_logic_vector(63 downto 0);
        s_axis_tkeep  : in std_logic_vector(7 downto 0);
        s_axis_tvalid : in std_logic;
        s_axis_tready : out std_logic;
        s_axis_tlast  : in std_logic;

        -- ====================================================================
        -- CVH1 acceptance/event reporting
        -- ====================================================================

        -- Pulses for every accepted external AXIS beat, including malformed
        -- beats.
        accept_valid : out std_logic;

        -- popcount(TKEEP) for the accepted beat, range 0..8.
        accept_bytes : out std_logic_vector(3 downto 0);

        -- Pulses when an accepted beat violates the required TKEEP/TLAST
        -- framing for its position in the frame.
        frame_error : out std_logic;

        -- Pulses once for every pixel handed to the convolution datapath.
        consumed_pulse : out std_logic;

        -- ====================================================================
        -- Pixel output toward convolution datapath
        -- ====================================================================

        out_pixel : out std_logic_vector(7 downto 0);
        out_valid : out std_logic;
        out_ready : in std_logic;

        -- Retained boundary indication for debug/integration.
        out_last : out std_logic
    );
end entity axi_stream_input_frontend;


architecture rtl of axi_stream_input_frontend is

    constant C_FIFO_WORD_WIDTH : positive := 73;

    -- A malformed final beat can physically report up to seven bytes beyond
    -- the remaining quota before the controller enters FAULT.
    constant C_ACCEPT_COUNT_MAX : natural :=
        C_EXPECTED_INPUT_BYTES + 7;

    -- ========================================================================
    -- Helpers
    -- ========================================================================

    function popcount8(
        value : std_logic_vector(7 downto 0)
    ) return natural is
        variable count : natural range 0 to 8 := 0;
    begin
        for lane in 0 to 7 loop
            if value(lane) = '1' then
                count := count + 1;
            end if;
        end loop;

        return count;
    end function popcount8;


    function low_lane_mask(
        count : natural
    ) return std_logic_vector is
        variable result :
            std_logic_vector(7 downto 0) :=
                (others => '0');
    begin
        for lane in 0 to 7 loop
            if lane < count then
                result(lane) := '1';
            end if;
        end loop;

        return result;
    end function low_lane_mask;


    function first_valid_lane(
        keep       : std_logic_vector(7 downto 0);
        start_lane : natural
    ) return integer is
    begin
        for lane in 0 to 7 loop
            if
                lane >= start_lane
                and keep(lane) = '1'
            then
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
            if
                later_lane > lane
                and keep(later_lane) = '1'
            then
                return false;
            end if;
        end loop;

        return true;
    end function is_final_valid_lane;


    -- ========================================================================
    -- Input FIFO
    -- ========================================================================

    signal fifo_push_valid :
        std_logic;

    signal fifo_push_ready :
        std_logic;

    signal fifo_push_data :
        std_logic_vector(C_FIFO_WORD_WIDTH - 1 downto 0);

    signal fifo_pop_valid :
        std_logic;

    signal fifo_pop_ready :
        std_logic;

    signal fifo_pop_data :
        std_logic_vector(C_FIFO_WORD_WIDTH - 1 downto 0);

    signal fifo_level :
        natural range 0 to C_FIFO_DEPTH;

    -- ========================================================================
    -- External acceptance/framing
    -- ========================================================================

    signal accepted_byte_count :
        natural range 0 to C_ACCEPT_COUNT_MAX := 0;

    signal effective_byte_count :
        natural range 0 to C_ACCEPT_COUNT_MAX;

    signal bytes_remaining :
        natural range 0 to C_EXPECTED_INPUT_BYTES;

    signal expected_keep :
        std_logic_vector(7 downto 0);

    signal expected_last :
        std_logic;

    signal offered_metadata_valid :
        std_logic;

    signal external_accept :
        std_logic;

    signal quota_open :
        std_logic;

    -- ========================================================================
    -- FIFO beat -> byte unpacker
    -- ========================================================================

    signal beat_active :
        std_logic := '0';

    signal beat_data :
        std_logic_vector(63 downto 0) :=
            (others => '0');

    signal beat_keep :
        std_logic_vector(7 downto 0) :=
            (others => '0');

    signal beat_tlast :
        std_logic := '0';

    signal lane_index :
        natural range 0 to 8 := 0;

    signal current_lane :
        integer range -1 to 7 := -1;

    signal out_valid_int :
        std_logic;

    signal pixel_fire :
        std_logic;

    signal final_pixel_fire :
        std_logic;

begin

    -- ========================================================================
    -- Elaboration checks
    -- ========================================================================

    assert C_EXPECTED_INPUT_BYTES > 0
        report "CVH1 input frame must contain at least one byte"
        severity failure;


    -- ========================================================================
    -- Per-frame quota basis
    --
    -- start_pulse is asserted during the first RUN cycle. Treat its count as
    -- zero combinationally so repeated frames can accept their first beat
    -- immediately instead of waiting an extra cycle for the counter register.
    -- ========================================================================

    effective_byte_count <=
        0
        when start_pulse = '1'
        else accepted_byte_count;


    quota_open <=
        '1'
        when effective_byte_count < C_EXPECTED_INPUT_BYTES
        else '0';


    bytes_remaining <=
        C_EXPECTED_INPUT_BYTES - effective_byte_count
        when effective_byte_count < C_EXPECTED_INPUT_BYTES
        else 0;


    -- ========================================================================
    -- Expected framing for the next accepted beat
    -- ========================================================================

    framing_expectation_process : process(all)
        variable remaining :
            natural;

        variable final_bytes :
            natural range 1 to 8;
    begin

        expected_keep <= (others => '0');
        expected_last <= '0';

        remaining := bytes_remaining;

        if remaining > 8 then

            expected_keep <= x"FF";
            expected_last <= '0';

        elsif remaining > 0 then

            final_bytes := remaining;

            expected_keep <=
                low_lane_mask(final_bytes);

            expected_last <= '1';

        end if;

    end process framing_expectation_process;


    offered_metadata_valid <=
        '1'
        when
            s_axis_tkeep = expected_keep
            and s_axis_tlast = expected_last
        else '0';


    -- ========================================================================
    -- External AXIS admission
    --
    -- The FIFO's available capacity determines whether an offered beat can be
    -- physically accepted. Metadata validity deliberately does NOT participate
    -- in TREADY: a malformed beat must handshake when buffering permits so the
    -- interface cannot deadlock waiting for the producer to change a held beat.
    -- ========================================================================

    s_axis_tready <=
        '1'
        when
            resetn = '1'
            and run_enable = '1'
            and quota_open = '1'
            and fifo_push_ready = '1'
        else '0';


    external_accept <=
        '1'
        when
            s_axis_tvalid = '1'
            and s_axis_tready = '1'
        else '0';


    accept_valid <=
        external_accept;


    accept_bytes <=
        std_logic_vector(
            to_unsigned(
                popcount8(s_axis_tkeep),
                accept_bytes'length
            )
        );


    frame_error <=
        '1'
        when
            external_accept = '1'
            and offered_metadata_valid = '0'
        else '0';


    -- ========================================================================
    -- FIFO push
    --
    -- Only correctly framed beats are committed to the input FIFO.
    -- Malformed accepted beats are counted/reported above but never reach the
    -- convolution datapath.
    -- ========================================================================

    fifo_push_valid <=
        '1'
        when
            external_accept = '1'
            and offered_metadata_valid = '1'
        else '0';


    fifo_push_data <=
        s_axis_tdata
        & s_axis_tkeep
        & s_axis_tlast;


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
                fifo_pop_ready,

            pop_data =>
                fifo_pop_data,

            level =>
                fifo_level
        );


    -- ========================================================================
    -- Physical accepted-byte quota bookkeeping
    --
    -- This local count exists only to determine framing expectations and when
    -- to stop accepting more input. The architectural counter lives in
    -- axi_lite_ctrl and receives accept_valid/accept_bytes.
    -- ========================================================================

    quota_counter_process : process(clk)
        variable next_count :
            natural;
    begin
        if rising_edge(clk) then

            if resetn = '0' then

                accepted_byte_count <= 0;

            else

                if start_pulse = '1' then
                    next_count := 0;
                else
                    next_count := accepted_byte_count;
                end if;


                if external_accept = '1' then

                    next_count :=
                        next_count
                        + popcount8(s_axis_tkeep);

                    if next_count > C_ACCEPT_COUNT_MAX then
                        accepted_byte_count <= C_ACCEPT_COUNT_MAX;
                    else
                        accepted_byte_count <= next_count;
                    end if;

                elsif start_pulse = '1' then

                    accepted_byte_count <= 0;

                end if;

            end if;

        end if;
    end process quota_counter_process;


    -- ========================================================================
    -- Byte unpacker
    --
    -- Valid admitted beats always contain contiguous low lanes, but the lane
    -- helper structure is retained because it keeps the unpacker generic and
    -- makes the final partial beat straightforward.
    --
    -- During FAULT/ABORT run_enable goes low. FIFO and active-beat contents
    -- remain frozen until an admitted local RESET drives resetn low.
    -- ========================================================================

    current_lane <=
        first_valid_lane(
            beat_keep,
            lane_index
        )
        when beat_active = '1'
        else -1;


    out_valid_int <=
        '1'
        when
            run_enable = '1'
            and beat_active = '1'
            and current_lane >= 0
        else '0';


    out_valid <=
        out_valid_int;


    pixel_fire <=
        '1'
        when
            out_valid_int = '1'
            and out_ready = '1'
        else '0';


    consumed_pulse <=
        pixel_fire;


    final_pixel_fire <=
        '1'
        when
            pixel_fire = '1'
            and is_final_valid_lane(
                beat_keep,
                current_lane
            )
        else '0';


    -- Pop a new FIFO beat when idle, or on the same edge as the current beat's
    -- final pixel handshake. This preserves the original bubble-free valid
    -- input path.
    --
    -- When RUN is removed by ABORT/FAULT, no further FIFO/beat movement occurs.
    fifo_pop_ready <=
        '1'
        when
            run_enable = '1'
            and
            (
                beat_active = '0'
                or final_pixel_fire = '1'
            )
        else '0';


    -- ========================================================================
    -- Pixel data
    -- ========================================================================

    pixel_mux_process : process(all)
    begin

        out_pixel <= (others => '0');

        if out_valid_int = '1' then

            case current_lane is

                when 0 =>
                    out_pixel <= beat_data(7 downto 0);

                when 1 =>
                    out_pixel <= beat_data(15 downto 8);

                when 2 =>
                    out_pixel <= beat_data(23 downto 16);

                when 3 =>
                    out_pixel <= beat_data(31 downto 24);

                when 4 =>
                    out_pixel <= beat_data(39 downto 32);

                when 5 =>
                    out_pixel <= beat_data(47 downto 40);

                when 6 =>
                    out_pixel <= beat_data(55 downto 48);

                when 7 =>
                    out_pixel <= beat_data(63 downto 56);

                when others =>
                    null;

            end case;

        end if;

    end process pixel_mux_process;


    -- ========================================================================
    -- Final input pixel indication
    -- ========================================================================

    last_process : process(all)
    begin

        out_last <= '0';

        if
            out_valid_int = '1'
            and beat_tlast = '1'
            and is_final_valid_lane(
                beat_keep,
                current_lane
            )
        then
            out_last <= '1';
        end if;

    end process last_process;


    -- ========================================================================
    -- FIFO beat staging / lane traversal
    -- ========================================================================

    unpack_process : process(clk)
    begin
        if rising_edge(clk) then

            if resetn = '0' then

                beat_active <= '0';

                beat_data <=
                    (others => '0');

                beat_keep <=
                    (others => '0');

                beat_tlast <=
                    '0';

                lane_index <=
                    0;

            elsif run_enable = '1' then

                if
                    beat_active = '0'
                    or final_pixel_fire = '1'
                then

                    if fifo_pop_valid = '1' then

                        beat_data <=
                            fifo_pop_data(72 downto 9);

                        beat_keep <=
                            fifo_pop_data(8 downto 1);

                        beat_tlast <=
                            fifo_pop_data(0);

                        lane_index <=
                            0;

                        -- Every enqueued beat has already passed strict framing
                        -- validation and therefore has at least one valid byte.
                        beat_active <=
                            '1';

                    elsif final_pixel_fire = '1' then

                        beat_active <=
                            '0';

                        lane_index <=
                            0;

                    end if;

                elsif pixel_fire = '1' then

                    lane_index <=
                        current_lane + 1;

                end if;

            end if;

        end if;
    end process unpack_process;

end architecture rtl;