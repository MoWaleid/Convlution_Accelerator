# Cleanup scan — 2026-09-14 (BUFFERED, nothing deleted)

Full-project scan for garbage/legacy/unneeded files, buffered for a polish
pass after the project completes. **No deletions were performed.** Re-run the
scan before acting: sizes and some items will have shifted by then (BLOCKREADY
payload consumed, further builds).

## A. Regenerable tool caches (~311 MB, zero risk)
| Item | Size | Notes |
|---|---|---|
| Convlution_Accelerator.gen/ | 121 MB | Vivado-generated IP output |
| Convlution_Accelerator.sim/ | 53 MB | sim artifacts |
| Convlution_Accelerator.cache/ | 49 MB | Vivado cache |
| Convlution_Accelerator.ip_user_files/ | 43 MB | generated |
| xsim.dir/ | 685 KB | xsim state |
| 7 x __pycache__/ dirs | trivial | software/, golden_model/, scripts/, verification/* |

## B. Temp payloads (~482 MB), staged deletion
- 24 x m8_mock_stage_*/ (~400 MB): fixture stages, each copies the four
  .bit.bin firmware images (~16 MB/stage); recreated by the m8 mock test from
  bitstreams/ on every run.
- ~25 x m8_mock_archive_*/ : mock test run archives, regenerable.
- Superseded payload chunks: m8c/m8cl/m8i/m8f/m9f/m7v2/chunk_00..06, plus
  installed-and-verified payloads m8fix, m9fix, m10fix.
- m8_import_base_*, m7_profiles_*, cltest/, m7prof_check/, m8_mock_custom.png,
  test_model.tgz, conv_lab_mini.tgz, _lf/_lf2.

### HOLD items inside Temp (archive to repo BEFORE any Temp cleanup)
1. m7_bundle/profiles/*/channel_config.json — possibly the ONLY surviving
   copies of the ORIGINAL legacy bundle metadata (pre-canonical-conversion;
   the conversion receipt kept hashes, not bytes).
2. m7_switch_board_qualified.py — the recovered board-qualified manager
   (md5 e853933b4d0610881e895be4ff48c3bf) that all M7 silicon evidence ran on.
3. m11f_* chunks + m11fix.b64/.tgz — the LIVE BLOCKREADY payload
   (AI_HANDOFF §16.7); untouchable until the board session completes.
4. m7sw_v2.b64 — recovery payload for the e853933b build (small).

## C. Convlution_Accelerator.runs/ (79 MB) — D640 implementation state
Contains the D640 .bit, 7 DCP checkpoints (opt/placed/routed...), 14 reports.
Timing reports already frozen at report/profile_builds/D640/final/. NOT frozen:
power, utilization, DRC, route-status. Pre-action before deleting: freeze the
remaining D640 reports into report/profile_builds/D640/final/, then delete at
the cost of a full re-implementation to regenerate.

## D. Root clutter (small)
vivado.log, vivado_41400.backup.log/.jou, vivado_38824.backup.log/.jou,
build_b32.log — build logs; archive to a logs/ dir or delete.

## E. Stale previews (110 KB)
golden_model/data/test_vectors_*/png/ — stale K=16-era previews (quirks
register item 2).

## F. User decision (434 MB, not garbage)
golden_model/data/cifar10_images/ (252 MB) + cifar10_raw/ (182 MB) — training
datasets; needed only for retraining. Keep locally or archive to cold storage.
The three .pth checkpoints (19 MB) stay regardless.

## Not candidates (verified keep)
bitstreams/ (M0 recovery references the len16 era; M7 qualified set),
checkpoints/k8_100mhz_postroute_physopt_met.dcp (M3 golden snapshot),
platform/accelerator_dma.xsa (M0/M2-P referenced handoff),
m4_final_utilization.rpt (report citation S3), profiles/history/,
debug_captures/, deploy recipe documentation copies (intentional build inputs,
byte-identical duplicates of software/CONVERSION.md and software/README.md),
M7 planning docs (committed history).

## Scan side-findings
- AI_HANDOFF §2 is stale on two items: golden_model.zip (~494 MB) and root
  m4_accelerator_dma.xsa no longer exist on disk.
- .venv/ is 888 MB (working environment, not project garbage — out of scope).
- .git/ is 19 MB (healthy).

## Suggested polish-pass order (when invoked)
1. Pre-archive HOLD items 1, 2, 4 into profiles/history/ (or a recovery/ dir).
2. Freeze remaining D640 reports (C).
3. Confirm BLOCKREADY consumed (item B.3) before Temp cleanup.
4. Delete A + B (minus holds) + D + E; decide F.
5. Update AI_HANDOFF §2 stale references; re-run this scan to confirm.
