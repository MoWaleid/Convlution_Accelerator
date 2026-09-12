# M7_FIX_PLAN.md — Fix guide derived from feedback.md review

**Purpose:** A strict, ordered plan to repair every finding from the feedback
review, with verification gates between steps. Follow top-to-bottom without
skipping. No step starts until the previous step's verification gate passes.

**Author of the errors:** the primary AI (me). The reviewer found real bugs
that I introduced by moving fast without testing actual execution paths.

**Rule:** after each fix, re-read the modified file end-to-end before running
anything. After each verification gate, record the result before moving on.

---

## PHASE 1 — Fix m7_switch.py correctness (all P1 code defects)

### 1.1 Defined-variable audit and fix
- [ ] `FPGA_FLAGS` / `FPGA_FIRMWARE` — define as module-level `Path` constants
      (same pattern as `m6_reload.py`)
- [ ] `read_identity()` — add `magic` and `abi` keys to the returned dict
- [ ] `run_frame()` — rename `tx_size` → `tx_bytes` consistently, or pass both;
      verify no other undefined names via `python3 -c "import ast; ast.parse(open('...').read())"`
      then a manual read-through of every function end-to-end
- [ ] `log()` — either accept `(message, flush)` or strip the second argument
      at the call site; pick one, apply everywhere

**Gate 1.1:** `py_compile` passes AND a grep for every function-call
argument count matches its definition AND `read_identity()` returns every key
that `validate_identity()` accesses.

### 1.2 Restore separate DMA + accelerator completion checks
- [ ] In `run_frame()`: after `CMD_START`, first wait for accelerator
      `DONE|IDLE`, then separately wait for both DMA channels to enter
      halted-without-error state (SR bit0 set, error bits clear on both 0x04
      and 0x34), then read the receive length and buffer
- [ ] Check DMA error bits (`ERRORS = 0x4770`) inside the completion wait,
      not just after it
- [ ] After frame completion, verify accelerator STATUS has no ERROR/FAULT
      bits and counters match expectations, separately from the DMA checks

**Gate 1.2:** read the modified `run_frame()` end-to-end and confirm:
accelerator completion ≠ DMA completion; both are independently verified;
DMA error bits are checked inside the wait loop.

### 1.3 Fix the memory layout to use the guarded-layout implementation
- [ ] Call `fb.dma.layout()` (the existing M4 validated implementation) or
      replicate its exact arithmetic, per profile — do NOT hardcode RX offsets
- [ ] Verify actual udmabuf allocation size against the computed layout
- [ ] RX offset for each profile comes from the layout calculation, not a
      hardcoded constant
- [ ] S2MM receive capacity = RX bytes exactly (not `rx_bytes + 64`)
- [ ] TX lead guard + TX tail guard + RX lead guard + RX tail guard — all
      four written and verified per frame
- [ ] `hardware_D640.json`: fix RX offset to match the calculated layout
      (not 65536, which overlaps TX)

**Gate 1.3:** for each of the 5 profiles, print the computed layout
(TX start/end, RX start/end, guard positions, alignment, total footprint)
and verify: no overlap, alignment correct, fits in 4 MiB allocation.

### 1.4 Fix D640 preprocessing
- [ ] `load_input()` must detect when `w > 32` and apply the recorded
      preprocessing: open the library PNG, convert to L, LANCZOS-resize to
      (w, h), then verify the canonical bytes against the recorded SHA256
- [ ] The recorded preprocessing and hash come from `anchors_m7.json`
      `D640_preprocessing` (already computed)
- [ ] No silent cropping or bypassing of the decoder pipeline

**Gate 1.4:** run the preprocessing locally on Windows against the recorded
hash and confirm the resized bytes match the anchor's canonical hash.

### 1.5 Fix admission and lifecycle discipline
- [ ] If BUILD_ID matches, STILL run full identity validation (all fields)
- [ ] Entry state check: require `IDLE|QUIESCENT` (both bits), and
      explicitly reject `FAULT` or any error bits
- [ ] Add a simple exclusive-ownership lock (PID file at
      `/tmp/m7_switch.lock`, fail if exists, clean up on exit)
- [ ] `--profile` and `--soak` modes: wrap execution in try/finally with
      guaranteed `dma_halt()` + CVH1 RESET in the finally block
- [ ] Matrix mode: print PASS only after final cleanup checks pass
- [ ] Final RESET wait: require both `IDLE` AND `QUIESCENT` bits, then
      require no ERROR/FAULT, then verify PARAM_COMPLETE

**Gate 1.5:** read the modified admission path end-to-end; confirm every
entry path validates fully, cleanup is in a finally block, and PASS is
only printed after all checks.

### 1.6 Fix parameter loading strictness
- [ ] `load_params()`: validate each channel's `channel` index is
      sequential and unique
- [ ] Validate every coefficient is in [-128, 127]
- [ ] Validate every bias fits signed-24: [-8388608, 8388607]
- [ ] Validate every shift is in [0, 31]
- [ ] Validate `relu_en` is present and interpretable
- [ ] Do NOT change the exporter's signed-32 output; enforce signed-24 at
      the admission point instead

**Gate 1.6:** run the loader against all 4 profile directories locally;
confirm all pass strict validation.

### 1.7 Fix matrix construction
- [ ] Fix the bridge-selection bug (`bridge[0]` picks a character, not a
      profile name)
- [ ] Assert the starting profile from the live BUILD_ID, not assumed
- [ ] Track actual observed transitions as `(src, dst)` tuples in a set;
      after the matrix, verify every ordered pair is in the observed set
- [ ] Track actual bit-exact activation digests per profile
- [ ] Guarantee termination: the walk either covers all remaining pairs or
      errors with a diagnostic

**Gate 1.7:** run the matrix-construction function locally (pure Python,
no hardware) and confirm: it terminates, produces a sequence that covers
all 20 ordered pairs, and every profile name in the sequence is valid.

---

## PHASE 2 — Fix identity reconciliation

### 2.1 Reconcile catalog vs manifests vs RTL
- [ ] The current RTL `config_pkg.vhd` has BUILD_ID `D640N3K04-260912`
      (hex `443634304e334b30342d323630393132`) — this matches
      `software/hardware_D640.json`
- [ ] `profiles/m7_profiles.json` has DIFFERENT IDs for C32/D32/D640
- [ ] Decision: the **manifest** (hardware_X.json) and the **RTL** are the
      source of truth (they match the actual built bitstreams). The catalog
      must be updated to match, not the other way around
- [ ] Update `profiles/m7_profiles.json` entries for C32/D32/D640 to the
      correct BUILD_IDs from their hardware manifests
- [ ] Verify: A32 and B32 catalog IDs already match their manifests

**Gate 2.1:** for each profile, assert catalog BUILD_ID == manifest
BUILD_ID == the BUILD_ID known to be in the built bitstream (from the
feedback review, the artifacts match their recorded manifest hashes).

---

## PHASE 3 — Fix report accuracy

### 3.1 Correct throughput definition
- [ ] The serializer packs 4 int16 values per 64-bit beat
- [ ] K=8: 2 beats per output position → 0.5 positions/cycle
- [ ] K=16: 4 beats per output position → 0.25 positions/cycle
- [ ] Measured end-to-end: 0.076 ms/frame = 1024 / 76 µs ≈ 13.5 M
      positions/s ≈ 0.135 positions/cycle (includes DMA + Python overhead)
- [ ] Update report §3 throughput, §9.1 Table 1, §11 FOM

### 3.2 Correct FOM
- [ ] FOM = Throughput / (Power × (LUTs + 50·DSP + 100·BRAM))
- [ ] With corrected throughput 0.5 positions/cycle (A32):
      FOM = 0.5 / (1.765 × 12,662) ≈ 2.2×10⁻⁵ (full system)
      FOM = 0.5 / (0.018 × 7,967) ≈ 3.5×10⁻³ (accelerator core)
- [ ] Update §9.1 Table 1 FOM row and §11 with corrected values

### 3.3 Correct bias/accumulator description
- [ ] The M4+ profiles use signed-24 bias, not signed-32
- [ ] The accumulator is max(21, 24) + 1 = 25 bits, not 33
- [ ] Update report §3 pipeline table, §6 fixed-point section,
      `report/figures/generate_figures.py` stage descriptions
- [ ] Cite `config_pkg.vhd` derived constants, not stale comments

### 3.4 Freeze source citations
- [ ] Copy the A32 routed timing/power/utilization reports into
      `report/profile_builds/A32/` before they are overwritten
- [ ] Update report source index to cite the frozen copies, not the live
      run directory
- [ ] Label intermediate (pre-physopt) reports as such where retained

**Gate 3.x:** read the updated report end-to-end and verify every number
has a citation to a frozen file, and no throughput/FOM claim exceeds what
the serializer and measurement support.

---

## PHASE 4 — Re-validate everything

### 4.1 Local validation
- [ ] Run the existing `run.ps1 -Suite All` (software + RTL tests)
- [ ] Confirm all previous PASS markers still pass

### 4.2 Board validation (user-executed via relay)
- [ ] `sudo python3 /home/petalinux/m7_switch.py --profile B32 3`
      (first switch: A32→B32 full reload + activation)
- [ ] `sudo python3 /home/petalinux/m7_switch.py --profile A32 3`
      (switch back)
- [ ] `sudo python3 /home/petalinux/m7_switch.py --matrix`
      (58 switches, 40+ full-PL reloads, 58 bit-exact activation frames)
- [ ] Record transcripts into `report/evidence/`

### 4.3 Update documentation
- [ ] `AI_HANDOFF.md`: M7 status, evidence, corrections
- [ ] `M7_CONTINUATION.md`: mark fixed items, update remaining steps
- [ ] `report/report.md`: corrected throughput/FOM/bias/accumulator
- [ ] Commit

---

## PHASE 5 — Remaining M7 gate items (after fixes)

1. Per-profile 100-frame soak (M5 gate requires ≥100 frames per compiled case)
2. Cold-boot fallback proof
3. Report final update with M7 results
4. Competition report assembly (due 2026-09-15)

---

## Rules for me during execution

1. Read every file end-to-end after editing, before running
2. Never cite a stale md5 or a stale path
3. Every number in every document has a citation to a real file
4. No test result from a previous source snapshot qualifies the current code
5. The reviewer's P1 findings are blocking; P2 findings are not optional
6. When uncertain, test locally before running on the board
7. When I make an error, state it plainly, fix it, and move on
