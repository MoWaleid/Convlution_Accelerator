# Graphical demonstration interface — implementation and qualification state

The first browser release is implemented under `software/gui/`. It is served
by Python on PetaLinux and opened from a browser over Ethernet. The GUI wraps
the existing command-line runtime, serializes hardware jobs, archives results,
and never reimplements MMIO, DMA, or FPGA Manager operations.

## Implemented first release

The implemented release avoids a desktop graphics stack on the ZedBoard while
keeping hardware access on the board. Production access is protected by HTTP
Basic authentication using a board-generated token; it remains intended for a
direct link or isolated competition LAN because HTTP itself is not encrypted.

The interface should:

1. List only admitted profiles and show N, K, geometry, build identity, and
   qualification status.
2. Switch the full PL through the existing FPGA Manager flow, then verify the
   live hardware identity before enabling inference.
3. Run an anchor self-test after every switch and refuse inference after a
   failed check.
4. Accept a static PNG/JPEG, apply the profile's declared preprocessing, and
   show the input plus every output channel in a compact gallery.
5. Browse allow-listed image directories on the board without exposing
   arbitrary filesystem paths; verified-sample and browser-upload flows remain
   available.
6. Display measured execution time, current profile, result checksum, and a
   concise error/recovery message.
7. Keep the existing fail-stop behavior: DMA and hardware faults trigger reset
   and require a successful anchor test before another run.

## Implementation boundary

The GUI must call the existing strict profile loader and runtime rather than
reimplementing register access. A small service layer should serialize
hardware operations, store results under the established result directory,
and return image/metric data to the browser.

The UI renders all generated feature maps as compact thumbnails. Selecting a
thumbnail opens an enlarged viewer with a direct PNG download. The runtime
still computes and verifies all K channels. Sobel/identity/blur
parameter presets remain a post-competition extension; they are not silently
presented as part of this fixed qualified-profile release.

## Acceptance checks

Host-complete:

- Seven focused API tests pass: catalog/image admission, traversal rejection,
  production authentication, job submission, deterministic resize dispatch,
  all-channel result admission, and security headers.
- Python and JavaScript syntax checks pass.
- Desktop browser rendering was inspected; responsive overflow fixes were
  applied for narrow viewports.

Physical-board progress:

- The authenticated service is installed and reachable over direct Ethernet.
- A normal uploaded PNG was decoded, converted, resized, and executed through
  D640 for three frames.  All four feature-map previews were rendered;
  accelerator-path median/p95 were 3.735/3.750 ms and the PS-observed whole-call
  median was 155.012 ms.  The run was correctly labelled `UNVERIFIED` because
  no slow D640 PS exact reference was requested.
- The final gallery exposes every generated channel, opens a selected channel
  in an enlarged dialog, and supports direct PNG download.
- A true power cycle automatically restored the static `192.168.0.3/24`
  network, authenticated service, FPGA Manager, both UIO devices, and
  `/dev/udmabuf0`; no terminal recovery was performed.
- From that cold boot, the GUI ran the B32 verified sample for three
  bit-identical frames and reported PASS. All 16 channel maps were rendered.
  Accelerator-path median/p95 were 0.126/0.145 ms and whole-call median was
  2.912 ms.
- The transferred evidence archive, its 24-entry internal checksum manifest,
  and the GUI screenshot are documented in
  `evidence/cold_boot/QUALIFICATION.md`.

Host-complete, awaiting board installation:

- A compact CIFAR-10 library contains five official sample images for each of
  the ten classes. Its 50 D640 golden outputs are stored as SHA-256 oracles,
  saving about 123 MB compared with raw tensors.
- Catalog admission is bound to source, canonical resize, padded payload,
  profile/build, parameter bundle, and output identities. Unknown and uploaded
  D640 images remain `UNVERIFIED`.
- The checksum-verified board update is under `deploy/board_updates/`; the next
  physical gate is one GUI-driven D640 catalog image reporting `PASS`.

Remaining release engineering:

- Bake the current GUI, decoder policy, service startup links, and static
  network configuration into a fresh reproducible PetaLinux image; the current
  board installation persists on ext4 but was applied after imaging.
- Optional extended assurance: drive each of the other four profile switches
  through the GUI and capture their anchors, then surface the already-qualified
  malformed-bundle, identity, and DMA-fault recovery paths as explicit GUI
  acceptance tests.
