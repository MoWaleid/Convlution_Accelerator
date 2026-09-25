#!/usr/bin/env python3
"""Create a deterministic FPGA-frame fixture and NumPy tail reference."""

from __future__ import annotations

import argparse
import json
from pathlib import Path

import numpy as np

from .hybrid_reference import HybridClassifier, ProfileAssets, load_grayscale


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path,
                        default=root / "software/classifier/fixtures/B32_alley_cat")
    args = parser.parse_args(argv)
    if args.output.exists():
        raise FileExistsError(f"refusing to overwrite fixture: {args.output}")
    assets = ProfileAssets(
        "B32_CFGLUT125", root / "golden_model/data/trained_k16.pth",
        root / "profiles/B32")
    image_path = (root / "deploy/petalinux/recipes-apps/conv-lab-starter/files/"
                  "dataset/images/alley_cat_s_000013.png")
    image = load_grayscale(image_path)
    classifier = HybridClassifier(assets)
    logits, hardware = classifier.hybrid_logits(image)
    frame = hardware.transpose(1, 2, 0).astype("<i2", copy=False).tobytes()
    args.output.mkdir(parents=True)
    (args.output / "frame.s16le").write_bytes(frame)
    result = {
        "profile": assets.profile,
        "source_image": image_path.name,
        "prediction": classifier.prediction(logits),
        "logits": [float(value) for value in logits],
        "comparison": {"absolute_tolerance": 2e-4, "relative_tolerance": 2e-5},
    }
    (args.output / "reference.json").write_text(
        json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps({"status": "PASS", "output": str(args.output)}))


if __name__ == "__main__":
    main()
