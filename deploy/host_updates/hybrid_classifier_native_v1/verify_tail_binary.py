#!/usr/bin/env python3
"""Compare the native PS tail runtime with the frozen NumPy fixture."""

from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import subprocess


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("binary", type=Path)
    parser.add_argument("--bundle", type=Path,
                        default=root / "software/classifier/bundles/B32_CFGLUT125")
    parser.add_argument("--fixture", type=Path,
                        default=root / "software/classifier/fixtures/B32_alley_cat")
    args = parser.parse_args(argv)

    reference = json.loads((args.fixture / "reference.json").read_text(encoding="utf-8"))
    completed = subprocess.run(
        [str(args.binary), str(args.bundle), "16", str(args.fixture / "frame.s16le")],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    actual = json.loads(completed.stdout)
    if actual.get("status") != "PASS":
        raise RuntimeError("native runtime did not report PASS")
    if actual.get("class_index") != reference["prediction"]["class_index"]:
        raise RuntimeError("native prediction differs from NumPy reference")
    tolerance = reference["comparison"]
    expected_logits = reference["logits"]
    actual_logits = actual.get("logits")
    if type(actual_logits) is not list or len(actual_logits) != len(expected_logits):
        raise RuntimeError("native logits have the wrong shape")
    for index, (expected, observed) in enumerate(zip(expected_logits, actual_logits)):
        if not math.isclose(expected, observed,
                            rel_tol=tolerance["relative_tolerance"],
                            abs_tol=tolerance["absolute_tolerance"]):
            raise RuntimeError(
                f"logit {index} mismatch: expected {expected}, observed {observed}")
    print(json.dumps({
        "status": "PASS",
        "class_index": actual["class_index"],
        "class_name": actual["class_name"],
        "confidence": actual["confidence"],
        "tail_ms": actual["tail_ms"],
        "logits_checked": len(actual_logits),
    }, sort_keys=True))


if __name__ == "__main__":
    main()
