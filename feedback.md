# Full-project integration feasibility audit for GLM — 2026-09-14

## Outcome

**The selective-integration strategy is viable, but the repository is not yet in a state where the M10–M12 plan can be executed end to end without losing reproducibility.** Git-level conflict risk is low; build, release, deployment, and runtime-model risk is materially higher. Do not merge the teammate branch wholesale and do not start from `origin/v1-bringup`. First close or explicitly defer the gates below, then create the integration branch from the current local `v1-bringup` HEAD.

This was a read-only/static pass over the live Git state, current RTL and Vivado flows, software/runtime, profile bundles and manifests, PetaLinux stage, milestone/status documents, evidence indexes, and the teammate's 100/125 MHz branch history. No simulation, synthesis, implementation, generator, test suite, packaging command, or board operation was run during this audit.

Verified repository identity and health:

- branch: `v1-bringup`;
- current HEAD: `e97e002a53efc81f11374b7b97a62b5f3fea1110`;
- local branch is 17 commits ahead of `origin/v1-bringup`;
- the only working-tree change is this `feedback.md` review;
- `git fsck --no-dangling` completed cleanly;
- there are currently no Git tags, including no `v1-m9-release` tag;
- teammate 125 MHz tip: `00a6e116b2823692c4e9de63eae04bc154d4dc1a`, whose direct parent and merge base with this line is `fb66066ab6eef721e09ce34d385cb53ca95e78d5`.

Since `fb66066`, the two lines have no overlapping RTL/build-source edits; their only path overlap is `AI_HANDOFF.md`. That makes a selective transplant mechanically reasonable. It does **not** prove that the two build systems, manifests, runtime APIs, clocks, or numerical implementations are compatible.

## Release-blocking findings

### FP-01 — M9 is not closed and the integration baseline is not frozen

`M9_CHECKLIST.md` records the M8 suite, the 1,000-frame soak, and five physical power-cycle boots as complete. The clean-build reproduction, release snapshot/manifest, final limitations record, and `v1-m9-release` tag remain unchecked; the tag does not exist. `AI_HANDOFF.md` therefore overstates the position when it calls M0–M9 effectively done. It also contains stale statements that M7 still needs a commit, that all M8 P1 findings are closed, and that board evidence totals only 765+ frames/90 reconfigurations.

Before integration, either close M9 honestly or create a clearly named **pre-M9 integration baseline**. Do not label the current line a frozen M9 release while the remaining gates and R14 findings are open.

### FP-02 — The qualified A32 release cannot currently be reproduced from the repository

The M4 evidence expects A32 `.bit` SHA-256 `8bc608...`, but that artifact was not found in this repository, `D:\MyProjects\release_checkpoints`, or `C:\VMShare`. Board evidence identifies `/lib/firmware/m7_A32.bin` with SHA-256 `b59378e4...`; neither that binary nor the exact runtime `hardware_A32.json` containing its `firmware_bin_sha256` is preserved here. `software/hardware.json` is historical and lacks the fields required by the current strict manager.

The B32, C32, D32, and D640 `.bit`/`.bit.bin` files currently match their local manifests, but these artifacts are ignored by Git. A fresh clone therefore does not contain the qualified hardware library. Preserve the artifacts in a checksum-addressed external release store or an approved artifact mechanism before cleanup, and retrieve the exact A32 firmware/manifest from the board while it is still available. Compare `.bit` to `.bit` and `.bit.bin` to `.bit.bin`; their hashes are not expected to be equal.

### FP-03 — The PetaLinux recipes recreate M2-P, not the board-proven M7/M8 runtime

`deploy/petalinux/SHA256SUMS.txt` verifies all 76 entries, but that only proves internal integrity of the old deployment stage. The recipe copy of `conv_lab/dma.py` lacks current layout validation, the recipe copy of `preprocessing.py` lacks the board-proven supervisor demotion path, and `conv_lab/profiles.py` is absent. The recipes do not install `m7_switch.py`, `m8_cli.py`, `m8_import.py`, the five-profile catalog/library, or the corresponding firmware images.

A clean PetaLinux rebuild from the tracked recipes would therefore regress from the live board state. Create a new versioned recipe revision that installs the exact current runtime, profiles, manifests, library data, and firmware; record source-to-recipe hashes; build and re-run installed-file, activation, inference, and recovery qualification. Do not silently overwrite the older M2-P recipe evidence.

### FP-04 — The current profile build flow will not build the teammate datapath correctly

The live root project and `Convlution_Accelerator.xpr` register the baseline `conv_channel`/`conv_engine` path, not `cfglut5_kcm.vhd` or `cfglut5_bitheap.vhd`. `scripts/prepare_profile.py` does not include those sources, while `scripts/build_profile.tcl` clones the root XPR and enforces the current 100 MHz/profile assumptions. The teammate release flow instead creates a fresh Vivado project, explicitly adds the CFGLUT sources, and imports its saved 125 MHz block design. The live BD-recreation script is still a 100 MHz description and remains unreconciled with the saved 125 MHz design.

Choose one authoritative research-build path before transplanting RTL. The recommended path is to adapt the teammate's fresh-project release builder so it consumes the current frozen profile snapshots, manifests, checksum policy, and output-directory discipline. The alternative is to update the root XPR, source lists, profile preparer, builder, and recreation Tcl together. Mixing these flows will either omit the CFGLUT sources or produce a build that cannot be recreated from Tcl.

### FP-05 — Runtime identity currently conflates geometry, hardware implementation, and model

The present manager/catalog assumes exactly five identities (`A32`, `B32`, `C32`, `D32`, `D640`) and maps each identity to both one firmware manifest and one parameter directory. That cannot represent a controlled comparison of `B32_MAC100`, `B32_CFGLUT100`, and `B32_CFGLUT125` using the same N3/K16 weights and image set without duplicating or relabeling model data.

M10 must introduce orthogonal identifiers:

1. a shape/ABI compatibility ID such as `N3_K16_W32_H32`;
2. a hardware implementation/release ID such as `B32_MAC100` or `B32_CFGLUT125`;
3. a model-bundle ID independent of hardware.

The catalog must select a hardware release and a compatible model bundle separately, validate ABI/shape/numerical compatibility, and bind both hashes into the run record. A standalone EF125 runner is acceptable for the first board proof, but it is not an acceptable M12 comparison interface.

### FP-06 — Existing R14 correctness findings remain live

The current files relevant to R14-01 through R14-10 have not changed since that review. In particular, the shift-24+ rounding defect, unsafe success/cleanup semantics, mutation before soak-image admission, signed-bias validation gap, unbounded pre-decode read, unselectable imported bundles, incomplete admitted-context binding, weak importer idempotency, incomplete resource accounting, and conversion-overwrite risk remain actionable. At minimum, the P1 findings must be fixed and requalified before the current runtime is called an unconditional release baseline.

### FP-07 — Profile metadata and project documentation have drifted

The active `config_pkg.vhd` is D640 (N3/K4/640×480), not B32. `profiles/README.md` says B32 is active, lists build identities inconsistent with `profiles/m7_profiles.json`, and still describes switching as future work. `software/README.md` still says M1/M2 and real qualification are pending. `report/report.md` does not include the M9 1,000-frame/cold-boot campaigns and still references an older record schema/evidence total. `M9_CHECKLIST.md` also retains a contradictory known-limits sentence about physical power-cycle evidence.

Update these only after the source/release state is settled. Documentation must be generated or checked against the authoritative catalog and evidence index so another stale handoff cannot become the source of truth.

### FP-08 — Baseline layout fields are contradictory even though runtime recomputes them

The A32/B32/C32/D32 hardware manifests retain `rx_offset=65536`; the approved 64-byte-aligned layouts derive 5,440 bytes for A/B/D and 5,568 for C. D640 correctly records 313,728. The runtime currently recomputes layout, so this did not invalidate the verified local payload arithmetic, but two authorities for the same value are unsafe. Remove the redundant field or make manifest generation derive and validate it from the approved layout function.

## Static checks that passed

- All 86 Python files parsed successfully without importing or executing them.
- All 37 JSON files parsed successfully.
- All five parameter bundles satisfy the inspected canonical-flat-2 structural rules: expected channel counts, per-channel weight counts, signed-24 biases, Boolean ReLU, shifts 0–31, and two-digit coefficient bytes.
- Derived layouts fit the 4 MiB policy: A32 extent 21,888; B32 38,272; C32 22,016; D32 13,696; D640 2,771,392 bytes.
- Local B32/C32/D32/D640 bitstreams and firmware binaries match their recorded manifest hashes.
- The PetaLinux deployment-stage checksum manifest passes 76/76 entries.
- The current `impl_1` outputs correspond to D640 and match the local D640 artifact hashes.

These checks are useful integrity evidence, not substitutes for simulation, clean synthesis/implementation, ARM execution, or board qualification.

## Corrected integration sequence

### Gate 0 — Make the current baseline recoverable

1. Resolve the release-critical R14 findings or explicitly record each accepted deferral and its containment.
2. Recover and archive the exact A32 firmware and runtime manifest; preserve all five qualified hardware artifacts, XSAs, reports, manifests, and board evidence under immutable checksums outside ignored working files.
3. Reconcile the current runtime into a new versioned PetaLinux recipe and prove a clean image installs the same bytes and can activate/recover every retained baseline profile.
4. Reproduce the chosen baseline from a clean source checkout, record tool/version/directive identity, update the evidence/report status, commit the current local work, push the 17 unpublished commits, and tag only if the M9 gates actually pass.

### Gate 1 — Establish a research-variant build and catalog contract

1. Create the integration branch from the resulting local HEAD, never from stale `origin/v1-bringup` and never by checking out over the live D640 project.
2. Separate shape/ABI, hardware-release, and model-bundle identities in schemas and manager APIs.
3. Create one authoritative clean research build flow that explicitly registers the CFGLUT sources and regenerates or validates the 125 MHz platform. Preserve the baseline recovery build unchanged.
4. Add a hard board/part/platform gate before accepting the teammate design.

### Gate 2 — Transplant and prove the minimum N3 datapath

1. Selectively transplant the exact multiplier/bitheap, fixed rounding, and only the required controller/prefetch changes. Preserve the current ABI unless a reviewed version bump is necessary.
2. Regenerate the bitheap and compare generated output byte-for-byte or semantically against the checked-in source.
3. Add directed tests for nonzero weights, accumulator extrema, every shift, signed-24 bias extrema, ReLU boundaries, AXI configuration lifecycle, START/config races, RESET/ABORT during configuration, stream stalls, TLAST, and reset recovery.
4. Build `B32_CFGLUT125` from a clean tree and preserve the exact bit/bin/XSA, utilization, timing, power, tool logs, source manifest, and hashes. Treat the teammate engine as N=3-specialized; retain the legacy path for C32/N5 unless a separate N5 bitheap is designed and qualified.

### Gate 3 — Board qualification

1. Package the 125 MHz platform with a matching XSA/FSBL/device tree/clock contract; do not combine a 125 MHz PL with unreviewed 100 MHz platform assumptions.
2. Activate through FPGA Manager using the new hardware-release identity, then run identity/capability checks, exact known-answer inference, 100+ distinct-frame soak, repeated reconfiguration, physical power cycles, and injected fault/recovery cases.
3. Verify the actual PL clock and capture ILA or equivalent counters if claiming an edge-free internal initiation interval. Keep internal window rate, external 64-bit AXIS beats per output position, end-to-end latency, and throughput as separate metrics.

### Gate 4 — Matched research comparison

Audit or rebuild `B32_CFGLUT100` from the same source and directives as the 125 MHz variant, changing only the intended clock/platform variable. Compare it against the retained `B32_MAC100` using identical weights, images, geometry, preprocessing, quantization, transfer sizes, software path, and measurement method. Report timing closure, resources, power method, exact correctness, latency, steady-state throughput, and recovery separately. Do not call the branch's simulation-only edge count or unmatched WNS a board-level performance result.

## Deadline-aware recommendation

The shortest defensible route is: preserve/recover the current baseline now; fix the release-critical runtime defects; create an isolated `B32_CFGLUT125` research build and prove one exact board path; then add the orthogonal catalog support and matched 100 MHz comparison. Do not spend the deadline merging all profiles into the new datapath before the K16 path is reproducible and board-qualified. K4/K8 can follow on the N=3 engine; C32/N5 should remain on the proven legacy implementation until it has its own exact generated reduction network.

---

# Teammate-branch integration-plan review for GLM — 2026-09-14

## Verdict

**Do not merge `origin/feature/k16-cfglut5-edgefree-125mhz` yet. The branch contains a strong exact CFGLUT5/Dadda implementation and useful timing work, but `INTEGRATION_PLAN_M10_M12.md` needs factual corrections and several explicit gates before it is safe or reproducible.** Integrate through a selective transplant onto the current `v1-bringup` line; do not adopt the branch wholesale.

Reviewed identities:

- current line: `e97e002a53efc81f11374b7b97a62b5f3fea1110`;
- teammate release tip: `00a6e116b2823692c4e9de63eae04bc154d4dc1a`;
- teammate tip's direct parent and merge base: `fb66066ab6eef721e09ce34d385cb53ca95e78d5`.

Only `feedback.md` was edited. The teammate ref was inspected through Git objects without checkout. No merge, source edit, generator, simulation, build, package, programming or board command was run.

### What is worth keeping

- The exact runtime-configurable CFGLUT5 multipliers and generated signed Dadda bitheap are substantive research work, with zero accelerator DSP/BRAM use.
- The split post-processing pipeline appears to solve the baseline large-shift rounding failure without widening the whole product-sum pipeline.
- `cfg_pending`/`cfg_ready`, registered local window banks, the prefetch slot, registered controller decode and completion staging are well-motivated architectural/timing changes.
- The failed broad-`MAX_FANOUT` experiment is documented instead of hidden; the local registered-bank remedy is the credible result to preserve.
- The fresh-project release flow has useful fail-closed timing/DRC/route gates and RTL source/build comparisons.
- Host/simulation evidence is broad and the branch correctly labels board execution `NOT_RUN`.

## Required corrections to `INTEGRATION_PLAN_M10_M12.md`

### IP-01 [P1] Correct the lineage and integration method

The plan and handoff call the published release ref a sibling lineage. That is not true for the ref we can actually integrate: `00a6e11` is a direct one-commit child of `fb66066`, and `fb66066` is the merge base. Earlier CFGLUT development may have happened on a separate lineage, but the published release commit was laid onto the M8-era base.

Required plan change: state this distinction explicitly. Create the integration branch from the current mainline, then selectively import reviewed files or commits from `00a6e11`. Do not use an unreviewed wholesale merge/cherry-pick: that commit deliberately deletes the root XPR, historical XSAs and the tracked B32 generated tree, and it predates current M8/M9 fixes.

### IP-02 [P1] The remote branch does not contain its claimed release artifacts or reports

The remote tree contains no `work/release_125/artifacts`, `dist/edgefree125`, `.bit`, `.xsa`, or whitelisted timing/power report/log evidence. Those outputs are intentionally ignored and existed only in the teammate's local workspace. A fresh clone therefore cannot perform the M11 instruction to import `edgefree.xsa`, nor independently validate physical numbers.

There is also a recorded discrepancy: the handoff/plan say setup WNS `+0.201 ns`, while the authoritative tracked `release/STATUS.md` and commit message say `+0.178 ns`; WHS is `+0.019 ns`. No tracked report arbitrates this.

Required gate: either obtain a complete immutable teammate artifact/evidence package with hashes and provenance, or reproduce the build from a clean tree. Until then, call it a routed release-candidate claim, not a qualified package, and mark all physical metrics provisional.

### IP-03 [P1] The engine is N=3-specialized, not K16/W32-specialized

The generated bitheap is fixed at nine taps and 21-bit sum rows, and `conv_engine.vhd` explicitly asserts `C_N = 3`. In contrast, channel count is generic (`C_K`), bank count is derived from it, and image width/height are generic in the surrounding design. Therefore:

- A32 N3/K8 and D32/D640 N3/K4 are plausible configuration/rebuild/qualification variants of this engine;
- B32 N3/K16 is the shipped instance;
- C32 N5/K8 needs a new N5 bitheap/generator path or must stay on the legacy MAC engine.

Rewrite F3 accordingly. Do not spend deadline time designing dual-engine coexistence before proving the simpler N3 K4/K8/K16 variants. Prioritize B32/EF125 first, then N3 variants; treat an N5 CFGLUT generator as a later, independently gated extension.

### IP-04 [P1] Add an explicit board-platform decision gate

This release is hard-targeted to the ZedBoard project: `xc7z020clg484-1`, `Zedboard-Master.xdc`, the tracked ZedBoard block design and `platform: zedboard_linux`. It is not a PYNQ-Z2 release. Because the competition wording about “Zynq-7000 XC7Z020/PYNQ-Z2” was still ambiguous, M10 must resolve the physical board before FSBL/PetaLinux work. If PYNQ-Z2 is required, constraints, PS configuration, project target, bitstream/XSA and board qualification must be ported/rebuilt; the ZedBoard artifact cannot simply be reused.

### IP-05 [P1] Reconcile the stale block-design recreation script

The tracked `.bd` and release build target native PS FCLK0 at 125 MHz, but `scripts/create_accelerator_dma_bd.tcl` still requests 100 MHz and describes one common 100 MHz PL domain. The release flow imports the saved `.bd`, so the claimed fresh build does not prove that the repository's BD-recreation path reproduces the release.

Required: update and validate the recreation script or explicitly retire it as non-authoritative. For sustainable builds, generate a BD from the supported script and compare relevant IP parameters, addresses, widths, resets and clocks with the committed release BD before sign-off.

### IP-06 [P1] Do not package the teammate branch's old manager and parameter dialect

`scripts/package_release.py` copies that branch's `software/m7_switch.py` and legacy `golden_model/data/weights_k16`. Its `load_params()` uses permissive JSON/type rules and returns only `channels`. Current mainline requires `canonical-flat-2`, exact types/fields, weight-file binding and returns `(channels, bundle_sha256)`. The branch config is format 2, declares `bias_bits: 32`, stores integer `relu_en`, and does not satisfy the current strict bundle contract.

A blind mixture will fail: `edgefree_board.py` expects the old `load_params()` return shape and old data. Replace the packaged manager/backend with the current audited software, convert K16 parameters into the current canonical model library, and add an adapter/integration test that exercises the exact current API. F5 should say the branch has source K16 weights and an exact runtime reference, but lacks a current canonical bundle, frozen expected anchor and board-qualified run—not that no K16 golden material exists.

### IP-07 [P1] Make runtime layout and hardware metadata single-source-of-truth

`release/hardware.json` records `rx_offset = 65536`; the approved four-guard layout for B32 computes `rx_offset = 5440`, and the branch runner ignores the manifest value by recomputing the layout. This makes release metadata contradictory/dead. The same template records an exact 4 MiB DMA buffer even though runtime discovery is the authoritative platform fact.

Required: either store a derived-layout policy and calculate it everywhere, or require manifest values and validate them against the calculation before any hardware access. Distinguish required/minimum buffer capacity from the discovered allocation. Add rejection tests for stale layout and capacity metadata.

### IP-08 [P1] Expand reproducibility and integration verification

The package script binds imported RTL files, which is useful, but it does not fully bind the `.bd`, XDC, generator, release scripts, IP configuration, tool build/settings or generated-bitheap equivalence. M10 must create a complete build-input manifest and preserve the reports/artifacts needed to reproduce the result.

Also add directed wrapper/controller tests for:

- START racing with or arriving during CFGLUT configuration;
- coefficient writes while configuration is pending;
- RESET and ABORT with a pending prefetched window;
- no stream acceptance before RUN;
- parameter readback not being mistaken for installed CFGLUT state before `cfg_ready`;
- exact one-time transition out of CONFIG after the last truth bit.

The handoff already identifies serializer release-phase and pending-prefetch reset/abort coverage as open; they must appear explicitly in M10/M11 rather than under a generic controller audit.

### IP-09 [P1] Fix throughput, edge-free and on-board evidence language

For K16 signed16 output on a 64-bit AXI Stream, one complete spatial position is 32 bytes and therefore takes four 64-bit beats. The design may accept one internal window per clock and may emit one 64-bit beat per clock without row-edge bubbles, but the external interface does not sustain one complete K16 position per clock. Use unambiguous units everywhere: channel-results/cycle, complete positions/cycle, stream beats/cycle and frames/s.

The reviewed branch exposes edge-bubble metrics in simulation; no on-silicon row-edge metric register was found. The board runner can measure end-to-end frames, but cannot by itself prove internal zero-bubble scheduling. If hardware proof is mandatory, specify an ILA capture or synthesizable counters; otherwise keep simulation bubble proof and board throughput evidence separate.

Do not report `~128.2 MHz` as established Fmax from one positive-slack 125 MHz route. At most it is a rough estimate; a tighter constraint can change the critical path and placement.

### IP-10 [P1] Strengthen numerical verification of the imported rounding fix

The teammate implementation's registered discarded-bit approach is directionally correct for shifts beyond the accumulator width and avoids the baseline's same-width rounding-add overflow. Update F1 from “shift 26–31” to the actual baseline risk range documented in R14-01: shift 24 can overflow for large positive accumulations, shift 25 has a zero-input counterexample, and shifts 26–31 are also wrong for part of the domain.

The teammate pipeline test exercises all shifts and biases largely with zero product sum. Before claiming the arithmetic contract closed, compare RTL with the independent exact oracle for nonzero positive/negative accumulations, accumulator extrema, rounding boundaries, signed24 bias endpoints, saturation rails and both ReLU states across all 32 shifts.

### IP-11 [P1] Make M12 an apples-to-apples research comparison

For MAC versus CFGLUT and 100 versus 125 MHz comparisons, freeze identical parameters, input corpus, output semantics, clock definitions, tool/version/directives and measurement method. The cited 100 and 125 MHz CFGLUT resource totals differ, so do not call them a pure-frequency axis until source/build manifests prove the intended controlled difference.

Vectorless power is an implementation estimate, not measured workload energy. Label it as such and do not mix full-system power with accelerator-hierarchy power in one FOM. Preserve both raw measures—results/cycle and results/s—and state exactly which resource/power boundary the competition formula uses.

## Corrected critical path for M10–M12

### M10A — freeze and repair the baseline

1. Resolve or explicitly scope every current P1 release blocker already listed below, especially R14-01 through R14-04.
2. Produce the clean-build baseline tag/evidence only after its stated contract matches what was actually qualified.
3. Preserve current M8/M9 software, profile library and immutable evidence before importing research RTL.

### M10B — make the teammate input reproducible

1. Resolve the target board.
2. Acquire the missing teammate artifact/report package or reproduce it from a clean tree.
3. Correct the WNS record and create a complete build-input/evidence manifest.
4. Reconcile the 100/125 MHz BD recreation path.
5. Regenerate and byte-compare the Dadda file, then run the expanded numerical and lifecycle tests.

### M11 — integrate the smallest competition-ready slice

1. Branch from current mainline and selectively transplant the CFGLUT/Dadda, pipeline, prefetch/window-bank and timing-safe controller changes.
2. Keep the current manager/CLI/importer; adapt them deliberately to `cfg_ready` and canonical K16 data.
3. Build and qualify N3/K16/W32 at 125 MHz first with exact anchors, >=100-frame soak, recovery/fault tests, measured clock and evidence hashes.
4. After that passes, build/qualify N3 K8 and K4 variants; include D640 only if the selected board and deadline allow it.
5. Keep C32 N5 on the frozen legacy engine until an N5 CFGLUT generator is independently ready.

### M12 — controlled comparison and release

1. Compare matched B32 MAC100, CFGLUT100 and CFGLUT125 builds only after their provenance and measurement boundaries match.
2. Keep simulation edge-bubble evidence separate from board frame/throughput evidence unless ILA/counters directly measure bubbles.
3. Publish raw timing, resources, estimated/measured power and exact definitions before derived FOM values.
4. Tag baseline and research releases separately, preserve both recovery images/artifact manifests, and update the final report with only qualified claims.

## Integration-plan acceptance gate

GLM should revise `INTEGRATION_PLAN_M10_M12.md` to close IP-01 through IP-11 before modifying RTL. The most deadline-efficient route is **current software + selective exact N3 CFGLUT RTL + one fully qualified B32/125 release first**. Generalization and N5 work must not delay that demonstrable slice.

---

# Current feedback for GLM — 2026-09-14

## Verdict and scope

**There is substantial, credible progress since the previous review. Preserve the passing baseline and its evidence. However, M8's unconditional COMPLETE claim is premature, and M9 must remain open.** The highest-priority issue is a numerical corner case in the baseline RTL; there are also fail-closed and library-integration gaps in the current software.

Reviewed branch: `v1-bringup`; implementation/evidence through `a3f31a5`, with documentation commit `e97e002` arriving during the review; changes since `3117f0f`. Reviewed the current M7 manager, M8 CLI/importer, decoder changes, conversion utility, mocks, qualification transcripts, M9 checklist, report corrections, and the baseline arithmetic implicated by the new research handoff. The `HANDOFF_v1bringup_to_edgefree125.md` and `INTEGRATION_PLAN_M10_M12.md` documents (initially untracked, then committed as `e97e002` during this review) describe a separate research lineage/plan, not work already integrated or board-qualified on this branch. This review does not certify that sibling branch.

Only `feedback.md` was edited. No tests, imports of application code, simulations, generators, conversions, builds, programming or board commands were executed. Counterexamples below are from static inspection, not claimed runtime results. Saved transcripts are reported user-relayed evidence; they are not new reviewer-observed board tests.

### Progress identified

| Area | What is now present | Review disposition |
|---|---|---|
| M7 ownership/layout/cleanup | Kernel `flock`; four guards; corrected RX offsets; runtime allocation and 22-bit length checks; cleanup requires legal quiescence and final `0x181` | Real fixes; retain them |
| Parameter admission | Strict scalar types/coefficient grammar, explicit `canonical-flat-2` conversion receipts, bundle digest, catalog/manifest comparison and WIDTHS register checks | Significant improvement; hardware-bias compatibility and snapshot sharing still need fixes below |
| M8 run path | Custom decoding delegated to a demoted Linux worker; `run` admits the image before switching; unverified output is labelled UNVERIFIED; exclusive run directories and atomic record replacement | Several prior findings partially or substantially resolved; do not extend that verdict to `soak` or all error paths |
| Importer | Model/dataset validation, transport extraction, collision check, publication and external receipts; board import/idempotency/list evidence | Import-only demonstration, not imported-model inference |
| E2 | Five profiles report four stimulus frames each, including both saturation rails and canonical reinstall; matrix rerun reports 58 reloads and all 20 ordered pairs | Valuable new coverage; not exhaustive numerical coverage |
| M9 soak | Six legs sum to 1,000 frames: A200/B200/C200/D200/D640100/B100, two image paths | Preserve as a six-leg campaign. It is not one uninterrupted 1,000-frame sequence or 1,000 distinct images |
| M9 cold boot | Five reported physical power removals/restorations, four reload paths plus A32 same-build activation | Stronger than the previous warm-reboot evidence; boot 1's script hash was not captured, as the record acknowledges |
| Report | Interface throughput is now labelled a theoretical ceiling; final D640 timing evidence is distinguished from intermediate results | Prior wording improved; latest campaigns and schema references still need updating |
| Research integration | EF125 handoff and M10–M12 planning documents | Proposed next lineage, not a replacement for finishing baseline gates |

The current `m7_switch.py` MD5 is `2fe949ca9040dd3fda990016c78a4474`; current `m8_cli.py` MD5 is `5542738961b01b2a2b1be4ac18136313`. Both match the latest M9 transcript identifiers. This resolves the earlier manager-source mismatch for those reported runs. It does not cryptographically bind every dependency, bitstream or archived record to execution.

## Blocking findings — address before release acceptance

### R14-01 [P1] Baseline rounding overflows at supported large shifts

References: `Convlution_Accelerator.srcs/sources_1/new/conv_channel.vhd:99`, `:159–165`; `config_pkg.vhd:106–107`; `software/m7_switch.py:547–560`.

`C_FULL_W` is 25 for the approved profiles, but both the rounding constant and the addition are evaluated in that same signed width. A minimal legal counterexample is **all weights zero, bias zero, shift 25, ReLU disabled**. The reference returns `(0 + 2^24) >> 25 = 0`. In the RTL, `1 << 24` occupies the sign bit of signed25, becoming negative; the subsequent arithmetic shift produces **-1**. For shifts 26–31 the rounding constant is shifted out of the 25-bit vector; negative accumulators can also produce -1 instead of the reference's 0. Shift 24 can overflow the rounding addition for sufficiently positive valid accumulators.

This is not exactly the research handoff's “out-of-range read” description: the current baseline uses a fixed-width add/shift. Correct the diagnosis in the integration plan. Existing low-shift passing vectors remain useful evidence, but the advertised 0..31 numerical contract is not fully satisfied. The new `extremes` saturation stimulus uses shift 0 and cannot detect this.

Required: use an overflow-safe rounding implementation without widening the entire product-sum pipeline unnecessarily; add directed RTL/reference comparisons for all 32 shifts, especially 24/25/26/31, zero and signed bias endpoints, both ReLU states, and positive/negative near-rounding boundaries. Requalify affected artifacts after a fix. Do not mark this resolved solely because a sibling research branch has different arithmetic. A narrower frozen-release numerical scope would require an explicit approved contract change and matching admission restrictions.

### R14-02 [P1] Cleanup/persistence failure still exits successfully; interruption can skip unlock

References: `software/m8_cli.py:401–434`, `:536–562`, `:675–700`, `:778–805`, `:866–872`.

After otherwise successful frames, an ordinary `safe_cleanup()` exception is caught and the record becomes FAILED, but the function returns normally. A `write_record()` exception is also swallowed. The executable consequently exits 0 despite failed cleanup or missing required evidence. Suppressing the terminal PASS message is an improvement, but a shell/GUI orchestrator still sees success. Additionally, a `KeyboardInterrupt` during cleanup is re-raised before `release_lock()`; an embedding caller which catches it keeps the lock, even though process termination would release it.

Required: one shared finalization path across all four modes, an outer `finally` that always releases ownership, and a nonzero process result/raised error for cleanup or persistence failure. Preserve the primary failure and separately report cleanup/persistence errors. Add injected cleanup failure, record-write failure and cleanup interruption cases; assert nonzero outcome, no PASS, and immediate lock reacquisition. Current mocks inject a frame failure, not these finalization failures.

### R14-03 [P1] New `soak --image` regresses pre-mutation admission

Reference: `software/m8_cli.py:472–499`.

`cmd_soak` calls `switch_to` before checking the custom-image reference limit or decoding the image. That call can reload PL, install parameters and execute the activation DMA frame. A missing/non-image input, wrong geometry, or unsupported D640 custom soak is rejected only afterward. The negative worker proof for `run` does not qualify this new ordering.

Required: resolve/decode/validate the selected input and verification mode before calling the switch manager, using the same admitted context as `run`. Add invalid-image, wrong-size, missing-file and disallowed-D640 soak cases that assert **zero programming, parameter writes and DMA launches**.

### R14-04 [P1] Bias admission trusts bundle width rather than the selected hardware width

References: `software/m7_switch.py:128–150`, `:466`, `:508`, `:528–541`.

`load_params` accepts a declared width up to 32 and validates against that declaration only. A bundle declaring `bias_width=32`, with bias `8388608`, passes this stage despite every current target implementing signed24. `program_params_accel` then emits the value after coefficient writes have begun. Hardware identity WIDTHS checks do not establish that the candidate biases fit those widths. The controller's canonical-bias check can reject this write; this must be a host-side admission error, not a deliberate MMIO error probe on the board.

Required: carry the target hardware bias width into complete bundle admission and validate every bias against it before any mutation. Test both signed24 endpoints and one beyond each, including a deliberately wider bundle declaration. Use mocks, not a live invalid AXI write, for rejection tests.

### R14-05 [P1] Source-byte limit is applied after an unbounded supervisor read

References: `software/m8_cli.py:140–146`; `software/conv_lab/preprocessing.py:185–192`.

The worker isolation is real, but `Path.read_bytes()` first reads the entire supplied path in the root supervisor. Only then does `LinuxDecoder.decode` enforce 8 MiB. A very large file can exhaust board RAM before the worker starts; a special/unending input can block outside the worker deadline. The 128 MiB worker limit cannot protect that read.

Required: open once, reject inappropriate file types, perform a bounded read of at most MAX_SOURCE_BYTES+1, reject excess bytes, and pass those exact bytes to hashing/decoding. Do not rely only on a pre-read size check susceptible to growth. Add oversized-file and special-file rejection tests with no hardware writes. Keep the isolated worker; do not replace it with in-process decoding.

## Remaining integration and evidence gaps

### R14-06 [P1 — M8 scope] Imported models/datasets cannot be selected by the runtime

References: `software/m8_import.py:272–306`; `software/m7_switch.py:32–43`, `:112–157`; `software/m8_cli.py:264–269`, `:836–860`.

The importer publishes format-3 bundles under `/var/lib/conv-lab/library`, but the runtime still selects fixed profile-directory `canonical-flat-2` parameters under `/home/petalinux/profiles`. Its CLI has no model/release/dataset/image-ID selection. Imported preprocessing/compatibility metadata is not consumed by inference. Hardware imports are explicitly unsupported. The board importer fixture is K=2, so it also does not demonstrate execution on a supported profile.

Required for the approved library workflow: connect an explicit identity resolver over embedded and imported roots to a single validated runtime context; demonstrate import → select model/image → activation → exact-reference run → archive, and a compatible parameter-only model change. Reject conflicting same-ID releases across roots. If the immediate release intentionally supports only frozen profiles and arbitrary image paths, document that as an approved scope reduction; do not call the full library workflow complete. Do not implement hardware import casually as part of this fix—retain its separate compatibility/reconfiguration gate.

### R14-07 [P2] Hash binding is incomplete and the admitted context is reopened

References: `software/m8_cli.py:244–252`, `:295–297`, `:343`, `:467–473`, `:703–743`; `software/m7_switch.py:466–508`.

The CLI parses parameters for the reference, then independently re-reads them for individual hashes; `switch_to` parses them again for hardware installation. The hardware-owner lock does not prevent filesystem editors/converters from changing those files. Therefore one bundle digest does not prove the reference, record and hardware consumed the same snapshot. Benchmark records still leave `input` and `parameters` empty; soak/extremes omit the catalog/anchor-file hashes added to `run`; records do not retain the actual selected hardware-manifest/firmware hashes. Custom-image bytes are not preserved or registered in a retrievable immutable store, so an arbitrary path and its hash alone cannot reproduce a run after the file disappears.

Required: share one frozen parameter/input/hardware context across activation, reference and record creation; return the identity actually installed by the manager. Standardize provenance fields for all modes. Preserve content-addressed custom inputs, or explicitly bind them to a retained immutable dataset. Hash-only storage can avoid duplicates, but only when those bytes are demonstrably retrievable. Add a test changing files between admission and switch that either uses the frozen original or rejects before writes.

### R14-08 [P2] Import idempotency verifies only the manifest, not the installed bundle

References: `software/m8_import.py:274–281`, `:284`, `:298–301`.

On re-import, an existing matching manifest yields `already-imported` without rechecking its referenced files. Delete or corrupt an installed weight/image while leaving the manifest intact, then re-import the original archive: the importer reports success and leaves the corruption in place. Published files are handed to the board user, so post-import changes are possible. Receipt names also have only second-level time plus identity and are overwritten by `write_text` on a same-second repeat.

Required: revalidate existing content before idempotent success; fail closed on damaged content without silently overwriting the published release. Use exclusively allocated unique receipt names and atomic publication. Add altered/deleted-payload and same-second receipt tests. Resolve conflicts against embedded bundles as part of R14-06, not only the mutable root.

### R14-09 [P2] Resource accounting is not yet the approved bounded-storage policy

References: `software/m8_import.py:83–103`, `:248–251`; `software/m8_cli.py:69–82`, `:336–339`, `:732`.

The importer reserves `compressed_size*3 + 1 MiB`, while accepting up to 64 MiB extracted: a highly compressible valid archive can consume much more than the reserved amount and breach the promised 512 MiB headroom. `getmembers()` materializes the entire tar inventory before enforcing the 256-member cap. The CLI checks each run's estimate against 256 MiB, not the accumulated disposable payloads; benchmark's estimate is constant despite unbounded `--frames`. Import and inference use different locks and no shared reservation ledger, so their free-space checks can both admit against the same space.

Required: bounded/streaming inventory admission, conservative extracted/output peak accounting, aggregate disposable-budget enforcement, and coordinated reservations across operations on the filesystem. Test a compressed expansion case, many zero-length headers, sequential runs over the aggregate budget, concurrent import/run reservations and very large benchmark counts. Keep protected evidence excluded from automatic deletion; do not solve quota failures by broad cleanup.

### R14-10 [P2] The new conversion utility can overwrite qualified profile files mid-conversion

References: `scripts/convert_legacy_profiles.py:37–69`, `:75–76`, `:95–98`.

The default output is the live repository `profiles/`, existing output directories are accepted, weights are copied before the whole source is validated, and a fixed receipt is overwritten. A late malformed channel/absent weight can leave a mixture of old metadata and new weights. The original `weights_file` is also used as a path without containment validation. This is not equivalent to the earlier isolated converter's refusal of existing destinations.

Required before reuse: explicit fresh staging/output root, complete source/path validation, atomic publish, and a unique receipt; alternatively retire this as a clearly labelled one-time migration tool and prevent accidental reruns. Preserve already converted files/receipts and the original legacy bytes. No regeneration was performed during this review.

## Release evidence and research handoff

- Keep M9 §4 open: clean-build reproduction, final reviewed tag/snapshot and final documentation are still unchecked. Fix or formally resolve the blocking findings before declaring “no critical correctness/switching issues.” Rebuilding alone does not qualify changed RTL/software.
- The newest evidence files are useful summaries/excerpts. The matrix file contains an ellipsis in the transition list, and the 1,000-frame file contains a summary table plus board-local record IDs. Transfer the original schema-v3 records/full matrix log, verify their hashes and preserve them with the source/artifact manifest. Do not describe these abbreviated files as complete verbatim transcripts. Do not rerun expensive campaigns merely to replace missing copied records if the originals remain available.
- Update stale `M9_CHECKLIST.md` introductory M8/BLOCKREADY status, `report/report.md`'s 876-frame/90-reload totals and schema-v2 S18 wording, and the handoff's stale next-action sections. Derive updated totals from a run ledger to avoid double counting activation versus stimulus frames. This does not erase the valid earlier campaign.
- The new M10–M12 plan identifies the large-shift concern but understates it as 26–31: R14-01 includes shift 25 and a shift-24 overflow case. Its one-output-position-per-clock bonus wording also needs a scope qualifier: a 64-bit stream carrying K16 signed16 channels needs four beats per complete output position. An internal II=1/edge-free test is not proof of one full position per clock at the external interface. Likewise distinguish an interface ceiling from measured sustained throughput.
- The EF125 sibling line remains separately identified and board-NOT_RUN in its handoff. Keep clocks/FSBL assumptions, artifacts, profile coverage and performance evidence separate until the proposed integration is actually reviewed and qualified. No branch checkout, merge or adoption occurred here.
- Keep the cleanup scan as a proposal. Its own HOLD list includes potentially unique legacy metadata and board-qualified source copies. No deletion is justified solely by a “regenerable/zero risk” label until those bytes and release dependencies are preserved.

## Recommended next batch for GLM

1. **Numerical and fail-closed repair:** address R14-01 through R14-05, add targeted tests, and hand the user the exact test/simulation commands. Do not change unrelated datapath architecture, regenerate weights or start research integration inside this repair batch.
2. **M8/M9 closeout correction:** address R14-06 through R14-10 in scoped follow-up work, preserve the actual records, and reconcile milestone/scope claims. Then perform the agreed user-run clean-build and affected board qualification before the reviewed release freeze.

Snapshot SHA-256 (current review):

| File | SHA-256 |
|---|---|
| `software/m7_switch.py` | `4c2df0d516e4833b78d7794456fbc0b91cb2f603f0ee512c8cc0b90f3f246360` |
| `software/m8_cli.py` | `3fa1ff0edc7960b9ad946da5050e0f3377000a8ddd25a74ae85d53ddea3650a1` |
| `software/m8_import.py` | `f607a6265508bf3eddbf608db18e92ec745113ec731b61bf0d2d318bbbc6ed76` |
| `software/conv_lab/preprocessing.py` | `eebc34d46018b8bd5a7fed2b889b99de15bbba1a505aa7a9bb500fda58e77894` |
| `Convlution_Accelerator.srcs/sources_1/new/conv_channel.vhd` | `57fada818c3bd8ea5fb22716ac06e76cc87a259efc64305dc7a01a56697f1cd0` |

---

# Historical feedback — 2026-09-13 (superseded by the review above)

Review date: **2026-09-13**. This section supersedes the original review retained below as history.

## Verdict and reviewed snapshot

**M7 has substantial new reported board evidence and genuine fixes. M8 is not ready for acceptance or an unattended board demo.** Preserve successful board evidence, but do not treat it as proof that every earlier finding is resolved or that the current source is qualified.

Reviewed HEAD: `3117f0f` (M7: qualify five profiles and runtime model switching). New untracked work: `software/m8_cli.py` and `verification/m8_cli/`. Reviewed the manager/CLI, both mock harnesses, catalog/manifests, M7 transcripts, relevant contracts, report corrections and earlier findings.

Snapshot SHA-256:

| File | SHA-256 |
|---|---|
| `software/m7_switch.py` | `08f3aaa9a4237af51616f6bed535f015c5036e475aa2e70d5bfc6dff16c9ba71` |
| `software/m8_cli.py` | `134df82494c4867676d81de692144b6e5101115e4653bc624b705b64f2e6432c` |
| `verification/m8_cli/mock_cli_test.py` | `e70b96f1a6b41213f7276740a1fe7a2d41970fe6d0e323105bf555368dcd5827` |

Only this feedback document was edited. No application imports, tests, training, generators, builds or board commands were executed. Transcript counts were obtained by reading saved text, not rerunning the manager. References below use file paths and line numbers from this snapshot. P1 indicates a blocking correctness/safety/acceptance issue; P2 indicates a significant evidence, completeness or maintainability issue.

## Confirmed improvements

- Earlier undefined FPGA paths, missing identity keys, undefined counter variable and invalid logging call are fixed in current source.
- Frame execution now checks DMA IOC/error and accelerator completion/fault state. S2MM length is exactly RX bytes, not RX bytes plus guard.
- Same-build activation now validates identity and rejects entry ERROR/FAULT states.
- D640 resize is implemented; activation digests are appended.
- C32/D32/D640 catalog IDs now match their manifests. This resolves the catalog discrepancy, not full provenance/admission.
- Matrix construction no longer has the first-character/infinite-loop defect.
- Saved transcripts report five 100-frame soaks, switching and post-reboot activation. Parsing the matrix's 58 activation lines from its stated D640 start finds all 20 distinct directed pairs. These are valuable historical records.
- Report/figure accumulator width is corrected to 25 bits, and the old one-position/cycle claim was reduced to the serializer-derived bound. Measured-versus-theoretical wording remains an issue.
- M8 delegates MMIO/DMA to M7, separates previews from comparison data, and introduces records and timing fields. Retain these directions.

## New M8 findings

### M8-01 [P1] Unverified custom D640 outputs receive PASS

References: `software/m8_cli.py:270-278`, `:285-317`; `software/m7_switch.py:403-405`.

For a custom image above REF_POSITION_LIMIT without --reference, expected=None and verification mode is sha_only. There is no expected hash to compare. The backend returns mismatches=0 whenever expected is None, and the CLI marks the run PASS. Arbitrarily wrong output with valid transfer counters/guards can therefore receive a verified-looking PASS.

Required: obtain an independent expected result/hash for the admitted input and parameters, or explicitly return UNVERIFIED/NOT_CHECKED with mismatches=null. Separate execution success from numerical verification. A hash of an unknown answer is not a correctness check. Add a custom D640 test with deliberately incorrect output and valid DMA/counters that cannot receive verified PASS.

### M8-02 [P1] Arbitrary image decoding runs as root, after activation, with limits too late

References: `software/m8_cli.py:88-113`, `:231-242`.

The loader reads the entire file before checking its byte limit and calls im.load() before checking dimensions/pixel count. Pillow runs in the root hardware-owning process without an unprivileged worker, address-space ceiling or supervised deadline. It hashes one path read and reopens that path for decoding, so a changed file can yield different decoded bytes. It also lacks the approved PNG/JPEG format restriction.

Before this validation, switch_to() may already reprogram PL, write parameters and run an activation frame. A wrong-size, missing or malformed user image is rejected only after those mutations.

Required: reuse the bounded immutable-source snapshot and isolated decoder worker. Validate the requested operation, canonical byte count and reference availability before hardware writes. Decode exactly the hashed bytes. Enforce size/dimension limits before full decode and through transformations; isolate worker descriptors from hardware handles. Test that rejected input causes zero programming/parameter/DMA writes.

### M8-03 [P1] Cleanup errors can still publish/print PASS; record errors can retain ownership

References: `software/m8_cli.py:317-340`, `:410-427`.

Outcome is set to PASS before safe_cleanup(). The nested finally writes that PASS record and prints PASS even if cleanup raises; the exception propagates afterward. If write_record() raises, release_lock() is skipped. Cleanup/archive exceptions can also obscure the primary failure.

Required: record separate operation, verification, cleanup and persistence outcomes. Emit terminal PASS only after required stages succeed. Release ownership in an outermost finally independent of archive success. Preserve primary and secondary failures. Test cleanup timeout/error, record-write failure, cancellation and combined failures.

### M8-04 [P1] Archive IDs can collide and overwrite previous evidence

References: `software/m8_cli.py:194-197`, `:212-219`, `:296-297`, `:355-361`.

Benchmark IDs contain only second-resolution time and profile; exist_ok=True reuses directories. Run mode attempts one deterministic suffix, so repeated collisions reuse that second location. Clock resets are a known board condition. Existing record/frame files can be overwritten or mixed across runs. Direct record writes can leave truncated JSON; list mode then fails on a malformed record.

Required: exclusively allocate unique run directories and never overwrite prior payloads. Atomically publish records and preserve pending/failed operations. Append completed benchmark-frame evidence incrementally: currently the frame list is built only after the final frame succeeds, losing earlier successful-frame details on a later failure. Test frozen clocks, repeated names and interrupted/corrupt archives.

### M8-05 [P1] Privileged archive operations lack containment and symlink safety

References: `software/m8_cli.py:50-68`, `:194-197`, `:442-446`.

M8_ARCHIVE_ROOT is unrestricted; record <run-id> accepts absolute paths and traversal; output/ownership operations use ordinary paths without symlink checks. chown_tree recursively changes ownership, and os.chown follows symlink targets. A reused or user-writable archive can redirect privileged writes/ownership changes outside the intended tree.

Required: approved roots, single-component validated run IDs, containment checks, no symlink components/targets, and ownership changes only for files created for the current operation. Test traversal/symlink cases with harmless fixtures. Do not turn a writable results directory into an arbitrary root write/chown interface.

### M8-06 [P1] Storage admission, reservations and bounded growth are missing

References: `software/m8_cli.py:50-59`, `:218-219`, `:283-315`.

Every run frame is saved without storage-derived admission. D640 raw output is 2,457,600 bytes/frame before metadata/previews. Previews scale both dimensions by eight even for D640. There is no free-headroom reservation, disposable-payload budget or protected-evidence policy. Root can fill the OS filesystem and then fail to record the error.

Required: use the approved storage policy before hardware activation, accounting for peak temporary/final outputs and previews: 512 MiB free headroom and a 256 MiB disposable run-payload budget, with protected evidence excluded from automatic deletion. Reject when insufficient space remains; do not silently bypass policy with a fallback root. Bound previews and actual growth. Test low-space rejection before hardware writes.

### M8-07 [P2] Archives do not yet contain enough identity to reproduce a run

References: `software/m8_cli.py:168-191`, `:255-257`, `:350-381`.

Missing items include model/config/weight hashes, complete manifest/firmware identity, Pillow/codec versions and exact command/options. Custom source paths are mutable; canonical bytes are hashed but neither preserved nor bound to an immutable dataset. Benchmark input metadata remains empty. M8 reloads parameter files after M7 programmed them, allowing reference inputs to differ from hardware parameters if files change.

Required: admit one immutable input/model/hardware snapshot shared by hardware, reference and recording. Preserve or content-address all necessary assets and record observed identity, layout, versions, verification method, output inventory/checksums and cleanup outcome. Validate archives for missing/tampered members. Do not invent missing hashes.

### M8-08 [P2] Measurement names imply scopes they do not measure

References: `software/m8_cli.py:285-300`, `:388-408`; `software/m7_switch.py:318-321`, `:352-375`, `:395-405`.

hw_ms is a host-clock MM2S submission-to-poll-completion interval, not a hardware cycle counter; it includes polling overhead. wall_ms surrounds run_frame only and excludes activation, preprocessing, archive writes and previews. io_overhead_ms_median subtracts medians and includes hashing/unpacking/reference comparison, not just I/O. frames_total_s also excludes frame-file archival.

Required: explicit interval names/scopes, raw samples and separate whole-operation wall time. Do not derive kernel-only speedup/FOM from polling latency. If reporting paired overhead, summarize per-frame differences and identify included work. For D640 retain the large buffer-copy cost instead of presenting milliseconds as total user-visible runtime.

### M8-09 [P2] Tests omit critical negative cases and depend on a temporary local fixture

References: `verification/m8_cli/mock_cli_test.py`; `verification/m7_profiles/mock_switch_test.py:27-28`.

The test covers mainly A32/B32 success and one injected activation failure. It omits custom D640 unchecked output, concurrent owners, cleanup failure, disk full, archive collisions, worker enforcement, traversal, symlinks, DMA cancellation and partial benchmark records. The imported fixture defaults to one user's temporary m7_bundle2/profiles directory, so a clean checkout is insufficient. Mock output uses the same reference implementation as the consumer: useful for wiring checks, not independent numerical qualification.

Required: portable isolated/versioned fixtures, the missing negative cases, and explicit mock-versus-ARM/decoder-enforcement status. Hardware error-path tests must remain mocked/simulated where real SLVERR causes SIGBUS. No new M8 runtime PASS was independently established in this review.

## M7 backend gaps inherited by M8

### M7-R1 [P1] The lock is check-then-create, not exclusive

Reference: `software/m7_switch.py:567-574`.

Two processes can both observe an absent PID file and both proceed. Abrupt exit leaves a stale file; release unlinks by name without proving ownership. M8's exclusive-owner claim is not implemented.

Required: OS-backed exclusive ownership held for the entire lifecycle, protected lock location and ownership-safe release. All hardware entry points must honor it. Test simultaneous acquisition and termination; the loser performs zero hardware accesses.

### M7-R2 [P1] Activation ignores the discovered allocation and uses the wrong guard layout

References: `software/m7_switch.py:171-194`, `:421-431`, `:327-331`; `software/hardware_D640.json:39-44`.

main()/M8 discover ctx['buffer_size'], but switch_to uses acc.get('buffer_bytes',4194304). That field is not in the accelerator object, so activation assumes 4 MiB even when runtime allocation is smaller. Checking later frames is too late.

compute_layout reserves only one 64-byte separation. RX offsets are 5376 for A/B/D32, 5504 for C32 and 313664 for D640, versus approved 5440/5568/313728. TX guards remain absent; physical aperture/alignment/DMA-length checks are missing. The D640 manifest still declares the old overlapping RX offset 65536. Current computed RX does not overlap TX, but it does not implement the approved four-guard layout.

Required: validated conv_lab layout with actual allocation facts before activation; reject incompatible buffers before DMA, reconcile manifests, and require padded payload length equals submitted TX length. Historical results qualify the actual tested layout, not a different promised layout.

### M7-R3 [P1] Cleanup can issue illegal RESET and print PASS on failed execution

References: `software/m7_switch.py:646-657`, `:696-723`.

safe_cleanup checks IDLE or FAULT but not QUIESCENT before RESET. A faulted accelerator can still have pending output; halting DMA does not prove quiescence. RESET risks the known SLVERR/SIGBUS behavior. Matrix cleanup prints PASS from finally even when its body raised, if cleanup succeeds. Top-level cleanup exceptions are printed and suppressed.

Required: validate complete legal reset state; avoid speculative MMIO on unknown fabric; record unresolved state as recovery-required. PASS needs successful execution AND required cleanup. Cleanup success cannot turn a failed matrix into PASS.

### M7-R4 [P1] Bundle/platform admission is still partial

References: `software/m7_switch.py:105-140`, `:263-294`, `:410-470`.

Range/order checks improved, but permissive format-2 JSON remains: ignored schema/scale/bias-width declarations, noncanonical types, invalid ReLU silently treated as zero, unconstrained weight paths, no immutable whole-bundle hash snapshot. The catalog argument does not validate the chosen manifest. Width registers are not validated; reload does not first establish a complete known source-platform identity. Production preprocessing does not consume its recorded canonical policy/hash.

Required: integrate approved strict admission and immutable snapshots, with explicit legacy conversion. Validate platform compatibility before touching the old fabric. Numeric bounds alone do not turn signed32 legacy metadata into a signed24/format-3 bundle.

## Evidence and closeout: reconcile without erasing success

### E1 [P1] Current source does not match the recorded board-tested source

Current m7_switch.py MD5 is `184d75c07eb96d4b7e64b27b6a05dd31`. New board transcripts/handoff identify `e853933b4d0610881e895be4ff48c3bf`. LF normalization leaves the current hash unchanged; its CRLF variant is `815521e84b68894198ea5c22cf064a9c`, so those line-ending variants do not explain the mismatch.

Required: preserve the actual board-tested file, compare it with committed source, explain the differences, and bind qualification to the correct snapshot/artifacts. Do not relabel transcripts. This gap does not imply the reported runs did not happen.

### E2 [P2] Directed-pair coverage exists, but exact gate claims need correction

- The 58 matrix activation lines cover all 20 pairs. Actual occurrence counts are A32=23, B32=23, C32=4, D32=4, D640=4; the footer says 24/24/5/4/4, which totals 61.
- The loop begins with B32 irrespective of source. Starting at D640, iteration one is D640->B32->A32, not a full A32->B32->A32 cycle. The initial alternating block therefore gives 19 consecutive full A32 cycles; a later edge is not proof of 20 consecutive cycles. Establish A32 before the counted loop if retaining that approved gate.
- The saved coldboot procedure says sudo reboot. It supports reboot/persistence/reload behavior, not a documented power removal/restoration. Preserve the actual procedure and identify separate power-cycle evidence for that claim.
- Five fixed-input soaks alone do not demonstrate all per-profile M5-grade extremes, varied inputs/parameters, lifecycle and bounded-failure coverage required by M7_CONTINUATION. Locate that evidence or leave those qualification items open; never regenerate evidence from expected behavior.

### E3 [P2] Foundation tests and report evidence remain partly stale

- test_m7_profiles.py still freezes old C32/D32/D640 IDs and asserts current selection is B32 while the source is D640. Those assertions cannot pass unchanged. Update approved anchors without weakening independent checks.
- Archived D32/D640 timing reports remain pre-optimization reports. Preserve final reports tied to exact bitstreams; current passing D640 live-run evidence is not the archived failing report.
- Widths were corrected, but 4/K positions/cycle is an interface ceiling, not an automatically measured sustained rate. Report/FOM and correction guidance still treat it as sustained/measured. Use a labeled theoretical upper-bound FOM or measured throughput at a consistent scope, not merely half the previous unsupported rate.
- Legacy exporter arbitrary-destination deletion and signed32 metadata remain open (original findings 11/8). Preserve explicit conversion and safe export requirements.
- State/README/fix-plan guidance remains contradictory. The handoff says commit pending although 3117f0f exists. Reconcile current guidance while clearly preserving historical material.

## Prior-review disposition

| Original finding | Current status |
|---|---|
| 1 runtime exceptions | Fixed in source; board-source binding remains E1 |
| 2 missing DMA completion | Materially fixed: IOC/error and accelerator completion checks added |
| 3 guarded layout | Open: M7-R2 |
| 4 catalog ID mismatch | Catalog/manifests reconciled; tests/provenance/admission remain open |
| 5 matrix infinite loop | Fixed; exact cycle coverage remains E2 |
| 6 missing D640 resize | Implemented; isolated metadata-driven preprocessing still incomplete |
| 7 lifecycle/ownership | Partial: M7-R1/R3 and M8-03 block acceptance |
| 8 strict admission/bias | Numeric checks improved; M7-R4/conversion remain open |
| 9 evidence freshness | Open: E1/E3 |
| 10 throughput/widths | Widths corrected; measured throughput/FOM/citations remain E3 |
| 11 unsafe export deletion | Open |
| 12 qualification gate | Soaks reported; full-gate/cold-boot/cycle precision remains E2 |

## Suggested work order for GLM

1. Preserve and reconcile the exact board-tested M7 source before changing the backend. Keep historical artifacts/evidence immutable.
2. Fix false verification/PASS, legal cleanup, actual allocation admission and exclusive ownership; add focused negative tests for the actual paths.
3. Integrate the existing isolated decoder, strict immutable bundles and bounded/atomic archive storage rather than adding weaker parallel implementations.
4. Make fixtures portable, records complete and timing scopes explicit. Request user-executed host/Linux/ARM validation under the established workflow.
5. Close only evidence-backed qualification gaps and complete report corrections before release. Do not expand into GUI/optimization work to bypass these blockers.

This review is feedback, not authorization for autonomous training, builds or board operations. Only feedback.md was edited.

---

# Historical review: 2026-09-12 (superseded by dispositions above)

Review date: 2026-09-12

## Verdict and scope

**Changes requested before any M7 board run. Moving the extracted folder is not the only blocker.**

This feedback records a read-only review of the M7 changes, including `M7_STATE.md`, the switch manager, profile catalog/manifests, RTL changes, build preparation, tests, numerical exports, available artifacts/evidence, and report claims. No tests, builds, generators, or hardware commands were executed during the review. No implementation files were changed. This feedback file was subsequently created at the user's request.

The reviewed `software/m7_switch.py` has MD5 `9337746ce1e5d597156458fd8666b09e`, matching the version recorded in `M7_STATE.md`. Findings describe that reviewed snapshot; later changes require reassessment.

P1 means a blocking correctness, safety, or submission-accuracy issue. P2 means a significant consistency, evidence, or maintainability issue.

## Blocking findings

### 1. [P1] Multiple guaranteed runtime failures in the switch manager

- `FPGA_FLAGS` and `FPGA_FIRMWARE` are undefined when the reload branch uses them.
- `read_identity()` does not return `magic` or `abi`, but `validate_identity()` accesses both keys.
- `run_frame()` unpacks `tx_size`, but the counter checks reference undefined `tx_bytes`.
- `log()` accepts one argument, but activation success calls it with two arguments.

These failures occur along normal activation paths. Syntax compilation cannot catch them.

References: [programming](software/m7_switch.py#L199), [identity](software/m7_switch.py#L122), [counters](software/m7_switch.py#L155), [logging](software/m7_switch.py#L228).

Required: fix these defects and exercise the actual manager through a mocked complete activation, not just its supporting helpers.

### 2. [P1] Accelerator completion is incorrectly treated as DMA completion

The manager waits for accelerator `DONE|IDLE`, then reads the receive length and buffer. It never requires both DMA channels to complete without errors. Accelerator stream completion is not proof that S2MM has finished writing DDR. The existing M4 backend explicitly checks DMA completion; the new manager drops that protection.

Reference: [run_frame](software/m7_switch.py#L149).

Required: restore separate, bounded DMA and accelerator completion checks before reading output or allowing another operation. Check DMA errors throughout relevant waits, and validate the final accelerator state/counters/errors separately.

### 3. [P1] Runtime bypasses the guarded-layout implementation

The manager:

- Never calls `profile_layout()` or `validate_layout()`.
- Never checks the actual DMA buffer allocation size.
- Retains RX offset `65536` for the small profiles instead of their approved calculated layouts.
- Programs S2MM receive length as `rx_bytes + 64`, including the trailing guard in writable receive capacity.
- Installs/checks only RX guards rather than all four TX/RX guards.

Separately, `software/hardware_D640.json` still declares RX offset `65536`, overlapping its TX region. D640 TX occupies `[4096, 313540)`. The manager itself calculates a different D640 RX offset, so this is a manifest/runtime inconsistency, not a claim that its calculated D640 offset overlaps.

References: [runtime layout](software/m7_switch.py#L73), [receive submission](software/m7_switch.py#L142), [D640 manifest](software/hardware_D640.json#L39).

Required: use one validated layout, actual runtime allocation facts, exact receive length, alignment/aperture/length checks, and all four guards. Do not silently ignore contradictory manifest fields.

### 4. [P1] Profile identities have competing definitions

C32, D32 and D640 IDs in `profiles/m7_profiles.json` differ from their hardware manifests:

| Profile | Catalog BUILD_ID | Manifest BUILD_ID |
|---|---|---|
| C32 | `4d374e354b385733322d323630393132` | `434e354b30385733322d323630393132` |
| D32 | `4d374e334b345733322d323630393132` | `444e334b30345733322d323630393132` |
| D640 | `4d374e334b3457363430483438300001` | `443634304e334b30342d323630393132` |

The selected D640 RTL follows the manifest ID, while the discovery tests generate their expected IDs from the different catalog. Passing those tests therefore does not validate the identities described for the built images. A32 and B32 catalog/manifest IDs agree; the issue is not hexadecimal ID length.

References: [catalog](profiles/m7_profiles.json#L6), [selected RTL](Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd#L18), [D640 manifest](software/hardware_D640.json#L7).

Required: reconcile catalog, generated RTL, manifests, actual artifacts and evidence. Do not merely rewrite IDs to make comparisons pass. Preserve evidence of what each existing bitstream actually represents and distinguish new builds from previously tested artifacts.

### 5. [P1] Matrix construction can loop indefinitely

In `build_matrix_sequence()`, `bridge` is a profile-name string, but `bridge[0]` selects its first character, such as `C` rather than `C32`. Once the walk exhausts A32's remaining outgoing edges, it enters this branch without reducing `remaining`. The manager can hang before performing the matrix switches.

The matrix also assumes the initial profile is A32 rather than proving it. Its `digests` list is never populated, so the summary's activation-frame count is not meaningful. Requested destinations are not sufficient evidence of observed source-to-destination coverage.

Reference: [matrix construction](software/m7_switch.py#L246).

Required: test termination, valid profile names, and coverage independently; establish the actual starting profile; record observed transitions and successful activation frames. Allow necessary connecting transitions rather than assuming the claimed total automatically proves coverage.

### 6. [P1] D640 preprocessing is described but not implemented

`load_input()` opens the original 32x32 image, converts it to grayscale, and immediately requires its dimensions to equal the requested geometry. There is no resize. D640 therefore fails after parameter programming. The recorded D640 preprocessing metadata and canonical hash are not used by this path.

Reference: [load_input](software/m7_switch.py#L53).

Required: apply explicitly approved preprocessing through the existing bounded decoder pipeline, verify canonical bytes, and finish input validation before hardware mutation. Do not introduce silent resizing or bypass the established decoder-resource and privilege boundaries.

### 7. [P1] Admission and failure handling regress the approved lifecycle

- A matching BUILD_ID skips full identity validation.
- QUIESCENT alone is accepted without excluding FAULT/error states.
- There is no exclusive ownership lock to prevent concurrent managers.
- `--profile` and `--soak` lack guaranteed DMA cleanup on failure.
- Matrix mode prints PASS before its final cleanup checks.
- The final RESET wait accepts any bit in `IDLE|QUIESCENT` rather than requiring both, and does not establish the full claimed clean state.

References: [admission](software/m7_switch.py#L185), [execution modes](software/m7_switch.py#L281), [matrix cleanup](software/m7_switch.py#L327).

Required: validate every activation path, serialize ownership, and define safe cleanup/fail-stop behavior before issuing PASS. Recovery must respect whether the fabric identity and transaction state are known; closing file handles is not equivalent to stopping DMA.

### 8. [P1] Parameter loading bypasses strict admission and signed24 enforcement

The manager directly accepts legacy format-2 files without validating channel ordering/uniqueness, coefficient ranges, signed24 bias bounds, shift bounds or bundle member hashes. It does not validate the complete bundle before MMIO writes.

The exporter still advertises and permits signed32 biases. The inspected B32 and C32 exports happen to fit signed24, so this is not a claim that those particular biases overflow; future exports need not fit. The current weak loader does not enforce the hardware limit.

References: [parameter loader](software/m7_switch.py#L35), [exporter bias validation](golden_model/extract_weights.py#L87), [export metadata](golden_model/extract_weights.py#L210).

Required: retain explicit legacy conversion, then use the approved strict admission path before any MMIO writes. Validate channel association, coefficient/bias/shift/ReLU values, geometry, schemas and member hashes. Preserve immutable historical inputs rather than silently relabeling legacy metadata.

## Evidence and reporting corrections

### 9. [P2] Historical PASS results do not qualify the current source completely

Existing logs genuinely show successful foundation tests. However, the current software test asserts that the working configuration equals the B32 projection, while the working configuration is now D640. That assertion cannot pass unchanged. These tests also never exercise `m7_switch.py`; the RTL bench covers discovery, not complete per-profile convolution and switching behavior.

Reference: [stale projection assertion](software/tests/test_m7_profiles.py#L136).

Archived D32/D640 routed timing reports contain WNS **-0.440 ns** and **-0.676 ns**, respectively. The current D640 **post-optimization** report correctly shows **+0.001 ns**, and its current run bitstream hash matches the named D640 bitstream. However, the passing post-optimization report is not the report archived under `report/profile_builds/D640/`.

References: [archived D32 timing](report/profile_builds/D32/accelerator_dma_wrapper_timing_summary_routed.rpt#L141), [archived D640 timing](report/profile_builds/D640/accelerator_dma_wrapper_timing_summary_routed.rpt#L141), [current D640 final timing](Convlution_Accelerator.runs/impl_1/accelerator_dma_wrapper_timing_summary_postroute_physopted.rpt#L141).

Required: preserve final artifact-matched reports and test-source provenance. Label intermediate failing reports as such. Update stale documentation about the selected profile and test status. Do not interpret a successful earlier test run as qualification of later changes.

### 10. [P1: submission accuracy] Sustained throughput and FOM are overstated

The report claims one complete output position per cycle and a 10.24 microsecond frame. For K8, each output position contains eight signed16 results: **128 bits over a 64-bit interface requires at least two beats**. The output alone requires at least **2048 cycles / 20.48 microseconds at 100 MHz**, before additional stalls. A compute pipeline's peak rate cannot be presented as measured full-system sustained throughput.

References: [throughput claim](report/report.md#L85), [results table](report/report.md#L262), [FOM](report/report.md#L294), [serializer](Convlution_Accelerator.srcs/sources_1/new/axi_stream_output_serializer.vhd#L414).

Required: distinguish scalar channel outputs from complete spatial output positions, and core peak rate from sustained integrated throughput. Recalculate FOM using an explicit, supported throughput definition and consistent measurement scope.

Also correct the report and figure's 32-bit bias / 33-bit accumulator descriptions. The implemented approved policy uses **24-bit bias and a 25-bit final accumulator** for these profiles. Some RTL comments are stale and must not substitute for the actual derived constants.

References: [report arithmetic](report/report.md#L66), [figure source](report/figures/generate_figures.py#L12), [actual configuration](Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd#L52).

Freeze source citations too: the report's A32 timing citation points into a live run directory now containing D640 results. Source references must identify the exact build supporting each claim, not whatever was built most recently.

### 11. [P2] Export destination flexibility introduces deletion risk

`CNN_WEIGHTS_DIR` now accepts arbitrary paths, but export deletes every file in an existing destination before completing conversion. A mistaken path or later quantization failure can destroy unrelated or previous output. The deletion loop predates this change, but allowing externally selected destinations expands its risk.

References: [environment-selected destination](golden_model/extract_weights.py#L46), [export cleanup](golden_model/extract_weights.py#L160).

Required: validate destinations, reject protected/input locations, and use fresh atomic exports. Any replacement should be explicit and scoped, not a blanket deletion of directory contents.

### 12. [P2] M7 closeout omits approved qualification gates

`M7_STATE.md` treats per-profile soak as optional and suggests 20 frames. `M7_CONTINUATION.md` retains the approved requirement of **at least 100 frames without inter-frame reset per compiled case**, applicable numerical/lifecycle tests, and cold-boot fallback. Those requirements must not disappear from closeout.

References: [execution summary and checklist](M7_STATE.md), [full M7 gate and per-profile qualification](M7_CONTINUATION.md).

Required: reconcile the checklist with the approved gate. Track implementation, host tests, fitting/timing, board qualification, switching coverage and cold-boot recovery separately. Any schedule-driven reduction requires an explicit scope decision, not an undocumented downgrade.

## Work worth retaining

- Shared `CFG_BUILD_ID` propagation through the RTL wrappers.
- Isolated build preparation and source snapshots.
- Strict layout/discovery helpers and negative identity tests.
- All four new B32/C32/D32/D640 bitstream and firmware pairs match their recorded manifest hashes.
- The saved C32 timing report and current post-optimization D640 timing report show timing closure.
- Existing foundation-test logs substantiate their historical results, within their actual coverage and source snapshot.

## Recommended handoff to the implementing agent

Retain those foundations, but repair and mock-test the actual manager before resuming board execution. Integrate the validated admission/layout/preprocessing paths rather than duplicating weaker versions. Reconcile artifact identities and evidence, correct quantitative report claims, and restore the full qualification checklist.

**M7 is not ready for approval yet.** This review does not authorize executing tests, generators, builds or board operations; follow the user's established execution workflow.
