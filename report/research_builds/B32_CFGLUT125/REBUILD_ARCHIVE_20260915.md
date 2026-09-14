# B32_CFGLUT125 uniform-provenance rebuild — archive record (2026-09-15)

Per AI_HANDOFF.md §19.6, the older full B32 work directory and its final
artifacts were preserved before the uniform generalized-source rebuild.
Nothing was deleted; every preserved item is hash-verified.

## 1. Pre-archive verification of board-qualified evidence

The three board-qualified B32 artifacts were re-hashed and match the §18.2
records exactly:

- `bitstreams/b32_cfglut125_125mhz.bit`
  SHA-256 `133713c5eca1f8a41a7baa40719e1c101364f3a835111028db925a7d7a309858`
- `bitstreams/b32_cfglut125_125mhz.bit.bin`
  SHA-256 `4e827310eb7f1e8c9278d0c9b36905eb4b7c766d9878a3a551e1909843d5b73b`
- `bitstreams/b32_cfglut125_125mhz.xsa`
  SHA-256 `e90b84413bf35d8da2aa5b5a86b5ea41e2519360fd593b60c9f3a918544f648d`

The tracked board evidence under `report/research_builds/B32_CFGLUT125/`
(G3 records tarball, board records, boot identity, runtime qualification,
build manifest) is unchanged.

## 2. Old work directory archived (§19.6 step 2)

- Source: `work/research_B32_CFGLUT125/` — 787 files, 200 MB, exactly the
  count documented in §19.6.
- SHA-256 manifest of all 787 files:
  `work/archive/b32_work_dir_20260914T231157Z_SHA256SUMS.txt`
  (SHA-256 of the manifest itself:
  `dc7a44393a669a62a669b58e89cf496b0a5934f63483a3087be1faf4176fa574`)
- Compressed archive:
  `work/archive/research_B32_CFGLUT125_pre_rebuild_20260914T231157Z.tar.gz`
  (SHA-256:
  `dbb6487216a2e7e0b1353c388b4927e5601209edd00870f2e64523c01f4accda`;
  1,136 entries = 787 files + 349 directories)
- Verification: the tarball was extracted and all 787 file hashes compared
  against the manifest — every hash matched.
- The original directory was then moved (not copied/deleted) to
  `work/archive/research_B32_CFGLUT125_old_20260914T231157Z/`.

`work/` is not tracked by git; the tarball, manifest and moved directory are
on-disk recovery state.

## 3. Board-qualified artifacts preserved under dated names (§19.6 step 3)

Copies (never moves) placed at `bitstreams/history/20260914_b32_board_qualified/`
with an in-directory `SHA256SUMS.txt`
(SHA-256 `190ca1d0935eec7e7346e6caf668458ff7c9a93ddba037f326a542efb94c9649`):

- `b32_cfglut125_125mhz.bit` — `133713c5eca1f8a41a7baa40719e1c101364f3a835111028db925a7d7a309858`
- `b32_cfglut125_125mhz.bit.bin` — `4e827310eb7f1e8c9278d0c9b36905eb4b7c766d9878a3a551e1909843d5b73b`
- `b32_cfglut125_125mhz.xsa` — `e90b84413bf35d8da2aa5b5a86b5ea41e2519360fd593b60c9f3a918544f648d`

The canonical paths in `bitstreams/` remain untouched at this checkpoint;
they will be replaced only after the rebuilt B32 passes full acceptance with
hash-verified new copies.

## 4. Rebuild render prepared (§19.6 step 4)

`research_release.py prepare B32_CFGLUT125` re-rendered the build tree:
`work/research_B32_CFGLUT125/` now contains only `src/config_pkg.vhd`, SHA-256
`1e24e3a823d1a940378f19d708cbabdecce93e982a9a91c639c46ccce07e3f0d` —
byte-identical to the required §19.6 value and to the earlier qualified
build's render. Spec check: `N3K16W32H32-CVH1`, 125 MHz, build ID
`EF125K16N3W32R01` (`45463132354b3136…`), catalog bundle binding
`952cb13ce0adad04…`.

## 5. Old qualification status

The older B32 routed/board-qualified 125 MHz evidence remains historical
proof for that exact artifact set (hashes above). The rebuilt B32 gets no
qualification credit from it; fresh build binding and board gates apply.
