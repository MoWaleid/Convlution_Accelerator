-- ============================================================================
-- Trained K=8 end-to-end convolution regression
--
-- Loads the exported trained configuration, kernels, input image, and expected
-- outputs directly from golden_model/data.  This is intentionally separate
-- from the independent K=4 custom-filter regression in tb_conv_top.vhd.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;
use IEEE.STD_LOGIC_TEXTIO.ALL;

library STD;
use STD.TEXTIO.ALL;
use STD.ENV.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity tb_conv_top_trained_k8 is
    generic (
        G_DATA_ROOT : string :=
            "D:/MyProjects/Convlution_Accelerator/golden_model/data"
    );
end entity tb_conv_top_trained_k8;

architecture sim of tb_conv_top_trained_k8 is
    constant CLK_PERIOD : time := 10 ns;

    constant C_CHANNEL_STRIDE : integer := 16#100#;
    constant C_BIAS_OFFSET    : integer := 16#F8#;
    constant C_CONTROL_OFFSET : integer := 16#FC#;
    constant C_COEFF_COUNT    : integer := CFG_N * CFG_N;
    constant C_COEFF_WORDS    : integer := (C_COEFF_COUNT + 3) / 4;
    constant C_PADDING        : integer := CFG_N / 2;
    constant C_INPUT_PIXELS   : integer :=
        CFG_UNPADDED_WIDTH * CFG_UNPADDED_HEIGHT;
    constant C_OUTPUT_POSITIONS : integer := C_INPUT_PIXELS;
    constant C_TOTAL_COMPARISONS : integer :=
        CFG_K * C_OUTPUT_POSITIONS;

    constant C_WEIGHTS_DIR : string := G_DATA_ROOT & "/weights/";
    constant C_VECTORS_DIR : string :=
        G_DATA_ROOT & "/test_vectors_trained/";

    type kernel_mem_t is array (0 to C_COEFF_COUNT - 1) of
        std_logic_vector(7 downto 0);
    type pixel_mem_t is array (0 to C_INPUT_PIXELS - 1) of
        std_logic_vector(7 downto 0);
    type output_mem_t is array (0 to C_OUTPUT_POSITIONS - 1) of
        std_logic_vector(15 downto 0);
    type output_channels_t is array (0 to CFG_K - 1) of output_mem_t;
    type integer_array_t is array (natural range <>) of integer;
    type boolean_array_t is array (natural range <>) of boolean;

    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';

    signal s_axi_awaddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_awprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_awvalid : std_logic := '0';
    signal s_axi_awready : std_logic;
    signal s_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_wstrb   : std_logic_vector(3 downto 0) := (others => '1');
    signal s_axi_wvalid  : std_logic := '0';
    signal s_axi_wready  : std_logic;
    signal s_axi_bresp   : std_logic_vector(1 downto 0);
    signal s_axi_bvalid  : std_logic;
    signal s_axi_bready  : std_logic := '1';
    signal s_axi_araddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_arprot  : std_logic_vector(2 downto 0) := (others => '0');
    signal s_axi_arvalid : std_logic := '0';
    signal s_axi_arready : std_logic;
    signal s_axi_rdata   : std_logic_vector(31 downto 0);
    signal s_axi_rresp   : std_logic_vector(1 downto 0);
    signal s_axi_rvalid  : std_logic;
    signal s_axi_rready  : std_logic := '1';

    signal pixel_in   : std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0) :=
        (others => '0');
    signal valid_in   : std_logic := '0';
    signal results_out : output_array_t(0 to CFG_K - 1);
    signal valid_out   : std_logic;

    function contains_text(source : string; needle : string) return boolean is
    begin
        if needle'length = 0 then
            return true;
        elsif source'length < needle'length then
            return false;
        end if;

        for first in source'low to source'high - needle'length + 1 loop
            if source(first to first + needle'length - 1) = needle then
                return true;
            end if;
        end loop;
        return false;
    end function contains_text;

    function integer_after_colon(source : string) return integer is
        variable colon_seen : boolean := false;
        variable digit_seen : boolean := false;
        variable negative   : boolean := false;
        variable value      : integer := 0;
    begin
        for idx in source'range loop
            if not colon_seen then
                if source(idx) = ':' then
                    colon_seen := true;
                end if;
            elsif not digit_seen and source(idx) = '-' then
                negative := true;
            elsif source(idx) >= '0' and source(idx) <= '9' then
                digit_seen := true;
                value := value * 10 + character'pos(source(idx)) -
                         character'pos('0');
            elsif digit_seen then
                exit;
            end if;
        end loop;

        assert colon_seen and digit_seen
            report "Could not parse integer from JSON line: " & source
            severity failure;
        if negative then
            return -value;
        end if;
        return value;
    end function integer_after_colon;

    impure function load_kernel_hex(filename : string) return kernel_mem_t is
        file kernel_file : text open read_mode is filename;
        variable line_buf : line;
        variable hex_val  : std_logic_vector(7 downto 0);
        variable mem      : kernel_mem_t := (others => (others => '0'));
        variable idx      : integer := 0;
        variable good     : boolean;
    begin
        while not endfile(kernel_file) loop
            readline(kernel_file, line_buf);
            if line_buf'length > 0 then
                hread(line_buf, hex_val, good);
                if good then
                    assert idx < C_COEFF_COUNT
                        report "Too many coefficients in " & filename
                        severity failure;
                    if idx < C_COEFF_COUNT then
                        mem(idx) := hex_val;
                    end if;
                    idx := idx + 1;
                end if;
            end if;
        end loop;
        assert idx = C_COEFF_COUNT
            report filename & " has " & integer'image(idx) &
                   " coefficients; expected " & integer'image(C_COEFF_COUNT)
            severity failure;
        return mem;
    end function load_kernel_hex;

    impure function load_input_hex(filename : string) return pixel_mem_t is
        file input_file : text open read_mode is filename;
        variable line_buf : line;
        variable hex_val  : std_logic_vector(7 downto 0);
        variable mem      : pixel_mem_t := (others => (others => '0'));
        variable idx      : integer := 0;
        variable good     : boolean;
    begin
        while not endfile(input_file) loop
            readline(input_file, line_buf);
            if line_buf'length > 0 then
                hread(line_buf, hex_val, good);
                if good then
                    assert idx < C_INPUT_PIXELS
                        report "Too many input pixels in " & filename
                        severity failure;
                    if idx < C_INPUT_PIXELS then
                        mem(idx) := hex_val;
                    end if;
                    idx := idx + 1;
                end if;
            end if;
        end loop;
        assert idx = C_INPUT_PIXELS
            report filename & " has " & integer'image(idx) &
                   " pixels; expected " & integer'image(C_INPUT_PIXELS)
            severity failure;
        return mem;
    end function load_input_hex;

    impure function load_expected_hex(filename : string) return output_mem_t is
        file expected_file : text open read_mode is filename;
        variable line_buf : line;
        variable hex_val  : std_logic_vector(15 downto 0);
        variable mem      : output_mem_t := (others => (others => '0'));
        variable idx      : integer := 0;
        variable good     : boolean;
    begin
        while not endfile(expected_file) loop
            readline(expected_file, line_buf);
            if line_buf'length > 0 then
                hread(line_buf, hex_val, good);
                if good then
                    assert idx < C_OUTPUT_POSITIONS
                        report "Too many expected values in " & filename
                        severity failure;
                    if idx < C_OUTPUT_POSITIONS then
                        mem(idx) := hex_val;
                    end if;
                    idx := idx + 1;
                end if;
            end if;
        end loop;
        assert idx = C_OUTPUT_POSITIONS
            report filename & " has " & integer'image(idx) &
                   " values; expected " & integer'image(C_OUTPUT_POSITIONS)
            severity failure;
        return mem;
    end function load_expected_hex;

begin
    assert CFG_K = 8
        report "This trained-artifact regression requires CFG_K=8"
        severity failure;
    assert CFG_N = 3
        report "The exported trained artifacts require CFG_N=3"
        severity failure;
    assert CFG_UNPADDED_WIDTH = 32 and CFG_UNPADDED_HEIGHT = 32
        report "The trained input/expected vectors require logical dimensions 32x32"
        severity failure;
    assert C_TOTAL_COMPARISONS = 8192
        report "Unexpected trained regression comparison count"
        severity failure;

    clk <= not clk after CLK_PERIOD / 2;

    uut : entity work.conv_top
        generic map (
            C_K                    => CFG_K,
            C_N                    => CFG_N,
            C_IMAGE_WIDTH          => CFG_IMAGE_WIDTH,
            C_IMAGE_HEIGHT         => CFG_IMAGE_HEIGHT,
            C_LOGICAL_IMAGE_WIDTH  => CFG_UNPADDED_WIDTH,
            C_LOGICAL_IMAGE_HEIGHT => CFG_UNPADDED_HEIGHT
        )
        port map (
            clk            => clk,
            resetn         => resetn,
            ce             => '1',
            busy_in        => '0',
            soft_reset_out => open,
            S_AXI_AWADDR   => s_axi_awaddr,
            S_AXI_AWPROT   => s_axi_awprot,
            S_AXI_AWVALID  => s_axi_awvalid,
            S_AXI_AWREADY  => s_axi_awready,
            S_AXI_WDATA    => s_axi_wdata,
            S_AXI_WSTRB    => s_axi_wstrb,
            S_AXI_WVALID   => s_axi_wvalid,
            S_AXI_WREADY   => s_axi_wready,
            S_AXI_BRESP    => s_axi_bresp,
            S_AXI_BVALID   => s_axi_bvalid,
            S_AXI_BREADY   => s_axi_bready,
            S_AXI_ARADDR   => s_axi_araddr,
            S_AXI_ARPROT   => s_axi_arprot,
            S_AXI_ARVALID  => s_axi_arvalid,
            S_AXI_ARREADY  => s_axi_arready,
            S_AXI_RDATA    => s_axi_rdata,
            S_AXI_RRESP    => s_axi_rresp,
            S_AXI_RVALID   => s_axi_rvalid,
            S_AXI_RREADY   => s_axi_rready,
            pixel_in       => pixel_in,
            valid_in       => valid_in,
            results_out    => results_out,
            valid_out      => valid_out
        );

    stim_proc : process
        procedure axi_write(
            addr : in std_logic_vector(31 downto 0);
            data : in std_logic_vector(31 downto 0)
        ) is
            variable aw_pending : boolean;
            variable w_pending  : boolean;
        begin
            wait until falling_edge(clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= '1';
            s_axi_wdata   <= data;
            s_axi_wstrb   <= "1111";
            s_axi_wvalid  <= '1';
            aw_pending := true;
            w_pending  := true;

            while aw_pending or w_pending loop
                wait until rising_edge(clk);
                if aw_pending and s_axi_awready = '1' then
                    aw_pending := false;
                    s_axi_awvalid <= '0';
                end if;
                if w_pending and s_axi_wready = '1' then
                    w_pending := false;
                    s_axi_wvalid <= '0';
                end if;
            end loop;

            loop
                wait until rising_edge(clk);
                exit when s_axi_bvalid = '1';
            end loop;
            assert s_axi_bresp = "00"
                report "AXI-Lite write returned a non-OKAY response"
                severity failure;
        end procedure axi_write;

        procedure load_channel_config(
            variable biases : out integer_array_t;
            variable shifts : out integer_array_t;
            variable relus  : out integer_array_t
        ) is
            file config_file : text open read_mode is
                C_WEIGHTS_DIR & "channel_config.json";
            variable line_buf : line;
            variable current_channel : integer := -1;
            variable parsed_value : integer;
            variable configured_k : integer := -1;
            variable configured_n : integer := -1;
            variable seen_channel : boolean_array_t(biases'range) :=
                (others => false);
            variable seen_bias : boolean_array_t(biases'range) :=
                (others => false);
            variable seen_shift : boolean_array_t(biases'range) :=
                (others => false);
            variable seen_relu : boolean_array_t(biases'range) :=
                (others => false);
        begin
            for ch in biases'range loop
                biases(ch) := 0;
                shifts(ch) := 0;
                relus(ch)  := 0;
            end loop;

            while not endfile(config_file) loop
                readline(config_file, line_buf);
                if contains_text(line_buf.all, """K""") then
                    configured_k := integer_after_colon(line_buf.all);
                elsif contains_text(line_buf.all, """N""") then
                    configured_n := integer_after_colon(line_buf.all);
                elsif contains_text(line_buf.all, """channel""") then
                    parsed_value := integer_after_colon(line_buf.all);
                    assert parsed_value >= biases'low and
                           parsed_value <= biases'high
                        report "Invalid channel index in channel_config.json"
                        severity failure;
                    if parsed_value >= biases'low and
                       parsed_value <= biases'high then
                        current_channel := parsed_value;
                        seen_channel(current_channel) := true;
                    end if;
                elsif contains_text(line_buf.all, """bias_quantized""") then
                    assert current_channel >= biases'low
                        report "bias_quantized precedes channel in channel_config.json"
                        severity failure;
                    if current_channel >= biases'low then
                        biases(current_channel) := integer_after_colon(line_buf.all);
                        seen_bias(current_channel) := true;
                    end if;
                elsif contains_text(line_buf.all, """shift""") then
                    assert current_channel >= shifts'low
                        report "shift precedes channel in channel_config.json"
                        severity failure;
                    if current_channel >= shifts'low then
                        shifts(current_channel) := integer_after_colon(line_buf.all);
                        seen_shift(current_channel) := true;
                    end if;
                elsif contains_text(line_buf.all, """relu_en""") then
                    assert current_channel >= relus'low
                        report "relu_en precedes channel in channel_config.json"
                        severity failure;
                    if current_channel >= relus'low then
                        relus(current_channel) := integer_after_colon(line_buf.all);
                        seen_relu(current_channel) := true;
                    end if;
                end if;
            end loop;

            assert configured_k = CFG_K
                report "Exported K=" & integer'image(configured_k) &
                       " does not match CFG_K=" & integer'image(CFG_K)
                severity failure;
            assert configured_n = CFG_N
                report "Exported N=" & integer'image(configured_n) &
                       " does not match CFG_N=" & integer'image(CFG_N)
                severity failure;
            for ch in biases'range loop
                assert seen_channel(ch) and seen_bias(ch) and
                       seen_shift(ch) and seen_relu(ch)
                    report "Incomplete exported configuration for channel " &
                           integer'image(ch)
                    severity failure;
            end loop;
        end procedure load_channel_config;

        variable input_pixels : pixel_mem_t;
        variable kernel       : kernel_mem_t;
        variable biases       : integer_array_t(0 to CFG_K - 1);
        variable shifts       : integer_array_t(0 to CFG_K - 1);
        variable relus        : integer_array_t(0 to CFG_K - 1);
        variable write_data   : std_logic_vector(31 downto 0);
        variable coeff_index  : integer;
        variable image_row    : integer;
        variable image_col    : integer;
    begin
        report "--- Starting trained K=8 conv_top regression ---";
        input_pixels := load_input_hex(C_VECTORS_DIR & "input.hex");
        load_channel_config(biases, shifts, relus);

        resetn <= '0';
        wait for 4 * CLK_PERIOD;
        wait until falling_edge(clk);
        resetn <= '1';

        report "Programming all exported K=8 channel parameters";
        for ch in 0 to CFG_K - 1 loop
            kernel := load_kernel_hex(
                C_WEIGHTS_DIR & "kernel_ch" & integer'image(ch) & ".mem"
            );

            for word_index in 0 to C_COEFF_WORDS - 1 loop
                write_data := (others => '0');
                for lane in 0 to 3 loop
                    coeff_index := word_index * 4 + lane;
                    if coeff_index < C_COEFF_COUNT then
                        write_data((lane + 1) * 8 - 1 downto lane * 8) :=
                            kernel(coeff_index);
                    end if;
                end loop;
                axi_write(
                    std_logic_vector(to_unsigned(
                        ch * C_CHANNEL_STRIDE + word_index * 4, 32)),
                    write_data
                );
            end loop;

            axi_write(
                std_logic_vector(to_unsigned(
                    ch * C_CHANNEL_STRIDE + C_BIAS_OFFSET, 32)),
                std_logic_vector(to_signed(biases(ch), 32))
            );

            write_data := (others => '0');
            write_data(4 downto 0) :=
                std_logic_vector(to_unsigned(shifts(ch), 5));
            if relus(ch) /= 0 then
                write_data(8) := '1';
            end if;
            axi_write(
                std_logic_vector(to_unsigned(
                    ch * C_CHANNEL_STRIDE + C_CONTROL_OFFSET, 32)),
                write_data
            );
        end loop;

        report "Streaming trained 32x32 input with the configured zero padding";
        for row in 0 to CFG_IMAGE_HEIGHT - 1 loop
            for col in 0 to CFG_IMAGE_WIDTH - 1 loop
                image_row := row - C_PADDING;
                image_col := col - C_PADDING;

                if image_row >= 0 and image_row < CFG_UNPADDED_HEIGHT and
                   image_col >= 0 and image_col < CFG_UNPADDED_WIDTH then
                    pixel_in <= input_pixels(
                        image_row * CFG_UNPADDED_WIDTH + image_col
                    );
                else
                    pixel_in <= (others => '0');
                end if;
                valid_in <= '1';
                wait until rising_edge(clk);
            end loop;
        end loop;

        wait until falling_edge(clk);
        valid_in <= '0';
        pixel_in <= (others => '0');
        report "--- Trained input stimulus complete ---";
        wait;
    end process stim_proc;

    check_proc : process
        variable expected         : output_channels_t;
        variable output_position  : integer := 0;
        variable comparison_count : integer := 0;
        variable mismatch_count   : integer := 0;
        variable expected_value   : std_logic_vector(15 downto 0);
        variable actual_value     : std_logic_vector(15 downto 0);
    begin
        for ch in 0 to CFG_K - 1 loop
            expected(ch) := load_expected_hex(
                C_VECTORS_DIR & "expected_ch" & integer'image(ch) & ".hex"
            );
        end loop;

        wait until resetn = '1';
        while output_position < C_OUTPUT_POSITIONS loop
            wait until rising_edge(clk);
            if valid_out = '1' then
                for ch in 0 to CFG_K - 1 loop
                    expected_value := expected(ch)(output_position);
                    actual_value   := results_out(ch);
                    comparison_count := comparison_count + 1;
                    if actual_value /= expected_value then
                        mismatch_count := mismatch_count + 1;
                        if mismatch_count <= 20 then
                            report "MISMATCH position=" &
                                   integer'image(output_position) &
                                   " channel=" & integer'image(ch) &
                                   " expected=0x" & to_hstring(expected_value) &
                                   " actual=0x" & to_hstring(actual_value)
                                severity warning;
                        end if;
                    end if;
                end loop;
                output_position := output_position + 1;
            end if;
        end loop;

        report "============================================";
        report "  Output positions:  " & integer'image(output_position);
        report "  Channels:          " & integer'image(CFG_K);
        report "  Total comparisons: " & integer'image(comparison_count);
        report "  Total mismatches:  " & integer'image(mismatch_count);
        assert comparison_count = C_TOTAL_COMPARISONS
            report "Comparison count was not 8192"
            severity failure;
        assert mismatch_count = 0
            report "Trained K=8 regression failed"
            severity failure;
        report "  RESULT: PASS - all trained K=8 outputs are bit-exact";
        report "============================================";
        stop(0);
        wait;
    end process check_proc;

    watchdog_proc : process
    begin
        wait for 100 us;
        assert false
            report "WATCHDOG: trained K=8 regression did not complete"
            severity failure;
        stop(1);
        wait;
    end process watchdog_proc;

end architecture sim;
