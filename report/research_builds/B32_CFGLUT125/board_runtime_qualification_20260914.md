# B32_CFGLUT125 runtime qualification — 2026-09-14

Status: runtime provisioning, anchor-exact activation, numerical extremes, and
the 100-frame soak PASS. Repeated baseline/research switching, power-cycle,
and fault/recovery remain incomplete.

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

## 100-frame anchor-exact soak

One activation was followed by 100 frames with no inter-frame reset. Every
frame matched the frozen B32_CFGLUT125 output anchor.

- Activation: 0.143 ms, anchor prefix `5821c8b19a88fd34`.
- Progress checks: 25/100, 50/100, 75/100, and 100/100 bit-exact.
- Hardware latency: median 0.125 ms, p95 0.128 ms.
- Final cleanup STATUS: `0x00000181`.
- Archived run record:
  `/var/lib/conv-lab/results/20180309T132021Z-soak100-B32_CFGLUT125-library_alley_cat/record.json`.

Observed terminal summary:

```text
M8 SOAK 20180309T132021Z-soak100-B32_CFGLUT125-library_alley_cat: PASS
(100 frames, median 0.125 ms / p95 0.128)
```

## Retrieved schema-v3 evidence

The three complete run directories were packaged on the board, copied from
the FAT boot partition, and verified on the Windows host. The original
transport archive is preserved alongside the extracted records.

- Transport archive:
  `B32_CFGLUT125_G3_records_20260914.tar.gz`
- Archive SHA-256:
  `f9a36cde5ada13af40f1c91f85bd1d81d415ed6982110fc042773552c753038e`
- Extracted evidence directory: `board_records_20260914/`.
- Internal checksum manifest: PASS.
- Manifest hardware release: `B32_CFGLUT125`; three runs.

Record hashes:

| Run | Frames | `record.json` SHA-256 |
|---|---:|---|
| `20180309T131241Z-B32_CFGLUT125-library_alley_cat` | 3 | `70d4cc728cb0378f3b7af75f25e107b3d336acd26665650d6733720bc66a48e3` |
| `20180309T131821Z-extremes-B32_CFGLUT125` | 12 | `e1ac710ee6b31ae4e9b8174657fb248926b3f536d1dad0b0c7213bd4015dddd9` |
| `20180309T132021Z-soak100-B32_CFGLUT125-library_alley_cat` | 100 | `3815ba560b12d2378fef2255d0b2ff4d8c94f5b4dbc1821372ea8a89c4c67566` |

All three records use schema `m8-run-record/3`, outcome `PASS`, profile
`B32_CFGLUT125`, and record `reloaded=false`, as expected for tests run while
the research image was already live.

## A32 recovery inventory and clock-safety decision

The missing A32 runtime inventory was restored without accessing the FPGA or
DMA. The installation used a verified 11-file payload and created this
pre-install recovery archive:

- Recovery archive:
  `/home/petalinux/release_checkpoints/A32_pre_restore_6f6742bc1bde4d43a2a3d9d6519c356e.tar.gz`
- Recovery SHA-256:
  `e93acaef69395e7c58b041181df0ae1e76e8749c492d8eae631b780d32818018`
- Installed A32 firmware SHA-256:
  `b59378e4918f3c128d0d787546981e58b7508085c916780a21fef5db3a04130b`
- Installed A32 manifest SHA-256:
  `31c96657b4208f6e36350a476bb8c8213528bb1d3a2476ad5099f68b1dc032f9`
- Admitted A32 bundle SHA-256:
  `367fb1f5a45a3271c2967ae4f0cadb1b50661470dc4df50496dbf36dce895469`

Inventory restoration is PASS. Reconfiguration was deliberately withheld:
`m7_switch.py` programs only the PL image and does not reconfigure PS FCLK0.
This boot supplies 125 MHz, whereas A32 is routed and qualified for 100 MHz
(reported Fmax approximately 100.7 MHz). Loading A32 here would therefore be
an unqualified overclock. The safe comparison/switching route is a common
100 MHz boot using A32_MAC100 and the same-source `B32_CFGLUT100` research
release. `B32_CFGLUT125` remains the separately qualified performance release.
