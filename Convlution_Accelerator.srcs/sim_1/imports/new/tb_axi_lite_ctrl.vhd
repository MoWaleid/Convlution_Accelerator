library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;


entity tb_axi_lite_ctrl is
end entity;


architecture sim of tb_axi_lite_ctrl is

    constant CLK_PERIOD : time := 10 ns;

    constant C_BUILD_ID_TB :
        std_logic_vector(127 downto 0) :=
            x"4D344E334B385733322D323630393131";

    constant AXI_OKAY :
        std_logic_vector(1 downto 0) := "00";

    constant AXI_SLVERR :
        std_logic_vector(1 downto 0) := "10";


    -- ========================================================================
    -- Common STATUS values
    -- ========================================================================

    constant STATUS_CLEAN :
        std_logic_vector(31 downto 0) := x"00000101";
        -- IDLE + QUIESCENT

    constant STATUS_ERROR :
        std_logic_vector(31 downto 0) := x"00000121";
        -- IDLE + ERROR + QUIESCENT

    constant STATUS_PARAM :
        std_logic_vector(31 downto 0) := x"00000181";
        -- IDLE + PARAM_COMPLETE + QUIESCENT

    constant STATUS_PARAM_ERROR :
        std_logic_vector(31 downto 0) := x"000001A1";
        -- IDLE + ERROR + PARAM_COMPLETE + QUIESCENT

    constant STATUS_CONFIG :
        std_logic_vector(31 downto 0) := x"00000182";
        -- BUSY + PARAM_COMPLETE + QUIESCENT

    constant STATUS_CONFIG_ERROR :
        std_logic_vector(31 downto 0) := x"000001A2";
        -- BUSY + ERROR + PARAM_COMPLETE + QUIESCENT

    constant STATUS_RUN :
        std_logic_vector(31 downto 0) := x"00000082";
        -- BUSY + PARAM_COMPLETE

    constant STATUS_RUN_ERROR :
        std_logic_vector(31 downto 0) := x"000000A2";
        -- BUSY + ERROR + PARAM_COMPLETE

    constant STATUS_FAULT :
        std_logic_vector(31 downto 0) := x"000001E2";
        -- BUSY + ERROR + FAULT + PARAM_COMPLETE + QUIESCENT

    constant STATUS_CORE_COMPLETE :
        std_logic_vector(31 downto 0) := x"00000086";
        -- BUSY + CORE_COMPLETE + PARAM_COMPLETE

    constant STATUS_SUCCESS :
        std_logic_vector(31 downto 0) := x"0000019D";
        -- IDLE + CORE_COMPLETE + OUTPUT_DRAINED +
        -- DONE + PARAM_COMPLETE + QUIESCENT

    constant STATUS_SUCCESS_NO_DONE :
        std_logic_vector(31 downto 0) := x"0000018D";
        -- IDLE + CORE_COMPLETE + OUTPUT_DRAINED +
        -- PARAM_COMPLETE + QUIESCENT


    -- ========================================================================
    -- Address helper
    -- ========================================================================

    function addr32(
        n : natural
    ) return std_logic_vector is
    begin
        return std_logic_vector(to_unsigned(n, 32));
    end function;


    -- ========================================================================
    -- Channel-local map
    -- ========================================================================

    constant CH0_COEFF0_ADDR :
        std_logic_vector(31 downto 0) := x"00000000";

    constant CH0_COEFF1_ADDR :
        std_logic_vector(31 downto 0) := x"00000004";

    constant CH0_COEFF2_ADDR :
        std_logic_vector(31 downto 0) := x"00000008";

    constant CH0_BIAS_ADDR :
        std_logic_vector(31 downto 0) := x"000000F8";

    constant CH0_CTRL_ADDR :
        std_logic_vector(31 downto 0) := x"000000FC";


    -- ========================================================================
    -- Legacy / invalid addresses
    -- ========================================================================

    constant LEGACY_STATUS_ADDR :
        std_logic_vector(31 downto 0) := x"00004000";

    constant LEGACY_CONTROL_ADDR :
        std_logic_vector(31 downto 0) := x"00004004";

    constant RESERVED_411C_ADDR :
        std_logic_vector(31 downto 0) := x"0000411C";

    constant UNALIGNED_ADDR :
        std_logic_vector(31 downto 0) := x"00004101";


    -- ========================================================================
    -- CVH1 global map
    -- ========================================================================

    constant MAGIC_ADDR :
        std_logic_vector(31 downto 0) := x"00004100";

    constant ABI_VERSION_ADDR :
        std_logic_vector(31 downto 0) := x"00004104";

    constant CAPABILITIES_ADDR :
        std_logic_vector(31 downto 0) := x"00004108";

    constant STATUS_ADDR :
        std_logic_vector(31 downto 0) := x"0000410C";

    constant COMMAND_ADDR :
        std_logic_vector(31 downto 0) := x"00004110";

    constant EVENT_CLEAR_ADDR :
        std_logic_vector(31 downto 0) := x"00004114";

    constant ERROR_FLAGS_ADDR :
        std_logic_vector(31 downto 0) := x"00004118";

    constant IMAGE_W_ADDR :
        std_logic_vector(31 downto 0) := x"00004120";

    constant IMAGE_H_ADDR :
        std_logic_vector(31 downto 0) := x"00004124";

    constant KERNEL_N_ADDR :
        std_logic_vector(31 downto 0) := x"00004128";

    constant CHANNEL_K_ADDR :
        std_logic_vector(31 downto 0) := x"0000412C";

    constant WIDTHS_0_ADDR :
        std_logic_vector(31 downto 0) := x"00004130";

    constant WIDTHS_1_ADDR :
        std_logic_vector(31 downto 0) := x"00004134";

    constant EXPECTED_INPUT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004138";

    constant EXPECTED_OUTPUT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"0000413C";

    constant INPUT_ACCEPT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004140";

    constant INPUT_CONSUMED_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004144";

    constant CORE_ACCEPT_PIXELS_ADDR :
        std_logic_vector(31 downto 0) := x"00004148";

    constant OUTPUT_ACCEPT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"0000414C";

    constant BUILD_ID_0_ADDR :
        std_logic_vector(31 downto 0) := x"00004150";

    constant BUILD_ID_1_ADDR :
        std_logic_vector(31 downto 0) := x"00004154";

    constant BUILD_ID_2_ADDR :
        std_logic_vector(31 downto 0) := x"00004158";

    constant BUILD_ID_3_ADDR :
        std_logic_vector(31 downto 0) := x"0000415C";

    constant DMA_LENGTH_WIDTH_ADDR :
        std_logic_vector(31 downto 0) := x"00004160";


    -- ========================================================================
    -- AXI4-Lite
    -- ========================================================================

    signal S_AXI_ACLK :
        std_logic := '0';

    signal S_AXI_ARESETN :
        std_logic := '0';


    signal S_AXI_AWADDR :
        std_logic_vector(31 downto 0) := (others => '0');

    signal S_AXI_AWPROT :
        std_logic_vector(2 downto 0) := (others => '0');

    signal S_AXI_AWVALID :
        std_logic := '0';

    signal S_AXI_AWREADY :
        std_logic;


    signal S_AXI_WDATA :
        std_logic_vector(31 downto 0) := (others => '0');

    signal S_AXI_WSTRB :
        std_logic_vector(3 downto 0) := (others => '0');

    signal S_AXI_WVALID :
        std_logic := '0';

    signal S_AXI_WREADY :
        std_logic;


    signal S_AXI_BRESP :
        std_logic_vector(1 downto 0);

    signal S_AXI_BVALID :
        std_logic;

    signal S_AXI_BREADY :
        std_logic := '0';


    signal S_AXI_ARADDR :
        std_logic_vector(31 downto 0) := (others => '0');

    signal S_AXI_ARPROT :
        std_logic_vector(2 downto 0) := (others => '0');

    signal S_AXI_ARVALID :
        std_logic := '0';

    signal S_AXI_ARREADY :
        std_logic;


    signal S_AXI_RDATA :
        std_logic_vector(31 downto 0);

    signal S_AXI_RRESP :
        std_logic_vector(1 downto 0);

    signal S_AXI_RVALID :
        std_logic;

    signal S_AXI_RREADY :
        std_logic := '0';


    -- ========================================================================
    -- Runtime events
    -- ========================================================================

    signal input_accept_valid :
        std_logic := '0';

    signal input_accept_bytes :
        std_logic_vector(3 downto 0) := (others => '0');

    signal input_consumed_pulse :
        std_logic := '0';

    signal input_frame_error :
        std_logic := '0';

    signal core_accept_pulse :
        std_logic := '0';

    signal output_accept_valid :
        std_logic := '0';

    signal output_accept_bytes :
        std_logic_vector(3 downto 0) := (others => '0');

    signal output_accept_last :
        std_logic := '0';

    signal output_fifo_empty :
        std_logic := '1';

    signal output_tvalid :
        std_logic := '0';

    signal internal_error_in :
        std_logic := '0';

    signal datapath_config_ready :
        std_logic := '1';


    -- ========================================================================
    -- Lifecycle outputs
    -- ========================================================================

    signal start_pulse :
        std_logic;

    signal local_reset_pulse :
        std_logic;

    signal run_enable :
        std_logic;

    signal production_enable :
        std_logic;

    signal coeff_write_pulse :
        std_logic;

    signal coeff_write_addr :
        std_logic_vector(31 downto 0);

    signal coeff_write_data :
        std_logic_vector(31 downto 0);

    signal start_pulse_count :
        natural := 0;

    signal local_reset_pulse_count :
        natural := 0;

    signal coeff_write_pulse_count :
        natural := 0;


    -- ========================================================================
    -- Parameters
    -- ========================================================================

    signal coeffs_out :
        coeff_array_t(
            0 to CFG_K * CFG_N * CFG_N - 1
        );

    signal bias_out :
        bias_array_t(0 to CFG_K - 1);

    signal shift_out :
        shift_array_t(0 to CFG_K - 1);

    signal relu_en_out :
        std_logic_vector(0 to CFG_K - 1);


begin

    -- ========================================================================
    -- Clock
    -- ========================================================================

    clk_process : process
    begin
        S_AXI_ACLK <= '0';
        wait for CLK_PERIOD / 2;

        S_AXI_ACLK <= '1';
        wait for CLK_PERIOD / 2;
    end process;


    -- ========================================================================
    -- DUT
    -- ========================================================================

    uut :
        entity work.axi_lite_ctrl
        generic map (
            C_S_AXI_DATA_WIDTH =>
                32,

            C_S_AXI_ADDR_WIDTH =>
                32,

            C_K =>
                CFG_K,

            C_N =>
                CFG_N,

            C_LOGICAL_IMAGE_WIDTH =>
                CFG_UNPADDED_WIDTH,

            C_LOGICAL_IMAGE_HEIGHT =>
                CFG_UNPADDED_HEIGHT,

            C_BUILD_ID =>
                C_BUILD_ID_TB,

            C_DMA_LENGTH_WIDTH =>
                22
        )
        port map (
            S_AXI_ACLK =>
                S_AXI_ACLK,

            S_AXI_ARESETN =>
                S_AXI_ARESETN,

            S_AXI_AWADDR =>
                S_AXI_AWADDR,

            S_AXI_AWPROT =>
                S_AXI_AWPROT,

            S_AXI_AWVALID =>
                S_AXI_AWVALID,

            S_AXI_AWREADY =>
                S_AXI_AWREADY,

            S_AXI_WDATA =>
                S_AXI_WDATA,

            S_AXI_WSTRB =>
                S_AXI_WSTRB,

            S_AXI_WVALID =>
                S_AXI_WVALID,

            S_AXI_WREADY =>
                S_AXI_WREADY,

            S_AXI_BRESP =>
                S_AXI_BRESP,

            S_AXI_BVALID =>
                S_AXI_BVALID,

            S_AXI_BREADY =>
                S_AXI_BREADY,

            S_AXI_ARADDR =>
                S_AXI_ARADDR,

            S_AXI_ARPROT =>
                S_AXI_ARPROT,

            S_AXI_ARVALID =>
                S_AXI_ARVALID,

            S_AXI_ARREADY =>
                S_AXI_ARREADY,

            S_AXI_RDATA =>
                S_AXI_RDATA,

            S_AXI_RRESP =>
                S_AXI_RRESP,

            S_AXI_RVALID =>
                S_AXI_RVALID,

            S_AXI_RREADY =>
                S_AXI_RREADY,

            input_accept_valid =>
                input_accept_valid,

            input_accept_bytes =>
                input_accept_bytes,

            input_consumed_pulse =>
                input_consumed_pulse,

            input_frame_error =>
                input_frame_error,

            core_accept_pulse =>
                core_accept_pulse,

            output_accept_valid =>
                output_accept_valid,

            output_accept_bytes =>
                output_accept_bytes,

            output_accept_last =>
                output_accept_last,

            output_fifo_empty =>
                output_fifo_empty,

            output_tvalid =>
                output_tvalid,

            internal_error_in =>
                internal_error_in,

            datapath_config_ready =>
                datapath_config_ready,

            start_pulse =>
                start_pulse,

            local_reset_pulse =>
                local_reset_pulse,

            run_enable =>
                run_enable,

            production_enable =>
                production_enable,

            coeff_write_pulse =>
                coeff_write_pulse,

            coeff_write_addr =>
                coeff_write_addr,

            coeff_write_data =>
                coeff_write_data,

            coeffs_out =>
                coeffs_out,

            bias_out =>
                bias_out,

            shift_out =>
                shift_out,

            relu_en_out =>
                relu_en_out
        );

    pulse_monitor : process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then
            if S_AXI_ARESETN = '0' then
                start_pulse_count       <= 0;
                local_reset_pulse_count <= 0;
                coeff_write_pulse_count <= 0;
            else
                if start_pulse = '1' then
                    start_pulse_count <= start_pulse_count + 1;
                end if;
                if local_reset_pulse = '1' then
                    local_reset_pulse_count <= local_reset_pulse_count + 1;
                end if;
                if coeff_write_pulse = '1' then
                    coeff_write_pulse_count <= coeff_write_pulse_count + 1;
                end if;
            end if;
        end if;
    end process pulse_monitor;


    -- ========================================================================
    -- Stimulus + local AXI helpers
    -- ========================================================================

    stim_proc : process

        -- --------------------------------------------------------------------
        -- Complete read transaction.
        -- Also stalls RREADY to prove response stability.
        -- --------------------------------------------------------------------

        procedure axi_read_check(
            constant addr :
                in std_logic_vector(31 downto 0);

            constant expected_data :
                in std_logic_vector(31 downto 0);

            constant expected_resp :
                in std_logic_vector(1 downto 0);

            constant tag :
                in string
        ) is

            variable held_data :
                std_logic_vector(31 downto 0);

            variable held_resp :
                std_logic_vector(1 downto 0);

        begin

            S_AXI_ARADDR <= addr;

            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_ARREADY = '1';
            end loop;

            S_AXI_ARVALID <= '1';

            wait until rising_edge(S_AXI_ACLK);

            S_AXI_ARVALID <= '0';


            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_RVALID = '1';
            end loop;


            held_data := S_AXI_RDATA;
            held_resp := S_AXI_RRESP;


            assert held_resp = expected_resp
                report tag & ": incorrect RRESP"
                severity error;

            assert held_data = expected_data
                report tag & ": incorrect RDATA"
                severity error;


            -- Hold response for one full cycle.
            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;


            assert S_AXI_RVALID = '1'
                report tag & ": RVALID dropped while stalled"
                severity error;

            assert S_AXI_RRESP = held_resp
                report tag & ": RRESP changed while stalled"
                severity error;

            assert S_AXI_RDATA = held_data
                report tag & ": RDATA changed while stalled"
                severity error;


            wait until falling_edge(S_AXI_ACLK);

            S_AXI_RREADY <= '1';

            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;

            S_AXI_RREADY <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Complete same-cycle AW/W transaction.
        -- Also stalls BREADY.
        -- --------------------------------------------------------------------

        procedure axi_write_check(
            constant addr :
                in std_logic_vector(31 downto 0);

            constant data :
                in std_logic_vector(31 downto 0);

            constant strb :
                in std_logic_vector(3 downto 0);

            constant expected_resp :
                in std_logic_vector(1 downto 0);

            constant tag :
                in string
        ) is

            variable held_resp :
                std_logic_vector(1 downto 0);

        begin

            S_AXI_AWADDR <= addr;
            S_AXI_WDATA  <= data;
            S_AXI_WSTRB  <= strb;


            loop
                wait until falling_edge(S_AXI_ACLK);

                exit when
                    S_AXI_AWREADY = '1' and
                    S_AXI_WREADY = '1';
            end loop;


            S_AXI_AWVALID <= '1';
            S_AXI_WVALID  <= '1';

            wait until rising_edge(S_AXI_ACLK);

            S_AXI_AWVALID <= '0';
            S_AXI_WVALID  <= '0';


            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_BVALID = '1';
            end loop;


            held_resp := S_AXI_BRESP;


            assert held_resp = expected_resp
                report tag & ": incorrect BRESP"
                severity error;


            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;


            assert S_AXI_BVALID = '1'
                report tag & ": BVALID dropped while stalled"
                severity error;

            assert S_AXI_BRESP = held_resp
                report tag & ": BRESP changed while stalled"
                severity error;


            wait until falling_edge(S_AXI_ACLK);

            S_AXI_BREADY <= '1';

            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;

            S_AXI_BREADY <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Send only AW.
        -- --------------------------------------------------------------------

        procedure send_aw_only(
            constant addr :
                in std_logic_vector(31 downto 0)
        ) is
        begin

            S_AXI_AWADDR <= addr;

            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_AWREADY = '1';
            end loop;

            S_AXI_AWVALID <= '1';

            wait until rising_edge(S_AXI_ACLK);

            S_AXI_AWVALID <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Send only W.
        -- --------------------------------------------------------------------

        procedure send_w_only(
            constant data :
                in std_logic_vector(31 downto 0);

            constant strb :
                in std_logic_vector(3 downto 0)
        ) is
        begin

            S_AXI_WDATA <= data;
            S_AXI_WSTRB <= strb;

            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_WREADY = '1';
            end loop;

            S_AXI_WVALID <= '1';

            wait until rising_edge(S_AXI_ACLK);

            S_AXI_WVALID <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Consume an already-created B response.
        -- Holds BREADY low for hold_cycles.
        -- --------------------------------------------------------------------

        procedure expect_b_response(
            constant expected_resp :
                in std_logic_vector(1 downto 0);

            constant hold_cycles :
                in natural;

            constant tag :
                in string
        ) is

            variable held_resp :
                std_logic_vector(1 downto 0);

        begin

            loop
                wait until falling_edge(S_AXI_ACLK);
                exit when S_AXI_BVALID = '1';
            end loop;

            held_resp := S_AXI_BRESP;


            assert held_resp = expected_resp
                report tag & ": incorrect BRESP"
                severity error;


            for i in 1 to hold_cycles loop

                wait until rising_edge(S_AXI_ACLK);
                wait for 1 ns;

                assert S_AXI_BVALID = '1'
                    report tag & ": BVALID dropped while stalled"
                    severity error;

                assert S_AXI_BRESP = held_resp
                    report tag & ": BRESP changed while stalled"
                    severity error;

            end loop;


            wait until falling_edge(S_AXI_ACLK);

            S_AXI_BREADY <= '1';

            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;

            S_AXI_BREADY <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Simultaneous read + write acceptance to the SAME register.
        --
        -- The read must return the PRE-WRITE value.
        -- --------------------------------------------------------------------

        procedure same_edge_rw_check(
            constant addr :
                in std_logic_vector(31 downto 0);

            constant new_data :
                in std_logic_vector(31 downto 0);

            constant expected_old_data :
                in std_logic_vector(31 downto 0);

            constant tag :
                in string
        ) is

            variable held_rdata :
                std_logic_vector(31 downto 0);

            variable held_rresp :
                std_logic_vector(1 downto 0);

            variable held_bresp :
                std_logic_vector(1 downto 0);

        begin

            S_AXI_AWADDR <= addr;
            S_AXI_WDATA  <= new_data;
            S_AXI_WSTRB  <= "1111";

            S_AXI_ARADDR <= addr;


            loop

                wait until falling_edge(S_AXI_ACLK);

                exit when
                    S_AXI_AWREADY = '1' and
                    S_AXI_WREADY  = '1' and
                    S_AXI_ARREADY = '1';

            end loop;


            S_AXI_AWVALID <= '1';
            S_AXI_WVALID  <= '1';
            S_AXI_ARVALID <= '1';


            wait until rising_edge(S_AXI_ACLK);


            S_AXI_AWVALID <= '0';
            S_AXI_WVALID  <= '0';
            S_AXI_ARVALID <= '0';


            -- Keep both READY signals low so both responses are retained.
            loop

                wait until falling_edge(S_AXI_ACLK);

                exit when
                    S_AXI_BVALID = '1' and
                    S_AXI_RVALID = '1';

            end loop;


            held_bresp := S_AXI_BRESP;
            held_rresp := S_AXI_RRESP;
            held_rdata := S_AXI_RDATA;


            assert held_bresp = AXI_OKAY
                report tag & ": write did not return OKAY"
                severity error;

            assert held_rresp = AXI_OKAY
                report tag & ": read did not return OKAY"
                severity error;

            assert held_rdata = expected_old_data
                report tag & ": same-edge read did not return pre-write data"
                severity error;


            -- One outstanding read only.
            assert S_AXI_ARREADY = '0'
                report tag & ": ARREADY accepted another read while RVALID pending"
                severity error;


            -- Hold responses while storage has already changed.
            for i in 1 to 3 loop

                wait until rising_edge(S_AXI_ACLK);
                wait for 1 ns;

                assert S_AXI_BVALID = '1'
                    report tag & ": BVALID dropped while stalled"
                    severity error;

                assert S_AXI_RVALID = '1'
                    report tag & ": RVALID dropped while stalled"
                    severity error;

                assert S_AXI_BRESP = held_bresp
                    report tag & ": BRESP changed while stalled"
                    severity error;

                assert S_AXI_RRESP = held_rresp
                    report tag & ": RRESP changed while stalled"
                    severity error;

                assert S_AXI_RDATA = held_rdata
                    report tag & ": RDATA changed after underlying register write"
                    severity error;

            end loop;


            wait until falling_edge(S_AXI_ACLK);

            S_AXI_BREADY <= '1';
            S_AXI_RREADY <= '1';

            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;

            S_AXI_BREADY <= '0';
            S_AXI_RREADY <= '0';

        end procedure;


        -- --------------------------------------------------------------------
        -- Runtime event helpers
        -- --------------------------------------------------------------------

        procedure input_accept_beats(
            constant count :
                in natural;

            constant bytes_per_beat :
                in natural
        ) is
        begin

            wait until falling_edge(S_AXI_ACLK);

            input_accept_valid <= '1';

            input_accept_bytes <=
                std_logic_vector(
                    to_unsigned(bytes_per_beat, 4)
                );


            for i in 1 to count loop
                wait until rising_edge(S_AXI_ACLK);
            end loop;


            input_accept_valid <= '0';
            input_accept_bytes <= (others => '0');

        end procedure;


        procedure input_consumed_cycles(
            constant count :
                in natural
        ) is
        begin

            wait until falling_edge(S_AXI_ACLK);

            input_consumed_pulse <= '1';


            for i in 1 to count loop
                wait until rising_edge(S_AXI_ACLK);
            end loop;


            input_consumed_pulse <= '0';

        end procedure;


        procedure core_accept_cycles(
            constant count :
                in natural
        ) is
        begin

            wait until falling_edge(S_AXI_ACLK);

            core_accept_pulse <= '1';


            for i in 1 to count loop
                wait until rising_edge(S_AXI_ACLK);
            end loop;


            core_accept_pulse <= '0';

        end procedure;


        procedure output_accept_beats(
            constant count :
                in natural;

            constant bytes_per_beat :
                in natural;

            constant last_on_final :
                in boolean
        ) is
        begin

            wait until falling_edge(S_AXI_ACLK);

            output_accept_valid <= '1';

            output_accept_bytes <=
                std_logic_vector(
                    to_unsigned(bytes_per_beat, 4)
                );

            output_accept_last <= '0';


            for i in 1 to count loop

                if last_on_final and i = count then
                    output_accept_last <= '1';
                else
                    output_accept_last <= '0';
                end if;

                wait until rising_edge(S_AXI_ACLK);

            end loop;


            output_accept_valid <= '0';
            output_accept_bytes <= (others => '0');
            output_accept_last  <= '0';

        end procedure;


        procedure pulse_input_frame_error is
        begin

            wait until falling_edge(S_AXI_ACLK);

            input_frame_error <= '1';

            wait until rising_edge(S_AXI_ACLK);

            input_frame_error <= '0';

            wait for 1 ns;

        end procedure;


        procedure pulse_internal_error is
        begin

            wait until falling_edge(S_AXI_ACLK);

            internal_error_in <= '1';

            wait until rising_edge(S_AXI_ACLK);

            internal_error_in <= '0';

            wait for 1 ns;

        end procedure;

        variable start_count_before :
            natural;

        variable reset_count_before :
            natural;

        variable coeff_count_before :
            natural;


    begin

        -- ====================================================================
        -- Static sanity
        -- ====================================================================

        assert CFG_K = 16
            report "This research controller regression expects CFG_K=16"
            severity failure;

        assert CFG_N = 3
            report "This controller regression currently expects CFG_N=3"
            severity failure;

        assert CFG_UNPADDED_WIDTH = 32 and CFG_UNPADDED_HEIGHT = 32
            report "This research controller regression expects 32x32 geometry"
            severity failure;


        -- ====================================================================
        -- Full reset
        -- ====================================================================

        S_AXI_ARESETN <= '0';

        wait for 4 * CLK_PERIOD;

        wait until falling_edge(S_AXI_ACLK);

        S_AXI_ARESETN <= '1';

        wait until rising_edge(S_AXI_ACLK);
        wait for 1 ns;


        -- ====================================================================
        -- CATEGORY 1
        -- Discovery / reset state
        -- ====================================================================

        report "--- CVH1 category 1: reset + discovery ---";


        assert run_enable = '0'
            report "run_enable asserted after reset"
            severity error;

        assert production_enable = '0'
            report "production_enable asserted after reset"
            severity error;

        assert start_pulse = '0'
            report "start_pulse asserted after reset"
            severity error;

        assert local_reset_pulse = '0'
            report "local_reset_pulse asserted after reset"
            severity error;


        axi_read_check(
            MAGIC_ADDR,
            x"43564831",
            AXI_OKAY,
            "MAGIC"
        );

        axi_read_check(
            ABI_VERSION_ADDR,
            x"00010000",
            AXI_OKAY,
            "ABI_VERSION"
        );

        axi_read_check(
            CAPABILITIES_ADDR,
            x"000001FF",
            AXI_OKAY,
            "CAPABILITIES"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_CLEAN,
            AXI_OKAY,
            "power-on STATUS"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "power-on ERROR_FLAGS"
        );

        axi_read_check(
            IMAGE_W_ADDR,
            x"00000020",
            AXI_OKAY,
            "IMAGE_W"
        );

        axi_read_check(
            IMAGE_H_ADDR,
            x"00000020",
            AXI_OKAY,
            "IMAGE_H"
        );

        axi_read_check(
            KERNEL_N_ADDR,
            x"00000003",
            AXI_OKAY,
            "KERNEL_N"
        );

        axi_read_check(
            CHANNEL_K_ADDR,
            x"00000010",
            AXI_OKAY,
            "CHANNEL_K"
        );

        axi_read_check(
            WIDTHS_0_ADDR,
            x"10180808",
            AXI_OKAY,
            "WIDTHS_0"
        );

        axi_read_check(
            WIDTHS_1_ADDR,
            x"00001915",
            AXI_OKAY,
            "WIDTHS_1"
        );

        axi_read_check(
            EXPECTED_INPUT_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "EXPECTED_INPUT_BYTES"
        );

        axi_read_check(
            EXPECTED_OUTPUT_BYTES_ADDR,
            x"00008000",
            AXI_OKAY,
            "EXPECTED_OUTPUT_BYTES"
        );

        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "INPUT_ACCEPT_BYTES reset"
        );

        axi_read_check(
            INPUT_CONSUMED_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "INPUT_CONSUMED_BYTES reset"
        );

        axi_read_check(
            CORE_ACCEPT_PIXELS_ADDR,
            x"00000000",
            AXI_OKAY,
            "CORE_ACCEPT_PIXELS reset"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "OUTPUT_ACCEPT_BYTES reset"
        );

        axi_read_check(
            BUILD_ID_0_ADDR,
            x"30393131",
            AXI_OKAY,
            "BUILD_ID_0"
        );

        axi_read_check(
            BUILD_ID_1_ADDR,
            x"322D3236",
            AXI_OKAY,
            "BUILD_ID_1"
        );

        axi_read_check(
            BUILD_ID_2_ADDR,
            x"4B385733",
            AXI_OKAY,
            "BUILD_ID_2"
        );

        axi_read_check(
            BUILD_ID_3_ADDR,
            x"4D344E33",
            AXI_OKAY,
            "BUILD_ID_3"
        );

        axi_read_check(
            DMA_LENGTH_WIDTH_ADDR,
            x"00000016",
            AXI_OKAY,
            "DMA_LENGTH_WIDTH"
        );


        report "--- CVH1 category 1 PASS ---";


        -- ====================================================================
        -- CATEGORY 2
        -- Invalid / legacy addressing
        -- ====================================================================

        report "--- CVH1 category 2: invalid address handling ---";


        axi_read_check(
            LEGACY_STATUS_ADDR,
            x"00000000",
            AXI_SLVERR,
            "legacy 0x4000 read"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            AXI_OKAY,
            "BAD_ADDRESS after legacy read"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear BAD_ADDRESS"
        );


        axi_write_check(
            LEGACY_CONTROL_ADDR,
            x"00000001",
            "1111",
            AXI_SLVERR,
            "legacy 0x4004 write"
        );


        assert start_pulse = '0'
            report "legacy 0x4004 generated START"
            severity error;

        assert local_reset_pulse = '0'
            report "legacy 0x4004 generated RESET"
            severity error;

        assert run_enable = '0'
            report "legacy 0x4004 entered RUN"
            severity error;


        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear legacy BAD_ADDRESS"
        );


        axi_read_check(
            RESERVED_411C_ADDR,
            x"00000000",
            AXI_SLVERR,
            "reserved 0x411C read"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear reserved BAD_ADDRESS"
        );


        axi_read_check(
            UNALIGNED_ADDR,
            x"00000000",
            AXI_SLVERR,
            "unaligned read"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear unaligned BAD_ADDRESS"
        );


        axi_read_check(
            STATUS_ADDR,
            STATUS_CLEAN,
            AXI_OKAY,
            "clean STATUS after category 2"
        );


        report "--- CVH1 category 2 PASS ---";


        -- ====================================================================
        -- CATEGORY 3
        -- Write admission / precedence
        -- ====================================================================

        report "--- CVH1 category 3: write admission rules ---";


        -- RO write -> BAD_ACCESS.
        axi_write_check(
            MAGIC_ADDR,
            x"DEADBEEF",
            "1111",
            AXI_SLVERR,
            "write RO MAGIC"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000002",
            AXI_OKAY,
            "BAD_ACCESS"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "clear BAD_ACCESS"
        );


        -- WSTRB=0 does not legalize RO address.
        axi_write_check(
            MAGIC_ADDR,
            x"00000000",
            "0000",
            AXI_SLVERR,
            "zero-strobe RO"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000002",
            AXI_OKAY,
            "BAD_ACCESS precedence"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "clear BAD_ACCESS precedence"
        );


        -- WSTRB=0 does not legalize invalid address.
        axi_write_check(
            LEGACY_STATUS_ADDR,
            x"00000000",
            "0000",
            AXI_SLVERR,
            "zero-strobe invalid address"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            AXI_OKAY,
            "BAD_ADDRESS precedence"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear BAD_ADDRESS precedence"
        );


        -- Valid writable address + WSTRB=0 = true no-op.
        -- Data itself is deliberately noncanonical signed24.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"00800000",
            "0000",
            AXI_OKAY,
            "zero-strobe writable bias"
        );


        assert bias_out(0) = x"000000"
            report "zero-strobe write modified bias"
            severity error;


        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "zero-strobe writable error state"
        );


        -- Partial strobe wins before BAD_VALUE.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"00800000",
            "0001",
            AXI_SLVERR,
            "partial-strobe bias"
        );

        assert bias_out(0) = x"000000"
            report "partial-strobe write modified bias"
            severity error;

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000004",
            AXI_OKAY,
            "BAD_STROBE precedence"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000004",
            "1111",
            AXI_OKAY,
            "clear BAD_STROBE"
        );


        report "--- CVH1 category 3 PASS ---";


        -- ====================================================================
        -- CATEGORY 4
        -- Parameter programming / signed24 / PARAM_COMPLETE
        -- ====================================================================

        report "--- CVH1 category 4: parameter programming ---";


        -- Noncanonical signed24 positive overflow.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"00800000",
            "1111",
            AXI_SLVERR,
            "noncanonical positive bias"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "BAD_VALUE positive bias"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear positive-bias BAD_VALUE"
        );


        -- Noncanonical signed24 negative encoding.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"FF7FFFFF",
            "1111",
            AXI_SLVERR,
            "noncanonical negative bias"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "BAD_VALUE negative bias"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear negative-bias BAD_VALUE"
        );


        -- Program every required word except channel-0 bias.
        for ch in 0 to CFG_K - 1 loop

            axi_write_check(
                addr32(ch * 16#100# + 16#00#),
                x"04030201",
                "1111",
                AXI_OKAY,
                "coeff word 0"
            );

            axi_write_check(
                addr32(ch * 16#100# + 16#04#),
                x"08070605",
                "1111",
                AXI_OKAY,
                "coeff word 1"
            );

            axi_write_check(
                addr32(ch * 16#100# + 16#08#),
                x"00000009",
                "1111",
                AXI_OKAY,
                "coeff word 2"
            );


            if ch /= 0 then

                -- Full-word zero still counts as admitted.
                axi_write_check(
                    addr32(ch * 16#100# + 16#F8#),
                    x"00000000",
                    "1111",
                    AXI_OKAY,
                    "channel bias"
                );

            end if;


            axi_write_check(
                addr32(ch * 16#100# + 16#FC#),
                x"00000103",
                "1111",
                AXI_OKAY,
                "channel control"
            );

        end loop;


        -- Previous WSTRB=0 CH0 bias write must NOT have admitted it.
        axi_read_check(
            STATUS_ADDR,
            STATUS_CLEAN,
            AXI_OKAY,
            "PARAM_COMPLETE low with CH0 bias missing"
        );


        -- START must fail while PARAM_COMPLETE=0.
        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_SLVERR,
            "START before PARAM_COMPLETE"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000020",
            AXI_OKAY,
            "BAD_COMMAND_STATE before PARAM_COMPLETE"
        );

        assert run_enable = '0'
            report "START entered RUN without PARAM_COMPLETE"
            severity error;

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000020",
            "1111",
            AXI_OKAY,
            "clear incomplete-parameter START error"
        );


        -- Final required admission: CH0 bias = -1.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFF",
            "1111",
            AXI_OKAY,
            "CH0 bias -1"
        );

        assert bias_out(0) = x"FFFFFF"
            report "signed24 -1 storage incorrect"
            severity error;

        axi_read_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFF",
            AXI_OKAY,
            "signed24 -1 readback"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "PARAM_COMPLETE asserted"
        );


        -- Legal maximum.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"007FFFFF",
            "1111",
            AXI_OKAY,
            "signed24 maximum"
        );

        axi_read_check(
            CH0_BIAS_ADDR,
            x"007FFFFF",
            AXI_OKAY,
            "signed24 maximum readback"
        );


        -- Legal minimum.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"FF800000",
            "1111",
            AXI_OKAY,
            "signed24 minimum"
        );

        axi_read_check(
            CH0_BIAS_ADDR,
            x"FF800000",
            AXI_OKAY,
            "signed24 minimum readback"
        );


        -- Restore -1.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFF",
            "1111",
            AXI_OKAY,
            "restore CH0 bias -1"
        );


        -- Unused coefficient lanes must be zero.
        axi_write_check(
            CH0_COEFF2_ADDR,
            x"01000009",
            "1111",
            AXI_SLVERR,
            "nonzero unused coefficient lane"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "BAD_VALUE unused coefficient lane"
        );

        axi_read_check(
            CH0_COEFF2_ADDR,
            x"00000009",
            AXI_OKAY,
            "coefficient preserved after reject"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM_ERROR,
            AXI_OKAY,
            "PARAM_COMPLETE retained after rejected write"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear coefficient BAD_VALUE"
        );


        -- Reserved control bits.
        axi_write_check(
            CH0_CTRL_ADDR,
            x"00000200",
            "1111",
            AXI_SLVERR,
            "reserved channel control bit"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "BAD_VALUE reserved control bit"
        );

        axi_read_check(
            CH0_CTRL_ADDR,
            x"00000103",
            AXI_OKAY,
            "control preserved after reject"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear control BAD_VALUE"
        );


        report "--- CVH1 category 4 PASS ---";

        -- ====================================================================
        -- CATEGORY 4B
        -- Serial-CFGLUT configuration lifecycle and recovery
        -- ====================================================================

        report "--- CVH1 category 4B: CFGLUT configuration lifecycle ---";

        -- A valid parameter transaction may be accepted while the previous
        -- CFGLUT word is still loading, but it must not commit or respond
        -- until datapath_config_ready returns. Readback remains the installed
        -- register value until that atomic commit.
        datapath_config_ready <= '0';
        coeff_count_before := coeff_write_pulse_count;

        send_aw_only(CH0_COEFF0_ADDR);
        send_w_only(x"0D0C0B0A", "1111");

        for cycle in 1 to 3 loop
            wait until rising_edge(S_AXI_ACLK);
            wait for 1 ns;
            assert S_AXI_BVALID = '0'
                report "parameter write responded while CFGLUT loader busy"
                severity error;
            assert coeff_write_pulse_count = coeff_count_before
                report "parameter write committed while CFGLUT loader busy"
                severity error;
        end loop;

        axi_read_check(
            CH0_COEFF0_ADDR,
            x"04030201",
            AXI_OKAY,
            "readback changed before deferred parameter commit"
        );

        datapath_config_ready <= '1';
        expect_b_response(AXI_OKAY, 1, "deferred parameter write");

        assert coeff_write_pulse_count = coeff_count_before + 1
            report "deferred coefficient write did not emit one loader pulse"
            severity error;

        axi_read_check(
            CH0_COEFF0_ADDR,
            x"0D0C0B0A",
            AXI_OKAY,
            "deferred coefficient write did not commit"
        );

        -- Restore the category-4 coefficient value.
        axi_write_check(
            CH0_COEFF0_ADDR,
            x"04030201",
            "1111",
            AXI_OKAY,
            "restore CH0 coefficient word 0"
        );

        -- START remains responsive while the final serial configuration tail
        -- is busy. It enters CONFIG, reports BUSY, and does not release stream
        -- production until datapath_config_ready.
        datapath_config_ready <= '0';
        start_count_before := start_pulse_count;

        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "START while CFGLUT loader busy"
        );

        assert run_enable = '0' and production_enable = '0'
            report "CONFIG state released stream production early"
            severity error;

        assert start_pulse_count = start_count_before
            report "CONFIG state emitted START before coefficients installed"
            severity error;

        axi_read_check(
            STATUS_ADDR,
            STATUS_CONFIG,
            AXI_OKAY,
            "CONFIG STATUS while loader busy"
        );

        -- Parameter writes during CONFIG are rejected without mutation.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"00000005",
            "1111",
            AXI_SLVERR,
            "parameter write during CONFIG"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000010",
            AXI_OKAY,
            "BUSY_PARAMETER_WRITE during CONFIG"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_CONFIG_ERROR,
            AXI_OKAY,
            "CONFIG STATUS after rejected parameter write"
        );

        -- RESET must remain reachable while configuration is busy.
        reset_count_before := local_reset_pulse_count;
        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET during CONFIG"
        );

        assert local_reset_pulse_count = reset_count_before + 1
            report "RESET during CONFIG did not emit local reset pulse"
            severity error;

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "RESET during CONFIG did not restore clean IDLE"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "RESET during CONFIG did not clear errors"
        );

        -- ABORT must likewise be reachable before the loader finishes.
        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "second START while CFGLUT loader busy"
        );

        axi_write_check(
            COMMAND_ADDR,
            x"00000004",
            "1111",
            AXI_OKAY,
            "ABORT during CONFIG"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_FAULT,
            AXI_OKAY,
            "ABORT during CONFIG did not enter FAULT"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000100",
            AXI_OKAY,
            "ABORTED flag during CONFIG"
        );

        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET after CONFIG ABORT"
        );

        -- Finally prove the delayed transition emits exactly one START pulse.
        start_count_before := start_pulse_count;
        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "delayed CONFIG START"
        );

        assert start_pulse_count = start_count_before
            report "delayed CONFIG START pulsed before cfg_ready"
            severity error;

        datapath_config_ready <= '1';
        wait until rising_edge(S_AXI_ACLK);
        wait until rising_edge(S_AXI_ACLK);
        wait for 1 ns;

        assert start_pulse_count = start_count_before + 1
            report "CONFIG-to-RUN transition did not emit exactly one START pulse"
            severity error;

        assert run_enable = '1' and production_enable = '1'
            report "CONFIG-to-RUN transition did not enable production"
            severity error;

        -- Return to the clean IDLE/PARAM state expected by category 5.
        axi_write_check(
            COMMAND_ADDR,
            x"00000004",
            "1111",
            AXI_OKAY,
            "ABORT after delayed CONFIG START"
        );

        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET after delayed CONFIG START"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "category 4B final clean STATUS"
        );

        report "--- CVH1 category 4B PASS ---";


        -- ====================================================================
        -- CATEGORY 5
        -- COMMAND / lifecycle / BUSY write rejection
        -- ====================================================================

        report "--- CVH1 category 5: command lifecycle ---";


        -- Zero command invalid.
        axi_write_check(
            COMMAND_ADDR,
            x"00000000",
            "1111",
            AXI_SLVERR,
            "zero COMMAND"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "zero COMMAND BAD_VALUE"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear zero COMMAND error"
        );


        -- Combined opcode invalid.
        axi_write_check(
            COMMAND_ADDR,
            x"00000003",
            "1111",
            AXI_SLVERR,
            "combined COMMAND"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "combined COMMAND BAD_VALUE"
        );

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear combined COMMAND error"
        );


        -- START forbidden with sticky error.
        axi_write_check(
            MAGIC_ADDR,
            x"AAAAAAAA",
            "1111",
            AXI_SLVERR,
            "create BAD_ACCESS"
        );

        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_SLVERR,
            "START with sticky error"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000022",
            AXI_OKAY,
            "START error preconditions"
        );

        assert run_enable = '0'
            report "rejected START entered RUN"
            severity error;

        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000022",
            "1111",
            AXI_OKAY,
            "clear START errors"
        );


        -- Legal START.
        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "legal START"
        );

        assert run_enable = '1'
            report "START failed to enter RUN"
            severity error;

        assert production_enable = '1'
            report "START failed to enable production"
            severity error;

        axi_read_check(
            STATUS_ADDR,
            STATUS_RUN,
            AXI_OKAY,
            "RUN STATUS"
        );


        -- Parameter writes forbidden while RUN.
        axi_write_check(
            CH0_BIAS_ADDR,
            x"00000005",
            "1111",
            AXI_SLVERR,
            "parameter write while RUN"
        );

        assert bias_out(0) = x"FFFFFF"
            report "BUSY parameter write mutated storage"
            severity error;

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000010",
            AXI_OKAY,
            "BUSY_PARAMETER_WRITE"
        );


        -- Software clear forbidden outside IDLE.
        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000010",
            "1111",
            AXI_SLVERR,
            "ERROR_FLAGS clear while RUN"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000030",
            AXI_OKAY,
            "BAD_COMMAND_STATE while RUN"
        );


        -- ABORT.
        axi_write_check(
            COMMAND_ADDR,
            x"00000004",
            "1111",
            AXI_OKAY,
            "ABORT"
        );

        assert run_enable = '0'
            report "ABORT left RUN enabled"
            severity error;

        assert production_enable = '0'
            report "ABORT left production enabled"
            severity error;

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000130",
            AXI_OKAY,
            "ERROR_FLAGS after ABORT"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_FAULT,
            AXI_OKAY,
            "FAULT STATUS after ABORT"
        );


        -- RESET recovers and retains parameters/admission.
        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET from FAULT"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "ERROR_FLAGS after RESET"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "STATUS after RESET"
        );

        axi_read_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFF",
            AXI_OKAY,
            "bias retained over RESET"
        );

        axi_read_check(
            CH0_COEFF0_ADDR,
            x"04030201",
            AXI_OKAY,
            "coeff retained over RESET"
        );

        axi_read_check(
            CH0_CTRL_ADDR,
            x"00000103",
            AXI_OKAY,
            "control retained over RESET"
        );


        report "--- CVH1 category 5 PASS ---";


        -- ====================================================================
        -- CATEGORY 6
        -- FINAL COMPREHENSIVE CONTROLLER REGRESSION
        -- ====================================================================

        report "--- CVH1 category 6: comprehensive final regression ---";


        -- ====================================================================
        -- 6A. SUCCESSFUL FRAME
        -- ====================================================================

        report "--- 6A: successful frame + counters + DONE ---";


        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "6A START"
        );


        -- ------------------------------------------------------------
        -- Exact input accepted bytes:
        --
        -- 144 * 8 + 4 = 1156
        -- ------------------------------------------------------------

        input_accept_beats(
            144,
            8
        );

        input_accept_beats(
            1,
            4
        );


        -- Exact consumed pixels/bytes.
        input_consumed_cycles(
            1156
        );


        -- Exactly 32*32 output vectors accepted by serializer.
        core_accept_cycles(
            1024
        );


        -- CORE_COMPLETE must now be sticky, but DONE must NOT be set.
        axi_read_check(
            STATUS_ADDR,
            STATUS_CORE_COMPLETE,
            AXI_OKAY,
            "CORE_COMPLETE before output drain"
        );


        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "successful INPUT_ACCEPT_BYTES"
        );

        axi_read_check(
            INPUT_CONSUMED_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "successful INPUT_CONSUMED_BYTES"
        );

        axi_read_check(
            CORE_ACCEPT_PIXELS_ADDR,
            x"00000400",
            AXI_OKAY,
            "successful CORE_ACCEPT_PIXELS"
        );


        -- ------------------------------------------------------------
        -- Output:
        --
        -- 4095 full beats without TLAST = 32760 bytes.
        -- Final beat provides remaining 8 bytes + TLAST.
        -- ------------------------------------------------------------

        output_accept_beats(
            4095,
            8,
            false
        );


        -- Still no successful completion before final external TLAST.
        axi_read_check(
            STATUS_ADDR,
            STATUS_CORE_COMPLETE,
            AXI_OKAY,
            "no DONE before final output TLAST"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00007FF8",
            AXI_OKAY,
            "output count before final beat"
        );


        -- Simulate final output beat being present but stalled.
        output_tvalid <= '1';

        wait until rising_edge(S_AXI_ACLK);

        axi_read_check(
            STATUS_ADDR,
            STATUS_CORE_COMPLETE,
            AXI_OKAY,
            "stalled final output must not complete"
        );


        -- Final external handshake.
        output_accept_beats(
            1,
            8,
            true
        );

        output_tvalid <= '0';


        -- The accepted output event and its TLAST completion check cross two
        -- controller timing-isolation registers.  Let both registered stages
        -- retire before observing the architectural DONE/IDLE state.
        wait until rising_edge(S_AXI_ACLK);
        wait until rising_edge(S_AXI_ACLK);
        wait for 1 ns;


        -- Success must now be visible.
        axi_read_check(
            STATUS_ADDR,
            STATUS_SUCCESS,
            AXI_OKAY,
            "successful final STATUS"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "successful ERROR_FLAGS"
        );

        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "final INPUT_ACCEPT_BYTES"
        );

        axi_read_check(
            INPUT_CONSUMED_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "final INPUT_CONSUMED_BYTES"
        );

        axi_read_check(
            CORE_ACCEPT_PIXELS_ADDR,
            x"00000400",
            AXI_OKAY,
            "final CORE_ACCEPT_PIXELS"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00008000",
            AXI_OKAY,
            "final OUTPUT_ACCEPT_BYTES"
        );


        -- ====================================================================
        -- 6B. DONE + EVENT_CLEAR semantics
        -- ====================================================================

        report "--- 6B: DONE + EVENT_CLEAR semantics ---";


        -- Zero write is admitted no-op.
        axi_write_check(
            EVENT_CLEAR_ADDR,
            x"00000000",
            "1111",
            AXI_OKAY,
            "EVENT_CLEAR zero no-op"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_SUCCESS,
            AXI_OKAY,
            "DONE retained after EVENT_CLEAR zero"
        );


        -- Reserved clear bit -> BAD_VALUE; DONE stays set.
        axi_write_check(
            EVENT_CLEAR_ADDR,
            x"00000002",
            "1111",
            AXI_SLVERR,
            "invalid EVENT_CLEAR mask"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            AXI_OKAY,
            "EVENT_CLEAR BAD_VALUE"
        );

        axi_read_check(
            STATUS_ADDR,
            x"000001BD",
            AXI_OKAY,
            "DONE retained after invalid EVENT_CLEAR"
        );


        -- Clear BAD_VALUE.
        axi_write_check(
            ERROR_FLAGS_ADDR,
            x"00000008",
            "1111",
            AXI_OKAY,
            "clear EVENT_CLEAR BAD_VALUE"
        );


        -- Valid bit0 clears DONE only.
        axi_write_check(
            EVENT_CLEAR_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "clear DONE"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_SUCCESS_NO_DONE,
            AXI_OKAY,
            "STATUS after DONE clear"
        );


        -- CORE_COMPLETE, OUTPUT_DRAINED and counters remain.
        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000484",
            AXI_OKAY,
            "counter retained after DONE clear"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00008000",
            AXI_OKAY,
            "output counter retained after DONE clear"
        );


        -- ====================================================================
        -- 6C. REPEATED START + INPUT FRAME FAULT
        -- ====================================================================

        report "--- 6C: repeated START + INPUT_FRAME_ERROR ---";


        -- No RESET between successful frame and new START.
        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "repeated START without RESET"
        );

        assert run_enable = '1'
            report "repeated START did not enter RUN"
            severity error;

        assert production_enable = '1'
            report "repeated START did not enable production"
            severity error;


        -- START must clear frame counters/events.
        axi_read_check(
            STATUS_ADDR,
            STATUS_RUN,
            AXI_OKAY,
            "STATUS after repeated START"
        );

        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "input counter cleared on repeated START"
        );

        axi_read_check(
            CORE_ACCEPT_PIXELS_ADDR,
            x"00000000",
            AXI_OKAY,
            "core counter cleared on repeated START"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "output counter cleared on repeated START"
        );


        -- EVENT_CLEAR outside IDLE is forbidden.
        axi_write_check(
            EVENT_CLEAR_ADDR,
            x"00000001",
            "1111",
            AXI_SLVERR,
            "EVENT_CLEAR while RUN"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000020",
            AXI_OKAY,
            "BAD_COMMAND_STATE from EVENT_CLEAR while RUN"
        );


        -- Count a little real traffic before fault.
        input_accept_beats(
            1,
            8
        );

        input_consumed_cycles(
            1
        );


        -- Frame error must force FAULT.
        pulse_input_frame_error;


        assert run_enable = '0'
            report "INPUT_FRAME_ERROR failed to leave RUN"
            severity error;

        assert production_enable = '0'
            report "INPUT_FRAME_ERROR failed to disable production"
            severity error;


        -- Existing BAD_COMMAND_STATE + INPUT_FRAME_ERROR.
        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000060",
            AXI_OKAY,
            "ERROR_FLAGS after INPUT_FRAME_ERROR"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_FAULT,
            AXI_OKAY,
            "FAULT after INPUT_FRAME_ERROR"
        );


        -- Counters retain accepted work.
        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000008",
            AXI_OKAY,
            "input counter retained in FAULT"
        );

        axi_read_check(
            INPUT_CONSUMED_BYTES_ADDR,
            x"00000001",
            AXI_OKAY,
            "consumed counter retained in FAULT"
        );

        axi_read_check(
            CORE_ACCEPT_PIXELS_ADDR,
            x"00000000",
            AXI_OKAY,
            "core counter retained in FAULT"
        );

        axi_read_check(
            OUTPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "output counter retained in FAULT"
        );


        -- RESET clears fault/event/counters but retains parameters.
        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET after INPUT_FRAME_ERROR"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "STATUS after frame-error RESET"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "errors cleared after frame-error RESET"
        );

        axi_read_check(
            INPUT_ACCEPT_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "input counter cleared by RESET"
        );

        axi_read_check(
            INPUT_CONSUMED_BYTES_ADDR,
            x"00000000",
            AXI_OKAY,
            "consumed counter cleared by RESET"
        );


        -- ====================================================================
        -- 6D. INTERNAL_ERROR
        -- ====================================================================

        report "--- 6D: INTERNAL_ERROR fault path ---";


        axi_write_check(
            COMMAND_ADDR,
            x"00000001",
            "1111",
            AXI_OKAY,
            "START before INTERNAL_ERROR"
        );


        pulse_internal_error;


        assert run_enable = '0'
            report "INTERNAL_ERROR failed to leave RUN"
            severity error;

        assert production_enable = '0'
            report "INTERNAL_ERROR failed to disable production"
            severity error;


        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000080",
            AXI_OKAY,
            "INTERNAL_ERROR flag"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_FAULT,
            AXI_OKAY,
            "STATUS after INTERNAL_ERROR"
        );


        axi_write_check(
            COMMAND_ADDR,
            x"00000002",
            "1111",
            AXI_OKAY,
            "RESET after INTERNAL_ERROR"
        );

        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "clean STATUS after internal-error RESET"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "clean errors after internal-error RESET"
        );


        -- ====================================================================
        -- 6E. AXI AW-BEFORE-W + READ WHILE WRITE HALF PENDING
        -- ====================================================================

        report "--- 6E: AXI AW-before-W independence ---";


        -- Current CH0 bias is still -1.
        send_aw_only(
            CH0_BIAS_ADDR
        );


        -- Address slot must now be occupied, but W channel remains available.
        for i in 1 to 3 loop
            wait until rising_edge(S_AXI_ACLK);
        end loop;

        wait until falling_edge(S_AXI_ACLK);


        assert S_AXI_AWREADY = '0'
            report "AW staging accepted second address while pending"
            severity error;

        assert S_AXI_WREADY = '1'
            report "W channel blocked while only AW was staged"
            severity error;


        -- Reads must remain available while AW waits for W.
        axi_read_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFF",
            AXI_OKAY,
            "read while AW pending"
        );


        send_w_only(
            x"00000011",
            "1111"
        );

        expect_b_response(
            AXI_OKAY,
            3,
            "AW-before-W response"
        );


        axi_read_check(
            CH0_BIAS_ADDR,
            x"00000011",
            AXI_OKAY,
            "AW-before-W writeback"
        );


        -- ====================================================================
        -- 6F. AXI W-BEFORE-AW + READ WHILE WRITE HALF PENDING
        -- ====================================================================

        report "--- 6F: AXI W-before-AW independence ---";


        send_w_only(
            x"FFFFFFFE",
            "1111"
        );


        for i in 1 to 3 loop
            wait until rising_edge(S_AXI_ACLK);
        end loop;

        wait until falling_edge(S_AXI_ACLK);


        assert S_AXI_WREADY = '0'
            report "W staging accepted second data beat while pending"
            severity error;

        assert S_AXI_AWREADY = '1'
            report "AW channel blocked while only W was staged"
            severity error;


        -- Read channel must remain independent.
        axi_read_check(
            MAGIC_ADDR,
            x"43564831",
            AXI_OKAY,
            "read while W pending"
        );


        send_aw_only(
            CH0_BIAS_ADDR
        );

        expect_b_response(
            AXI_OKAY,
            3,
            "W-before-AW response"
        );


        axi_read_check(
            CH0_BIAS_ADDR,
            x"FFFFFFFE",
            AXI_OKAY,
            "W-before-AW writeback"
        );


        -- ====================================================================
        -- 6G. SAME-EDGE READ + WRITE TO SAME WORD
        -- ====================================================================

        report "--- 6G: same-edge read/write snapshot semantics ---";


        -- Old bias = -2.
        -- Same-edge admitted write changes it to +0x123.
        --
        -- The simultaneous read MUST return -2.
        same_edge_rw_check(
            CH0_BIAS_ADDR,
            x"00000123",
            x"FFFFFFFE",
            "same-edge bias read/write"
        );


        -- A later read sees the new value.
        axi_read_check(
            CH0_BIAS_ADDR,
            x"00000123",
            AXI_OKAY,
            "post-write bias readback"
        );


        -- PARAM_COMPLETE must survive ordinary reprogramming.
        axi_read_check(
            STATUS_ADDR,
            STATUS_PARAM,
            AXI_OKAY,
            "final controller STATUS"
        );

        axi_read_check(
            ERROR_FLAGS_ADDR,
            x"00000000",
            AXI_OKAY,
            "final controller ERROR_FLAGS"
        );


        report "--- CVH1 category 6 PASS: comprehensive final regression ---";
        report "============================================================";
        report " AXI_LITE_CTRL COMPLETE UNIT REGRESSION PASS ";
        report "============================================================";


        finish;
        wait;

    end process;

end architecture;
