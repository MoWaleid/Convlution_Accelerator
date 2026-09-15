# FPGA-manager firmware generation — 2026-09-15 (§19.7 steps 1-2)

All five releases: Bootgen v2025.2 (`-arch zynq -process_bitstream bin`),
run on the Windows host from the frozen canonical bitstreams. Each image is
4,045,568 bytes. The proven M6 BIF form was used verbatim (plain path, no
`[destination_device]`); the only extra flag was `-w on` for B32, whose
canonical output already existed (old qualified firmware) — its dated
preservation copy was re-verified immediately before the overwrite.

## Firmware hashes (also bound in software/hardware_<ID>_CFGLUT125.json)

| Release | Firmware (bitstreams/<id>_cfglut125_125mhz.bit.bin) | SHA-256 |
|---|---|---|
| A32_CFGLUT125 | 4,045,568 B | `880505feaa397ac3899ac72fb2237d10fe88865a1c178d98b642265c4461997a` |
| B32_CFGLUT125 | 4,045,568 B | `757595d54cef273d7975f1f7e6ce783e41e0ccafcab8702555ea4a87ddb95dea` |
| C32_CFGLUT125 | 4,045,568 B | `f046eec5ec2a92be12104c02e9608bb34b50a5d4dc467c58faec507ce0716909` |
| D32_CFGLUT125 | 4,045,568 B | `5f83266d38f9d35ebe5e8db6541b86d1a3c58553e4bff5fb5421c64bb9a81692` |
| D640_CFGLUT125 | 4,045,568 B | `20289d5e0405e2e62e46d95db2367a3197434173f8bef6689b5d7e41e2f6ea96` |

Source bitstreams (frozen five-build record, §18.17): A32
`0ddd0a46…5cdc759` (commit `45b35a6`), B32 `2388f249…4b8abcdd` (`b230d02`),
C32 `8108a82f…315d866f` (`9c725cc`), D32 `b02fc59c…2c4786dd` (`fcc3ed1`),
D640 `6e95188e…f41cca3` (`180c2fa`).

## Files in this directory

- `<ID>_CFGLUT125.bif` — exact BIF used (absolute path to the canonical-named
  `.bit`).
- `<ID>_CFGLUT125_bootgen.log` — verbatim bootgen output; every run ends
  `[INFO] : Bootimage generated successfully`.
- `FIRMWARE_SHA256SUMS.txt` — the five hashes above.

The generated `.bit.bin` files themselves are gitignored (`*.bin`); the
tracked hash bindings are the five runtime manifests plus this record.

## Admission (§19.7 step 2)

`scripts/research_release/admit_built_manifests.py` performed fail-closed
admission before writing anything: for each release it required the routed
build manifest identity (release/shape/BUILD_ID/125 MHz/nonnegative slack/
BOARD_VALIDATION=NOT_RUN), catalog release-entry agreement, existence of the
canonical `.bit`/`.xsa`/`.bit.bin`, and canonical-BIT/XSA hashes equal to the
build manifest's recorded artifact hashes. One earlier run correctly refused
to bind when it read the older B32 build's manifest instead of the
`rebuild_20260915/` one; after the path fix all five releases passed and the
manifests were bound:

- `bitstream_sha256` / `firmware_bin_sha256`: canonical 64-hex values above
- `release_status: built-unqualified`
- `deployable: true` — meaning controlled test-loadable only; board
  qualification remains external evidence (§19.7)

The old B32 qualified firmware (`4e827310…`) remains preserved and verified
at `bitstreams/history/20260914_b32_board_qualified/`.

## Host-side regression after the state change

- `verification/m7_profiles/mock_switch_test.py --candidate-undeployable
  profile|soak`: PASS. The mock now fabricates the pre-build candidate state
  in its stage (the repo manifests are legitimately deployable since this
  admission), so the GLM-F7 fail-closed gate stays negatively tested.
- `--profile B32 3` and `--matrix-seq` mocks: PASS (58-switch matrix, all 20
  ordered pairs covered).
- `verification/m8_cli/mock_cli_test.py`: PASS (full suite).
- `software/tests/test_m7_profiles.py`: 12/12 OK.
