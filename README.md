# Exact CFGLUT5 K16 EdgeFree — 100 MHz

Branch: `feature/k16-cfglut5-edgefree-100mhz`. Based on updated upstream `v1-bringup` commit `fb66066`.

Start with [release/QUICKSTART.md](release/QUICKSTART.md). Run `powershell -ExecutionPolicy Bypass -File scripts/release.ps1` with Vivado 2025.2 and Python on PATH to test, build the complete PS/DMA/accelerator system, export bitstream/XSA, and create a standalone board-test package.

This is exact N3/K16/W32 convolution, not Drop-2. All 16 channels run in parallel, engine II=1 when unstalled, pipeline=4 stages. Runtime weights/bias/shift/ReLU remain programmable. [release/hardware.json](release/hardware.json) defines this branch's unique identity. [release/STATUS.md](release/STATUS.md) distinguishes fresh release validation from earlier reference reports.

Canonical RTL is `Convlution_Accelerator.srcs/sources_1/new/`; the complete system BD is `Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/accelerator_dma.bd`. The fresh build copies all inputs into `work/release_100/project/`. Open that generated `edgefree.xpr`, not an old cached project.

Upstream `software/`, `deploy/`, `golden_model/`, profiles, research reports and evidence remain available. Their A32/B32/C32/D32/D640 identifiers and board-qualification claims are **historical**, not evidence for this release. Use the release-specific package/runner, not old hardware manifests or M7 firmware filenames. The old root XPR, old XSA handoffs and tracked generated B32 project leftovers are removed from these release branches; they remain recoverable from `v1-bringup`.

The 125 MHz branch requires matching PS clock initialization; a PL-only bitstream replacement does not change FCLK0. No board has been programmed as part of packaging. No automatic destructive cleanup, clock-register writes, remote upload or board reprogramming occurs in the release workflow.

