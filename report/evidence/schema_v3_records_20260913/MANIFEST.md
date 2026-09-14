# schema_v3_records_20260913 — provenance

Recovered 2026-09-14 from the live board (`/var/lib/conv-lab/results/`) via the
SD FAT boot partition (`/boot`), per the R14/FP-02 evidence-recovery action.
Transport hashes (board-side md5, verified byte-identical on Windows):

| artifact | md5 |
|---|---|
| `r14_recover.tgz` (board `/boot`) | `47dacbe7d71cfc00bda663c2f734c200` |
| `r14_reval.tgz` (board `/boot`) | `ca6b5566b91adad4c2356bd993e39722` |
| `m7_A32_recovered.bin` (board `/boot`, copy of `/lib/firmware/m7_A32.bin`) | md5 `d774c3816c39138ef20866cb3f9784a5`, sha256 `b59378e4918f3c128d0d787546981e58b7508085c916780a21fef5db3a04130b` |

The firmware sha256 equals `firmware_bin_sha256` in the recovered runtime
manifest and in `bitstreams/`-manifest records; it is the qualified A32
firmware whose `.bit` (`8bc60890…`) is otherwise unrecoverable. Archived here
as `bitstreams/m7_A32.bin`; the runtime manifest as `software/hardware_A32.json`
(it carries the width fields required by the current strict manager and is NOT
identical to the historical `software/hardware.json`).

## Contents

- `20260913T051612Z-soak200-A32-library_alley_cat/` — PASS, 200 frames, anchor
- `20260913T051950Z-soak200-B32-library_alley_cat/` — PASS, 200 frames, anchor
- `20260913T052000Z-soak200-C32-library_alley_cat/` — PASS, 200 frames, anchor
- `20260913T052012Z-soak200-D32-aeroplane_s_000002/` — PASS, 200 frames, exact reference
- `20260913T052038Z-soak100-D640-library_alley_cat/` — PASS, 100 frames, anchor
- `20260913T052201Z-soak100-B32-aeroplane_s_000002/` — PASS, 100 frames, exact reference

(the six M9 1,000-frame soak legs — these are the true schema-v3 records the
M9 evidence file summarized)

- `20260913T071249Z-C32… / 071557Z-D32… / 071840Z-D640… / 072133Z-A32…` —
  single-frame sanity runs recorded around the E2 session
- `20260913T070952Z-B32-library_alley_cat/` — **0-byte crashed-run leftover**
  (empty record.json + empty frame file): a pre-R14-02 failure-mode artifact
  where an early error left an allocated run directory with no durable record.
  Retained deliberately as documentation of the defect class the R14-02 repair
  (commit 73bb803) eliminates; note the repair now persists every record
  atomically and fails the invocation on persistence errors.
- `20260913T042145Z-soak5-A32-library_alley_cat/` — repair-batch board
  revalidation soak: PASS, 5 frames, median 0.127 ms, cleanup 0x181
- `20260913T042303Z-A32-alley_cat_s_000013/` — repair-batch board revalidation
  image run: PASS, exact-reference, 2 frames (first runs on the repaired
  m8_cli/m7_switch, md5s `9b38d584…` / `8c87221d…`)

`SHA256SUMS.txt` covers every file in this directory.

## Known gaps / notes

- The five E2 `extremes-*` record directories (04:05–04:07) were not in this
  pull; they remain on the board rootfs (and SD p2) and can be recovered at
  the next board session. Their substance is already summarized in
  `report/evidence/e2_extremes_matrix_20260914.txt`.
- The full E2 matrix console log was never written to disk (m7_switch prints
  to console only); the transcript excerpt stands unless the operator's PuTTY
  session log captured it.
- Record IDs carry the board's un-synced RTC clock (`20260913T04…` for runs
  executed 2026-09-14 UTC); hashes, not timestamps, bind the evidence.
