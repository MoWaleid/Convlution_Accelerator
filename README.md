# Exact CFGLUT5 CNN convolution accelerator

**Team: Attention is all you need** · IEEE SSCS Egypt 2026 Student Design Competition

A fixed-point N×N convolution accelerator for the first layer of a grayscale
CNN, built for the Digilent ZedBoard (Zynq-7020, XC7Z020CLG484-1) in VHDL-2008
with Vivado 2025.2. Every 8×8 tap product comes from runtime-programmable
CFGLUT5 lookup multipliers and is summed by a generated Dadda bit heap, so the
datapath is bit-exact against an arbitrary-precision reference and uses no DSP
blocks. This repository holds the RTL, the five qualified 125 MHz hardware
releases, the exact Python reference, the board runtime and GUI, the
verification suite, and the competition deliverables.

- [Competition report](report/report.md) ([PDF](report/report.pdf))
- [Board demonstration video](https://drive.google.com/drive/folders/190LHhYTYuoAFmNcWCe7-HPHLm7nQeYk8)
- [Source repository](https://github.com/MoWaleid/Convlution_Accelerator)

## Quick start

No FPGA, Vivado or board is needed to try the browser interface. It needs
Python 3.11 or newer and Pillow:

```bash
git clone https://github.com/MoWaleid/Convlution_Accelerator.git
cd Convlution_Accelerator
pip install pillow
python -B software/gui/server.py --demo --catalog profiles/m7_profiles.json --profiles profiles --image-root deploy/petalinux/recipes-apps/conv-lab-starter/files/dataset/images --results .gui-demo/results --uploads .gui-demo/uploads --bind 127.0.0.1 --port 8080
```

Then open <http://127.0.0.1:8080>. Demo mode exercises the web application
only and never touches FPGA, DMA or firmware interfaces. To run the host test
suites or build a release, see [Run it without hardware](#run-it-without-hardware)
and [Build another hardware profile](#build-another-hardware-profile).

## Results at a glance

Routed full-system results at 125 MHz, all with zero DSP blocks and 3 BRAM
(the DMA FIFOs). FOM is throughput divided by power times area, as defined in
the [report](report/report.md#11-design-trade-offs-and-figure-of-merit).

| Release | LUTs | Power | Throughput | Full-system FOM |
|---|---:|---:|---:|---:|
| `D640_CFGLUT125` | 7,679 | 1.769 W | 3.988 outputs/cycle | 2.83×10⁻⁴ |
| `D32_CFGLUT125` | 7,273 | 1.768 W | 3.758 outputs/cycle | 2.81×10⁻⁴ |
| `A32_CFGLUT125` | 9,145 | 1.785 W | 4.000 outputs/cycle | 2.37×10⁻⁴ |
| `B32_CFGLUT125` | 12,670 | 1.806 W | 4.000 outputs/cycle | 1.71×10⁻⁴ |
| `C32_CFGLUT125` | 14,162 | 1.823 W | 3.940 outputs/cycle | 1.49×10⁻⁴ |

## Qualified releases

All five pass timing at 125 MHz with zero DSPs and were qualified on the
ZedBoard. N, K and the image size are compile-time constants, so each release
is its own bitstream; weights, bias, shift and ReLU are programmed at runtime.

| Release | Kernel N | Channels K | Image | Parameters |
|---|---|---|---|---|
| `A32_CFGLUT125` | 3 | 8 | 32×32 | Trained CIFAR-10 Conv1 |
| `B32_CFGLUT125` | 3 | 16 | 32×32 | Trained CIFAR-10 Conv1, plus the hybrid classifier |
| `C32_CFGLUT125` | 5 | 8 | 32×32 | Trained CIFAR-10 Conv1 |
| `D32_CFGLUT125` | 3 | 4 | 32×32 | Identity, Sobel X, Sobel Y, blur |
| `D640_CFGLUT125` | 3 | 4 | 640×480 | Same filter set as D32 |

## Status

- The final board campaign covered 577 bit-exact frames, all ordered release
  transitions, a power-cycle cold boot, and injected fault recovery.
- The command-line demonstration is complete.
- The authenticated board-hosted browser GUI is implemented and passed a
  true-power-cycle board test: the board restored networking and the GUI on its
  own, then completed a three-frame anchored B32 run and rendered all 16 output
  channels.
- A deterministic 50-image CIFAR-10 demonstration library provides five images
  per class. Each image carries a content- and profile-bound D640 golden output
  hash, so catalog runs report bit-exact `PASS` without storing roughly 123 MB
  of raw golden tensors.
- A native ARM classification tail completes the B32 network after the FPGA
  first layer and reports the top three CIFAR-10 predictions in the GUI.
- Still open: baking the current GUI, decoder limits and classifier into a
  reproducible PetaLinux image. See [GUI_ROADMAP.md](GUI_ROADMAP.md).

## Repository map

| Path | Purpose |
|---|---|
| `Convlution_Accelerator.srcs/sources_1/new/` | Canonical VHDL-2008 RTL |
| `Convlution_Accelerator.srcs/sim_1/new/` | Canonical testbenches |
| `Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/` | Qualified block design |
| `Zedboard-Master.xdc` | Constraints used by the release flow |
| [`scripts/`](scripts/README.md) | Release flow, generators, packaging and library tools |
| [`profiles/`](profiles/README.md) | Qualified runtime catalog, parameter bundles, anchors, development catalog |
| `bitstreams/` | The five qualified `.bit`, `.bit.bin` and `.xsa` triplets |
| `golden_model/` | Training, quantization, weights, checkpoints, test vectors and the exact reference |
| [`software/`](software/README.md) | Board runtime, release switching, browser GUI and hybrid classifier |
| `verification/` | Host mock suites and SystemVerilog checks for the runtime and AXI shim |
| `deploy/` | PetaLinux recipes and checksum-verified board/host update archives |
| `evidence/` | Cold-boot and hybrid-classification qualification records |
| `report/` | Report sources, figures, presentation, routed build reports and board evidence |
| `docs/` | Learning material, such as the complete technical field guide (PDF) |
| `recovery/` | Checksums and instructions for the archived legacy history and board recovery |
| `platform/` | Exported hardware platform (`.xsa`) |
| `Important documents/` | Competition announcement and early planning records |

Generated locally and not committed: `releases/` (compact build evidence
exported before a Vivado project is deleted), `submission/` (the assembled
competition package; only its checksum manifest is tracked), `final_upload/`
(the uploaded archives), and Vivado project output.

## Frozen files

The qualified bitstreams are bound by SHA-256 to the exact bytes of their
inputs. Editing any of these, even a comment, breaks that binding and means a
rebuild and a fresh board qualification:

- the RTL under `Convlution_Accelerator.srcs/sources_1/new/`, the block design
  `accelerator_dma.bd`, and `Zedboard-Master.xdc`;
- `scripts/research_release/research_build.tcl` and the five specs in
  `builds/`.

All 95 of those bindings still match the five build manifests. The manifests
also recorded `research_release.py` and `profiles/m7_profiles.json`; both were
revised in later commits, so they no longer match and should not be reverted
to chase it.

Also treat as release artifacts: `profiles/m7_profiles.json` and the parameter
bundles it names by SHA-256, and everything in `bitstreams/`,
`report/research_builds/` and `report/evidence/`.

The PetaLinux recipe payload under `deploy/petalinux/recipes-apps/` must stay
byte-identical to `software/gui/server.py`, `software/gui/static/`,
`software/m7_switch.py` and `software/m8_cli.py`. `deploy/petalinux/` also
carries its own `SHA256SUMS.txt`.

## Run it without hardware

The quick start above launches the demo. The same command in PowerShell, using
line continuations:

```powershell
python -B software/gui/server.py --demo `
  --catalog profiles/m7_profiles.json `
  --profiles profiles `
  --image-root deploy/petalinux/recipes-apps/conv-lab-starter/files/dataset/images `
  --results .gui-demo/results --uploads .gui-demo/uploads `
  --bind 127.0.0.1 --port 8080
```

Open `http://127.0.0.1:8080`. Demo mode exercises the web application only and
never opens FPGA, DMA or firmware interfaces.

Host tests:

```powershell
python -B software/gui/test_server.py
python -B scripts/research_release/test_spec_crosscheck.py
python -B scripts/research_release/research_release.py check A32_CFGLUT125
```

[software/README.md](software/README.md) lists the remaining runtime test
groups. Verify the qualified artifacts with `sha256sum -c FINAL_SHA256SUMS.txt`
from `bitstreams/`.

## Build another hardware profile

The exact bit-heap RTL supports N=3 and N=5. K may be 1 through 64; device
resources and the timing gates determine which configurations fit. Image
dimensions are compile-time values, and each DMA transfer must fit the 22-bit
length field.

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
Development profiles stay in `profiles/development_profiles.json`, separate
from the qualified runtime catalog, until they pass board qualification.

## Competition package

The upload package is assembled in `submission/` and includes the report,
presentation, source code, expected vectors, FPGA reports and board evidence.
Its `SHA256SUMS.txt` covers every payload file. After editing the report, run
`python -B scripts/packaging/refresh_submission.py` to re-sync the package and
rebuild the upload archives.
