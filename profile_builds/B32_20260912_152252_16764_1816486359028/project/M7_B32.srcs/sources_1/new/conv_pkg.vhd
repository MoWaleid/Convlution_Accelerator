library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;

library work;
use work.config_pkg.all;

package conv_pkg is

    -- Unconstrained arrays for ports, sized by generics in the entity
    
    -- Array of signed coefficients (width set by CFG_WEIGHT_WIDTH)
    type coeff_array_t is array (natural range <>) of std_logic_vector(CFG_WEIGHT_WIDTH - 1 downto 0);
    
    -- Array of bias values (width set by CFG_BIAS_WIDTH)
    type bias_array_t is array (natural range <>) of std_logic_vector(CFG_BIAS_WIDTH - 1 downto 0);
    
    -- Array of shift values (width set by CFG_SHIFT_WIDTH)
    type shift_array_t is array (natural range <>) of std_logic_vector(CFG_SHIFT_WIDTH - 1 downto 0);

    -- Array of pixels (for the sliding window)
    type pixel_array_t is array (natural range <>) of std_logic_vector(CFG_PIXEL_WIDTH - 1 downto 0);

    -- Array of output feature-map values (one per channel, width set by CFG_OUTPUT_WIDTH)
    type output_array_t is array (natural range <>) of std_logic_vector(CFG_OUTPUT_WIDTH - 1 downto 0);

end package conv_pkg;
