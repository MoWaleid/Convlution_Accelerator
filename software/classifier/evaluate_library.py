#!/usr/bin/env python3
"""Evaluate float and FPGA-first-layer hybrid inference on a labeled library."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import time

from .hybrid_reference import CLASS_NAMES, HybridClassifier, ProfileAssets, load_grayscale


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def parameter_identity(directory: Path) -> dict:
    files = [directory / "channel_config.json", *sorted(directory.glob("kernel_ch*.mem"))]
    return {path.name: sha256(path) for path in files}


def evaluate(profile: str, assets: ProfileAssets, image_root: Path) -> dict:
    classifier = HybridClassifier(assets)
    rows = []
    started = time.perf_counter()
    for class_index, class_name in enumerate(CLASS_NAMES):
        paths = sorted((image_root / class_name).glob("*.png"))
        if not paths:
            raise ValueError(f"no PNG inputs for {class_name}")
        for path in paths:
            image = load_grayscale(path)
            float_prediction = classifier.prediction(classifier.float_logits(image))
            hybrid_logits, _ = classifier.hybrid_logits(image)
            hybrid_prediction = classifier.prediction(hybrid_logits)
            rows.append({
                "image": path.relative_to(image_root).as_posix(),
                "source_sha256": sha256(path),
                "expected_class_index": class_index,
                "expected_class_name": class_name,
                "float": float_prediction,
                "hybrid": hybrid_prediction,
                "predictions_agree": (float_prediction["class_index"] ==
                                      hybrid_prediction["class_index"]),
            })
    count = len(rows)
    float_correct = sum(row["float"]["class_index"] == row["expected_class_index"]
                        for row in rows)
    hybrid_correct = sum(row["hybrid"]["class_index"] == row["expected_class_index"]
                         for row in rows)
    agreement = sum(row["predictions_agree"] for row in rows)
    return {
        "profile": profile,
        "checkpoint": {
            "path": assets.checkpoint.as_posix(),
            "sha256": sha256(assets.checkpoint),
            "metadata": classifier.metadata,
        },
        "parameters": parameter_identity(assets.parameters),
        "images": count,
        "float_correct": float_correct,
        "float_accuracy_percent": 100.0 * float_correct / count,
        "hybrid_correct": hybrid_correct,
        "hybrid_accuracy_percent": 100.0 * hybrid_correct / count,
        "float_hybrid_agreement": agreement,
        "float_hybrid_agreement_percent": 100.0 * agreement / count,
        "elapsed_seconds": time.perf_counter() - started,
        "results": rows,
    }


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--images", type=Path, default=root /
        "deploy/petalinux/recipes-apps/conv-lab-starter/files/demo_library/images")
    parser.add_argument("--output", type=Path, default=root /
        "software/reports/HYBRID_CLASSIFIER_LIBRARY50.json")
    args = parser.parse_args(argv)
    assets = {
        "A32_CFGLUT125": ProfileAssets("A32_CFGLUT125",
            root / "golden_model/data/trained_model.pth", root / "profiles/A32"),
        "B32_CFGLUT125": ProfileAssets("B32_CFGLUT125",
            root / "golden_model/data/trained_k16.pth", root / "profiles/B32"),
        "C32_CFGLUT125": ProfileAssets("C32_CFGLUT125",
            root / "golden_model/data/trained_n5.pth", root / "profiles/C32"),
    }
    report = {
        "schema_version": 1,
        "scope": "50-image official-page CIFAR-10 sample; preliminary, not full test-set accuracy",
        "profiles": [evaluate(profile, item, args.images)
                     for profile, item in assets.items()],
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(report, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    for item in report["profiles"]:
        print(f"{item['profile']}: float={item['float_correct']}/{item['images']} "
              f"({item['float_accuracy_percent']:.1f}%), "
              f"hybrid={item['hybrid_correct']}/{item['images']} "
              f"({item['hybrid_accuracy_percent']:.1f}%), "
              f"agreement={item['float_hybrid_agreement']}/{item['images']} "
              f"({item['float_hybrid_agreement_percent']:.1f}%)")
    print(f"REPORT: {args.output}")


if __name__ == "__main__":
    main()
