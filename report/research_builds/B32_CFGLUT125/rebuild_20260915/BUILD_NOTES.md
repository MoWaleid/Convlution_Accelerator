# B32_CFGLUT125 uniform-provenance rebuild — 2026-09-15

Status: **BUILT; BOARD_VALIDATION=NOT_RUN.**

This is the uniform generalized-source rebuild of AI_HANDOFF.md §19.6: the
older full B32 build was archived and hash-verified first (see
`../REBUILD_ARCHIVE_20260915.md`), the build tree was re-rendered pristine,
and the user executed `scripts/research_release/research_build.tcl` with
Vivado 2025.2 from clean commit
`b230d02096f7273aa50fcbca477680df0739a100`.

The older board-qualified B32 evidence (reports and board records in this
directory's parent, plus the dated artifact copies under
`bitstreams/history/20260914_b32_board_qualified/`) remains the historical
qualification proof for that exact older artifact set only. This rebuilt
B32 inherits no qualification credit; fresh build binding and board gates
apply.

## Identity and implementation result

- Release: `B32_CFGLUT125`
- Shape: `N3K16W32H32-CVH1`
- Build ID: `EF125K16N3W32R01`
- Target: Zynq-7000 `xc7z020clg484-1`
- PL clock: 125 MHz (8.000 ns)
- WNS: +0.090 ns
- WHS: +0.053 ns
- Setup/hold failing endpoints: 0 / 0
- Routing errors: 0
- Methodology checks: 0
- DRC errors: 0; one routable-loads warning and four BRAM advisories are
  preserved verbatim in `drc.rpt`.
- PS7 PSU-1..4 negative-DQS-skew critical warnings during generation are the
  known ZedBoard-preset artifact; see the A32 build notes for the disposition.

Top-level hierarchical utilization: 12,670 total LUTs, 12,686 FFs, two
RAMB36, two RAMB18 and zero DSP blocks. The accelerator wrapper hierarchy
uses 8,274 total LUTs and 6,440 FFs; the sixteen-channel N=3 convolution
engine uses 6,186 total LUTs and 3,911 FFs.

## Preserved artifacts (canonical names replaced; old set preserved)

- Bitstream: `bitstreams/b32_cfglut125_125mhz.bit`
  - SHA-256: `2388f249aa1ae8c4bce2b9aa0cfd612acecf11d0e4cf595f020ff8bf4b8abcdd`
- XSA: `bitstreams/b32_cfglut125_125mhz.xsa`
  - SHA-256: `2b523f78d4b59c6fa0f468ccb9d90a8b420cbd224d7ac586e0f8f76229d222c8`
- Source-bound build manifest: `build_manifest.json` (this directory)
  - SHA-256: `15f1deb26ac28769240937e839c05a04639ff4090d0ce461df3fc2d474d83171`

The replaced canonical files' old bytes are preserved at
`bitstreams/history/20260914_b32_board_qualified/` (re-verified at replacement
time: BIT `133713c5…`, BIT.BIN `4e827310…`, XSA `e90b8441…`) and, for the XSA,
in git history.

Open: the canonical `bitstreams/b32_cfglut125_125mhz.bit.bin` still belongs to
the older qualified build until §19.7 generates the rebuild's FPGA-manager
firmware; the dated copy is its preservation record.

The `.bit.bin` for the rebuild has not yet been generated. The candidate
runtime manifest must remain `deployable:false` until that firmware exists,
its hash is recorded, and the board gates pass. Simulator qualification is
recorded separately under `../CFGLUT125_MATRIX/` (B32 optimized: frame-D
0/0 — the only release with a proven zero-internal-invalid-advance,
zero-external-gap claim).
