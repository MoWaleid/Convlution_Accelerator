from __future__ import annotations

from pathlib import Path
import unittest

import numpy as np

from classifier.checkpoint_reader import load_checkpoint
from classifier.tail_bundle import load_tail_bundle


ROOT = Path(__file__).resolve().parents[2]


class TailBundleTests(unittest.TestCase):
    def test_exported_b32_tail_is_byte_exact(self):
        bundle = ROOT / "software/classifier/bundles/B32_CFGLUT125"
        manifest, exported = load_tail_bundle(bundle)
        checkpoint = load_checkpoint(ROOT / "golden_model/data/trained_k16.pth")
        self.assertEqual(manifest["profile"], "B32_CFGLUT125")
        for name, actual in exported.items():
            expected = np.ascontiguousarray(
                checkpoint["model_state_dict"][name], dtype="<f4")
            self.assertEqual(actual.dtype, expected.dtype)
            self.assertEqual(actual.shape, expected.shape)
            self.assertEqual(actual.tobytes(), expected.tobytes())


if __name__ == "__main__":
    unittest.main()
