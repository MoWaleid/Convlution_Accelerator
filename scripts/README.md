# Scripts

Host-side tooling for building, verifying and packaging the accelerator. Run
Python scripts from the repository root with `python -B`; run Tcl scripts in
Vivado 2025.2.

## Release flow

[`research_release/`](research_release/README.md) is the only supported way to
build a hardware release. `research_build.tcl` and the specs in `builds/` are
hashed into every build manifest and still match it, so they are frozen
alongside the RTL.

| Script | Purpose |
|---|---|
| `research_release/create_profile.py` | Create an unqualified development profile and its Tcl spec |
| `research_release/research_release.py` | `check`, `prepare`, `manifest`, `publish` and `clean` a release |
| `research_release/research_build.tcl` | Isolated Vivado build with timing, DRC and route gates |
| `research_release/admit_built_manifests.py` | Bind the canonical bitstream hashes into the runtime manifests |
| `research_release/test_spec_crosscheck.py` | Negative identity tests for release specs (host only) |
| `research_release/test_cfglut_geometries.tcl` | Exact-datapath regression for the N=3 and N=5 bit heaps |
| `research_release/test_profile_wrappers.tcl` | A–H streaming wrapper regression per release |
| `research_release/run_official_wrapper.tcl` | Batch entry point for the wrapper regression |
| `research_release/preserve_wrapper_evidence.py` | Copy a wrapper run into a checksummed evidence directory |
| `research_release/debug_wrapper_sim.tcl` | Debug and bisect variant of the wrapper regression |

## Generators and design sources

| Script | Purpose |
|---|---|
| `generate_cfglut_bitheap.py` | Generate `cfglut5_bitheap_3x3.vhd` and `cfglut5_bitheap_5x5.vhd` |
| `create_accelerator_dma_bd.tcl` | Recreate the Zynq + AXI DMA block design |
| `zedboard_ps_platform.tcl` | ZedBoard processing-system preset used by the block design |

## Packaging and demo library

| Script | Purpose |
|---|---|
| `packaging/fom_table.py` | Regenerate the Figure-of-Merit table from the routed reports |
| `packaging/build_deck.js` | Build the presentation deck |
| `packaging/refresh_submission.py` | Re-sync the report and golden-model files in `submission/`, rewrite its checksum manifest and rebuild `final_upload/` |
| `library/build_cifar10_demo.py` | Build the 50-image CIFAR-10 library and its D640 output hashes |

## Historical

Kept as a record of how earlier artifacts were produced. Neither is part of the
current release flow.

| Script | What it was for |
|---|---|
| `test_edge_bubbles.tcl` | The original K=16, N=3 wrapper regression; `research_release/test_profile_wrappers.tcl` generalizes it to all five releases |
| `maintenance/cleanup_legacy.ps1` | Dry-run-first cleanup helper used for the 2026-09-20 archive |

The milestone-era generators and one-off packaging scripts (`build_profile.tcl`,
`prepare_profile.py`, `convert_legacy_profiles.py`, `test_engine_regressions.tcl`,
`verify_edge_model.py`, `package_decoder_api_v2.ps1`) were removed after the
submission. They remain in git history, and `recovery/legacy_history_20260920.tar.gz`
holds the earlier checkpoints.
