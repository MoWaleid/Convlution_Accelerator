# Current feedback for GLM: M7 closeout and M8 review

Review date: **2026-09-13**. This section supersedes the original review retained below as history.

## Verdict and reviewed snapshot

**M7 has substantial new reported board evidence and genuine fixes. M8 is not ready for acceptance or an unattended board demo.** Preserve successful board evidence, but do not treat it as proof that every earlier finding is resolved or that the current source is qualified.

Reviewed HEAD: `3117f0f` (M7: qualify five profiles and runtime model switching). New untracked work: `software/m8_cli.py` and `verification/m8_cli/`. Reviewed the manager/CLI, both mock harnesses, catalog/manifests, M7 transcripts, relevant contracts, report corrections and earlier findings.

Snapshot SHA-256:

| File | SHA-256 |
|---|---|
| `software/m7_switch.py` | `08f3aaa9a4237af51616f6bed535f015c5036e475aa2e70d5bfc6dff16c9ba71` |
| `software/m8_cli.py` | `134df82494c4867676d81de692144b6e5101115e4653bc624b705b64f2e6432c` |
| `verification/m8_cli/mock_cli_test.py` | `e70b96f1a6b41213f7276740a1fe7a2d41970fe6d0e323105bf555368dcd5827` |

Only this feedback document was edited. No application imports, tests, training, generators, builds or board commands were executed. Transcript counts were obtained by reading saved text, not rerunning the manager. References below use file paths and line numbers from this snapshot. P1 indicates a blocking correctness/safety/acceptance issue; P2 indicates a significant evidence, completeness or maintainability issue.

## Confirmed improvements

- Earlier undefined FPGA paths, missing identity keys, undefined counter variable and invalid logging call are fixed in current source.
- Frame execution now checks DMA IOC/error and accelerator completion/fault state. S2MM length is exactly RX bytes, not RX bytes plus guard.
- Same-build activation now validates identity and rejects entry ERROR/FAULT states.
- D640 resize is implemented; activation digests are appended.
- C32/D32/D640 catalog IDs now match their manifests. This resolves the catalog discrepancy, not full provenance/admission.
- Matrix construction no longer has the first-character/infinite-loop defect.
- Saved transcripts report five 100-frame soaks, switching and post-reboot activation. Parsing the matrix's 58 activation lines from its stated D640 start finds all 20 distinct directed pairs. These are valuable historical records.
- Report/figure accumulator width is corrected to 25 bits, and the old one-position/cycle claim was reduced to the serializer-derived bound. Measured-versus-theoretical wording remains an issue.
- M8 delegates MMIO/DMA to M7, separates previews from comparison data, and introduces records and timing fields. Retain these directions.

## New M8 findings

### M8-01 [P1] Unverified custom D640 outputs receive PASS

References: `software/m8_cli.py:270-278`, `:285-317`; `software/m7_switch.py:403-405`.

For a custom image above REF_POSITION_LIMIT without --reference, expected=None and verification mode is sha_only. There is no expected hash to compare. The backend returns mismatches=0 whenever expected is None, and the CLI marks the run PASS. Arbitrarily wrong output with valid transfer counters/guards can therefore receive a verified-looking PASS.

Required: obtain an independent expected result/hash for the admitted input and parameters, or explicitly return UNVERIFIED/NOT_CHECKED with mismatches=null. Separate execution success from numerical verification. A hash of an unknown answer is not a correctness check. Add a custom D640 test with deliberately incorrect output and valid DMA/counters that cannot receive verified PASS.

### M8-02 [P1] Arbitrary image decoding runs as root, after activation, with limits too late

References: `software/m8_cli.py:88-113`, `:231-242`.

The loader reads the entire file before checking its byte limit and calls im.load() before checking dimensions/pixel count. Pillow runs in the root hardware-owning process without an unprivileged worker, address-space ceiling or supervised deadline. It hashes one path read and reopens that path for decoding, so a changed file can yield different decoded bytes. It also lacks the approved PNG/JPEG format restriction.

Before this validation, switch_to() may already reprogram PL, write parameters and run an activation frame. A wrong-size, missing or malformed user image is rejected only after those mutations.

Required: reuse the bounded immutable-source snapshot and isolated decoder worker. Validate the requested operation, canonical byte count and reference availability before hardware writes. Decode exactly the hashed bytes. Enforce size/dimension limits before full decode and through transformations; isolate worker descriptors from hardware handles. Test that rejected input causes zero programming/parameter/DMA writes.

### M8-03 [P1] Cleanup errors can still publish/print PASS; record errors can retain ownership

References: `software/m8_cli.py:317-340`, `:410-427`.

Outcome is set to PASS before safe_cleanup(). The nested finally writes that PASS record and prints PASS even if cleanup raises; the exception propagates afterward. If write_record() raises, release_lock() is skipped. Cleanup/archive exceptions can also obscure the primary failure.

Required: record separate operation, verification, cleanup and persistence outcomes. Emit terminal PASS only after required stages succeed. Release ownership in an outermost finally independent of archive success. Preserve primary and secondary failures. Test cleanup timeout/error, record-write failure, cancellation and combined failures.

### M8-04 [P1] Archive IDs can collide and overwrite previous evidence

References: `software/m8_cli.py:194-197`, `:212-219`, `:296-297`, `:355-361`.

Benchmark IDs contain only second-resolution time and profile; exist_ok=True reuses directories. Run mode attempts one deterministic suffix, so repeated collisions reuse that second location. Clock resets are a known board condition. Existing record/frame files can be overwritten or mixed across runs. Direct record writes can leave truncated JSON; list mode then fails on a malformed record.

Required: exclusively allocate unique run directories and never overwrite prior payloads. Atomically publish records and preserve pending/failed operations. Append completed benchmark-frame evidence incrementally: currently the frame list is built only after the final frame succeeds, losing earlier successful-frame details on a later failure. Test frozen clocks, repeated names and interrupted/corrupt archives.

### M8-05 [P1] Privileged archive operations lack containment and symlink safety

References: `software/m8_cli.py:50-68`, `:194-197`, `:442-446`.

M8_ARCHIVE_ROOT is unrestricted; record <run-id> accepts absolute paths and traversal; output/ownership operations use ordinary paths without symlink checks. chown_tree recursively changes ownership, and os.chown follows symlink targets. A reused or user-writable archive can redirect privileged writes/ownership changes outside the intended tree.

Required: approved roots, single-component validated run IDs, containment checks, no symlink components/targets, and ownership changes only for files created for the current operation. Test traversal/symlink cases with harmless fixtures. Do not turn a writable results directory into an arbitrary root write/chown interface.

### M8-06 [P1] Storage admission, reservations and bounded growth are missing

References: `software/m8_cli.py:50-59`, `:218-219`, `:283-315`.

Every run frame is saved without storage-derived admission. D640 raw output is 2,457,600 bytes/frame before metadata/previews. Previews scale both dimensions by eight even for D640. There is no free-headroom reservation, disposable-payload budget or protected-evidence policy. Root can fill the OS filesystem and then fail to record the error.

Required: use the approved storage policy before hardware activation, accounting for peak temporary/final outputs and previews: 512 MiB free headroom and a 256 MiB disposable run-payload budget, with protected evidence excluded from automatic deletion. Reject when insufficient space remains; do not silently bypass policy with a fallback root. Bound previews and actual growth. Test low-space rejection before hardware writes.

### M8-07 [P2] Archives do not yet contain enough identity to reproduce a run

References: `software/m8_cli.py:168-191`, `:255-257`, `:350-381`.

Missing items include model/config/weight hashes, complete manifest/firmware identity, Pillow/codec versions and exact command/options. Custom source paths are mutable; canonical bytes are hashed but neither preserved nor bound to an immutable dataset. Benchmark input metadata remains empty. M8 reloads parameter files after M7 programmed them, allowing reference inputs to differ from hardware parameters if files change.

Required: admit one immutable input/model/hardware snapshot shared by hardware, reference and recording. Preserve or content-address all necessary assets and record observed identity, layout, versions, verification method, output inventory/checksums and cleanup outcome. Validate archives for missing/tampered members. Do not invent missing hashes.

### M8-08 [P2] Measurement names imply scopes they do not measure

References: `software/m8_cli.py:285-300`, `:388-408`; `software/m7_switch.py:318-321`, `:352-375`, `:395-405`.

hw_ms is a host-clock MM2S submission-to-poll-completion interval, not a hardware cycle counter; it includes polling overhead. wall_ms surrounds run_frame only and excludes activation, preprocessing, archive writes and previews. io_overhead_ms_median subtracts medians and includes hashing/unpacking/reference comparison, not just I/O. frames_total_s also excludes frame-file archival.

Required: explicit interval names/scopes, raw samples and separate whole-operation wall time. Do not derive kernel-only speedup/FOM from polling latency. If reporting paired overhead, summarize per-frame differences and identify included work. For D640 retain the large buffer-copy cost instead of presenting milliseconds as total user-visible runtime.

### M8-09 [P2] Tests omit critical negative cases and depend on a temporary local fixture

References: `verification/m8_cli/mock_cli_test.py`; `verification/m7_profiles/mock_switch_test.py:27-28`.

The test covers mainly A32/B32 success and one injected activation failure. It omits custom D640 unchecked output, concurrent owners, cleanup failure, disk full, archive collisions, worker enforcement, traversal, symlinks, DMA cancellation and partial benchmark records. The imported fixture defaults to one user's temporary m7_bundle2/profiles directory, so a clean checkout is insufficient. Mock output uses the same reference implementation as the consumer: useful for wiring checks, not independent numerical qualification.

Required: portable isolated/versioned fixtures, the missing negative cases, and explicit mock-versus-ARM/decoder-enforcement status. Hardware error-path tests must remain mocked/simulated where real SLVERR causes SIGBUS. No new M8 runtime PASS was independently established in this review.

## M7 backend gaps inherited by M8

### M7-R1 [P1] The lock is check-then-create, not exclusive

Reference: `software/m7_switch.py:567-574`.

Two processes can both observe an absent PID file and both proceed. Abrupt exit leaves a stale file; release unlinks by name without proving ownership. M8's exclusive-owner claim is not implemented.

Required: OS-backed exclusive ownership held for the entire lifecycle, protected lock location and ownership-safe release. All hardware entry points must honor it. Test simultaneous acquisition and termination; the loser performs zero hardware accesses.

### M7-R2 [P1] Activation ignores the discovered allocation and uses the wrong guard layout

References: `software/m7_switch.py:171-194`, `:421-431`, `:327-331`; `software/hardware_D640.json:39-44`.

main()/M8 discover ctx['buffer_size'], but switch_to uses acc.get('buffer_bytes',4194304). That field is not in the accelerator object, so activation assumes 4 MiB even when runtime allocation is smaller. Checking later frames is too late.

compute_layout reserves only one 64-byte separation. RX offsets are 5376 for A/B/D32, 5504 for C32 and 313664 for D640, versus approved 5440/5568/313728. TX guards remain absent; physical aperture/alignment/DMA-length checks are missing. The D640 manifest still declares the old overlapping RX offset 65536. Current computed RX does not overlap TX, but it does not implement the approved four-guard layout.

Required: validated conv_lab layout with actual allocation facts before activation; reject incompatible buffers before DMA, reconcile manifests, and require padded payload length equals submitted TX length. Historical results qualify the actual tested layout, not a different promised layout.

### M7-R3 [P1] Cleanup can issue illegal RESET and print PASS on failed execution

References: `software/m7_switch.py:646-657`, `:696-723`.

safe_cleanup checks IDLE or FAULT but not QUIESCENT before RESET. A faulted accelerator can still have pending output; halting DMA does not prove quiescence. RESET risks the known SLVERR/SIGBUS behavior. Matrix cleanup prints PASS from finally even when its body raised, if cleanup succeeds. Top-level cleanup exceptions are printed and suppressed.

Required: validate complete legal reset state; avoid speculative MMIO on unknown fabric; record unresolved state as recovery-required. PASS needs successful execution AND required cleanup. Cleanup success cannot turn a failed matrix into PASS.

### M7-R4 [P1] Bundle/platform admission is still partial

References: `software/m7_switch.py:105-140`, `:263-294`, `:410-470`.

Range/order checks improved, but permissive format-2 JSON remains: ignored schema/scale/bias-width declarations, noncanonical types, invalid ReLU silently treated as zero, unconstrained weight paths, no immutable whole-bundle hash snapshot. The catalog argument does not validate the chosen manifest. Width registers are not validated; reload does not first establish a complete known source-platform identity. Production preprocessing does not consume its recorded canonical policy/hash.

Required: integrate approved strict admission and immutable snapshots, with explicit legacy conversion. Validate platform compatibility before touching the old fabric. Numeric bounds alone do not turn signed32 legacy metadata into a signed24/format-3 bundle.

## Evidence and closeout: reconcile without erasing success

### E1 [P1] Current source does not match the recorded board-tested source

Current m7_switch.py MD5 is `184d75c07eb96d4b7e64b27b6a05dd31`. New board transcripts/handoff identify `e853933b4d0610881e895be4ff48c3bf`. LF normalization leaves the current hash unchanged; its CRLF variant is `815521e84b68894198ea5c22cf064a9c`, so those line-ending variants do not explain the mismatch.

Required: preserve the actual board-tested file, compare it with committed source, explain the differences, and bind qualification to the correct snapshot/artifacts. Do not relabel transcripts. This gap does not imply the reported runs did not happen.

### E2 [P2] Directed-pair coverage exists, but exact gate claims need correction

- The 58 matrix activation lines cover all 20 pairs. Actual occurrence counts are A32=23, B32=23, C32=4, D32=4, D640=4; the footer says 24/24/5/4/4, which totals 61.
- The loop begins with B32 irrespective of source. Starting at D640, iteration one is D640->B32->A32, not a full A32->B32->A32 cycle. The initial alternating block therefore gives 19 consecutive full A32 cycles; a later edge is not proof of 20 consecutive cycles. Establish A32 before the counted loop if retaining that approved gate.
- The saved coldboot procedure says sudo reboot. It supports reboot/persistence/reload behavior, not a documented power removal/restoration. Preserve the actual procedure and identify separate power-cycle evidence for that claim.
- Five fixed-input soaks alone do not demonstrate all per-profile M5-grade extremes, varied inputs/parameters, lifecycle and bounded-failure coverage required by M7_CONTINUATION. Locate that evidence or leave those qualification items open; never regenerate evidence from expected behavior.

### E3 [P2] Foundation tests and report evidence remain partly stale

- test_m7_profiles.py still freezes old C32/D32/D640 IDs and asserts current selection is B32 while the source is D640. Those assertions cannot pass unchanged. Update approved anchors without weakening independent checks.
- Archived D32/D640 timing reports remain pre-optimization reports. Preserve final reports tied to exact bitstreams; current passing D640 live-run evidence is not the archived failing report.
- Widths were corrected, but 4/K positions/cycle is an interface ceiling, not an automatically measured sustained rate. Report/FOM and correction guidance still treat it as sustained/measured. Use a labeled theoretical upper-bound FOM or measured throughput at a consistent scope, not merely half the previous unsupported rate.
- Legacy exporter arbitrary-destination deletion and signed32 metadata remain open (original findings 11/8). Preserve explicit conversion and safe export requirements.
- State/README/fix-plan guidance remains contradictory. The handoff says commit pending although 3117f0f exists. Reconcile current guidance while clearly preserving historical material.

## Prior-review disposition

| Original finding | Current status |
|---|---|
| 1 runtime exceptions | Fixed in source; board-source binding remains E1 |
| 2 missing DMA completion | Materially fixed: IOC/error and accelerator completion checks added |
| 3 guarded layout | Open: M7-R2 |
| 4 catalog ID mismatch | Catalog/manifests reconciled; tests/provenance/admission remain open |
| 5 matrix infinite loop | Fixed; exact cycle coverage remains E2 |
| 6 missing D640 resize | Implemented; isolated metadata-driven preprocessing still incomplete |
| 7 lifecycle/ownership | Partial: M7-R1/R3 and M8-03 block acceptance |
| 8 strict admission/bias | Numeric checks improved; M7-R4/conversion remain open |
| 9 evidence freshness | Open: E1/E3 |
| 10 throughput/widths | Widths corrected; measured throughput/FOM/citations remain E3 |
| 11 unsafe export deletion | Open |
| 12 qualification gate | Soaks reported; full-gate/cold-boot/cycle precision remains E2 |

## Suggested work order for GLM

1. Preserve and reconcile the exact board-tested M7 source before changing the backend. Keep historical artifacts/evidence immutable.
2. Fix false verification/PASS, legal cleanup, actual allocation admission and exclusive ownership; add focused negative tests for the actual paths.
3. Integrate the existing isolated decoder, strict immutable bundles and bounded/atomic archive storage rather than adding weaker parallel implementations.
4. Make fixtures portable, records complete and timing scopes explicit. Request user-executed host/Linux/ARM validation under the established workflow.
5. Close only evidence-backed qualification gaps and complete report corrections before release. Do not expand into GUI/optimization work to bypass these blockers.

This review is feedback, not authorization for autonomous training, builds or board operations. Only feedback.md was edited.

---

# Historical review: 2026-09-12 (superseded by dispositions above)

Review date: 2026-09-12

## Verdict and scope

**Changes requested before any M7 board run. Moving the extracted folder is not the only blocker.**

This feedback records a read-only review of the M7 changes, including `M7_STATE.md`, the switch manager, profile catalog/manifests, RTL changes, build preparation, tests, numerical exports, available artifacts/evidence, and report claims. No tests, builds, generators, or hardware commands were executed during the review. No implementation files were changed. This feedback file was subsequently created at the user's request.

The reviewed `software/m7_switch.py` has MD5 `9337746ce1e5d597156458fd8666b09e`, matching the version recorded in `M7_STATE.md`. Findings describe that reviewed snapshot; later changes require reassessment.

P1 means a blocking correctness, safety, or submission-accuracy issue. P2 means a significant consistency, evidence, or maintainability issue.

## Blocking findings

### 1. [P1] Multiple guaranteed runtime failures in the switch manager

- `FPGA_FLAGS` and `FPGA_FIRMWARE` are undefined when the reload branch uses them.
- `read_identity()` does not return `magic` or `abi`, but `validate_identity()` accesses both keys.
- `run_frame()` unpacks `tx_size`, but the counter checks reference undefined `tx_bytes`.
- `log()` accepts one argument, but activation success calls it with two arguments.

These failures occur along normal activation paths. Syntax compilation cannot catch them.

References: [programming](software/m7_switch.py#L199), [identity](software/m7_switch.py#L122), [counters](software/m7_switch.py#L155), [logging](software/m7_switch.py#L228).

Required: fix these defects and exercise the actual manager through a mocked complete activation, not just its supporting helpers.

### 2. [P1] Accelerator completion is incorrectly treated as DMA completion

The manager waits for accelerator `DONE|IDLE`, then reads the receive length and buffer. It never requires both DMA channels to complete without errors. Accelerator stream completion is not proof that S2MM has finished writing DDR. The existing M4 backend explicitly checks DMA completion; the new manager drops that protection.

Reference: [run_frame](software/m7_switch.py#L149).

Required: restore separate, bounded DMA and accelerator completion checks before reading output or allowing another operation. Check DMA errors throughout relevant waits, and validate the final accelerator state/counters/errors separately.

### 3. [P1] Runtime bypasses the guarded-layout implementation

The manager:

- Never calls `profile_layout()` or `validate_layout()`.
- Never checks the actual DMA buffer allocation size.
- Retains RX offset `65536` for the small profiles instead of their approved calculated layouts.
- Programs S2MM receive length as `rx_bytes + 64`, including the trailing guard in writable receive capacity.
- Installs/checks only RX guards rather than all four TX/RX guards.

Separately, `software/hardware_D640.json` still declares RX offset `65536`, overlapping its TX region. D640 TX occupies `[4096, 313540)`. The manager itself calculates a different D640 RX offset, so this is a manifest/runtime inconsistency, not a claim that its calculated D640 offset overlaps.

References: [runtime layout](software/m7_switch.py#L73), [receive submission](software/m7_switch.py#L142), [D640 manifest](software/hardware_D640.json#L39).

Required: use one validated layout, actual runtime allocation facts, exact receive length, alignment/aperture/length checks, and all four guards. Do not silently ignore contradictory manifest fields.

### 4. [P1] Profile identities have competing definitions

C32, D32 and D640 IDs in `profiles/m7_profiles.json` differ from their hardware manifests:

| Profile | Catalog BUILD_ID | Manifest BUILD_ID |
|---|---|---|
| C32 | `4d374e354b385733322d323630393132` | `434e354b30385733322d323630393132` |
| D32 | `4d374e334b345733322d323630393132` | `444e334b30345733322d323630393132` |
| D640 | `4d374e334b3457363430483438300001` | `443634304e334b30342d323630393132` |

The selected D640 RTL follows the manifest ID, while the discovery tests generate their expected IDs from the different catalog. Passing those tests therefore does not validate the identities described for the built images. A32 and B32 catalog/manifest IDs agree; the issue is not hexadecimal ID length.

References: [catalog](profiles/m7_profiles.json#L6), [selected RTL](Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd#L18), [D640 manifest](software/hardware_D640.json#L7).

Required: reconcile catalog, generated RTL, manifests, actual artifacts and evidence. Do not merely rewrite IDs to make comparisons pass. Preserve evidence of what each existing bitstream actually represents and distinguish new builds from previously tested artifacts.

### 5. [P1] Matrix construction can loop indefinitely

In `build_matrix_sequence()`, `bridge` is a profile-name string, but `bridge[0]` selects its first character, such as `C` rather than `C32`. Once the walk exhausts A32's remaining outgoing edges, it enters this branch without reducing `remaining`. The manager can hang before performing the matrix switches.

The matrix also assumes the initial profile is A32 rather than proving it. Its `digests` list is never populated, so the summary's activation-frame count is not meaningful. Requested destinations are not sufficient evidence of observed source-to-destination coverage.

Reference: [matrix construction](software/m7_switch.py#L246).

Required: test termination, valid profile names, and coverage independently; establish the actual starting profile; record observed transitions and successful activation frames. Allow necessary connecting transitions rather than assuming the claimed total automatically proves coverage.

### 6. [P1] D640 preprocessing is described but not implemented

`load_input()` opens the original 32x32 image, converts it to grayscale, and immediately requires its dimensions to equal the requested geometry. There is no resize. D640 therefore fails after parameter programming. The recorded D640 preprocessing metadata and canonical hash are not used by this path.

Reference: [load_input](software/m7_switch.py#L53).

Required: apply explicitly approved preprocessing through the existing bounded decoder pipeline, verify canonical bytes, and finish input validation before hardware mutation. Do not introduce silent resizing or bypass the established decoder-resource and privilege boundaries.

### 7. [P1] Admission and failure handling regress the approved lifecycle

- A matching BUILD_ID skips full identity validation.
- QUIESCENT alone is accepted without excluding FAULT/error states.
- There is no exclusive ownership lock to prevent concurrent managers.
- `--profile` and `--soak` lack guaranteed DMA cleanup on failure.
- Matrix mode prints PASS before its final cleanup checks.
- The final RESET wait accepts any bit in `IDLE|QUIESCENT` rather than requiring both, and does not establish the full claimed clean state.

References: [admission](software/m7_switch.py#L185), [execution modes](software/m7_switch.py#L281), [matrix cleanup](software/m7_switch.py#L327).

Required: validate every activation path, serialize ownership, and define safe cleanup/fail-stop behavior before issuing PASS. Recovery must respect whether the fabric identity and transaction state are known; closing file handles is not equivalent to stopping DMA.

### 8. [P1] Parameter loading bypasses strict admission and signed24 enforcement

The manager directly accepts legacy format-2 files without validating channel ordering/uniqueness, coefficient ranges, signed24 bias bounds, shift bounds or bundle member hashes. It does not validate the complete bundle before MMIO writes.

The exporter still advertises and permits signed32 biases. The inspected B32 and C32 exports happen to fit signed24, so this is not a claim that those particular biases overflow; future exports need not fit. The current weak loader does not enforce the hardware limit.

References: [parameter loader](software/m7_switch.py#L35), [exporter bias validation](golden_model/extract_weights.py#L87), [export metadata](golden_model/extract_weights.py#L210).

Required: retain explicit legacy conversion, then use the approved strict admission path before any MMIO writes. Validate channel association, coefficient/bias/shift/ReLU values, geometry, schemas and member hashes. Preserve immutable historical inputs rather than silently relabeling legacy metadata.

## Evidence and reporting corrections

### 9. [P2] Historical PASS results do not qualify the current source completely

Existing logs genuinely show successful foundation tests. However, the current software test asserts that the working configuration equals the B32 projection, while the working configuration is now D640. That assertion cannot pass unchanged. These tests also never exercise `m7_switch.py`; the RTL bench covers discovery, not complete per-profile convolution and switching behavior.

Reference: [stale projection assertion](software/tests/test_m7_profiles.py#L136).

Archived D32/D640 routed timing reports contain WNS **-0.440 ns** and **-0.676 ns**, respectively. The current D640 **post-optimization** report correctly shows **+0.001 ns**, and its current run bitstream hash matches the named D640 bitstream. However, the passing post-optimization report is not the report archived under `report/profile_builds/D640/`.

References: [archived D32 timing](report/profile_builds/D32/accelerator_dma_wrapper_timing_summary_routed.rpt#L141), [archived D640 timing](report/profile_builds/D640/accelerator_dma_wrapper_timing_summary_routed.rpt#L141), [current D640 final timing](Convlution_Accelerator.runs/impl_1/accelerator_dma_wrapper_timing_summary_postroute_physopted.rpt#L141).

Required: preserve final artifact-matched reports and test-source provenance. Label intermediate failing reports as such. Update stale documentation about the selected profile and test status. Do not interpret a successful earlier test run as qualification of later changes.

### 10. [P1: submission accuracy] Sustained throughput and FOM are overstated

The report claims one complete output position per cycle and a 10.24 microsecond frame. For K8, each output position contains eight signed16 results: **128 bits over a 64-bit interface requires at least two beats**. The output alone requires at least **2048 cycles / 20.48 microseconds at 100 MHz**, before additional stalls. A compute pipeline's peak rate cannot be presented as measured full-system sustained throughput.

References: [throughput claim](report/report.md#L85), [results table](report/report.md#L262), [FOM](report/report.md#L294), [serializer](Convlution_Accelerator.srcs/sources_1/new/axi_stream_output_serializer.vhd#L414).

Required: distinguish scalar channel outputs from complete spatial output positions, and core peak rate from sustained integrated throughput. Recalculate FOM using an explicit, supported throughput definition and consistent measurement scope.

Also correct the report and figure's 32-bit bias / 33-bit accumulator descriptions. The implemented approved policy uses **24-bit bias and a 25-bit final accumulator** for these profiles. Some RTL comments are stale and must not substitute for the actual derived constants.

References: [report arithmetic](report/report.md#L66), [figure source](report/figures/generate_figures.py#L12), [actual configuration](Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd#L52).

Freeze source citations too: the report's A32 timing citation points into a live run directory now containing D640 results. Source references must identify the exact build supporting each claim, not whatever was built most recently.

### 11. [P2] Export destination flexibility introduces deletion risk

`CNN_WEIGHTS_DIR` now accepts arbitrary paths, but export deletes every file in an existing destination before completing conversion. A mistaken path or later quantization failure can destroy unrelated or previous output. The deletion loop predates this change, but allowing externally selected destinations expands its risk.

References: [environment-selected destination](golden_model/extract_weights.py#L46), [export cleanup](golden_model/extract_weights.py#L160).

Required: validate destinations, reject protected/input locations, and use fresh atomic exports. Any replacement should be explicit and scoped, not a blanket deletion of directory contents.

### 12. [P2] M7 closeout omits approved qualification gates

`M7_STATE.md` treats per-profile soak as optional and suggests 20 frames. `M7_CONTINUATION.md` retains the approved requirement of **at least 100 frames without inter-frame reset per compiled case**, applicable numerical/lifecycle tests, and cold-boot fallback. Those requirements must not disappear from closeout.

References: [execution summary and checklist](M7_STATE.md), [full M7 gate and per-profile qualification](M7_CONTINUATION.md).

Required: reconcile the checklist with the approved gate. Track implementation, host tests, fitting/timing, board qualification, switching coverage and cold-boot recovery separately. Any schedule-driven reduction requires an explicit scope decision, not an undocumented downgrade.

## Work worth retaining

- Shared `CFG_BUILD_ID` propagation through the RTL wrappers.
- Isolated build preparation and source snapshots.
- Strict layout/discovery helpers and negative identity tests.
- All four new B32/C32/D32/D640 bitstream and firmware pairs match their recorded manifest hashes.
- The saved C32 timing report and current post-optimization D640 timing report show timing closure.
- Existing foundation-test logs substantiate their historical results, within their actual coverage and source snapshot.

## Recommended handoff to the implementing agent

Retain those foundations, but repair and mock-test the actual manager before resuming board execution. Integrate the validated admission/layout/preprocessing paths rather than duplicating weaker versions. Reconcile artifact identities and evidence, correct quantitative report claims, and restore the full qualification checklist.

**M7 is not ready for approval yet.** This review does not authorize executing tests, generators, builds or board operations; follow the user's established execution workflow.
