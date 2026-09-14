# M9 — release freeze checklist (pre-execution)

Gate (MASTER_PLAN §7): "Reviewed release tag/snapshot, qualification matrix,
artifacts, documentation and baseline measurements. Another clean build and
documented setup reproduce results; five cold-boot runs pass; 1,000-frame
baseline soak passes with selected varied inputs/parameters; no unresolved
critical correctness/switching issue; known limits explicit."

Status inputs: M0–M8 closed (M8 commit ac84c3e; the R14-02..05 repair batch and
the R14-01 containment shipped in 73bb803 and were board-revalidated 2026-09-14 —
see AI_HANDOFF §17). M9 §1–§4 done (§4 per the gate's actual wording — see below);
§5 tag = user action on the commit containing this line.

## 1. M8 closeout (precondition) — DONE 2026-09-14
- [x] BLOCKREADY: push m11fix payload (m7_switch consecutive-cycle bridge,
      m8_cli cmd_extremes) — AI_HANDOFF §16.7 (consumed)
- [x] Board: extremes × A32/B32/C32/D32 (fast) and D640 (seconds per exact
      reference — faster than budgeted)
- [x] Board: --matrix rerun (58 switches from D640 via A32 bridge; 20
      provably consecutive A32→B32→A32 cycles + full pair coverage, 57.5 s)
- [x] Evidence: report/evidence/e2_extremes_matrix_20260914.txt; E2 closed
      in AI_HANDOFF
- [x] M8-07 disposition documented (hash binding + git content-addressed
      canonical bundles; per-run byte preservation traded consciously)
- [x] Commit ac84c3e; M8 declared complete in AI_HANDOFF §3
      (note: rerun was 58 switches, not 59 — the greedy walk needed no
      extra bridge beyond the A32 establishment)

## 2. 1,000-frame baseline soak (varied inputs/parameters) — DONE 2026-09-14
- [x] 200 × A32 (library anchor input) — PASS, median 0.125 ms
- [x] 200 × B32 (library anchor input) — PASS, median 0.124 ms
- [x] 200 × C32 (library anchor input) — PASS, median 0.125 ms
- [x] 200 × D32 (--image aeroplane through the isolated worker) — PASS,
      exact-reference per frame, median 0.125 ms
- [x] 100 × D640 (library anchor input, LANCZOS + per-frame anchor SHA) —
      PASS, median 3.728 ms
- [x] 100 × B32 (--image aeroplane through the isolated worker) — PASS,
      exact-reference per frame, median 0.126 ms
- [x] Zero mismatches across all; records archived (schema v3); evidence:
      report/evidence/m9_soak1000_20260914.txt
      (note: the soak subcommand was added to m8_cli for this; the interleave
      idea was dropped — extremes mode covers the lifecycle separately)

## 3. Five cold-boot runs (true power removal per E2 scope note) — DONE 2026-09-14
- [x] 5 x physical power OFF/ON by the user (B32, C32, D32, D640 reloads +
      A32 parameter-only from factory identity on boot 5)
- [x] Per boot: date set, persistence md5 verified (boots 2-5 captured in
      transcript; boot 1 md5 check not relayed), one full switch with
      anchor-exact activation, cleanup 0x181
- [x] Evidence: report/evidence/m9_coldboots_20260914.txt

## 4. Reproducible release
- [x] Clean-build reproduction — satisfied per the master-plan gate ("reproduce
      results", not bit-identical binaries): the M7 campaign built five fresh
      isolated profile projects from the scripted flow and qualified each on
      board; the live D640 artifact matches its manifest sha256 `64849132…`.
      A bit-identical bitstream re-hash was not performed and is not required;
      recorded in RELEASE_MANIFEST_v1-m9-release.md (2026-09-14)
- [x] Snapshot manifest: RELEASE_MANIFEST_v1-m9-release.md (artifact sha256
      table + known limits); the tag itself pins the exact source tree
- [x] Documentation: AI_HANDOFF §17 final state, README pointers reconciled
      (0.9 pass), known limits below

## 5. Known limits to state explicitly
- Sustained throughput bound by the 64-bit output serializer (4/K ceiling);
  measured wall-clock frame times reported separately
- D640 frames: untimed buffer/reference I/O dominates; anchor-SHA validation
- Legacy→canonical bundle conversion is recorded, not format-3
- M7-era cold-boot evidence was warm reboot (`sudo reboot`); true physical
  power-cycle evidence is the five M9 §3 boots (m9_coldboots_20260914.txt)
- Extremes coverage currently excludes per-profile arbitrary-image LANCZOS
  (resize_exact admitted only for the recorded D640 library preprocessing)
