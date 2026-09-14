# B32_CFGLUT125 runtime qualification — 2026-09-14

Status: runtime provisioning and initial anchor-exact board activation PASS;
the full Gate 3.3 soak, extremes, switching, power-cycle, and fault/recovery
sequence remains incomplete.

## Runtime provisioning

- Board runtime archive:
  `B32_CFGLUT125_board_runtime_3eb5074.tar.gz`
- Archive SHA-256:
  `6779f85967ebd428113eb6219a85561f4400b68bc45aa9f151d8d4f40f60a3b0`
- Transfer path: SD-card FAT boot partition, then `/boot` on the board.
- Pre-install board backup:
  `/home/petalinux/release_checkpoints/G3_pre_runtime_20180309T125402Z.tar.gz`
- Backup SHA-256:
  `bbeb4fc3061856fec509f4228a5113646465d4505be17b3ada088aee73b035a3`
- Installed home-runtime files verified byte-for-byte: 41.
- Installed FPGA-manager firmware:
  `/lib/firmware/m7_B32_CFGLUT125.bin`
- Firmware SHA-256:
  `4e827310eb7f1e8c9278d0c9b36905eb4b7c766d9878a3a551e1909843d5b73b`

The board RTC is not initialized, so names containing `20180309` are board
timestamps rather than qualification dates.

## Release-to-bundle runtime correction

The first M8 attempt failed before hardware access because `m8_cli.py`
derived the parameter directory from the release name
`B32_CFGLUT125`. The release catalog correctly binds this hardware release to
the shared `B32` parameter bundle. `run`, `soak`, and `extremes` now resolve
the catalog's `bundle_dir` before admission and record that directory in the
run record.

- Corrected board `m8_cli.py` SHA-256:
  `ace18ea4bae15b998a9239ddf7cd2516c0db37f5bfd3cf3266d3e1dd2df99129`
- Focused host profile regression suite: 10 tests PASS.
- The failed pre-fix attempt did not open or mutate hardware.

## Initial live activation

Command:

```text
sudo -n python3 -B /home/petalinux/m8_cli.py run --profile B32_CFGLUT125 --frames 3
```

Observed:

```text
admitted B32_CFGLUT125 parameter bundle 952cb13ce0adad04
live build already B32_CFGLUT125: parameter re-admission only
[B32_CFGLUT125] activation OK 0.142 ms sha=5821c8b19a88fd34
cleanup: final STATUS 0x00000181
M8 RUN 20180309T131241Z-B32_CFGLUT125-library_alley_cat: PASS
(3 frames, median 0.129 ms)
```

The complete expected output SHA-256 is
`5821c8b19a88fd34e3002dd7b0c7d60c7fcd79b8a61a326697d95b6e3ec3be94`.
The switch manager correctly took the parameter-only path because the live
BUILD_ID already matched `EF125K16N3W32R01`.

The archived board run record is
`/var/lib/conv-lab/results/20180309T131241Z-B32_CFGLUT125-library_alley_cat/record.json`.

## Numerical extremes and high shifts

The M8 extremes harness was extended before this run so the research build is
tested live at every shift from 24 through 31. Shift 24 is required to produce
both signed `+1` and `-1`; shifts 25 through 31 are required to produce exact
zero through the half-up/sign-extension path. The harness also retains the
all-zero, all-255, signed-24 bias endpoint/saturation checks, and finally
reinstalls the canonical B32 parameters and verifies their anchor again.

- Qualified board `m8_cli.py` SHA-256:
  `798c26f7834d8cb4c5f4ac404b0b333aa77b4e1b7d02647d282068fa384bb1ce`
- Focused host profile regression suite: 11 tests PASS.
- Board result: 12 verified stimulus frames PASS.
- Activation before the procedural stimuli: 0.146 ms, anchor prefix
  `5821c8b19a88fd34`.
- Cleanup status: `0x00000181`.
- Archived run record:
  `/var/lib/conv-lab/results/20180309T131821Z-extremes-B32_CFGLUT125/record.json`.

Observed terminal summary:

```text
M8 EXTREMES 20180309T131821Z-extremes-B32_CFGLUT125: PASS
(12 verified stimulus frames)
```
