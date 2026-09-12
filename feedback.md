# M7 review feedback

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
