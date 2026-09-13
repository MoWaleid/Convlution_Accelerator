# Conv Lab: hardware-independent M2 implementation

> EdgeFree release users: start with ../release/QUICKSTART.md and the generated standalone package. This document describes retained upstream history; its old hardware.json/profile IDs and private paths are not the active release's deployment configuration.

Implementation added 2026-09-09; extended with explicit conversion/offline tooling.
Historical host A/B results are preserved in [reports/HOST_EVIDENCE.md](reports/HOST_EVIDENCE.md).
**New C tests, current-revision A/B reruns, conversion and offline validation are NOT RUN.**
M1/M2 are not declared complete. No bundle or hardware platform is qualified.

This package follows the approved planning contracts in
[C:/Users/moham/Documents/Codex/2026-09-05/referenced-chatgpt-conversation-this-is-an/contracts/M1_READINESS.md](C:/Users/moham/Documents/Codex/2026-09-05/referenced-chatgpt-conversation-this-is-an/contracts/M1_READINESS.md).
Legacy golden_model code, saved board runners, RTL, Vivado files, assets and M0 records are untouched.

## Structure and API boundaries

| Module | Responsibility |
| --- | --- |
| conv_lab/strict.py | Exact JSON types/duplicate keys, reduced rational scales, strict coefficient byte grammar |
| conv_lab/bundles.py | Bounded filesystem inventory, opened-file containment, hashes over stored bytes, immutable snapshots |
| conv_lab/schemas.py | Schema-1 manifests, format-3 channels, explicit channel paths, numerical/profile compatibility |
| conv_lab/dma.py | Derived widths, all five DMA layouts, aperture/alignment/length checks, padding and stream packing |
| conv_lab/preprocessing.py | Linux supervisor, one per-UID worker slot, bounded nonblocking IPC/deadline/reaping |
| conv_lab/_decoder_worker.py | Private unprivileged child, address-space limit before Pillow, encoded format checks and canonical pipeline |
| conv_lab/admission.py | Identity catalog, whole-selection admission, deeply immutable context and generation-bound mock submission |
| conv_lab/reference.py | Arbitrary-precision cross-correlation, rounding/saturation/ReLU, channel-fast signed16 bytes and diagnostics |
| conv_lab/storage.py | Bounded ZIP snapshot, peak-space reservations, atomic publication and protected retention candidate planning |
| tests/fixtures.py | Synthetic fixture-generation code; creates only user-run temporary fixtures |
| tests/oracle.py | Independently structured numerical oracle; no implementation helpers reused |
| tests/run_group.py | User-run groups and timestamped evidence reports |

Use AdmissionSession.admit with three bundle roots, an explicit image ID, MockPlatform and
Allocation. The default decoder is LinuxDecoder. Decoder injection is an explicit trusted test seam,
not an automatic platform fallback or evidence of real enforcement. Admission validates all referenced bytes,
channel data, compatibility and layout before preprocessing. Only a complete successful
selection is registered. Snapshot content is bytes/tuples/frozen scalar objects; raw JSON
records remain immutable bytes. Later filesystem changes cannot substitute decoded input,
weights or hardware artifacts.

AdmissionSession.submit accepts only the exact context issued by that session and its current
generation, and only RecordingMockBackend. invalidate revokes existing submissions. Weak
registration does not retain abandoned full-frame snapshots indefinitely. A copied or manually
constructed reference fixture is not a submission capability. The mock records programming,
parameter, register and DMA requests but contains no device opening, MMIO, programming,
driver or live-discovery implementation. Its event sequence is not physical lifecycle evidence.

Only explicitly marked synthetic hardware under a matching fixture platform/envelope is admitted
by this mock session. purpose="production" always rejects. Real release qualification, PS/DT
discovery, cache/barrier procedures and hardware activation remain outside this batch.
The synthetic marker is a testing restriction, not an extension that overrides core validation.

reference_only/evaluate use the same canonical bytes as TX packing, without a second decode.
The reference retains serialized output and one scalar accumulator at a time. It has no decoder
deadline. Fraction-based physical units and display interpretation never modify raw comparisons.
compare reports lengths, checked/mismatched values and bounded coordinate/channel diagnostics.

## Supported hosts and dependency checks — user executes

Python **3.11 or newer** is required (including weak-reference slots for frozen contexts).
Validation, mock integration, storage-fixture and reference tests support Windows and Linux.
Opened-file containment currently requires Windows final-handle paths or Linux /proc;
other hosts fail closed rather than weakening path validation.

Full Group A also requires Pillow with PNG/JPEG codecs and the Image.Resampling.LANCZOS API
(Pillow 10 or newer is the intended host baseline). Installed versions are not assumed or pinned
by this batch; record and qualify the actual PetaLinux recipes/versions later. NumPy, PyTorch,
training checkpoints and expected .hex files are not required.

Run these dependency observations yourself. They install nothing:

~~~sh
python -I -c "import sys; assert sys.version_info >= (3,11); print(sys.version)"
python -I -c "import PIL; from PIL import Image,features; print('Pillow',PIL.__version__); print('JPEG',features.version('jpg')); print('PNG/zlib',features.version('zlib')); assert features.check('jpg') and features.check('zlib'); print(Image.Resampling.LANCZOS)"
~~~

The second check is needed for full Group A, not for the dependency-light Group B.
Pillow must be visible to the selected interpreter under -I, as used by the worker. Do not
assume Ubuntu already provides it. This task did not execute these checks or install anything.

## Linux process boundary

Actual worker enforcement is Linux-only. Run as an ordinary explicitly chosen unprivileged
user: root, setuid identity and effective capabilities are rejected. No deployed service account
is invented and no automatic privilege drop or privileged decoder fallback is supplied.
A future service arrangement and its device permissions remain M2-P work.

The supervisor launches the private worker using the same interpreter with -I -B, closed
unrelated descriptors, pipe-only standard streams, a restricted environment and a new session.
The worker checks its descriptor set, installs RLIMIT_AS at or below 134217728 bytes before
decoding, disables core dumps and sets no_new_privs. No hardware descriptors/mappings survive
exec and no hardware operations exist in worker code. This is not a claim of a qualified
deployed service sandbox.

The one-worker flock is per operating-system UID across supervisor processes, under a private
0700 temporary directory and 0600 lock file. Concurrent decoder requests reject instead of
forming an unbounded queue. Failure to establish the boundary rejects decoding.

Source limits apply jointly: 8388608 source bytes, width/height each at most 4096, and at most
2097152 pixels. Encoded PNG depth/color/transparency/animation and JPEG precision/components
are checked before full decoding. Orientation precedes grayscale and exact/explicit LANCZOS
geometry handling. Source bounds do not independently cap compiled output dimensions:
the latter come from the validated context and bounded DMA/output envelope.

The supervisor bounds input, stderr and output, enforces the 30-second preprocessing deadline,
kills/reaps a failed worker and rejects partial/late output. It cannot terminate a hardware
backend. Reference computation has no such decoder timeout. No warning, RSS observation,
thread timeout or missing feature is treated as enforcement. Limits are never silently relaxed.

## Storage and identity integration

Register all selected embedded/imported origins in IdentityCatalog before admitting/publishing.
Equal IDs with different manifest or payload bytes reject, including across origins. A repeat
of identical content preserves its existing origin; publication rereads that origin before reuse.

read_zip_bundle supports bounded, single-disk, non-ZIP64, unencrypted regular-file ZIP imports into snapshots; it does
not extract caller-controlled filesystem paths. Actual decompressed bytes, file count, CRC,
hashes and inventory are checked. Central-directory counts/bounds are checked before ZipFile
allocates its entry objects. Symlink/special ZIP entries reject. Filesystem snapshots
resolve contained links and reject escapes/cycles and undeclared payload.

ReadBudget defaults are implementation read guardrails: 64 MiB per bundle, 4096 inventory
entries and 1 MiB per JSON document, with directory depth bounded to 64. These are not approved
hardware capacities, replacement image limits or measured embedded memory availability.
Callers may explicitly choose stricter budgets; any deployed change needs review and resource
evidence. A source image remains bounded by the approved image policy regardless.

Publisher requires separate application-owned library and staging roots on one filesystem,
a SpaceLedger for that filesystem, a populated existing-origin inventory, and an explicit
trusted semantic validator for the selected bundle kind. For hardware use schemas.hardware;
model/dataset validators must also bind their selected compatibility context. This interface
does not silently invent platform values or import adapters.

Peak temporary/final storage is reserved with the approved 536870912-byte headroom; chunk
writes and reservations are serialized under the exclusive application's ledger. Publication
checks staged hashes/semantics, fsyncs payload files and renames only to a new target while
holding its publication lock. This is atomic visibility, not a claim of power-loss durability
or a backup/restore qualification. Existing targets and stale locks reject; no automatic
destructive recovery is implemented. Failed staging and a bounded failure record are retained
as protected evidence. Subsequent admission sees their real space use.

All writers in the application must share the same ledger. External filesystem writers,
filesystem allocation granularity and actual embedded headroom still require M2-P measurement;
a Python reservation is not a filesystem quota.

retention_candidates only plans oldest unpinned successful explicitly disposable payload IDs
under the 268435456-byte budget/headroom need. Summaries, failures, qualification records,
bundles, pinned data and recovery assets are excluded. It has no deletion executor. Insufficient
eligible content rejects. Full deployment, UI and backup/restore features are not implemented.

## User-run command group A

Working directory on this workstation:
D:\MyProjects\Convlution_Accelerator\software

On Linux, use the software directory of the checkout/copy you actually prepared; no Ubuntu
checkout path is assumed. For full worker evidence use Linux as an unprivileged user, with the
dependency checks above satisfied.

~~~sh
python -B -m tests.run_group A
~~~

Covers strict grammar/manifests, hashes/paths/identities, all five DMA layouts, immutable/stale
contexts, zero mock writes on rejection, staging/publication/headroom/protected retention,
and Linux worker process/PNG/JPEG enforcement cases. On Windows or root Linux, worker tests
are SKIPPED, never PASS. A missing Pillow dependency also leaves decoder coverage incomplete.
The deliberate fault workers use shortened transport deadlines solely to exercise failures;
the production preprocessing policy remains 30 seconds.

## User-run command group B

Use the same software working directory. Python 3.11+ is sufficient; Pillow is optional here.

~~~sh
python -B -m tests.run_group B
~~~

Covers the readiness hand-solvable cases, N3/N5/tiny/rectangular borders and orientation,
coefficient -128, signed24 bias limits, all shifts/ties/neighbors, saturation/ReLU, channel
ordering/serialization/scales, diagnostics and shared-canonical mock integration. It defines
1000 small differential cases with seeds 0x5EED000 through 0x5EED000+999. Cases are generated
only when the user runs tests. No real model/filter release or trained provenance is generated.

The independent oracle builds an explicit zero-padded matrix, computes channel planes, rounds
using quotient/remainder, clamps with independent branches, and packs bytes manually.
It does not call implementation indexing, rounding, clipping, padding or packing helpers.
Shared inputs and immutable Channel records are the independence boundary; the arithmetic
under comparison is not shared. Integration uses an explicitly labeled FixtureDecoder, so it
is software dataflow evidence and not actual Pillow/Linux enforcement evidence.

## Reports and current evidence

Each command creates a unique reports/M2-A-<UTC>-<id>.json or M2-B-<UTC>-<id>.json.
The report records PASS / FAIL / SKIPPED / NOT RUN, actual method/subcase counts, actual started
differential cases/seeds, Python/Pillow/codec observations, separate Linux worker status and
actual successful worker records. Unstarted cases remain NOT RUN after interruption.
Exit 0 means the whole requested group passed, 1 failure/not-run, 2 incomplete skipped coverage.
A Group B report correctly leaves Linux worker enforcement NOT RUN.

[reports/NOT_RUN.md](reports/NOT_RUN.md) retains the original handoff state.
[reports/HOST_EVIDENCE.md](reports/HOST_EVIDENCE.md) records the supplied historical host results
and separates them from the unexecuted new revision. Original JSON reports remain unchanged.
Passing host software tests will not complete M2's real library curation or qualify board safety.

Static source/diff review is the only verification performed by this implementation batch.

## Explicit conversion and offline validation

[CONVERSION.md](CONVERSION.md) documents the known format-2 N3/K8 converter, numerical-only offline context, historical hash domains, new C tests and exact user-run commands. No hardware identity is fabricated; production admission is unchanged. Run A/B/C for new evidence after the shared interface changes. The independent oracle remains unchanged.
