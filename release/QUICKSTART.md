# Exact CFGLUT5 K16 EdgeFree release

This package contains the **whole accelerator system**, not just the arithmetic core: Zynq PS configuration, DDR/MIO platform, GP0 control, HP0 DMA data path, AXI DMA simple-mode len22, SmartConnect, reset network, AXI-Lite controller, input frontend, line/window storage, exact CFGLUT engine, FIFOs and output serializer.

Read `release/hardware.json` in the repository (or `hardware.json` in the generated package) for this branch's frequency and unique BUILD_ID. N=3, K=16, logical image=32x32, unsigned8 pixels, signed8 weights, signed24 bias and signed16 output. Coefficients remain software-programmable. No approximate/drop-2 multiplication is used. No accelerator DSP or BRAM is required; DMA has its own BRAMs.

## Build on your own workstation

Prerequisites: Vivado **2025.2**, Zynq-7000 device support for `xc7z020clg484-1`, a valid license, Python 3.10+ and PowerShell. No private user folders, prior Vivado caches, preinstalled board preset repository, pretrained-model training, or network downloads are required. The tracked block design contains the PS platform configuration. Allow several GB of disk space and implementation time.

1. Check out `feature/k16-cfglut5-edgefree-100mhz` or `feature/k16-cfglut5-edgefree-125mhz`. Keep local source edits safe before switching.
2. In a shell with Vivado and Python on PATH, from the repository root:

   ```powershell
   powershell -ExecutionPolicy Bypass -File scripts/release.ps1
   ```

   Or supply executable paths with `-Vivado 'C:\...\Vivado\bin\vivado.bat' -Python 'C:\...\python.exe'`.
3. The command runs RTL tests, builds an isolated full system, requires passing setup/hold/pulse-width/route/DRC checks, exports `.bit` and `.xsa`, packages the software/parameters/input, and verifies package hashes and the software reference on the host.

Actions can run separately: `-Action Test`, `Build`, `Package`, or `Check`. Build output is `work/release_<MHz>/`; its project is `project/edgefree.xpr`, reports and hardware are in `artifacts/`. The transferable package is `dist/edgefree<MHz>/`. The scripts refuse to overwrite existing build/package directories; archive them explicitly if rebuilding. Simulation working directories are reproducible scratch directories. Generated outputs are intentionally not Git source files.

Do not open the historical upstream root project or run its multiprofile build scripts for this release. Use the fresh release project/script. N5/C32/D640 and historical A32/B32 identities are not this CFGLUT release.

## Boot/deployment boundary — important

These releases have RTL and physical-tool validation, **not new board qualification**. The bitstream and XSA are complete PL/hardware handoffs; they are not an SD-card Linux image.

Use `artifacts/edgefree.xsa` to regenerate/import the hardware platform in the friend's existing matching PetaLinux/Vitis ZedBoard project, and rebuild PS initialization/FSBL and the boot image with `artifacts/edgefree.bit`. Preserve the repository's Linux platform requirements: accelerator at `0x43c00000`, DMA at `0x40400000`, 64 KiB UIO mappings (`/dev/uio1` accelerator, `/dev/uio0` DMA), u-dma-buf `/dev/udmabuf0` with sync_mode=1, and a non-overlapping reserved DMA buffer. Existing platform integration files and historical provisioning instructions are under `deploy/petalinux/`; they do not substitute for importing the new XSA. Linux/PetaLinux boot-image rebuilding cannot be certified from this Windows-only hardware build.

**125 MHz needs actual PS FCLK0=125 MHz after boot.** Replacing only a PL bitstream in an old 100 MHz boot environment does not change PS clock initialization. Use the matching XSA/FSBL/device-tree clock configuration; inspect the running Linux clock summary or platform clock API to verify the actual clock before testing. Do not directly poke clock registers during active DMA. No MMCM is added. The clock-confirmation argument below is a user assertion, not a clock measurement.

Never use old `software/hardware_B.json` firmware hashes or `m7_B32.bin` to load this release. Those files remain historical upstream profiles. Each new release package has its own manifest and hashes. The new board runner intentionally **does not program PL or alter clocks**; boot the matching release first.

## Run the standalone board test

Copy the entire `dist/edgefree<MHz>` directory onto the booted ZedBoard. Do not rename/mix individual artifacts across releases. Python 3 and the existing Linux UIO/u-dma-buf drivers are required. The supplied deterministic grayscale input and trained K16 parameters remove dependency on the friend's private image library; no Pillow dependency is needed for this test.

```sh
cd edgefree125  # or edgefree100
python3 software/edgefree_board.py --check-only
sudo python3 software/edgefree_board.py --frames 3 --confirmed-clock-mhz 125
# Use 100 for the 100 MHz release; then repeat with --frames 100.
```

The runner verifies package hashes, live BUILD_ID/ABI/geometry/widths, exclusive ownership, UIO addresses and DMA-buffer configuration. It programs nine ordinary 3x3 weights per channel, performs bit-exact comparison of all 16,384 output values per frame, checks byte/pixel counters and four memory guards, and resets after success. On a failure it attempts to halt DMA/abort and reports recovery needs; it never prints success merely because a timeout was reached. Host `--check-only` does not touch devices and is not board evidence.

The latest upstream software is retained in `software/`; the standalone runner reuses its M7/M4 low-level/reference helpers without using historical profile-switch manifests. Existing M8 demos remain historical multiprofile workflows, not a prequalified launch command for the new identities. The wire/register/numerical ABI stays unchanged.

## Interpretation

EdgeFree removes internal row-transition stalls under its verified prefetch conditions. External source starvation or output backpressure can still stall transfers. All 16 arithmetic channels remain parallel; unstalled engine II=1. The 100 MHz engine has four stages; the 125 MHz engine has six. End-to-end throughput includes serialization and DMA, not just the engine's peak rate. Consult `release/STATUS.md` for the exact packaged-build evidence; older reference figures are not a guarantee for a new tool version or changed RTL.
