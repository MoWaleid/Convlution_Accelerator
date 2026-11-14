#!/usr/bin/env python3
"""Refresh the assembled competition package after report or docstring edits.

The package under ``submission/`` is a path-adapted snapshot of this repository
(``src/`` and ``docs/`` layout). It is never regenerated wholesale: the build
and qualification evidence it carries is frozen. This script only re-syncs the
few files that are intentionally kept identical to their repository sources,
rewrites ``submission/SHA256SUMS.txt``, and rebuilds the two upload files in
``final_upload/``.

Run from the repository root:

    python -B scripts/packaging/refresh_submission.py          # apply
    python -B scripts/packaging/refresh_submission.py --check  # report only
"""
from __future__ import annotations

import argparse
import hashlib
import sys
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PKG = ROOT / "submission"
UPLOAD = ROOT / "final_upload"
MANIFEST = PKG / "SHA256SUMS.txt"
ZIP_NAME = "Attention_is_all_you_need_SSCS_Egypt_2026_Design_Files.zip"
PDF_NAME = "Attention_is_all_you_need_SSCS_Egypt_2026_Report.pdf"
ZIP_STAMP = (2026, 11, 14, 0, 0, 0)

# package path -> repository source kept byte-identical to it
SYNC = {
    "docs/report.md": "report/report.md",
    "docs/report.html": "report/report.html",
    "docs/report.pdf": "report/report.pdf",
    "src/golden_model/golden_conv.py": "golden_model/golden_conv.py",
    "src/golden_model/extract_weights.py": "golden_model/extract_weights.py",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_manifest() -> list[tuple[str, str]]:
    rows = []
    for line in MANIFEST.read_text(encoding="utf-8").splitlines():
        digest, _, rel = line.partition("  ")
        if digest and rel:
            rows.append((digest, rel))
    return rows


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--check", action="store_true",
                        help="report what would change without writing")
    args = parser.parse_args()

    rows = read_manifest()
    listed = {rel for _, rel in rows}
    stale = [p for p in SYNC if p not in listed]
    if stale:
        print("not in manifest:", *stale, sep="\n  ")
        return 1

    # The frozen part of the package must still match its manifest.
    bad = [rel for digest, rel in rows
           if rel not in SYNC and sha256(PKG / rel) != digest]
    if bad:
        print("package files differ from the manifest (refusing to continue):",
              *bad, sep="\n  ")
        return 1

    changed = [p for p, src in SYNC.items()
               if sha256(PKG / p) != sha256(ROOT / src)]
    print("files to refresh:", *(changed or ["(none)"]), sep="\n  ")
    if args.check:
        return 0

    for rel in changed:
        (PKG / rel).write_bytes((ROOT / SYNC[rel]).read_bytes())

    lines = [f"{sha256(PKG / rel)}  {rel}\n" for _, rel in rows]
    MANIFEST.write_text("".join(lines), encoding="utf-8", newline="\n")
    for digest, rel in read_manifest():
        if sha256(PKG / rel) != digest:
            print("manifest verification failed:", rel)
            return 1

    UPLOAD.mkdir(exist_ok=True)
    names = ["README.md", "SHA256SUMS.txt"] + sorted(
        rel for _, rel in rows if rel != "README.md")
    zip_path = UPLOAD / ZIP_NAME
    with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for name in names:
            info = zipfile.ZipInfo(name, ZIP_STAMP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, (PKG / name).read_bytes())
    (UPLOAD / PDF_NAME).write_bytes((PKG / "docs/report.pdf").read_bytes())

    with zipfile.ZipFile(zip_path) as z:
        assert z.testzip() is None and len(z.namelist()) == len(rows) + 1
    print(f"package refreshed: {len(rows)} manifest entries, {zip_path.name}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
