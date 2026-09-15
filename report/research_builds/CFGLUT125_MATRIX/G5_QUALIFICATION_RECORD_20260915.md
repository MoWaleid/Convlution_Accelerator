# G5 five-release qualification record — 2026-09-15 (§19.7 complete)

**Status: all five releases QUALIFIED.** This record is the qualification
decision; the runtime manifests deliberately remain `built-unqualified` /
`deployable: true` (external-evidence discipline, §19.7 step 2).

Board: ZedBoard (Zynq-7020 xc7z020clg484-1), PetaLinux image BOOT.BIN
`b91acd41a83eba8866c4385b5ff0d0ef9e38b1ad4b6c909d32c31d03783c04c4`, live
FCLK0 124.99999875 MHz (SLCR: IO_PLL_CTRL FBDIV=30, FPGA0 divisors 4x2,
re-verified after cold boot). Runtime per §18.20 staging (68 files,
archive `9d927855…587b3`); active catalog = exactly the five releases.

## Qualified releases (frozen artifact set, §18.17)

| Release | Shape | BIT SHA-256 (prefix) | Firmware SHA-256 (prefix) |
|---|---|---|---|
| A32_CFGLUT125 | N3 K8 32x32 | `0ddd0a46…` | `880505fe…` |
| B32_CFGLUT125 | N3 K16 32x32 | `2388f249…` (rebuild) | `757595d5…` (rebuild) |
| C32_CFGLUT125 | N5 K8 32x32 | `8108a82f…` | `f046eec5…` |
| D32_CFGLUT125 | N3 K4 32x32 | `b02fc59c…` | `5f83266d…` |
| D640_CFGLUT125 | N3 K4 640x480 | `6e95188e…` | `20289d5e…` |

The B32 legacy qualified artifact set (BIT `133713c5…`, firmware
`4e827310…`, XSA `e90b8441…`) remains historical evidence at
`bitstreams/history/20260914_b32_board_qualified/`; the rebuild above is the
qualified release.

## Board evidence gates (transcript: `../../evidence/g5_board_qualification_20260915.txt`;
records: `../../evidence/g5_board_records_20260915/`, 87 files,
SHA256SUMS `17b4dcc1…`; board archive `06b4cb7f…3a96a`)

1. **Identity + anchor activation, full-PL reload per release** (singles,
   3 frames each): all five `reload=yes` with the correct
   `m7_<ID>_CFGLUT125.bin`, live BUILD_IDs matching the locked table,
   anchor-exact activations (A32 `cb397559…`, B32 `5821c8b1…`,
   C32 `b6ab2d53…`, D32 `6cb736f6…`, D640 `e323defb…`), cleanup `0x181`.
   The A32-first ordering proved the B32 rebuild firmware on silicon
   (identical BUILD_ID to the old boot bitstream would otherwise have taken
   the parameter-only path).
2. **Numerical extremes, 12 exact-reference frames per release** (60 total):
   all-zero, all-255, both saturation rails, signed-24 bias endpoints, live
   shift 24-31 sweep, reinstall + anchor revalidation. Zero mismatches.
   D640's VGA exact-reference computations ran minutes each as documented.
3. **100-frame no-reset soaks, one activation per release** (500 frames):
   100% bit-exact, anchor_sha256 mode, zero inter-frame resets, cleanup
   `0x181`. Medians: A32 0.126 / B32 0.123 / C32 0.124 / D32 0.125 /
   D640 3.731 ms (p95 0.127-0.132 / 3.749); the D640 median matches the
   historical M7-era soak exactly. Timing scope note embedded in each
   record: host-clock intervals incl. polling; declared fabric clock
   125 MHz; not hardware cycle counts (G3.4 claim discipline).
4. **Directed five-profile switching matrix**: 58 switches, 58 full-PL
   reloads, 20/20 ordered pairs, 58.5 s, every activation anchor-exact;
   includes 20 provably consecutive A32-B32-A32 cycles and all C32/D32/D640
   transitions.
5. **True power-cycle cold boot**: halt -> power off -> power on; all 68
   runtime files and 5 firmware images persisted cmp-identical; SLCR
   re-verified 125 MHz; fresh A32 anchor sample PASS (`reload=yes`).
   One harness correction during FCLK probing: the assistant first probed
   wrong SLCR addresses (0xF8000100/0xF8000140 = ARM CPU clocks, values
   consistent with a healthy 650 MHz CPU boot); corrected to the documented
   0xF8000108/0xF800010C/0xF8000170, which matched the accepted derivation.
6. **Bounded-recovery fault injection** (`g5_fault_check.py`, commit
   `1bffc31`): ABORT-from-IDLE latched FAULT with ABORTED alone in
   ERROR_FLAGS; ABORT-after-START race took the FAULT path; both RESET
   recoveries clean; recovery proven by an anchor-exact m8_cli frame
   (records `20180309T230706Z` / `20180309T232234Z`). Harness lesson
   recorded: real CVH1 silicon retains PARAM_COMPLETE across RESET
   (0x181), the first harness revision's equality check was wrong, and a
   93-line single serial paste corrupted in transit and was rejected by
   the per-chunk md5 gate before decode (chunk discipline re-confirmed).
7. **Session totals**: 575 scripted qualification frames + 2 fault-proof
   frames, zero mismatches anywhere; every switch a verified full-PL
   reload of the frozen firmware set.

## Claim scope (Option A, unchanged)

Zero external output gaps and frame-D internal invalid advances = 0 are
claimed for A32/B32 only. C32/D32/D640 are exact datapaths with measured
row-transition bubbles disclosed (wrapper-sim record
`profile_wrapper_sims_20260914.md`). Throughput/FOM statements must use the
recorded host-clock timings with the embedded scope note; positions,
channel-results and beats must not be conflated.

## Board-clock caveat

All board run-ids carry 2018 stamps (dead RTC); they are identifiers, not
chronology. Host evidence dates (this file, 2026-09-15) are authoritative.

## Remaining (post-qualification, non-blocking)

- Competition/research report + demo update from this evidence (user's
  call on timing; §19.7 step 7 wording).
- Optional recorded legacy-file cleanup on the board (9 stale M2-era
  conv_lab modules + legacy manifests); pre-change state preserved in
  `/home/petalinux/release_checkpoints/G5_pre_runtime.tar.gz`
  (SHA-256 `63c955e2…f0602`).
