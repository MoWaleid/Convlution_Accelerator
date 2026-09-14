# A32_CFGLUT125 routed build — 2026-09-15

Status: **BUILT; BOARD_VALIDATION=NOT_RUN.**

The user executed `scripts/research_release/research_build.tcl` with Vivado
2025.2 from clean commit `45b35a6970975552050db9cf3eabd292df3fa3a6`.
The deterministic rendered configuration was verified before the build.

## Identity and implementation result

- Release: `A32_CFGLUT125`
- Shape: `N3K8W32H32-CVH1`
- Build ID: `EF125K08N3W32R01`
- Target: Zynq-7000 `xc7z020clg484-1`
- PL clock: 125 MHz (8.000 ns)
- WNS: +0.197 ns
- WHS: +0.037 ns
- Setup/hold failing endpoints: 0 / 0
- Routing errors: 0
- Methodology checks: 0
- DRC errors: 0; one routable-loads warning and four BRAM advisories are
  preserved verbatim in `drc.rpt`.
- PS7 PSU-1..4 negative-DQS-skew critical warnings during generation are the
  known ZedBoard-preset artifact; the four `PCW_UIPARAM_DDR_DQS_TO_CLK_DELAY_*`
  values are byte-identical to the accepted C32/D640 builds and the
  board-qualified B32 CFGLUT125 build.

Top-level hierarchical utilization: 9,145 total LUTs, 9,758 FFs, two
RAMB36, two RAMB18 and zero DSP blocks. The accelerator wrapper hierarchy
uses 4,746 total LUTs and 3,512 FFs; the eight-channel N=3 convolution engine
uses 3,165 total LUTs and 1,968 FFs.

## Preserved artifacts

- Bitstream: `bitstreams/a32_cfglut125_125mhz.bit`
  - SHA-256: `0ddd0a4694dcf7f8f9e91d9444f420415540df96db40fc166cfe950a15cdc759`
- XSA: `bitstreams/a32_cfglut125_125mhz.xsa`
  - SHA-256: `41cc3d8d0a70faaabc90ba0baaa120722a7a9d0baff86e87651adb5efddbfef8`
- Source-bound build manifest: `build_manifest.json`
  - SHA-256: `fa0200b1265dc685f2a82331ec85c704e761bb86b16fce5a73db0d4ec8e5d0bd`

The `.bit.bin` FPGA-manager firmware image has not yet been generated. The
candidate runtime manifest must remain `deployable:false` until that firmware
exists, its hash is recorded, and the board gates pass. Simulator qualification
is recorded separately under `../CFGLUT125_MATRIX/` (A32 optimized: frame-D
31 internal invalid advances / 0 external gaps — external gapless, internal
bubbles disclosed per Option A).
