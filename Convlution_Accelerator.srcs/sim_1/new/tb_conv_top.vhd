-- ============================================================================
-- tb_conv_top.vhd — End-to-End Convolution Accelerator Testbench
-- ============================================================================
-- Verifies bit-exact match between the RTL pipeline and the Python golden
-- model by:
--   1. Configuring weights/bias/shift/ReLU via AXI-Lite writes
--   2. Streaming a zero-padded 34×34 image (from input.hex)
--   3. Comparing each output pixel against expected_ch*.hex
--
-- Uses the "custom" test vector set (4 channels, Identity/Sobel/Blur).
-- Change the constants below to switch to trained/zeros/ones test sets.
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

entity tb_conv_top is
end entity tb_conv_top;

architecture sim of tb_conv_top is

    -- ========================================================================
    -- Test Configuration
    -- ========================================================================
    -- Set USE_CUSTOM_FILTERS = true for the 4-channel custom demo,
    -- or false to load trained weights from .mem files (16 channels).
    constant USE_CUSTOM_FILTERS : boolean := true;

    constant TEST_N          : integer := 3;
    constant TEST_K          : integer := 4;  -- 4 for custom, 16 for trained
    constant TEST_IMG_W      : integer := 32;
    constant TEST_PADDED_W   : integer := TEST_IMG_W + 2 * (TEST_N / 2);  -- 34
    constant TEST_NUM_PIXELS : integer := TEST_IMG_W * TEST_IMG_W;        -- 1024

    -- Paths to golden model test vector files
    constant C_DATA_DIR : string := "D:/MyProjects/Convlution_Accelerator/golden_model/data/";
    constant C_VEC_DIR  : string := C_DATA_DIR & "test_vectors_custom/";

    -- Clock period
    constant CLK_PERIOD : time := 10 ns;  -- 100 MHz

    -- ========================================================================
    -- DUT signals
    -- ========================================================================
    signal clk    : std_logic := '0';
    signal resetn : std_logic := '0';
    signal ce     : std_logic := '1';

    -- AXI4-Lite
    signal s_axi_awaddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_awprot  : std_logic_vector(2 downto 0)  := (others => '0');
    signal s_axi_awvalid : std_logic := '0';
    signal s_axi_awready : std_logic;
    signal s_axi_wdata   : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_wstrb   : std_logic_vector(3 downto 0)  := (others => '1');
    signal s_axi_wvalid  : std_logic := '0';
    signal s_axi_wready  : std_logic;
    signal s_axi_bresp   : std_logic_vector(1 downto 0);
    signal s_axi_bvalid  : std_logic;
    signal s_axi_bready  : std_logic := '1';
    signal s_axi_araddr  : std_logic_vector(31 downto 0) := (others => '0');
    signal s_axi_arprot  : std_logic_vector(2 downto 0)  := (others => '0');
    signal s_axi_arvalid : std_logic := '0';
    signal s_axi_arready : std_logic;
    signal s_axi_rdata   : std_logic_vector(31 downto 0);
    signal s_axi_rresp   : std_logic_vector(1 downto 0);
    signal s_axi_rvalid  : std_logic;
    signal s_axi_rready  : std_logic := '1';

    -- Pixel stream
    signal pixel_in  : std_logic_vector(7 downto 0) := (others => '0');
    signal valid_in  : std_logic := '0';

    -- Outputs
    signal results_out : output_array_t(0 to TEST_K - 1);
    signal valid_out   : std_logic;

    -- ========================================================================
    -- Storage for test data
    -- ========================================================================
    type pixel_mem_t is array (0 to TEST_NUM_PIXELS - 1) of integer range 0 to 255;
    type output_mem_t is array (0 to TEST_NUM_PIXELS - 1) of std_logic_vector(15 downto 0);
    type output_ch_array_t is array (0 to TEST_K - 1) of output_mem_t;

    -- Test results
    signal total_mismatches : integer := 0;

begin

    -- ========================================================================
    -- Clock Generation
    -- ========================================================================
    clk <= not clk after CLK_PERIOD / 2;

    -- ========================================================================
    -- DUT Instantiation
    -- ========================================================================
    uut : entity work.conv_top
        generic map (
            C_K           => TEST_K,
            C_N           => TEST_N,
            C_IMAGE_WIDTH => TEST_PADDED_W
        )
        port map (
            clk           => clk,
            resetn        => resetn,
            ce            => ce,
            S_AXI_AWADDR  => s_axi_awaddr,
            S_AXI_AWPROT  => s_axi_awprot,
            S_AXI_AWVALID => s_axi_awvalid,
            S_AXI_AWREADY => s_axi_awready,
            S_AXI_WDATA   => s_axi_wdata,
            S_AXI_WSTRB   => s_axi_wstrb,
            S_AXI_WVALID  => s_axi_wvalid,
            S_AXI_WREADY  => s_axi_wready,
            S_AXI_BRESP   => s_axi_bresp,
            S_AXI_BVALID  => s_axi_bvalid,
            S_AXI_BREADY  => s_axi_bready,
            S_AXI_ARADDR  => s_axi_araddr,
            S_AXI_ARPROT  => s_axi_arprot,
            S_AXI_ARVALID => s_axi_arvalid,
            S_AXI_ARREADY => s_axi_arready,
            S_AXI_RDATA   => s_axi_rdata,
            S_AXI_RRESP   => s_axi_rresp,
            S_AXI_RVALID  => s_axi_rvalid,
            S_AXI_RREADY  => s_axi_rready,
            pixel_in      => pixel_in,
            valid_in      => valid_in,
            results_out   => results_out,
            valid_out     => valid_out
        );

    -- ========================================================================
    -- Stimulus Process
    -- ========================================================================
    stim_proc : process
        constant C_CHANNEL_STRIDE : integer := 16#100#;
        constant C_BIAS_OFFSET    : integer := 16#F8#;
        constant C_CONTROL_OFFSET : integer := 16#FC#;

        -- ----------------------------------------------------------------
        -- AXI-Lite write procedure (from tb_axi_lite_ctrl)
        -- ----------------------------------------------------------------
        procedure axi_write(addr : in std_logic_vector(31 downto 0);
                            data : in std_logic_vector(31 downto 0)) is
        begin
            wait until rising_edge(clk);
            s_axi_awaddr  <= addr;
            s_axi_awvalid <= '1';
            s_axi_wdata   <= data;
            s_axi_wvalid  <= '1';
            wait until rising_edge(clk) and s_axi_awready = '1' and s_axi_wready = '1';
            s_axi_awvalid <= '0';
            s_axi_wvalid  <= '0';
            -- Wait for write response
            if s_axi_bvalid /= '1' then
                wait until rising_edge(clk) and s_axi_bvalid = '1';
            end if;
            wait until rising_edge(clk);
        end procedure;

        -- ----------------------------------------------------------------
        -- Write four signed int8 coefficients packed into one 32-bit word.
        -- The first argument after word_idx becomes byte lane 0 / bits [7:0].
        -- ----------------------------------------------------------------
        procedure write_coeff_word(
            ch       : integer;
            word_idx : integer;
            w0       : integer range -128 to 127;
            w1       : integer range -128 to 127;
            w2       : integer range -128 to 127;
            w3       : integer range -128 to 127
        ) is
            variable addr : std_logic_vector(31 downto 0);
            variable data : std_logic_vector(31 downto 0);
        begin
            addr := std_logic_vector(to_unsigned(ch * C_CHANNEL_STRIDE + word_idx * 4, 32));
            data := (others => '0');
            data(7 downto 0)   := std_logic_vector(to_signed(w0, 8));
            data(15 downto 8)  := std_logic_vector(to_signed(w1, 8));
            data(23 downto 16) := std_logic_vector(to_signed(w2, 8));
            data(31 downto 24) := std_logic_vector(to_signed(w3, 8));
            axi_write(addr, data);
        end procedure;

        -- ----------------------------------------------------------------
        -- Write bias to the register file
        -- ----------------------------------------------------------------
        procedure write_bias(ch : integer; val : integer) is
            variable addr : std_logic_vector(31 downto 0);
            variable data : std_logic_vector(31 downto 0);
        begin
            addr := std_logic_vector(to_unsigned(ch * C_CHANNEL_STRIDE + C_BIAS_OFFSET, 32));
            data := std_logic_vector(to_signed(val, 32));
            axi_write(addr, data);
        end procedure;

        -- ----------------------------------------------------------------
        -- Write shift + ReLU enable to the register file
        -- ----------------------------------------------------------------
        procedure write_shift_relu(ch : integer; shift : integer; relu : integer) is
            variable addr : std_logic_vector(31 downto 0);
            variable data : std_logic_vector(31 downto 0);
        begin
            addr := std_logic_vector(to_unsigned(ch * C_CHANNEL_STRIDE + C_CONTROL_OFFSET, 32));
            data := (others => '0');
            data(4 downto 0) := std_logic_vector(to_unsigned(shift, 5));
            data(8) := '1' when relu = 1 else '0';
            axi_write(addr, data);
        end procedure;

        -- ----------------------------------------------------------------
        -- Load a hex file (uint8, 2-digit hex per line) into pixel memory
        -- ----------------------------------------------------------------
        impure function load_input_hex(filename : string) return pixel_mem_t is
            file     hex_file : text open read_mode is filename;
            variable line_buf : line;
            variable hex_val  : std_logic_vector(7 downto 0);
            variable mem      : pixel_mem_t := (others => 0);
            variable idx      : integer := 0;
            variable good     : boolean;
        begin
            while not endfile(hex_file) and idx < TEST_NUM_PIXELS loop
                readline(hex_file, line_buf);
                if line_buf'length > 0 then
                    hread(line_buf, hex_val, good);
                    if good then
                        mem(idx) := to_integer(unsigned(hex_val));
                        idx := idx + 1;
                    end if;
                end if;
            end loop;
            assert idx = TEST_NUM_PIXELS
                report "Input hex file has " & integer'image(idx) &
                       " values, expected " & integer'image(TEST_NUM_PIXELS)
                severity failure;
            return mem;
        end function;

        -- ----------------------------------------------------------------
        -- Load a hex file (int16, 4-digit hex per line) into output memory
        -- ----------------------------------------------------------------
        impure function load_expected_hex(filename : string) return output_mem_t is
            file     hex_file : text open read_mode is filename;
            variable line_buf : line;
            variable hex_val  : std_logic_vector(15 downto 0);
            variable mem      : output_mem_t := (others => (others => '0'));
            variable idx      : integer := 0;
            variable good     : boolean;
        begin
            while not endfile(hex_file) and idx < TEST_NUM_PIXELS loop
                readline(hex_file, line_buf);
                if line_buf'length > 0 then
                    hread(line_buf, hex_val, good);
                    if good then
                        mem(idx) := hex_val;
                        idx := idx + 1;
                    end if;
                end if;
            end loop;
            assert idx = TEST_NUM_PIXELS
                report "Expected hex file has " & integer'image(idx) &
                       " values, expected " & integer'image(TEST_NUM_PIXELS)
                severity failure;
            return mem;
        end function;

        -- Local variables
        variable input_pixels : pixel_mem_t;
        variable expected     : output_ch_array_t;
        variable padded_pixel : integer;
        variable img_row, img_col : integer;

    begin
        -- ==================================================================
        -- 1. RESET
        -- ==================================================================
        report "--- Starting Conv Top Testbench ---";
        resetn <= '0';
        wait for CLK_PERIOD * 4;
        resetn <= '1';
        wait for CLK_PERIOD * 2;

        -- ==================================================================
        -- 2. CONFIGURE WEIGHTS via AXI-Lite
        -- ==================================================================
        report "Configuring weights...";

        if USE_CUSTOM_FILTERS then
            -- Channel 0: Identity  [0,0,0, 0,127,0, 0,0,0]  shift=7, bias=0, relu=0
            write_coeff_word(0, 0,   0,   0,  0,  0);
            write_coeff_word(0, 1, 127,   0,  0,  0);
            write_coeff_word(0, 2,   0,   0,  0,  0);  -- weight 8 plus harmless unused bytes
            write_bias(0, 0);
            write_shift_relu(0, 7, 0);

            -- Channel 1: Sobel X  [-1,0,1, -2,0,2, -1,0,1]  shift=8, bias=0, relu=0
            write_coeff_word(1, 0,  -1,   0,  1, -2);
            write_coeff_word(1, 1,   0,   2, -1,  0);
            write_coeff_word(1, 2,   1,   0,  0,  0);  -- weight 8 plus harmless unused bytes
            write_bias(1, 0);
            write_shift_relu(1, 8, 0);

            -- Channel 2: Sobel Y  [-1,-2,-1, 0,0,0, 1,2,1]  shift=8, bias=0, relu=0
            write_coeff_word(2, 0,  -1,  -2, -1,  0);
            write_coeff_word(2, 1,   0,   0,  1,  2);
            write_coeff_word(2, 2,   1,   0,  0,  0);  -- weight 8 plus harmless unused bytes
            write_bias(2, 0);
            write_shift_relu(2, 8, 0);

            -- Channel 3: Box blur [1,2,1, 2,4,2, 1,2,1]  shift=4, bias=0, relu=0
            write_coeff_word(3, 0,   1,   2,  1,  2);
            write_coeff_word(3, 1,   4,   2,  1,  2);
            write_coeff_word(3, 2,   1,   0,  0,  0);  -- weight 8 plus harmless unused bytes
            write_bias(3, 0);
            write_shift_relu(3, 4, 0);
        end if;

        report "Weight configuration complete.";

        -- ==================================================================
        -- 3. LOAD TEST VECTORS FROM FILES
        -- ==================================================================
        report "Loading test vectors from hex files...";
        input_pixels := load_input_hex(C_VEC_DIR & "input.hex");
        for ch in 0 to TEST_K - 1 loop
            expected(ch) := load_expected_hex(
                C_VEC_DIR & "expected_ch" & integer'image(ch) & ".hex"
            );
        end loop;
        report "Test vectors loaded.";

        -- ==================================================================
        -- 4. STREAM PADDED IMAGE (34×34)
        -- ==================================================================
        report "Streaming padded image...";
        for row in 0 to TEST_PADDED_W - 1 loop
            for col in 0 to TEST_PADDED_W - 1 loop
                wait until rising_edge(clk);

                -- Determine pixel value: zero-pad border, else from image
                img_row := row - (TEST_N / 2);  -- 0-based unpadded row
                img_col := col - (TEST_N / 2);  -- 0-based unpadded col

                if img_row >= 0 and img_row < TEST_IMG_W and
                   img_col >= 0 and img_col < TEST_IMG_W then
                    padded_pixel := input_pixels(img_row * TEST_IMG_W + img_col);
                else
                    padded_pixel := 0;  -- Zero padding
                end if;

                pixel_in <= std_logic_vector(to_unsigned(padded_pixel, 8));
                valid_in <= '1';
            end loop;
        end loop;

        -- De-assert valid and wait for pipeline to flush
        wait until rising_edge(clk);
        valid_in <= '0';
        pixel_in <= (others => '0');
        wait for CLK_PERIOD * 20;

        report "--- Stimulus complete ---";
        wait;
    end process stim_proc;

    -- ========================================================================
    -- Output Monitor & Checker Process
    -- ========================================================================
    check_proc : process
        variable expected     : output_ch_array_t;
        variable output_count : integer := 0;
        variable ch_mismatch  : integer := 0;
        variable mismatches   : integer := 0;
        variable exp_val      : std_logic_vector(15 downto 0);
        variable act_val      : std_logic_vector(15 downto 0);

        -- ----------------------------------------------------------------
        -- Load expected hex file (same as in stim_proc, duplicated here
        -- because impure functions are local to the declaring process)
        -- ----------------------------------------------------------------
        impure function load_expected_ch(filename : string) return output_mem_t is
            file     hex_file : text open read_mode is filename;
            variable line_buf : line;
            variable hex_val  : std_logic_vector(15 downto 0);
            variable mem      : output_mem_t := (others => (others => '0'));
            variable idx      : integer := 0;
            variable good     : boolean;
        begin
            while not endfile(hex_file) and idx < TEST_NUM_PIXELS loop
                readline(hex_file, line_buf);
                if line_buf'length > 0 then
                    hread(line_buf, hex_val, good);
                    if good then
                        mem(idx) := hex_val;
                        idx := idx + 1;
                    end if;
                end if;
            end loop;
            assert idx = TEST_NUM_PIXELS
                report "Expected hex has " & integer'image(idx) &
                       " values, need " & integer'image(TEST_NUM_PIXELS)
                severity failure;
            return mem;
        end function;

    begin
        -- Wait for reset release
        wait until resetn = '1';

        -- Load expected outputs from golden model hex files
        expected(0) := load_expected_ch(C_VEC_DIR & "expected_ch0.hex");
        expected(1) := load_expected_ch(C_VEC_DIR & "expected_ch1.hex");
        expected(2) := load_expected_ch(C_VEC_DIR & "expected_ch2.hex");
        expected(3) := load_expected_ch(C_VEC_DIR & "expected_ch3.hex");

        -- Monitor valid_out and check each output pixel
        output_count := 0;
        mismatches   := 0;

        while output_count < TEST_NUM_PIXELS loop
            wait until rising_edge(clk);
            if valid_out = '1' then
                for ch in 0 to TEST_K - 1 loop
                    exp_val := expected(ch)(output_count);
                    act_val := results_out(ch);

                    if act_val /= exp_val then
                        mismatches := mismatches + 1;
                        if mismatches <= 20 then  -- Limit output noise
                            report "MISMATCH at pixel " & integer'image(output_count) &
                                   " ch" & integer'image(ch) &
                                   ": expected=0x" & to_hstring(exp_val) &
                                   " actual=0x" & to_hstring(act_val)
                                severity warning;
                        end if;
                    end if;
                end loop;
                output_count := output_count + 1;
            end if;
        end loop;

        -- --------------------------------------------------------------
        -- FINAL REPORT
        -- --------------------------------------------------------------
        report "============================================";
        report "  Output pixels checked: " & integer'image(output_count);
        report "  Channels checked:      " & integer'image(TEST_K);
        report "  Total comparisons:     " & integer'image(output_count * TEST_K);
        report "  Total mismatches:      " & integer'image(mismatches);
        if mismatches = 0 then
            report "  RESULT: *** PASS - Bit-exact match! ***";
        else
            report "  RESULT: *** FAIL - " & integer'image(mismatches) & " mismatches ***"
                severity error;
        end if;
        report "============================================";

        -- Clean simulation exit
        stop(0);
        wait;
    end process check_proc;

end architecture sim;

