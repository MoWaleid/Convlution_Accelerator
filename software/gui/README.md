# Convolution Lab board GUI

This is the browser interface for the five qualified 125 MHz accelerator
profiles.  It wraps `m8_cli.py`; it does not duplicate FPGA programming, DMA,
parameter admission, output verification, or result archiving.

## Demo workflow

1. Choose a qualified hardware profile.
2. Choose a PNG/JPEG from the board library, use the verified sample, or upload
   a file from the browser.
3. Run 1, 3, 10, or 20 frames.  The board decodes the image in the bounded
   unprivileged worker, applies EXIF orientation, converts it to grayscale,
   and resizes it to the selected profile geometry with deterministic LANCZOS.
   The CLI retains `--image-policy exact` for strict qualification checks.
4. Inspect the outcome, timing, hashes, and every display-normalized output
   feature map.  The compact gallery includes all channels; select any thumbnail
   to open a large viewer and download that channel as a PNG.

The default board image roots are:

- `/opt/conv-lab/library/datasets`
- `/home/petalinux/images`
- `/var/lib/conv-lab/images`

Only signature-matched static PNG/JPEG files no larger than 8 MiB are admitted.
Decoded sources are limited to 4096 pixels per axis and 12,000,000 pixels in
total under a single 256 MiB address-space-limited worker.
Standard grayscale, palette, RGB, grayscale-alpha, and RGBA PNG encodings are
supported; alpha is composited over white and the decision is recorded.  The
JPEG path accepts bounded non-image trailer bytes used by some cameras and
editors, but still rejects an appended JPEG or PNG as a second image.  The
browser receives opaque image IDs and relative display names, never arbitrary
filesystem paths.  Override the roots with repeated `--image-root` arguments or
the `CONV_GUI_IMAGE_ROOTS` path-separated environment variable.

Small-profile image runs are checked against the exact integer reference.
The installed CIFAR-10 demonstration library contains five official sample
images from each of the ten classes.  Every one of those 50 immutable source
files has a precomputed D640 oracle bound to its source hash, resized canonical
bytes, padded DMA payload, hardware build ID, and complete parameter bundle.
A selected catalog image therefore reports `PASS` only when the FPGA output
hash matches its exact golden hash.  Unknown, uploaded, or modified D640 images
remain `UNVERIFIED`; they retain their output SHA-256 and previews and are never
promoted by filename or directory alone.

## Timing labels

`Accelerator path` is the existing `hw_ms` measurement from `m7_switch.py`: a
PS monotonic-clock interval beginning immediately before the MM2S length write
and ending after DMA/accelerator completion polling.  It includes PS register
access and polling overhead, so it is not presented as a pure PL cycle count.

`Whole call` is the existing `wall_ms` interval around `run_frame`; it includes
the complete per-frame software call but excludes profile loading, image
preprocessing, reference generation, and preview rendering.  Benchmark mode
uses ten warm-up frames followed by 100 measured frames by default.

## Run locally without hardware

From the repository root:

```powershell
python -B software/gui/server.py --demo `
  --catalog profiles/m7_profiles.json `
  --profiles profiles `
  --image-root deploy/petalinux/recipes-apps/conv-lab-starter/files/dataset/images `
  --results .gui-demo/results --uploads .gui-demo/uploads `
  --bind 127.0.0.1 --port 8080
```

Open `http://127.0.0.1:8080`.  Demo mode exercises the web application only and
never opens FPGA, DMA, UIO, or firmware interfaces.

Run host tests with:

```powershell
python -B software/gui/test_server.py
```

## Board service

The PetaLinux recipe installs the application under `/opt/conv-lab-gui`, the
complete five-profile runtime under `/home/petalinux`, FPGA-manager firmware
under `/lib/firmware`, and a SysV init script named `conv-lab-gui`.  The starter
recipe installs the 50-image catalog under
`/opt/conv-lab/library/datasets/cifar10-demo/v1`.  The service listens on TCP
port 8080 and restores the direct-link `192.168.0.3/24` address by default.
The self-contained image includes:

- `/home/petalinux/m8_cli.py`
- `/home/petalinux/profiles/m7_profiles.json`
- `/home/petalinux/profiles/hardware_*.json`
- `/lib/firmware/m7_*.bin`

The production service requires HTTP Basic authentication.  Its user is
`conv`; the board generates the password in `/etc/conv-lab-gui.token` during
first service start.  Basic authentication is not encrypted, so the service is
still intended for the isolated competition LAN or a direct Ethernet link, not
an untrusted or Internet-routed network.  Hardware operations are serialized,
subprocesses are invoked without a shell, and all profile/image/result
identifiers are validated before use.  Demo mode disables authentication only
for local host-side preview.
