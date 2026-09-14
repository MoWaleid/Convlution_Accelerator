# Profile-matrix wrapper simulations — 2026-09-14 (CFGLUT125 releases)

Status: **engineering verification complete for all five releases; official
user-executed transcripts and physical builds follow.** Fixture: the A-H
comprehensive wrapper regression (`sim_1/imports/new/tb_conv_axis_wrapper.vhd`,
generalized 2026-09-14 to take all geometry from config_pkg), run per release
against the rendered `work/research_<ID>/src/config_pkg.vhd` in isolated
Vivado 2025.2 projects, VHDL-2008, 8 ns clock (125 MHz).

## Results

| Release | N / K / W×H | Variant | Frames A-H | Frame D invalid_advances | Frame D output gaps | Verdict |
|---|---|---|---|---:|---:|---|
| B32_CFGLUT125 | 3 / 16 / 32×32 | optimized (strict) | PASS | 0 | 0 | **PASS — gapless claim PROVEN** |
| A32_CFGLUT125 | 3 / 8 / 32×32 | optimized (strict) | PASS | 0 | 0 | **PASS — gapless claim PROVEN** |
| C32_CFGLUT125 | 5 / 8 / 32×32 | optimized_relaxed | PASS | 62 | 31 | PASS functional; zero-bubble NOT proven |
| D32_CFGLUT125 | 3 / 4 / 32×32 | optimized_relaxed | PASS | 62 | 62 | PASS functional; zero-bubble NOT proven |
| D640_CFGLUT125 | 3 / 4 / 640×480 | optimized_relaxed | PASS | 958 | 958 | PASS functional; zero-bubble NOT proven |

Frame C/H values for C32: invalid_advances 32 / 42 under output
backpressure; frame D (guaranteed supply, continuously ready sink) shows 62
invalid advances and 31 external output gaps = one bubble per logical row
transition (31 transitions). D32 frame D: 62 invalid advances and 62 output
gaps (two per transition at one beat per position). D640 frame D: 958/958
over 307,200 output beats (479 transitions, ~0.31% of frame cycles). The
bubble overhead on frame throughput is therefore ~1.5% (C32), ~6% (D32) and
~0.3% (D640) of external output beats. All mismatches checked per scalar
against the in-TB reference; frame data is bit-exact in every run — the
gapless assertion is the only failing check for C32/D32.

## Fixture bugs found and fixed by this campaign (both testbench-side)

1. **Duplicated final input beat** (all profiles): the frame-sender
   generalization left the original unconditional trailing
   `send_input_beat(x"0F", TLAST)` in place after adding the conditional
   trailing-beat block, so every frame carried a second TLAST beat. The DUT
   completed each frame correctly and gated further input; the TB hung on
   the rejected beat. Diagnosed by beat-level instrumentation (146 sent /
   145 accepted); fixed in the TB, verified against the pre-edit TB
   (commit `8dd1d31`).
2. **Untruncated reference pixels at 640-wide** (D640 only): the fixture's
   `pixel(r,c) = r+c` reaches 643 at 640-wide padding, overflowing the 8-bit
   pixel. The byte stream truncates to 8 bits but the reference summed the
   unbounded integers, so position 252 expected 2286 vs the DUT's correct
   2030 (one pixel contributing 256 truncated to 0). Fixed by applying
   `mod 256` in `input_pixel_value` so the reference and the byte stream
   always agree. Not reachable at 32-wide profiles (max value 68).
   The DUT was bit-exact against its actual input stream in both cases; no
   datapath change was required for either bug.

## Edge-free zero-bubble claim scope — user decision 2026-09-14 (option a)

The zero-bubble output property ("one position per clock once filled,
including edges") is **proven for N=3 with K>=8 only** (B32_CFGLUT125,
A32_CFGLUT125). For K=4 (D32, D640) and N=5 (C32), engine bubbles at row
transitions surface externally on the continuous-sink benchmark; measured
overhead is one to two cycles per logical row transition (31 transitions per
32-row frame, ~3% of frame cycles; proportionally negligible for D640).

Working explanation (analysis consistent with all data points, not
cycle-proven): the window generator's valid drops for the first N-1 pixels
of each padded row; the prefetch/serializer slack hides those holes when the
output path carries >=2 beats per position (K>=8 at N=3), but not at one
beat per position (K=4) and not for N=5's wider hole.

Per the user's decision, the five-release package freezes with the gapless
claim attached to A32/B32 only; C32/D32/D640 are released as exact datapaths
with these measured transition bubbles documented, and the claim for those
shapes waits on a window-generator redesign (produce valid windows on
transition pixels). Correctness, framing, counters, backpressure tolerance,
fault/abort/recovery (frames A-H minus the zero-gap assert) pass for all
five geometries.

## Boundary

These are AI-driven batch xsim runs on the Windows workstation (logs under
`work/debug_wrapper_<ID>/`). The official Gate-3 wrapper-sim evidence is the
user-executed run of `scripts/research_release/test_profile_wrappers.tcl`
per release (B32/A32 `optimized`; C32/D32/D640 `optimized_relaxed`), whose
transcripts are recorded alongside the physical-build evidence. Board-level
correctness (anchors, soaks, extremes) is a separate, already-proven axis
for B32 and follows for the other releases after their builds.
