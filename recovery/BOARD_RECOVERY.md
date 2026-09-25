# Board recovery baseline

Keep exactly two external recovery payloads:

- `zedboard_B32_CFGLUT125_G3_3eb5074.wic.gz`: the final compatible PetaLinux
  SD image, compressed after byte-hash verification.
- `g5_runtime_20260915T024500Z.tar.gz`: the five-profile runtime overlay.

Verified source hashes before cleanup:

```text
c99781f6e30a651c1fe878e9806f9e6b78a605eb46f0d6315516c0af6265e5f4  zedboard_B32_CFGLUT125_G3_3eb5074.wic
9d92785537f858e5807e39711dc2711496fbf1588838324b028ac7b9683587b3  g5_runtime_20260915T024500Z.tar.gz
```

Restore the SD image by decompressing the WIC and flashing it. Boot the board,
then install the runtime overlay if the filesystem does not already contain the
five final firmware images and profile bundles. After recovery, verify the live
hardware identity, run each profile's anchor, and repeat a short switching test
before using the board for demonstrations.

The checksums written beside the recovery files are the authority. Do not use
the older len16, address-fix, reset-fix, M2P, or single-profile transfer files.

## Compressed recovery verification

Verified retained-file hashes after compression:

```text
7ae7b55826c0dafe8ebcc7416a01fc161c144a1ed47d3168cfffb022890a2fb2  zedboard_B32_CFGLUT125_G3_3eb5074.wic.gz
9d92785537f858e5807e39711dc2711496fbf1588838324b028ac7b9683587b3  g5_runtime_20260915T024500Z.tar.gz
```

Streaming decompression of the retained `.wic.gz` reproduced the original WIC
SHA-256 exactly. The 3,158,315,008-byte uncompressed duplicate was then removed.

## Archived cleanup history

These archives preserve material removed from the active tree:

- `legacy_history_20260920.tar.gz`: checkpoints, ILA captures, milestone notes, and logs.
- `release_checkpoints_20260920.tar.gz`: earlier external release checkpoints.
- `vmshare_legacy_20260920.tar.gz`: superseded VMShare transfers and qualification evidence.
- `EXTERNAL_SOURCES.md`: restoration identity for the removed clean teammate clone.

Each archive has a neighboring `.sha256` file and passed an integrity listing before its loose source was removed.
