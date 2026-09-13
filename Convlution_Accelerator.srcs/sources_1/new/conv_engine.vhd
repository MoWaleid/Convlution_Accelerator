-- ============================================================================
-- conv_engine.vhd -- K-channel exact CFGLUT5 convolution engine
-- ============================================================================
-- Each accepted packed AXI coefficient write is captured directly.  Its four
-- signed8 lanes configure four coefficient banks sequentially; the final word
-- configures only the valid tail lane.  This avoids both BRAM and a 144-to-1
-- read mux over stored coefficients.  The controller backpressures subsequent
-- writes until cfg_ready returns high.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.conv_pkg.all;
use work.config_pkg.all;

entity conv_engine is
    generic (
        C_K : integer := CFG_K;
        C_N : integer := CFG_N
    );
    port (
        clk        : in  std_logic;
        resetn     : in  std_logic;
        cfg_resetn : in  std_logic;
        ce         : in  std_logic;

        window_in  : in  pixel_array_t(0 to C_N * C_N - 1);
        valid_in   : in  std_logic;

        bias_all    : in  bias_array_t(0 to C_K - 1);
        shift_all   : in  shift_array_t(0 to C_K - 1);
        relu_en_all : in  std_logic_vector(0 to C_K - 1);

        coeff_write_pulse : in  std_logic;
        coeff_write_addr  : in  std_logic_vector(31 downto 0);
        coeff_write_data  : in  std_logic_vector(31 downto 0);
        cfg_ready         : out std_logic;

        results_out : out output_array_t(0 to C_K - 1);
        valid_out   : out std_logic
    );
end entity conv_engine;

architecture rtl of conv_engine is
    constant C_TAPS : positive := C_N * C_N;

    signal channel_valid : std_logic_vector(0 to C_K - 1);

    signal cfg_active        : std_logic := '0';
    signal cfg_channel_index : natural range 0 to C_K - 1 := 0;
    signal cfg_tap_index     : natural range 0 to C_TAPS - 1 := 0;
    signal cfg_lane_index    : natural range 0 to 3 := 0;
    signal cfg_bit_index     : natural range 0 to 31 := 31;
    signal cfg_write_word    : std_logic_vector(31 downto 0) :=
        (others => '0');
    signal cfg_weight        : signed(CFG_WEIGHT_WIDTH - 1 downto 0) :=
        (others => '0');
    signal cfg_data          : std_logic_vector(5 downto 0) :=
        (others => '0');
begin
    assert C_N = 3
        report "CFGLUT5 engine configuration is specialized for N=3"
        severity failure;

    cfg_ready <= not cfg_active;

    -- One shared 4-bit-by-signed8 shift/add operation generates all six serial
    -- truth-table bits for the active coefficient bank.
    cfg_data_process : process(all)
        variable digit        : natural range 0 to 15;
        variable output_phase : natural range 0 to 1;
        variable weight_ext   : signed(11 downto 0);
        variable product      : signed(11 downto 0);
    begin
        if cfg_bit_index >= 16 then
            digit := cfg_bit_index - 16;
            output_phase := 1;
        else
            digit := cfg_bit_index;
            output_phase := 0;
        end if;

        -- The active signed8 coefficient is registered when a lane begins.
        -- This removes a dynamic 4:1 byte mux from the serial CFGLUT D path.
        weight_ext := resize(cfg_weight, weight_ext'length);

        product := (others => '0');
        for digit_bit in 0 to 3 loop
            if ((digit / (2 ** digit_bit)) mod 2) = 1 then
                product := product + shift_left(weight_ext, digit_bit);
            end if;
        end loop;

        for pair_index in 0 to 5 loop
            cfg_data(pair_index) <=
                product(2 * pair_index + output_phase);
        end loop;
    end process cfg_data_process;

    configuration_process : process(clk)
        variable written_channel : natural;
        variable written_word    : natural;
        variable first_tap       : natural;
    begin
        if rising_edge(clk) then
            if cfg_resetn = '0' then
                cfg_active        <= '0';
                cfg_channel_index <= 0;
                cfg_tap_index     <= 0;
                cfg_lane_index    <= 0;
                cfg_bit_index     <= 31;
                cfg_write_word    <= (others => '0');
                cfg_weight        <= (others => '0');
            elsif coeff_write_pulse = '1' then
                assert cfg_active = '0'
                    report "Coefficient write arrived while CFGLUT loading"
                    severity failure;

                written_channel :=
                    to_integer(unsigned(coeff_write_addr(13 downto 8)));
                written_word :=
                    to_integer(unsigned(coeff_write_addr(7 downto 2)));
                first_tap := written_word * 4;

                assert written_channel < C_K and first_tap < C_TAPS
                    report "Invalid coefficient write forwarded to CFGLUT engine"
                    severity failure;

                cfg_active        <= '1';
                cfg_channel_index <= written_channel;
                cfg_tap_index     <= first_tap;
                cfg_lane_index    <= 0;
                cfg_bit_index     <= 31;
                cfg_write_word    <= coeff_write_data;
                cfg_weight        <= signed(coeff_write_data(7 downto 0));
            elsif cfg_active = '1' then
                if cfg_bit_index = 0 then
                    if
                        cfg_lane_index < 3
                        and cfg_tap_index + 1 < C_TAPS
                    then
                        cfg_tap_index  <= cfg_tap_index + 1;
                        cfg_lane_index <= cfg_lane_index + 1;
                        cfg_bit_index  <= 31;

                        case cfg_lane_index is
                            when 0 =>
                                cfg_weight <=
                                    signed(cfg_write_word(15 downto 8));
                            when 1 =>
                                cfg_weight <=
                                    signed(cfg_write_word(23 downto 16));
                            when others =>
                                cfg_weight <=
                                    signed(cfg_write_word(31 downto 24));
                        end case;
                    else
                        cfg_active <= '0';
                    end if;
                else
                    cfg_bit_index <= cfg_bit_index - 1;
                end if;
            end if;
        end if;
    end process configuration_process;

    gen_channels : for channel in 0 to C_K - 1 generate
        signal cfg_ce_taps : std_logic_vector(0 to C_TAPS - 1);
    begin
        gen_cfg_select : for tap in 0 to C_TAPS - 1 generate
        begin
            cfg_ce_taps(tap) <=
                '1' when
                    cfg_active = '1'
                    and cfg_channel_index = channel
                    and cfg_tap_index = tap
                else '0';
        end generate gen_cfg_select;

        channel_inst : entity work.conv_channel
            generic map (
                C_N => C_N
            )
            port map (
                clk        => clk,
                resetn     => resetn,
                ce         => ce,
                window_in  => window_in,
                cfg_ce     => cfg_ce_taps,
                cfg_data   => cfg_data,
                bias_in    => bias_all(channel),
                shift_in   => shift_all(channel),
                relu_en_in => relu_en_all(channel),
                valid_in   => valid_in,
                result_out => results_out(channel),
                valid_out  => channel_valid(channel)
            );
    end generate gen_channels;

    valid_out <= channel_valid(0);
end architecture rtl;
