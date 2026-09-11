# Evidence association for this stage

[Checkpoint](C:/Users/moham/Documents/Codex/2026-09-05/referenced-chatgpt-conversation-this-is-an/M2_real_platform_evidence_20260910_000410_452784_6a3a26b8/ACCEPTANCE.md) preserves originals, safe extraction inventory, source comparisons, candidate/output hashes and platform findings.

| Input archive | Verified SHA-256 |
| --- | --- |
| evidence.tar.gz | 64321d772655b7b5bc95c0f02ecd99eccecaf0c295d52bb8955634b9fbe15631 |
| platform_inputs.tar.gz | f316ed1f1da393c920d9b04dd7a12caadb0304ab48562d17a8ebc61766927520 |
| conv_lab_M2_real_20260909_124553_830.zip | 91939156e0be42b1467c417524fb6db0f9d87d5b773453c520dcfa9b8a19c75e |

COPY_MAP.json identifies each unchanged source/asset copy and intended installed path. Host A/B/C source observations match the 29 transferred Python files; the offline record matches all 16 package files and 12 model/dataset files. Candidate checksum count 14; offline output checksum count 3. Real offline output is 8192 values/16384 bytes with all four historical domains matching.

The preserved executions are user-reported x86_64 results. The assistant performed filesystem/source/JSON checks only, never replayed the tests or decoder/reference. The first staging batch left templates unresolved. Subsequent finalization below supersedes that staging status only; old host PASS does not cover new packaging/helper or ARM execution.

The copied READMEs/NOT RUN references retain their original historical wording as source documentation. Current acceptance scope is this evidence record and checkpoint, not an implicit update inside immutable model/dataset manifests.


## Finalized M2-P package — 2026-09-10

READY FOR USER APPLICATION; evaluated settings, build and ARM validation NOT RUN.
Verified discovery: evidence/recipe_discovery.json, SHA256
618b951d9f4e5c1acb73a270f63b16af617de4b863151e3012e3dac6ea1a5bfd.
Recorded provider/packagegroup/unpack/menu evidence supports the concrete recipes; generated include
files still require the focused evaluated-settings check in README batch 3. Team app/test CLOSED
classification was explicitly approved; the separate starter notice retains unresolved provenance.
No application/test/candidate bytes changed. COPY_MAP.json retains all 47 original associations.

Changed/new integration files in this finalization:
- Three concrete recipes: recipes-apps/conv-lab/conv-lab_0.2.0.bb,
  recipes-apps/conv-lab-starter/conv-lab-starter_1.0.bb,
  recipes-apps/conv-lab-validation/conv-lab-validation_0.2.0.bb.
- recipes-apps/conv-lab-starter/files/PROVENANCE-NOTICE.txt and
  recipes-apps/conv-lab-validation/files/INSTALLED_SHA256SUMS.txt (52 payload hashes).
- apply.py, preflight.py, check_settings.py, check_build_settings.sh.
- APPLICATION_PLAN.json; configuration/original/{rootfs_config,user-rootfsconfig};
  configuration/updated/{rootfs_config,user-rootfsconfig}; evidence/recipe_discovery.json.
- README.md, APPLY.md, DEPENDENCIES.md, EVIDENCE.md, proposed-selection.txt and SHA256SUMS.txt.
- Brief synchronized readiness text in the planning master plan, M1_READINESS.md and
  M1_PLATFORM_AUDIT.md; software/reports/REAL_BUNDLE_EVIDENCE.md references this finalized handoff.

Verification is limited to checksums, exact file/configuration comparisons, static source/syntax
review and documentation consistency. No helper, application import, test, conversion, generator,
training, build, Ubuntu mutation or hardware operation was executed. Immutable M0/M2 records and
pre-existing RTL/project changes remain untouched. Retained .bb.in files are historical and excluded
from the exact application inventory; no files were deleted.

Final static verification: 1010 supplied text/hash records agree; 47/47 copied originals agree; both configuration deltas are exact single-line appends; 34 Python files parse without import/execution; all three concrete recipe SRC_URI inventories exist. The project application inventory contains 56 files and the installed checksum list covers 52 payload files (excluding that list itself). Local handoff links were checked. Shell/recipe commands were reviewed as text, not executed or BitBake-parsed.


## Settings-helper repair — already-applied project, 2026-09-10

User-reported execution: rootfs regeneration succeeded; CONFIG_conv-lab-validation=y survived;
all 76 original stage hashes passed. The settings helper then leaked its output argument into
settings.sh and oe-init-build-env, producing an incorrect PETALINUX and default Poky configuration.
The package/image builds were not reached. Failure transcript source:
C:/Users/moham/.codex/attachments/35e13280-0b66-4a40-9612-437f9bb90f1d/pasted-text.txt.

This repair changes only check_build_settings.sh, README.md, EVIDENCE.md and SHA256SUMS.txt.
It saves/clears positional arguments, validates the fixed tool root, retains SDK host-tool setup
while resetting directory-routing state, requires existing project build configs, sources the
explicit absolute project build directory, checks configuration hash stability and context, and
preserves all six unchanged check_settings.py evaluations. It restores/checks setup exit behavior.
No SDK compatibility, dependency, codec, provider or image-selection check is relaxed.

The README's leading recovery handoff is settings-check ONLY, using a fresh transferable snapshot
and empty output directory. The original application/build workflow is historical for this retry.
Keep the already-applied recipe files, application receipt, old log directory and accidentally
created configuration unchanged. No preflight/apply rerun or configuration regeneration is requested.

Verification for this repair consists only of pre/post SHA256 comparisons and Bash syntax-only
parsing (-n), plus source/document review. Every recipe/application/model/test payload and the
check_settings.py validator is unchanged. The new helper has NOT RUN. No BitBake evaluation, build,
Ubuntu application, tests, configuration tool or hardware command was executed by the assistant.
Upstream setup source was inspected; installed vendor-script byte identity remains unproven.
