# Explicit legacy conversion and Linux offline validation

Added 2026-09-09. **New implementation/tests NOT RUN; no real bundle generated.**
Historical A/B PASS applies to the separately preserved previous source snapshot. Run A/B again
for this revision as well as new C tests: immutable types/reference interfaces and the report
harness changed. The arithmetic algorithm and independent oracle remain unchanged.

## Scope and boundaries

legacy.py supports the known format-2 N3/K8 trained convention only: same padding, stride one,
uint8_q0.8 with divisor 256, int8_raw coefficients, signed32 legacy bias metadata and int16_q<F>
with F in 0..15. Unknown fields (including legacy extensions), unsupported conventions and
source-channel remapping reject. This adapter does not admit additional trained profiles.

Each weight fraction comes from metadata, not an assumption of 8:
bias_fraction_bits=8+weight_fraction_bits and shift=bias_fraction_bits-output_fraction_bits.
Exact scales are input=1/256, weight=1/(2**weight_fraction_bits), bias=input*weight and
output=bias*(2**shift)=1/(2**output_fraction_bits). Shifts must fit 0..31 and biases signed24.
No clipping, wrapping or requantization. Only validated integer 0/1 ReLU becomes JSON boolean.
Every coefficient, bias, shift and channel mapping is preserved. MEM formatting becomes
uppercase two-digit bytes, LF, one terminal newline; original/converted byte hashes stay separate.

PNG structural metadata is checked within the source-byte limit; original PNG bytes are copied
unchanged. Conversion does not decode. The dataset uses exact/NONE and model geometry 32x32.
Actual EXIF/grayscale/geometry/resource validation uses the approved Linux worker offline.

Output has schema-1 model/ and dataset/ bundles with format-3 channel configuration. External
CONVERSION.json records provenance; SHA256SUMS.txt excludes itself and COMPLETE.json is written
last. There is no hardware manifest, PS digest, build ID, synthetic label, expected .hex or .pth.

NumericalTarget/OfflineContext contain numerical requirements, without hardware identity,
allocation or generation. AdmissionSession cannot submit them. Production admission remains
prohibited. The offline CLI has no backend/submission or decoder-injection option. Its private
Python _test_decoder seam is for trusted synthetic tests only. ABI compatibility remains a
model requirement, not a fabricated hardware fact.

## Output and provenance rules

Parent directories must exist; output must be a new path, including symlink checks. Conversion
refuses output within input/checkpoint directories; offline reports must be outside model/dataset
roots. Exclusive mkdir/file writes prevent overwrite. Output is bounded to 32 MiB/256 supplied
members, with reserved metadata and the approved 512 MiB free-space headroom. Each written file
is hash verified. This offline candidate writer does not insert releases into a deployed catalog;
later import must enforce cross-library identity collisions.

Multi-file visibility is not atomic. Without COMPLETE.json, treat the retained directory as
failed staging; nothing is deleted or silently reused. Choose a new path after failure.
Completion means writing finished, not qualification. Filesystem quota, deployment, licensing,
backup and power-loss recovery qualification remain separate.

--checkpoint-root and --historical-audit must be supplied together, or both omitted. With them,
the converter checks actual input bytes against the frozen manifest and audit's unique original
path mapping; it never reads mutable historical paths. Without both, provenance is explicitly
unverified. Use both for this candidate. Source paths/hashes, mapping, scale derivation, output
hashes/exclusions and observed package-source hashes are recorded. Source observations are not
authenticated execution attestation.

## Initial frozen candidate and historical hash domains

Root:
D:\MyProjects\release_checkpoints\M0_k8_len16_20260907_052648_358\current_project\golden_model\data

Ten candidate inputs match both checkpoint entries and historical source hashes: configuration,
eight kernels, PNG. Five provenance files also match M0: SOURCE_MAP.md, preserved vector audit,
verification script, trained runner and exporter. The planning audit matches its preserved copy.
Inspected metadata declares input 1/256, all weight fractions 8, all shifts 8, bias fractions 16,
output fraction 8 and signed24-compatible biases. These are file checks, not fresh execution.

Reading preserved verify_trained_vectors.py establishes:

| Historical field | Byte domain | SHA-256 |
| --- | --- | --- |
| PNG entry in source_sha256 | Original encoded PNG | 200f5baa120d957838037c7e28052ac998e82ddd94aef937173e37c3dfb470b0 |
| input_sha256 | 1024 grayscale canonical uint8 bytes | a240bb760e2a85951f5c4e27c95041e98d4919c5cc32114cc4f5191f6ffb6771 |
| padded_input_sha256 | 1156 bytes, zero-padded 34x34 TX | 967c1c7687d3775d4512bd30eaa7f07fc8e1956145ed82326b35eb8cff28f74e |
| expected_output_sha256 | 16384 bytes, 8192 channel-fast little-endian signed16 values | cb3975593073652b9d5f2fcb206748ad70c4abf621339ea19878b6863d9be705 |

The input.hex text-file hash is neither canonical-pixel nor PNG hash. No saved .hex is a runtime
input. The reference computes from actual decoded pixels/parameters before historical checks;
audit arrays only verify association, never supply parameters. Historical hashes are additional
regression anchors, not an algorithm or sole oracle. B/C retain the independently structured oracle.
Licensing/redistribution permission and complete training lineage remain unresolved; checksums do
not grant permission. No source-to-bitstream equivalence or curated-library qualification follows.

## User-run tests

Working directory: D:\MyProjects\Convlution_Accelerator\software
Python 3.11+; full Linux C integration additionally needs Pillow with PNG/JPEG support under -I.
Use README.md's dependency-check commands; no dependency was checked/installed by this task.

~~~sh
python -B -m tests.run_group C
python -B -m tests.run_group A
python -B -m tests.run_group B
~~~

C defines 14 planned methods, not executed cases: lossless conversion, malformed metadata,
ranges/scales/mapping, output refusal, provenance mapping, immutable offline integration,
historical hash domains and one actual Linux integration case. Windows skips that Linux case;
C is not a substitute for all A enforcement tests. B retains 1000 seeded differential cases.
Reports are software/reports/M2-C-*.json, M2-A-*.json and M2-B-*.json, with actual statuses/counts,
versions/seeds and observed package/test source hashes. All current-revision results remain NOT RUN.

## User-run Windows conversion (PowerShell)

These commands are for later execution after reviewing test results. Labels identify unqualified
candidates, not approved production releases. Existing output is refused.

~~~powershell
Set-Location -LiteralPath 'D:\MyProjects\Convlution_Accelerator\software'
$m0 = 'D:\MyProjects\release_checkpoints\M0_k8_len16_20260907_052648_358'
$data = Join-Path $m0 'current_project\golden_model\data'
python -B -m conv_lab.convert_legacy --source-config "$data\weights\channel_config.json" --weights-dir "$data\weights" --source-png "$data\cifar10_images\test\cat\alley_cat_s_000013.png" --output-root 'D:\MyProjects\release_checkpoints\M2_trained_cifar_k8_candidate_v1' --model-id m0-trained-cifar-k8 --model-release converted-1 --dataset-id m0-cifar-cat --dataset-release converted-1 --image-id alley_cat_s_000013 --checkpoint-root "$m0" --historical-audit "$m0\external\planning_workspace\trained_cifar_vector_audit.json"
~~~

## Linux transfer prerequisites and offline validation

Transfer the UPDATED software tree (the old ZIP lacks this implementation), complete candidate
directory including checksum/completion/provenance files, and preserved trained_cifar_vector_audit.json.
Verify candidate files using its SHA256SUMS.txt. The audit SHA-256 is
31ff39dc84828e4fa7e72bd1b80c5df45dcf4306496224f2f61cc4b8c449ac43.
No expected .hex/.pth is needed. Prepare an ordinary unprivileged Linux Python 3.11+/Pillow
environment; root or unavailable enforcement fails closed. Do not assume Ubuntu has Pillow.

Actual next-transfer paths are unknown. Replace the explicit path selections below with prepared
locations; do not assume the old temporary Ubuntu checkout contains new code. Report parent must
exist, and the report directory must be new.

~~~sh
cd /absolute/path/to/updated/software
python -B -m tests.run_group C
python -B -m conv_lab.offline --model /absolute/path/to/candidate/model --dataset /absolute/path/to/candidate/dataset --image-id alley_cat_s_000013 --W 32 --H 32 --N 3 --K 8 --bias-width 24 --historical-audit /absolute/path/to/trained_cifar_vector_audit.json --report-output /absolute/path/to/new-offline-evidence
~~~

Output contains VALIDATION.json, output.s16le, SHA256SUMS.txt and COMPLETE.json. Records include
numerical target/widths, model/dataset identities and hashes, actual worker/codec versions,
source/canonical/TX/output domains, dimensions/counts, source observations and optional historical
regression status. A historical hash mismatch writes FAIL evidence and exits nonzero.
Admission/worker errors print failure and exit nonzero; no successful result is fabricated.
The reference has no decoder deadline. This command is not new board/ARM/PetaLinux qualification.
