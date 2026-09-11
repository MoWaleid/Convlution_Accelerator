# M2 host evidence and current revision status

Recorded 2026-09-09. [Preserved acceptance record](C:/Users/moham/Documents/Codex/2026-09-05/referenced-chatgpt-conversation-this-is-an/M2_host_evidence_20260909_081514_455_7085f2de/ACCEPTANCE.md) and its SHA256SUMS.txt are authoritative for the transferred historical source snapshot. Original JSON reports are unchanged. NOT_RUN.md is the earlier implementation handoff, retained as history.

| Supplied execution report | Methods | Passing subcases | Worker enforcement |
| --- | --- | ---: | --- |
| Windows A | 26 PASS, 9 SKIPPED | 105 | SKIPPED |
| Windows B | 1008 PASS | 706 | NOT RUN in B |
| Linux A | 35 PASS | 122 | PASS |
| Linux B | 1008 PASS | 706 | NOT RUN in B |

Both B runs cover the same 1000 distinct seeds (99536896..99537895), all PASS. Linux is user-reported Ubuntu, x86_64; its report records Linux 6.8.0-138-generic/glibc2.35. It is not ARM/PetaLinux evidence. Windows A/B: Python 3.13.14, Pillow 12.2.0, JPEG 8.0, zlib 1.3.1.zlib-ng. Linux A/B: Python 3.13.15, Pillow 12.2.0, JPEG 6.2, zlib 1.2.11. Full version strings are in original reports.

The assistant verified supplied Linux report/archive hashes, recounted report records and checked five copied originals plus all eight checkpoint manifest entries. All 30 ZIP entries matched pre-edit workstation files. Reports lack a commit/source-archive digest binding execution to the archive; transfer association is user-reported. No host tests were rerun by the assistant.

New version 0.2.0-m2-conversion adds converter/offline tooling and changes shared types/reference/report interfaces. **C tests, A/B reruns for this revision, real conversion and offline integration remain NOT RUN.** Static source parsing is not a runtime test. Old PASS results do not automatically qualify modified code.

[CONVERSION.md](../CONVERSION.md) supplies exact user-run commands and Linux transfer prerequisites. No real bundle, custom filters, additional trained profile, training/export, build or hardware test was generated/run. Licensing/full training provenance, real library curation, deployed platform and board qualification remain open. No full M1/M2/library/board completion is declared.
