#!/usr/bin/env python3
"""GLM-F3 negative identity tests: every mutation of a release spec's
numerical geometry, canonical shape, profile binding, build identity or
clock must be rejected by research_release.crosscheck BEFORE any render or
Vivado invocation. Host-side only; no hardware, no build tree."""
import json
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import research_release as rr  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CANDIDATES = ["B32_CFGLUT125", "A32_CFGLUT125", "C32_CFGLUT125",
              "D32_CFGLUT125", "D640_CFGLUT125"]


class SpecCrosscheck(unittest.TestCase):
    def setUp(self):
        self.catalog = rr.load_catalog()

    def mutated_spec(self, release_id, **changes):
        spec = rr.parse_spec(release_id)
        spec.update({k: str(v) for k, v in changes.items()})
        return spec

    def test_valid_specs_pass(self):
        for release_id in CANDIDATES:
            with self.subTest(release=release_id):
                spec = rr.parse_spec(release_id)
                rr.crosscheck(spec, self.catalog)  # must not raise

    def test_geometry_mutations_rejected(self):
        for field, bad in (("n", 5), ("k", 4), ("w", 640), ("h", 480)):
            with self.subTest(field=field):
                spec = self.mutated_spec("B32_CFGLUT125", **{field: bad})
                with self.assertRaises(RuntimeError):
                    rr.crosscheck(spec, self.catalog)

    def test_shape_id_mutations_rejected(self):
        for bad in ("N3K16W32H33-CVH1", "N3K16W32H32", "N3K8W32H32-CVH1",
                    "SOMETHING_ELSE"):
            with self.subTest(shape=bad):
                spec = self.mutated_spec("B32_CFGLUT125", shape_id=bad)
                with self.assertRaises(RuntimeError):
                    rr.crosscheck(spec, self.catalog)

    def test_profile_binding_mutation_rejected(self):
        spec = self.mutated_spec("B32_CFGLUT125", profile="B32")
        with self.assertRaises(RuntimeError):
            rr.crosscheck(spec, self.catalog)

    def test_build_id_mutations_rejected(self):
        spec = self.mutated_spec("B32_CFGLUT125",
                                 build_id_hex="45463132354b30384e33573332523031")
        with self.assertRaises(RuntimeError):
            rr.crosscheck(spec, self.catalog)
        # catalog-side profile build ID mismatch is rejected too
        catalog = json.loads(json.dumps(self.catalog))
        catalog["profiles"]["B32_CFGLUT125"]["build_id"] = "1" * 32
        spec = rr.parse_spec("B32_CFGLUT125")
        with self.assertRaises(RuntimeError):
            rr.crosscheck(spec, catalog)

    def test_clock_mutation_rejected_for_cfglut125(self):
        spec = self.mutated_spec("B32_CFGLUT125", clock_mhz=100)
        with self.assertRaises(RuntimeError):
            rr.crosscheck(spec, self.catalog)
        for release_id in CANDIDATES:
            spec = rr.parse_spec(release_id)
            self.assertEqual(int(spec["clock_mhz"]), 125, release_id)

    def test_unknown_release_rejected(self):
        spec = rr.parse_spec("B32_CFGLUT125")
        spec["release_id"] = "X32_CFGLUT125"
        with self.assertRaises(RuntimeError):
            rr.crosscheck(spec, self.catalog)

    def test_rendered_config_requires_exact_deterministic_bytes(self):
        release_id = "A32_CFGLUT125"
        spec = rr.parse_spec(release_id)
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "config_pkg.vhd"
            rr.render_config_pkg(spec, path)
            self.assertEqual(rr.verify_rendered_config(release_id, path), path)
            path.write_bytes(path.read_bytes().replace(b"CFG_BIAS_WIDTH", b"CFG_BIAS_WIDTX", 1))
            with self.assertRaisesRegex(RuntimeError, "stale or modified"):
                rr.verify_rendered_config(release_id, path)


if __name__ == "__main__":
    unittest.main(verbosity=2)
