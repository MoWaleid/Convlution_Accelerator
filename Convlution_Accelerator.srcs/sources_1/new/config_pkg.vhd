library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.MATH_REAL.ALL;

package config_pkg is
    
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
    constant CFG_K : integer := 8;
    
    -- Kernel spatial dimension (N x N).
    -- Standard small-image convolution kernel size is 3x3.
    constant CFG_N : integer := 3;
    
    -- Image spatial dimensions
    constant CFG_UNPADDED_WIDTH  : integer := 32; -- CIFAR-10 is 32x32
    constant CFG_UNPADDED_HEIGHT : integer := 32;
    -- Hardware receives padded image (padding = N/2 on each side)
    constant CFG_IMAGE_WIDTH  : integer := CFG_UNPADDED_WIDTH + 2 * (CFG_N / 2);
    constant CFG_IMAGE_HEIGHT : integer := CFG_UNPADDED_HEIGHT + 2 * (CFG_N / 2);
    
    -- Data widths
    constant CFG_PIXEL_WIDTH  : integer := 8;  -- 8-bit unsigned input pixels
    constant CFG_WEIGHT_WIDTH : integer := 8;  -- 8-bit signed kernel weights
    constant CFG_BIAS_WIDTH   : integer := 32; -- 32-bit signed bias
    constant CFG_SHIFT_WIDTH  : integer := 5;  -- Bit width of unsigned shift amounts
    
    -- Accumulator Width: pixel_w + kernel_w + ceil(log2(N^2)) + 1
    -- For N=3: 8 + 8 + ceil(log2(9)) + 1 = 21 bits. 
    -- We round to 24 bits for cleaner DSP/fabric boundaries.
    constant CFG_ACCUM_WIDTH  : integer := 24; 
    
    -- Output feature map width (post-rescale and saturation)
    constant CFG_OUTPUT_WIDTH : integer := 16;

    -- ========================================================================
    -- Derived Pipeline Widths (auto-computed from base constants)
    -- ========================================================================
    
    -- Product width: zero-extended unsigned pixel × signed weight
    -- signed(pixel_w + 1) × signed(weight_w) = signed(pixel_w + weight_w + 1)
    constant CFG_PRODUCT_WIDTH : integer := CFG_PIXEL_WIDTH + CFG_WEIGHT_WIDTH + 1;
    
    -- Extra bits needed per adder-tree level (summing N values adds ceil(log2(N)) bits)
    constant CFG_PSUM_EXTRA_BITS : integer := clog2(CFG_N);
    
    -- Partial-sum width after first adder-tree level (sums of N products)
    constant CFG_PSUM_WIDTH : integer := CFG_PRODUCT_WIDTH + CFG_PSUM_EXTRA_BITS;
    
    -- Full accumulator width: must hold (sum of all N*N products) + (32-bit bias)
    -- product_sum_width = psum_width + psum_extra = 19 + 2 = 21 for N=3
    -- full_width = max(product_sum_width, bias_width) + 1
    -- For N=3: max(21, 32) + 1 = 33 bits
    constant CFG_FULL_ACCUM_WIDTH : integer := max_int(CFG_PSUM_WIDTH + CFG_PSUM_EXTRA_BITS, CFG_BIAS_WIDTH) + 1;

end package config_pkg;

package body config_pkg is

    function max_int(a, b : integer) return integer is
    begin
        if a > b then return a; else return b; end if;
    end function max_int;

    function clog2(n : positive) return natural is
    begin
        if n = 1 then return 0; end if;
        return integer(ceil(log2(real(n))));
    end function clog2;

end package body config_pkg;
