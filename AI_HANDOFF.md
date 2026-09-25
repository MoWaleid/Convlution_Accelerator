# Project handoff

Read [README.md](README.md) first. It is the current project map and build
guide. The qualified design consists of five exact CFGLUT5/Dadda releases at
125 MHz: A32, B32, C32, D32, and D640. The final submission is under
`submission/`; compact build evidence is under `releases/`; qualified runtime
artifacts are under `bitstreams/`.

The graphical demonstration interface is implemented under `software/gui/`.
It is a polished board-hosted web UI that selects one of the five qualified
profiles, browses allow-listed PNG/JPEG directories on the ZedBoard, runs the
existing `m8_cli.py` path, reports precisely labelled PS-observed timing, and
shows all output feature maps in a compact gallery with enlarged viewing and
per-channel PNG download. The production service requires Basic
authentication with user `conv` and a board-generated token. The direct-board
runtime is installed. An uploaded ordinary PNG completed a three-frame D640
run with all four previews, and a later true power cycle automatically restored
the static network, GUI service, FPGA Manager, UIO devices, and DMA buffer. A
GUI-initiated B32 verified-sample run passed for three bit-identical frames
(0.126 ms accelerator-path median, 0.145 ms p95, 2.912 ms whole-call median)
and rendered all 16 downloadable channel maps. The evidence archive and
screenshot are under `evidence/cold_boot/`; see its `QUALIFICATION.md`.

The board-library expansion is implemented. The canonical generator is
`scripts/library/build_cifar10_demo.py`; it selects official CIFAR-10 page
samples 1-5 for each class, reproduces the existing D640 alley-cat anchor as a
self-test, and emits 50 PNGs plus content-bound D640 output hashes. The catalog
SHA-256 is `cedbc76ac11f09fd7ee795d435ee9748473fbbd0f15fef0d2f8b6f80c23c86e7`.
`m8_cli.py --trusted-library` checks source, preprocessing, padded payload,
hardware/profile, parameter bundle, and output identities. The GUI sets this
flag only for the installed catalog root; arbitrary uploads remain UNVERIFIED.
The board update archive is
`deploy/board_updates/conv_lab_library50_d640_v1_20260925.tar.gz` (SHA-256
`fd7120cbac6eb8ba7edab5e7b6941a92bf23ae80263e71aeb6479d2791b8da34`).
Host GUI tests and the full runtime mock suite pass. The 50-image library is
installed on the board. D640 uses its content-bound precomputed references;
A32/B32/C32/D32 use the same images and compute the exact reference during the
run. The GUI routes trust per image *and per profile*, so it never asks a
non-D640 profile for a nonexistent D640 oracle.

Host tests and the B32 cold-boot GUI path pass. Remaining deployment work is to
bake the current GUI, decoder limits, service links, and static-network policy
into a reproducible PetaLinux image, then optionally repeat GUI-driven
switch/anchor coverage for all five profiles and expose injected failure
recovery through the interface. `GUI_ROADMAP.md` records the exact state.

## Hybrid full classification — qualified live path

The B32 hybrid path is implemented and demonstrated. Qualified B32 hardware
runs Conv1; `/usr/bin/conv-classify-tail` then runs max-pool, Conv2, max-pool,
Conv3, FC1, FC2 and softmax natively on the Cortex-A9. The GUI invokes the
wrapper `/home/petalinux/m8_classify_cli.py`, keeps the existing bit-exact FPGA
run and evidence record, and adds the predicted class, confidence, top three,
and separate FPGA/PS/combined timing.

The frozen ARM fixture passed all-ten-logit equivalence. A live GUI run of
`ship_03.png` passed the FPGA reference and classified **Ship at 98.8%**. The
capture reports FPGA Conv1 0.145 ms, PS tail 19.041 ms, combined compute
19.186 ms and whole call 31.405 ms, with all 16 feature maps available. Evidence
is under `evidence/hybrid_classification/` and is mirrored into
`submission/docs/board_evidence/hybrid_classification/`. The B32 model's
recorded CIFAR-10 test accuracy is 70.08%; classification accuracy is a model
property and is not conflated with the accelerator's bit-exact PASS result.

Canonical implementation is under `software/classifier/`. The PetaLinux
classifier recipe is under `deploy/petalinux/recipes-apps/conv-lab-classifier/`.
The GUI recipe formally depends on it and installs the wrapper, binary, and
model bundle in future images. Host classifier tests pass (4), GUI/security
tests pass (7), and the current report includes the live hybrid result.
The bounded decoder accepts standard static PNG modes and JPEG. JPEG files may
contain bounded non-image trailer bytes, but appended JPEG/PNG signatures are
rejected as a second image. Source admission is bounded to 8 MiB encoded,
4096 pixels per axis, and 12 megapixels total under one 256 MiB RLIMIT_AS
worker. Preserve these limits and the single-worker rule when changing admission.

PetaLinux source is in
`deploy/petalinux/recipes-apps/conv-lab-gui/`; select
`CONFIG_conv-lab-gui=y`. The recipe payload must remain byte-identical to the
canonical `software/gui/server.py` and `software/gui/static/` files. Do not
replace the GUI runtime with direct MMIO code: it must continue to wrap the
qualified CLI so switching, identity checks, DMA recovery, and evidence
archiving retain one implementation.

Do not restore legacy 100 MHz builds, old MAC RTL, milestone-era catalogs, or
generated Vivado projects. New hardware profiles must be created through
`scripts/research_release/create_profile.py`, built through the checked release
flow, and kept unqualified until board identity, anchor, soak, timing, and
switching evidence passes.

User workflow: edit and run local code directly. Give the user only commands
that must run in Vivado, Ubuntu/PetaLinux, or the ZedBoard shell. Keep `sudo`
commands in separate copy-paste blocks because password prompts can interrupt
the following commands.

## Cleanup and recovery state

- Generated Vivado projects, caches, simulations, and temporary datasets were removed.
- `bitstreams/` now contains only the five qualified 125 MHz profile triplets and their verified manifest.
- Historical checkpoints, captures, milestone notes, and logs are preserved in `recovery/legacy_history_20260920.tar.gz`.
- Earlier external release checkpoints are preserved in `recovery/release_checkpoints_20260920.tar.gz`.
- The integrated teammate clone was clean and reproducible; its remote and commit are recorded in `recovery/EXTERNAL_SOURCES.md`.
- VMShare retains `zedboard_B32_CFGLUT125_G3_3eb5074.wic.gz` and `g5_runtime_20260915T024500Z.tar.gz` as the recovery pair. Decompress the WIC before flashing.
- The safe maintenance helper is dry-run first and project-only; it never removes VMShare or external directories.
