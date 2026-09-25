# Exact CFGLUT5 CNN convolution accelerator

**Team: Attention is all you need**

This repository contains the final 125 MHz Zynq-7020 convolution accelerator,
its five qualified hardware profiles, the exact Python reference, board
runtime, verification suite, and competition deliverables.

## Current status

- Five hardware releases passed timing at 125 MHz and were qualified on the
  ZedBoard: A32, B32, C32, D32, and D640.
- The final board campaign covered 577 bit-exact frames, all ordered release
  transitions, cold boot, and injected fault recovery.
- The command-line demonstration is complete.
- The authenticated board-hosted graphical interface is implemented, passed
  host API/browser-layout checks, and passed a true-power-cycle board test.
  The board automatically restored networking and the GUI, then completed a
  three-frame anchored B32 run while rendering all 16 output channels.
- A deterministic 50-image CIFAR-10 demonstration library now provides five
  images per class. Each image carries a content- and profile-bound D640 golden
  output hash, so catalog runs can report bit-exact `PASS` without storing
  approximately 123 MB of raw golden tensors.
- A native ARM classification tail completes the B32 network after the FPGA
  first layer and reports the top-three CIFAR-10 predictions in the GUI.
- The final report and compact reviewer archive are under `final_upload/`
  locally; that generated directory is intentionally not committed.

## Canonical project areas

| Path | Purpose |
|---|---|
| `Convlution_Accelerator.srcs/sources_1/new/` | Canonical VHDL-2008 RTL |
| `Convlution_Accelerator.srcs/sim_1/new/` | Canonical testbenches |
| `Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/accelerator_dma.bd` | Qualified block design |
| `scripts/research_release/` | Reproducible profile creation and Vivado release flow |
| `profiles/` | Qualified runtime catalog, bundles, anchors, and development catalog |
| `bitstreams/` | Five qualified `.bit`, `.bit.bin`, and `.xsa` triplets |
| `golden_model/` | Training, quantization, weights, checkpoints, and exact reference |
| `software/` | Board runtime, profile switching software, and browser GUI |
| `deploy/` | PetaLinux integration |
| `scripts/library/` | Reproducible verified-library generator |
| `releases/` | Compact local build evidence exported before deleting Vivado projects |
| `submission/` | Final competition package source tree |

Vivado output directories are disposable. The repository keeps source,
qualified artifacts, and compact reports rather than generated projects.

## Build another hardware profile

The current exact bit-heap RTL supports N=3 and N=5. K may be 1 through 64;
the device resources and timing gates determine which configurations fit.
Image dimensions are compile-time values, and each DMA transfer must fit the
22-bit length field.

Create an unqualified development profile:

```powershell
python -B scripts/research_release/create_profile.py E128_CFGLUT125 `
  --n 3 --k 8 --width 128 --height 128
python -B scripts/research_release/research_release.py check E128_CFGLUT125
python -B scripts/research_release/research_release.py prepare E128_CFGLUT125
```

Then run in the Vivado Tcl console:

```tcl
cd {D:/MyProjects/Convlution_Accelerator}
set research_release_id E128_CFGLUT125
source {scripts/research_release/research_build.tcl}
```

Back in PowerShell:

```powershell
python -B scripts/research_release/research_release.py manifest E128_CFGLUT125
python -B scripts/research_release/research_release.py publish E128_CFGLUT125
python -B scripts/research_release/research_release.py clean E128_CFGLUT125 --yes
```

`publish` preserves the compact artifact set. `clean` refuses to remove the
generated Vivado project until that published copy passes its checksums.
Development profiles are kept separate from the qualified runtime catalog.

## Competition links

- [Board demonstration video](https://drive.google.com/drive/folders/190LHhYTYuoAFmNcWCe7-HPHLm7nQeYk8)
- The exact submitted revision is tagged `sscs-egypt-2026-submission`.

The upload package is generated from `submission/` and includes the report,
presentation, source code, expected vectors, FPGA reports, and board evidence.
