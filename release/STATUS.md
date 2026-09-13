# Release validation status

Release candidate: RTL, physical build, package and host checks complete. Board execution NOT run.

- Upstream base: fb66066; branch target 100 MHz, N3/K16/W32; identity EF100K16N3W32R01 (magic 0x43564831, ABI 0x00010000).
- Fresh full-system build: PASS - setup WNS +0.061 ns, hold WHS +0.008 ns at 10.000 ns; 0 routing errors; 0 DRC errors; edgefree.bit and edgefree.xsa exported (work/release_100/artifacts).
- RTL suite: PASS - wrapper A-H for baseline/optimized/baseline_stress/optimized_stress, negative control rejected as required, engine exact/K16/pipeline suites (EDGEFREE_RELEASE_RTL_PASS).
- Numerical reference: PASS - 1,007 tests, `python -m unittest tests.test_b_reference` from software/.
- Host package check: PASS - PACKAGE_HOST_PASS, 16,384 expected int16 outputs verified against the software reference; SHA256SUMS.txt manifest in the package.
- Package: dist/edgefree100 (bit, xsa, params, input, software, quickstart, hashes). Generated output, intentionally untracked.
- Board validation: NOT_RUN. The friend imports artifacts/edgefree.xsa into the matching PetaLinux/Vitis ZedBoard project, rebuilds FSBL/boot with edgefree.bit, and confirms the running clock (100 MHz) per QUICKSTART.md. Do not reuse historical firmware hashes or m7_B32.bin.

RTL deltas vs the qualified EdgeFree experimental sources: branch identity constants only (CFG_BUILD_ID = EF100K16N3W32R01 replaces the legacy M4N3K8W32-260911 string) plus a conv_channel correctness fix that sign-extends the discarded half bit for shifts beyond the accumulator width (covered by the pipeline test). Everything else is byte-identical.
