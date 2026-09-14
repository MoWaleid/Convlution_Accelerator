# AI_HANDOFF.md — Complete Project Context

**Purpose:** This is the single self-contained briefing for any AI assistant or engineer
continuing this project. If you have this file plus repository access, you need nothing
else to work effectively — it covers the system, the history, the workflow, and **how to
talk to the user** (§15). Every claim below was verified first-hand; state as of
**2026-09-13**, HEAD commit `9f6f68a` ("M6: qualify same-image full-PL reload");
all M7 work (now **board-qualified**, §16) is uncommitted in the working tree.

> **CURRENT STATE POINTER (2026-09-14, context-reset safe): read §18 first.**
> The sections below are historical layers; §18 supersedes all earlier status
> prose where it conflicts, including §3, §16, §17, and the stale header line.
> Authoritative companions: INTEGRATION_PLAN_M10_M12.md (+ Addendum A, ba1b3ef),
> feedback.md (FP/IP/R14 review series), M9_CHECKLIST.md, CLEANUP_SCAN_20260914.md.

---

## 1. What this project is

**Two goals, one system.**

1. **Competition:** IEEE SSCS Egypt 2026 Student Design Competition — an FPGA NxN CNN
   convolution accelerator for edge-AI vision. **The summary report is due 2026-09-15**
   (winners announced Sep 30). Deliverables: report + RTL + testbench + golden model +
   test vectors + FPGA reports + optional board demo (bonus). Judged on correctness,
   design quality, resource usage, latency, throughput, timing closure, power, and
   FOM = Throughput / (Power × (LUTs + 50·DSPs + 100·BRAMs)), throughput in output
   pixels/cycle.
2. **Research program (the user's primary track, called "Branch B"):** a milestone-driven
   plan (M0→M9, see §3) that turns the accelerator into a "research-ready baseline" with a
   **live, plausible, touchable demo**. The competition report is treated as packaging
   ("the building around the real work"), produced from evidence as it accumulates.

**The system:** a K=8-channel, 3×3, stride-1 fixed-point Conv1 accelerator for 32×32
grayscale images on a **ZedBoard (Zynq-7020 xc7z020clg484-1)**, at **100 MHz**, with the
full software stack to drive it from embedded Linux. 1 output pixel/cycle, zero DSPs,
zero-BRAM line buffers.

**Team:** the user (Windows workstation owner, drives the board via serial) plus a
teammate with a parallel implementation (see §11).

---

## 2. Repository map (D:\MyProjects\Convlution_Accelerator)

Git branch `v1-bringup`; HEAD `9f6f68a` ("M6: qualify same-image full-PL reload",
2026-09-12). Prior key commits: `9a499ae` M5, `b11200a` handoff update, `5d7e416` M4,
`f711631` M3 closeout. **All M7 work is uncommitted** (modified: RTL identity chain,
golden_model scripts, dma.py; untracked: M7 docs, profiles/, software/hardware_*.json,
report/, profile_builds/, verification/m7_profiles/).

| Path | What it is |
|---|---|
| `Convlution_Accelerator.srcs/sources_1/new/` | **The RTL** (VHDL-2008): `config_pkg.vhd` (K=8, N=3, widths), `conv_pkg.vhd` (array types), `window_generator.vhd` (SRL line buffers, zero BRAM), `conv_channel.vhd` (4-stage pipeline: multiply → add-tree L1 → add-tree L2+bias → round-half-up/saturate/ReLU; `use_dsp="no"`), `conv_engine.vhd` (K channels sharing one window), `conv_top.vhd` (AXI-Lite + datapath), `axi_lite_ctrl.vhd` (AXI4-Lite slave + globals), `coeff_bias_shift_regfile.vhd` (per-channel storage), `sync_fifo.vhd`, `axi_stream_input_frontend.vhd` (64-bit AXIS → byte lanes), `axi_stream_output_serializer.vhd` (K×int16 → 64-bit beats, TLAST framing), `conv_axis_wrapper.vhd` (top wrapper: frame-busy, backpressure freeze, soft reset), `conv_axis_wrapper_bd.v` (Verilog BD adapter; **masks AXI addresses to lower 16 bits** — the "addrfix") |
| `Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/` | The tracked final M4 block design `accelerator_dma.bd`: no System ILA, AXI DMA simple-mode length width = 22, ZedBoard PS/HP0 platform |
| `Convlution_Accelerator.srcs/sim_1/new/` | RTL testbenches including `tb_conv_top`, `tb_conv_axis_wrapper`, AXI-Lite, AXI-stream frontend/serializer, datapath, window and regfile regressions. `sim_1/imports/new/` contains Vivado-imported copies registered in the project fileset |
| `scripts/` | `create_accelerator_dma_bd.tcl` + `zedboard_ps_platform.tcl` (ZedBoard PS7 preset). **Note:** the BD creation script has not yet been reconciled with the final M4 tracked BD setting `c_sg_length_width=22`; the tracked `.bd` is authoritative for M4 |
| `software/` | `conv_lab/` (M2 PS software), `tests/`, `reports/`, `m3_filebackend.py`, `m3_demo.py`, and `m4_filebackend.py` (CVH1 live-discovery/BUILD_ID validation, parameter admission, repeated-frame DMA inference, final counter checks, guard verification and cleanup RESET). **Repo is the source of truth** for board-script copies. **M7 additions:** `m7_switch.py` (profile switch manager — repaired + mock-tested, see §16), `hardware.json` (= A32 manifest) + `hardware_{B,C,D,D640}.json` (per-profile manifests), `conv_lab/profiles.py` |
| `deploy/petalinux/` | Finalized PetaLinux application pack: 3 recipes (conv-lab, conv-lab-starter, conv-lab-validation), rootfs configs, apply/preflight scripts, `SHA256SUMS.txt` (76 entries), `check_build_settings.sh` + `check_settings.py` (six-recipe `bitbake -e` evaluated-settings checker; **image target = `petalinux-image-minimal`, MACHINE = `zynq-generic-7z020`**) |
| `platform/accelerator_dma.xsa` | **Older** hardware handoff. The current qualified M4 XSA is `bitstreams/k8_gp0_noila_len22_2026-09-11.xsa`, SHA-256 `47a53884ff7529d3979a40d58418b837166c2ebd80bf93d32477a4f2824a503d` |
| `bitstreams/` (mostly gitignored) | Historical bring-up snapshots plus the qualified M4 no-ILA/len22 XSA `k8_gp0_noila_len22_2026-09-11.xsa`. Final M4 bitstream SHA-256: `8bc60890250bd34311f67fc9e66ce842abb9813f6053b116d254b059e80b67fd`. **M7:** `bn3k16/cn5k08/dn3k04/dn3k04_w640480_*_2026-09-12.bit` + their `.bit.bin` FPGA-manager firmware images (the board's `m7_A32.bin` is a copy of the M4 firmware) |
| `debug_captures/` | ILA captures telling the bring-up story (GP0 AR deadlock → fixes), plus 2 board-rendered demo PNGs (`m3_demo_sobel_mag_*.png`) |
| `golden_model/` | Training + quantization + golden model + test vectors (see §6). **M7 additions:** `data/weights_k16/` (B32, 70.08%), `data/weights_n5/` (C32, 67.72%), `data/weights_d32/` (hand-authored D filters), `data/trained_k16.pth`, `data/trained_n5.pth`; `train_cifar10.py`/`extract_weights.py` take env-var overrides (`CNN_K`, `CNN_N`, `CNN_MODEL`, `CNN_LOG`, `CNN_WEIGHTS_DIR`) |
| `profiles/` | M7 profile inputs: `m7_profiles.json` (frozen catalog — BUILD_IDs reconciled to the manifests, review finding 4), `anchors_m7.json` (per-profile golden output SHA256 + D640 preprocessing record), `README.md` (**its C32/D32/D640 ID list is stale — catalog + manifests are authority**), `history/` |
| `M7_CONTINUATION.md` / `M7_STATE.md` / `M7_FIX_PLAN.md` / `feedback.md` | M7 plan + approved gates (≥100-frame soak per profile, cold boot) / execution state (⚠ extraction-path claim corrected — see §16.2) / review-fix plan / the other AI's review (8 P1 findings) |
| `verification/m7_profiles/` | M7 software+RTL test suites and `mock_switch_test.py` (mocked full-activation test of the real manager) |
| `report/` | Competition report (`report.md`, print-ready `report.html`, `evidence/` board transcripts, `profile_builds/<P>/` per-profile frozen reports — some are intermediate/pre-physopt, see feedback finding 9) |
| `verification/axi_address_normalization/` | SystemVerilog regression of the BD adapter + full RTL + `run_xsim.ps1` driver |
| `Important documents/` | Competition announcement PDF, spec-decisions (39 pp), master plan (12 milestones), ADR, `Architecture_Mapping.html` (**stale** — predates K=8 and the MAC array) |
| `AI_HANDOFF.md` | This file |

Untracked but present on disk: `.venv/` (Python 3.13 env with torch/numpy/Pillow/pypdf),
`checkpoints/k8_100mhz_postroute_physopt_met.dcp` (M3-era golden post-route snapshot),
`m4_final_utilization.rpt` (hierarchical M4 utilization; gitignored `*.rpt`),
root `m4_accelerator_dma.xsa` (scratch copy of the qualified M4 XSA),
Vivado generated dirs (`.gen/`, `.runs/`, `.sim/`, `.cache/`, `.ip_user_files/`, `xsim.dir/`),
`golden_model.zip` (~494 MB snapshot).

---

## 3. The operative plan and current status

Two plan layers exist. **Layer 1** (`Important documents/CNN_Accelerator_Master_Plan.pdf`)
is the original 12-milestone competition plan — its M0–M9 are all effectively done.
**Layer 2 is operative**: `MASTER_PLAN_PRE_RESEARCH.md` in the Codex archive (§13),
which re-plans the program as M0→M9 with strict acceptance gates (§7 of that document
is the milestone table — read it before doing milestone work).

| Milestone | Gate (summary) | Status |
|---|---|---|
| M0 freeze recovery/reference release | manifest verifies; board run reproduced; recovery documented | **PASS** (2026-09-07 acceptance) |
| M1 freeze the contracts | 9 collaborator-approved contracts | **Closed** (residual gaps tracked in `contracts/M1_READINESS.md`) |
| M2 certify reference/library | ≥1000 seeded differential cases; host tests | **Complete** (Win + Linux x86_64 + **ARM**) |
| M2-P qualify embedded platform | offline boot, codecs, hashes, UIO/DMA regression | **Complete** (first ARM acceptance 2026-09-10/11; DMA proven 2026-09-11) |
| **M3 file-driven inference on existing build** | file-driven runs, ≥20 frames, zero mismatches, guards intact | **PASS** (2026-09-11, commit `f711631`) |
| **M4 integrate the exact hybrid incrementally** | CVH1 ABI per contract; regression per subsystem; clean 100 MHz build | **PASS** (2026-09-11; exact hybrid integration and live board proof complete) |
| **M5 qualify one hybrid build end-to-end** | ≥100 frames no inter-frame RESET, extremes, lifecycle, bounded-failure, identity/platform freeze | **PASS** (2026-09-12; `software/m5_qualify.py` + `software/hardware.json`) |
| **M6 same-image full reload** | 20× A32→A32 via approved lifecycle + cold-boot sample; activation validation per load; no stale state | **PASS** (2026-09-12; `software/m6_reload.py`, FPGA Manager + `m4_accelerator_dma.bin`) |
| M7 required profiles + model switching | A=N3/K8, B=N3/K16, C=N5/K8, D=N3/K4, D@640×480; switching matrix | **PASS** (2026-09-13 — 5/5 anchors, 58-switch matrix 20/20 ordered pairs, 5×100-frame soaks, cold boot; §10/§16; commit pending user) |
| M8 reproducible operation and demo | CLI/API, run archive, previews, measurement harness, importer, per-profile extremes | **PASS** (2026-09-14; E2 closed — extremes x5 profiles board-proven + matrix rerun with 20 provably consecutive cycles; all review P1s closed; evidence in report/evidence/e2_extremes_matrix_20260914.txt) |
| M9 freeze pre-research release | release tag, qualification matrix, 1000-frame soak | pending |

### Condensed history (the story so far)

- **Jul–Aug 2026:** spec decisions, original master plan, RTL built module-by-module
  (regfile → window gen → compute → streaming wrapper), golden model + trained model
  (68.15%), four test-vector sets. Teammate builds the K=16 variant in parallel.
- **Sep 1:** block design scripted (`scripts/*.tcl`), addresses frozen.
- **Sep 4–6 (bring-up war):** first bitstream → GP0/DMA **hang** (ILA: `arvalid` stuck) →
  reset fix → **addrfix** (BD adapter masks AXI addresses to the 64-KiB aperture) →
  **len16** (DMA length width) → trained-CIFAR board run PASS. Five bitstreams document it.
- **Sep 7:** M0 frozen (recovery + qualification PASS); teammate comparison audit
  (keep our repo as baseline; merge decision deferred).
- **Sep 8–10:** M1 contracts approved; M2 conv_lab written + host-tested (Win + Linux);
  PetaLinux pack staged → applied on Ubuntu → rootfs rebuilt → checker repaired twice
  (`petalinux-image-minimal` target, then `zynq-generic-7z020` machine) → M2P WIC built;
  ARM qualification tarball (A/B/C PASS) returned 2026-09-11.
- **Sep 11 (M3 day, 61 board frames, 0 mismatches):** proven M0 runners re-run on the
  new image → file-driven backend written and validated locally first, then pushed over
  serial (base64 chunk protocol with per-chunk md5) → demo runner: 9 images ×
  trained+custom configs, Sobel maps rendered **on the board**. Committed `f711631`.
  Same day/night: **M4 implemented** — full CVH1 ABI in RTL (~10.5 k lines), ILA removed,
  22-bit DMA lengths, integration sim A–H PASS, routed **WNS +0.066**, XSA exported,
  M4 WIC built, board run PASS via `m4_filebackend.py` (counters exact). Committed `5d7e416`.
- **Sep 12 (M5, M6, M7 prep):** M5 qualification (103 frames) and M6 same-image full-PL
  reload (21 reloads) closed and committed (`9a499ae`, `9f6f68a`). M7: all 5 profile
  bitstreams built with timing closure, K16/N5 models trained (70.08% / 67.72%),
  per-profile manifests + golden anchors written, switch manager drafted — then an
  external review (`feedback.md`, 8 P1 findings) forced a local repair pass.
- **Sep 13 (M7 execution, board):** repaired manager (md5 `e853933b…`) + profile delta
  pushed via per-chunk-verified relay (staged payloads had CRLF endings — fixed locally
  before the push). All 5 profiles switched with anchor-exact activation frames; full
  matrix PASS (58 switches / 58 full-PL reloads / 20 ordered pairs / 404.4 s);
  100-frame soaks ×5 PASS (A32/B32/C32/D32 median ≈0.124 ms, D640 median 3.731 ms
  timed); same-build parameter-only path proven at A32/D640 soak starts; cold-boot
  fallback PASS. 577 new frames, 69 new reloads, **0 mismatches**. §16 now records
  the closed state.

---

## 4. Hardware design essentials

- **Numeric contract:** uint8 Q0.8 pixels (value/256), int8 weights, per-channel
  signed-24 bias (sign-extended into the 32-bit register word), 5-bit shift, per-channel
  ReLU. Arithmetic: `acc = bias + Σ pixel·weight`; `if shift: acc = (acc + 2^(shift-1)) >> shift`
  (round-half-up); saturate to int16; ReLU clamps negatives to 0. **Bit-exact** against
  `golden_model/golden_conv.py`.
- **Geometry:** logical 32×32, padded 34×34 (zero border), TX frame = 1156 bytes,
  output = 32×32×K int16 little-endian, order **y,x,channel** (channel-fastest) = 16384 bytes at K=8.
- **AXI-Lite register map (M4 CVH1):** accelerator base `0x43C00000`.
  Channel slots occupy `0x0000–0x3FFF` in 0x100-byte strides; only channels `0..K-1` are active.
  Per channel: packed coefficients at `+0x00`, signed-24 bias at `+0xF8`, shift/ReLU control at `+0xFC`.
  Globals start at `0x4100`: MAGIC `0x43564831`, ABI_VERSION `0x00010000`,
  CAPABILITIES `0x000001FF`, STATUS `0x410C`, COMMAND `0x4110`, EVENT_CLEAR `0x4114`,
  ERROR_FLAGS `0x4118`, geometry/configuration discovery `0x4120–0x413C`, live counters
  `0x4140–0x414C`, BUILD_ID `0x4150–0x415C`, DMA_LENGTH_WIDTH `0x4160`.
  Frozen M4 BUILD_ID = `4d344e334b385733322d323630393131` (`M4N3K8W32-260911`).
  Legacy global space `0x4000–0x40FF` is decommissioned under CVH1 and must not control the datapath.
- **Block design:** PS7 (ZedBoard preset: DDR533, QSPI, SD, UART1, ENET0, USB0) +
  AXI DMA (simple mode, no SG, 64-bit both directions, `c_sg_length_width=22`, no DRE) +
  2 SmartConnects + proc_sys_reset + module-ref accelerator. **System ILA was removed for M4.**
  Addresses: DMA `0x40400000`/64K, accelerator `0x43C00000`/64K, HP0→DDR `0x0`/512M.
  One 100 MHz clock domain, FCLK_RESET0_N → peripheral resets.
- **Final M4 routed build:** full system = 12,362 LUTs, 9,787 FFs, 2 RAMB36 + 2 RAMB18,
  **0 DSPs**. The accelerator wrapper itself uses 7,967 LUTs, 3,541 FFs, **0 BRAM, 0 DSP**;
  the reported system BRAM belongs to AXI DMA.
  Timing at 100 MHz: **WNS +0.066 ns, TNS 0, WHS +0.022 ns, THS 0**.
  `check_timing` is clean. Final DRC has only reviewed RTSTAT-10/REQP-165/REQP-181
  warning/advisory messages; no dbg_hub warning and no failing DRC errors.
- **Bring-up history:** the Sep 4–6 sequence was GP0 AR deadlock → resetfix → addrfix →
  len16 DMA → trained-CIFAR board run. Those artifacts remain historical recovery evidence.
  M4 supersedes that runtime build with **no System ILA**, **22-bit DMA lengths**, CVH1 control,
  signed-24 bias handling, coherent discovery/counters, and the 4-MiB u-dma-buf platform.
  Final routed bitstream:
  `Convlution_Accelerator.runs/impl_1/accelerator_dma_wrapper.bit`,
  SHA-256 `8bc60890250bd34311f67fc9e66ce842abb9813f6053b116d254b059e80b67fd`.
  Qualified XSA: `bitstreams/k8_gp0_noila_len22_2026-09-11.xsa`,
  SHA-256 `47a53884ff7529d3979a40d58418b837166c2ebd80bf93d32477a4f2824a503d`.
  The bitstream embedded in the exported XSA hashes identically to the final routed `.bit`.
  Current SD image: `C:\VMShare\zedboard_M4_2026-09-11.wic`,
  SHA-256 `2579e8bedc38fb1630ac0e0b67b13540d049c7aa9d4d294a88f7a44aee2a0499`.

---

## 5. The CVH1 ABI (implemented in M4)

Approved contract: `contracts/M1_REGISTER_STREAM_ABI.md` (Codex archive, §13). M4 implements the CVH1 hardware/runtime ABI; full manifest/platform-digest lifecycle integration remains an M5 concern. Highlights:

- New global block at **0x4100+** (independent of K): MAGIC `0x43564831` ("CVH1"),
  ABI_VERSION `0x00010000`, CAPABILITIES `0x000001FF`, STATUS (reset `0x00000101`),
  COMMAND (WO: 1=START, 2=RESET, 4=ABORT), counters, and a **nonzero 128-bit BUILD_ID**
  (assigned before synthesis; frozen M4 value `4d344e334b385733322d323630393131`). Full `hardware.json`/platform binding is deferred to M5.
- Legacy space `0x4000–0x40FF` becomes SLVERR — **writing 1 to 0x4004 must never start a frame**.
- Channel slots keep the 0x100 layout; reserved offsets in a slot → SLVERR.
- Software must read MAGIC/ABI_VERSION/BUILD_ID and reject mismatch **before any writes**.
- Bias default width becomes signed 24 (sign-extended into the 32-bit word).
- READ THE CONTRACT before implementing — the table excerpt here is truncated.

---

## 6. Model, golden model, and hash anchors

Pipeline (all in `golden_model/`): `train_cifar10.py` (grayscale Q0.8 CIFAR-10 CNN,
seed 2026, **68.15% test accuracy**, checkpoint `data/trained_model.pth`) →
`extract_weights.py` (per-channel int8, all shifts=8, int32 quantized biases) →
`golden_conv.py` (arbitrary-precision bit-exact RTL replica) →
`generate_test_vectors.py` (4 vector sets: trained K=8, custom K=4 identity/Sobel×2/blur,
all-zero, all-255) → `compare_results.py`.

**Golden anchors for the alley_cat_s_000013 test image:**

| Artifact | SHA256 |
|---|---|
| Encoded PNG (32×32 RGB) | `200f5baa120d957838037c7e28052ac998e82ddd94aef937173e37c3dfb470b0` |
| Canonical grayscale bytes (1024 B; `PIL convert('L')`) | `a240bb760e2a85951f5c4e27c95041e98d4919c5cc32114cc4f5191f6ffb6771` |
| Padded TX (1156 B) | `967c1c7687d3775d4512bd30eaa7f07fc8e1956145ed82326b35eb8cff28f74e` |
| Trained-model output (16384 B) | `cb3975593073652b9d5f2fcb206748ad70c4abf621339ea19878b6863d9be705` |

`channel_config.json` exists in **two formats**: format-2 (`golden_model/data/weights/`,
fields `shift`/`relu_en` as ints) and **format-3** (the installed library: per-channel
`weights_file`, boolean `relu_en`, `input_scale`/`weight_scale` rationals, N/K inside
`model.json` compatibility block). The board library uses format 3.

---

## 7. Software stack (M2 / conv_lab)

`software/conv_lab/` is a hardware-independent exact-convolution platform: strict JSON/
byte grammar (`strict.py`), bounded snapshots (`bundles.py`), schema validation
(`schemas.py`), pure DMA layout arithmetic for five layouts with 22-bit lengths
(`dma.py`; TX at +4096, guarded RX, 64-byte alignment), a Linux-only sandboxed decoder
(`preprocessing.py` + `_decoder_worker.py`: RLIMIT_AS 128 MiB, unprivileged, 30 s
deadline), mock admission (`admission.py`), independent integer reference
(`reference.py`), storage publisher (`storage.py`). Tests in Groups A (admission/storage/
worker), B (1000 seeded differential cases, seeds 0x5EED000+i), C (conversion/offline).

Evidence: Windows A 26 PASS/9 skipped, Windows B 1008 PASS, Linux A 35 PASS (worker
enforcement PASS), Linux B 1008 PASS, current-revision A/B/C reruns all PASS; real-bundle
offline run reproduces output hash `cb397559…`. **ARM board qualification (2026-09-10/11):
A 35 PASS, B 1008 PASS, C 14 PASS on armv7l** (tarball:
`C:\VMShare\M2P_ARM_qualification_2026-09-11.tar.gz`).

---

## 8. Environments and how to reach them

| Environment | Access | Contents |
|---|---|---|
| **Windows host** (this repo) | direct | Vivado 2025.2 project, all sources, PuTTY serial console to the board, SD flashing via Raspberry Pi Imager from `.wic` files in `C:\VMShare` |
| **Ubuntu VM** (`linux-vm`, user `walid`) | **relay only**: user copy-pastes commands and returns output | PetaLinux 2025.2 (`/home/walid/petalinux/2025.2`), project `/home/walid/projects/zedboard_linux` (recipes applied, `CONFIG_conv-lab-validation=y`, rootfs built 2026-09-10), 8 GB RAM, 24 GB free. VM cannot see the board or the SD card |
| **ZedBoard** (`zedboard_linux`, login `petalinux`, sudo needs password) | user's PuTTY serial session | see §9 |

The user relays every command between the assistant and the VM/board. **User preferences:
keep responses short; evidence-first; do not work on the competition report unless told
(deadline 2026-09-15); Branch B (plan/demo) is the priority.**

`C:\VMShare` holds the transfer artifacts: historical len16 `.bit`/`.xsa`/`.wic` recovery
assets, the current M4 `m4_accelerator_dma.xsa` and `zedboard_M4_2026-09-11.wic`, M2 evidence
zips, settings-check packs, and the ARM qualification tarball.

---

## 9. Board operations manual

**Device map (verified 2026-09-11):**

| Device | Identity | Notes |
|---|---|---|
| `/dev/uio0` | DMA @ `0x40400000`, 64 KiB | root:root 0600 |
| `/dev/uio1` | accelerator @ `0x43C00000`, 64 KiB | root:root 0600 |
| `/dev/udmabuf0` | u-dma-buf 5.5.0, phys `0x1F100000`, **4 MiB**, sync_mode 1 (noncached) | current M4 DMA buffer |

Board: kernel `6.12.40-xilinx-g31626ef92ff1`, armv7l, Python **3.12.11**, Pillow **10.3.0**
(JPEG 6.2, zlib 1.3.1), 508 MB RAM, ~2.1 GB free disk. **Quirks:** board clock resets to
2018 on every boot (no RTC battery — `sudo date -s "<UTC time>"` after each boot, or NTP
once Ethernet exists); `/tmp` is wiped on reboot (use `/home/petalinux/`); no `base64`
applet (use `python3 -c "import base64,..."`); devices are root-only → run inference
with `sudo`; Ethernet interface `enx000a35001e53` exists but no cable (sshd present).

**Persistent on-board artifacts:** `/home/petalinux/m4_filebackend.py` is the current M4
file-driven hardware backend. It validates DMA state, CVH1 MAGIC/ABI/CAPABILITIES, frozen
BUILD_ID, geometry, widths and byte counts **before accelerator writes**, programs and
readback-verifies parameters, performs repeated STARTs without inter-frame RESET, checks
final CVH1 counters/output/guards, then returns the accelerator to a clean retained-parameter
state with local RESET. The earlier `/home/petalinux/m3_filebackend.py`, `m3_demo.py`,
`/home/petalinux/demo_out/` and `/home/petalinux/demo_images/` remain as M3/demo evidence.

**Current M4 execution sequence** (`m4_filebackend.py`; do not replace with the old M0 soft-reset flow):
1. Verify both DMA channels are halted/simple-mode/error-free.
2. Read and validate CVH1 MAGIC, ABI_VERSION, CAPABILITIES, DMA_LENGTH_WIDTH=22, BUILD_ID,
   IMAGE_W/H, KERNEL_N, CHANNEL_K, WIDTHS_0/1 and expected input/output byte counts.
3. Admit local accelerator RESET only from IDLE/FAULT while QUIESCENT; accepted clean states are
   `IDLE|QUIESCENT = 0x101` or retained-parameter `IDLE|PARAM_COMPLETE|QUIESCENT = 0x181`.
4. Program channel parameters with readback verification and require PARAM_COMPLETE.
5. Per frame: prepare/arm S2MM first, prepare MM2S, issue CVH1 START, observe BUSY, then release
   the MM2S length. **Do not RESET between successful frames.**
6. Require DMA completion plus accelerator DONE, OUTPUT_DRAINED and QUIESCENT.
7. Before cleanup RESET, verify final counters: input_accept=1156, input_consumed=1156,
   core_accept=1024, output_accept=16384; then verify bit-exact output and RX guards.
8. Halt DMA channels, issue local CVH1 RESET, and require clean retained-parameter state `0x181`.
Measured M4 Python wall-clock latency on the qualified run was about 0.230–0.261 ms/frame;
the datapath still sustains one output pixel/cycle at 100 MHz.

**Serial file-transfer protocol** (no network on board): gzip -9 → `base64 -w 76` →
paste in ≤24-line chunks into `cat > file << 'XEOF'` heredocs → **verify per-chunk md5**
against assistant-provided references before decoding (corrupted chunks are re-emitted
individually; `sed -i 'Ns/a/b/'` for single-character repairs) → decode with
`python3 -c "import base64,gzip,..."`. **Lessons: there is no `base64` applet (use
python3); never double-gunzip (`.tgz` payloads decode with `base64.b64decode` only);
transcription errors in chat are the main corruption source — always verify chunk hashes.
Large files (>100 KB): don't serial-push at all — sneakernet them through the SD's FAT
boot partition (`/dev/mmcblk0p1`, mountable read/write from the board).**

**Runtime PL reprogramming (M6, proven):** Zynq FPGA Manager is in the running kernel
(`fpga0`, "Xilinx Zynq FPGA Manager"); the consumers-format image is generated on
Windows from the routed `.bit` with
`bootgen -image m4_pl.bif -arch zynq -process_bitstream bin` (BIF = plain path, no
`[destination_device]` attribute on zynq arch; output lands next to the `.bit` as
`*.bit.bin`). Staged at `/lib/firmware/m4_accelerator_dma.bin` (persists on ext4
rootfs; also on SD p1). SHA256 `b59378e4918f3c128d0d787546981e58b7508085c916780a21fef5db3a04130b`,
4,045,568 bytes. Programming: write `0` to `fpga0/flags`, write firmware name to
`fpga0/firmware`, poll `fpga0/state` == `operating` (~183 ms). After reload the PL is
factory-fresh: STATUS `0x101`, params/admission wiped, identity registers re-readable
— the seven-phase lifecycle in `m6_reload.py` implements it (handles closed before
programming, brand-new handles after).

---

## 10. Verification evidence ledger (hardware, 2026-09-11/13)

| Run | Frames | Result |
|---|---|---|
| `dma_len16_trained.py` (M0 runner, embedded payload) | 1 | bit-exact, output sha `cb397559…` |
| `dma_len16_repeated.py` | 20 | 20/20 PASS, no inter-frame resets, distinct outputs |
| `dma_len16_golden.py` (custom filters, saturation extremes) | 1 | PASS |
| `m3_filebackend.py` (file-driven, format-3 library) | 3 | PASS, ~0.14 ms/frame |
| `m3_demo.py` (9 images × trained+custom ×2) | 36 | PASS, 135 PNGs, manifest `96b01a0f416893c7acb2df32b02a54d5712e1283b6debc5cf11686c1e21a4828` |
| `m4_filebackend.py` (CVH1 hybrid build) | 3 | PASS; repeated START/no inter-frame RESET; counters exact; guards intact; output SHA `cb397559…` |
| `m5_qualify.py` (M5 qualification) | 103 | **PASS** — 100-frame no-reset soak (alternating images) + saturation/all-zero/all-255 extremes + ABORT→FAULT→recovery, ABORT-race, poisoned-expectation tests; median 0.076 ms/frame; final retained state `0x181` |
| `m6_reload.py` (same-image full reload) | 21 frames / 21 reloads | **PASS** — 20 consecutive + 1 post-cold-boot A32→A32 full-PL reloads via FPGA Manager (`m4_accelerator_dma.bin` from `/lib/firmware`); per-cycle: identity re-validated, stale-state proof (STATUS==`0x101`), full re-installation, bit-exact frame; ~183 ms/reload |
| M7 host-side (mocked end-to-end manager test, matrix-seq, D640 resize hash) | — | **PASS locally** (`verification/m7_profiles/mock_switch_test.py`) |
| `m7_switch.py` singles (B32 first, then A32/C32/D32/D640) | 5×3 | **PASS** — first M7 board evidence; every activation frame anchor-exact; D640 via recorded LANCZOS preprocessing |
| `m7_switch.py --matrix` | 58 activation frames / 58 full-PL reloads | **PASS** — 20/20 ordered pairs observed-verified, 404.4 s, final state `0x181` |
| `m7_switch.py --soak` ×5 | 100 each | **PASS** — A32/B32/C32/D32 median 0.124–0.125 ms, D640 median 3.731 ms (timed); same-build parameter-only lifecycle proven at A32/D640 soak starts |
| `m7_switch.py --profile B32 3` after cold reboot | 3 | **PASS** — ext4 persistence (md5 `e853933b…`), BOOT.BIN A32 identity → full reload → anchor-exact frames |

Total recorded board evidence: **765+ frames, 0 mismatches**, guards intact every run; **90 verified full-PL reconfigurations** (21 M6 + 69 M7). M2-P, M3, M4, M5, M6 and **M7** are closed. Board-side copies: `/home/petalinux/{m4_filebackend,m5_qualify,m6_reload,m7_switch.py,profiles/}`. M7 transcripts (verbatim relays): `report/evidence/m7_switch_B32_first_20260913.txt`, `m7_switch_matrix_20260913.txt`, `m7_soaks_20260913.txt`, `m7_coldboot_20260913.txt`.
`debug_captures/m3_demo_sobel_mag_aeroplane_view.png` (Sobel magnitude through real
silicon); `…_board.png` (alley cat — correctly near-empty: that image's golden Sobel
max magnitude is 3).

---

## 11. Teammate repo and the pending merge decision

`D:\MyProjects\AI-accelerator` @ rev `7f677528` ("Synchro branch"): a **K=16** variant
(`conv_system` BD, top `conv_system_wrapper`, packaged `conv_top_ip` with the same module
lineage), accelerator at **0x40000000**, 8-bit MM2S into the core, **256-bit output →
axis_dwidth_converter → 64-bit**, start/status/counters at `0x1000/0x1004/0x1008/0x100C`,
SLVERR on writes-while-busy, K=16 trained vectors, 32-config GHDL/XSim regression,
schema-2 manifest, **WNS +0.306** (better margin than ours).

The recorded decision (2026-09-07 comparison audit in the Codex archive): **keep
Convlution_Accelerator as the integration/software baseline**; treat the teammate core
as a serious alternative; final datapath choice deferred to a matched-configuration
comparison — `comparison_audit_2026-09-06/MERGE_DECISION_CHECKLIST.md` (27 KB) is the
instrument. This decision becomes unavoidable at **M7** (profile B = N3/K16). FOM note:
both designs deliver 1 output pixel/cycle, so the FOM formula's LUT term likely favors
our leaner K=8 design; clarify whether competition "throughput" counts pixels or values.

---

## 12. Known issues / quirks register

1. **Timing margin is small but positive on the final M4 build:** WNS +0.066 ns, WHS +0.022 ns at 100 MHz. Preserve this margin in later changes.
2. `Important documents/Architecture_Mapping.html` is **stale** (claims K=16, "pending
   RTL" for things that exist). `golden_model/verify_by_hand.ipynb` is broken (imports
   removed functions). `golden_model/data/test_vectors_*/png/` contain stale K=16-era
   previews.
3. `scripts/create_accelerator_dma_bd.tcl` has not yet been reconciled with the final
   M4 tracked-BD DMA setting `c_sg_length_width=22`; the tracked `.bd` is authoritative.
4. `platform/accelerator_dma.xsa` is the older handoff; the qualified M4 XSA is
   `bitstreams/k8_gp0_noila_len22_2026-09-11.xsa`.
5. `deploy/petalinux/README.md` references `deploy/petalinux_snapshots/…` which does not
   exist in the repo (snapshot lives outside).
6. Board clock resets every boot; UIO/udmabuf are root-only; no RTC battery.
8. **PLATFORM FINDING (2026-09-12):** deliberately provoking SLVERR from userspace
   (illegal command values, reserved-address accesses) escalates on the Zynq GP path to
   `Unhandled fault: external abort on non-linefetch (0x1818)` → SIGBUS, killing the
   process. The platform enforces the validate-before-write backend contract **fail-stop**;
   SLVERR decode is qualified in simulation (`tb_axi_lite_ctrl`). Backends must never
   probe error paths with live MMIO writes. Also: post-frame sticky event bits
   (DONE/CORE_COMPLETE/OUTPUT_DRAINED) persist until CVH1 RESET — a healthy post-frame
   STATUS reads `0x19D`; only after RESET does it read `0x181`.
7. `.bit/.ltx/.dcp` files are gitignored — `bitstreams/*.bit` and `checkpoints/*.dcp`
   exist only on disk (the tested-bitstream hash gate in §4 covers this).
9. **M7 source reconciliation (2026-09-13, E1):** the M7 board evidence (matrix,
   soaks, cold boot) was produced by manager md5 `e853933b4d0610881e895be4ff48c3bf`
   (always-compute on-board reference; anchor checked on activation frames only),
   while commit `3117f0f` contains the later `184d75c07eb96d4b7e64b27b6a05dd31`
   (adds `REF_POSITION_LIMIT=65536` gating + anchor checks in soak/switch-frames).
   The board was reconciled to `184d75c0…` the same day: whole-payload md5
   verified, A32 same-build smoke PASS, D640 reload activation 3.783 ms
   (anchor-exact, no reference computation). Evidence transcripts carry
   correction banners where the verification mechanism was originally
   mislabeled. Do not re-verify with `e853933b`-era assumptions.
10. **Push-payload lesson (2026-09-13):** the staged Temp payloads had CRLF line
    endings and failed `base64 -d`; always strip CR and re-verify decoded hashes
    locally before handing chunks to the relay.

---

## 13. Key locations index (outside the repo)

| Path | Contents |
|---|---|
| `C:\Users\moham\Documents\Codex\` (+ identical `Codex.zip`) | The evidence vault: `2026-09-05/referenced-chatgpt-conversation-this-is-an/` = **operative master plan** (`MASTER_PLAN_PRE_RESEARCH.md`), `contracts/` (9 approved M1 contracts), `M2_host_evidence_20260909_…/` and `M2_real_platform_evidence_20260910_…/` acceptance checkpoints (manifests verified 8/8 and 114/114), `M0_closeout/`+`M0_acceptance/` (M0 PASS + len16 SD recovery procedure), the proven board runners, `comparison_audit_2026-09-06/` (teammate audit + merge checklist) |
| `C:\VMShare\` | Transfer bridge Windows↔VM: tested bits/XSA, both `.wic`s, M2P packs, ARM qualification tarball |
| `D:\MyProjects\release_checkpoints\M0_k8_len16_20260907_052648_358\` | Frozen M0 checkpoint (project snapshot + evidence; 246-entry manifest verified); `external/planning_workspace/` holds the proven board runners; `current_project\bitstreams\` holds the tested len16 `.bit` |
| `D:\MyProjects\release_checkpoints\M2_trained_cifar_k8_candidate_v1\` | Converted model+dataset bundle candidate |
| `D:\MyProjects\AI-accelerator\` | Teammate's K=16 repo (§11) |

---

## 14. Working conventions that emerged (follow these)

- Everything is **evidence-gated**: a milestone is done only with recorded artifacts
  (hashes, transcripts); a failed gate blocks promotion, never gets relabeled PASS.
- All numeric changes must remain **bit-exact** against `golden_conv.py`.
- The **qualified M4 profile** is the 4-MiB u-dma-buf / 22-bit DMA / no-ILA CVH1 build.
  The older 1-MiB/len16 image remains historical recovery evidence, not the current profile.
- Exclusive-ownership lifecycle (§5 of `M1_ACTIVATION_LIFECYCLE.md`) governs all future
  backend work: UNVERIFIED at start → identity/capability validation → READY.
- When transferring files to the board: chunked base64 with per-chunk md5 verification
  (§9). When asking the user to run things: one short self-contained block at a time.

---

## 15. How to work with the user (conversation style & collaboration protocol)

The user is an Egyptian undergrad competitor; casual register, occasionally profane,
zero patience for fluff. What works and what doesn't, learned the hard way:

**Style**
- **Be concise.** The user explicitly asked for short responses. Lead with the outcome
  ("PASS — 36 frames, 0 mismatches"), then detail only as needed. No filler, no restating
  their words back at them.
- Direct and honest beats diplomatic. Own your bugs immediately and precisely (see the
  bug-history below) — the user respects "my bug, here's the one-line fix" and distrusts hedging.
- When the user says **"GO"**, that's approval to execute the proposed plan without
  further check-ins. When they say "identify/describe X" they mean read-only — **do not
  change anything** until explicitly told ("don't change a fucking thing" is a real quote).
- Don't ask the user questions you can answer yourself from the repo/evidence. The one
  strategic question that mattered (competition vs research focus) was asked once and
  answered: **Branch B (research/demo) is the priority; the report is packaging** and is
  only assembled when the user says so (due 2026-09-15).

**The relay workflow (critical — you have no direct access to VM or board)**
- You hand the user **one short, self-contained command block at a time** for Ubuntu
  (VM) or the ZedBoard (PuTTY serial). They paste it and return the output verbatim.
  Multi-line heredocs for file pushes; single-line commands pasted **separately** to
  avoid terminal line-garbling.
- Board pushes use the base64-chunk protocol in §9, **always with per-chunk md5
  verification**. When a chunk mismatches: compute reference chunk hashes locally,
  have the user hash theirs, re-emit or `sed`-patch only the bad chunk.
- VM (builds, PetaLinux) and board (runtime) are separate worlds; the SD card moves
  between them via `C:\VMShare` and Raspberry Pi Imager on Windows.

**Working rhythm that has proven effective**
1. Propose the next plan step (tied to the milestone gates, §3) — get "GO".
2. Do everything possible locally first (validate scripts against golden anchors on
   Windows before ever pushing). The user values this: zero board time wasted on
   avoidable bugs.
3. Execute through the relay; verify every result against expected hashes.
4. Record evidence (hashes, transcripts, artifacts) and prompt the user to commit
   with a milestone message; they do the committing.
5. Keep `AI_HANDOFF.md` current as state changes — it is the continuity contract.

**Known failure modes of this collaboration (avoid repeating)**
- Transcription errors when re-typing payloads into chat (one flipped char cost an
  hour) → never retype; emit from files, verify by hash.
- Argument-order bugs in board scripts (`os.pread(fd, count, offset)`) and success
  messages printed unconditionally in `finally` blocks → validate locally, structure
  scripts so PASS is only printed on real success.
- Assuming tools exist on the board (`base64`, `/tmp` persistence, correct clock) — §9
  lists the real quirks; read it before board work.

---

## 16. M7 execution state — CLOSED 2026-09-13 (PASS; commit pending user)

M7 is complete with board evidence. Ledger rows: §10. Verbatim transcripts:
`report/evidence/m7_switch_B32_first_20260913.txt`, `m7_switch_matrix_20260913.txt`,
`m7_soaks_20260913.txt`, `m7_coldboot_20260913.txt`. M7_STATE checklist is fully
ticked. What happened, in one paragraph: the repaired manager (md5
`e853933b4d0610881e895be4ff48c3bf`) and the profile delta (11 files) were pushed
through the per-chunk-md5 relay protocol after fixing CRLF corruption in the staged
payloads; then, in one board session: first switch A32→B32 PASS, singles through
A32/C32/D32/D640 PASS, full matrix PASS (58 switches, 58 full-PL reloads, all 20
ordered pairs observed and verified, 404.4 s), 100-frame soaks ×5 PASS (D640
validates per frame against its frozen anchor SHA-256; software reference disabled
above `REF_POSITION_LIMIT=65536`), same-build parameter-only lifecycle proven at the
A32/D640 soak starts, and the cold-boot fallback PASS (persistence md5 verified, then
BOOT.BIN A32 identity → full reload → anchor-exact frames, `0x181` cleanup).

Board inventory (persistent): `/home/petalinux/m7_switch.py` (md5 `e853933b…`),
`/home/petalinux/profiles/` (`m7_profiles.json`, `anchors_m7.json`,
`hardware_<P>.json` ×5, `A32/ B32/ C32/ D32/ D640/` parameter dirs),
`/lib/firmware/m7_{A32,B32,C32,D32,D640}.bin`, push payloads retained under
`/home/petalinux/push/` (regenerable from the repo — deletion is optional cleanup).

All five profiles frozen exactly as in the old 16.1 table (A32 `M4N3K8W32-260911`,
B32 `BN3K16W32-260912`, C32 `CN5K08W32-260912`, D32 `DN3K04W32-260912`,
D640 `D640N3K04-260912`); golden anchors unchanged
(A32 `cb397559…`, B32 `5821c8b1…`, C32 `b6ab2d53…`, D32 `6cb736f6…`,
D640 `e323defb…`).

### 16.7 PENDING BOARD PUSH — CONSUMED 2026-09-14 (E2 round delivered via BLOCKREADY)

The user is away from the board. On the keyword **BLOCKREADY**, re-emit the
staged payload blocks exactly and resume injection. State:

- Payload: Temp/m11fix.tgz (18,319 B) — contains home/petalinux/m7_switch.py
  (md5 2fe949ca9040dd3fda990016c78a4474, E2 consecutive-cycle bridge in
  build_matrix_sequence) and home/petalinux/m8_cli.py (md5
  1553ec801557e9defe2fedef83725bce, cmd_extremes). Whole b64 m11fix.b64 md5
  42c667cd2b4522da6e26f9f2e18363e0, 322 lines = 14 chunks in
  Temp/m11f_00..m11f_13 (first 13 x 24 lines + 10 lines).
- Chunk md5s: c1 c19334d8f7e21e030301719d68fcec1c, c2
  4bf62fd4b1321fc3408ad81988e16c86, c3 f3978f825c7665f9f8c9242e3dc455f3, c4
  1f30ed843ecd37e74d5bbac1fa2c981f, c5 ce1983e767058476072d278e973fe02f, c6
  6d7f77eb6077702aa6787a9e6022b2bb, c7 e8c7a60d3066950fde4a03adc1c9f958, c8
  b390dcf49305e534cc3ef0d87cdf7255, c9 91ead0ce20a2b150970beb46bca8a62b, c10
  09df40ff2df8be80a378bd253bea3305, c11 5037aee93702ee3794bad599572c65f8, c12
  8cd34320edcc96053486a278c5ca9175, c13 353866b27ca1e6008b0d6d172be17333, c14
  e522fd81146b3e8cd17fc2a90fb0a72f.
- Install: concat 14 chunks in order -> decode (base64 ONLY - no gzip) ->
  verify tgz 18,319 B -> tar xzf m11fix.tgz -C /home/petalinux
  --strip-components=2 (members carry the home/petalinux/ prefix; the strip
  avoids the nesting bug) -> verify installed md5s.
- Board validation plan after install:
  1. sudo python3 /home/petalinux/m8_cli.py extremes --profile A32 (fast)
  2. extremes --profile B32, then C32, then D32
  3. extremes --profile D640 (three exact-reference computations take minutes
     each - expected, not a hang)
  4. sudo python3 /home/petalinux/m7_switch.py --matrix (rerun with the
     bridge: establishes A32 first -> 20 provably consecutive A32-B32-A32
     cycles; 59 switches from a non-A32 start)
  5. Evidence: report/evidence/m8_02_extremes_20260914.txt + matrix rerun
     transcript; then E2 closes.
- Board state at pause: PL holds B32; all five canonical bundles installed;
  m7_switch md5 8b4315b8..., m8_cli md5 bfdbb39b... (both superseded by this
  push); importer + conv_lab grammar/worker package in place.

## 16.6 Report corrections — APPLIED 2026-09-13 (report/report.md, uncommitted)

- **Throughput/FOM:** done — 4/K is now labeled an output-interface ceiling
  (theoretical upper bound) in §3/§9.1/§11/§12; the 10.24 µs / 1,024-cycle
  datapath claim removed; measured wall-clock scopes kept explicit.
- **Bias/accumulator widths:** already corrected (25-bit accumulator text).
- **Citation freeze:** S1/S2 carry the A32-overwritten caveat; D640 final
  post-physopt timing reports frozen at `report/profile_builds/D640/final/`
  (S20); archived D32/D640 intermediates labeled pre-physopt.
- **M7 updates applied:** §1/§8.2 totals (876 frames, 20+ runs, 90 reloads),
  new §10.1 multi-profile section (five profiles, BUILD_IDs, WNS, models,
  matrix/soak/cold-boot evidence), §5 approved four-guard buffer layout,
  §7 profile-scoped identity, §9.1 rows, §13 sources S16–S20, §14 reproduction,
  Appendix B.
- **Still open (tomorrow):** optional D-profile Sobel figure from the board
  preview PNGs; `report.html` regeneration if used; E3 stale foundation tests
  (`software/tests/test_m7_profiles.py`); remaining review items (M8-02 worker
  isolation, M7-R4 strict admission, M8 Phase B importer).

**Next milestone: M8** — in progress (2026-09-13). Phase A implemented and
board-validated: `software/m8_cli.py` (run/benchmark/list/record) + run archive
at `/var/lib/conv-lab/results/` + display-only previews + measurement harness,
strictly layered on m7_switch (UI never bypasses the backend). Mock suite
`verification/m8_cli/mock_cli_test.py` (8 cases) + the M7 manager mocks all PASS.

Second external review (feedback.md top section, 2026-09-13) accepted the M7
board evidence as historical and listed new blockers; disposition so far:
- **E1 (source/identity mismatch) RESOLVED:** the M7 board runs used manager
  md5 `e853933b…` while commit `3117f0f` contains `184d75c0…`; the board was
  reconciled to `184d75c0…` (payload md5-verified, A32/D640 smokes) and is now
  byte-identical to the repo. Evidence transcripts carry correction banners.
- **Fixed, mock-tested, board-validated:** M7-R1 flock-based exclusive
  ownership (kernel-released, pid recorded, `/run/lock` preferred); M7-R2
  approved four-guard layout (RX at 5440/5568/313728, 22-bit bounds, physical
  alignment, runtime allocation honored, D640 manifest rx_offset corrected to
  313728); M7-R3 cleanup RESET only from IDLE/FAULT **and QUIESCENT**, final
  `0x181` required, PASS printed only after cleanup in all modes; M8-01
  sha-only runs are UNVERIFIED (never PASS), mismatches=null; M8-03 cleanup +
  persistence outcomes recorded, terminal PASS gated on both, lock released in
  outermost finally; M8-04 exclusive run-dir allocation + atomic record
  publication; M8-05 record-command run-id validation + containment; M8-06
  storage admission (256 MiB disposable budget, 512 MiB headroom) before any
  hardware mutation; M8-02 partial — byte/dimension/format limits before
  decode, single read, decode of exactly the hashed bytes, image admission
  before the switch.
- **E2 CLOSED (2026-09-14, board-proven):** extremes x5 profiles (20 stimulus
  frames, zero-tolerance exact-reference verification, both saturation rails,
  signed-24 bias endpoints, shift-0, reinstall-revalidate lifecycle) + matrix
  rerun with 20 provably consecutive A32-B32-A32 cycles (bridge construction;
  58 switches, 58 reloads, 20/20 pairs, 57.5 s). Evidence:
  report/evidence/e2_extremes_matrix_20260914.txt. **M8 IS COMPLETE.**
- **M8-02 CLOSED (2026-09-14, board-proven):** m8_cli --image decoding routes
  through the M2 isolated bounded worker (LinuxDecoder with root-supervisor
  demotion); board evidence in report/evidence/m8_02_worker_isolation_20260914.txt.
- **M8-07 CLOSED (2026-09-14, disposition):** single-admitted-context met -
  load_params admits one canonical bundle and returns its immutable SHA-256;
  reference, hardware frames and the archived record all bind to that admitted
  state (schema v3: bundle_sha256, per-file parameter hashes, catalog/anchors
  hashes). Assets are content-addressed via git-tracked canonical bundles plus
  conversion receipts; per-run byte preservation consciously traded for hash
  binding.
- **M9 prep:** execution checklist at M9_CHECKLIST.md (1,000-frame varied
  soak plan, five true power-cycle cold boots, clean-build reproduction,
  release tag, known-limits list).
- **M8-02 CLOSED (2026-09-14, board-proven):** m8_cli's `--image` path decodes
  through the M2 isolated bounded worker (`conv_lab.preprocessing.LinuxDecoder`);
  a scoped root-supervisor extension (`demote_to=(uid,gid)`) drops the worker
  subprocess to the board user before exec — the worker keeps its own privilege
  refusals, 128-MiB RLIMIT_AS, 30 s supervisor deadline, bounded IPC and zero
  inherited descriptors. Board evidence
  (`report/evidence/m8_02_worker_isolation_20260914.txt`): positive run with
  `resource_strategy=linux-process-rlimit-as-supervised-v1` and canonical hash
  matching the independent decode; negative non-image run rejected inside the
  worker with zero hardware writes. Board copies: m8_cli md5 `610b4449…`,
  conv_lab/{preprocessing,_decoder_worker,types}.py pushed (payload m10fix.tgz
  14,557 B, b64 `01250f7d…`).
- **M7-R4 CLOSED (2026-09-14, board-proven):** explicit legacy conversion of
  all five parameter bundles to the canonical-flat-2 dialect
  (`scripts/convert_legacy_profiles.py`, receipts in
  `profiles/history/legacy_conversion_20260914.json`, canonical bundles tracked
  under `profiles/<P>/`); `load_params` strictly admits only that dialect via
  conv_lab.strict (exact field sets, boolean relu_en, coefficient grammar over
  hashed bytes, bundle-declared signed-24 bias width) and returns an immutable
  whole-bundle SHA-256 logged at admission; `switch_to` cross-validates
  manifest vs catalog before hardware writes; `validate_identity` checks
  WIDTHS_0/WIDTHS_1. Board evidence:
  `report/evidence/m7_r4_strict_admission_20260914.txt`. Board copies:
  m7_switch md5 `8b4315b8…`, m8_cli md5 `bfdbb39b…`, canonical configs pushed
  (payload m9fix.tgz 18,048 B, b64 `f5ca1a8b…`).
- **M8 Phase B importer BOARD-PROVEN (2026-09-14):** `software/m8_import.py`
  (md5 `899f65e3…`, needs `/home/petalinux/conv_lab/` = 3-file grammar package
  `__init__/errors/strict` — pushed; keep in sync with repo's conv_lab) imports
  model/dataset transport archives with strict validation, identity collisions
  rejected, idempotent same-content re-import, receipts outside bundles.
  Host suite 15/15 PASS; board import/already-imported/list PASS
  (`report/evidence/m8_import_board_20260914.txt`). Hardware-bundle import
  explicitly unsupported this release.
- **Push lessons (2026-09-14):** never extract tars containing directory
  entries with sudo over live dirs — it clobbers ownership (fixed via
  `chown -R petalinux:petalinux /home/petalinux`; extract as petalinux or omit
  dir entries); re-confirmed §9's never-double-gunzip rule for .tgz transports.

The old per-step M7 push/run instructions below this section were
executed and are preserved only in git history / the amendment note that follows.

## M7 foundation amendment — 2026-09-12 (SUPERSEDED)

Superseded by §16. Its "current source keeps B32 selected" claim is stale (the
selected RTL snapshot is the D640 projection per the review), and its "tests NOT
RUN" claim was overtaken by the foundation test runs and then by the mocked
end-to-end suite. Historical text kept below for provenance only.

Current source keeps B32 selected. profiles/m7_profiles.json owns the five frozen
IDs/geometries; wrapper defaults now use CFG_BUILD_ID. Focused integrated discovery
and guarded DMA tests are implemented but NOT RUN. M7_CONTINUATION.md contains
exact user commands and corrected D640 RX=313728 / exact-length guidance. A32
metadata was already 32 hexadecimal digits in the inspected file; it is unchanged and
the original is preserved under profiles/history. No deployed-file verification.
The full per-profile M5 gate (>=100 frames without inter-frame RESET) and M7
switching/cold-boot requirements remain; this amendment claims no qualification.
---

## 17. CURRENT STATE — 2026-09-14 evening (context-reset safe; supersedes older sections)

### 17.1 Where the program stands
- M0–M7: closed (evidence in §10 + report/evidence/). M8: functionally
  complete and board-proven (E2 closed, ac84c3e) BUT Codex review R14-02/03
  found P1 defects in the NEW soak path and exit-code semantics — M8
  acceptance was CONDITIONAL on the repair batch: that batch is now COMMITTED
  (73bb803, R14-02..05 + R14-01 containment option (b) with max_shift=23)
  and BOARD-REVALIDATED 2026-09-14 (soak5-A32 + A32 image run PASS on the
  repaired code; records in report/evidence/schema_v3_records_20260913/).
  M9: §1 done, §2 done (1,000-frame varied soak, 6/6 legs PASS, ef5c614),
  §3 done (five true power-cycle boots, a3f31a5), §4 done 2026-09-14 — the
  clean-build gate is satisfied per its actual wording ("reproduce results"):
  M7 built five fresh isolated profile projects from the scripted flow and
  qualified each on board, and the live D640 artifact matches its manifest
  sha256 64849132…; a bit-identical bitstream re-hash was not performed and
  is not required (RELEASE_MANIFEST_v1-m9-release.md). §5 (tag + final
  docs) staged — tag application is the user's action.
- User directive: deadline pressure is OFF (user's own business). Quality
  and evidence discipline govern sequencing.
- Branch `v1-bringup` is 17+ commits ahead of origin/v1-bringup — PUSH
  pending (user action, do at next convenience; Codex FP-01 Gate 0 item).

### 17.2 Codex review (feedback.md, three parts) — dispositions committed
`INTEGRATION_PLAN_M10_M12.md` Addendum A (ba1b3ef) records verified
dispositions for: FP-01..08 (feasibility), IP-01..11 (integration-plan
corrections), R14-01..10 (current-work findings). Key verified facts:
- R14-01 [P1, RTL, OUR BASELINE]: conv_channel S4 rounding overflows at
  shift 24 / mis-rounds 25-31 (fixed-width constant at C_FULL_W=25).
  Containment decision PENDING USER: (b recommended) freeze baseline with
  admission-restricted shift range + documented limit, real fix rides M11
  (teammate S4/S5 implements the contract's discarded-bit alternative);
  or (a) rebuild+requalify all five profiles now.
- R14-02/03/04/05 [P1, sw]: soak admits image AFTER hardware switch;
  cleanup/persistence failure exits 0; bias validated vs bundle width not
  hardware width; unbounded supervisor read_bytes. ALL ACCEPTED — repair
  batch queued (17.4 step 1), mock suite must gain the negative cases.
- R14-06..10 [P2]: accepted, scoped post-repair batch.
- Integration corrections: 00a6e11 is a DIRECT child of fb66066 (selective
  transplant onto mainline, never wholesale merge); EF125 physical numbers
  PROVISIONAL (no artifacts on the remote branch; +0.201 vs +0.178 WNS
  discrepancy unresolved); CFGLUT5 engine is N3-specialized but K-GENERIC
  (A32/D32/D640 = config rebuilds; only C32/N5 needs a new generator);
  teammate release package ships OLD permissive manager + legacy dialect —
  never adopt it; unit discipline: results vs positions vs beats.

### 17.3 Research branch (feature/k16-cfglut5-edgefree-125mhz @ 00a6e11)
Teammate handoff committed: HANDOFF_v1bringup_to_edgefree125.md.
EF125K16N3W32R01, 125 MHz WNS +0.178 (teammate-confirmed 2026-09-14; the
+0.201 in the handoff table was an earlier design — IP-02 discrepancy
closed; routed reports still untracked, numbers provisional until the
artifact package arrives), CFGLUT5/Dadda bitheap, edge-free
windowing (judge bonus), 5-stage pipeline, host-only qualification
(1,007 tests + A-H wrapper incl. edge-bubble metrics; Board NOT_RUN).
M10-M12 plan committed with Addendum A corrections: Gate 0 baseline
recoverable → Gate 1 research build contract → Gate 2 B32_CFGLUT125 first
(N3 K4/K8 variants after; C32/N5 stays legacy) → Gate 3 board qualification
→ Gate 4 matched comparison (MAC100/CFGLUT100/CFGLUT125).

### 17.4 ACTION QUEUE (exact order, awaiting user GO per item)
1. **DONE 2026-09-14 (commit 73bb803):** repair batch R14-02..05 (shared
   finalization + nonzero exit + lock in outermost finally; soak image
   admission hoisted above switch_to; hw bias_width threaded into
   load_params; bounded supervisor read) + mock negatives 8->17 cases all
   PASS + C_FULL_W stale comment fixed. R14-01 containment: option (b)
   IMPLEMENTED as admission max_shift=23 (defective range is 24..31; note
   the plan's "shift<=8" premise was wrong — B32 ch2 ships shift 9).
2. **DONE 2026-09-14 (board):** /lib/firmware/m7_A32.bin (b59378e4…) and
   runtime hardware_A32.json recovered to the repo (bitstreams/m7_A32.bin,
   software/hardware_A32.json — FP-02 closed); repaired soak + image run
   PASS on board; the true schema-v3 soak records pulled to
   report/evidence/schema_v3_records_20260913/ (see its MANIFEST.md for the
   extremes-records and matrix-log gaps that remain open).
3. **DONE (folded into 1):** R14-01 admission restriction (option b).
4. **DONE 2026-09-14 (reframed):** M9 §4 — the clean-build gate is met by
   the M7 fresh-profile-build campaign (results reproduction) + the impl_1
   D640/manifest hash match; RELEASE_MANIFEST_v1-m9-release.md carries the
   artifact sha256 table and the full known-limits list. §5 tag
   `v1-m9-release` = user action on the commit that contains this note.
5. **Push branch to origin** (user action; ~24 commits after the tag).
6. **M10** per INTEGRATION_PLAN (Addendum A order): baseline recoverable →
   research build contract → B32_CFGLUT125 first → board qual → matched
   comparison (M12). C32/N5 stays legacy until an N5 generator exists.

### 17.5 Operational lessons added this session
- Serial/chat transport can DROP '+' characters from base64 (m13f round):
  transport payloads as PLUS-FREE base64 (tr '+' '.' locally, tr '.' '+'
  on board before decode); chunk md5 gates caught it both times.
- Tarballs containing directory entries extracted with sudo clobber live
  dir ownership (chown -R petalinux:petalinux /home/petalinux fixed it);
  extract as petalinux or use --strip-components.
- Mock suites must exceed thresholds that real runs hit (soak progress
  print at frame 25 crashed with 5-frame mocks; log() vs print()).
- Cleanup scan buffered: CLEANUP_SCAN_20260914.md (do not delete anything
  without re-running it; Temp holds the only legacy bundle sources —
  archive to profiles/history first).

---

## 18. CURRENT STATE — 2026-09-14 Gate 3 live board qualification

This section is the authoritative resume point. Read it first, then read
`M10_RESUME_HANDOFF.md`, `INTEGRATION_PLAN_M10_M12.md`, and the two current
evidence files named below. Older sections remain historical evidence and
must not be used to infer the current branch, clock, datapath, or next action.

### 18.1 Human/AI working agreement

- The user is the engineering collaborator and final operator, not a passive
  copy/paste endpoint. Give a short explanation of what every command proves.
- The AI directly edits repository files and runs local Windows commands and
  tests. Do not generate prompts for another coding agent; the user explicitly
  stopped using one.
- The user runs only commands that require their environments: Vivado Tcl in
  the GUI console, Ubuntu/PetaLinux commands in the VM, and PuTTY commands on
  the ZedBoard. Give exact commands and wait for their output when evidence is
  needed.
- Put `sudo -v` in its own copy/paste block. Put later `sudo -n ...` commands
  in separate blocks because a password prompt can interrupt subsequent pasted
  commands.
- Prefer one or two meaningful tasks per message. Deadline pressure is real,
  but never claim PASS without evidence, never overwrite a recovery artifact,
  and never guess a path, device, build identity, or live state that can be
  inspected.
- Tone: concise, technically direct, collaborative, and calm. Avoid excessive
  headings and celebrations. The user appreciates plain-language reasoning
  alongside exact engineering detail.
- Before editing, inspect the working tree and applicable files. Preserve user
  changes, use `apply_patch`, run proportional tests, and commit coherent
  verified increments. Do not create another Vivado project casually; the
  research-release flow intentionally creates isolated generated projects
  under `work/` without replacing the user's main project.

### 18.2 Repository truth

- Workspace: `D:\MyProjects\Convlution_Accelerator`
- Current branch: `integration/m10-cfglut5`
- Baseline tag: `v1-m9-release`
- Current work has completed the selective CFGLUT5 integration and the first
  research build; do not wholesale-merge the teammate branch.
- Last code/evidence commits before this handoff update:
  - `3eb5074` — repair release catalog and declared-clock metadata.
  - `8e91d24` — record live 125 MHz boot identity.
  - `d6049b4` — fix release-to-parameter-bundle resolution and qualify the
    initial live activation.
  - `f262783` — extend and qualify numerical extremes, including shifts
    24–31.
- The first hardware release is `B32_CFGLUT125`: N=3, K=16, W=H=32,
  CFGLUT5/Dadda exact datapath, edge-free internal position pipeline, 125 MHz.
- BUILD_ID hex: `45463132354b31364e33573332523031`; ASCII:
  `EF125K16N3W32R01`.
- The release deliberately reuses the canonical `profiles/B32` parameter
  bundle. Hardware release names and bundle directory names are orthogonal.
  `software/m8_cli.py` must resolve `releases.<id>.bundle_dir`; never regress
  to `profiles/<release-id>`.
- Canonical B32 bundle SHA-256:
  `952cb13ce0adad04c42704c1e85bd964538cf66f8455783b2123bbce9d160cec`.
- Frozen output anchor SHA-256:
  `5821c8b19a88fd34e3002dd7b0c7d60c7fcd79b8a61a326697d95b6e3ec3be94`.

Key build evidence:

- Routed bitstream SHA-256:
  `133713c5eca1f8a41a7baa40719e1c101364f3a835111028db925a7d7a309858`.
- FPGA-manager `.bit.bin` SHA-256:
  `4e827310eb7f1e8c9278d0c9b36905eb4b7c766d9878a3a551e1909843d5b73b`.
- XSA SHA-256:
  `e90b84413bf35d8da2aa5b5a86b5ea41e2519360fd593b60c9f3a918544f648d`.
- Vivado 2025.2 route: WNS `+0.157 ns`, WHS `+0.019 ns`; timing met,
  DRC/route clean.
- Evidence directory: `report/research_builds/B32_CFGLUT125/`.
- Build/packaging source is the current mainline runtime plus canonical bundle;
  never use the teammate branch's old permissive manager or legacy parameter
  dialect.

### 18.3 Deployed image and live board state

The board is currently powered, at the Linux shell, and booted from the new
B32_CFGLUT125 PetaLinux image.

- WIC SHA-256:
  `c99781f6e30a651c1fe878e9806f9e6b78a605eb46f0d6315516c0af6265e5f4`.
- Board `/boot/BOOT.BIN` SHA-256:
  `b91acd41a83eba8866c4385b5ff0d0ef9e38b1ad4b6c909d32c31d03783c04c4`.
- FPGA Manager: `Xilinx Zynq FPGA Manager`, state `operating`.
- Live discovery reads MAGIC `0x43564831`, ABI `0x00010000`, capabilities
  `0x000001FF`, W/H/N/K `32/32/3/16`, TX/RX `1156/32768`, DMA length width
  22, and the exact BUILD_ID above.
- Live FCLK0 is nominal 125 MHz, independently derived from SLCR:
  IO_PLL_CTRL `0x0001E000` gives FBDIV=30; FPGA0_CLK_CTRL `0x00200400`
  gives divisors 4 and 2; `33.333333 MHz * 30 / 8 = 124.99999875 MHz`.
  The kernel lacks debugfs, so do not retry debugfs clock commands.
- Boot/clock evidence:
  `report/research_builds/B32_CFGLUT125/board_boot_identity_20260914.md`.

Runtime provisioning is complete:

- Runtime transport archive SHA-256:
  `6779f85967ebd428113eb6219a85561f4400b68bc45aa9f151d8d4f40f60a3b0`.
- Forty-one `/home/petalinux` runtime files were verified byte-for-byte.
- `/lib/firmware` was absent in this image and was created explicitly before
  installing `m7_B32_CFGLUT125.bin`; the installed firmware hash is the
  expected `4e827310...b5b73b` above.
- Pre-runtime recovery archive:
  `/home/petalinux/release_checkpoints/G3_pre_runtime_20180309T125402Z.tar.gz`,
  SHA-256
  `bbeb4fc3061856fec509f4228a5113646465d4505be17b3ada088aee73b035a3`.
- The board RTC is unset; paths beginning `20180309` are not real execution
  dates. Host evidence dates are authoritative.
- Current board `m8_cli.py` SHA-256:
  `798c26f7834d8cb4c5f4ac404b0b333aa77b4e1b7d02647d282068fa384bb1ce`.

PetaLinux host state:

- VM project: `/home/walid/projects/zedboard_linux`.
- Current imported `system.xsa` matches the release XSA (`e90b844...`).
- Ubuntu was upgraded to 24.04. PetaLinux 2025.2 is unsupported there but the
  build completed after installing the official Jammy `libtinfo5` package and
  temporarily setting `kernel.apparmor_restrict_unprivileged_userns=0`.
  The restriction was restored to `1` after packaging.
- Shared folders may require remounting after every VM restart:
  `sudo mkdir -p /mnt/hgfs` then
  `sudo vmhgfs-fuse .host:/ /mnt/hgfs -o subtype=vmhgfs-fuse,allow_other`.
- Preserve the pre-XSA recovery checkpoint:
  `/home/walid/projects/release_checkpoints/G3_pre_xsa_20260914T101106Z/petalinux_pre_xsa.tar.gz`,
  SHA-256
  `92f0f4ddf68718d125067622c0db098978fab7e968ab1846c4f1dd350279f4c5`.

### 18.4 Gate status at handoff

Gate 2 is complete. Gate 3.1 (PetaLinux/XSA/WIC/boot), Gate 3.2 (live 125 MHz
clock), and these Gate 3.3 sub-gates are complete:

1. Release/catalog/firmware/bundle admission and live identity validation.
2. Parameter-only activation on the already-live research build.
3. Anchor-exact activation plus three additional frames: PASS; median
   `0.129 ms`, final cleanup STATUS `0x00000181`.
4. Numerical extremes: PASS, 12 exact-reference frames. This includes
   all-zero, all-255, signed-24 endpoints, both saturation rails, every live
   shift 24–31, and canonical reinstall/anchor revalidation. Shift 24 proves
   signed `+1/-1`; shifts 25–31 prove the corrected sign-extension result.
5. One 100-frame anchor-exact soak under a single activation: PASS, all 100
   frames bit-exact; median `0.125 ms`, p95 `0.128 ms`; cleanup STATUS
   `0x00000181`.

Board run records were retrieved from the rootfs and are now preserved in the
repository (copies also remain on the board):

- `/var/lib/conv-lab/results/20180309T131241Z-B32_CFGLUT125-library_alley_cat/record.json`
- `/var/lib/conv-lab/results/20180309T131821Z-extremes-B32_CFGLUT125/record.json`
- `/var/lib/conv-lab/results/20180309T132021Z-soak100-B32_CFGLUT125-library_alley_cat/record.json`

Full evidence narrative:
`report/research_builds/B32_CFGLUT125/board_runtime_qualification_20260914.md`.
The original record transport archive hashes to
`f9a36cde5ada13af40f1c91f85bd1d81d415ed6982110fc042773552c753038e`;
extracted schema-v3 evidence is under
`report/research_builds/B32_CFGLUT125/board_records_20260914/`.

### 18.5 Exact remaining order

**Superseding user directive (2026-09-14):** do not continue the previously
planned 100 MHz common-clock product path. The final polished system contains
five active releases only—A32, B32, C32, D32 and D640—and every one must use
the exact CFGLUT5 datapath, edge-free strategy and nominal 125 MHz FCLK0.
Legacy MAC/100 MHz artifacts and `B32_CFGLUT100` remain immutable historical
report evidence, but are excluded from the final catalog, firmware library,
PetaLinux image, demo UI and active build matrix.

The implementation order is now:

1. Generalize the deterministic CFGLUT5 bitheap generator to emit separately
   named exact 3x3 and 5x5 compressors. Preserve regeneration byte identity
   for the qualified 3x3 output.
2. Select the proper generated compressor in `conv_channel.vhd`; prove N=3
   has not regressed and add independent N=5 exactness, all-shift,
   saturation, ReLU, backpressure and configuration-lifecycle tests.
3. Create isolated 125 MHz research-release specs for A32, B32, C32, D32
   and D640, with unique BUILD_IDs and their existing canonical parameter
   bundles. Build all five and require nonnegative setup/hold slack, clean
   routing/DRC and artifact-bound manifests.
4. Replace the active runtime catalog/manifests/firmware library with those
   five releases only. Add a fail-closed live-FCLK compatibility check before
   FPGA Manager access. Historical releases stay under report/history paths.
5. On the verified 125 MHz PetaLinux boot, run identity + anchor activation,
   numerical extremes and at least 100 consecutive exact frames per release;
   run the full ordered switching matrix, recovery/fault tests and true cold
   boot qualification. D640 additionally proves the 640x480 static-image
   path and 4 MiB DMA allocation.
6. Pull and hash all evidence, freeze the five-release package, then update
   the report/demo. The report may compare against legacy 100 MHz results,
   clearly labelled historical and not normalized as a controlled
   same-source frequency experiment.

Final BUILD_IDs are:

| Profile | ASCII | Hex |
|---|---|---|
| A32 | `EF125K08N3W32R01` | `45463132354b30384e33573332523031` |
| B32 | `EF125K16N3W32R01` | `45463132354b31364e33573332523031` |
| C32 | `EF125K08N5W32R01` | `45463132354b30384e35573332523031` |
| D32 | `EF125K04N3W32R01` | `45463132354b30344e33573332523031` |
| D640 | `EF125N3K04VGA-R1` | `45463132354e334b30345647412d5231` |

The older numbered list below is retained as historical execution context;
where it requests 100 MHz building, booting, switching or deployment, this
new directive overrides it.

Do not mark `B32_CFGLUT125` QUALIFIED yet. Resume Gate 3.3 in this order:

1. **DONE — preserve the three board run records.** The archive and extracted
   schema-v3 records are checked into the research evidence directory.
2. **DONE — restore A32 inventory without hardware access.** Eleven files were
   installed and verified. Firmware SHA `b59378e4…`, manifest SHA `31c96657…`,
   bundle SHA `367fb1f5…`. Pre-install recovery archive:
   `/home/petalinux/release_checkpoints/A32_pre_restore_6f6742bc1bde4d43a2a3d9d6519c356e.tar.gz`,
   SHA-256 `e93acaef69395e7c58b041181df0ae1e76e8749c492d8eae631b780d32818018`.
   The installer explicitly reported that no FPGA or DMA device was accessed.
3. **Clock-safe repeated full-PL reconfiguration.** Do not load A32 on the
   current 125 MHz boot. `m7_switch.py` changes only the PL image; A32 is routed
   for 100 MHz with only about 100.7 MHz derived Fmax. First build and boot the
   same-source `B32_CFGLUT100` release, then exercise A32_MAC100 →
   B32_CFGLUT100 → A32 at the common 100 MHz clock for at least 20 complete
   cycles, with identity validation and anchor-exact activation after every
   load. Keep B32_CFGLUT125 as the separately qualified performance release.
   `B32_CFGLUT100` is now BUILT: WNS `+0.764 ns`, WHS `+0.011 ns`, DRC and
   routing clean; BIT SHA `a4c1a183…fff900`, firmware SHA
   `fe603bd1…e0dad`, XSA SHA `fc33afa0…64840`. Board validation is `NOT_RUN`.
4. **Fault/recovery.** Reuse the proven lifecycle/fault harness only after
   reviewing its target-profile assumptions. Inject bounded failures, verify
   nonzero exit/FAILED record, DMA halt, ERROR/FAULT accounting, RESET recovery,
   canonical parameter reinstall, and a final anchor-exact frame.
5. **True power cycle.** Halt Linux, switch board power off, restart from the
   research WIC, recheck BUILD_ID/FCLK, and run a fresh anchor-exact sample.
6. **Close Gate 3.3.** Pull all records/logs, verify hashes, update the
   qualification record tied to exact artifact hashes, and only then promote
   the release from BUILT to QUALIFIED. Keep qualification evidence outside
   immutable bundle manifests.
7. **Close G3.4 claim discipline.** The internal engine accepts one output
   position per cycle once filled, including edges. At K=16 on the 64-bit
   AXI-Stream output, each position is 32 bytes = four beats; therefore never
   claim one complete position per external bus cycle. Report positions,
   channel-results, beats, frames/s, and clock basis explicitly.

Then execute Gate 4 / M12:

1. Build `B32_CFGLUT100` from the same source and directives with only the
   controlled clock variable changed.
2. Run a matched comparison: `B32_MAC100` versus `B32_CFGLUT100` versus
   `B32_CFGLUT125`, using the identical B32 parameter bundle, image bytes,
   preprocessing, software path, warmup, frame count, and measurement method.
3. Preserve routed timing/utilization/power reports. Label Vivado power as a
   vectorless estimate unless activity-driven evidence exists.
4. Update the competition/research report with normalized throughput/FOM and
   edge-free evidence; produce the research release tag and final archive.
5. Re-run `CLEANUP_SCAN_20260914.md` before deleting anything. Preserve every
   artifact referenced by a manifest, qualification record, recovery record,
   report, or tag.

### 18.6 Known traps — do not rediscover them

- `B32_CFGLUT125` is a hardware release; its bundle directory is `B32`.
- The first M8 run failed with `profiles/B32_CFGLUT125` not found. It stopped
  before hardware mutation. The catalog-resolution fix is committed and live.
- The original extremes harness tested shift 0 only. Commit `f262783` adds
  the required live 24–31 sweep; do not replace the board file with an older
  packaged copy.
- System ILA was removed from the release build. Do not plan ILA capture as if
  the old GP0 debug bitstream were still deployed.
- The ZedBoard PS↔PL AXI-Lite address adapter must continue masking to the
  64-KiB aperture; losing that addrfix recreates the historical GP0 hang.
- DMA length width is 22 bits; AXI memory/stream data paths are 64 bits;
  AXI-Lite is 32 bits. Do not confuse buffer allocation with transfer length.
- Base64 pasted through chat/serial can lose `+`; use the documented plus-free
  transport or, preferably, verified SD/FAT transfer for larger files.
- Never extract a tar containing live directory entries as root over
  `/home/petalinux`; it can clobber ownership. Stage as `petalinux`, back up
  exact targets, install explicit files, and verify byte-for-byte.
- PetaLinux packaging must use the selected verified release bitstream, never
  an incidental generated `system.bit`.
- `/bin/sh is not bash` and Ubuntu 24.04 warnings are expected host warnings;
  actual missing libraries or BitBake user-namespace failures are blockers.
- Windows sees only the FAT boot partition. Safely halt/eject before moving
  the SD card. Identify the removable FAT volume instead of guessing a drive
  letter.
- The board RTC is stale. Never use its timestamps as chronological proof.
- Preserve a dirty worktree unless inspected. Never use `git reset --hard` or
  delete generated/recovery artifacts merely to make status look clean.

### 18.7 First message for a new AI session

The user should tell the new session:

> Read `AI_HANDOFF.md` section 18 completely, then verify the current git
> branch/status and read `M10_RESUME_HANDOFF.md`,
> `INTEGRATION_PLAN_M10_M12.md`, and both B32_CFGLUT125 board evidence files.
> Do not change anything until you can restate the exact live board state,
> completed Gate 3 sub-gates, artifact hashes, and the next safe action. From
> then on, edit and test repository files yourself; give me only Vivado Tcl,
> Ubuntu/PetaLinux, or PuTTY commands that require my environment. Explain
> briefly what each command proves, and keep sudo authentication in a separate
> block.

The best continuity check is not conversational memory; it is whether the new
session independently reproduces §18.2–§18.5 from the repository and evidence
without inventing state.

### 18.8 Five-profile CFGLUT125 geometry checkpoint — 2026-09-14

Commit `72763d5` replaced the abandoned 100 MHz product target with the
user-approved five-profile CFGLUT5/edge-free/125 MHz target. Work immediately
after that commit generalized the exact generated compressor:

- `scripts/generate_cfglut_bitheap.py` emits deterministic 3x3 and 5x5
  entities. The canonical 3x3 output remains byte-identical to its earlier Git
  blob (`ad49b540...27aa7`).
- The new 5x5 compressor handles 25 taps / 50 signed rows at the approved
  22-bit sum width. Its nine Dadda targets are
  `42,28,19,13,9,6,4,3,2`, with register boundaries after levels 3 and 6.
- `conv_channel.vhd` selects the 3x3 or 5x5 entity at elaboration and derives
  its local sum/accumulator width from `C_N`. `conv_engine.vhd` now accepts
  exactly N=3 or N=5.
- User-executed Vivado 2025.2 regression PASS: existing 3x3 exact test,
  existing 3x3 5,120-output all-shift pipeline test, new nonzero 5x5
  exact/reload/backpressure test, and new 5x5 6,144-output all-shift/bias/ReLU
  pipeline test. Tcl result was zero.
- Evidence boundary and exact markers are recorded in
  `report/research_builds/CFGLUT125_MATRIX/geometry_generalization_20260914.md`.

This closes the behavioral F3/N=5 feasibility blocker only. Next: freeze this
checkpoint, add the five 125 MHz release specs/catalog staging, run full
wrapper/profile simulations, then synthesize/route each release. No new
physical build or board claim follows from the geometry regression alone.

### 18.9 Five-release staging — 2026-09-14 (host-side complete, sims pending)

Following §18.5's directive, the four remaining CFGLUT125 releases are staged
host-side on `integration/m10-cfglut5` (B32_CFGLUT125 already existed and is
board-qualified). Release names deliberately carry the `_CFGLUT125` suffix
until the §18.5 step-4 catalog cutover renames them to the final five
(A32/C32/D32/D640); BUILD_IDs are already the final ones from the §18.5
table. Local canonical bundles verified byte-exact against the catalog
(D640 = D32 bundle bytes, as documented):

- New specs: `scripts/research_release/builds/{A32,C32,D32,D640}_CFGLUT125.spec.tcl`
  (A32 N3/K8, C32 N5/K8, D32 N3/K4, D640 N3/K4-640x480; all 125 MHz; sources
  include both generated bitheaps). `research_release.py check` PASS x5.
- Catalog `profiles/m7_profiles.json`: new `profiles` + `releases` entries
  for the four IDs (bundle_dir A32/C32/D32/D640; bundle shas carried over
  from the legacy entries).
- New manifests `software/hardware_<ID>_CFGLUT125.json` x4 with clock_mhz
  125, no rx_offset (IP-07), and deliberate `TBD_FIRST_BUILD` artifact hashes
  (fail-closed: `switch_to` cannot admit them until a real build fills the
  hashes). Final artifact filenames: `bitstreams/{a32,c32,d32,d640}_cfglut125_125mhz.{bit,bit.bin}`.
- `profiles/anchors_m7.json`: anchors transferred from the legacy profiles
  with provenance notes (same bundle + input + geometry => same golden
  output; C32 rides the 6,144-output N=5 regression).
- `software/m7_switch.py` FW_NAME: added m7_{A32,C32,D32,D640}_CFGLUT125.bin.
- **Wrapper TB generalized to the profile matrix** (this was the blocker for
  full wrapper/profile sims): `sim_1/imports/new/tb_conv_axis_wrapper.vhd`
  now supports N in {3,5} x K in {4,8,16} with all geometry from config_pkg
  (N x N reference convolution, N*N coefficient packing -> C_COEFF_WORDS,
  generic final input beat incl. the C32 exact-multiple frame,
  geometry-scaled partial-frame ABORT beat count and hang-detector timeout).
  K16/N3 stimulus semantics are unchanged. Mock suites re-PASS
  (m7_switch --profile B32 3 + --matrix-seq; m8 suite 18 cases after fixing
  its stale extremes expectation to the board-qualified 12-stimulus set).
- New sim runner `scripts/research_release/test_profile_wrappers.tcl`
  (profile-matrix generalization of test_edge_bubbles.tcl): runs the A-H
  wrapper regression per release against the rendered per-release
  config_pkg with N-aware metric expectations; usage
  `set argv {<RELEASE_ID> optimized}; source ...` from the Vivado Tcl
  console. All five `work/research_<ID>/src/config_pkg.vhd` renders are in
  place; the B32 re-render is byte-identical to the qualified build's
  (sha256 1e24e3a8...), so its provenance is untouched.

Superseded status: the user-executed five-profile wrapper matrix later passed
from a clean, source-bound commit; see §18.13. The remaining sequence is the
five `research_build.tcl` routed builds, then board qualification per §18.5
steps 5-6.

### 18.10 Wrapper-sim bring-up: duplicate-beat bug + edge-free claim scope (2026-09-14 evening)

The first B32 wrapper-sim attempt hung after frame C. Root cause was NOT the
RTL: `8c0425f`'s conv_channel/conv_engine changes are N=3-equivalent (proven
by running the pre-edit TB against current RTL: PASS). The hang was a
testbench bug introduced by the generalization edit: the frame sender's new
conditional trailing-beat block was added WITHOUT removing the original
unconditional trailing `send_input_beat`, so frame C carried a second
TLAST beat. The DUT correctly completed the frame at 1156 bytes and gated
further input; the TB spun forever on the rejected beat. Instrumentation
(DEBUG_SEND_BEAT/BEAT_ACCEPTED reports) pinpointed 146 beats sent / 145
accepted / the duplicate keep=15 TLAST beat spinning. Fixed and verified:
full A-H B32 regression passes with metrics byte-identical to the
historical fixture (commit `8dd1d31`).

**Edge-free claim scope (engineering finding, wrapper-level):** Option A
limits the external zero-bubble output claim to A32/B32. Evidence from
the generalized A-H fixture (benchmark frame D = guaranteed supply,
continuously ready sink):
- B32_CFGLUT125 (K16/N3): strict PASS, frame D invalid_advances=0, gaps=0.
- A32_CFGLUT125 (K8/N3): wrapper-complete with frame D
  invalid_advances=31, external gaps=0; the serializer hides the internal
  transition bubbles.
- C32_CFGLUT125 (K8/N5): frame C exact and complete, frame D asserts
  "Unexpected output gap" at the first row transition (beat 64 = position
  32); frame C WINDOW_METRICS invalid_advances=32 (vs 0 at N3).
- D32_CFGLUT125 (K4/N3): same signature; frame D gap at beat 32 = position
  32; frame C invalid_advances=57.
Working explanation (analysis, consistent with all four points, not
cycle-proven): the window generator's valid drops for the first N-1 pixels
of each padded row (any N); the prefetch/serializer slack hides those holes
when the output path carries >=2 beats per position (K>=8 at N3), but not at
K4 (1 beat/position) and not for N5's 4-wide hole. Correctness is NOT
affected: in both failing runs frame C completed with every output scalar
bit-exact; only the zero-gap assertion tripped. Consequence per the G3.4
claim discipline: the "one position per clock including edges" judge-bonus
claim attaches to A32/B32 only; C32/D32/D640 run the fixture with
G_REQUIRE_CONTINUOUS=false (`optimized_relaxed` variant of the runner) and
record measured transition bubbles. A source-level fix (window generator
producing valid windows on transition pixels) is a scoped follow-up design
task, not a release gate.

**USER DECISION 2026-09-14 (option a): freeze the five-release package with
the gapless claim on A32/B32 only; C32/D32/D640 documented with measured
transition bubbles.** Final wrapper-sim matrix (all five releases, A-H
complete, AI-driven batch xsim): B32 strict PASS metrics (0/0), A32 strict
PASS metrics (31/0); C32 relaxed PASS (62/31), D32 relaxed PASS
(62/62), D640 relaxed PASS (958/958) — frame D invalid advances / external
output gaps; one-to-two bubbles per logical row transition, ~1.5% / ~6% /
~0.3% of frame output beats. A second fixture bug surfaced at D640: the
reference summed untruncated pixel integers while the byte stream truncates
r+c to 8 bits (first mismatch at position 252: expected 2286 vs the DUT's
correct 2030); fixed with `mod 256` in the TB's input_pixel_value. The DUT
was bit-exact against its actual input in every case; no datapath change was
needed. Full record:
`report/research_builds/CFGLUT125_MATRIX/profile_wrapper_sims_20260914.md`.
The runner's `optimized_relaxed` variant + geometry-aware checker encode the
claim scope; `debug_wrapper_sim.tcl <RELEASE_ID> <TB> <require_continuous>`
is the batch bisect tool. Both official and debug runners now allocate unique
microsecond/PID directories and refuse reuse.

### 18.11 GLM review round — five-profile staging + wrapper campaign (2026-09-14)

`feedback.md`'s newest layer (GLM-F1..F8) reviewed commits 523b0fd..6a2c5f6
and blocked the routed builds until fixed. Dispositions, executed in the
reviewer's required order:
- **F1 (P0, fixed):** `conv_lab/profiles.py` strict loader accepted only the
  seven-entry catalog; the eleven-entry staging catalog broke
  `tests.test_m7_profiles` (12/12 errors). Loader + tests now define the
  exact eleven-release staging set (final five only at cutover); 12/12 PASS.
- **F2 (P0, fixed):** `test_profile_wrappers.tcl` never parsed
  CFG_UNPADDED_HEIGHT (`$spec_h` undefined in expr) and called check_metrics
  with 4 of 5 parameters — deterministic post-sim failures the batch debug
  runs could not catch. Both fixed; every regexp return is now checked
  fail-closed; H is bound in the identity comparison.
- **F3 (P1, fixed):** `research_release.crosscheck` now binds spec
  N/K/W/H == catalog profile fields, canonical shape string,
  profile==release_id, profile/release/spec build-ID agreement, and 125 MHz
  for _CFGLUT125 releases. Negative tests:
  `scripts/research_release/test_spec_crosscheck.py` (7 cases).
- **F5 (P1, fixed):** debug runner uses unique timestamped out dirs, never
  deletes, records TB/config SHA-256 in run_meta.txt, and exits nonzero on
  any missing PASS marker or Failure/Error/Fatal.
- **F6 (P1, fixed):** `m7_switch.release_bundle_dir()` added; `--soak` and
  `do_switch_frames` resolve the catalog bundle_dir instead of the raw
  release name. Mock coverage: `--candidate-undeployable profile|soak`
  proves A32_CFGLUT125 is rejected before any hardware mutation (catalog/
  firmware/F7-hash gates; registers byte-identical, zero program calls).
  ORDER stays the legacy five until catalog cutover.
- **F7 (P2, fixed in code):** the four candidate manifests carry explicit
  `release_status: candidate-unbuilt` / `deployable: false`, and
  `switch_to` rejects any manifest whose artifact hashes are not canonical
  64-hex SHA-256 (clean GLM-F7 error instead of a hash mismatch). The
  cutover packaging gate (reject TBD_*, 100 MHz entries, suffixed names,
  missing firmware) is a recorded cutover checklist item.
- **F8 (P2, fixed):** the TB's trailing-beat TKEEP is generated from
  C_FINAL_INPUT_BYTES (contiguous low-lane mask) instead of the hardcoded
  x"0F"; the remainder assert now admits any beat-sized remainder, and a
  synthetic W=33/H=33 fixture (remainder 1) passed the full strict A-H
  regression (frame D 0/0).
- **F4 (P1, still open after GLM):** GLM re-ran the matrix, but A32/B32 exited
  1 after successful simulation because `check_metrics` read `spec_k` outside
  its Tcl procedure scope. The collection is preserved honestly at
  `report/research_builds/CFGLUT125_MATRIX/wrapper_glm_provisional_20260914/`.
  C32/D32/D640 exited 0; A32/B32 retain useful functional logs and metrics but
  no official terminal PASS. User-executed clean-commit qualification remains
  required.

### 18.12 Codex takeover after GLM corrections (2026-09-14)

The user ended external-agent delegation; Codex now owns repository edits and
Windows-side checks. The user continues to execute supplied Vivado Tcl,
Ubuntu/PetaLinux and board-shell commands. Option A is locked: only A32/B32
may advertise zero external output bubbles; C32/D32/D640 ship exact with their
measured row-transition bubbles documented.

Takeover audit outcome:
- GLM's eleven-entry staging loader, release geometry/identity crosscheck,
  bundle aliases and generalized TKEEP pass focused host tests.
- Fixed the remaining official-runner scope fault by passing `spec_k`
  explicitly. Every rendered/spec regexp is now fail-closed; evidence paths
  use microsecond/PID nonces; official runs refuse a dirty tracked tree.
- The official runner now emits `run_meta.txt` (commit and exact
  runner/testbench/rendered-config hashes) and `run_result.txt` (exact terminal
  marker and Option-A scope). `preserve_wrapper_evidence.py` no longer launches
  Vivado: it collects user-run results, verifies all bindings against the same
  clean commit, refuses overwrite, and generates complete SHA-256 evidence.
- Candidate manifests are explicitly `deployable:false`; `m7_switch.py` now
  rejects that field before firmware access or any hardware mutation, in
  addition to rejecting placeholder/noncanonical hashes.
- Corrected the report: A32 frame D is 31 internal invalid advances / 0
  external gaps, not 0/0. This distinction is central to Option A.
- Takeover host verification passed: 8 release crosscheck/tamper tests, 12
  M7 profile tests, deterministic 3x3+5x5 generator check, five release checks
  and exact render checks, B32/matrix/candidate M7 mocks, the full M8 mock
  suite, 15 importer tests, and static parsing of 49 Python plus 7 JSON files.
  No Vivado simulation/build or hardware command was executed by Codex.

Immediate gate: commit the repaired staging state, then the user runs the five
official wrapper regressions from that clean commit (A32/B32 `optimized`,
C32/D32/D640 `optimized_relaxed`). After collection passes, build risk-first:
C32, D640, A32, D32, then rebuild B32 for uniform provenance. Only B32 has a
routed and board-qualified 125 MHz CFGLUT5 artifact at this checkpoint.

### 18.13 Official five-profile wrapper matrix accepted (2026-09-15)

The user executed the complete official Vivado 2025.2 wrapper matrix from
clean commit `1f68ccf3e2e20a7c228365ef8b03de72ff22f99f`. Every profile passed
the A-H wrapper regression, emitted the exact profile identity marker and
returned Tcl RC=0:

- B32_CFGLUT125 `optimized`: frame-D invalid advances / external gaps = 0 / 0.
- A32_CFGLUT125 `optimized`: 31 / 0; external gapless, internal bubbles recorded.
- C32_CFGLUT125 `optimized_relaxed`: 62 / 31.
- D32_CFGLUT125 `optimized_relaxed`: 62 / 62.
- D640_CFGLUT125 `optimized_relaxed`: 958 / 958.

This is the accepted Option-A boundary: the zero-external-output-gap claim is
limited to A32/B32; C32/D32/D640 are exact and releaseable with their measured
row-transition bubbles disclosed. The official collection is
`report/research_builds/CFGLUT125_MATRIX/wrapper_official_user_20260914T210835Z/`.
`MANIFEST.json` binds all five runs to the commit, Vivado 2025.2 and the exact
runner/testbench/rendered-config hashes. Independent post-collection checking
passed all 16 `SHA256SUMS.txt` entries.

The repaired staging state was already committed as `8253be2`; the evidence
hardening followed as `1f68ccf`. The wrapper-simulation gate is therefore
closed.

The risk-first C32_CFGLUT125 routed build then passed from clean commit
`9c725cc4d667888cece0bb3982d95b6648725b5b`: 125 MHz, WNS +0.003 ns,
WHS +0.037 ns, zero timing failures, clean routing, zero DRC errors, and a
source-bound build manifest. Preserved BIT SHA-256 is
`8108a82fcbb7cec73aca919e58ef1c6725561444bfd6ee5887e8aa51315d866f`;
XSA SHA-256 is
`eb777ad376eb81687a834a7beb66de2f4085e0757522df53480d7b0dd6b43538`.
Reports are under `report/research_builds/C32_CFGLUT125/`; immutable artifacts
are under `bitstreams/`. C32 is BUILT, not board-qualified, and its candidate
runtime manifest remains fail-closed until `.bit.bin` generation and the board
gates.

Next routed build is D640_CFGLUT125, followed by A32, D32 and a B32 rebuild
for uniform provenance. Only the historical B32 125 MHz CFGLUT5 artifact is
board-qualified at this checkpoint; do not infer board qualification for C32
or the three unbuilt profiles from simulator or routed-build evidence.

### 18.14 D640_CFGLUT125 routed build accepted (2026-09-15)

The risk-second D640_CFGLUT125 build passed from clean commit
`180c2fafc5ec9d36344b101ca9ea7d5569b24002`: 125 MHz, WNS +0.001 ns,
WHS +0.022 ns, zero timing failures, clean routing, zero DRC errors and a
source-bound build manifest. Preserved BIT SHA-256 is
`6e95188e197f402bf9029295b3d4584111aa7b5afbb06802045596f49f41cca3`;
XSA SHA-256 is
`371a420baf8b20d1ad2cb0ad072bde8f101a232df0dc691e72f79b37742c9457`.
Reports are under `report/research_builds/D640_CFGLUT125/`; immutable artifacts
are under `bitstreams/`. D640 remains BUILT / BOARD_VALIDATION=NOT_RUN, and
the required 640×480 static-image plus 4 MiB DMA board gates remain open.

Next routed build is A32_CFGLUT125, then D32 and the uniform-provenance B32
rebuild. Firmware generation, final-manifest hash binding, catalog cutover and
board qualification follow only after the five routed builds are frozen.

## 19. GLM RESUME RUNBOOK — AUTHORITATIVE FROM THIS POINT (2026-09-15)

This section supersedes every older "next action", pending-build count and
agent-ownership sentence above. Historical sections remain evidence, but
execute from this section and observed repository state only.

### 19.1 Collaboration contract

- Repository: `D:\MyProjects\Convlution_Accelerator`.
- Branch: `integration/m10-cfglut5`.
- Last checkpoint before this handoff edit: `58fca2c1eae6fbb6ddde13d1b9c9b803089afaa3`.
- The coding agent inspects, edits, tests and commits repository files.
- The user alone runs supplied Vivado Tcl, Ubuntu/PetaLinux and ZedBoard-shell
  commands. Give one exact block, explain briefly what it proves, then consume
  its output. Never claim a user command ran without its output.
- Put `sudo -v` in a separate block before board commands needing sudo.
- Work in small verified checkpoints; update this file after each accepted
  routed build or board stage. Do not delegate, speculate, or celebrate.

Start every resumed session with:

```powershell
Set-Location -LiteralPath 'D:\MyProjects\Convlution_Accelerator'
git branch --show-current
git rev-parse HEAD
git status --short
git log -6 --oneline
Get-Content -LiteralPath 'AI_HANDOFF.md' -Tail 300
```

Stop if the branch differs, tracked changes are unexplained, or `58fca2c` is
not an ancestor. Never reset, clean, delete, overwrite or discard unexpected
state. Preserve and explain it.

### 19.2 Locked final product

Exactly five active releases, all exact generated CFGLUT5 bitheap,
edge-free/prefetch, nominal 125 MHz FCLK0:

| Release | Shape | Build ID | Wrapper/claim |
|---|---|---|---|
| A32_CFGLUT125 | N3 K8 32x32 | `EF125K08N3W32R01` | optimized; zero external gaps, internal bubbles recorded |
| B32_CFGLUT125 | N3 K16 32x32 | `EF125K16N3W32R01` | optimized; zero external gaps and frame-D internal invalid advances |
| C32_CFGLUT125 | N5 K8 32x32 | `EF125K08N5W32R01` | optimized_relaxed; exact with measured bubbles |
| D32_CFGLUT125 | N3 K4 32x32 | `EF125K04N3W32R01` | optimized_relaxed; exact with measured bubbles |
| D640_CFGLUT125 | N3 K4 640x480 | `EF125N3K04VGA-R1` | optimized_relaxed; exact with measured bubbles |

Option A is final. Advertise zero **external output gaps** only for A32/B32.
Never call A32 internally bubble-free. Frame-D `invalid_advances/gaps`:
B32 `0/0`, A32 `31/0`, C32 `62/31`, D32 `62/62`, D640 `958/958`.
All MAC/100 MHz artifacts including B32_CFGLUT100 are historical report
evidence only; exclude them from the active catalog/library/image/demo.

### 19.3 Accepted evidence/current state

1. Official five-profile Vivado 2025.2 A-H wrapper matrix PASS from clean
   `1f68ccf`; evidence is
   `report/research_builds/CFGLUT125_MATRIX/wrapper_official_user_20260914T210835Z/`.
   All 16 checksums verified; evidence commit `9c725cc`.
2. C32 BUILT / board NOT_RUN: 125 MHz, WNS `+0.003`, WHS `+0.037`, clean route,
   zero DRC errors. Source `9c725cc`; BIT SHA
   `8108a82fcbb7cec73aca919e58ef1c6725561444bfd6ee5887e8aa51315d866f`;
   XSA SHA `eb777ad376eb81687a834a7beb66de2f4085e0757522df53480d7b0dd6b43538`.
   Reports `report/research_builds/C32_CFGLUT125/`; commit `180c2fa`.
3. D640 BUILT / board NOT_RUN: 125 MHz, WNS `+0.001`, WHS `+0.022`, clean route,
   zero DRC errors. Source `180c2fa`; BIT SHA
   `6e95188e197f402bf9029295b3d4584111aa7b5afbb06802045596f49f41cca3`;
   XSA SHA `371a420baf8b20d1ad2cb0ad072bde8f101a232df0dc691e72f79b37742c9457`.
   Reports `report/research_builds/D640_CFGLUT125/`; commit `58fca2c`.
4. B32 has older routed/board-qualified 125 MHz evidence. Preserve it, but
   rebuild B32 last for uniform generalized-source provenance.

C32/D640 BITs are ignored under `bitstreams/` with hashes in tracked records;
their XSAs/reports are tracked. New `.bit.bin` and board qualification are open.

### 19.4 Immediate action — A32

Observed: `work/research_A32_CFGLUT125/` contains only `src/config_pkg.vhd`,
SHA `7434e32794e00ce54ddd9fde1ee94c0a863c629412fabd1146acff2883a96fe4`.
After confirming clean state, give the user:

```tcl
if {[llength [get_projects -quiet]]} { close_project }
cd {D:/MyProjects/Convlution_Accelerator}
set research_release_id A32_CFGLUT125
set build_rc [catch { source {scripts/research_release/research_build.tcl} } build_msg build_opts]
puts "BUILD RESULT: $build_rc"
puts "BUILD MESSAGE: $build_msg"
if {$build_rc} { puts [dict get $build_opts -errorinfo] }
```

Accept only `RESEARCH_BUILD_OK: A32_CFGLUT125` with nonnegative WNS/WHS and
`BUILD RESULT: 0`. On failure inspect the preserved run; never rerun blindly.

### 19.5 Mandatory post-build acceptance

Before requesting the next build:

1. Record clean Git HEAD/status.
2. Require `results.txt`: exact identity/shape, 125 MHz, WNS/WHS >=0,
   `BOARD_VALIDATION=NOT_RUN`.
3. Require BIT/XSA/routed DCP/reports; timing met with zero setup/hold failures,
   routing errors=0, DRC Error rows=0, methodology checks=0. Preserve warnings.
4. Run `python -B scripts/research_release/research_release.py manifest <ID>`;
   verify identity, clean source commit, timing and artifact hashes.
5. Refuse existing destinations. Copy (never move) BIT/XSA to lowercase final
   names in `bitstreams/`; copy manifest plus check_timing/drc/methodology/
   power/results/route/timing/tool/utilization into
   `report/research_builds/<ID>/`. SHA-verify every copy.
6. Add `BUILD_NOTES.md` like C32/D640. Say BUILT, never QUALIFIED; record source,
   timing, gates, utilization, hashes and open board work.
7. Stage XSA/notes/manifest/reports. Use
   `git add -f report/research_builds/<ID>/*.rpt` because reports are ignored.
   Keep the large BIT ignored; preserve Vivado report whitespace exactly.
8. Commit, require clean state, verify next render, update this handoff.

Final names: A32 `a32_cfglut125_125mhz.bit/.xsa`; D32
`d32_cfglut125_125mhz.bit/.xsa`; B32
`b32_cfglut125_125mhz.bit/.xsa` only after preserving old artifacts.

### 19.6 Remaining order and B32 trap

After A32 build D32, then B32. D32 is pristine with one render, SHA
`78c6169625362bff679ba29ba7f392dcd4d62a4bf85a8df78613953b3edb0d92`.

B32 is **not pristine**: `work/research_B32_CFGLUT125/` has the older full build
(787 files). Do not delete it or weaken the guard. After A32/D32 commits:

1. Verify tracked B32 build/board evidence and hashes.
2. Hash/archive the entire old work directory to a unique recovery path;
   verify, then move it to unique `work/archive/` storage.
3. Preserve old final B32 BIT/BIN/XSA under dated/history names before replacement.
4. Run `research_release.py prepare B32_CFGLUT125`; require render SHA
   `1e24e3a823d1a940378f19d708cbabdecce93e982a9a91c639c46ccce07e3f0d`
   and only `src/config_pkg.vhd`.
5. Build/accept normally. Old qualification is history; new B32 needs fresh binding.

### 19.7 After five routed builds

1. Generate exact FPGA-manager `.bit.bin` files using Bootgen Zynq
   `-process_bitstream bin`; verify hashes. Never substitute `system.bit`.
2. Bind canonical BIT/BIN filenames/hashes in manifests. Set
   `release_status: built-unqualified` and `deployable:true` only after complete
   file/hash/identity admission. Deployable means controlled test-loadable,
   not qualified; qualification remains external evidence.
3. Cut active catalog/runtime to exactly five; reject placeholders, missing
   firmware, 100 MHz and MAC entries.
4. Stage runtime on proven 125 MHz PetaLinux with recovery.
5. Per release: identity/FCLK, parameter admission, golden anchor, extremes/
   fault recovery, >=100 no-reset frames. D640 also proves actual 640x480,
   byte counts, approved four-guard 4 MiB layout and intact guards.
6. Run directed five-profile switching, repeated A32/B32, bounded recovery,
   then real power-off/on cold boot.
7. Pull/hash original records; only then mark QUALIFIED and update report/demo.

### 19.8 Prohibited shortcuts

- No RTL/numerical/ABI/DMA-width redesign during reproduction unless an actual
  failed gate requires a scoped user-approved fix.
- No 100 MHz/MAC artifact in the active final project; no claim inflation.
- No overwrite, reset-hard, git-clean, broad deletion, or non-pristine reuse.
- No guessed or cross-artifact hashes; no deployable flag before full admission;
  no QUALIFIED label before board evidence.
- No PL programming with live DMA/MMIO handles: quiesce, close, program, reopen,
  verify identity, then admit parameters.
- Simulation, timing closure and XSA creation do not prove board behavior.
