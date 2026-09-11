library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity axi_lite_ctrl is
    generic (
        C_S_AXI_DATA_WIDTH : integer := 32;
        C_S_AXI_ADDR_WIDTH : integer := 32;

        C_K : integer := CFG_K;
        C_N : integer := CFG_N;

        C_LOGICAL_IMAGE_WIDTH  : integer := CFG_UNPADDED_WIDTH;
        C_LOGICAL_IMAGE_HEIGHT : integer := CFG_UNPADDED_HEIGHT;

        -- Frozen release identifier for this M4 N3/K8/W32 build.
        -- hardware.json must contain the identical 128-bit value.
        C_BUILD_ID : std_logic_vector(127 downto 0) :=
            x"4D344E334B385733322D323630393131";

        C_DMA_LENGTH_WIDTH : integer := 22
    );
    port (
        -- ====================================================================
        -- AXI4-Lite slave
        -- ====================================================================
        S_AXI_ACLK    : in std_logic;
        S_AXI_ARESETN : in std_logic;

        S_AXI_AWADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_AWPROT  : in std_logic_vector(2 downto 0);
        S_AXI_AWVALID : in std_logic;
        S_AXI_AWREADY : out std_logic;

        S_AXI_WDATA   : in std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_WSTRB   : in std_logic_vector((C_S_AXI_DATA_WIDTH/8)-1 downto 0);
        S_AXI_WVALID  : in std_logic;
        S_AXI_WREADY  : out std_logic;

        S_AXI_BRESP   : out std_logic_vector(1 downto 0);
        S_AXI_BVALID  : out std_logic;
        S_AXI_BREADY  : in std_logic;

        S_AXI_ARADDR  : in std_logic_vector(C_S_AXI_ADDR_WIDTH-1 downto 0);
        S_AXI_ARPROT  : in std_logic_vector(2 downto 0);
        S_AXI_ARVALID : in std_logic;
        S_AXI_ARREADY : out std_logic;

        S_AXI_RDATA   : out std_logic_vector(C_S_AXI_DATA_WIDTH-1 downto 0);
        S_AXI_RRESP   : out std_logic_vector(1 downto 0);
        S_AXI_RVALID  : out std_logic;
        S_AXI_RREADY  : in std_logic;

        -- ====================================================================
        -- Stream/lifecycle observations
        --
        -- These are acceptance-boundary events supplied by the wrapper,
        -- frontend and serializer. They will be wired in the next M4 edits.
        -- ====================================================================

        -- External input beat accepted.
        input_accept_valid : in std_logic;
        input_accept_bytes : in std_logic_vector(3 downto 0);

        -- One valid input byte/pixel handed from frontend to convolution core.
        input_consumed_pulse : in std_logic;

        -- Accepted malformed input beat.
        input_frame_error : in std_logic;

        -- One complete K-channel output-pixel vector accepted by serializer.
        core_accept_pulse : in std_logic;

        -- External output beat accepted.
        output_accept_valid : in std_logic;
        output_accept_bytes : in std_logic_vector(3 downto 0);
        output_accept_last  : in std_logic;

        -- Serializer/external-output observability for QUIESCENT.
        output_fifo_empty : in std_logic;
        output_tvalid     : in std_logic;

        -- Catch-all datapath/stream invariant failure.
        internal_error_in : in std_logic;

        -- ====================================================================
        -- Lifecycle control outputs
        -- ====================================================================

        -- One-cycle pulse when START is admitted.
        start_pulse : out std_logic;

        -- One-cycle pulse when local RESET is admitted.
        local_reset_pulse : out std_logic;

        -- RUN-state gates.
        run_enable        : out std_logic;
        production_enable : out std_logic;

        -- ====================================================================
        -- Parameters to datapath
        -- ====================================================================
        coeffs_out :
            out coeff_array_t(0 to C_K * C_N * C_N - 1);

        bias_out :
            out bias_array_t(0 to C_K - 1);

        shift_out :
            out shift_array_t(0 to C_K - 1);

        relu_en_out :
            out std_logic_vector(0 to C_K - 1)
    );
end entity axi_lite_ctrl;


architecture rtl of axi_lite_ctrl is

    -- ========================================================================
    -- Constants / derived configuration
    -- ========================================================================

    constant C_AXI_OKAY   : std_logic_vector(1 downto 0) := "00";
    constant C_AXI_SLVERR : std_logic_vector(1 downto 0) := "10";

    constant C_COEFFS_PER_WORD : positive :=
        32 / CFG_WEIGHT_WIDTH;

    constant C_COEFF_WORDS : positive :=
        (C_N * C_N + C_COEFFS_PER_WORD - 1)
        / C_COEFFS_PER_WORD;

    constant C_BIAS_WORD    : natural := 62;
    constant C_CONTROL_WORD : natural := 63;

    constant C_PARAMS_PER_CHANNEL : positive :=
        C_COEFF_WORDS + 2;

    constant C_PARAMETER_COUNT : positive :=
        C_K * C_PARAMS_PER_CHANNEL;

    constant C_SUM_WIDTH : natural :=
        CFG_PIXEL_WIDTH
        + CFG_WEIGHT_WIDTH
        + clog2(C_N * C_N)
        + 1;

    constant C_ACC_WIDTH : natural :=
        max_int(C_SUM_WIDTH, CFG_BIAS_WIDTH) + 1;

    constant C_EXPECTED_INPUT_BYTES : natural :=
        (C_LOGICAL_IMAGE_WIDTH + C_N - 1)
        * (C_LOGICAL_IMAGE_HEIGHT + C_N - 1);

    constant C_EXPECTED_CORE_PIXELS : natural :=
        C_LOGICAL_IMAGE_WIDTH
        * C_LOGICAL_IMAGE_HEIGHT;

    constant C_EXPECTED_OUTPUT_BYTES : natural :=
        2
        * C_LOGICAL_IMAGE_WIDTH
        * C_LOGICAL_IMAGE_HEIGHT
        * C_K;

    constant C_DMA_MAX_BYTES : natural := 4194303;

    -- ========================================================================
    -- CVH1 global map
    -- ========================================================================

    constant C_MAGIC_ADDR :
        std_logic_vector(31 downto 0) := x"00004100";

    constant C_ABI_VERSION_ADDR :
        std_logic_vector(31 downto 0) := x"00004104";

    constant C_CAPABILITIES_ADDR :
        std_logic_vector(31 downto 0) := x"00004108";

    constant C_STATUS_ADDR :
        std_logic_vector(31 downto 0) := x"0000410C";

    constant C_COMMAND_ADDR :
        std_logic_vector(31 downto 0) := x"00004110";

    constant C_EVENT_CLEAR_ADDR :
        std_logic_vector(31 downto 0) := x"00004114";

    constant C_ERROR_FLAGS_ADDR :
        std_logic_vector(31 downto 0) := x"00004118";

    constant C_IMAGE_W_ADDR :
        std_logic_vector(31 downto 0) := x"00004120";

    constant C_IMAGE_H_ADDR :
        std_logic_vector(31 downto 0) := x"00004124";

    constant C_KERNEL_N_ADDR :
        std_logic_vector(31 downto 0) := x"00004128";

    constant C_CHANNEL_K_ADDR :
        std_logic_vector(31 downto 0) := x"0000412C";

    constant C_WIDTHS_0_ADDR :
        std_logic_vector(31 downto 0) := x"00004130";

    constant C_WIDTHS_1_ADDR :
        std_logic_vector(31 downto 0) := x"00004134";

    constant C_EXPECTED_INPUT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004138";

    constant C_EXPECTED_OUTPUT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"0000413C";

    constant C_INPUT_ACCEPT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004140";

    constant C_INPUT_CONSUMED_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"00004144";

    constant C_CORE_ACCEPT_PIXELS_ADDR :
        std_logic_vector(31 downto 0) := x"00004148";

    constant C_OUTPUT_ACCEPT_BYTES_ADDR :
        std_logic_vector(31 downto 0) := x"0000414C";

    constant C_BUILD_ID_0_ADDR :
        std_logic_vector(31 downto 0) := x"00004150";

    constant C_BUILD_ID_1_ADDR :
        std_logic_vector(31 downto 0) := x"00004154";

    constant C_BUILD_ID_2_ADDR :
        std_logic_vector(31 downto 0) := x"00004158";

    constant C_BUILD_ID_3_ADDR :
        std_logic_vector(31 downto 0) := x"0000415C";

    constant C_DMA_LENGTH_WIDTH_ADDR :
        std_logic_vector(31 downto 0) := x"00004160";

    -- ========================================================================
    -- Error bits
    -- ========================================================================

    constant C_ERR_BAD_ADDRESS          : natural := 0;
    constant C_ERR_BAD_ACCESS           : natural := 1;
    constant C_ERR_BAD_STROBE           : natural := 2;
    constant C_ERR_BAD_VALUE            : natural := 3;
    constant C_ERR_BUSY_PARAMETER_WRITE : natural := 4;
    constant C_ERR_BAD_COMMAND_STATE    : natural := 5;
    constant C_ERR_INPUT_FRAME          : natural := 6;
    constant C_ERR_INTERNAL             : natural := 7;
    constant C_ERR_ABORTED              : natural := 8;

    -- ========================================================================
    -- Lifecycle state
    -- ========================================================================

    type lifecycle_state_t is (
        STATE_IDLE,
        STATE_RUN,
        STATE_FAULT
    );

    signal lifecycle_state : lifecycle_state_t;

    -- ========================================================================
    -- Helper functions
    -- ========================================================================

    function normalize_addr(
        value : std_logic_vector
    ) return std_logic_vector is
        variable result : std_logic_vector(31 downto 0);
    begin
        result := std_logic_vector(
            resize(unsigned(value), 32)
        );
        return result;
    end function normalize_addr;


    function is_aligned(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        return addr(1 downto 0) = "00";
    end function is_aligned;


    function channel_index(
        addr : std_logic_vector(31 downto 0)
    ) return natural is
    begin
        return to_integer(
            unsigned(addr(13 downto 8))
        );
    end function channel_index;


    function word_index(
        addr : std_logic_vector(31 downto 0)
    ) return natural is
    begin
        return to_integer(
            unsigned(addr(7 downto 2))
        );
    end function word_index;


    function is_parameter_addr(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
        variable ch : natural;
        variable wd : natural;
    begin
        if unsigned(addr) >= to_unsigned(16#4000#, 32) then
            return false;
        end if;

        ch := channel_index(addr);
        wd := word_index(addr);

        if ch >= C_K then
            return false;
        end if;

        return
            (wd < C_COEFF_WORDS)
            or
            (wd = C_BIAS_WORD)
            or
            (wd = C_CONTROL_WORD);
    end function is_parameter_addr;


    function is_known_global(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        case addr is
            when C_MAGIC_ADDR
               | C_ABI_VERSION_ADDR
               | C_CAPABILITIES_ADDR
               | C_STATUS_ADDR
               | C_COMMAND_ADDR
               | C_EVENT_CLEAR_ADDR
               | C_ERROR_FLAGS_ADDR
               | C_IMAGE_W_ADDR
               | C_IMAGE_H_ADDR
               | C_KERNEL_N_ADDR
               | C_CHANNEL_K_ADDR
               | C_WIDTHS_0_ADDR
               | C_WIDTHS_1_ADDR
               | C_EXPECTED_INPUT_BYTES_ADDR
               | C_EXPECTED_OUTPUT_BYTES_ADDR
               | C_INPUT_ACCEPT_BYTES_ADDR
               | C_INPUT_CONSUMED_BYTES_ADDR
               | C_CORE_ACCEPT_PIXELS_ADDR
               | C_OUTPUT_ACCEPT_BYTES_ADDR
               | C_BUILD_ID_0_ADDR
               | C_BUILD_ID_1_ADDR
               | C_BUILD_ID_2_ADDR
               | C_BUILD_ID_3_ADDR
               | C_DMA_LENGTH_WIDTH_ADDR =>
                return true;

            when others =>
                return false;
        end case;
    end function is_known_global;


    function is_ro_global(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        if not is_known_global(addr) then
            return false;
        end if;

        return
            addr /= C_COMMAND_ADDR
            and
            addr /= C_EVENT_CLEAR_ADDR
            and
            addr /= C_ERROR_FLAGS_ADDR;
    end function is_ro_global;


    function is_writable_global(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        return
            addr = C_COMMAND_ADDR
            or
            addr = C_EVENT_CLEAR_ADDR
            or
            addr = C_ERROR_FLAGS_ADDR;
    end function is_writable_global;


    function is_implemented_addr(
        addr : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        return
            is_parameter_addr(addr)
            or
            is_known_global(addr);
    end function is_implemented_addr;


    function canonical_bias(
        data : std_logic_vector(31 downto 0)
    ) return boolean is
    begin
        if CFG_BIAS_WIDTH = 32 then
            return true;
        end if;

        for bit_index in 31 downto CFG_BIAS_WIDTH loop
            if data(bit_index) /=
                    data(CFG_BIAS_WIDTH - 1) then
                return false;
            end if;
        end loop;

        return true;
    end function canonical_bias;


    function final_coeff_mask
        return std_logic_vector is
        variable mask :
            std_logic_vector(31 downto 0) :=
                (others => '0');
    begin
        for lane in 0 to C_COEFFS_PER_WORD - 1 loop
            if
                (C_COEFF_WORDS - 1)
                * C_COEFFS_PER_WORD
                + lane
                < C_N * C_N
            then
                mask(
                    (lane + 1) * CFG_WEIGHT_WIDTH - 1
                    downto
                    lane * CFG_WEIGHT_WIDTH
                ) := (others => '1');
            end if;
        end loop;

        return mask;
    end function final_coeff_mask;


    constant C_FINAL_COEFF_MASK :
        std_logic_vector(31 downto 0) :=
            final_coeff_mask;


    function valid_parameter_data(
        addr : std_logic_vector(31 downto 0);
        data : std_logic_vector(31 downto 0)
    ) return boolean is
        variable wd :
            natural;

        variable control_mask :
            std_logic_vector(31 downto 0) :=
                (others => '0');
    begin
        wd := word_index(addr);

        if wd < C_COEFF_WORDS then

            if wd = C_COEFF_WORDS - 1 then
                return
                    (data and not C_FINAL_COEFF_MASK)
                    = x"00000000";
            end if;

            return true;

        elsif wd = C_BIAS_WORD then

            return canonical_bias(data);

        elsif wd = C_CONTROL_WORD then

            control_mask(
                CFG_SHIFT_WIDTH - 1 downto 0
            ) := (others => '1');

            control_mask(8) := '1';

            return
                (data and not control_mask)
                = x"00000000";

        end if;

        return false;
    end function valid_parameter_data;


    function parameter_admission_index(
        addr : std_logic_vector(31 downto 0)
    ) return natural is
        variable ch :
            natural;

        variable wd :
            natural;
    begin
        ch := channel_index(addr);
        wd := word_index(addr);

        if wd < C_COEFF_WORDS then
            return
                ch * C_PARAMS_PER_CHANNEL
                + wd;

        elsif wd = C_BIAS_WORD then
            return
                ch * C_PARAMS_PER_CHANNEL
                + C_COEFF_WORDS;

        else
            return
                ch * C_PARAMS_PER_CHANNEL
                + C_COEFF_WORDS
                + 1;
        end if;
    end function parameter_admission_index;


    function all_ones(
        value : std_logic_vector
    ) return boolean is
    begin
        for i in value'range loop
            if value(i) /= '1' then
                return false;
            end if;
        end loop;

        return true;
    end function all_ones;


    procedure add_u32_saturating(
        variable value    : inout unsigned(31 downto 0);
        constant delta    : in natural;
        variable overflow : inout boolean
    ) is
        variable extended :
            unsigned(32 downto 0);
    begin
        extended :=
            ('0' & value)
            + to_unsigned(delta, 33);

        if extended(32) = '1' then
            value := (others => '1');
            overflow := true;
        else
            value := extended(31 downto 0);
        end if;
    end procedure add_u32_saturating;

    -- ========================================================================
    -- AXI registers / staging
    -- ========================================================================

    signal axi_awready :
        std_logic;

    signal axi_wready :
        std_logic;

    signal axi_bvalid :
        std_logic;

    signal axi_bresp :
        std_logic_vector(1 downto 0);

    signal axi_arready :
        std_logic;

    signal axi_rvalid :
        std_logic;

    signal axi_rresp :
        std_logic_vector(1 downto 0);

    signal write_addr_pending :
        std_logic;

    signal write_data_pending :
        std_logic;

    signal write_addr_reg :
        std_logic_vector(31 downto 0);

    signal write_data_reg :
        std_logic_vector(31 downto 0);

    signal write_strb_reg :
        std_logic_vector(3 downto 0);

    -- ========================================================================
    -- Register-file interface
    -- ========================================================================

    signal rf_wr_en :
        std_logic;

    signal rf_wr_addr :
        std_logic_vector(31 downto 0);

    signal rf_wr_data :
        std_logic_vector(31 downto 0);


    signal rf_rd_en :
        std_logic;

    signal rf_rd_addr :
        std_logic_vector(31 downto 0);

    signal rf_rd_data :
        std_logic_vector(31 downto 0);

    -- ========================================================================
    -- Lifecycle / status storage
    -- ========================================================================

    signal parameter_written :
        std_logic_vector(
            C_PARAMETER_COUNT - 1 downto 0
        );

    signal param_complete :
        std_logic;

    signal error_flags :
        std_logic_vector(31 downto 0);

    signal core_complete :
        std_logic;

    signal output_drained :
        std_logic;

    signal done_sticky :
        std_logic;

    signal input_accept_count :
        unsigned(31 downto 0);

    signal input_consumed_count :
        unsigned(31 downto 0);

    signal core_accept_count :
        unsigned(31 downto 0);

    signal output_accept_count :
        unsigned(31 downto 0);

    signal quiescent :
        std_logic;

    signal start_pulse_reg :
        std_logic;

    signal local_reset_pulse_reg :
        std_logic;

    -- ========================================================================
    -- Read combinational decode
    -- ========================================================================

    signal read_data_comb :
        std_logic_vector(31 downto 0);

    signal read_resp_comb :
        std_logic_vector(1 downto 0);

    signal read_bad_address_comb :
        std_logic;

    signal read_bad_address_accept :
        std_logic;

    signal status_word :
        std_logic_vector(31 downto 0);

begin

    -- ========================================================================
    -- Elaboration guards
    -- ========================================================================

    assert C_S_AXI_DATA_WIDTH = 32
        report "CVH1 requires 32-bit AXI-Lite data"
        severity failure;

    assert C_S_AXI_ADDR_WIDTH = 32
        report "Current CVH1 wrapper requires 32-bit AXI-Lite address"
        severity failure;

    assert C_K = CFG_K
        report "C_K must match CFG_K"
        severity failure;

    assert C_N = CFG_N
        report "C_N must match CFG_N"
        severity failure;

    assert C_LOGICAL_IMAGE_WIDTH = CFG_UNPADDED_WIDTH
        report "Controller width generic must match config_pkg"
        severity failure;

    assert C_LOGICAL_IMAGE_HEIGHT = CFG_UNPADDED_HEIGHT
        report "Controller height generic must match config_pkg"
        severity failure;

    assert C_N = 3 or C_N = 5
        report "CVH1 implemented kernel family is N=3 or N=5"
        severity failure;

    assert C_DMA_LENGTH_WIDTH = 22
        report "CVH1 new-family DMA length width must be 22"
        severity failure;

    assert C_EXPECTED_INPUT_BYTES <= C_DMA_MAX_BYTES
        report "Input frame exceeds 22-bit DMA transfer limit"
        severity failure;

    assert C_EXPECTED_OUTPUT_BYTES <= C_DMA_MAX_BYTES
        report "Output frame exceeds 22-bit DMA transfer limit"
        severity failure;

    assert C_BUILD_ID /= x"00000000000000000000000000000000"
        report "CVH1 BUILD_ID must be nonzero"
        severity failure;

    -- ========================================================================
    -- AXI outputs
    -- ========================================================================

    S_AXI_AWREADY <= axi_awready;
    S_AXI_WREADY  <= axi_wready;

    S_AXI_BRESP  <= axi_bresp;
    S_AXI_BVALID <= axi_bvalid;

    S_AXI_ARREADY <= axi_arready;

    S_AXI_RRESP  <= axi_rresp;
    S_AXI_RVALID <= axi_rvalid;

    start_pulse       <= start_pulse_reg;
    local_reset_pulse <= local_reset_pulse_reg;

    run_enable <=
        '1'
        when lifecycle_state = STATE_RUN
        else '0';

    production_enable <=
        '1'
        when lifecycle_state = STATE_RUN
        else '0';

    axi_awready <=
        '1'
        when
            S_AXI_ARESETN = '1'
            and axi_bvalid = '0'
            and write_addr_pending = '0'
        else '0';

    axi_wready <=
        '1'
        when
            S_AXI_ARESETN = '1'
            and axi_bvalid = '0'
            and write_data_pending = '0'
        else '0';

    axi_arready <=
        '1'
        when
            S_AXI_ARESETN = '1'
            and axi_rvalid = '0'
        else '0';

    -- ========================================================================
    -- Parameter completion / quiescence
    -- ========================================================================

    param_complete <=
        '1'
        when all_ones(parameter_written)
        else '0';

    quiescent <=
        '1'
        when
            lifecycle_state /= STATE_RUN
            and output_fifo_empty = '1'
            and output_tvalid = '0'
            and production_enable = '0'
        else '0';

    -- ========================================================================
    -- STATUS
    -- ========================================================================

    status_process : process(all)
        variable value :
            std_logic_vector(31 downto 0);
    begin
        value := (others => '0');

        if lifecycle_state = STATE_IDLE then
            value(0) := '1';
        end if;

        if
            lifecycle_state = STATE_RUN
            or lifecycle_state = STATE_FAULT
        then
            value(1) := '1';
        end if;

        value(2) := core_complete;
        value(3) := output_drained;
        value(4) := done_sticky;

        if error_flags /= x"00000000" then
            value(5) := '1';
        end if;

        if lifecycle_state = STATE_FAULT then
            value(6) := '1';
        end if;

        value(7) := param_complete;
        value(8) := quiescent;

        status_word <= value;
    end process status_process;

    -- ========================================================================
    -- Register-file read path
    --
    -- The register-file address is driven directly from the offered ARADDR.
    -- Therefore data sampled on the AR handshake is the pre-write value if a
    -- write to that same word commits on the same clock edge.
    -- ========================================================================

    rf_rd_addr <= normalize_addr(S_AXI_ARADDR);

    rf_rd_en <=
        '1'
        when
            axi_arready = '1'
            and S_AXI_ARVALID = '1'
            and is_aligned(
                normalize_addr(S_AXI_ARADDR)
            )
            and is_parameter_addr(
                normalize_addr(S_AXI_ARADDR)
            )
        else '0';

    read_decode : process(all)
        variable addr :
            std_logic_vector(31 downto 0);

        variable value :
            std_logic_vector(31 downto 0);
    begin
        addr :=
            normalize_addr(S_AXI_ARADDR);

        value := (others => '0');

        read_resp_comb <= C_AXI_OKAY;
        read_bad_address_comb <= '0';

        if
            not is_aligned(addr)
            or not is_implemented_addr(addr)
        then
            read_resp_comb <= C_AXI_SLVERR;
            read_bad_address_comb <= '1';

        elsif is_parameter_addr(addr) then

            value := rf_rd_data;

        else

            case addr is

                when C_MAGIC_ADDR =>
                    value := x"43564831";

                when C_ABI_VERSION_ADDR =>
                    value := x"00010000";

                when C_CAPABILITIES_ADDR =>
                    value := x"000001FF";

                when C_STATUS_ADDR =>
                    value := status_word;

                -- WO/RZ
                when C_COMMAND_ADDR =>
                    value := (others => '0');

                -- WO/RZ
                when C_EVENT_CLEAR_ADDR =>
                    value := (others => '0');

                when C_ERROR_FLAGS_ADDR =>
                    value := error_flags;

                when C_IMAGE_W_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(
                                C_LOGICAL_IMAGE_WIDTH,
                                32
                            )
                        );

                when C_IMAGE_H_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(
                                C_LOGICAL_IMAGE_HEIGHT,
                                32
                            )
                        );

                when C_KERNEL_N_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(C_N, 32)
                        );

                when C_CHANNEL_K_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(C_K, 32)
                        );

                when C_WIDTHS_0_ADDR =>
                    value := (others => '0');

                    value(7 downto 0) :=
                        std_logic_vector(
                            to_unsigned(
                                CFG_PIXEL_WIDTH,
                                8
                            )
                        );

                    value(15 downto 8) :=
                        std_logic_vector(
                            to_unsigned(
                                CFG_WEIGHT_WIDTH,
                                8
                            )
                        );

                    value(23 downto 16) :=
                        std_logic_vector(
                            to_unsigned(
                                CFG_BIAS_WIDTH,
                                8
                            )
                        );

                    value(31 downto 24) :=
                        std_logic_vector(
                            to_unsigned(
                                CFG_OUTPUT_WIDTH,
                                8
                            )
                        );

                when C_WIDTHS_1_ADDR =>
                    value := (others => '0');

                    value(7 downto 0) :=
                        std_logic_vector(
                            to_unsigned(
                                C_SUM_WIDTH,
                                8
                            )
                        );

                    value(15 downto 8) :=
                        std_logic_vector(
                            to_unsigned(
                                C_ACC_WIDTH,
                                8
                            )
                        );

                when C_EXPECTED_INPUT_BYTES_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(
                                C_EXPECTED_INPUT_BYTES,
                                32
                            )
                        );

                when C_EXPECTED_OUTPUT_BYTES_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(
                                C_EXPECTED_OUTPUT_BYTES,
                                32
                            )
                        );

                when C_INPUT_ACCEPT_BYTES_ADDR =>
                    value :=
                        std_logic_vector(
                            input_accept_count
                        );

                when C_INPUT_CONSUMED_BYTES_ADDR =>
                    value :=
                        std_logic_vector(
                            input_consumed_count
                        );

                when C_CORE_ACCEPT_PIXELS_ADDR =>
                    value :=
                        std_logic_vector(
                            core_accept_count
                        );

                when C_OUTPUT_ACCEPT_BYTES_ADDR =>
                    value :=
                        std_logic_vector(
                            output_accept_count
                        );

                when C_BUILD_ID_0_ADDR =>
                    value := C_BUILD_ID(31 downto 0);

                when C_BUILD_ID_1_ADDR =>
                    value := C_BUILD_ID(63 downto 32);

                when C_BUILD_ID_2_ADDR =>
                    value := C_BUILD_ID(95 downto 64);

                when C_BUILD_ID_3_ADDR =>
                    value := C_BUILD_ID(127 downto 96);

                when C_DMA_LENGTH_WIDTH_ADDR =>
                    value :=
                        std_logic_vector(
                            to_unsigned(
                                C_DMA_LENGTH_WIDTH,
                                32
                            )
                        );

                when others =>
                    -- Unreachable after is_implemented_addr().
                    value := (others => '0');

            end case;

        end if;

        read_data_comb <= value;
    end process read_decode;

    read_bad_address_accept <=
        '1'
        when
            axi_arready = '1'
            and S_AXI_ARVALID = '1'
            and read_bad_address_comb = '1'
        else '0';

    -- ========================================================================
    -- AXI read response holding
    -- ========================================================================

    read_response_process : process(S_AXI_ACLK)
    begin
        if rising_edge(S_AXI_ACLK) then

            if S_AXI_ARESETN = '0' then

                axi_rvalid <= '0';
                axi_rresp  <= C_AXI_OKAY;
                S_AXI_RDATA <= (others => '0');

            else

                if axi_rvalid = '1' then

                    if S_AXI_RREADY = '1' then
                        axi_rvalid <= '0';
                    end if;

                elsif
                    axi_arready = '1'
                    and S_AXI_ARVALID = '1'
                then

                    S_AXI_RDATA <= read_data_comb;
                    axi_rresp   <= read_resp_comb;
                    axi_rvalid  <= '1';

                end if;

            end if;
        end if;
    end process read_response_process;

    -- ========================================================================
    -- Main lifecycle / AXI-write process
    -- ========================================================================

    main_process : process(S_AXI_ACLK)

        variable v_addr_pending :
            std_logic;

        variable v_data_pending :
            std_logic;

        variable v_addr :
            std_logic_vector(31 downto 0);

        variable v_data :
            std_logic_vector(31 downto 0);

        variable v_strb :
            std_logic_vector(3 downto 0);

        variable v_state :
            lifecycle_state_t;

        variable v_error_set :
            std_logic_vector(31 downto 0);

        variable v_error_clear :
            std_logic_vector(31 downto 0);

        variable v_parameter_written :
            std_logic_vector(
                C_PARAMETER_COUNT - 1 downto 0
            );

        variable v_input_accept :
            unsigned(31 downto 0);

        variable v_input_consumed :
            unsigned(31 downto 0);

        variable v_core_accept :
            unsigned(31 downto 0);

        variable v_output_accept :
            unsigned(31 downto 0);

        variable v_core_complete :
            std_logic;

        variable v_output_drained :
            std_logic;

        variable v_done :
            std_logic;

        variable v_internal_fault :
            boolean;

        variable v_delta :
            natural;

        variable v_bresp :
            std_logic_vector(1 downto 0);

        variable v_admission_index :
            natural range 0 to C_PARAMETER_COUNT - 1;

        variable v_current_errors :
            std_logic_vector(31 downto 0);

    begin
        if rising_edge(S_AXI_ACLK) then

            if S_AXI_ARESETN = '0' then

                lifecycle_state <= STATE_IDLE;

                error_flags <= (others => '0');

                parameter_written <= (others => '0');

                core_complete  <= '0';
                output_drained <= '0';
                done_sticky    <= '0';

                input_accept_count   <= (others => '0');
                input_consumed_count <= (others => '0');
                core_accept_count    <= (others => '0');
                output_accept_count  <= (others => '0');

                start_pulse_reg       <= '0';
                local_reset_pulse_reg <= '0';

                axi_bvalid <= '0';
                axi_bresp  <= C_AXI_OKAY;

                write_addr_pending <= '0';
                write_data_pending <= '0';

                write_addr_reg <= (others => '0');
                write_data_reg <= (others => '0');
                write_strb_reg <= (others => '0');

                rf_wr_en   <= '0';
                rf_wr_addr <= (others => '0');
                rf_wr_data <= (others => '0');

            else

                -- ============================================================
                -- Defaults / working copies
                -- ============================================================

                start_pulse_reg       <= '0';
                local_reset_pulse_reg <= '0';

                rf_wr_en   <= '0';

                v_addr_pending :=
                    write_addr_pending;

                v_data_pending :=
                    write_data_pending;

                v_addr :=
                    write_addr_reg;

                v_data :=
                    write_data_reg;

                v_strb :=
                    write_strb_reg;

                v_state :=
                    lifecycle_state;

                v_error_set :=
                    (others => '0');

                v_error_clear :=
                    (others => '0');

                v_parameter_written :=
                    parameter_written;

                v_input_accept :=
                    input_accept_count;

                v_input_consumed :=
                    input_consumed_count;

                v_core_accept :=
                    core_accept_count;

                v_output_accept :=
                    output_accept_count;

                v_core_complete :=
                    core_complete;

                v_output_drained :=
                    output_drained;

                v_done :=
                    done_sticky;

                v_internal_fault :=
                    false;

                -- ============================================================
                -- Accepted stream events
                -- ============================================================

                if input_accept_valid = '1' then

                    v_delta :=
                        to_integer(
                            unsigned(input_accept_bytes)
                        );

                    if lifecycle_state = STATE_RUN then

                        if v_delta > 8 then
                            v_internal_fault := true;
                        end if;

                        add_u32_saturating(
                            v_input_accept,
                            v_delta,
                            v_internal_fault
                        );

                        if
                            v_input_accept >
                            to_unsigned(
                                C_EXPECTED_INPUT_BYTES,
                                32
                            )
                        then
                            v_internal_fault := true;
                        end if;

                    else
                        -- Input must be gated outside RUN.
                        v_internal_fault := true;
                    end if;

                end if;


                if input_consumed_pulse = '1' then

                    if lifecycle_state = STATE_RUN then

                        add_u32_saturating(
                            v_input_consumed,
                            1,
                            v_internal_fault
                        );

                        if
                            v_input_consumed >
                            to_unsigned(
                                C_EXPECTED_INPUT_BYTES,
                                32
                            )
                        then
                            v_internal_fault := true;
                        end if;

                    else
                        v_internal_fault := true;
                    end if;

                end if;


                if core_accept_pulse = '1' then

                    if lifecycle_state = STATE_RUN then

                        add_u32_saturating(
                            v_core_accept,
                            1,
                            v_internal_fault
                        );

                        if
                            v_core_accept =
                            to_unsigned(
                                C_EXPECTED_CORE_PIXELS,
                                32
                            )
                        then
                            v_core_complete := '1';

                        elsif
                            v_core_accept >
                            to_unsigned(
                                C_EXPECTED_CORE_PIXELS,
                                32
                            )
                        then
                            v_internal_fault := true;
                        end if;

                    else
                        v_internal_fault := true;
                    end if;

                end if;


                if output_accept_valid = '1' then

                    v_delta :=
                        to_integer(
                            unsigned(output_accept_bytes)
                        );

                    if
                        lifecycle_state = STATE_RUN
                        or lifecycle_state = STATE_FAULT
                    then

                        if v_delta > 8 then
                            v_internal_fault := true;
                        end if;

                        add_u32_saturating(
                            v_output_accept,
                            v_delta,
                            v_internal_fault
                        );

                        if
                            v_output_accept >
                            to_unsigned(
                                C_EXPECTED_OUTPUT_BYTES,
                                32
                            )
                        then
                            v_internal_fault := true;
                        end if;

                    else
                        v_internal_fault := true;
                    end if;

                end if;


                -- Malformed input has its own architectural fault bit.
                if input_frame_error = '1' then

                    if lifecycle_state = STATE_RUN then
                        v_error_set(C_ERR_INPUT_FRAME) := '1';
                        v_state := STATE_FAULT;
                    else
                        v_internal_fault := true;
                    end if;

                end if;


                if internal_error_in = '1' then
                    v_internal_fault := true;
                end if;

                -- ============================================================
                -- Bad read-address event
                -- ============================================================

                if read_bad_address_accept = '1' then
                    v_error_set(C_ERR_BAD_ADDRESS) := '1';
                end if;

                -- ============================================================
                -- Capture independent AW / W channels
                -- ============================================================

                if
                    axi_awready = '1'
                    and S_AXI_AWVALID = '1'
                then

                    v_addr_pending := '1';

                    v_addr :=
                        normalize_addr(S_AXI_AWADDR);

                end if;


                if
                    axi_wready = '1'
                    and S_AXI_WVALID = '1'
                then

                    v_data_pending := '1';
                    v_data := S_AXI_WDATA;
                    v_strb := S_AXI_WSTRB(3 downto 0);

                end if;

                -- ============================================================
                -- Existing B response
                -- ============================================================

                if axi_bvalid = '1' then

                    if S_AXI_BREADY = '1' then
                        axi_bvalid <= '0';
                    end if;

                -- ============================================================
                -- New write commit
                -- ============================================================

                elsif
                    v_addr_pending = '1'
                    and v_data_pending = '1'
                then

                    v_bresp := C_AXI_OKAY;

                    -- Consume exactly one buffered transaction.
                    v_addr_pending := '0';
                    v_data_pending := '0';

                    -- --------------------------------------------------------
                    -- Priority 1: local address validity/alignment
                    -- --------------------------------------------------------

                    if
                        not is_aligned(v_addr)
                        or not is_implemented_addr(v_addr)
                    then

                        v_bresp := C_AXI_SLVERR;
                        v_error_set(C_ERR_BAD_ADDRESS) := '1';

                    -- --------------------------------------------------------
                    -- Priority 2: access type
                    -- --------------------------------------------------------

                    elsif is_ro_global(v_addr) then

                        v_bresp := C_AXI_SLVERR;
                        v_error_set(C_ERR_BAD_ACCESS) := '1';

                    -- --------------------------------------------------------
                    -- All remaining addresses are writable.
                    -- Universal zero-strobe no-op.
                    -- --------------------------------------------------------

                    elsif v_strb = "0000" then

                        null;

                    -- --------------------------------------------------------
                    -- Partial nonzero strobe is always illegal.
                    -- --------------------------------------------------------

                    elsif v_strb /= "1111" then

                        v_bresp := C_AXI_SLVERR;
                        v_error_set(C_ERR_BAD_STROBE) := '1';

                    -- --------------------------------------------------------
                    -- Parameter write
                    -- --------------------------------------------------------

                    elsif is_parameter_addr(v_addr) then

                        if lifecycle_state /= STATE_IDLE then

                            v_bresp := C_AXI_SLVERR;

                            v_error_set(
                                C_ERR_BUSY_PARAMETER_WRITE
                            ) := '1';

                        elsif not valid_parameter_data(
                            v_addr,
                            v_data
                        ) then

                            v_bresp := C_AXI_SLVERR;
                            v_error_set(C_ERR_BAD_VALUE) := '1';

                        else

                            -- Atomic committed parameter write.
                            rf_wr_en   <= '1';
                            rf_wr_addr <= v_addr;
                            rf_wr_data <= v_data;

                            v_admission_index :=
                                parameter_admission_index(
                                    v_addr
                                );

                            v_parameter_written(
                                v_admission_index
                            ) := '1';

                        end if;

                    -- --------------------------------------------------------
                    -- COMMAND
                    -- --------------------------------------------------------

                    elsif v_addr = C_COMMAND_ADDR then

                        if v_data = x"00000001" then
                            -- START

                            v_current_errors :=
                                error_flags
                                or v_error_set;

                            if
                                lifecycle_state /= STATE_IDLE
                                or quiescent /= '1'
                                or param_complete /= '1'
                                or v_current_errors /= x"00000000"
                            then

                                v_bresp := C_AXI_SLVERR;

                                v_error_set(
                                    C_ERR_BAD_COMMAND_STATE
                                ) := '1';

                            else

                                v_state := STATE_RUN;

                                v_input_accept :=
                                    (others => '0');

                                v_input_consumed :=
                                    (others => '0');

                                v_core_accept :=
                                    (others => '0');

                                v_output_accept :=
                                    (others => '0');

                                v_core_complete  := '0';
                                v_output_drained := '0';
                                v_done           := '0';

                                start_pulse_reg <= '1';

                            end if;

                        elsif v_data = x"00000002" then
                            -- RESET

                            if
                                (
                                    lifecycle_state = STATE_IDLE
                                    or
                                    lifecycle_state = STATE_FAULT
                                )
                                and quiescent = '1'
                            then

                                v_state := STATE_IDLE;

                                v_input_accept :=
                                    (others => '0');

                                v_input_consumed :=
                                    (others => '0');

                                v_core_accept :=
                                    (others => '0');

                                v_output_accept :=
                                    (others => '0');

                                v_core_complete  := '0';
                                v_output_drained := '0';
                                v_done           := '0';

                                -- RESET clears every architectural
                                -- error bit but preserves parameter
                                -- storage/admission.
                                v_error_clear :=
                                    (others => '1');

                                local_reset_pulse_reg <= '1';

                            else

                                v_bresp := C_AXI_SLVERR;

                                v_error_set(
                                    C_ERR_BAD_COMMAND_STATE
                                ) := '1';

                            end if;

                        elsif v_data = x"00000004" then
                            -- ABORT
                            --
                            -- Legal in IDLE, RUN and FAULT.
                            -- Already-occurring handshakes above have
                            -- already been counted on this edge.

                            v_state := STATE_FAULT;

                            v_error_set(
                                C_ERR_ABORTED
                            ) := '1';

                        else

                            v_bresp := C_AXI_SLVERR;
                            v_error_set(C_ERR_BAD_VALUE) := '1';

                        end if;

                    -- --------------------------------------------------------
                    -- EVENT_CLEAR
                    -- --------------------------------------------------------

                    elsif v_addr = C_EVENT_CLEAR_ADDR then

                        if lifecycle_state /= STATE_IDLE then

                            v_bresp := C_AXI_SLVERR;

                            v_error_set(
                                C_ERR_BAD_COMMAND_STATE
                            ) := '1';

                        elsif
                            (
                                v_data
                                and x"FFFFFFFE"
                            )
                            /= x"00000000"
                        then

                            v_bresp := C_AXI_SLVERR;
                            v_error_set(C_ERR_BAD_VALUE) := '1';

                        else

                            if v_data(0) = '1' then
                                v_done := '0';
                            end if;

                        end if;

                    -- --------------------------------------------------------
                    -- ERROR_FLAGS RW1C
                    -- --------------------------------------------------------

                    elsif v_addr = C_ERROR_FLAGS_ADDR then

                        if lifecycle_state /= STATE_IDLE then

                            v_bresp := C_AXI_SLVERR;

                            v_error_set(
                                C_ERR_BAD_COMMAND_STATE
                            ) := '1';

                        elsif
                            (
                                v_data
                                and x"FFFFFFC0"
                            )
                            /= x"00000000"
                        then

                            v_bresp := C_AXI_SLVERR;
                            v_error_set(C_ERR_BAD_VALUE) := '1';

                        else

                            v_error_clear(5 downto 0) :=
                                v_data(5 downto 0);

                        end if;

                    else

                        -- Should be unreachable because access validity
                        -- was checked before this point.
                        v_bresp := C_AXI_SLVERR;
                        v_error_set(C_ERR_BAD_ADDRESS) := '1';

                    end if;

                    axi_bresp  <= v_bresp;
                    axi_bvalid <= '1';

                end if;

                -- ============================================================
                -- Controller-detected internal invariant failure
                -- ============================================================

                if v_internal_fault then

                    v_error_set(C_ERR_INTERNAL) := '1';
                    v_state := STATE_FAULT;

                end if;

                -- ============================================================
                -- Successful external frame completion
                --
                -- ABORT/frame/internal faults above changed v_state to FAULT,
                -- so FAULT automatically wins over simultaneous success.
                -- ============================================================

                if
                    lifecycle_state = STATE_RUN
                    and output_accept_valid = '1'
                then

                    if output_accept_last = '1' then

                        if v_state = STATE_RUN then

                            if
                                v_input_accept =
                                to_unsigned(
                                    C_EXPECTED_INPUT_BYTES,
                                    32
                                )
                                and
                                v_input_consumed =
                                to_unsigned(
                                    C_EXPECTED_INPUT_BYTES,
                                    32
                                )
                                and
                                v_core_accept =
                                to_unsigned(
                                    C_EXPECTED_CORE_PIXELS,
                                    32
                                )
                                and
                                v_output_accept =
                                to_unsigned(
                                    C_EXPECTED_OUTPUT_BYTES,
                                    32
                                )
                                and
                                v_core_complete = '1'
                            then

                                v_output_drained := '1';
                                v_done := '1';
                                v_state := STATE_IDLE;

                            else

                                v_error_set(
                                    C_ERR_INTERNAL
                                ) := '1';

                                v_state := STATE_FAULT;

                            end if;

                        end if;

                    elsif
                        v_state = STATE_RUN
                        and
                        v_output_accept =
                        to_unsigned(
                            C_EXPECTED_OUTPUT_BYTES,
                            32
                        )
                    then

                        -- Expected byte quota reached without TLAST.
                        v_error_set(C_ERR_INTERNAL) := '1';
                        v_state := STATE_FAULT;

                    end if;

                end if;

                -- ============================================================
                -- Set-dominant sticky error update
                -- ============================================================

                error_flags <=
                    (
                        error_flags
                        and not v_error_clear
                    )
                    or v_error_set;

                -- ============================================================
                -- Commit working state
                -- ============================================================

                lifecycle_state <= v_state;

                parameter_written <=
                    v_parameter_written;

                input_accept_count <=
                    v_input_accept;

                input_consumed_count <=
                    v_input_consumed;

                core_accept_count <=
                    v_core_accept;

                output_accept_count <=
                    v_output_accept;

                core_complete <=
                    v_core_complete;

                output_drained <=
                    v_output_drained;

                done_sticky <=
                    v_done;

                write_addr_pending <=
                    v_addr_pending;

                write_data_pending <=
                    v_data_pending;

                write_addr_reg <=
                    v_addr;

                write_data_reg <=
                    v_data;

                write_strb_reg <=
                    v_strb;

            end if;

        end if;
    end process main_process;

    -- ========================================================================
    -- Parameter register file
    -- ========================================================================

    regfile_inst :
        entity work.coeff_bias_shift_regfile
        generic map (
            C_K => C_K,
            C_N => C_N
        )
        port map (
            clk    => S_AXI_ACLK,
            resetn => S_AXI_ARESETN,

            wr_en   => rf_wr_en,
            wr_addr => rf_wr_addr(13 downto 2),
            wr_data => rf_wr_data,

            rd_en   => rf_rd_en,
            rd_addr => rf_rd_addr(13 downto 2),
            rd_data => rf_rd_data,

            coeffs_out  => coeffs_out,
            bias_out    => bias_out,
            shift_out   => shift_out,
            relu_en_out => relu_en_out
        );

end architecture rtl;