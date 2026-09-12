# Exact CFGLUT5 K=16 convolution

## Result

This branch implements an exact, runtime-programmable 3x3 convolution with all
16 output channels active in parallel.  The convolution engine uses no DSPs and
no BRAMs.  It accepts one valid 3x3 window per clock and emits all 16 channel
results per clock after the four-stage channel pipeline fills.

Project directory:

`C:\Users\Sigma\Desktop\Convlution_Accelerator_K16_CFGLUT5_Exact`

Git branch:

`feature/k16-cfglut5-exact`

## Strategies used

### 1. Exact CFGLUT5 constant-coefficient multipliers

The software-facing format remains nine ordinary signed int8 weights per
channel.  A pixel is split into low and high four-bit radix-16 digits.  Each
digit addresses a truth table for `digit * weight`.  Six CFGLUT5 primitives
produce the 12 signed product bits, using O5 and O6 as two independent outputs.
The second digit bank uses another six CFGLUT5 primitives.  Therefore one tap
uses 12 CFGLUT5 primitives and the complete 9-tap, 16-channel engine uses 1,728.

This is exact for every uint8 pixel and signed int8 weight.  It does not discard
LSBs and does not use an approximate multiplier.

### 2. Runtime truth-table generation from normal AXI weights

The CPU still writes the existing packed coefficient words.  When a write is
accepted, the engine captures its four int8 lanes and generates the CFGLUT truth
table serially.  Each weight takes 32 clocks.  A complete 16 x 9 reload takes
4,608 clocks, or 46.08 microseconds at 100 MHz.

The controller backpressures the next coefficient write until the current LUT
configuration is complete.  No coefficient BRAM and no large coefficient-read
multiplexer are required.  The active weight byte is registered before truth-
table generation, which keeps the dynamic byte-select mux out of the CFGLUT
configuration critical path.

### 3. One fused, column-aware Dadda compressor tree

The 18 radix-16 partial products for a channel enter one signed bit heap instead
of nine separate multipliers followed by a conventional adder tree.  A generated
six-level Dadda schedule compresses only occupied columns.  Each channel uses
183 full compressors and 13 half compressors, mapped to 196 LUT6_2 primitives.
The first three levels are before the S1 register and the last three levels are
before the S2 two-row register.  S3 performs the single final carry-propagate
addition and adds the bias.

This removes repeated sign extension and avoids materializing nine full-width
products and several full-width intermediate sums.

### 4. Width-efficient exact S4 processing

S4 implements the same round-half-up arithmetic by shifting first and adding the
discarded half bit.  Saturation uses sign-extension checks instead of two broad
magnitude comparators.  The numerical result is unchanged, but the logic cone is
smaller and faster.

### 5. Timing isolation outside the convolution pipeline

AXI write address and data must be captured before commit.  AXI-stream input and
output accounting events are also registered before the 32-bit frame counters
and lifecycle logic.  Parameter-complete is derived from the preceding registered
admission bitmap.  These boundaries remove raw SmartConnect/DMA signals from long
control cones.

They do not add a convolution stage and do not reduce convolution throughput.
They add one controller clock to transaction/status observation, including DONE
after the final output beat.  AXI-Lite programming throughput is unchanged because
the interface already has one outstanding write-response slot.

## Pipeline and throughput

1. S1: CFGLUT lookup plus Dadda levels 1 to 3.
2. S2: Dadda levels 4 to 6 and two-row register.
3. S3: final carry-propagate sum plus bias.
4. S4: exact rounding, saturation and optional ReLU.

The channel latency is four clocks.  Initiation interval is one clock.  All 16
channels are evaluated together, so the core produces 16 int16 channel values
for every accepted window after pipeline fill.

## Verification

The XSim regression programs the weights through the same three packed words
used by AXI software, checks 64 windows, completely reloads the physical CFGLUTs
with a second mixed-sign weight set, then checks another 64 windows.  It covers
weights -128 and +127, shift 3, shift 0, signed bias, exact rounding and signed
saturation.  Result:

`Exact CFGLUT5 KCM + fused compressor regression passed` at 7,230 ns.

A second K=16 smoke test programs all 48 packed coefficient words with distinct
per-channel patterns, including -128 and +127, then checks all 16 outputs for
eight consecutive II=1 windows.  Result:

`Exact CFGLUT5 K=16 channel/configuration smoke test passed` at 46,730 ns.

The full Zynq design synthesizes, places and routes successfully for the
XC7Z020-1 at 100 MHz.  The normal `impl_1` run includes post-route
`AggressiveExplore` physical optimization and completes with WNS +0.103 ns,
TNS 0, no setup failures and no hold failures.  The DRC has zero errors.  It
reports one harmless no-routable-load warning and four AXI-DMA BRAM write-mode
advisories.

The Vivado simulation top is set to the passing K=16 smoke test.  The legacy
full-wrapper regression has also been updated for K=16.  It programs and checks
all 16 channels across three complete frames, repeated START, malformed-frame
fault accounting, abort under output backpressure, and reset recovery.  It
reports `CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS` at
217,290 ns.

## Measured resources

All values below are from the final hierarchical reports generated by Vivado
2025.2.

| Scope | Stage | LUTs | FFs | DSPs | RAMB36 | RAMB18 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Complete system | Synthesis | 13,744 | 12,172 | 0 | 2 | 2 |
| Convolution engine | Synthesis | 6,460 | 2,948 | 0 | 0 | 0 |
| Complete system | Routed | 12,995 | 11,721 | 0 | 2 | 2 |
| AXIS accelerator wrapper | Routed | 8,601 | 5,475 | 0 | 0 | 0 |
| Convolution top | Routed | 8,126 | 5,084 | 0 | 0 | 0 |
| Convolution engine | Routed | 6,168 | 2,948 | 0 | 0 | 0 |
| AXI-Lite controller plus parameter regfile | Routed | 1,950 | 2,004 | 0 | 0 | 0 |

The routed system's two RAMB36 and two RAMB18 blocks equal three 36-Kb BRAM tile
equivalents.  They belong to the surrounding DMA/system infrastructure, not the
CFGLUT convolution datapath.  Vectorless estimated total on-chip power is 1.788 W
(1.644 W dynamic and 0.144 W static); it is an estimate, not a measured board
power result.

For the stated FOM, the complete-system weighted resource term is
`12,995 + 50*0 + 100*3 = 13,295`, and the power-weighted denominator is
`1.788*13,295 = 23,771.46`.  At the theoretical II=1 core rate this corresponds
to 4,207 full 16-channel windows/s per weighted W-resource unit, or 67,307
individual channel results/s per weighted W-resource unit.  Use the same
throughput definition and the same power-estimation method for every design when
comparing FOM values.

## Comparison

The previously measured routed exact inferred-multiplier engine used 7,082 LUTs.
This exact CFGLUT engine uses 6,168 LUTs, a reduction of 914 LUTs or 12.9%, with
the same four convolution stages and II=1.

The routed drop-2 approximate engine used 5,399 LUTs.  The exact CFGLUT engine is
769 LUTs or 14.2% larger.  The drop-2 implementation therefore remains the
smallest option if its accuracy loss is acceptable; CFGLUT5 is the better choice
when arithmetic must remain exact.

The whole-system total fell from the earlier exact inferred implementation's
19,162 LUTs to 12,995 LUTs.  Do not attribute that entire difference to CFGLUT5:
the new result also includes the direct write-through configuration path, removal
of the old coefficient selection structure, exact S4 simplification, and control-
path timing isolation.  The engine-only comparison is the more useful measure of
the convolution architecture.

The supplied older Winograd CSV reports roughly 27,780 LUTs in the 16 lanes plus
5,124 LUTs in its raster reorder block, and setup WNS -0.927 ns.  That result is
not a like-for-like baseline for this branch, but it confirms why the narrower
direct 3x3 products are a better fit for this FPGA and data width.

## Reproducibility

- `scripts/generate_cfglut_bitheap.py` regenerates the structural Dadda tree.
- `scripts/synth_cfglut_engine.tcl` runs out-of-context engine synthesis.
- `scripts/rebuild_cfglut_project.tcl` rebuilds the full synthesis checkpoint and
  writes hierarchical reports.
- `scripts/implement_cfglut_project.tcl` places, routes and writes timing,
  utilization, power and DRC reports.  It enables post-route physical
  optimization and fails explicitly if the final WNS is negative.
- `scripts/run_k16_wrapper_regression.tcl` runs and checks the complete K=16
  AXI/full-wrapper regression while restoring the previous simulation top.
- `Convlution_Accelerator.srcs/sim_1/new/tb_cfglut5_exact.vhd` is the exactness
  and runtime-reload regression.
- `Convlution_Accelerator.srcs/sim_1/new/tb_cfglut5_k16_smoke.vhd` verifies all
  channel addresses and all 16 parallel results.

## Current integration limitation

The RTL configuration is N=3, K=16 in `config_pkg.vhd`.  The copied software
metadata, golden model and deployed model artifacts still identify K=8 and refer
to the older frozen bitstream.  They must not be used unchanged with this K=16
experimental hardware.  Updating them requires a real 16-channel trained model,
then regenerating the expected output sizes, build identity, bitstream/XSA hashes
and deployment artifacts.  No synthetic extra channels were invented here.
