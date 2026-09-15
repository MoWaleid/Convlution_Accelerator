# FPGA CNN Convolution Accelerator for Edge-AI Vision

**Team submission — IEEE SSCS Egypt 2026 Student Design Competition**
Target platform: Digilent ZedBoard (Xilinx Zynq-7020 XC7Z020CLG484-1) · Toolchain: AMD/Xilinx Vivado 2025.2 · RTL: VHDL-2008

> **Source-index convention:** every numeric claim in this report carries a citation
> `[S#]` resolving to the Source Index (§13). All cited files are in the submission
> package or the project repository. No value in this report is assumed; derivations
> are marked "(derived)" and show their inputs.

---

## 1. Introduction

This report presents a fixed-point NxN convolution accelerator family for the
first convolutional layer (Conv1) of a grayscale CNN, implemented on a Xilinx
Zynq-7020 SoC and **qualified on physical silicon as five compiled hardware
releases**: N=3 with 4, 8 or 16 channels at 32×32, N=5 with 8 channels at
32×32, and N=3 with 4 channels at 640×480 [S25]. The compute datapath is an
**exact CFGLUT5 Dadda-compressor architecture**: every 8×8 tap product is
produced by runtime-configurable LUT multipliers and reduced by a generated,
column-aware Dadda bit heap with an exact sum, so the result is bit-identical
to an arbitrary-precision golden model for every input, coefficient set, shift
and rounding case [S10], [S33]. Images stream over AXI4-Stream through an AXI
DMA at a 125 MHz fabric clock; results stream back as signed 16-bit feature
maps.

The complete hardware-software system — five releases, runtime full-FPGA
reconfiguration between them, and the embedded Linux operation stack — has been
qualified on the ZedBoard: **577 new bit-exact frames in the final
qualification campaign with zero mismatches** (per-release anchor activations,
60 exact-reference extreme frames, five 100-frame soaks), a 58-switch
five-profile matrix covering all 20 ordered release pairs, a true power-cycle
cold boot, and hardware fault-injection with clean recovery [S26]. Together
with the predecessor datapath's 1,966 recorded frames (§8.4), the platform
total is **2,543 transcript-recorded bit-exact frames across 50+ runs**.

The work was performed against the competition specification [S12]: minimum
32×32 grayscale input, unsigned fixed-point pixels, programmable 8-bit signed
kernels, stride 1, ≥16-bit signed outputs, golden-model verification, and
reporting of utilization, timing, latency, throughput, power, and Figure of
Merit. §9 gives the required results table for every release, ranked by FOM.

## 2. System architecture

The block design (`accelerator_dma`) instantiates:

- **Zynq PS7** — Cortex-A9 dual-core, DDR3 controller, and the AXI interfaces
  (M_AXI_GP0 control plane, S_AXI_HP0 high-throughput memory port).
- **AXI DMA** — simple mode (no scatter-gather), 64-bit on both memory sides,
  22-bit transfer-length configuration, no datatype re-alignment (DRE) [S10: BD + scripts/create_accelerator_dma_bd.tcl].
- **The accelerator** — a module reference wrapping the VHDL design (§3), exposed
  as AXI4-Lite slave + one 64-bit AXI4-Stream slave (pixels in) + one 64-bit
  AXI4-Stream master (results out).
- **Two AXI SmartConnects** (control and HP0), **proc_sys_reset**, and a single
  125 MHz clock domain derived from FCLK_CLK0 (SLCR-derived: IO PLL FBDIV=30,
  FPGA0 divisors 4×2 → 124.99999875 MHz, verified on hardware after a cold
  boot) [S26].

Address map (from the scripted BD, reproducible via `scripts/create_accelerator_dma_bd.tcl`
and frozen in the per-release manifests [S9][S32]): DMA `0x40400000`/64 KiB,
accelerator `0x43C00000`/64 KiB, HP0 → DDR `0x00000000`/512 MB.

![Figure 1 — Vivado block-design schematic: PS7, AXI DMA, the accelerator (module reference), two SmartConnects, and the reset infrastructure](figures/fig1_blockdesign.png)

*Figure 1 — Block design `accelerator_dma` in Vivado 2025.2 [screenshot, user capture].*

**Data flow:** PS writes channel parameters and the CVH1 control ABI over AXI4-Lite;
PS arms the DMA S2MM (receive) channel; PS writes TX length to trigger; pixels stream
DMA → accelerator → edge-free window generator → K parallel exact-convolution
channels → output packer → DMA → DDR; PS polls CVH1 status for frame completion and verifies
the received buffer.

## 3. Convolution datapath: the exact CFGLUT5 compressor

### 3.1 Why LUT-based exact multiplication

The competition requires programmable 8-bit signed kernel coefficients. The
design computes each tap product **exactly** by *configuration-as-constant
multiplication*: the 8-bit signed weight is stored as the Boolean configuration
of six Xilinx **CFGLUT5** primitives per radix-16 digit, and the 4-bit pixel
digit addresses that configuration, reading the pre-computed multiplication
table directly out of the LUT. One CFGLUT5, with its I4 input held high,
presents two independent four-input functions in the lower and upper halves of
its 32-bit configuration shift register, so a single primitive returns two bits
of the signed 12-bit digit×weight product [S10: `cfglut5_kcm.vhd`]. Six
primitives per digit bank therefore produce the full 12-bit signed product of
one 4-bit pixel digit by the 8-bit weight; the two digit banks (low and high
nibble) together form the exact 8×8 product with one 4-bit shift-and-add.
Coefficients are reprogrammed at runtime through the CFGLUT5 configuration
chain (six configuration bits per clock, 32 clocks per bank), which is what
makes every kernel in this report programmable without any DSP48 or fabric
multiplier.

### 3.2 Generated Dadda bit-heap compressor

The N² per-channel digit products (2·N² signed rows) enter a **generated,
column-aware Dadda compressor** (`scripts/generate_cfglut_bitheap.py` →
`cfglut5_bitheap_3x3.vhd` / `cfglut5_bitheap_5x5.vhd` [S10], [S33]):

| Entity | Taps / signed rows | Sum width | Dadda targets | Registered boundaries |
|---|---:|---:|---|---|
| `cfglut5_bitheap_3x3` | 9 / 18 | 21 bit | 13, 9, 6, 4, 3, 2 | after level 3 (of 6) |
| `cfglut5_bitheap_5x5` | 25 / 50 | 22 bit | 42, 28, 19, 13, 9, 6, 4, 3, 2 | after levels 3 and 6 (of 9) |

The generator emits 183 full + 13 half compressors for N=3 (LUT6_2 primitives,
two outputs each), compresses **only occupied columns** — avoiding the
sign-extension waste of a uniform-width carry-save array — and produces two
exact partial-sum rows. Both generated entities are deterministic artifacts:
the N=3 output is byte-identical to its original reviewed version
(`ad49b540…27aa7`, [S33]).

### 3.3 Channel pipeline

Each channel (`conv_channel.vhd` [S10]) instantiates one KCM per tap plus the
generated bit heap, then completes the accumulation and post-processing:

| Stage | Function | Width |
|---|---|---|
| BH | CFGLUT digit-lookup product generation + Dadda compression (one registered boundary for N=3, two for N=5) | signed rows → 21/22-bit pair |
| S2 | two-row register (valid-aligned) | 2 × 21/22 bit |
| S3 | sole carry-propagate sum + signed-24 bias | 25-bit accumulator |
| S4 | arithmetic shift + **discarded half-bit register** | exact shift 0..31 |
| S5 | round-half-up increment, saturate to int16, optional ReLU | 16-bit output |

**Exactness at every shift:** S4 registers the bit that the barrel shift is
about to discard, and S5's round-half-up increment consumes it together with
the remaining low bits — the "discarded-bit alternative" of the CVH1 contract.
This makes shifts 24–31 exact, including the signed boundary cases at shift 24
(+1/−1) that a conventional truncated accumulator mis-rounds; the datapath was
qualified on silicon across all 32 shift values [S26], [S33]. The predecessor
MAC datapath (§8.4) restricted shifts to 0–23 for exactly this reason; the
CFGLUT5 architecture removed that restriction by construction.

**Throughput definition** (used consistently for every FOM in this report):
throughput is the number of **valid output values (pixels) per clock cycle**.
The accelerator core produces **one valid result per channel per cycle** once
the pipeline is filled — K outputs per clock cycle (8 at K=8, 16 at K=16,
4 at K=4). The full system is bounded by its output side: the AXI DMA output
interface is a 64-bit bus carrying 4 int16 values per beat
(`axi_stream_output_serializer.vhd` [S10]), so the **full-system throughput is
4 valid outputs per cycle** regardless of K, derated by the disclosed edge
bubbles of §3.4. All measured frame times are host-clock wall-clock intervals
including DMA and polling overhead, reported separately (§9).

### 3.4 Edge-free window generation

`window_generator.vhd` [S10] implements (N−1) SRL-mapped row-delay line buffers
feeding the tap window, with a **prefetch strategy that keeps the channel
pipeline supplied across row transitions**. The five releases expose measured,
disclosed behavior at the frame edges (wrapper-sim record, frame D =
continuously-supplied stress case [S28]):

| Release | Frame-D invalid core advances | External output gaps | Core rate (design) | Full-system sustained rate |
|---|---:|---:|---:|---:|
| B32_CFGLUT125 (3×16) | **0** | **0** | 16 outputs/cycle | 4.000 outputs/cycle (bus ceiling) |
| A32_CFGLUT125 (3×8) | 31 | **0** | 8 outputs/cycle | 4.000 outputs/cycle (bus ceiling) |
| C32_CFGLUT125 (5×8) | 62 | 31 | 8 outputs/cycle | 3.940 outputs/cycle |
| D32_CFGLUT125 (3×4) | 62 | 62 | 4 outputs/cycle | 3.758 outputs/cycle |
| D640_CFGLUT125 (3×4, 640×480) | 958 | 958 | 4 outputs/cycle | 3.988 outputs/cycle |

At K≥8 the output prefetch slack hides the residual transition bubbles entirely
from the external stream (A32: zero external gaps; B32: zero even internally);
at K=4 one beat per position exposes one-to-two bubbles per row transition
(~6% of beats at 32×32, ~0.3% at 640×480), disclosed here and measured in the
simulator record [S28]. Output correctness is unaffected: every delivered
value is bit-exact against the golden model in all five releases.

![Figure 2 — exact CFGLUT5 channel pipeline: KCM digit lookups, generated Dadda bit heap, and S2–S5 post-processing](figures/fig2_pipeline.png)

*Figure 2 — Per-channel pipeline (regenerated for the CFGLUT5 datapath; §C figures). Bit widths are RTL-derived [S10], [S33].*

## 4. Control FSM

The CVH1 control layer (`axi_lite_ctrl.vhd` [S10]) implements a three-state
lifecycle FSM — **IDLE, RUN, FAULT** — with command-encoded transitions:

- **START** (command 1): legal only from IDLE while QUIESCENT, PARAM_COMPLETE and
  zero architectural errors; otherwise SLVERR with BAD_COMMAND_STATE. On acceptance:
  state → RUN, all four transfer counters zero, event flags cleared.
- **RESET** (command 2): legal from IDLE or FAULT while QUIESCENT; clears counters,
  event bits and all error bits while **preserving parameter storage and admission**
  (hardware-verified: the fault-injection round of §8.2 observed STATUS `0x181` —
  parameters retained — across RESET).
- **ABORT** (command 4): legal in any state; forces FAULT and latches ERR_ABORTED.
  Both fault paths (ABORT-from-IDLE and the ABORT-after-START race) were injected
  on hardware and recovered cleanly (§8.2, gate 6) [S26].

Frame completion is self-checking: on the final output beat the hardware requires
the four counters to equal the compiled quotas exactly (input accepted/consumed =
padded frame bytes, core pixels = W·H, output bytes = 2·W·H·K) together with
CORE_COMPLETE, otherwise it latches ERR_INTERNAL and faults [S10: axi_lite_ctrl.vhd,
completion guard]. Sticky events are cleared via EVENT_CLEAR or RESET.

![Figure 3 — CVH1 lifecycle FSM](figures/fig3_fsm.png)

*Figure 3 — Control FSM with START/RESET/ABORT semantics, drawn from `axi_lite_ctrl.vhd` [S10].*

## 5. Memory organization

**Line buffers / window generation** (`window_generator.vhd` [S10]): (N−1) row-delay
line buffers of depth W+N−1 implemented as SRL-mapped shift registers, feeding the
N×N register window with the prefetch strategy of §3.4. The design uses **zero
block RAM** for windowing and the datapath; the only BRAM in the system belongs to
the DMA IP's internal FIFOs (2 RAMB36 + 2 RAMB18 in every release) [S32].

**DMA buffer layout** (`software/m7_switch.py` `compute_layout`; manifests
`software/hardware_<ID>_CFGLUT125.json` [S9][S32]): a physically contiguous u-dma-buf
allocation (4 MiB at 0x1F100000, sync_mode 1) is partitioned per compiled release by
the approved formula TX at +0x1000, RX at `ALIGN_UP(0x1000 + TX_BYTES + 2·G, 64)` with
G = 64 — giving RX at +5440 (A32/B32/D32), +5568 (C32) and +313728 (D640 at 640×480) —
with **four** 64-byte 0xA5-filled guard regions (leading and trailing on both TX and
RX). All transfer lengths are bounded by the 22-bit DMA length field and the
runtime-discovered allocation, RX DMA capacity is exactly the RX byte count,
and all four guards are rewritten and verified after every transfer to prove
the DMA wrote exactly its length. D640 exercises the full 4 MiB layout with
2,457,600-byte output frames [S26].

## 6. Fixed-point arithmetic

Per channel: `acc = bias + Σ pixel·weight` (exact Dadda-compressed sum, no
truncation), then arithmetic shift by the per-channel 5-bit shift with the
discarded half-bit retained (§3.3), round-half-up
(`acc += 2^(shift-1); acc >>= shift`), saturation to signed int16, and an optional
per-channel ReLU clamp [S10: conv_channel.vhd; S13: golden_conv.py].

**Bit-width derivation** (design analysis, RTL `config_pkg.vhd` + generated
entities [S10], [S33]): a product of unsigned 8-bit × signed 8-bit needs 17 bits
signed; the digit-LUT form produces two signed 12-bit radix-16 partial products
whose combination is exact by construction. The N=3 bit heap reduces 18 signed
rows to a 21-bit exact pair (max |Σ| = 9·255·128 = 293,760 < 2^19, one sign
bit of margin); N=5 reduces 50 rows to 22 bits (25 taps). The signed-24 bias
dominates, so the accumulator is max(sum, 24) + 1 = **25 bits**
(`CFG_BIAS_WIDTH = 24`).

The identical arithmetic is implemented three independent times and compared:
(1) the RTL; (2) an arbitrary-precision Python golden model
(`golden_model/golden_conv.py` [S13]); (3) an independent test oracle in the
software stack. The golden model was anchored to trained networks: a grayscale
CIFAR-10 CNN trained for 50 epochs reaching **68.15% test accuracy** (K=8,
`golden_model/data/training_log.txt` [S11]) and a retrained K=16 network at
**70.08%** / N=5 network at **67.72%** [S13]. Quantized weights (int8, per-channel
fraction bits = 8), int32 biases and shifts populate the canonical parameter
bundles per release [S9].

Stimulus coverage on silicon includes the trained configurations, the
hand-authored D-filter set (identity / Sobel-X / Sobel-Y / 4× box-blur, ReLU off
on the Sobels so signed outputs remain visible), all-zero and all-255 inputs,
both saturation rails, signed-24 bias endpoints and every shift 0–31 [S26].

## 7. Control ABI and identity

The accelerator exposes a 64-channel parameter space (each channel: packed 8-bit
coefficients, bias at +0xF8, shift/ReLU control at +0xFC) and a global CVH1 block at
0x4100: MAGIC `0x43564831`, ABI_VERSION 1.0, CAPABILITIES, STATUS (state + event
bits), COMMAND (START/RESET/ABORT), EVENT_CLEAR, ERROR_FLAGS, geometry/width
discovery registers, four live transfer counters, a 128-bit BUILD_ID and the
DMA length-width capability [S10:
axi_lite_ctrl.vhd; S9]. The companion register map and channel layout are given in
Appendix A. Each compiled release carries its own frozen BUILD_ID (§9); software
validates MAGIC, ABI version, capabilities, BUILD_ID, geometry and DMA
length width against the selected release's manifest **before any parameter
write** and rejects mismatches — a rule the
platform itself enforces: a deliberately illegal access from userspace escalates to
a PS external abort (SIGBUS), i.e. the system fails stop [recorded 2026-09-12,
see AI_HANDOFF.md §12].

## 8. Verification and results

### 8.1 Simulation

- **Exact datapath regressions for both generated geometries**
  (`tb_cfglut5_exact`, `tb_cfglut5_pipeline`, `tb_cfglut5_exact_n5`,
  `tb_cfglut5_pipeline_n5` [S33]): nonzero exact 3×3 and 5×5 convolution,
  runtime coefficient reload, signed-24 bias, **all 32 shift values**, both ReLU
  modes, saturation boundaries, CE stalls, valid latency and in-flight reset
  flushing — 5,120 (N=3) and 6,144 (N=5) output comparisons, all PASS
  (`CFGLUT_GEOMETRY_REGRESSION_PASS`, Vivado 2025.2).
- **Five-release wrapper regression** (`tb_conv_axis_wrapper`, generalized to
  N∈{3,5} × K∈{4,8,16}) [S28]: the full A–H framing/backpressure/lifecycle
  suite executed officially per release from a clean, commit-bound state —
  all five PASS with the exact per-release edge metrics of §3.4
  (`wrapper_official_user_20260914T210835Z`, 16/16 checksums verified).
- Legacy regressions (bit-exact datapath, AXI protocol, window generator,
  register file, frontend, serializer): all PASS [S4].

![Figure 5 — behavioral simulation waveform of the streaming wrapper regression](figures/fig5_waveform.png)

*Figure 5 — XSim waveform of `tb_conv_axis_wrapper` [screenshot, user capture]: AXI-Stream
input bursts (`s_axis_*`, TKEEP) and packed result beats (`m_axis_*`) with TLAST,
under live backpressure. (Captured on the predecessor datapath build; the
five-release CFGLUT5 wrapper regression passes the same fixture — per-release
metrics in [S28].)*

### 8.2 Physical silicon evidence

All runs on the ZedBoard through the full PS→DDR→DMA→accelerator path. The
**final qualification campaign (G5, 2026-09-15)** ran the five qualified
releases end-to-end [S26]; every run below is transcript-recorded and the
structured run records are preserved with hashes [S27]:

| Gate | Coverage | Result |
|---|---|---|
| 1. Per-release identity + anchor activation (full-PL reload, 3 frames each) | 15 frames, 5 reloads | **PASS** — anchor-exact on every activation, cleanup `0x181` |
| 2. Numerical extremes (12 exact-reference frames ×5 releases) | 60 frames | **PASS** — all-zero, all-255, both saturation rails, signed-24 endpoints, shifts 24–31, reinstall+revalidation; zero mismatches |
| 3. 100-frame no-reset soaks ×5 | 500 frames | **PASS** — 100% bit-exact, medians 0.123–0.126 ms (32×32) and 3.731 ms (640×480) |
| 4. Five-profile switching matrix | 58 switches / 58 full-PL reloads | **PASS** — all 20 ordered pairs, 20 provably consecutive A32↔B32 cycles, 58.5 s |
| 5. True power-cycle cold boot | persistence + 125 MHz SLCR + fresh anchor | **PASS** — 68 runtime files and 5 firmware images cmp-identical |
| 6. Bounded fault injection + recovery | ABORT-from-IDLE, ABORT-after-START race | **PASS** — FAULT latched (ABORTED alone), clean RESET recovery, anchor-exact proof frames |

**Campaign total: 577 bit-exact frames, zero mismatches**, every switch a
verified full-PL reload of the frozen firmware set. Combined with the
predecessor datapath's recorded history (§8.4), the platform total is
**2,543 bit-exact frames across 50+ runs and 200+ verified full-PL
reconfigurations**.

The per-record verification scope note is embedded in every record: timing
values are host-clock intervals including polling; the declared fabric clock is
125 MHz; neither is a hardware cycle count. Board run-ids carry 2018 stamps
from the dead RTC — they are identifiers, not chronology.

### 8.3 Edge-detection demonstration

The five releases include hand-authored D-profile kernels (identity / Sobel-X /
Sobel-Y / 4× box-blur), and the platform renders Sobel-magnitude maps from
hardware output on the embedded Linux side. The render below was computed
on-silicon from a 32×32 test image over the DMA path:

![Figure 4 — Sobel magnitude map computed by the accelerator on silicon](../debug_captures/m3_demo_sobel_mag_aeroplane_view.png)

*Figure 4 — Board-computed Sobel magnitude map (aeroplane test image), rendered from hardware output retrieved over the serial console (`debug_captures/m3_demo_sobel_mag_aeroplane_view.png`; captured on the predecessor build — the qualified D32/D640 releases implement the identical filter set and were anchor-qualified bit-exact [S26]).*

### 8.4 Predecessor datapath record (historical)

Before the CFGLUT5 datapath, the platform's MAC-array datapath (LUT
multipliers + 4-stage adder-tree pipeline, 100 MHz) accumulated **1,966
transcript-recorded bit-exact frames across 35+ runs** — including a
1,000-frame varied soak, five physical power-cycle boots, a 103-frame M5
qualification and the full profile-switching campaign [S5]–[S8], [S16]–[S24].
That datapath is superseded by the exact CFGLUT5 architecture of §3 (its shift
24–31 rounding restriction is removed there by construction); its results are
retained as historical evidence and as the baseline of the architecture
comparison in §11.

## 9. Implementation results (XC7Z020CLG484-1, Vivado 2025.2)

All five releases are routed, DRC-clean, timing-clean builds from the same
generalized RTL source set — every routed artifact is hash-bound in its
source-bound build manifest [S32], and the five firmware images the board
actually executed are the Bootgen products of exactly these bitstreams
[S30]. Per-release routed results (full system = PS + DMA + SmartConnects +
accelerator; core = `conv_axis_wrapper` accelerator hierarchy):

| Release | WNS / WHS (ns) | Failing endpoints | LUTs (sys / core) | FFs (sys / core) | BRAM | DSP | Power (sys / core, W) |
|---|---|---|---|---|---|---|---|
| D32_CFGLUT125 | +0.093 / +0.014 | 0 / 0 | 7,273 / 2,883 | 8,308 / 2,062 | 3 | **0** | 1.768 / 0.015 |
| D640_CFGLUT125 | +0.001 / +0.022 | 0 / 0 | 7,679 / 3,281 | 8,940 / 2,694 | 3 | **0** | 1.769 / 0.017 |
| A32_CFGLUT125 | +0.197 / +0.037 | 0 / 0 | 9,145 / 4,746 | 9,758 / 3,512 | 3 | **0** | 1.785 / 0.028 |
| B32_CFGLUT125 | +0.090 / +0.053 | 0 / 0 | 12,670 / 8,274 | 12,686 / 6,440 | 3 | **0** | 1.806 / 0.049 |
| C32_CFGLUT125 | +0.003 / +0.037 | 0 / 0 | 14,162 / 9,764 | 13,934 / 7,688 | 3 | **0** | 1.823 / 0.065 |

Every release meets "All user specified timing constraints are met" at the
125 MHz constraint (routing errors = 0, DRC errors = 0, methodology checks = 0;
per-release reports preserved and hash-bound [S32]). Maximum frequency is
≥125 MHz by constraint closure; deriving from WNS gives Fmax ≈ 126.5 MHz
(D32) down to ≈ 125.0 MHz (D640).

![Figure 6 — implemented device view](figures/fig6_deviceview.png)

*Figure 6 — Placed design on the XC7Z020 [screenshot, user capture, predecessor build]: the
repeating per-channel structure is visible in the fabric; the PS occupies the
die center-left by construction.*

### 9.1 Competition results tables — one per release, ranked by FOM

The competition's Table 1 is given per release, ordered by full-system FOM
(§11 defines the two scopes: accelerator core at the design rate of K valid
outputs/cycle, full system at the 64-bit-bus limit of 4 valid outputs/cycle
derated by disclosed gaps; [S29] is the reproducible generator). The
"Specification" column is the competition requirement [S12]; the "Team Result"
column is this release.

#### Rank 1 — D640_CFGLUT125 (N=3, K=4, 640×480)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32, grayscale | 32×32 | px | single-channel; larger sizes supported (D640: 640×480) |
| Input precision | unsigned fixed-point, justified | unsigned 8-bit Q0.8 (value/256) | — | §6: quantized trained networks; digit-LUT addressing needs unsigned pixels |
| Kernel precision | 8-bit signed | signed 8-bit weights · signed-24 bias · 5-bit shift | — | runtime-programmable via CFGLUT5 configuration |
| Architecture type | — | exact CFGLUT5 Dadda-compressor datapath, 4 parallel channels, edge-free window generation with prefetch, AXI-Stream I/O, CVH1 control | — | §3 |
| Multipliers / MACs | — | 36 exact LUT multipliers (4 ch × 9 taps), **0 DSP** | — | 12 CFGLUT5 primitives per multiplier |
| Pipeline stages | — | 5 named stages (BH, S2–S5); Dadda tree adds 1 registered internal boundary at N=3 | — | §3.3 |
| Latency | — | 0.125 ms measured frame median (host-clock, 100-frame soak); 1,024-beat streaming floor ≈ 8.19 µs (derived) | — | [S26], [S27] |
| Throughput | — | core: **4 valid outputs/cycle** (design rate); full system: **3.758 valid outputs/cycle** sustained — bus limit 4/beat derated ~6% by disclosed edge bubbles | outputs/cycle | §3.3–3.4, [S28] |
| FPGA utilization | — | full system 7,273 LUT (13.7%), 8,308 FF, 3 BRAM, **0 DSP**; core 2,883 LUT, 2,062 FF, 0 BRAM, 0 DSP | — | [S32] |
| Maximum frequency | — | 125 MHz met, WNS +0.093 ns (Fmax ≈ 126.5 MHz derived) | MHz | [S32] |
| Power estimate | — | 1.768 W full system (core block 0.015 W), Vivado vectorless | W | [S32] |
| Verification status | golden-model comparison | bit-exact: 115 frames this release (singles + 60-frame shared extremes + 100-frame soak), zero mismatches; exact to all 32 shifts | — | [S26], [S27] |
| FOM | — | accelerator core **9.25×10⁻²** · full system **2.81×10⁻⁴** | — | §11, [S29] |

#### Rank 2 — D32_CFGLUT125 (N=3, K=4, 32×32)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32, grayscale | **640×480** | px | largest supported release; same D-filter set |
| Input precision | unsigned fixed-point, justified | unsigned 8-bit Q0.8 | — | §6 |
| Kernel precision | 8-bit signed | signed 8-bit weights · signed-24 bias · 5-bit shift | — | byte-identical bundle to D32 |
| Architecture type | — | exact CFGLUT5 Dadda-compressor datapath, 4 parallel channels, edge-free window generation with prefetch | — | §3 |
| Multipliers / MACs | — | 36 exact LUT multipliers (4 ch × 9 taps), **0 DSP** | — | §3.1 |
| Pipeline stages | — | 5 named stages (BH, S2–S5) | — | §3.3 |
| Latency | — | 3.731 ms measured frame median (host-clock, 100-frame soak); 307,200-beat streaming floor ≈ 2.458 ms (derived) | — | [S26], [S27] |
| Throughput | — | core: **4 valid outputs/cycle** (design rate, pipeline filled); full system: **3.988 valid outputs/cycle** sustained — the 64-bit output bus carries 4 int16/beat, derated ~0.3% by disclosed edge bubbles | outputs/cycle | §3.3–3.4, [S28] |
| FPGA utilization | — | full system 7,679 LUT (14.4%), 8,940 FF, 3 BRAM, **0 DSP**; core 3,281 LUT, 2,694 FF | — | [S32] |
| Maximum frequency | — | 125 MHz met, WNS +0.001 ns | MHz | [S32] |
| Power estimate | — | 1.769 W full system (core block 0.017 W), Vivado vectorless | W | [S32] |
| Verification status | golden-model comparison | bit-exact: 115 frames this release incl. actual 640×480 frames and the recorded LANCZOS input preprocessing (hash-anchored) | — | [S26], [S27] |
| FOM | — | accelerator core **7.17×10⁻²** · full system **2.83×10⁻⁴** | — | §11, [S29] |

#### Rank 3 — A32_CFGLUT125 (N=3, K=8, 32×32)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32, grayscale | 32×32 | px | trained-CIFAR10 K8 parameters |
| Input precision | unsigned fixed-point, justified | unsigned 8-bit Q0.8 | — | §6 |
| Kernel precision | 8-bit signed | signed 8-bit weights · signed-24 bias · 5-bit shift | — | §6 |
| Architecture type | — | exact CFGLUT5 Dadda-compressor datapath, 8 parallel channels, edge-free window generation with prefetch | — | §3 |
| Multipliers / MACs | — | 72 exact LUT multipliers (8 ch × 9 taps), **0 DSP** | — | §3.1 |
| Pipeline stages | — | 5 named stages (BH, S2–S5) | — | §3.3 |
| Latency | — | 0.126 ms measured frame median (host-clock, 100-frame soak); 2,048-beat streaming floor ≈ 16.38 µs (derived) | — | [S26], [S27] |
| Throughput | — | core: **8 valid outputs/cycle** (design rate); full system: **4.000 valid outputs/cycle** sustained — bus-limited (4 int16/beat), zero external output gaps (internal transition bubbles hidden by prefetch) | outputs/cycle | §3.3–3.4, [S28] |
| FPGA utilization | — | full system 9,145 LUT (17.2%), 9,758 FF, 3 BRAM, **0 DSP**; core 4,746 LUT, 3,512 FF | — | [S32] |
| Maximum frequency | — | 125 MHz met, WNS +0.197 ns (Fmax ≈ 126.7 MHz derived) | MHz | [S32] |
| Power estimate | — | 1.785 W full system (core block 0.028 W), Vivado vectorless | W | [S32] |
| Verification status | golden-model comparison | bit-exact: 115 frames this release, zero mismatches | — | [S26], [S27] |
| FOM | — | accelerator core **6.02×10⁻²** · full system **2.37×10⁻⁴** | — | §11, [S29] |

#### Rank 4 — C32_CFGLUT125 (N=5, K=8, 32×32)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32, grayscale | 32×32 | px | N=5 25-tap kernel — beyond the 3×3 baseline |
| Input precision | unsigned fixed-point, justified | unsigned 8-bit Q0.8 | — | §6 |
| Kernel precision | 8-bit signed | signed 8-bit weights · signed-24 bias · 5-bit shift | — | retrained N=5 network, 67.72% |
| Architecture type | — | exact CFGLUT5 Dadda-compressor datapath, 8 parallel channels, edge-free window generation with prefetch | — | §3 |
| Multipliers / MACs | — | 200 exact LUT multipliers (8 ch × 25 taps), **0 DSP** | — | 50-row Dadda heap per channel |
| Pipeline stages | — | 5 named stages (BH, S2–S5); Dadda tree adds a second registered boundary | — | §3.3 |
| Latency | — | 0.124 ms measured frame median (host-clock, 100-frame soak); 2,048-beat streaming floor ≈ 16.38 µs (derived) | — | [S26], [S27] |
| Throughput | — | core: **8 valid outputs/cycle** (design rate); full system: **3.940 valid outputs/cycle** sustained — bus-limited, derated ~1.5% by disclosed edge bubbles | outputs/cycle | §3.3–3.4 |
| FPGA utilization | — | full system 14,162 LUT (26.6%), 13,934 FF, 3 BRAM, **0 DSP**; core 9,764 LUT, 7,688 FF | — | [S32] |
| Maximum frequency | — | 125 MHz met, WNS +0.003 ns | MHz | [S32] |
| Power estimate | — | 1.823 W full system (core block 0.065 W), Vivado vectorless | W | [S32] |
| Verification status | golden-model comparison | bit-exact: 115 frames this release, zero mismatches | — | [S26], [S27] |
| FOM | — | accelerator core **1.26×10⁻²** · full system **1.49×10⁻⁴** | — | §11, [S29] |

#### Rank 5 — B32_CFGLUT125 (N=3, K=16, 32×32)

| Parameter | Specification | Team Result | Units | Comments |
|---|---|---|---|---|
| Input image size | ≥ 32×32, grayscale | 32×32 | px | 16 parallel channels — the edge-free showcase |
| Input precision | unsigned fixed-point, justified | unsigned 8-bit Q0.8 | — | §6 |
| Kernel precision | 8-bit signed | signed 8-bit weights · signed-24 bias · 5-bit shift | — | retrained K16 network, 70.08% |
| Architecture type | — | exact CFGLUT5 Dadda-compressor datapath, 16 parallel channels, edge-free window generation with prefetch | — | §3 |
| Multipliers / MACs | — | 144 exact LUT multipliers (16 ch × 9 taps), **0 DSP** | — | §3.1 |
| Pipeline stages | — | 5 named stages (BH, S2–S5) | — | §3.3 |
| Latency | — | 0.123 ms measured frame median (host-clock, 100-frame soak); 4,096-beat streaming floor ≈ 32.77 µs (derived) | — | [S26], [S27] |
| Throughput | — | core: **16 valid outputs/cycle** (design rate); full system: **4.000 valid outputs/cycle** sustained — bus-limited, **zero gaps, zero internal invalid advances** | outputs/cycle | §3.3–3.4, [S28] |
| FPGA utilization | — | full system 12,670 LUT (23.8%), 12,686 FF, 3 BRAM, **0 DSP**; core 8,274 LUT, 6,440 FF | — | [S32] |
| Maximum frequency | — | 125 MHz met, WNS +0.090 ns | MHz | [S32] |
| Power estimate | — | 1.806 W full system (core block 0.049 W), Vivado vectorless | W | [S32] |
| Verification status | golden-model comparison | bit-exact: 115 frames this release, zero mismatches; release first board-qualified in the predecessor campaign and re-qualified on the rebuild | — | [S25], [S26] |
| FOM | — | accelerator core **3.95×10⁻²** · full system **1.71×10⁻⁴** | — | §11, [S29] |

**Cross-release observation:** the FOM ranking is set by the K·N² LUT cost of
the exact-compressor datapath, while the full-system ranking additionally
rewards clean external streaming — D640 edges ahead of D32 because its
edge bubbles are proportionally smaller (0.31% vs 6.15% of output beats).
Every release keeps the DSP term at zero and BRAM at the DMA's 3 blocks. The
K=16 release trades FOM for channel parallelism (16 valid outputs/cycle core
rate) and is the release where edge-free operation is proven with zero
internal invalid advances.

## 10. Runtime reconfiguration and multi-release operation

The platform reprograms the complete FPGA fabric at runtime from embedded Linux
through the Zynq FPGA Manager: each switch validates the live BUILD_ID first; a
mismatch triggers the full sequence (quiesce → detach → FPGA-Manager reload →
reattach with identity re-validation and stale-state proof → parameter
installation with readback → anchor-checked activation frame), while a match
takes the parameter-only path [S19], [S26]. The active catalog contains exactly
the five qualified releases [S31]; legacy 100 MHz/MAC entries are inadmissible.

G5 qualification evidence [S26]: the 58-switch matrix (all 20 ordered pairs,
20 provably consecutive A32↔B32 cycles, every activation anchor-exact), a true
power-cycle cold boot with byte-exact persistence of all 68 runtime files and
5 firmware images plus SLCR-verified 125 MHz, and hardware fault injection
(ABORT-from-IDLE and ABORT-after-START race) with clean RESET recovery and
anchor-exact proof frames. Combined with the predecessor campaigns, **200+
full-PL reconfigurations are on record**. Incompatible geometry is admitted
only with explicit recorded preprocessing — D640's LANCZOS resize of the
library image (hash-recorded in `profiles/anchors_m7.json`) is such a record;
D640 frames are validated per frame against their frozen golden-output SHA-256.

## 11. Design trade-offs and Figure of Merit

- **Exact LUT multiplication vs DSP48:** all multiplication is performed by
  CFGLUT5 configuration lookup — the routed design contains **0 DSP blocks in
  every release**, keeping the FOM's DSP term at zero. The cost is LUT count
  (worst case 14,162 LUT, 26.6%, for the 25-tap K=8 release [S32]).
- **Exactness by construction:** the generated Dadda heap compresses to an
  exact sum (no truncation before the bias), and the discarded-bit shift path
  makes all 32 shifts exact — a deliberate architecture change that removed
  the predecessor's shift restriction (§3.3, [S33]).
- **Zero-BRAM datapath:** SRL line buffers and LUT-based windowing keep BRAM
  at the DMA FIFOs only (3 RAMB36-equivalents system-wide, identical in all
  five releases [S32]).
- **Edge-free with disclosed bubbles:** output prefetch hides row-transition
  bubbles at K≥8 (A32/B32 external gapless); the K=4 releases expose ~6%
  (32×32) / ~0.3% (640×480) transition bubbles, disclosed and measured
  [S28] rather than claimed away.
- **Fail-stop error architecture:** illegal accesses are rejected with SLVERR in
  RTL (qualified in simulation); from userspace the platform escalates them to a
  process-fatal abort, so the software contract "validate before write" is enforced
  by construction. Hardware fault paths were injected and recovered on the
  qualified releases (§8.2 gate 6).
- **Self-checking frame completion:** the hardware faults itself if the transfer
  counters do not exactly match the compiled frame quotas at TLAST.

**Figure of Merit** (competition formula [S12]):
FOM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs)), with throughput in
**valid output values per clock cycle**, reported at two scopes:

- **Accelerator FOM** — the contest deliverable hierarchy. Throughput is the
  design rate of the exact datapath: **one valid result per channel per cycle,
  K outputs/cycle** (16/8/4), demonstrated with zero invalid core advances at
  B32 and zero external gaps at A32/B32. Resources and power are the
  accelerator core's own (conv_axis_wrapper hierarchy).
- **Full-system FOM** — the delivered system as shipped in the bitstream.
  Throughput is limited by the 64-bit AXI DMA output bus, which carries
  **4 int16 values per beat = 4 valid outputs/cycle** regardless of K, derated
  by the disclosed row-transition gaps; resources and power are the full
  routed system's.

Power is the Vivado **vectorless** routed estimate (no activity factors
measured); BRAM counts RAMB36-equivalents (3). Reproducible generator:
`scripts/packaging/fom_table.py` [S29].

| Rank | Release | Core throughput | System throughput | Power core / sys (W) | LUTs core / sys | DSP | BRAM | FOM (accelerator) | FOM (full system) |
|---|---|---|---:|---:|---:|---:|---:|---:|---:|
| 1 | D640_CFGLUT125 | 4/cycle | 3.988/cycle | 0.017 / 1.769 | 3,281 / 7,679 | 0 | 3 | **7.17×10⁻²** | **2.83×10⁻⁴** |
| 2 | D32_CFGLUT125 | 4/cycle | 3.758/cycle | 0.015 / 1.768 | 2,883 / 7,273 | 0 | 3 | **9.25×10⁻²** | **2.81×10⁻⁴** |
| 3 | A32_CFGLUT125 | 8/cycle | 4.000/cycle | 0.028 / 1.785 | 4,746 / 9,145 | 0 | 3 | **6.02×10⁻²** | **2.37×10⁻⁴** |
| 4 | B32_CFGLUT125 | 16/cycle | 4.000/cycle | 0.049 / 1.806 | 8,274 / 12,670 | 0 | 3 | **3.95×10⁻²** | **1.71×10⁻⁴** |
| 5 | C32_CFGLUT125 | 8/cycle | 3.940/cycle | 0.065 / 1.823 | 9,764 / 14,162 | 0 | 3 | **1.26×10⁻²** | **1.49×10⁻⁴** |

The two scopes answer different questions: the accelerator FOM isolates the
contest deliverable (the exact compressor core is remarkably cheap — D32
delivers 4 valid outputs/cycle from 2,883 LUTs at 0.015 W), while the
full-system FOM prices in the DMA bus width and 88% of the power being the
ARM processing system (≈1.56 W [S32]). Historical comparison, clearly
labeled and recomputed on the same outputs-per-cycle basis: the predecessor
MAC datapath at 100 MHz (K=8 shape) scored ≈1.79×10⁻⁴ full-system and
≈5.58×10⁻² core; the CFGLUT5 A32 release improves the same shape to
2.37×10⁻⁴ (+33% full-system) and 6.02×10⁻² (+8% core) while running 25%
faster, using 26% fewer system LUTs (9,145 vs 12,362 — the compressor is
*smaller* than the MAC array it replaced), and removing the predecessor's
shift 24–31 restriction by construction.

## 12. Assumptions

1. FOM throughput is in **valid output values per clock cycle** at two
   scopes: the accelerator core at its design rate (K outputs/cycle, one per
   channel, pipeline filled) and the full system at its 64-bit output-bus
   limit (4 int16 per beat = 4 outputs/cycle) derated by the disclosed
   edge bubbles. BRAM counted in RAMB36-equivalents (3 per release [S32]).
   None of the FOM inputs is assumed.
2. Power is the Vivado vectorless routed estimate at 125 MHz [S32]; no on-board
   rail measurement is claimed.
3. Board latency figures are host-clock wall-clock intervals including DMA setup
   and Python-side polling overhead; the per-release streaming floors are
   derived from beat counts at 125 MHz, not measured.
4. Utilization percentages use the XC7Z020 capacities stated in the Vivado
   utilization reports [S32].
5. The board RTC is dead; all board run-ids carry 2018 stamps and are used as
   identifiers only. Host evidence dates are authoritative [S26].

## 13. Source index

| # | Source |
|---|---|
| S1 | Predecessor A32 (MAC) routed timing/power as of commit `5d7e416` — historical (§8.4, §11 comparison) |
| S2 | Predecessor A32 (MAC) routed power — historical |
| S3 | `m4_final_utilization.rpt` (hierarchical routed utilization, predecessor build) — historical |
| S4 | `Convlution_Accelerator.sim/sim_1/behav/xsim/simulate.log` + legacy regression set |
| S5 | `report/evidence/m5_qualification_transcript.txt` |
| S6 | `report/evidence/m6_reload_transcript.txt` |
| S7 | `report/evidence/m6_coldboot_sample.txt` |
| S8 | `report/evidence/m3_board_runs_transcript.txt` |
| S9 | `software/hardware.json` (predecessor manifest), `software/hardware_<ID>_CFGLUT125.json` ×5 (qualified manifests) |
| S10 | RTL: `Convlution_Accelerator.srcs/sources_1/new/*.vhd` (incl. `cfglut5_kcm.vhd`, generated `cfglut5_bitheap_3x3.vhd` / `cfglut5_bitheap_5x5.vhd`); generator `scripts/generate_cfglut_bitheap.py` |
| S11 | `golden_model/data/training_log.txt` |
| S12 | `Important documents/2026 SSCS_Egypt Competition Announcement.pdf` |
| S13 | `golden_model/` scripts, weights and `data/test_vectors_*/` |
| S14 | Board boot log (udmabuf 4 MiB @ 0x1F100000, FPGA Manager registered) — submission package |
| S15 | Predecessor DRC/route status reports — historical |
| S16 | `report/evidence/m7_switch_B32_first_20260913.txt`, `m7_switch_matrix_20260913.txt`, `m7_coldboot_20260913.txt` |
| S17 | `report/evidence/m7_soaks_20260913.txt` |
| S18 | `report/evidence/m8_cli_board_validation_20260913.txt` |
| S19 | `software/m7_switch.py`, `software/m8_cli.py`, `profiles/m7_profiles.json` (active five-release catalog), `profiles/anchors_m7.json` |
| S20 | Predecessor D640 routing reports — historical |
| S21 | `report/evidence/e2_extremes_matrix_20260914.txt` |
| S22 | `report/evidence/m9_soak1000_20260914.txt` |
| S23 | `report/evidence/m9_coldboots_20260914.txt` |
| S24 | `report/evidence/schema_v3_records_20260913/` |
| S25 | `report/research_builds/CFGLUT125_MATRIX/G5_QUALIFICATION_RECORD_20260915.md` (qualification decision; per-release artifact hashes) |
| S26 | `report/evidence/g5_board_qualification_20260915.txt` (verbatim G5 campaign transcript: singles, extremes, soaks, matrix, cold boot, fault injection) |
| S27 | `report/evidence/g5_board_records_20260915/` (17 schema-v3 run records, SHA256SUMS `17b4dcc1…`) |
| S28 | `report/research_builds/CFGLUT125_MATRIX/profile_wrapper_sims_20260914.md` + `wrapper_official_user_20260914T210835Z/` (five-release wrapper-sim matrix; edge metrics) |
| S29 | `scripts/packaging/fom_table.py` + `report/research_builds/CFGLUT125_MATRIX/fom_results.json` (reproducible FOM/results extraction) |
| S30 | `report/research_builds/CFGLUT125_MATRIX/firmware_20260915/FIRMWARE_RECORD.md` (Bootgen firmware generation + hashes) |
| S31 | `report/research_builds/CFGLUT125_MATRIX/catalog_cutover_20260915.md` (active five-release catalog cutover) |
| S32 | Five routed build records: `report/research_builds/{A32,B32,C32,D32,D640}_CFGLUT125/` (B32 under `rebuild_20260915/`) — build manifests, timing/power/utilization/DRC/route reports, `results.txt`, `BUILD_NOTES.md`; bitstreams `bitstreams/<id>_cfglut125_125mhz.bit/.xsa` |
| S33 | `report/research_builds/CFGLUT125_MATRIX/geometry_generalization_20260914.md` (generated-compressor geometry regression; canonical generator hashes) |
| S34 | `software/g5_fault_check.py` (bounded-recovery harness) |

## 14. Reproduction

All RTL (including the generated compressor entities and their deterministic
generator), the scripted block design, testbenches, golden model and board
software are in the repository. Per-release builds reproduce via
`scripts/research_release/research_build.tcl` (isolated projects under `work/`),
with the FOM table regenerating from the routed reports via
`scripts/packaging/fom_table.py` [S29]. Board experiments use
`software/m7_switch.py --matrix | --profile <REL> N` and
`software/m8_cli.py run | extremes | soak | benchmark | list | record`
against the active five-release catalog [S19], [S31]; the fault-injection
harness is `software/g5_fault_check.py` [S34].

---

*Appendix A (register map) and the submission bundle manifest follow this document.*

---

## Appendix A — CVH1 register map (as implemented, `axi_lite_ctrl.vhd` [S10])

Channel slots occupy `0x0000–0x3FFF`, one 0x100-byte block per channel, channels 0..K−1 implemented:

| Offset in slot | Access | Content |
|---|---|---|
| `0x00`, `0x04`, `0x08` | RW | Packed signed-8 coefficients; coefficient 0 in bits 7:0 of word 0 (N=3 → 9 coefficients, N=5 → 25, lane 0 of the last word only) |
| `0xF8` | RW | Bias, signed 24-bit value sign-extended in the 32-bit word |
| `0xFC` | RW | Bits 4:0 = shift (0..31); bit 8 = ReLU enable |
| all other offsets | — | SLVERR; reads return zero; no state change |

Global block (fixed offsets, independent of K):

| Offset | Register | Access | Content |
|---|---|---|---|
| `0x4100` | MAGIC | RO | `0x43564831` ("CVH1") |
| `0x4104` | ABI_VERSION | RO | `0x00010000` (major 1, minor 0) |
| `0x4108` | CAPABILITIES | RO | `0x000001FF` |
| `0x410C` | STATUS | RO | bit0 IDLE · 1 BUSY · 2 CORE_COMPLETE · 3 OUTPUT_DRAINED · 4 DONE · 5 ERROR · 6 FAULT · 7 PARAM_COMPLETE · 8 QUIESCENT (reset `0x101`; `0x181` with retained parameters) |
| `0x4110` | COMMAND | WO | 1 = START · 2 = RESET · 4 = ABORT (other values: SLVERR + BAD_VALUE) |
| `0x4114` | EVENT_CLEAR | WO | sticky event clearing (IDLE only) |
| `0x4118` | ERROR_FLAGS | RO/clear | bits 0..8: BAD_ADDRESS, BAD_ACCESS, BAD_STROBE, BAD_VALUE, BUSY_PARAMETER_WRITE, BAD_COMMAND_STATE, INPUT_FRAME, INTERNAL, ABORTED |
| `0x4120` / `0x4124` | IMAGE_W / IMAGE_H | RO | compiled per release (32/32 or 640/480) |
| `0x4128` / `0x412C` | KERNEL_N / CHANNEL_K | RO | compiled per release (3 or 5 / 4, 8, 16) |
| `0x4130` | WIDTHS_0 | RO | [7:0] pixel width 8 · [15:8] weight width 8 |
| `0x4134` | WIDTHS_1 | RO | [7:0] sum width (21 at N=3, 22 at N=5) · [15:8] accumulator width 25 |
| `0x4138` / `0x413C` | EXPECTED_INPUT/OUTPUT_BYTES | RO | compiled per release (1156/16384 at 32×32 K8; 309444/2457600 at D640) |
| `0x4140`–`0x414C` | INPUT_ACCEPT · INPUT_CONSUMED · CORE_ACCEPT_PIXELS · OUTPUT_ACCEPT_BYTES | RO | live per-frame counters |
| `0x4150`–`0x415C` | BUILD_ID_0..3 | RO | per-release frozen identity (§9) |
| `0x4160` | DMA_LENGTH_WIDTH | RO | 22 |
| `0x4000–0x40FF` | legacy space | — | decommissioned: SLVERR, reads zero, writes never control the datapath |

## Appendix B — submission bundle

Two top-level directories, each with a `SHA256SUMS.txt` and a README:

**`submission/src/`** — everything needed to rebuild and re-verify:

| Item | Location |
|---|---|
| RTL sources | `rtl/*.vhd` — the 16 active files incl. `cfglut5_kcm.vhd` and the generated `cfglut5_bitheap_3x3/5x5.vhd`, plus `scripts/generate_cfglut_bitheap.py` |
| Testbenches | `tb/` — datapath, geometry and wrapper regressions incl. `tb_conv_axis_wrapper` and the CFGLUT5 geometry tests |
| Golden model | `golden_model/` — `golden_conv.py`, training scripts, weights, `data/test_vectors_*/` |
| Test images + expected outputs | `vectors/` — canonical input images and per-configuration expected-output files |
| Block design + constraints | `bd/` — scripted BD, PS platform, XDC |
| Board software | `software/` — `m7_switch.py`, `m8_cli.py`, `m4_filebackend.py`, `conv_lab/`, manifests, catalog, anchors |

**`submission/docs/`** — the documents:

| Item | Location |
|---|---|
| This report | `report.md` (+ rendered PDF/HTML) |
| Presentation | `presentation.pptx` |
| FPGA reports | `fpga_reports/<RELEASE>/` — timing, power, utilization, DRC, route, methodology, check_timing per release + build manifests |
| Board-run evidence | `board_evidence/` — G5 qualification transcript, schema-v3 run records, Sobel render, boot identity |
| FOM table | `fom_results.json` + generator |
