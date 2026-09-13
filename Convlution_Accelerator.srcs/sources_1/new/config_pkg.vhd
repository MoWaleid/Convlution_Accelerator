library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.MATH_REAL.ALL;

package config_pkg is

    -- Release identity must change when publishing a different hardware build.
    constant CFG_PROFILE : string := "EF100";
    constant CFG_BUILD_ID : std_logic_vector(127 downto 0) := x"45463130304B31364E33573332523031";

    -- ========================================================================
    -- Helper Functions (used for constant elaboration)
    -- ========================================================================
    function max_int(a, b : integer) return integer;
    function clog2(n : positive) return natural;

    -- ========================================================================
    -- Master Hardware Configuration
    -- Change these constants to globally update the architecture at compile-time
    -- ========================================================================

    -- Number of parallel output channels (K).
    constant CFG_K : integer := 16;

    -- Kernel spatial dimension (N x N).
    constant CFG_N : integer := 3;

    -- Image spatial dimensions.
    constant CFG_UNPADDED_WIDTH  : integer := 32;
    constant CFG_UNPADDED_HEIGHT : integer := 32;

    -- Hardware receives an externally zero-padded image.
    constant CFG_IMAGE_WIDTH  : integer :=
        CFG_UNPADDED_WIDTH + 2 * (CFG_N / 2);
    constant CFG_IMAGE_HEIGHT : integer :=
        CFG_UNPADDED_HEIGHT + 2 * (CFG_N / 2);

    -- ========================================================================
    -- Numerical Format
    -- ========================================================================

    -- uint8 input pixels.
    constant CFG_PIXEL_WIDTH : integer := 8;

    -- signed int8 kernel coefficients.
    constant CFG_WEIGHT_WIDTH : integer := 8;

    -- This branch uses exact CFGLUT5 constant-coefficient multiplication.
    -- Retain the legacy capability field at zero so software and reports
    -- identify that no activation bits are discarded.
    constant CFG_APPROX_PIXEL_LSB_DROP : natural := 0;

    -- CVH1 default: signed 24-bit bias.
    constant CFG_BIAS_WIDTH : integer := 24;

    -- Unsigned post-accumulation right shift.
    constant CFG_SHIFT_WIDTH : integer := 5;

    -- Signed int16 output.
    constant CFG_OUTPUT_WIDTH : integer := 16;

    -- ========================================================================
    -- Derived Pipeline Widths
    -- ========================================================================

    -- unsigned pixel is zero-extended by one bit before signed multiplication:
    --
    --   signed(PIXEL_WIDTH + 1) * signed(WEIGHT_WIDTH)
    --
    -- For the default configuration:
    --   9 x 8 -> signed 17-bit product.
    constant CFG_PRODUCT_WIDTH : integer :=
        CFG_PIXEL_WIDTH + CFG_WEIGHT_WIDTH + 1;

    -- Width required by one first-level group of N products.
    -- This remains useful for the physical two-level reduction pipeline.
    constant CFG_PSUM_EXTRA_BITS : integer := clog2(CFG_N);

    constant CFG_PSUM_WIDTH : integer :=
        CFG_PRODUCT_WIDTH + CFG_PSUM_EXTRA_BITS;

    -- CVH1 SUM_WIDTH:
    --
    --   PIXEL_WIDTH
    -- + WEIGHT_WIDTH
    -- + ceil(log2(N*N))
    -- + 1
    --
    -- Equivalently:
    --
    --   PRODUCT_WIDTH + ceil(log2(N*N))
    --
    -- Defaults:
    --   N=3 -> 17 + 4 = 21
    --   N=5 -> 17 + 5 = 22
    --
    -- Do not derive this as PSUM_WIDTH + clog2(N): that happens to give the
    -- correct N=3 width but overestimates the approved N=5 SUM_WIDTH by one bit.
    constant CFG_SUM_WIDTH : integer :=
        CFG_PRODUCT_WIDTH + clog2(CFG_N * CFG_N);

    -- CVH1 ACC_WIDTH:
    --
    --   max(SUM_WIDTH, BIAS_WIDTH) + 1
    --
    -- Default N=3 / signed24 bias:
    --   max(21, 24) + 1 = 25
    constant CFG_FULL_ACCUM_WIDTH : integer :=
        max_int(CFG_SUM_WIDTH, CFG_BIAS_WIDTH) + 1;

    -- Legacy compatibility constant retained temporarily while M4 is being
    -- integrated. New M4 logic must use CFG_SUM_WIDTH and
    -- CFG_FULL_ACCUM_WIDTH instead.
    --
    -- We will remove or alias this after checking that no remaining source
    -- depends on its historical value.

end package config_pkg;


package body config_pkg is

    function max_int(a, b : integer) return integer is
    begin
        if a > b then
            return a;
        else
            return b;
        end if;
    end function max_int;

    function clog2(n : positive) return natural is
    begin
        if n = 1 then
            return 0;
        end if;

        return integer(ceil(log2(real(n))));
    end function clog2;

end package body config_pkg;
