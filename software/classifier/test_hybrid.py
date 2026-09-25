from __future__ import annotations

import hashlib
import json
from pathlib import Path
import unittest

import numpy as np

from classifier.checkpoint_reader import load_checkpoint
from classifier.hybrid_reference import (
    HybridClassifier, ProfileAssets, fpga_conv1, interleaved_output_sha256,
    load_grayscale,
)


ROOT = Path(__file__).resolve().parents[2]
IMAGE = ROOT / "deploy/petalinux/recipes-apps/conv-lab-starter/files/dataset/images/alley_cat_s_000013.png"
ANCHORS = json.loads((ROOT / "profiles/anchors_m7.json").read_text(encoding="utf-8"))
ASSETS = {
    "A32_CFGLUT125": ProfileAssets("A32_CFGLUT125",
        ROOT / "golden_model/data/trained_model.pth", ROOT / "profiles/A32"),
    "B32_CFGLUT125": ProfileAssets("B32_CFGLUT125",
        ROOT / "golden_model/data/trained_k16.pth", ROOT / "profiles/B32"),
    "C32_CFGLUT125": ProfileAssets("C32_CFGLUT125",
        ROOT / "golden_model/data/trained_n5.pth", ROOT / "profiles/C32"),
}


class HybridClassifierTests(unittest.TestCase):
    def test_checkpoint_metadata_and_shapes(self):
        expected = {
            "A32_CFGLUT125": (3, 8, 68.15),
            "B32_CFGLUT125": (3, 16, 70.08),
            "C32_CFGLUT125": (5, 8, 67.72),
        }
        for profile, assets in ASSETS.items():
            checkpoint = load_checkpoint(assets.checkpoint)
            metadata, state = checkpoint["metadata"], checkpoint["model_state_dict"]
            n, k, accuracy = expected[profile]
            self.assertEqual(metadata["kernel_size"], n)
            self.assertEqual(metadata["num_channels"], k)
            self.assertAlmostEqual(metadata["test_acc"], accuracy, places=2)
            self.assertEqual(state["conv1.weight"].shape, (k, 1, n, n))
            self.assertEqual(state["fc2.weight"].shape, (10, 256))

    def test_fpga_exact_first_layer_matches_qualified_anchors(self):
        image = load_grayscale(IMAGE)
        for profile, assets in ASSETS.items():
            output = fpga_conv1(image, assets.parameters)
            self.assertEqual(interleaved_output_sha256(output),
                             ANCHORS[profile]["output_sha256"])

    def test_hybrid_and_float_inference_are_finite(self):
        image = load_grayscale(IMAGE)
        for assets in ASSETS.values():
            classifier = HybridClassifier(assets)
            float_logits = classifier.float_logits(image)
            hybrid_logits, hardware = classifier.hybrid_logits(image)
            self.assertEqual(float_logits.shape, (10,))
            self.assertEqual(hybrid_logits.shape, (10,))
            self.assertTrue(np.isfinite(float_logits).all())
            self.assertTrue(np.isfinite(hybrid_logits).all())
            self.assertEqual(hardware.shape[1:], (32, 32))
            prediction = classifier.prediction(hybrid_logits)
            self.assertIn(prediction["class_index"], range(10))
            self.assertAlmostEqual(sum(item["confidence"] for item in
                                       classifier.prediction(hybrid_logits)["top3"]),
                                   sum(sorted(_softmax_for_test(hybrid_logits), reverse=True)[:3]),
                                   places=6)


def _softmax_for_test(logits):
    values = np.exp(logits.astype(np.float64) - float(np.max(logits)))
    return values / values.sum()


if __name__ == "__main__":
    unittest.main()
