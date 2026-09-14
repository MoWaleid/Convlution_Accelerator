# AI_HANDOFF.md — Complete Project Context

**Purpose:** This is the single self-contained briefing for any AI assistant or engineer
continuing this project. If you have this file plus repository access, you need nothing
else to work effectively — it covers the system, the history, the workflow, and **how to
talk to the user** (§15). Every claim below was verified first-hand; state as of
**2026-09-13**, HEAD commit `9f6f68a` ("M6: qualify same-image full-PL reload");
all M7 work (now **board-qualified**, §16) is uncommitted in the working tree.

> **⚡ CURRENT STATE POINTER (2026-09-14, context-reset safe): read §17 first.**
> The sections below are historical layers; §17 supersedes all status prose in
> §3/§16/§16.6/§16.7 where they conflict (including this stale header line).
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
  §3 done (five true power-cycle boots, a3f31a5), §4 (clean-build
  reproduction) and §5 (tag v1-m9-release + known-limits) OPEN. The tag
  must NOT be applied until Gate 0 closes (see 17.4).
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
EF125K16N3W32R01, 125 MHz WNS(provisional), CFGLUT5/Dadda bitheap, edge-free
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
4. **M9 §4:** clean-build reproduction (user-executed Vivado; D640
   projection reproduces dn3k04_w640480 hash 64849132…; or A32 via
   prepare_profile) + §5 tag v1-m9-release + known-limits (incl. R14-01
   containment if (b)).
5. **Push branch to origin** (17+ commits).
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
