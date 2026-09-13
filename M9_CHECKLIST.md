# M9 — release freeze checklist (pre-execution)

Gate (MASTER_PLAN §7): "Reviewed release tag/snapshot, qualification matrix,
artifacts, documentation and baseline measurements. Another clean build and
documented setup reproduce results; five cold-boot runs pass; 1,000-frame
baseline soak passes with selected varied inputs/parameters; no unresolved
critical correctness/switching issue; known limits explicit."

Status inputs: M0–M7 closed (AI_HANDOFF §3). M8 in progress — all P1 review
findings closed; remaining E2 board session is staged behind the BLOCKREADY
keyword (§16.7).

## 1. M8 closeout (precondition)
- [ ] BLOCKREADY: push m11fix payload (m7_switch consecutive-cycle bridge,
      m8_cli cmd_extremes) — AI_HANDOFF §16.7
- [ ] Board: `extremes` × A32/B32/C32/D32 (fast) and D640 (minutes of exact
      reference per stimulus — expected)
- [ ] Board: `--matrix` rerun (59 switches from a non-A32 start; 20
      provably consecutive A32→B32→A32 cycles + full pair coverage)
- [ ] Evidence: transcripts → report/evidence/; E2 closed in AI_HANDOFF
- [ ] M8-07 disposition documented (hash binding + git content-addressed
      canonical bundles; per-run byte preservation traded consciously)
- [ ] Commit; M8 declared complete in AI_HANDOFF §3

## 2. 1,000-frame baseline soak (varied inputs/parameters)
Plan (all machinery exists):
- [ ] 200 × A32 (library anchor input, --soak A32 200)
- [ ] 200 × B32 (library anchor input)
- [ ] 200 × C32 (library anchor input)
- [ ] 200 × D32 (--image aeroplane demo image through the isolated worker)
- [ ] 100 × D640 (library anchor input, LANCZOS + per-frame anchor SHA)
- [ ] 100 × D32 (--image board-probe imported bundle parameters? — no;
      imported bundles are model metadata. Use the second demo image set or
      repeat aeroplane with the saturation-lifecycle interleave: run + 1
      extremes-style reinstall per 25 frames)
- [ ] Zero mismatches across all; records archived; transcript per profile

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
