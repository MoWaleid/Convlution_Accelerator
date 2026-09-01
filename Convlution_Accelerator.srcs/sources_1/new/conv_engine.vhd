-- ============================================================================
-- conv_engine.vhd — K-Channel Parallel Convolution Engine
-- ============================================================================
-- Instantiates K conv_channel units sharing a single sliding window.
-- Each channel applies its own kernel/bias/shift/ReLU to the same window.
-- All channels have identical pipeline latency, so one valid signal suffices.
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
        ce         : in  std_logic;

        -- Shared pixel window (broadcast to all channels)
        window_in  : in  pixel_array_t(0 to C_N * C_N - 1);
        valid_in   : in  std_logic;

        -- Per-channel parameters (flat arrays from register file)
        coeffs_all  : in  coeff_array_t(0 to C_K * C_N * C_N - 1);
        bias_all    : in  bias_array_t(0 to C_K - 1);
        shift_all   : in  shift_array_t(0 to C_K - 1);
        relu_en_all : in  std_logic_vector(0 to C_K - 1);

        -- Parallel channel outputs
        results_out : out output_array_t(0 to C_K - 1);
        valid_out   : out std_logic
    );
end entity conv_engine;

architecture rtl of conv_engine is

    -- Per-channel valid signals (all identical due to same pipeline depth)
    signal channel_valid : std_logic_vector(0 to C_K - 1);

begin

    -- ========================================================================
    -- Generate K parallel conv_channel instances
    -- ========================================================================
    gen_channels : for k in 0 to C_K - 1 generate

        -- Re-indexed coefficient slice for channel k
        signal ch_coeffs : coeff_array_t(0 to C_N * C_N - 1);

    begin

        -- Extract this channel's coefficients from the flat array
        gen_coeff_map : for i in 0 to C_N * C_N - 1 generate
            ch_coeffs(i) <= coeffs_all(k * C_N * C_N + i);
        end generate gen_coeff_map;

        -- Channel compute unit
        ch_inst : entity work.conv_channel
            generic map (
                C_N => C_N
            )
            port map (
                clk        => clk,
                resetn     => resetn,
                ce         => ce,
                window_in  => window_in,
                coeffs_in  => ch_coeffs,
                bias_in    => bias_all(k),
                shift_in   => shift_all(k),
                relu_en_in => relu_en_all(k),
                valid_in   => valid_in,
                result_out => results_out(k),
                valid_out  => channel_valid(k)
            );

    end generate gen_channels;

    -- All channels share the same pipeline depth → use channel 0's valid
    valid_out <= channel_valid(0);

end architecture rtl;
