# Graphical demonstration interface — state and remaining work

The browser interface lives under `software/gui/`. It is served by Python on
PetaLinux and opened from a browser over Ethernet. It wraps the existing
command-line runtime, serializes hardware jobs, archives results, and never
reimplements MMIO, DMA or FPGA Manager operations. Usage, image roots, timing
labels and credentials are documented in
[software/gui/README.md](software/gui/README.md).

## What the release does

Serving from the board avoids a desktop graphics stack on the ZedBoard while
keeping hardware access local. Production access uses HTTP Basic authentication
with a board-generated token. HTTP itself is not encrypted, so the service is
meant for a direct link or an isolated competition LAN.

1. Lists only admitted profiles and shows N, K, geometry, build identity and
   qualification status.
2. Switches the full PL through the existing FPGA Manager flow, then verifies
   the live hardware identity before enabling inference.
3. Runs an anchor self-test after every switch and refuses inference after a
   failed check.
4. Accepts a static PNG or JPEG, applies the profile's declared preprocessing,
   and shows the input plus every output channel in a compact gallery.
5. Browses allow-listed image directories on the board without exposing
   arbitrary filesystem paths; the verified-sample and browser-upload flows
   remain available.
6. Displays measured execution time, current profile, result checksum, and a
   concise error or recovery message.
7. Keeps the fail-stop behavior: DMA and hardware faults trigger a reset and
   require a successful anchor test before another run.
8. For B32, adds the hybrid classification result: predicted class,
   confidence, top three, and separate FPGA, processor and combined timing.

## Implementation boundary

The GUI calls the strict profile loader and runtime rather than reimplementing
register access. A small service layer serializes hardware operations, stores
results under the established result directory, and returns image and metric
data to the browser.

Every generated feature map is rendered as a compact thumbnail. Selecting one
opens an enlarged viewer with a direct PNG download. The runtime still computes
and verifies all K channels. Sobel, identity and blur parameter presets remain
a post-competition extension; they are not presented as part of this fixed
qualified-profile release.

## Qualification state

Host:

- Seven focused API tests pass: catalog and image admission, traversal
  rejection, production authentication, job submission, deterministic resize
  dispatch, all-channel result admission, and security headers.
- Python and JavaScript syntax checks pass.
- Desktop browser rendering was inspected; responsive overflow fixes were
  applied for narrow viewports.

Board:

- The authenticated service is installed and reachable over direct Ethernet.
- A normal uploaded PNG was decoded, converted, resized and executed through
  D640 for three frames. All four feature-map previews were rendered.
  Accelerator-path median/p95 were 3.735/3.750 ms and the PS-observed
  whole-call median was 155.012 ms. The run was correctly labelled
  `UNVERIFIED` because no slow D640 PS exact reference was requested.
- The gallery exposes every generated channel, opens a selected channel in an
  enlarged dialog, and supports direct PNG download.
- A true power cycle automatically restored the static `192.168.0.3/24`
  network, the authenticated service, FPGA Manager, both UIO devices and
  `/dev/udmabuf0`; no terminal recovery was performed.
- From that cold boot, the GUI ran the B32 verified sample for three
  bit-identical frames and reported PASS. All 16 channel maps were rendered.
  Accelerator-path median/p95 were 0.126/0.145 ms and the whole-call median was
  2.912 ms. The evidence archive, its 24-entry checksum manifest and the
  screenshot are documented in
  [evidence/cold_boot/QUALIFICATION.md](evidence/cold_boot/QUALIFICATION.md).
- The 50-image CIFAR-10 library (five official samples per class) is installed
  on the board. Its 50 D640 golden outputs are stored as SHA-256 oracles,
  saving about 123 MB compared with raw tensors. Catalog admission is bound to
  the source, canonical resize, padded payload, profile and build, parameter
  bundle and output identities. D640 uses the precomputed references; the
  32×32 profiles compute the exact reference during the run. Unknown and
  uploaded D640 images remain `UNVERIFIED`.
- A live B32 run of `ship_03.png` passed the FPGA reference and classified
  Ship at 98.8%, with all 16 feature maps available. See
  [evidence/hybrid_classification/QUALIFICATION.md](evidence/hybrid_classification/QUALIFICATION.md).

## Remaining release engineering

- Bake the current GUI, decoder policy, classifier, service startup links and
  static network configuration into a fresh reproducible PetaLinux image. The
  current board installation persists on ext4 but was applied after imaging.
- Capture one GUI-driven D640 catalog image reporting `PASS`. This was the next
  physical gate when the library update was packaged, and `evidence/` holds no
  record of it yet.
- Optional extended assurance: drive each of the other four profile switches
  through the GUI and capture their anchors, then surface the already-qualified
  malformed-bundle, identity and DMA-fault recovery paths as explicit GUI
  acceptance tests.
