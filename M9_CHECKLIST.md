# M9 — release freeze checklist (pre-execution)

Gate (MASTER_PLAN §7): "Reviewed release tag/snapshot, qualification matrix,
artifacts, documentation and baseline measurements. Another clean build and
documented setup reproduce results; five cold-boot runs pass; 1,000-frame
baseline soak passes with selected varied inputs/parameters; no unresolved
critical correctness/switching issue; known limits explicit."

Status inputs: M0–M7 closed (AI_HANDOFF §3). M8 in progress — all P1 review
findings closed; remaining E2 board session is staged behind the BLOCKREADY
keyword (§16.7).

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

## 3. Five cold-boot runs (true power removal per E2 scope note)
- [ ] Power OFF (remove USB/adapter), wait, power ON
- [ ] Per boot: date set, persistence md5 (m7_switch/m8_cli/profiles),
      one full switch with anchor-exact activation
- [ ] Transcript per boot → report/evidence/

## 4. Reproducible release
- [ ] Clean-build reproduction: scripted BD + Vivado 2025.2 → bitstream hash
      comparison against the qualified M4/A32 artifact
- [ ] Release tag `v1-m9-release` on the final commit; snapshot manifest
      (SHA-256 of tagged tree, bitstreams, firmware images, evidence)
- [ ] Documentation: AI_HANDOFF final state, README pointers, known limits
      (timing margin WNS +0.066 A32-class; D640 I/O characteristics; legacy
      dialect conversion; no video/frame-rate claims; D640 reference cost)

## 5. Known limits to state explicitly
- Sustained throughput bound by the 64-bit output serializer (4/K ceiling);
  measured wall-clock frame times reported separately
- D640 frames: untimed buffer/reference I/O dominates; anchor-SHA validation
- Legacy→canonical bundle conversion is recorded, not format-3
- Warm-reboot cold-boot evidence; physical power-cycle evidence from M9 §3
- Extremes coverage currently excludes per-profile arbitrary-image LANCZOS
  (resize_exact admitted only for the recorded D640 library preprocessing)
