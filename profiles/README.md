# M7 profile inputs

Authority: [m7_profiles.json](m7_profiles.json). IDs are frozen pre-synthesis inputs,
not hashes, timestamps, qualification flags or newly generated build IDs.
The checked-in config_pkg is the **B32 projection**, retaining the existing K16
work. All wrapper defaults use CFG_BUILD_ID; the BD adapter supplies no override.
scripts/prepare_profile.py requires a profile and a new output directory, rendering
only the selected configuration block into an isolated RTL snapshot. Do not edit
the projection independently. The focused tests compare it with the authority.

A32 = 4d344e334b385733322d323630393131.
B32 = 424e334b31365733322d323630393132.
C32 = 4d374e354b385733322d323630393132.
D32 = 4d374e334b345733322d323630393132.
D640 = 4d374e334b3457363430483438300001.

A32 and the pre-existing B32 edit retain their numeric identities. Contrary to the reported 30-digit issue, the inspected workstation A32 original is already 32 hexadecimal digits (four words: 4d344e33 4b385733 322d3236 30393131); adding 00 would exceed 128 bits. It remains byte-for-byte unchanged. Shorter text could only be zero-padded as a separate explicit migration preserving its numeric value, never by dropping nonzero digits. C32/D32/D640 assignments
are distinct frozen inputs for this increment. Changed releases require an explicit
identity decision; no script invents IDs. A32 source changes are not evidence that
a rebuilt artifact is equivalent to the preserved M4/A32 bitstream.

Original workstation hardware.json is preserved byte-for-byte as
[history/hardware_A32_original_20260912.json](history/hardware_A32_original_20260912.json),
SHA256 cd125d369c2239e4e2b6488ea0d69d48499e4402984673d84f14c5536924be08.
software/hardware.json is byte-identical to that preserved original. Its historical
layout and artifact references remain unchanged. No deployed board file was
inspected or verified. This existing legacy-shaped JSON is not being promoted
to the complete M1 hardware-bundle schema.

New M7 layout/admission uses conv_lab.profiles + conv_lab.dma, with supplied
runtime-discovered allocation facts; these helpers do no device discovery or DMA.
M5/M6 runners keep their historical layouts. Full runtime switching is subsequent
work. Commands/status are in [M7_CONTINUATION.md](../M7_CONTINUATION.md).

Vivado command references used for static review:
[save_project_as](https://docs.amd.com/r/en-US/ug835-vivado-tcl-commands/save_project_as),
[update_module_reference](https://docs.amd.com/r/2025.2-English/ug835-vivado-tcl-commands/update_module_reference).
No Vivado command was executed during this edit.

