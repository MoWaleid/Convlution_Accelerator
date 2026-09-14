# D640_CFGLUT125 routed build — 2026-09-15

Status: **BUILT; BOARD_VALIDATION=NOT_RUN.**

The user executed `scripts/research_release/research_build.tcl` with Vivado
2025.2 from clean commit `180c2fafc5ec9d36344b101ca9ea7d5569b24002`.
The deterministic rendered configuration was verified before the build.

## Identity and implementation result

- Release: `D640_CFGLUT125`
- Shape: `N3K4W640H480-CVH1`
- Build ID: `EF125N3K04VGA-R1`
- Target: Zynq-7000 `xc7z020clg484-1`
- PL clock: 125 MHz (8.000 ns)
- WNS: +0.001 ns
- WHS: +0.022 ns
- Setup/hold failing endpoints: 0 / 0
- Routing errors: 0
- Methodology checks: 0
- DRC errors: 0; implementation warnings and BRAM advisories are preserved
  verbatim in `drc.rpt`.

Top-level hierarchical utilization: 7,679 total LUTs, 8,940 FFs, two RAMB36,
two RAMB18 and zero DSP blocks. The accelerator wrapper hierarchy uses 3,281
total LUTs and 2,694 FFs; the four-channel convolution engine uses 1,619 total
LUTs and 1,011 FFs.

## Preserved artifacts

- Bitstream: `bitstreams/d640_cfglut125_125mhz.bit`
  - SHA-256: `6e95188e197f402bf9029295b3d4584111aa7b5afbb06802045596f49f41cca3`
- XSA: `bitstreams/d640_cfglut125_125mhz.xsa`
  - SHA-256: `371a420baf8b20d1ad2cb0ad072bde8f101a232df0dc691e72f79b37742c9457`
- Source-bound build manifest: `build_manifest.json`
  - SHA-256: `fd61fdd98ec5580807552edc0ee606bd7c010a11db0beec730cb15a4207a87aa`

The `.bit.bin` FPGA-manager firmware image has not yet been generated. The
candidate runtime manifest remains `deployable:false` until firmware creation,
hash binding and board qualification. The 640×480 static-image path and 4 MiB
DMA allocation are mandatory board gates, not implied by routing success.
