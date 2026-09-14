# C32_CFGLUT125 routed build — 2026-09-15

Status: **BUILT; BOARD_VALIDATION=NOT_RUN.**

The user executed `scripts/research_release/research_build.tcl` with Vivado
2025.2 from clean commit `9c725cc4d667888cece0bb3982d95b6648725b5b`.
The deterministic rendered configuration was verified before the build.

## Identity and implementation result

- Release: `C32_CFGLUT125`
- Shape: `N5K8W32H32-CVH1`
- Build ID: `EF125K08N5W32R01`
- Target: Zynq-7000 `xc7z020clg484-1`
- PL clock: 125 MHz (8.000 ns)
- WNS: +0.003 ns
- WHS: +0.037 ns
- Setup/hold failing endpoints: 0 / 0
- Routing errors: 0
- Methodology checks: 0
- DRC errors: 0; two implementation warnings and four BRAM advisories are
  preserved verbatim in `drc.rpt`.

Top-level hierarchical utilization: 14,162 total LUTs, 13,934 FFs, two
RAMB36, two RAMB18 and zero DSP blocks. The accelerator wrapper hierarchy
uses 9,764 total LUTs and 7,688 FFs; the eight-channel N=5 convolution engine
uses 7,836 total LUTs and 4,944 FFs.

## Preserved artifacts

- Bitstream: `bitstreams/c32_cfglut125_125mhz.bit`
  - SHA-256: `8108a82fcbb7cec73aca919e58ef1c6725561444bfd6ee5887e8aa51315d866f`
- XSA: `bitstreams/c32_cfglut125_125mhz.xsa`
  - SHA-256: `eb777ad376eb81687a834a7beb66de2f4085e0757522df53480d7b0dd6b43538`
- Source-bound build manifest: `build_manifest.json`
  - SHA-256: `0bf0155ac74d34d14b63b8fadf0864651ecd65d425bda552cccd9a44ea979ca4`

The `.bit.bin` FPGA-manager firmware image has not yet been generated. The
candidate runtime manifest must remain `deployable:false` until that firmware
exists, its hash is recorded, and the board gates pass. Simulator qualification
is recorded separately under `../CFGLUT125_MATRIX/`.
