# M7 profile inputs

Authority: [m7_profiles.json](m7_profiles.json). IDs are frozen pre-synthesis inputs,
not hashes, timestamps, qualification flags or newly generated build IDs.
The checked-in config_pkg is the **D640 projection** (the M7/M9-era selected
snapshot: N3/K4, 640×480, `D640N3K04-260912`), not the B32 instance. All wrapper defaults use CFG_BUILD_ID; the BD adapter supplies no override.
scripts/prepare_profile.py requires a profile and a new output directory, rendering
only the selected configuration block into an isolated RTL snapshot. Do not edit
the projection independently. The focused tests compare it with the authority.

A32 = 4d344e334b385733322d323630393131.
B32 = 424e334b31365733322d323630393132.
C32 = 434e354b30385733322d323630393132.
D32 = 444e334b30345733322d323630393132.
D640 = 443634304e334b30342d323630393132.

(These are the reconciled catalog values from `m7_profiles.json`; the
pre-reconciliation strings shown here earlier — `M7N5…`/`M7N3…` for C32/D32/D640
— were superseded by the 2026-09-13 catalog/manifest reconciliation.)

A32 and the pre-existing B32 edit retain their numeric identities. Contrary to the reported 30-digit issue, the inspected workstation A32 original is already 32 hexadecimal digits (four words: 4d344e33 4b385733 322d3236 30393131); adding 00 would exceed 128 bits. It remains byte-for-byte unchanged. Shorter text could only be zero-padded as a separate explicit migration preserving its numeric value, never by dropping nonzero digits. C32/D32/D640 assignments
are distinct frozen inputs for this increment. Changed releases require an explicit
identity decision; no script invents IDs. A32 source changes are not evidence that
a rebuilt artifact is equivalent to the preserved M4/A32 bitstream. The qualified
A32 firmware is now archived in-repo as `bitstreams/m7_A32.bin`
(sha256 `b59378e4…`), recovered from the board 2026-09-14.

Original workstation hardware.json is preserved byte-for-byte as
[history/hardware_A32_original_20260912.json](history/hardware_A32_original_20260912.json),
SHA256 cd125d369c2239e4e2b6488ea0d69d48499e4402984673d84f14c5536924be08.
software/hardware.json is byte-identical to that preserved original. Its historical
layout and artifact references remain unchanged. (No deployed board file was
inspected at the time of that edit; the deployed runtime was subsequently verified
throughout M7–M9 qualification, and the runtime manifest was recovered 2026-09-14
as `software/hardware_A32.json`, the strict-manager-compatible A32 manifest.)
This existing legacy-shaped JSON is not being promoted
to the complete M1 hardware-bundle schema.

New M7 layout/admission uses conv_lab.profiles + conv_lab.dma, with supplied
runtime-discovered allocation facts; these helpers do no device discovery or DMA.
M5/M6 runners keep their historical layouts. Full runtime switching is qualified
on board (M7: 58-switch matrix, five 100-frame soaks, cold-boot fallback; M9:
1,000-frame varied soak and five physical power-cycle boots). Current status is
in AI_HANDOFF.md; [M7_CONTINUATION.md](../M7_CONTINUATION.md) is historical.

Vivado command references used for static review:
[save_project_as](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/save_project_as),
[update_module_reference](https://docs.amd.com/r/2025.2-English/ug835-vivado-tcl-commands/update_module_reference).
No Vivado command was executed during this edit.

