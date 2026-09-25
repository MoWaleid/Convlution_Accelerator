#!/usr/bin/env python3
"""Wrap the qualified runtime and append native B32 classification evidence."""

from __future__ import annotations

import json
from pathlib import Path
import subprocess
import sys
import time

import m8_cli


BINARY = Path("/usr/bin/conv-classify-tail")
BUNDLE = Path("/opt/conv-lab-classifier/B32_CFGLUT125")
CLASSIFIER_PROFILE = "B32_CFGLUT125"


def _records(root: Path) -> set[Path]:
    if not root.is_dir():
        return set()
    return {path for path in root.glob("*/record.json") if path.is_file()}


def _classify(record_path: Path) -> None:
    record = json.loads(record_path.read_text(encoding="utf-8"))
    if record.get("outcome") != "PASS":
        return
    if record.get("profile", {}).get("name") != CLASSIFIER_PROFILE:
        return
    frames = record.get("frames")
    if type(frames) is not list or not frames:
        raise RuntimeError("B32 record has no completed frames")
    frame_path = record_path.parent / f"frame_{len(frames):03d}.s16le"
    if not frame_path.is_file() or frame_path.stat().st_size != 32768:
        raise RuntimeError("B32 classifier frame is missing or malformed")
    if not BINARY.is_file() or not BUNDLE.is_dir():
        raise RuntimeError("native B32 classifier is not installed")

    started = time.perf_counter()
    completed = subprocess.run(
        [str(BINARY), str(BUNDLE), "16", str(frame_path)],
        shell=False, check=True, text=True, capture_output=True, timeout=30)
    process_wall_ms = (time.perf_counter() - started) * 1000.0
    if len(completed.stdout) > 64 * 1024:
        raise RuntimeError("classifier response exceeds limit")
    result = json.loads(completed.stdout)
    if (result.get("status") != "PASS" or
            type(result.get("class_index")) is not int or
            not 0 <= result["class_index"] < 10 or
            type(result.get("class_name")) is not str or
            type(result.get("confidence")) not in (int, float) or
            type(result.get("tail_ms")) not in (int, float) or
            type(result.get("top3")) is not list or len(result["top3"]) != 3):
        raise RuntimeError("classifier returned an invalid result")

    hardware_ms = float(frames[-1]["hw_ms"])
    record["classification"] = {
        "status": "PASS",
        "model": "trained-k16-cifar10",
        "model_test_accuracy_percent": 70.08,
        "class_index": result["class_index"],
        "class_name": result["class_name"],
        "confidence": result["confidence"],
        "top3": result["top3"],
        "logits": result.get("logits"),
        "fpga_conv1_ms": hardware_ms,
        "ps_tail_ms": result["tail_ms"],
        "hybrid_compute_ms": hardware_ms + float(result["tail_ms"]),
        "classifier_process_wall_ms": process_wall_ms,
        "frame": frame_path.name,
    }
    blob = json.dumps(record, indent=2, sort_keys=True) + "\n"
    temporary = record_path.with_suffix(".json.tmp")
    temporary.write_text(blob, encoding="utf-8")
    temporary.replace(record_path)
    (record_path.parent / "classification.json").write_text(
        json.dumps(record["classification"], indent=2, sort_keys=True) + "\n",
        encoding="utf-8")
    print(f"HYBRID CLASSIFICATION: {result['class_name']} "
          f"({100.0 * float(result['confidence']):.1f}%), "
          f"FPGA {hardware_ms:.3f} ms + PS {float(result['tail_ms']):.3f} ms",
          flush=True)


def main() -> None:
    root, _ = m8_cli.archive_root()
    before = _records(root)
    m8_cli.main()
    created = sorted(_records(root) - before, key=lambda path: path.stat().st_mtime_ns)
    for record_path in created:
        _classify(record_path)


if __name__ == "__main__":
    main()
