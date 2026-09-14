# research_release — authoritative research-line build flow (M10 D3)

Fresh-project Vivado build adapted from the teammate release flow, with our
identity discipline. One build = one release = one checked spec.

## Components

- `research_build.tcl` — the Vivado flow: fresh project (`xc7z020clg484-1`),
  explicit source list from the spec, committed 125 MHz block design with
  parameter assertions (PS clock, DMA config, no System ILA), fail-closed
  gates (WNS/WHS ≥ 0, timing met, check_timing clean, DRC 0 errors, routing
  clean, exactly one clock at the spec frequency), routed checkpoint +
  bitstream + XSA + reports under `work/research_<ID>/artifacts/`.
- `research_release.py` — host driver: spec cross-check against
  `profiles/m7_profiles.json` `releases` (shape_id + build_id_hex), rendered
  `config_pkg.vhd` (repo template never mutated), Vivado batch invocation,
  and the IP-08 build-input manifest (`build_manifest.json`: tool version,
  git commit, every source + artifact sha256, results, BOARD_VALIDATION).
- `builds/<ID>.spec.tcl` — one checked spec per release: release_id,
  shape_id, n/k/w/h, build_id_hex, clock_mhz, profile string, sources list.
  Specs are added when a release's sources exist (Gate 2 adds
  `B32_CFGLUT125` after the transplant).

## Usage

Batch (one command):

```sh
python scripts/research_release/research_release.py build B32_CFGLUT125
```

Vivado GUI Tcl console (the workstation's usual workflow):

```tcl
cd D:/MyProjects/Convlution_Accelerator
# on the host shell first: python scripts/research_release/research_release.py prepare B32_CFGLUT125
set research_release_id B32_CFGLUT125
source scripts/research_release/research_build.tcl
```

then on the host shell: `python scripts/research_release/research_release.py manifest B32_CFGLUT125`.

## Gates (all fail-closed, reports preserved on failure)

timing (WNS/WHS + "all constraints met"), check_timing, DRC errors, routing
errors, exactly one physical clock at the spec frequency, BD PS/DMA/ILA
parameter assertions, output directory must not pre-exist.

## Notes

- `create_accelerator_dma_bd.tcl` is retired as non-authoritative for
  research builds (IP-05): the flow imports the committed `.bd` and asserts
  its parameters.
- A release is "built", never "qualified", until it passes the board gates
  (Gate 3): identity validation, anchor-exact activation, ≥100-frame soak,
  measured clock.
- The baseline reproduction flow (`scripts/prepare_profile.py` +
  `scripts/build_profile.tcl`) is unchanged and remains authoritative for
  `v1-m9-release`-class builds.
