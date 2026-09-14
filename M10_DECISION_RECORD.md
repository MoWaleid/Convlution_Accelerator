# M10 decision record — integration groundwork (Gate 1)

Status: DRAFT for user sign-off (Gate 1 requires a signed decision record).
Branch: `integration/m10-cfglut5` (created from `v1-m9-release` = 82a4812 —
the local tagged HEAD, per the corrected execution order; never from stale
`origin/v1-bringup`).
Inputs: INTEGRATION_PLAN_M10_M12.md + Addendum A (verified dispositions),
HANDOFF_v1bringup_to_edgefree125.md (independently verified), R14/FP/IP
review series.

## D1 — Physical board: ZedBoard (IP-04 gate)

**Decision: ZedBoard `xc7z020clg484-1`.**

Rationale: every qualified artifact and constraint targets it —
`Zedboard-Master.xdc`, the ZedBoard PS7 preset, all 1,966 board frames of
evidence, the recovered firmware/manifest chain, and the PetaLinux runtime.
The teammate EF125 package is likewise ZedBoard-targeted (`xc7z020clg484-1`,
Zedboard XDC, `platform: zedboard_linux`). No competition requirement for
PYNQ-Z2 has been identified for our entry.

Consequence: if a PYNQ-Z2 requirement appears later, it forces a constraint +
PS-configuration port and full re-qualification; nothing in the Gate-1
identity or build-flow work below is wasted by that (only the platform layer
changes). Revisit explicitly before any FSBL work.

## D2 — Orthogonal runtime identities (FP-05)

**Problem:** the current catalog maps one identity (`A32`…`D640`) to one
firmware manifest AND one parameter directory. A controlled comparison needs
`B32_MAC100` vs `B32_CFGLUT100` vs `B32_CFGLUT125` on the same N3/K16 weights,
which that schema cannot express.

**Decision: three orthogonal identifiers.**

1. **Shape/ABI compatibility ID** — geometry + ABI + numerical contract:
   `N3K16W32H32-CVH1` style. Declared by both hardware releases and model
   bundles; a release and a bundle are compatible only on exact shape-ID
   match (plus the existing WIDTHS/geometry register checks).
2. **Hardware-release ID** — one compiled implementation: `B32_MAC100`,
   `B32_CFGLUT125`, … Maps to: firmware image + hardware manifest (which
   keeps `build_id_hex` as the in-silicon identity) + shape ID.
3. **Model-bundle ID** — one parameter bundle, hardware-independent:
   content-addressed (whole-bundle SHA-256, already computed by
   `load_params`) plus a human tag. Shape ID declared by the bundle's
   catalog entry.

**Schema mechanics (deliberately non-invasive):**

- The canonical-flat-2 bundle grammar stays EXACTLY as is — strict admission
  (`obj()` exact field sets) is not loosened and the bundles are not
  re-frozen. Identity lives one level up.
- `profiles/m7_profiles.json` gains a `releases` section alongside the
  existing profiles: each release entry = {release_id, shape_id,
  firmware_file, manifest_file, bundle_dir, bundle_sha256_expected}.
- `switch_to` resolves release → manifest → bundle, cross-validates
  shape IDs, and admits the bundle (unchanged strict path).
- Run record (schema v3) gains `release_id` and `shape_id` alongside the
  already-bound `bundle_sha256` / catalog / anchor hashes.

**Comparison-facing consequence (M12):** `B32_MAC100` and `B32_CFGLUT125`
are two releases sharing one shape ID and one bundle — the honest controlled
comparison falls out of the schema instead of being hand-assembled.

## D3 — Authoritative research build flow (FP-04)

**Decision: adapt the teammate's fresh-project release builder** to our
profile discipline; the baseline flow stays for reproduction only.

- The existing `scripts/prepare_profile.py` + `scripts/build_profile.tcl`
  remain the *baseline* reproduction path (they clone the root XPR; they do
  not know CFGLUT sources — by design, that is FP-04's trap).
- The research flow is a new `scripts/research_release/` pair (Tcl + driver)
  modeled on the teammate's `release.ps1`/`release_build.tcl` pattern: fresh
  project per build, explicit source list including
  `cfglut5_kcm.vhd` + `cfglut5_bitheap_3x3.vhd` + generated siblings, fail-
  closed timing/DRC/route gates, build-input manifest (BD/XDC/generator/IP
  config/tool settings per IP-08) written next to the artifacts.
- `scripts/create_accelerator_dma_bd.tcl` is formally retired as
  non-authoritative for research builds (IP-05) — the release imports the
  committed 125 MHz `.bd`; a reconciliation task may regenerate it later.

## D4 — F1/R14-01 status

Containment decision D4 was taken (option b) and shipped in 73bb803:
admission rejects shift ≥ 24; defective range 24–31 documented in
RELEASE_MANIFEST_v1-m9-release.md. **Open item:** the plan requires the
diagnosis confirmed by simulation on OUR conv_channel (shift-25 zero-input
counterexample → −1 vs reference 0). Static verification is done; the xsim
run is scheduled as the first item on this branch's testbench work, before
any transplant.

## D5 — EF125 WNS provenance resolved (2026-09-14)

The teammate confirmed: **+0.178 ns is the current EF125 WNS** (matching the
tracked `release/STATUS.md`); the +0.201 ns in the handoff table belonged to
an earlier design iteration and is not relevant. All EF125 physical numbers
are normalized to WNS +0.178 / WHS +0.019. They remain **provisional until
the teammate's artifact/report package arrives** (no tracked routed reports
exist), but the discrepancy itself is closed. IP-02's remaining action is
artifact acquisition only.

## Gate-1 remainder (after sign-off)

1. **DONE 2026-09-14 (85c077a):** D2 implemented — catalog v2 `releases`
   section (content-bound bundle hashes; note D32/D640 intentionally share
   one bundle hash: same model, two geometries), `resolve_release` +
   `switch_to` enforcement (build_id, shape, bundle sha), run records carry
   `release_id`/`shape_id`, mock suites 17→18 cases all PASS.
2. **Bitheap provenance DONE 2026-09-14:** the committed
   `cfglut5_bitheap_3x3.vhd` on `00a6e11` regenerates **byte-identically**
   from `scripts/generate_cfglut_bitheap.py` (sha256 `ad49b540…`).
   **Research build flow STOOD UP 2026-09-14:** `scripts/research_release/`
   (fresh-project Tcl with fail-closed gates + host driver with catalog
   cross-check, rendered config_pkg, IP-08 build manifest; README with batch
   and GUI-Tcl-console usage). The `B32_CFGLUT125` spec is committed and
   fails closed until the Gate-2 transplant provides its sources; first
   full exercise happens at Gate 2.
3. **F1 xsim confirmation DONE 2026-09-14:** `tb_conv_channel_shifts` ran on
   the baseline (Vivado 2025.2 xsim): case 0 (shift 8) OK; cases 1-3
   (shift 25 zero-acc, shift 26/31 acc −1) each returned **−1 vs reference
   0**. Verdict line: `TB_R14_01_SIM: DEFECT CONFIRMED BY SIMULATION - 3 of
   4 large-shift cases`. R14-01 is sim-proven on our baseline; the M9
   known-limit statement is simulation-backed.
4. **WNS provenance RESOLVED 2026-09-14 (D5):** teammate confirmed +0.178
   as the current EF125 number; +0.201 was an earlier design. Artifact
   package request remains open for full provenance.
