# Settings-check repair: already-applied project

Current recovery handoff: **run the repaired evaluated-settings check ONLY**.
The user reports application already completed, rootfs regeneration succeeded and
CONFIG_conv-lab-validation=y survived. Do not rerun preflight.py, apply.py, configuration
regeneration, package/image builds or hardware operations for this retry. Keep the existing
application receipt unchanged. The full original workflow below is historical guidance for
initial application, not this repair's command sequence.

## Failure and repair

The old helper retained its output-directory argument while sourcing setup scripts. The supplied
transcript shows settings.sh reporting /home/walid/projects/M2P_build.bwr25ZCI as PETALINUX.
The same inherited positional argument reached oe-init-build-env; default Poky local.conf and
bblayers.conf were created in the selected wrong build location. The exact accidental paths must
be confirmed read-only below. Rootfs regeneration and all 76 stage checksum checks passed before
this failure. Neither package nor image build was reached, according to the supplied execution.
No assistant-run setup, settings evaluation or build is claimed.

The repaired helper saves validated arguments in private variables, clears positional arguments
before each no-argument source, asserts the fixed tool installation, and discovers exactly one
existing project SDK setup file. It retains SDK host tools/PATH/sysroots but clears SDK/inherited
directory routing variables BDIR/BUILDDIR/OEROOT/BITBAKEDIR/BBPATH before explicitly initializing
/home/walid/projects/zedboard_linux/build. BDIR can override the explicit positional argument,
so passing the directory alone is insufficient. LD_LIBRARY_PATH is unset before and after SDK
setup. SDK compatibility checks are retained, including OECORE_SDK_VERSION/OE_SKIP_SDK_CHECK;
no bypass is introduced.

Both existing project configuration files must already be readable and nonempty, and bblayers.conf
must include the project's meta-user layer. Their hashes are compared across setup. Missing or
changed files stop the helper; it never offers default regeneration. PWD/BUILDDIR/BBPATH,
PETALINUX and PROOT must match the intended context before any bitbake -e invocation.
Fresh empty output, noclobber, all six evaluations and the unchanged check_settings.py dependency,
codec, provider, target and image checks remain required. Setup return codes and shell failure
options are checked/restored after each sourced script.

The discovery report does not contain installed settings.sh/SDK/oe-init script bodies. The supplied
transcript proves observed argument leakage; upstream source explains the directory precedence
and default-copy behavior. Installed vendor source identity is not asserted. Reference:
[Poky scarthgap oe-init](https://raw.githubusercontent.com/yoctoproject/poky/scarthgap/oe-init-build-env),
[directory/SDK handling](https://raw.githubusercontent.com/yoctoproject/poky/scarthgap/scripts/oe-buildenv-internal),
[default configuration setup](https://raw.githubusercontent.com/yoctoproject/poky/scarthgap/scripts/oe-setup-builddir).
If a vendor-specific guard fails, preserve its exact error and request only the relevant setup-script
lines; do not weaken checks or repeat a broad discovery inventory.

## Read-only diagnosis — Ubuntu

This locates configuration under the known old log directory and project, prints hashes and
confirms the intended existing files. It performs no setup or edits. Preserve everything found.

~~~bash
find /home/walid/projects/M2P_build.bwr25ZCI /home/walid/projects/zedboard_linux \
  -maxdepth 4 -type f \( -path '*/conf/local.conf' -o -path '*/conf/bblayers.conf' \) \
  -print -exec sha256sum '{}' \;
ls -l /home/walid/projects/zedboard_linux/build/conf/{local.conf,bblayers.conf}
grep -nF '/home/walid/projects/zedboard_linux/project-spec/meta-user' /home/walid/projects/zedboard_linux/build/conf/bblayers.conf
~~~

Do not delete, overwrite or move the old /home/walid/projects/M2P_build.bwr25ZCI directory or any
accidentally created configuration. If intended configuration is absent/default, stop for diagnosis.

## Transfer the fresh snapshot — Windows

Snapshot: D:\MyProjects\Convlution_Accelerator\deploy\petalinux_snapshots\M2P_settings_check_20260910_175012_366_656e1059
The snapshot is separate from the live stage and earlier evidence. Package it under a new filename:

~~~powershell
$snapshot = 'D:\MyProjects\Convlution_Accelerator\deploy\petalinux_snapshots\M2P_settings_check_20260910_175012_366_656e1059'
$name = 'M2P_settings_check_' + [guid]::NewGuid().ToString('N') + '.zip'
$archive = Join-Path 'C:\VMShare' $name
Compress-Archive -LiteralPath (Join-Path $snapshot 'petalinux') -DestinationPath $archive
$hash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($archive + '.sha256', $hash + '  ' + $name + [char]10, [Text.UTF8Encoding]::new($false))
Write-Output $archive
Write-Output $hash
~~~

Transfer the ZIP and its sidecar using the existing VMShare arrangement; do not assume its Ubuntu
mount location. Do not overlay the previous transferred stage or install recipe files again.

## Verify and run the repaired check only — fresh Ubuntu Bash terminal

Enter the actual transferred ZIP path. Both extraction and check output use new directories.
The log is beside the empty check-output directory so it does not violate freshness checks.

~~~bash
set -e -o pipefail
read -r -p "Absolute Ubuntu path to the repaired ZIP: " ARCHIVE
test -f "$ARCHIVE"
test -f "$ARCHIVE.sha256"
(cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE").sha256")
TRANSFER=$(mktemp -d "$HOME/M2P_settings_transfer.XXXXXXXX")
unzip -q "$ARCHIVE" -d "$TRANSFER"
STAGE="$TRANSFER/petalinux"
(cd "$STAGE" && sha256sum -c SHA256SUMS.txt)
CHECK_OUTPUT=$(mktemp -d /home/walid/projects/M2P_settings_retry.XXXXXXXX)
printf 'Check output: %s\nLog: %s.log\n' "$CHECK_OUTPUT" "$CHECK_OUTPUT"
bash "$STAGE/check_build_settings.sh" "$CHECK_OUTPUT" 2>&1 | tee "$CHECK_OUTPUT.log"
~~~

Stop after this check and retain its outputs whether it passes or fails. Do not regenerate the
application receipt, run preflight/apply again, or chain a build command onto this retry.
Successful settings evaluation would establish settings only; builds and ARM qualification
still require separate execution evidence.

---

# M2-P offline integration — ready for user application

Concrete recipes and guarded helpers are finalized. **Application, evaluated settings, builds,
installed launchers and ARM tests have NOT RUN.** Follow the numbered batches below in order.
This is the first offline package integration, not whole M2-P acceptance.

The existing project is /home/walid/projects/zedboard_linux with PetaLinux 2025.2.
Keep the tested legacy hardware and 1-MiB DMA allocation; later approved 4-MiB/22-bit integration
remains scheduled. No XSA import, DT/UIO/kernel/module/IRQ edits, DMA backend, FPGA Manager action,
auto-starting service, new account or device-permission changes are included.

## Package contents

| Package | Installed content | Runtime dependencies |
| --- | --- | --- |
| conv-lab 0.2.0 | /opt/conv-lab/app/conv_lab, fixed launch.py and user-invoked wrappers; documentation | python3-core, python3-modules, python3-pillow |
| conv-lab-starter 1.0 | unchanged converted N3/K8 model and one-image dataset under /opt/conv-lab/library; separate provenance notice | none |
| conv-lab-validation 0.2.0 | /opt/conv-lab/app/tests (sibling of conv_lab), separate audit/evidence and installed hashes; test wrapper | conv-lab, conv-lab-starter, python3-modules |

The 47 original copied source/assets remain byte-identical, including all 29 app/test Python files.
WORKDIR-based unpacking is supported by the recorded classes. Inactive .bb.in files remain only
as historical source templates; APPLICATION_PLAN.json excludes them from Ubuntu application.
No application semantics, bundle bytes, conversion outputs or coefficient parameters are changed.

[DEPENDENCIES.md](DEPENDENCIES.md) records provider/version/appends/codec evidence and licenses.
Team app/tests use the approved CLOSED classification. Starter provenance/redistribution remains
unresolved and explicitly separate; no CLOSED label is applied to the third-party image.
[COPY_MAP.json](COPY_MAP.json) retains source associations. [APPLY.md](APPLY.md) defines transaction,
original/post hashes and scoped rollback. [EVIDENCE.md](EVIDENCE.md) links immutable host evidence.

## 1. Package and transfer — Windows, user executes

This creates a uniquely named ZIP and checksum beside the existing shared transfer files; it
does not package the workstation environment or modify the stage.

~~~powershell
$repo = 'D:\MyProjects\Convlution_Accelerator'
$packageName = 'M2P_final_' + (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N') + '.zip'
$archive = Join-Path 'C:\VMShare' $packageName
Compress-Archive -LiteralPath (Join-Path $repo 'deploy\petalinux') -DestinationPath $archive
$archiveHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash.ToLowerInvariant()
[IO.File]::WriteAllText($archive + '.sha256', $archiveHash + '  ' + $packageName + [char]10, [Text.UTF8Encoding]::new($false))
Write-Output $archive
Write-Output $archiveHash
~~~

Make those two files available in Ubuntu using the existing VMShare mount/transfer arrangement.
No mount path is assumed. In an Ubuntu Bash terminal, enter the ZIP's actual absolute path:
this verifies the transferred bytes, extracts only into a new external directory, and verifies
the complete stage before any helper is run.

~~~bash
set -e -o pipefail
read -r -p "Absolute Ubuntu path to the transferred M2P ZIP: " ARCHIVE
test -f "$ARCHIVE"
test -f "$ARCHIVE.sha256"
(cd "$(dirname "$ARCHIVE")" && sha256sum -c "$(basename "$ARCHIVE").sha256")
RUN=$(mktemp -d "$HOME/M2P_apply.XXXXXXXX")
unzip -q "$ARCHIVE" -d "$RUN"
export STAGE="$RUN/petalinux"
test -f "$STAGE/SHA256SUMS.txt"
(cd "$STAGE" && sha256sum -c SHA256SUMS.txt)
printf 'RUN=%s\nSTAGE=%s\n' "$RUN" "$STAGE"
~~~

Keep this terminal and RUN/STAGE values. Do not extract into the project, an older stage or recovery.

## 2. Preflight, verified backup and application — Ubuntu owner, no sudo

Stop concurrent project editors/builds. The first command is read-only; the second independently
rechecks, creates/verifies its unique external backup, adds only the three recipe directories and
two selection lines, and prints an APPLIED receipt on success.

~~~bash
export PROJECT=/home/walid/projects/zedboard_linux
python3 -I -B "$STAGE/preflight.py" --project "$PROJECT"
python3 -I -B "$STAGE/apply.py" apply --project "$PROJECT" | tee "$RUN/application.log"
~~~

Expected preflight success is exit 0, not the old deliberate exit 2. On failure stop; do not
overwrite configs or remove collisions. Save the exact APPLIED/FAILED_PARTIAL receipt path.
[APPLY.md](APPLY.md) provides recovery; all backups and quarantines are retained.

## 3. Regenerate selection and check evaluated package settings — Ubuntu

The project discovery identifies the installed tool root, SDK layers and source package menu.
Regenerate only rootfs selection, then retain the resulting configuration and confirm the
validation selection survived. The helper's immediate post hashes remain recorded separately.

~~~bash
source /home/walid/petalinux/2025.2/settings.sh
cd "$PROJECT"
petalinux-config -c rootfs --silentconfig 2>&1 | tee "$RUN/rootfs-config.log"
grep -Fx 'CONFIG_conv-lab-validation=y' project-spec/configs/rootfs_config
cp --preserve=mode,timestamps project-spec/configs/rootfs_config "$RUN/rootfs_config.after-regeneration"
sha256sum project-spec/configs/rootfs_config project-spec/meta-user/conf/user-rootfsconfig > "$RUN/config-after-regeneration.sha256"
~~~

The report's local.conf includes generated plnxtool.conf/petalinuxbsp.conf and locked/unlocked
signatures, whose evaluated effects are not fully supplied. This single focused batch resolves
the six relevant recipe/image environments without building tasks. It discovers exactly one
existing project SDK environment filename; it does not guess an AArch64 SDK for this ARM board.

~~~bash
bash "$STAGE/check_build_settings.sh" "$RUN"
~~~

If this fails, retain the exact error/env file for the affected setting. Do not broaden inventory,
change hardware or suppress license checks. Expected target is zynq-generic/ARM with allarch
application packages, Python 3.12.11, Pillow 10.3.0, JPEG/zlib enabled, WORKDIR unpacking and the
reviewed dependencies/image selection. Parsing may write ordinary BitBake caches; it is not a build.
The checks establish evaluated settings only, not built codec functionality.

Syntax follows this recorded PetaLinux 2025.2 eSDK project layout and AMD's
[rootfs regeneration examples](https://docs.amd.com/r/2025.2-English/ug1144-petalinux-tools-reference-guide/petalinux-config-c-COMPONENT-Examples)
and [BitBake environment workflow](https://docs.amd.com/r/2025.2-English/ug1144-petalinux-tools-reference-guide/Steps-to-Access-the-BitBake-Utility?contentId=f9GuqsiFsJcbXISHzdqJ9g).
The ARM SDK filename is discovered locally rather than copied from AMD's different-board example.

## 4. Build packages, then the image — Ubuntu, only after batch 3 passes

This first resolves/builds the three packages and target runtime through the validation dependency
chain, then builds the system image; it does not package a boot image or flash/program a board.

~~~bash
cd "$PROJECT"
petalinux-build -c conv-lab-validation 2>&1 | tee "$RUN/package-build.log"
petalinux-build 2>&1 | tee "$RUN/image-build.log"
~~~

Commands use the supported [PetaLinux component/image build interface](https://docs.amd.com/r/2025.2-English/ug1144-petalinux-tools-reference-guide/petalinux-build-Command-Line-Options).
Keep logs, the exact package/image/license manifests and image hashes. Confirm the image manifest
includes conv-lab, conv-lab-starter, conv-lab-validation, python3-modules and python3-pillow.
A dependency/license/QA failure is a failure to resolve, not permission to change app behavior.
This is an incremental user build; no clean-rebuild reproducibility claim is made.
No clean/cleanall/mrproper commands are required. Builds may regenerate output artifacts;
they do not authorize selecting a generated bitstream for boot.

## 5. Boot-artifact gate before media deployment

Imported system.xsa is the older handoff. Never use images/linux/system.bit by default.
Preserve the tested len16 BOOT.BIN for a compatible software-only assembly, or separately review
explicit boot packaging with the designated hash-matched artifact:

k8_gp0_ila_len16_2026-09-06.bit
SHA256: 22097a5e3a1640fdc2505821c800c4df363d5e3390df02ee27d7b079ccdec80d

Immutable Windows location:
D:\MyProjects\release_checkpoints\M0_k8_len16_20260907_052648_358\current_project\bitstreams\k8_gp0_ila_len16_2026-09-06.bit

~~~bash
: "${TESTED_BIT:?Set the exact preserved named len16 bitstream path}"
test "$(basename "$TESTED_BIT")" = k8_gp0_ila_len16_2026-09-06.bit
printf '%s  %s\n' '22097a5e3a1640fdc2505821c800c4df363d5e3390df02ee27d7b079ccdec80d' "$TESTED_BIT" | sha256sum -c -
~~~

Actual Ubuntu BOOT.BIN/FSBL/U-Boot paths and software assembly compatibility remain the separate
deployment gate. No default --fpga, wildcard fallback, new XSA import, automatic boot packaging
or destructive device-specific flashing command is supplied. Keep M0 recovery independent.
Only after reviewed media deployment and SD boot proceed to batch 6.

## 6. Installed-package and ARM offline validation — board, user executes later

Verify the actual ARM board/interpreter, installed payload hashes and compiled codecs. This
imports target dependencies only when the user runs it; no runtime checks were performed here.

~~~bash
hostname
uname -a
test "$(uname -m)" = armv7l
sha256sum -c /opt/conv-lab/validation/evidence/INSTALLED_SHA256SUMS.txt
/usr/bin/python3 -I -B -c 'import sys,ctypes,fcntl,resource,unittest,pwd,zlib; import PIL; from PIL import Image,features; print(sys.version); print("Pillow",PIL.__version__,"JPEG",features.version("jpg"),"zlib",features.version("zlib")); assert sys.version_info >= (3,11); assert features.check("jpg") and features.check("zlib"); print(Image.Resampling.LANCZOS)'
sudo /usr/sbin/conv-lab-prepare-output
~~~

Packages install immutable files root-owned (0644; executable wrappers 0755) and /var/lib/conv-lab
root:root 0755. The explicit setup command discovers the existing petalinux UID/primary GID and
creates only staging/results/qualification owned by that account, mode 0750. It refuses unexpected
existing ownership/modes/symlinks and does not recursively change ownership or create an account.
No root decoder fallback. Run the following as petalinux without sudo:

~~~bash
test "$(id -un)" = petalinux
test "$(id -u)" -ne 0
conv-lab-offline
conv-lab-tests --group A
conv-lab-tests --group C
conv-lab-tests --group B
~~~

Launchers use fixed /usr/bin/python3 -I -B and /opt/conv-lab/app/launch.py, independent of cwd,
PYTHONPATH and developer checkouts. Tests and conv_lab remain siblings for subprocess imports.
Output goes to /var/lib/conv-lab/qualification; retain every report, failure and actual environment.
The private lock serializes sessions; one worker, 128-MiB address-space ceiling, 30-second
preprocessing deadline, bounded output and 512-MiB free headroom remain enforced. Reference time is
separate. No automatic deletion, world-write, root decoding or larger resource-limit fallback.

First ARM acceptance: offline file/bundle loading, bounded PNG/JPEG decoding and enforced worker
isolation; real trained example 8192 raw signed16 values / 16384 bytes, all four historical domains
matching, output SHA256 cb3975593073652b9d5f2fcb206748ad70c4abf621339ea19878b6863d9be705.
Host evidence does not substitute for these runs. Inspect reports for PASS, skips/failures and
actual resources. DMA inference, cache/MMIO/IRQ mechanisms, safe full-PL switching, whole-library
qualification, clean rebuild and complete M2-P acceptance remain later work.

