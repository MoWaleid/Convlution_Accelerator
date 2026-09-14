# D32_CFGLUT125 routed build — 2026-09-15

Status: **BUILT; BOARD_VALIDATION=NOT_RUN.**

The user executed `scripts/research_release/research_build.tcl` with Vivado
2025.2 from clean commit
`fcc3ed1ba0cdf232a7959b1e3836ac8c2d831aa3`. The deterministic rendered
configuration was verified before the build.

## Identity and implementation result

- Release: `D32_CFGLUT125`
- Shape: `N3K4W32H32-CVH1`
- Build ID: `EF125K04N3W32R01`
- Target: Zynq-7000 `xc7z020clg484-1`
- PL clock: 125 MHz (8.000 ns)
- WNS: +0.093 ns
- WHS: +0.014 ns
- Setup/hold failing endpoints: 0 / 0
- Routing errors: 0
- Methodology checks: 0
- DRC errors: 0; one routable-loads warning and four BRAM advisories are
  preserved verbatim in `drc.rpt`.
- PS7 PSU-1..4 negative-DQS-skew critical warnings during generation are the
  known ZedBoard-preset artifact; see the A32 build notes for the disposition.

Top-level hierarchical utilization: 7,273 total LUTs, 8,308 FFs, two
RAMB36, two RAMB18 and zero DSP blocks. The accelerator wrapper hierarchy
uses 2,883 total LUTs and 2,062 FFs; the four-channel N=3 convolution engine
uses 1,620 total LUTs and 1,011 FFs.

## Preserved artifacts

- Bitstream: `bitstreams/d32_cfglut125_125mhz.bit`
  - SHA-256: `b02fc59ce9e463f77c1b79ac9094b3d6c38dda9f3948b18bff4897cf2c4786dd`
- XSA: `bitstreams/d32_cfglut125_125mhz.xsa`
  - SHA-256: `096927f40b54dd054f253c3038e74f8fcdf471c7f3ae76d72c065598143f6a67`
- Source-bound build manifest: `build_manifest.json`
  - SHA-256: `dda46963dd3d19f43340293c88028ab79f6f550f0d137489e32f9e07d77c702e`

The `.bit.bin` FPGA-manager firmware image has not yet been generated. The
candidate runtime manifest must remain `deployable:false` until that firmware
exists, its hash is recorded, and the board gates pass. Simulator qualification
is recorded separately under `../CFGLUT125_MATRIX/` (D32 optimized_relaxed:
frame-D 62 internal invalid advances / 62 external gaps — exact datapath with
measured row-transition bubbles disclosed per Option A).
