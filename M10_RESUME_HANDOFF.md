# M10_RESUME_HANDOFF.md — resumption brief for the next AI session

> **Target correction — 2026-09-14:** the final product is a five-profile
> CFGLUT5 edge-free library at 125 MHz: A32, B32, C32, D32 and D640. The
> legacy 100 MHz/MAC releases and `B32_CFGLUT100` are historical report
> evidence only. Any common-clock comparison instructions below are
> superseded and must not drive final deployment work. C32 needs a new exact
> 5x5 generated bitheap; the current `conv_channel.vhd` intentionally fails
> elaboration for N other than 3.

**Written 2026-09-14 (end of session). Audience: the next assistant ("Codex"
or equivalent) resuming this project. Read this file top to bottom before
touching anything. It is context-reset safe: every claim below carries its
commit id / hash / file path so you can re-verify first-hand — the standing
rule of this collaboration.**

Collaboration protocol (learned the hard way — obey):
- The user relays all VM/board commands. **One short command block at a
  time**, wait for its output before the next. **Never** put anything after
  a `sudo` line in the same block.
- Vivado runs through the **GUI Tcl console** on the workstation (not
  batch/shell). When you give a Tcl block, expect its pasted output in the
  user's next message — write the block so its output is self-verifying.
- The assistant **runs git itself** (explicitly delegated). The user says
  "GO" to approve plans; "identify/describe" means read-only.
- User style: concise, evidence-first, no fluff.

---

## 1. Where the program stands (one paragraph)

The baseline line is **frozen and released**: tag `v1-m9-release` on
`v1-bringup` (commit `82a4812`), pushed to origin, with the R14 P1 repair
batch committed (`73bb803`) and board-revalidated, the qualified A32 firmware
recovered into the repo (FP-02 closed, `c1107df`), docs truth-passed
(`7fa89d7`), and `RELEASE_MANIFEST_v1-m9-release.md` recording artifact
hashes + known limits. Work then moved to branch
**`integration/m10-cfglut5`** (created from the tag): **M10 Gate 1 is
COMPLETE and pushed through `c2d639d`**, and **Gate 2 (the selective
transplant of the teammate CFGLUT5 datapath) is IN PROGRESS with UNCOMMITTED
changes in the working tree** (details in §4 — commit or verify them first).

## 2. Branch / commit map

| Branch | HEAD | Meaning |
|---|---|---|
| `v1-bringup` | `82a4812` (+ tag `v1-m9-release`) | frozen baseline, pushed |
| `integration/m10-cfglut5` | `c2d639d` (pushed) + uncommitted tree | active research line |

Integration-branch commits (all pushed):
- `8e5e759` M10 Gate 1 decision record (D1–D4 draft)
- `85c077a` D2: orthogonal release identities (catalog v2, switch_to
  enforcement, run records; mocks 17→18 PASS)
- `d6768a4` bitheap provenance byte-identical + D4 testbench staged
- `10e2a3f` D4 closed: R14-01 confirmed by xsim
- `c2d639d` D3+D5: research build flow stood up; WNS discrepancy resolved
- `fce2771` Gate 2 transplant (RTL/BD/testbenches/scripts from 00a6e11)
- `86327de` Gate 2 release plumbing (B32_CFGLUT125 catalog/anchor/manifest)

Authoritative planning docs on this branch: `INTEGRATION_PLAN_M10_M12.md`
(+ Addendum A dispositions), `M10_DECISION_RECORD.md` (D1–D5 decisions and
their status), this file. `AI_HANDOFF.md` §17 remains the baseline-state
narrative but does NOT know about Gate-2 progress (§4 below).

## 3. Verified facts established this session (do not re-litigate)

1. **R14-01 defect is sim-proven on the baseline.** Testbench
   `Convlution_Accelerator.srcs/sim_1/new/tb_conv_channel_shifts.vhd`,
   xsim 2025-09-14: shift 8 sanity OK; shifts 25/26/31 return **−1 vs
   reference 0**. Containment (option b) is in admission:
   `load_params(max_shift=23)` rejects shift ≥ 24. NOTE the deliberate
   deviation from the plan text: the plan said "shift ≤ 8" but **B32 channel
   2 ships shift 9** — the bound is 23 (the provably-defective range is
   24–31), documented in `RELEASE_MANIFEST_v1-m9-release.md`.
2. **The teammate bitheap is generator-exact.** `00a6e11:scripts/
   generate_cfglut_bitheap.py` regenerates `cfglut5_bitheap_3x3.vhd`
   byte-identically (sha256 `ad49b5405d3d0773…`).
3. **EF125 WNS question is closed at the source.** Teammate confirmed
   **+0.178 ns is current** (matches tracked `release/STATUS.md`); +0.201
   was an earlier design iteration. Routed reports remain untracked — their
   physical numbers stay "provisional" until the artifact package arrives,
   but there is no discrepancy anymore.
4. **F5 collapses.** The M7 `profiles/B32/` bundle IS the teammate's K16
   weights already converted to canonical-flat-2 (ch0 bias −1564, shift 8,
   `bias_width 24`); the golden anchor `5821c8b1…` transfers to
   B32_CFGLUT125 because bundle+input+geometry are identical. No new K16
   export needed.
5. **D2 identity schema is live** (commit `85c077a`): catalog
   `profiles/m7_profiles.json` schema_version 2 with a `releases` section
   (shape_id / bundle_sha256 / manifest / build_id_hex / optional
   bundle_dir); `switch_to` enforces release build_id + shape + bundle hash
   before any hardware write; m8 run records carry `release_id`/`shape_id`.
   D32/D640 share one bundle hash (`d735ca24…`) — same model, two
   geometries; that is the orthogonality working, not a bug.
6. Board-recovered artifacts (commit `c1107df`):
   `bitstreams/m7_A32.bin` (sha256 `b59378e4…`, manifest-cross-verified),
   `software/hardware_A32.json` (runtime manifest with width fields),
   `report/evidence/schema_v3_records_20260913/` (six M9 soak records +
   revalidation records + MANIFEST.md documenting remaining gaps).

## 4. Gate 2 transplant state (COMMITTED, verification still pending)

The selective transplant is committed on this branch — taken file-by-file
with `git checkout 00a6e11 -- <paths>` (NEVER merge their commit — it
deletes the root XPR, both bitstream XSAs and the platform XSA; F2):
RTL+BD+testbenches+scripts in `fce2771`, release plumbing
(catalog/anchor/manifest/m7_switch/research_release fix) in `86327de`.

- RTL (now the teammate versions): `cfglut5_kcm.vhd`, `cfglut5_bitheap_3x3.vhd`
  (new), `conv_channel.vhd`, `conv_engine.vhd`, `conv_top.vhd`,
  `conv_axis_wrapper.vhd`, `axi_lite_ctrl.vhd`, `window_generator.vhd`,
  `conv_axis_wrapper_bd.v`, `config_pkg.vhd` (**EF125 identity: profile
  "EF125", K=16, BUILD_ID `45463132354b31364e33573332523031`**).
- BD: `accelerator_dma.bd` (125 MHz).
- Testbenches: `tb_cfglut5_exact/k16_smoke/pipeline.vhd` (new) +
  `tb_conv_axis_wrapper.vhd` (upgraded A-H + edge-bubble metrics).
- Scripts: `generate_cfglut_bitheap.py`, `verify_edge_model.py`,
  `test_edge_bubbles.tcl`, `test_engine_regressions.tcl`.
- Release plumbing (authored by us):
  - `software/hardware_B32_CFGLUT125.json` — manifest mirroring our schema,
    `clock_mhz 125`, **no rx_offset** (IP-07), artifact hashes
    `TBD_FIRST_BUILD` (fail-closed until the first build fills them).
  - `profiles/m7_profiles.json`: `B32_CFGLUT125` in BOTH `profiles` and
    `releases` (release binds `bundle_dir: "B32"`, shape `N3K16W32H32-CVH1`,
    bundle sha `952cb13c…`).
  - `profiles/anchors_m7.json`: `B32_CFGLUT125` anchor = B32's
    `5821c8b1…` (+ note explaining why).
  - `software/m7_switch.py`: `FW_NAME["B32_CFGLUT125"] =
    "m7_B32_CFGLUT125.bin"`; `switch_to` loads params from
    `rel.get("bundle_dir", profile)`.
  - `scripts/research_release/research_release.py`: `check` no longer
    requires the rendered config_pkg to pre-exist.

**Resumption steps (the transplant is committed but NOT yet verified):**
1. `python scripts/research_release/research_release.py check
   B32_CFGLUT125` (venv) — should print SPEC OK + source hashes.
2. Re-run both mock suites (they exercise the changed m7_switch):
   `.venv/Scripts/python.exe verification/m8_cli/mock_cli_test.py` (18 cases)
   and `verification/m7_profiles/mock_switch_test.py --profile B32 3` +
   `--matrix-seq`. NOTE: the m8 suite's mock stage lives at
   `C:/Users/moham/AppData/Local/Temp/m7_bundle2/profiles` — if Temp was
   purged, regenerate per that harness's fixture logic before concluding
   anything.
3. Commit the transplant (suggested message: "Gate 2: selective transplant
   of the EF125 CFGLUT5 datapath from 00a6e11 (RTL/BD/testbenches/scripts,
   file-by-file) + B32_CFGLUT125 release plumbing; mocks PASS").

## 5. Remaining execution order (masterplan style)

### Gate 2 — prove the transplanted datapath (host + workstation)
- [x] G2.1 Verify + commit the working tree (§4 steps above).
- [x] G2.2 **Controller audit (F4)**: diff `axi_lite_ctrl.vhd`
      v1-m9-release..working tree end-to-end; confirm CVH1 conformance
      (STATUS bits, counters, quotas, admission, ERROR_FLAGS) and map our
      software admission (write+readback+PARAM_COMPLETE) onto the new
      `cfg_pending`/`cfg_ready` flow. Add the IP-08 directed cases:
      START-vs-config races, writes during cfg_pending, RESET/ABORT with a
      prefetched window, readback≠installed-state before cfg_ready.
- [x] G2.3 **RTL regressions in Vivado GUI Tcl console** (user runs, output
      comes back next message): compile tb_cfglut5_exact /
      tb_cfglut5_k16_smoke / tb_cfglut5_pipeline / tb_conv_axis_wrapper
      (A–H + edge-bubble metrics at 8000 ps). Note the live project's BD is
      now the 125 MHz one — sims are behavioral, unaffected.
- [x] G2.4 **Numerical gauntlet (IP-10)**: the transplanted conv_channel
      S4/S5 sign-extension fix must be exercised beyond their zero-heavy
      suite — nonzero ±accumulations, extrema, rounding boundaries,
      signed-24 bias endpoints, both ReLU states, ALL 32 shifts vs the
      exact reference. Extend `tb_conv_channel_shifts.vhd` (it already
      demonstrates the harness pattern; on the new datapath all cases
      including shifts 24–31 must PASS — that is the R14-01 fix riding M11).
- [x] G2.5 **First research build** (Vivado 2025.2 isolated batch build):
      host `python scripts/research_release/research_release.py prepare
      B32_CFGLUT125`, then in the Tcl console
      `cd D:/MyProjects/Convlution_Accelerator; set research_release_id
      B32_CFGLUT125; source scripts/research_release/research_build.tcl`,
      then host `... research_release.py manifest B32_CFGLUT125`.
      Expect WNS/WHS ≥ 0 at 8 ns (their +0.178 is the reference, ±route
      variance; the gate is sign, not the exact value).
      Actual: WNS +0.157 ns, WHS +0.019 ns, timing met, DRC/route clean.
- [x] G2.6 Fill the TBD hashes in `hardware_B32_CFGLUT125.json` from
      `work/research_B32_CFGLUT125/artifacts/build_manifest.json`; copy
      bit/xsa to `bitstreams/b32_cfglut125_125mhz.*`; produce the
      FPGA-manager firmware with
      `bootgen -image <bif> -arch zynq -process_bitstream bin`
      (BIF = plain .bit path, no destination_device attr) and record its
      sha256 as `firmware_bin_sha256`.
- [x] G2.7 Board push of the new firmware + updated
      `hardware_B32_CFGLUT125.json`, profiles, and runtime. Actual transfer
      used the SD FAT boot partition; 41 home files matched byte-for-byte and
      firmware SHA-256 was `4e827310...b5b73b`.

### Gate 3 — board qualification at 125 MHz (needs VM + board)
- [x] G3.1 VM: import the XSA into the PetaLinux project, rebuild
      FSBL/BOOT.BIN with the 125 MHz bitstream (QUICKSTART procedure),
      flash SD. Actual WIC SHA-256 `c99781f6e30a651c1fe878e9806f9e6b78a605eb46f0d6315516c0af6265e5f4`;
      live BUILD_ID `EF125K16N3W32R01`.
- [x] G3.2 Board: **measured** FCLK0 = 125 MHz (live SLCR derivation:
      IO PLL FBDIV=30, DIVISOR0=4, DIVISOR1=2; evidence in
      `report/research_builds/B32_CFGLUT125/board_boot_identity_20260914.md`).
- [ ] G3.3 Full gate via `m7_switch`/`m8_cli` on the new release:
      identity validation → anchor-exact activation (`5821c8b1…`) →
      ≥100-frame soak → extremes (shift 24–31 now live and must PASS) →
      repeated reconfigurations vs the MAC baseline → power cycle →
      fault/recovery. Then catalog the release BUILT→QUALIFIED. Identity,
      runtime admission, parameter-only activation, and the first three run
      frames PASS. The 12-frame numerical extremes suite also passes,
      including live shifts 24–31 and canonical-parameter restoration.
      The 100-frame anchor-exact soak passes (median 0.125 ms, p95 0.128 ms,
      all frames bit-exact). Repeated baseline/research switching,
      power-cycle, and fault/recovery remain open. The A32 runtime inventory
      has been restored and hash-verified, but A32 was not loaded under the
      live 125 MHz FCLK: the switcher changes PL only, and the routed A32
      artifact is a 100 MHz release. Cross-release switching is therefore
      deferred to the common-clock A32_MAC100/B32_CFGLUT100 boot. Evidence:
      `report/research_builds/B32_CFGLUT125/board_runtime_qualification_20260914.md`.
- [ ] G3.4 Edge-free claim discipline (IP-09): simulation metrics + board
      throughput stay separate claims; K16 = 4 beats/position on 64-bit
      AXIS — no "one position/cycle at the interface" language.

### Gate 4 / M12 — matched comparison + dual release
- [x] G4.1 Build `B32_CFGLUT100` from the same tree/directives (only the
      controlled clock and build identity differ; provenance-controlled per
      IP-11). Routed build PASS at 100 MHz: WNS `+0.764 ns`, WHS
      `+0.011 ns`, DRC/route clean. This is now the candidate for safe
      common-clock A32/research switching; board validation remains pending.
- [ ] G4.2 Matched measurement: B32_MAC100 vs CFGLUT100 vs CFGLUT125,
      identical bundle (the shared B32 bundle), input, preprocessing,
      software path, method. Unit discipline (results vs positions vs
      beats vs frames/s) in every table; vectorless power labeled.
- [ ] G4.3 Report section + dual release (baseline tag exists; research
      tag after Gate 3), AI_HANDOFF final state.

### Standing backlog (post-Gate-2, pre-"masterpiece")
- [ ] R14-06..10 P2 batch (imported-model selection, context freezing,
      importer idempotency, storage ledger, converter overwrite guard).
- [ ] FP-03: versioned PetaLinux recipe recreating the CURRENT runtime.
- [ ] FP-02 remainder: archive B32/C32/D32/D640 firmware binaries beyond
      gitignored disk (checksum-addressed store).
- [ ] Board pull of the five E2 `extremes-*` record dirs (still on SD p2 /
      board rootfs; see schema_v3_records MANIFEST.md gaps).
- [ ] CLEANUP_SCAN re-run before any deletion; Temp legacy bundles →
      profiles/history first.
- [ ] Stale artifacts: `Architecture_Mapping.html`, `verify_by_hand.ipynb`,
      K16-era previews; teammate merge decision formally closed via
      MERGE_DECISION_CHECKLIST.md (M12 does this implicitly — record it).

## 6. Gotchas specific to this state

- The **live Vivado project** (`Convlution_Accelerator.xpr`) still has the
  D640-era compile state; the transplanted sources changed underneath it.
  Behavioral sims after `update_compile_order` are fine; do NOT launch
  implementation in the live project — research builds go through
  `scripts/research_release/` (fresh project) only.
- `m7_switch.py` now requires catalog `releases` for every profile — the
  board's `/home/petalinux/profiles/m7_profiles.json` is the OLD schema v1
  until the next push. Any board run of transplanted software requires the
  updated catalog pushed alongside (they travel together).
- Repo manifest naming is inconsistent by history: `hardware_B.json` (repo)
  vs `hardware_B32.json` (board/stage). `bundle_dir` + release
  `manifest` fields carry the mapping; do not "fix" the filenames without
  re-touching every stage.
- The m8 mock harness depends on the Temp-stage fixtures and real
  bitstreams/*.bit.bin files; on a cleaned machine regenerate the stage
  before trusting suite failures.
- `feedback.md` on v1-bringup had uncommitted +405-line review sections —
  those were committed as part of the doc-truth era; if you see feedback.md
  dirty again it's a NEW review layer: read it before acting.

## 7. Definition of done (unchanged)

A stranger with a clean clone, the vault, and the artifact store can
reproduce every claim — every bitstream, frame, and number — without
finding a document that contradicts the evidence, a hash that doesn't
verify, or a claim that outruns its proof.
