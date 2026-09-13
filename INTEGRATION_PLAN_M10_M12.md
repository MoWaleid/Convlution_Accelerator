# Integration plan — M10/M11/M12: v1-bringup ← feature/k16-cfglut5-edgefree-125mhz

Source: teammate handoff `HANDOFF_v1bringup_to_edgefree125.md` (2026-09-13,
comparison fb66066..00a6e11) + independent branch inspection
(AI_HANDOFF/config_pkg/hardware.json/STATUS/QUICKSTART read first-hand).
Date: 2026-09-14. Status: PLAN — execution gates below; nothing merged yet.

## 0. What the branch is (absorbed)

Sibling lineage (research developed on `feature/k16-cfglut5-exact` @ b831072,
not an ancestor). One squashed release commit, EF125K16N3W32R01. Scope:
complete datapath replacement, system integration and software contract
preserved (frontend/serializer/regfile/sync_fifo/XDC byte-identical; M4
lifecycle contract preserved in the restructured controller).

1. **CFGLUT5 KCM + Dadda bitheap** (the "Wallace/Dadda trees"): exact
   constant-coefficient multiplication in runtime-configurable LUTs — two
   CFGLUT5 per output pair, weight byte -> 32-bit truth table, fused signed
   Dadda tree per channel over nine radix-16 partial products, structural
   LUT6_2, 0 DSP. Runtime serial config load: 4,608 clocks per full 16x9
   reload, guarded by cfg_pending/cfg_ready (START/new writes wait until the
   last truth bit reaches the LUTs).
2. **Five-stage pipeline** (S1 lookup+Dadda 1-3, S2 levels 4-6, S3
   carry-propagate+bias, S4 shift+discarded-half-bit, S5 round+sat+ReLU):
   latency 4->6 clocks, II=1, split for 8 ns closure.
3. **Edge-free windowing**: C_WINDOW_PREFETCH elastic slot
   (window_ce = run and (ce or not window_valid)), pixel_ready edge prefetch,
   four engine-local registered window banks (dont_touch) — eliminates edge
   bubbles => the judges' bonus requirement (exactly one output position per
   clock once filled, no stall cycles) with an acceptance checker built into
   the upgraded wrapper testbench (A-H phases + edge-bubble metrics).
4. **125 MHz**: native PS FCLK125 (validated 125.000), WNS +0.201 /
   WHS +0.019, Fmax ~128.2, 0/48,664 failing, 0 route/DRC errors. System
   13,072 LUT / 13,050 FF; wrapper 8,241/6,440; engine 6,185/3,911;
   0 DSP/BRAM; 1.804 W. Failed experiment documented (broad MAX_FANOUT made
   it worse: -0.574/855 endpoints — reverted; engine banks are the standing
   solution).
5. **Controller**: M4 lifecycle preserved (IDLE/CONFIG/RUN/FAULT, discovery,
   quotas, fault accounting, abort, reset) + three 8 ns additions (AW/W
   capture after registered decode, one-cycle completion-check stage,
   CFG_BUILD_ID propagation).
6. Verification on branch: wrapper A-H PASS (baseline/optimized/stress) at
   8,000 ps incl. negative control and edge-bubble metrics; engine suites
   (exactness+reload, K16 smoke, pipeline 32 shifts x 16 biases x 2 ReLU =
   5,120 outputs); 1,007 Python reference tests; release.ps1
   Build/Package/Check PASS; PACKAGE_HOST_PASS (16,384 int16). **Board:
   NOT_RUN.**
7. FOM nuance: their "4 px/cycle sustained" counts channel RESULTS through
   the serializer (K16: 4 cycles per output position); "16 px/cycle peak" is
   the core. Announcement-units FOM is frequency-independent (-1.5% system at
   125 MHz); per-second basis +23.1% (400->500 M results/s). Definitions must
   be normalized in any comparison (review M8-08 discipline).

## 1. Findings that affect OUR line

- **F1 (correctness, our baseline): latent shift 26-31 bug.** The handoff
  states the old (v1-bringup) conv_channel S4 "silently produced a wrong
  result for shifts 26-31 (out-of-range read, 'U' semantics, no round-up)";
  their branch adds the sign-extension guard and verifies all 32 shifts.
  Our shipped profiles use shift <= 8, so no board evidence is invalidated,
  but the M1 numerical contract requires shifts 0..31. Decision D4 required
  (back-port to baseline before the M9 tag, or document as frozen-baseline
  known limit fixed in the research line). Must be confirmed by simulation
  on our conv_channel first (never trust a handoff claim unverified).
- **F2 (evidence preservation):** their commit deletes platform/
  accelerator_dma.xsa, bitstreams/*.xsa, root .xpr, M7_B32.srcs project
  (61 files) — all recoverable from v1-bringup, but the integrated line must
  restore them (M0/M2-P evidence references) or formally re-bind references.
- **F3 (profile matrix):** the CFGLUT5 bitheap is generated for 3x3 @ K16.
  C32 is N=5 (5x5 kernel) and A32/D32/D640 are K8/K4 — the new engine as
  shipped serves only the B32-shaped geometry. Multi-profile survival
  requires either a K/N-generalized generator or dual-engine coexistence.
  Core M10 audit question.
- **F4 (admission semantics):** coefficient writes now trigger a runtime LUT
  configuration load; the controller guards START during cfg_pending. Our
  software admission (write+readback+PARAM_COMPLETE) must be audited against
  the new controller flow — likely zero software change if the controller
  rejects/parks START per the ABI, but must be proven in M10.
- **F5 (K16 golden anchors):** no K16 golden-model export exists on the
  board path (their open item) — board verification of EF125 frames needs
  K16 canonical anchors first (golden_model export for the B32-trained
  parameters).

## 2. Settled decisions (user directive 2026-09-14)

- Our M8/M9 software line is kept in full; the branch contributes the three
  RTL upgrades: 125 MHz clock compatibility, Dadda-tree datapath
  (CFGLUT5 bitheap), edge-bubble elimination.
- Integration target is our mainline (v1-bringup), not branch adoption.
- Their host-only "qualified" status is not accepted as qualification; the
  integrated result is re-qualified on board under our gates.

## 3. Milestone M10 — audit & integration groundwork

Gate: signed decision record + audit evidence, no merge yet.

- [ ] M9 finish (precondition): clean-build reproduction + v1-m9-release tag
      on v1-bringup (baseline freeze BEFORE research adoption; §9.8).
- [ ] F1 confirmation: simulate our conv_channel for shifts 26-31; document
      the result; decide D4 (back-port fix + re-qualify, or frozen-baseline
      known limit + fix rides M11).
- [ ] Controller audit: diff axi_lite_ctrl v1-bringup..branch end-to-end;
      verify CVH1 conformance (STATUS bits, counters, quotas, admission,
      cfg_pending behavior, ERROR_FLAGS semantics unchanged); map our
      software admission onto the new flow (F4).
- [ ] Generated-code provenance: run scripts/generate_cfglut_bitheap.py,
      byte-compare against the committed cfglut5_bitheap_3x3.vhd; review the
      generator's exactness argument (radix-16 partial products, Dadda
      levels) against the numerical contract.
- [ ] Edge model review: verify_edge_model.py + test_edge_bubbles.tcl
      acceptance criteria mapped to the judges' bonus wording (one position
      per clock once filled, zero stall cycles, including edge rows).
- [ ] F3 assessment: parameterize the generator for K8/K4/N5 feasibility, or
      scope dual-engine coexistence; decide the post-adoption profile matrix
      (which of A32/B32/C32/D32/D640 survive, which are re-frozen as-is).
- [ ] Restore/deletion disposition (F2): platform xsa, bitstreams xsas, root
      project on the integrated line.
- [ ] Integration decision record: profile matrix, clock plan (125 MHz FSBL
      rebuild in VM), software delta list, timeline.

## 4. Milestone M11 — datapath upgrade integration & board qualification

Gate: full board evidence green on the integrated line.

- [ ] Merge their RTL deltas onto our mainline (m7_switch/m8_cli stack kept;
      restore F2 artifacts; EF125 identity per their constants).
- [ ] Software adaptation: EF125 manifest (hardware_EF125.json, done by them
      — re-validate against our schema), canonical bundle conversion for the
      B32-trained K16 parameters, cfg_pending-aware admission (per M10 audit).
- [ ] K16 golden anchors: golden-model export for the EF125 parameters
      (their open item) -> canonical anchors -> board verification data.
- [ ] VM: 125 MHz deployment — import edgefree.xsa into the PetaLinux
      project, rebuild FSBL/boot with edgefree.bit, boot-time clock
      confirmation (their QUICKSTART procedure).
- [ ] Board gate: activation anchor-exact, >=100-frame soak, extremes (with
      the shift-26-31 fix now live), worker/importer compatibility,
      edge-bubble metrics captured on real frames (judge-bonus evidence),
      measured PS clock = 125 MHz.

## 5. Milestone M12 — matched comparison, report, dual release

Gate: comparison published, tags, report submitted.

- [ ] Matched measurement: EF125 K16 CFGLUT5 @ 125 MHz vs B32 K16 MAC @
      100 MHz (same geometry — the honest research comparison), plus the
      sibling 100 MHz CFGLUT5 branch data (12,966 LUT / WNS +0.061) for a
      pure-frequency axis. Normalize results-vs-positions definitions
      (M8-08 discipline) in every table.
- [ ] Judge-bonus section: edge-bubble elimination evidence (sim metrics +
      board frames), throughput claim now sustainable at one position per
      clock including edges — update report S3/S9/S11 accordingly.
- [ ] FOM: both bases stated (announcement px/cycle units are
      frequency-independent; per-second +23.1%) — pick and justify one.
- [ ] Release: v1-m9-release (baseline) + research tag; AI_HANDOFF final
      state; cleanup scan re-run (CLEANUP_SCAN_20260914.md).
