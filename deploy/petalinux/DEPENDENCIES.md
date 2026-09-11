# Resolved packaging dependencies

Status: ready for user application; evaluated settings, build and ARM execution NOT RUN.

The supplied discovery report is preserved at evidence/recipe_discovery.json.
SHA256: 618b951d9f4e5c1acb73a270f63b16af617de4b863151e3012e3dac6ea1a5bfd.
Its recorded file contents and configuration originals were checked against their recorded hashes.
Filesystem evidence supports these concrete recipes; it is not evaluated BitBake evidence.

| Item | Recorded evidence / selection |
| --- | --- |
| Python | poky/meta/recipes-devtools/python/python3_3.12.11.bb, PSF-2.0 |
| Standard library | python3-modules is defined through python3/python3-manifest.json; recipe creates PACKAGES/RDEPENDS and ALLOW_EMPTY for it |
| Pillow | meta-openembedded/meta-python/recipes-devtools/python/python3-pillow_10.3.0.bb, HPND; SRCREV 5c89d88eee199ba53f64581ea39b6a1bc52feb1a |
| Codecs | Pillow PEP517_BUILD_OPTS explicitly enables jpeg and zlib; DEPENDS includes jpeg and zlib (also tiff/freetype/lcms/openjpeg) |
| App runtime | RDEPENDS = python3-core python3-modules python3-pillow |
| Validation runtime | RDEPENDS = conv-lab conv-lab-starter python3-modules |
| Unpack | recorded poky meta/classes-global/base.bbclass uses fetcher.unpack(WORKDIR); new recipes use S = WORKDIR |
| Architecture | allarch for the three pure source/data recipes; target Python/Pillow remain ARM packages |
| Registration | project-spec/meta-user/conf/layer.conf includes recipes-*/*/*.bb, priority 7, scarthgap; meta-user appears in recorded build/conf/bblayers.conf |

python3-modules intentionally trades image/storage footprint for reliable standard-library coverage
in this initial validation image. Its dependencies include core, ctypes, fcntl, resource, unittest,
unixadmin, compression, json and the other standard-library groups. It also brings functionality
not used by this application (for example tkinter, venv and ensurepip); selecting it does not authorize
pip downloads or require using them. Measure resulting image/storage/RAM headroom. A reduced split
set requires separate validation; no workstation environment, wheels or binaries are copied.
No runtime NumPy/PyTorch or expected .hex input is required.

Inspected app/worker/test imports include argparse, collections, contextlib, copy, ctypes, dataclasses,
datetime, fcntl, fractions, hashlib, importlib, io, json, math, os, pathlib, platform, pwd (launcher),
random, re, resource, selectors, shutil, signal, stat, struct, subprocess, sys, tempfile, threading,
time, traceback, unittest/mock, uuid, warnings, weakref, zipfile, zlib and Pillow. Tests remain beside
conv_lab under /opt/conv-lab/app; fault_worker.py relies on this parent layout. Missing worker/resource
enforcement must fail closed. No changes to the tested Python sources are made.

## Relevant overrides and remaining evaluated check

Recorded BBLAYERS includes poky/meta, meta-python, meta-user, meta-ros-common, meta-microblaze and
meta-petalinux. Matching python3_%.bbappend files are:
- meta-ros-common: update-alternatives for python/python-config (does not redirect our explicit python3 launcher).
- meta-microblaze: static-library FILES addition under the microblaze override (not an ARM setting).

No matching Pillow append appears in the supplied records. Observed meta-aws masks affect boto
recipes; meta-petalinux masks affect ROS fuse/babeltrace; the virtualization mask affects device-tree.
None of those masks targets these packages. Other dynamic layer logic is not assumed evaluated.

build/conf/local.conf has a qemu-zynqmp weak default followed by MACHINE = zynq-generic.
It includes locked-sigs.inc, unlocked-sigs.inc, plnxtool.conf and petalinuxbsp.conf; their evaluated
effects are not fully supplied. This is why README batch 3 checks actual recipe providers, ARM
target, allarch handling, dependencies, image selection and codec options using saved bitbake -e
output. It is one focused package-setting gate, not another discovery inventory or an excuse to
leave templates unfinished. A changed evaluated version/override requires review, not silent pinning
or editing vendor recipes. Target Pillow is not pinned to host Pillow 12.2.0.

## License classification

The user explicitly approved LICENSE = CLOSED for the team-owned conv-lab application and
conv-lab-validation tests. No conflicting existing license was found in those copied payloads.
This classification grants no additional rights. Existing documentation/evidence remains unchanged.

The starter package is deliberately separate and does NOT use CLOSED. Its concrete local identifier
LicenseRef-ConvLab-Starter-Provenance-Unresolved names the preserved unresolved provenance status;
LIC_FILES_CHKSUM and NO_GENERIC_LICENSE reference PROVENANCE-NOTICE.txt. That notice is installed
outside immutable bundles and explicitly grants no permission. The user's internal validation
packaging request is fulfilled; model training provenance and image/dataset redistribution clearance
are not established. This is not a redistributable cleared release. No legal determination is made.

Python/Pillow/codecs retain vendor recipe licenses and notices. Review eventual build license/package
manifests. Do not suppress license checks, relabel third-party material CLOSED, or treat the archived
driver's BSD notice as a license for unrelated application/data.

The recipe-specific notice copying uses Yocto's documented [NO_GENERIC_LICENSE mechanism](https://docs.yoctoproject.org/5.0.11/dev-manual/licenses.html#copying-non-standard-licenses); this machinery does not establish missing asset rights.
