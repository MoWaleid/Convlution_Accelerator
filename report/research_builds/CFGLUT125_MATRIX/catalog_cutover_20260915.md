# Active catalog cutover to the five CFGLUT125 releases — 2026-09-15 (§19.7 step 3)

The active catalog, runtime admission names, and host test/mock suites now
recognize exactly the five locked releases. Legacy MAC-era entries (A32, B32,
C32, D32, D640) and B32_CFGLUT100 are no longer admissible names anywhere in
the active path; they remain historical report evidence (git history,
`bitstreams/history/`, `report/research_builds/`, `profiles/history/`).

## What changed

- `profiles/m7_profiles.json`: profiles+releases cut from the eleven-entry
  staging catalog to the five `*_CFGLUT125` entries (final BUILD_IDs per the
  §18.5/§19.2 table). Bundle dirs remain the canonical A32/B32/C32/D32/D640
  directories.
- `software/conv_lab/profiles.py`: the strict loader requires exactly the
  five-release active set (was: eleven-release staging set, GLM-F1).
  `bundle_dir` validation now requires a simple safe directory name instead
  of naming a profile (bundle dirs and release names are orthogonal since the
  cutover; bundle content stays hash-bound at admission via
  `bundle_sha256`).
- `software/m7_switch.py`: `FW_NAME` maps the five releases to the canonical
  generated firmware (`{a32,b32,c32,d32,d640}_cfglut125_125mhz.bit.bin`);
  `ORDER` is the five releases; `build_matrix_sequence` derives its A32/B32
  bridge anchors from `ORDER` instead of hardcoded legacy names (same E2
  termination guarantee: 20 provably consecutive cycles, all 20 ordered
  pairs).
- `software/m8_cli.py`: `D_PROFILES` (Sobel preview profiles) is
  `("D32_CFGLUT125", "D640_CFGLUT125")`; usage docstring updated.
- `software/tests/test_m7_profiles.py`: CASES/BUNDLE_ALIASES are the five
  active releases; the five frozen legacy identities move to `LEGACY_CASES`
  used only by the historical generator test (locally constructed, no
  catalog membership); all tests reference release names.
- `verification/m7_profiles/mock_switch_test.py`: stage sync copies the
  authoritative five-release catalog, admitted manifests, anchors and bundle
  dirs from the repo; FW mapping uses the canonical firmware files; matrix
  and same-build paths use release names; `run()` resolves bundle dirs via
  `release_bundle_dir` like the real manager.
- `verification/m8_cli/mock_cli_test.py`: the old A32-mock firmware fixture
  is deleted (all five canonical `.bit.bin` files now exist in the repo with
  hashes matching the admitted manifests); all release names updated;
  `set_current` resolves bundle dirs via `release_bundle_dir`; bundle-dir
  references (e.g. `STAGE_COPY/"A32"`) deliberately keep legacy short names.

## Verification (all on the cut-over tree)

- `software/tests/test_m7_profiles.py`: 12/12 OK.
- `verification/m7_profiles/mock_switch_test.py`:
  `--candidate-undeployable profile|soak` PASS (GLM-F7 fail-closed gate,
  zero register/DMA mutation, no firmware call);
  `--profile B32_CFGLUT125 3` PASS run twice (reload + same-build
  parameter-only path, final STATUS `0x00000181`);
  `--matrix-seq` PASS (all 20 ordered pairs from all five starts);
  `--d640-input-hash` PASS (canonical input hash matches anchors).
- `verification/m8_cli/mock_cli_test.py`: full suite PASS (same-build anchor
  run, B32_CFGLUT125 reload run, exact-reference image run, UNVERIFIED
  semantics, archive collisions, benchmark, 12-stimulus extremes, soaks,
  admission ordering, cleanup/persistence failure semantics, bias-width and
  R14-01 containment, release identity binding, failure records, list/
  record round-trip).
- `verification/m8_import` suite: 15/15 OK.
- `scripts/research_release/research_release.py check` x5: SPEC OK with
  correct catalog bindings (existing work/ build dirs produce expected
  archive-before-rebuild warnings only).
- `scripts/research_release/test_spec_crosscheck.py`: 7 cases OK, A32 render
  unchanged (`7434e327…`).
- Static parse of all touched Python files: OK.

## Deliberately unchanged

- `software/hardware.json` and the legacy `hardware_{B,C,D,D640}.json`:
  historical manifests, now unreferenced by the active catalog (the loader
  resolves only the five `_CFGLUT125` manifests). The A32-original byte
  equality test still guards them.
- `profiles/history/`, `bitstreams/history/`, `report/research_builds/`
  historical evidence, and the anchors file (keys for both eras; only the
  five active keys are reachable through the cut catalog).
- Board-side runtime staging is §19.7 step 4 (user relay) and is not part of
  this commit.
