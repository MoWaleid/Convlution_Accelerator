# AI_HANDOFF.md — Complete Project Context

**Purpose:** This is the single self-contained briefing for any AI assistant or engineer
continuing this project. If you have this file plus repository access, you need nothing
else to work effectively. Every claim below was verified first-hand as of **2026-09-11**.

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

Git branch `v1-bringup`; HEAD `f711631` "finalized M3 officially" (2026-09-11); working tree clean; 245 tracked files.

| Path | What it is |
|---|---|
| `Convlution_Accelerator.srcs/sources_1/new/` | **The RTL** (VHDL-2008): `config_pkg.vhd` (K=8, N=3, widths), `conv_pkg.vhd` (array types), `window_generator.vhd` (SRL line buffers, zero BRAM), `conv_channel.vhd` (4-stage pipeline: multiply → add-tree L1 → add-tree L2+bias → round-half-up/saturate/ReLU; `use_dsp="no"`), `conv_engine.vhd` (K channels sharing one window), `conv_top.vhd` (AXI-Lite + datapath), `axi_lite_ctrl.vhd` (AXI4-Lite slave + globals), `coeff_bias_shift_regfile.vhd` (per-channel storage), `sync_fifo.vhd`, `axi_stream_input_frontend.vhd` (64-bit AXIS → byte lanes), `axi_stream_output_serializer.vhd` (K×int16 → 64-bit beats, TLAST framing), `conv_axis_wrapper.vhd` (top wrapper: frame-busy, backpressure freeze, soft reset), `conv_axis_wrapper_bd.v` (Verilog BD adapter; **masks AXI addresses to lower 16 bits** — the "addrfix") |
| `Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/` | The tracked block design `accelerator_dma.bd` (includes the debug `system_ila_0` on GP0) |
| `Convlution_Accelerator.srcs/sim_1/new/` | 10 unique testbenches (`tb_conv_top` custom K=4 bit-exact; `tb_conv_top_trained_k8` 8192-comparison trained regression; `tb_conv_axis_wrapper` streaming+backpressure+soft-reset; `tb_axi_lite_ctrl` 10-scenario AXI protocol; `tb_conv_datapath_stall`; frontend/serializer/window/regfile TBs). `sim_1/imports/new/` holds 4 byte-identical duplicates of sim_1/new TBs |
| `scripts/` | `create_accelerator_dma_bd.tcl` (rebuilds the BD deterministically) + `zedboard_ps_platform.tcl` (ZedBoard PS7 preset). **Note:** the tcl does not yet instantiate system_ila or set DMA `c_sg_length_width=16` (added by hand in the BD; tracked in `.bd`) |
| `software/` | `conv_lab/` (M2 PS software: strict validation, DMA layout math, sandboxed decoder, mock admission, independent integer reference), `tests/` (Groups A/B/C; B = 1000 seeded differential cases), `reports/` (host evidence JSONs + md), `m3_filebackend.py`, `m3_demo.py` (board scripts — **repo is the source of truth** for the on-board copies) |
| `deploy/petalinux/` | Finalized PetaLinux application pack: 3 recipes (conv-lab, conv-lab-starter, conv-lab-validation), rootfs configs, apply/preflight scripts, `SHA256SUMS.txt` (76 entries), `check_build_settings.sh` + `check_settings.py` (six-recipe `bitbake -e` evaluated-settings checker; **image target = `petalinux-image-minimal`, MACHINE = `zynq-generic-7z020`**) |
| `platform/accelerator_dma.xsa` | **Older** hardware handoff (no bitstream). The current tested XSA is `bitstreams/k8_gp0_ila_len16_2026-09-06.xsa` |
| `bitstreams/` (mostly gitignored) | 5 tested bitstreams, Sep 4→6: bringup → +ILA → resetfix → addrfix → **len16 (current tested build)**, each with `.ltx`; len16 `.xsa` |
| `debug_captures/` | ILA captures telling the bring-up story (GP0 AR deadlock → fixes), plus 2 board-rendered demo PNGs (`m3_demo_sobel_mag_*.png`) |
| `golden_model/` | Training + quantization + golden model + test vectors (see §6) |
| `verification/axi_address_normalization/` | SystemVerilog regression of the BD adapter + full RTL + `run_xsim.ps1` driver |
| `Important documents/` | Competition announcement PDF, spec-decisions (39 pp), master plan (12 milestones), ADR, `Architecture_Mapping.html` (**stale** — predates K=8 and the MAC array) |
| `AI_HANDOFF.md` | This file |

Untracked but present on disk: `.venv/` (Python 3.13 env with torch/numpy/Pillow/pypdf),
`checkpoints/k8_100mhz_postroute_physopt_met.dcp` (golden post-route snapshot),
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
| M4 integrate the exact hybrid incrementally | CVH1 ABI per contract; regression per subsystem; clean 100 MHz build | **NEXT — scoped in §9/§15** |
| M5 qualify one hybrid build end-to-end | ≥100 frames, lifecycle tests | pending |
| M6 same-image full reload | 20× A32→A32 via exclusive-owner lifecycle (FPGA Manager) | pending |
| M7 required profiles + model switching | A=N3/K8, B=N3/K16, C=N5/K8, D=N3/K4, D@640×480; switching matrix | pending |
| M8 reproducible operation and demo | CLI/API, run archive, previews, measurement harness | demo core exists (m3_demo.py); formal M8 pending |
| M9 freeze pre-research release | release tag, qualification matrix, 1000-frame soak | pending |

---

## 4. Hardware design essentials

- **Numeric contract:** uint8 Q0.8 pixels (value/256), int8 weights, per-channel int32
  bias (contract default moving to signed-24, sign-extended), 5-bit shift, per-channel
  ReLU. Arithmetic: `acc = bias + Σ pixel·weight`; `if shift: acc = (acc + 2^(shift-1)) >> shift`
  (round-half-up); saturate to int16; ReLU clamps negatives to 0. **Bit-exact** against
  `golden_model/golden_conv.py`.
- **Geometry:** logical 32×32, padded 34×34 (zero border), TX frame = 1156 bytes,
  output = 32×32×K int16 little-endian, order **y,x,channel** (channel-fastest) = 16384 bytes at K=8.
- **AXI-Lite register map (CURRENT legacy hardware):** accelerator base `0x43C00000`.
  Channel k at `k*0x100`: packed coefficient words `+0x00/+0x04/+0x08` (4×int8, coefficient 0 in bits 7:0),
  bias `+0xF8` (int32), control `+0xFC` (shift bits 4:0, relu_en bit 8).
  Globals: `0x4000` STATUS (bit0 idle, bit1 busy), `0x4004` CONTROL (write bit0=1 with
  WSTRB[0] → one-cycle soft-reset pulse; write-only; never reads nonzero),
  `0x4008` BUILD_CONFIG (N | K<<8 = `0x00000803`), `0x400C` IMAGE_DIMS (`0x00200020`).
  The BD adapter masks addresses to the 64 KiB aperture (lower 16 bits).
- **Block design:** PS7 (ZedBoard preset: DDR533, QSPI, SD, UART1, ENET0, USB0) +
  AXI DMA (simple mode, no SG, 64-bit both directions, `c_sg_length_width=16`,
  no DRE) + 2 SmartConnects + proc_sys_reset + module-ref accelerator + system_ila on
  GP0. Addresses: **DMA `0x40400000`/64K, accelerator `0x43C00000`/64K, HP0→DDR `0x0`/512M**.
  One 100 MHz clock domain, FCLK_RESET0_N → peripheral resets.
- **Build results (len16 build):** LUT 14,731 (27.7%), FF 14,092 (13.2%), BRAM 10.5
  tiles (7.5%), **DSP 0**, **WNS 0.000 / TNS 0.000 met — zero margin**, WHS +0.029,
  power est. 1.859 W, DRC clean. ⚠️ New RTL (M4.2+) may break 100 MHz; a pipelining pass is budgeted.
- **Bring-up history (Sep 4–6):** GP0 AR deadlock (ILA captured) → resetfix →
  addrfix (address normalization) → **len16** (DMA length width) → trained-CIFAR board
  run Sep 6. The five bitstreams in `bitstreams/` document this; **len16 is the tested
  build**. Boot-artifact gate: never program `images/linux/system.bit`; the tested
  bitstream is
  `D:\MyProjects\release_checkpoints\M0_k8_len16_20260907_052648_358\current_project\bitstreams\k8_gp0_ila_len16_2026-09-06.bit`
  (SHA256 `22097a5e3a1640fdc2505821c800c4df363d5e3390df02ee27d7b079ccdec80d`).
  The deployed `zedboard_M2P_2026-09-10.wic` reuses the identical len16 boot chain
  (BOOT.BIN md5 `aba9fc907db28329…`) with the new conv-lab rootfs — verified byte-identical boot partitions.

---

## 5. The CVH1 target ABI (what M4 builds toward)

Approved contract: `contracts/M1_REGISTER_STREAM_ABI.md` (Codex archive, §13). Highlights:

- New global block at **0x4100+** (independent of K): MAGIC `0x43564831` ("CVH1"),
  ABI_VERSION `0x00010000`, CAPABILITIES `0x000001FF`, STATUS (reset `0x00000101`),
  COMMAND (WO: 1=START, 2=RESET, 4=ABORT), counters, and a **nonzero 128-bit BUILD_ID**
  (assigned before synthesis, recorded in `hardware.json`, never self-referential).
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

`C:\VMShare` holds the transfer artifacts: tested `.bit`s, len16 `.xsa`, both `.wic`s
(`zedboard_gp0_ila_len16_2026-09-06.wic` legacy, `zedboard_M2P_2026-09-10.wic` current),
M2 evidence zips, settings-check packs (`M2P_settings_repaired3_…zip` contains the
fixed checker bytes), and the ARM qualification tarball.

---

## 9. Board operations manual

**Device map (verified 2026-09-11):**

| Device | Identity | Notes |
|---|---|---|
| `/dev/uio0` | DMA @ `0x40400000`, 64 KiB | root:root 0600 |
| `/dev/uio1` | accelerator @ `0x43C00000`, 64 KiB | root:root 0600 |
| `/dev/udmabuf0` | u-dma-buf 5.5.0, phys `0x1F100000`, 1 MiB, sync_mode 1 (noncached) | O_SYNC pwrite/pread are cache-coherent |

Board: kernel `6.12.40-xilinx-g31626ef92ff1`, armv7l, Python **3.12.11**, Pillow **10.3.0**
(JPEG 6.2, zlib 1.3.1), 508 MB RAM, ~2.1 GB free disk. **Quirks:** board clock resets to
2018 on every boot (no RTC battery — `sudo date -s "<UTC time>"` after each boot, or NTP
once Ethernet exists); `/tmp` is wiped on reboot (use `/home/petalinux/`); no `base64`
applet (use `python3 -c "import base64,..."`); devices are root-only → run inference
with `sudo`; Ethernet interface `enx000a35001e53` exists but no cable (sshd present).

**Persistent on-board artifacts:** `/home/petalinux/m3_filebackend.py` (file-driven
inference; loads `/opt/conv-lab/library/models/N3_K8/m0-trained-cifar-k8/converted-1/`
— format-3 config, `weights/kernel_ch*.mem` — and
`/opt/conv-lab/library/datasets/m0-cifar-cat/converted-1/`), `/home/petalinux/m3_demo.py`
(9 images × trained+custom configs → `/home/petalinux/demo_out/`, 135 PNGs incl. Sobel
magnitude maps), `/home/petalinux/demo_images/` (8 grayscale CIFAR test images).

**Proven DMA register sequence** (from the M0 runner; do not improvise):
DMA regs via uio0 mmap: `0x00/0x30` DMACR (bit0 RS, bit2 reset), `0x04/0x34` SR,
`0x18` MM2S_SA, `0x28` MM2S_LENGTH (write triggers), `0x48` S2MM_DA, `0x58` S2MM_LENGTH
(write arms); error mask `0x4770`. Sequence: reset both channels (write 4 to 0x00, wait
both DMACRs bit2 clear, expect SR==1) → program all parameters via accel MMIO **with
readback verify** → soft reset (`0x4004=1`, expect STATUS==1) → **arm S2MM first**
(`0x30=1`, then `0x48=phys+RX`, `0x58=0x8000`) → arm MM2S (`0x00=1`, `0x18=phys+TX`) →
trigger (`0x28=1156`) → poll both SR until `0x1002` (halted+IOC, ≤5 s) → received length
(`0x58`) must equal 16384 → verify guards (0xA5 around RX region) and outputs. Buffer
layout: TX @ +0x1000, RX @ +0x10000, RX_CAP 0x8000, 64-byte 0xA5 guards. Start state
contract: parameters must be all-zero (fresh boot) before a run; restore zeros when done.
**Latency measured: ~0.135–0.157 ms/frame wall-clock from Python (≈7,000 frames/s);
hardware datapath is 1024 cycles = 1 output pixel/cycle @ 100 MHz.**

**Serial file-transfer protocol** (no network on board): gzip -9 → `base64 -w 76` →
paste in ≤24-line chunks into `cat > file << 'XEOF'` heredocs → **verify per-chunk md5**
against assistant-provided references before decoding (corrupted chunks are re-emitted
individually; `sed -i 'Ns/a/b/'` for single-character repairs) → decode with
`python3 -c "import base64,gzip;..."`. **Lessons: there is no `base64` applet (use
python3); never double-gunzip (`.tgz` payloads decode with `base64.b64decode` only);
transcription errors in chat are the main corruption source — always verify chunk hashes.**

---

## 10. Verification evidence ledger (hardware, all 2026-09-11 unless noted)

| Run | Frames | Result |
|---|---|---|
| `dma_len16_trained.py` (M0 runner, embedded payload) | 1 | bit-exact, output sha `cb397559…` |
| `dma_len16_repeated.py` | 20 | 20/20 PASS, no inter-frame resets, distinct outputs |
| `dma_len16_golden.py` (custom filters, saturation extremes) | 1 | PASS |
| `m3_filebackend.py` (file-driven, format-3 library) | 3 | PASS, ~0.14 ms/frame |
| `m3_demo.py` (9 images × trained+custom ×2) | 36 | PASS, 135 PNGs, manifest `96b01a0f416893c7acb2df32b02a54d5712e1283b6debc5cf11686c1e21a4828` |

Total: **61 board frames, 0 mismatches**, guards intact every run. Both M2-P's
"UIO/DMA/buffer regression" gate item and all of M3 are closed. A known-good visual:
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

1. **Timing margin is zero** (WNS 0.000) — M4 RTL must be built with timing in mind.
2. `Important documents/Architecture_Mapping.html` is **stale** (claims K=16, "pending
   RTL" for things that exist). `golden_model/verify_by_hand.ipynb` is broken (imports
   removed functions). `golden_model/data/test_vectors_*/png/` contain stale K=16-era
   previews. `CFG_ACCUM_WIDTH` in config_pkg.vhd is a dead constant.
3. `scripts/create_accelerator_dma_bd.tcl` does not yet reproduce system_ila_0 or the
   DMA `c_sg_length_width=16` (both live in the tracked `.bd`).
4. `platform/accelerator_dma.xsa` is the older handoff; the len16 XSA lives in `bitstreams/`.
5. `deploy/petalinux/README.md` references `deploy/petalinux_snapshots/…` which does not
   exist in the repo (snapshot lives outside).
6. Board clock resets every boot; UIO/udmabuf are root-only; no RTC battery.
7. `.bit/.ltx/.dcp` files are gitignored — `bitstreams/*.bit` and `checkpoints/*.dcp`
   exist only on disk (the tested-bitstream hash gate in §4 covers this).

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
- The legacy 1-MiB u-dma-buf / len16 build is the **qualified profile**; the approved
  4-MiB/22-bit new family is scheduled but not yet integrated.
- Exclusive-ownership lifecycle (§5 of `M1_ACTIVATION_LIFECYCLE.md`) governs all future
  backend work: UNVERIFIED at start → identity/capability validation → READY.
- When transferring files to the board: chunked base64 with per-chunk md5 verification
  (§9). When asking the user to run things: one short self-contained block at a time.

---

## 15. Next steps (as of this writing)

1. **M4.1 — CVH1 identity block** (0x4100+ read-only MAGIC/ABI_VERSION/CAPABILITIES/
   STATUS + 128-bit BUILD_ID with `hardware.json`), plus TB; no behavior change elsewhere.
   Read the full ABI contract first. Keep legacy behavior intact during M4.1.
2. M4.2 — COMMAND/STATUS lifecycle + counters (the FSM; simulate tails/stalls/reset/
   write-protection). Watch timing (zero WNS margin).
3. M4.3 — legacy decommission (0x4000–0x40FF → SLVERR) + tightened slot decode.
4. M4.4 — bias signed-24 default alignment.
5. Then M5 (≥100-frame soak + lifecycle on the hybrid build) → M6 (full-PL reload ×20)
   → M7 (profiles A–D; teammate merge decision) → M8 (demo CLI/harness) → M9 (freeze).
6. Parallel cheap win: 100-frame soak + latency histogram on the current build
   (`m3_filebackend.py` with `FRAMES = 100`) — M5-style evidence and Table 1 data.
7. Competition report (due 2026-09-15): ~90% of evidence exists; assemble only when the
   user says so.
