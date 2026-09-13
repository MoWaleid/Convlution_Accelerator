-- ============================================================================
-- cfglut5_kcm.vhd -- Runtime-configurable exact 8-bit constant multiplier
-- ============================================================================
--
-- The unsigned pixel is split into two radix-16 digits.  Each digit addresses
-- six CFGLUT5 primitives.  With I4 held high, O5 and O6 are independent
-- four-input functions stored in the lower and upper halves of the 32-bit
-- configuration shift register.  One primitive therefore returns two bits of
-- the signed 12-bit digit-by-weight product.
--
-- Both digit banks receive the same six configuration bits.  A bank is fully
-- programmed by presenting INIT(31), INIT(30), ... INIT(0) on cfg_data while
-- cfg_ce is asserted for 32 rising clock edges.
-- ============================================================================

library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

library UNISIM;
use UNISIM.VComponents.ALL;

entity cfglut5_kcm is
    port (
        clk       : in  std_logic;
        cfg_ce    : in  std_logic;
        cfg_data  : in  std_logic_vector(5 downto 0);
        pixel_in  : in  std_logic_vector(7 downto 0);
        pp_lo_out : out std_logic_vector(11 downto 0);
        pp_hi_out : out std_logic_vector(11 downto 0)
    );
end entity cfglut5_kcm;

architecture rtl of cfglut5_kcm is
    signal pp_lo : std_logic_vector(11 downto 0);
    signal pp_hi : std_logic_vector(11 downto 0);
begin

    gen_output_pairs : for pair_index in 0 to 5 generate
    begin

        low_digit_lut : CFGLUT5
            generic map (
                INIT => X"00000000"
            )
            port map (
                CDO => open,
                O5  => pp_lo(2 * pair_index),
                O6  => pp_lo(2 * pair_index + 1),
                CDI => cfg_data(pair_index),
                CE  => cfg_ce,
                CLK => clk,
                I0  => pixel_in(0),
                I1  => pixel_in(1),
                I2  => pixel_in(2),
                I3  => pixel_in(3),
                I4  => '1'
            );

        high_digit_lut : CFGLUT5
            generic map (
                INIT => X"00000000"
            )
            port map (
                CDO => open,
                O5  => pp_hi(2 * pair_index),
                O6  => pp_hi(2 * pair_index + 1),
                CDI => cfg_data(pair_index),
                CE  => cfg_ce,
                CLK => clk,
                I0  => pixel_in(4),
                I1  => pixel_in(5),
                I2  => pixel_in(6),
                I3  => pixel_in(7),
                I4  => '1'
            );

    end generate gen_output_pairs;

    pp_lo_out <= pp_lo;
    pp_hi_out <= pp_hi;

end architecture rtl;
