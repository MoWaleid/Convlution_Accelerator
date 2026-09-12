# M7_CONTINUATION.md — M7 working context (restore point)

**Purpose:** restore full M7 working context after the competition-report detour.
Read this together with `AI_HANDOFF.md` (§3 milestones, §4 register map, §9 board
manual, §11 teammate, §16 next steps). This file is the M7-specific working state as
of **2026-09-12**, after M6 closure (21 verified full-PL reloads, commit after
`5d7e416`). Historical results below retain their original provenance; this foundation update is static implementation only, not new execution evidence.

---

## M7 foundation update — 2026-09-12 (NOT RUN)

Implemented one profile catalog, a B32 config projection, matching wrapper IDs,
integrated discovery tests and guarded DMA layout validation. No tests, generators,
training, Vivado or hardware commands were executed by the assistant.
The catalog/snapshot is a build input, not a qualified hardware bundle.

| Case | TX bytes | RX offset | Exact RX bytes | Minimum guarded extent |
|---|---:|---:|---:|---:|
| A32 | 1156 | 5440 | 16384 | 21888 |
| B32 | 1156 | 5440 | 32768 | 38272 |
| C32 | 1296 | 5568 | 16384 | 22016 |
| D32 | 1156 | 5440 | 8192 | 13696 |
| D640 | 309444 | 313728 | 2457600 | 2771392 |

TX_OFFSET=4096, four 64-byte guards, alignment=64. Supply actual runtime allocation
base/size and conforming 22-bit DMA width. D640 RX=65536 is rejected for overlap.
These are calculated requirements, not platform test results.

Run in Windows PowerShell with Python 3.11+ (existing .venv) and Vivado 2025.2:
~~~powershell
Set-Location 'D:\MyProjects\Convlution_Accelerator'
powershell.exe -NoProfile -ExecutionPolicy Bypass -File verification\m7_profiles\run.ps1 -Suite Software
if ($LASTEXITCODE -ne 0) { throw 'Software foundation failed; stop' }
powershell.exe -NoProfile -ExecutionPolicy Bypass -File verification\m7_profiles\run.ps1 -Suite RTL
if ($LASTEXITCODE -ne 0) { throw 'RTL discovery failed; stop' }
~~~

Expected: M7_SOFTWARE_PASS; M7_PROFILE_PASS for all five cases;
M7_ID_LEAK_REJECT_PASS; M7_RTL_SUITE_PASS. Each invocation prints M7_LOG_ROOT
(%TEMP%\m7_profiles_<unique>). Logs: software.log and per-case prepare/compile/
elaborate logs, simulation.log, xsim_console.log. RTL self-check marker is
M7_RTL_PASS ... checks=42; negative B32 case requires M7_PROFILE_ID_MISMATCH.
Each tool has a 300-second wall timeout; the bench has a 100-us watchdog.
The intentional ID fault affects only its retained isolated test copy.

Only after both commands pass:
~~~powershell
$M7BuildLog = Join-Path $env:TEMP ('M7_B32_' + [guid]::NewGuid().ToString('N'))
& 'D:\Program_Files_2\2025.2\Vivado\bin\vivado.bat' -mode batch -log "$M7BuildLog.log" -journal "$M7BuildLog.jou" -source scripts/build_profile.tcl -tclargs B32
if ($LASTEXITCODE -ne 0) { throw 'B32 build failed; preserve logs' }
~~~

Builds go to profile_builds/<profile>_<unique>/, preserving named A32 outputs and
live runs. The script verifies project/top/part and DMA settings, clones the
project without run results, checks source containment, refreshes the cloned BD
module reference and opens impl_1 before timing checks. TIMING_PASS is only a
build check; NOT_QUALIFIED remains explicit. Inputs, exported bit/XSA/DCP/reports
and hashes are retained. No FPGA-manager image or deployable manifest is invented.

Remaining: execute these checks, then fit/time all profiles; qualify complete
streams/numerics and the exact guarded layout on the actual allocation; freeze
matched artifact/platform manifests and perform the full M5/M7 switching gates.
The existing imported benches pin A32 identity; do not run them unchanged against
B32 or infer five-profile numerical coverage from this discovery-only bench.
Historical M5/M6 scripts and layouts are unchanged. Deployed hardware.json was
not inspected. Workstation A32 ID was already 32 digits and remains unchanged, with its original
preserved (profiles/README.md).

## 1. The M7 gate (verbatim from MASTER_PLAN_PRE_RESEARCH §7)

> Qualify required profiles and model switching: A=N3/K8, B=N3/K16, C=N5/K8 and
> D=N3/K4 custom filters under the same platform/ABI; all at 32×32 plus required D
> at W=640, H=480 for static grayscale images. Each required compiled case passes M5
> tests and fitting/timing/stream/geometry checks; retain at least 20 A32→B32→A32
> cycles; cover every other ordered distinct source→destination pair among
> A32/B32/C32/D32/D640x480 at least once (18 other pairs — 20 ordered pairs total);
> activation validation after every load under the approved lifecycle matrix;
> compatible same-geometry parameter/model changes avoid programming; incompatible
> geometry is rejected unless explicit recorded preprocessing produces compiled W/H;
> cold-boot fallback proven.

## 2. Authoritative profiles (`contracts/M1_BUILD_MATRIX.md` — READ IT FIRST on resume)

| Profile | N | K | W×H | TX bytes | RX bytes | Training? |
|---|---:|---:|---|---:|---:|---|
| A | 3 | 8 | 32×32 | 1,156 | 16,384 | exists (m0-trained-cifar-k8) |
| B | 3 | 16 | 32×32 | 1,156 | 32,768 | checkpoint/export present; qualification pending (K=16) |
| C | 5 | 8 | 32×32 | 1,296 | 16,384 | checkpoint/export present; qualification pending (N=5) |
| D | 3 | 4 | 32×32 | 1,156 | 8,192 | **NONE — D is dedicated custom filters by contract** |
| D640 | 3 | 4 | 640×480 | 309,444 | 2,457,600 | same D coefficients, geometry change only |

Key contract rules baked in:
- W/H independently compile-time configurable; every artifact's manifest records its
  compiled W/H/N/K; geometry admission needs per-geometry evidence.
- D: no mandatory training step; coefficients/bias/shift/ReLU are ours to select and
  validate against the exact reference. Suggested D channel set (mirrors M3 custom):
  identity, Sobel X, Sobel Y, box blur — ReLU **off** on Sobel channels (signed output).
- Software must REJECT incompatible geometry unless explicit recorded preprocessing
  produced the compiled W/H (no silent crop/resize).
- 63×47 stays a simulation-only corner case. 128×128 optional, not required.
- All five calculated guarded layouts fit the 4-MiB target, subject to runtime allocation checks. D640 TX=[4096,313540) overlaps RX@65536: the former fixed-offset guidance is invalid. Use RX@313728, exactly 2457600 RX bytes, minimum extent 2771392.

## 3. Technical context (historical evidence and corrected source observations)

1. Profile authority is profiles/m7_profiles.json; config_pkg is its selected projection. The wrapper identity defaults now follow CFG_BUILD_ID; the earlier independent A32 overrides were a source inconsistency.
2. Serializer is K-generic and **already testbenched at K=6 and K=16**
   (`tb_axi_stream_output_serializer`); K=16 → 4×64-bit beats/position.
3. Regfile is generic: N=5 → 25 coefficients → 7 packed words/channel (ceil(25/4));
   CVH1 ABI asserts N∈{3,5} and ceil(N²/4)≤62 — both satisfied.
4. Window storage is N-1 rows of padded width: C32 has 4x36 and D640 has 2x642 elements per byte lane. Mapping/resources/timing remain unqualified for these cases (R1).
5. CVH1 globals at 0x4100 are K-independent; 16 channel blocks end at 0x1000 < 0x4100 ✓.
6. BUILD_ID word 0 is bits31:0; canonical IDs have 32 lowercase hex digits. Frozen IDs and normalization provenance are in profiles/README.md. No per-build random identity generation.
7. **No WIC/PetaLinux rebuild per profile** — M6 proved runtime `.bin` switching;
   bootgen flow: `bootgen -image x.bif -arch zynq -process_bitstream bin` (plain-path
   BIF; output `*.bit.bin` lands beside the `.bit`). Stage as `/lib/firmware/<name>.bin`.
8. SLVERR provocation from userspace = SIGBUS (fail-stop, 2026-09-12 finding) — the
   profile manager must validate-before-write; error-path probing is simulation-only.
9. Post-frame STATUS is `0x19D` (sticky events) until CVH1 RESET → `0x181`; admission
   logic in `m5_qualify.py` handles this — reuse it.
10. New M7 DMA submissions use profile_layout/validate_layout from conv_lab: TX@4096, G=64, alignment=64, RX_OFFSET=ALIGN_UP(4096+TX_BYTES+128,64), RX capacity exactly RX_BYTES. M5/M6 tested scripts remain historical and unchanged.

## 4. Work breakdown (ordered resume plan)

- [x] **S0 — Profile B source direction**: retain this repository's K-generic RTL per the adopted decision in section 6; this foundation implements that selection. No teammate files changed.
- [ ] **S1 — Training matrix** (user-executes, machine-time): B = retrain with
  K=16; C = retrain with KERNEL_SIZE=5 (need same-mode padding=2); D = select 4 custom
  filters (no training). Exports → per-profile `kernel_ch*.mem` + format-3 configs.
  Golden anchors per profile via `golden_conv.py` + `generate_test_vectors.py`.
- [ ] **S2 — Builds** (user-executes, ~25 min each): 4 Vivado runs
  (B32, C32, D32, D640), each explicitly selected from profiles/m7_profiles.json in an isolated project + `hardware_<X>.json`
  (complete M1 hardware-bundle metadata with matching profile/platform/artifact hashes; the historical hardware.json alone is not that schema) + routed timing/
  utilization evidence + `.bin` via bootgen. Watch D640 timing (R1) and B resources.
- [ ] **S3 — `software/m7_switch.py` profile manager** (me, locally first): loads a
  profile request → VALIDATING (manifest vs request; reject wrong geometry/model) →
  compatible-parameter-change shortcut (same geometry: no reload) vs full reload →
  the M6 seven-phase machine → per-profile M5-class qualification hook (soak, extremes
  at that profile's sizes). Include rejection tests (wrong .bin for requested profile,
  busy request, incompatible geometry without preprocessing record).
- [ ] **S4 — Per-profile qualification**: each required compiled case passes the full M5 gate: at least 100 frames without inter-frame RESET, applicable extremes/custom/trained coverage, lifecycle and bounded failure checks, plus fitting/timing/stream/geometry checks. The earlier 20-frame reduction was not an approved relaxation.
- [ ] **S5 — Switch matrix**: 20× A32→B32→A32, then every ordered pair of
  {A32,B32,C32,D32,D640} (20 transitions), each: reload → identity validate → full
  parameter install → bit-exact activation frame → evidence line.
- [ ] **S6 — Evidence + handoff**: update `AI_HANDOFF.md` (M7 row, ledger, quirks),
  commit per milestone discipline.

## 5. Risks (ranked)

- **R1 — D640 timing:** two padded-width-642 line buffers and larger geometry counters; first build
  decides. Mitigation: build D640 EARLY (before writing the switch manager) to fail fast.
- **R2 — K16 resources/timing:** MAC count doubles; baseline had +0.066 WNS margin.
  Mitigation: build B early, same reason.
- **R3 — N=5 training quality:** a weak N5 model is acceptable (contract needs a
  qualified profile, not SOTA accuracy) — golden-exactness is what matters.
- **R4 — relay tax:** budget 2–4 debug round trips per new profile; validate everything
  locally first (established discipline).
- **R5 — schedule:** report due 2026-09-15 (deferred until done — see below).

## 6. Decisions — WORKING DEFAULTS ADOPTED 2026-09-12 (user may still override)

1. Profile B: implemented from **our own K-generic RTL** (config_pkg K=16). Teammate
   core remains a report-level FOM/margin comparison only (checklist still unread —
   read `MERGE_DECISION_CHECKLIST.md` before final submission if time allows).
2. Profile D filters: identity (127, shift 7) / Sobel-X (shift 8) / Sobel-Y (shift 8) /
   box-blur (shift 4), bias 0, ReLU **off** on Sobels — mirrors the proven M3 custom set.
3. Per-profile soak: retain the full approved M5 requirement (at least 100 frames without inter-frame RESET) for every required compiled case. Prior 20-frame working guidance is superseded.

## 7. REPORT-UPDATES QUEUE (add to report/report.md when M7 completes — user instruction)

- [ ] New §: multi-profile architecture — per-profile config_pkg constants, BUILD_IDs
      (B/C/D/D640), per-profile hardware_X.json identity scheme.
- [ ] §9: per-profile utilization/timing/power table (4 new builds) + FOM per profile
      in BOTH scopes (accelerator-core block power vs full system — same two-scope
      method as the current §11).
- [ ] §8: switching evidence — 20× A32→B32→A32 + all 20 ordered pairs table +
      transcripts (report/evidence/m7_*.txt).
- [ ] §10: note profile switching as the productized form of runtime reconfiguration.
- [ ] Figures: Sobel/edge maps from D-profile (esp. D640 if produced) — strong visuals.
- [ ] Table 1: either per-profile rows or a note that Table 1 reports profile A with
      per-profile data in the new section.
- [ ] Assumptions: per-profile BUILD_ID assignment scheme; D's no-training contract cite
      (M1_BUILD_MATRIX.md).

## 8. Training matrix kickoff (scripts patched 2026-09-12 — env-overridable, defaults = A)

Working defaults adopted; per-profile runs (Windows PowerShell, repo root, venv python):

~~~powershell
# Profile B (N3/K16) — run FIRST, longest pole:
$env:CNN_K='16'; $env:CNN_MODEL='golden_model\data\trained_k16.pth'; $env:CNN_LOG='golden_model\data\training_k16.log'
.venv\Scripts\python.exe golden_model\train_cifar10.py
# Export B weights:
$env:CNN_MODEL='golden_model\data\trained_k16.pth'; $env:CNN_WEIGHTS_DIR='golden_model\data\weights_k16'
.venv\Scripts\python.exe golden_model\extract_weights.py

# Profile C (N5/K8):
$env:CNN_K='8'; $env:CNN_N='5'; $env:CNN_MODEL='golden_model\data\trained_n5.pth'; $env:CNN_LOG='golden_model\data\training_n5.log'
.venv\Scripts\python.exe golden_model\train_cifar10.py
# Export C weights:
$env:CNN_MODEL='golden_model\data\trained_n5.pth'; $env:CNN_WEIGHTS_DIR='golden_model\data\weights_n5'
.venv\Scripts\python.exe golden_model\extract_weights.py
~~~

Profile D needs NO training: hand-authored filters (decision §6.2), written directly
as kernel .mem + config (assistant generates from the proven M3 custom set).

## 9. Resume checklist (execute top-to-bottom)

1. Read `AI_HANDOFF.md` §3/§4/§9/§11/§16 + this file.
2. Run the focused software/RTL commands above first. Existing trained_k16.pth, trained_n5.pth and their weight exports were preserved; their qualification is separate.
3. S2 build B32 early (fail-fast on R2), then C32, D32, D640.
4. S3 manager + S5 matrix as board sessions become available.
5. Keep `AI_HANDOFF.md` updated per milestone; commit per established discipline.
