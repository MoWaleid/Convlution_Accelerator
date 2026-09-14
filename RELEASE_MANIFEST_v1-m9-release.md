# Release manifest — `v1-m9-release`

Baseline freeze of the `v1-bringup` line before research-branch integration
(M10–M12). The tag pins the exact source tree; this manifest binds the
qualified on-disk artifacts and states the release's known limits.

## Reproducibility framing (honest scope)

The M9 gate is "another clean build and documented setup **reproduce
results**". Evidence on record:

- The M7 campaign built **five fresh isolated profile projects** from the
  scripted flow (`scripts/prepare_profile.py` + `scripts/build_profile.tcl`,
  Vivado 2025.2) and qualified every profile on board — a clean build
  reproducing results, five times.
- The live `impl_1` D640 artifact matches its manifest hash
  (`hardware_D640.json` `bitstream_sha256` = `64849132…`), and the D640
  firmware matches `17896ba8…`.
- A bit-identical bitstream re-hash was **not** performed (and is not
  required by the gate); bitstreams are not guaranteed bit-reproducible.

## Qualified artifact hashes (sha256, on-disk at tag time)

| Artifact | sha256 |
|---|---|
| `bitstreams/m7_A32.bin` (qualified A32 firmware, recovered 2026-09-14) | `b59378e4918f3c128d0d787546981e58b7508085c916780a21fef5db3a04130b` |
| `bitstreams/k8_gp0_noila_len22_2026-09-11.xsa` (qualified M4/A32 XSA) | `47a53884ff7529d3979a40d58418b837166c2ebd80bf93d32477a4f2824a503d` |
| `bitstreams/dn3k04_w640480_2026-09-12.bit` (D640, matches manifest `64849132…`) | `6484913270795428dc9c3705e1359f8dcc663a61eb3f63084cfc2f90b9e6aaa5` |
| `bitstreams/dn3k04_w640480_2026-09-12.bit.bin` (D640 firmware) | `17896ba8c291d1b2c2c5480bd6f2bcfabea3f1dc697608501054aac2c0e474f6` |
| `bitstreams/bn3k16_len22_2026-09-12.bit` (B32) | `210d2379317b2f20191f703cf911c7b19c090714e19fa4befb2ea98b0731fde6` |
| `bitstreams/bn3k16_len22_2026-09-12.bit.bin` (B32 firmware) | `f5a5d07fc0015f23f72ef1db93016621dc46d4068e6ad99090295855fb3ee5c2` |
| `bitstreams/cn5k08_len22_2026-09-12.bit` (C32) | `3b1b917d8a2596d8f57616165ebddcc0ccf24125843b90caddcb166ff7549c96` |
| `bitstreams/cn5k08_len22_2026-09-12.bit.bin` (C32 firmware) | `c8b3e0c627804aef6343dba4a855bac2bb86b9fc9e4a92563e3c232f167cfd1f` |
| `bitstreams/dn3k04_len22_2026-09-12.bit` (D32) | `0cf965e37375426b0b5fd7f363b69dbb19672a6b4e10bcbad5722903cb96749a` |
| `bitstreams/dn3k04_len22_2026-09-12.bit.bin` (D32 firmware) | `fc28223877f4a779f251f67c791ee971761470b40d44ba74974b0491ca7ab894` |
| `platform/accelerator_dma.xsa` (historical handoff) | `38da09ba7020f8ddc4502be9ae0dfb1b34dd1e8ac0d10135f389f3a0a3bc7836` |

Note: `*.bit` / `*.bin` are gitignored; these bytes exist on this workstation
and on the SD recovery partition. Checksum-addressed external artifact store
is a Gate-1 deliverable of the integration plan (FP-02 remainder for
B32/C32/D32/D640).

## Known limits at tag time

1. **Numerical scope (R14-01 containment, option b):** the MAC S4 rounding
   add is defective for shifts 24–31 (constant overflows at 24, wraps at 25,
   vanishes at 26+); admission (`load_params`) rejects shift ≥ 24. Shifts
   0–23 are arithmetically safe; 4/7/8/9 are board-qualified. The real fix
   rides the research line (M11).
2. **Throughput:** 4/K output positions/cycle is the 64-bit serializer
   interface ceiling, not a measured rate; only wall-clock frame times are
   reported. No video/frame-rate claims.
3. **D640:** untimed buffer/reference I/O dominates frame cost; per-frame
   anchor-SHA validation; `resize_exact` admitted only for the recorded
   LANCZOS library preprocessing.
4. **Parameter dialect:** legacy→canonical-flat-2 conversion is recorded
   (receipts in `profiles/history/legacy_conversion_20260914.json`), not
   format-3.
5. **Cold boots:** M7-era fallback was warm reboot; true power-cycle evidence
   is the five M9 §3 boots.
6. **Evidence gaps:** the five E2 `extremes-*` record directories remain on
   the board/SD rootfs; the full E2 matrix console log was never captured
   (substance is in the transcripts and recovered records).
7. **Open P2s (R14-06..10):** imported-model runtime selection, admitted
   context freezing/binding, importer idempotency revalidation, aggregate
   storage ledger, converter overwrite guard — scoped post-release batch.
8. **Platform:** board clock resets each boot (record IDs carry the un-synced
   RTC); UIO/udmabuf root-only; PetaLinux recipes recreate the M2-P stage,
   not the current runtime (FP-03, post-release recipe revision).
9. **Timing:** A32-class WNS +0.066 ns; D640 post-physopt WNS +0.001 ns
   (frozen [S20]). Power figures are vectorless estimates.
