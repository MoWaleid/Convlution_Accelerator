-- ============================================================================
-- tb_conv_axis_wrapper.vhd
-- End-to-end AXI4-Lite + AXI4-Stream wrapper regression with backpressure.
-- ============================================================================
library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library STD;
use STD.ENV.ALL;

entity tb_conv_axis_wrapper is
end entity tb_conv_axis_wrapper;

architecture sim of tb_conv_axis_wrapper is
    constant CLK_PERIOD       : time := 10 ns;
    constant C_K              : integer := 4;
    constant C_N              : integer := 3;
    constant C_LOGICAL_WIDTH  : integer := 16;
    constant C_LOGICAL_HEIGHT : integer := 16;
    constant C_PADDED_WIDTH   : integer := C_LOGICAL_WIDTH + 2 * (C_N / 2);
    constant C_PADDED_HEIGHT  : integer := C_LOGICAL_HEIGHT + 2 * (C_N / 2);
    constant C_INPUT_PIXELS   : integer := C_PADDED_WIDTH * C_PADDED_HEIGHT;
    constant C_AXIS_BEATS     : integer := (C_INPUT_PIXELS + 7) / 8;
    constant C_LAST_BYTES     : integer := C_INPUT_PIXELS mod 8;
    constant C_OUTPUT_POSITIONS : integer := C_LOGICAL_WIDTH * C_LOGICAL_HEIGHT;
    constant C_OUTPUT_SCALARS : integer := C_OUTPUT_POSITIONS * C_K;

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

    signal s_axis_tdata  : std_logic_vector(63 downto 0) := (others => '0');
    signal s_axis_tkeep  : std_logic_vector(7 downto 0) := (others => '0');
    signal s_axis_tvalid : std_logic := '0';
    signal s_axis_tready : std_logic;
    signal s_axis_tlast  : std_logic := '0';

    signal m_axis_tdata  : std_logic_vector(63 downto 0);
    signal m_axis_tkeep  : std_logic_vector(7 downto 0);
    signal m_axis_tvalid : std_logic;
    signal m_axis_tready : std_logic;
    signal m_axis_tlast  : std_logic;

    signal frame_one_done       : std_logic := '0';
    signal frame_two_done       : std_logic := '0';
    signal stall_phase          : std_logic := '0';
    signal release_output       : std_logic := '0';
    signal backpressure_complete : std_logic := '0';

    function padded_pixel(pixel_index : natural) return std_logic_vector is
        variable row_index    : natural;
        variable column_index : natural;
        variable value        : natural;
    begin
        row_index := pixel_index / C_PADDED_WIDTH;
        column_index := pixel_index mod C_PADDED_WIDTH;
        if row_index = 0 or row_index = C_PADDED_HEIGHT - 1 or
           column_index = 0 or column_index = C_PADDED_WIDTH - 1 then
            value := 0;
        else
            value := ((row_index - 1) * C_LOGICAL_WIDTH + (column_index - 1) + 1) mod 256;
        end if;
        return std_logic_vector(to_unsigned(value, 8));
    end function padded_pixel;

    function make_axis_beat(beat_index : natural) return std_logic_vector is
        variable data        : std_logic_vector(63 downto 0) := (others => '0');
        variable pixel_index : natural;
    begin
        for lane in 0 to 7 loop
            pixel_index := beat_index * 8 + lane;
            if pixel_index < C_INPUT_PIXELS then
                data((lane + 1) * 8 - 1 downto lane * 8) := padded_pixel(pixel_index);
            end if;
        end loop;
        return data;
    end function make_axis_beat;

    function expected_result(position_index : natural) return std_logic_vector is
        variable value : natural;
    begin
        value := (position_index + 1) mod 256;
        return std_logic_vector(to_signed(value, 16));
    end function expected_result;

    function last_keep return std_logic_vector is
    begin
        case C_LAST_BYTES is
            when 0 => return x"FF";
            when 1 => return x"01";
            when 2 => return x"03";
            when 3 => return x"07";
            when 4 => return x"0F";
            when 5 => return x"1F";
            when 6 => return x"3F";
            when others => return x"7F";
        end case;
    end function last_keep;
begin
    clk <= not clk after CLK_PERIOD / 2;
    m_axis_tready <= '1' when stall_phase = '0' or release_output = '1' else '0';

    dut : entity work.conv_axis_wrapper
        generic map (
            C_K                   => C_K,
            C_N                   => C_N,
            C_IMAGE_WIDTH         => C_PADDED_WIDTH,
            C_IMAGE_HEIGHT        => C_PADDED_HEIGHT,
            C_OUTPUT_IMAGE_WIDTH  => C_LOGICAL_WIDTH,
            C_OUTPUT_IMAGE_HEIGHT => C_LOGICAL_HEIGHT
        )
        port map (
            clk           => clk,
            resetn        => resetn,
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
            s_axis_tdata  => s_axis_tdata,
            s_axis_tkeep  => s_axis_tkeep,
            s_axis_tvalid => s_axis_tvalid,
            s_axis_tready => s_axis_tready,
            s_axis_tlast  => s_axis_tlast,
            m_axis_tdata  => m_axis_tdata,
            m_axis_tkeep  => m_axis_tkeep,
            m_axis_tvalid => m_axis_tvalid,
            m_axis_tready => m_axis_tready,
            m_axis_tlast  => m_axis_tlast
        );

    stimulus : process
        procedure axi_write(
            constant address : in std_logic_vector(31 downto 0);
            constant data    : in std_logic_vector(31 downto 0)
        ) is
        begin
            wait until falling_edge(clk);
            s_axi_awaddr  <= address;
            s_axi_awvalid <= '1';
            s_axi_wdata   <= data;
            s_axi_wstrb   <= "1111";
            s_axi_wvalid  <= '1';
            loop
                wait until rising_edge(clk);
                exit when s_axi_awready = '1' and s_axi_wready = '1';
            end loop;
            wait until falling_edge(clk);
            s_axi_awvalid <= '0';
            s_axi_wvalid  <= '0';
            loop
                wait until rising_edge(clk);
                exit when s_axi_bvalid = '1';
            end loop;
            assert s_axi_bresp = "00"
                report "AXI-Lite configuration write did not receive OKAY" severity failure;
        end procedure axi_write;

        procedure configure_identity_channel(constant channel : in natural) is
            variable base : natural;
        begin
            base := channel * 16#100#;
            axi_write(std_logic_vector(to_unsigned(base + 16#00#, 32)), x"00000000");
            axi_write(std_logic_vector(to_unsigned(base + 16#04#, 32)), x"00000001");
            axi_write(std_logic_vector(to_unsigned(base + 16#08#, 32)), x"00000000");
            axi_write(std_logic_vector(to_unsigned(base + 16#F8#, 32)), x"00000000");
            axi_write(std_logic_vector(to_unsigned(base + 16#FC#, 32)), x"00000000");
        end procedure configure_identity_channel;

        procedure send_padded_frame is
        begin
            for beat_index in 0 to C_AXIS_BEATS - 1 loop
                wait until falling_edge(clk);
                s_axis_tdata  <= make_axis_beat(beat_index);
                if beat_index = C_AXIS_BEATS - 1 then
                    s_axis_tkeep <= last_keep;
                    s_axis_tlast <= '1';
                else
                    s_axis_tkeep <= x"FF";
                    s_axis_tlast <= '0';
                end if;
                s_axis_tvalid <= '1';
                loop
                    wait until rising_edge(clk);
                    exit when s_axis_tready = '1';
                end loop;
                wait until falling_edge(clk);
                s_axis_tvalid <= '0';
                -- One 64-bit beat every eight clocks matches one pixel per clock.
                for idle_cycle in 1 to 6 loop
                    wait until falling_edge(clk);
                end loop;
            end loop;
            s_axis_tlast <= '0';
        end procedure send_padded_frame;
    begin
        resetn <= '0';
        wait until falling_edge(clk);
        wait until falling_edge(clk);
        resetn <= '1';

        for channel in 0 to C_K - 1 loop
            configure_identity_channel(channel);
        end loop;
        wait until falling_edge(clk);

        -- Frame A: uncongested AXI output must match the standalone core result.
        send_padded_frame;
        if frame_one_done /= '1' then
            wait until frame_one_done = '1';
        end if;

        -- Frame B: hold downstream ready low until the complete chain stalls.
        wait until falling_edge(clk);
        stall_phase <= '1';
        send_padded_frame;
        if backpressure_complete /= '1' then
            wait until backpressure_complete = '1';
        end if;
        if frame_two_done /= '1' then
            wait until frame_two_done = '1';
        end if;

        report "--- AXI4-Stream convolution wrapper regression completed successfully ---";
        stop(0);
        wait;
    end process stimulus;

    -- Proves AXI output data/control remain stable on every downstream stall.
    output_stability_monitor : process
        variable held_valid : boolean := false;
        variable held_data  : std_logic_vector(63 downto 0) := (others => '0');
        variable held_keep  : std_logic_vector(7 downto 0) := (others => '0');
        variable held_last  : std_logic := '0';
    begin
        wait until resetn = '1';
        loop
            wait until falling_edge(clk);
            if held_valid and m_axis_tready = '0' then
                assert m_axis_tvalid = '1' and m_axis_tdata = held_data and
                       m_axis_tkeep = held_keep and m_axis_tlast = held_last
                    report "Wrapper AXI output changed while m_axis_tready was low" severity failure;
            end if;
            held_valid := (m_axis_tvalid = '1' and m_axis_tready = '0');
            if held_valid then
                held_data := m_axis_tdata;
                held_keep := m_axis_tkeep;
                held_last := m_axis_tlast;
            end if;
            exit when frame_two_done = '1';
        end loop;
        wait;
    end process output_stability_monitor;

    -- The input FIFO can fill only after serializer backpressure has frozen the core.
    backpressure_monitor : process
    begin
        wait until stall_phase = '1';
        loop
            wait until falling_edge(clk);
            exit when s_axis_tvalid = '1' and s_axis_tready = '0' and
                      m_axis_tvalid = '1' and m_axis_tready = '0';
        end loop;

        -- Existing row-boundary valid bubbles may permit isolated core advances,
        -- but the preceding handshake proves that the full input FIFO blocked the
        -- upstream AXI source while the output path remained stalled.
        for stalled_cycle in 1 to 20 loop
            wait until falling_edge(clk);
            assert m_axis_tvalid = '1' and m_axis_tready = '0'
                report "Output blockage was not present while input was backpressured" severity failure;
        end loop;

        release_output <= '1';
        backpressure_complete <= '1';
        wait;
    end process backpressure_monitor;

    output_monitor : process
        variable frame_index  : natural := 0;
        variable scalar_index : natural := 0;
        variable last_count   : natural := 0;
        variable position_index : natural;
        variable expected : std_logic_vector(15 downto 0);
    begin
        wait until resetn = '1';
        loop
            wait until rising_edge(clk);
            if m_axis_tvalid = '1' and m_axis_tready = '1' then
                assert m_axis_tkeep = x"FF"
                    report "K=4 wrapper output must contain four int16 scalars per beat" severity failure;
                for lane in 0 to C_K - 1 loop
                    position_index := scalar_index / C_K;
                    expected := expected_result(position_index);
                    assert m_axis_tdata((lane + 1) * 16 - 1 downto lane * 16) = expected
                        report "Wrapper output scalar ordering or value mismatch" severity failure;
                    scalar_index := scalar_index + 1;
                end loop;

                if m_axis_tlast = '1' then
                    last_count := last_count + 1;
                end if;
                if scalar_index = C_OUTPUT_SCALARS then
                    assert m_axis_tlast = '1' and last_count = 1
                        report "Wrapper frame did not terminate with exactly one TLAST" severity failure;
                    if frame_index = 0 then
                        frame_one_done <= '1';
                    elsif frame_index = 1 then
                        frame_two_done <= '1';
                    else
                        assert false report "Wrapper emitted an unexpected extra frame" severity failure;
                    end if;
                    frame_index := frame_index + 1;
                    scalar_index := 0;
                    last_count := 0;
                else
                    assert m_axis_tlast = '0'
                        report "Wrapper asserted TLAST before the final output scalar" severity failure;
                end if;
            end if;
        end loop;
    end process output_monitor;

    timeout_monitor : process
    begin
        wait for 100 us;
        assert false report "AXI4-Stream convolution wrapper regression timed out" severity failure;
        wait;
    end process timeout_monitor;
end architecture sim;