"""End-to-end tests for software/m8_import.py (no hardware): fixture bundles,
validation positives/negatives, identity collisions, idempotent re-import,
bounded/safe extraction, and the receipt trail.

Usage (repo root, venv python):
    python verification/m8_import/test_import.py
"""
import hashlib
import io
import json
import os
import sys
import tarfile
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "software"))

_BASE = Path(tempfile.mkdtemp(prefix="m8_import_base_"))
os.environ["M8_IMPORT_ROOT"] = str(_BASE)
import m8_import as MI   # noqa: E402  (reads M8_IMPORT_ROOT at import)


def mem_text(values):
    return "".join(f"{v & 0xFF:02X}\n" for v in values).encode("ascii")


def sha(data):
    return hashlib.sha256(data).hexdigest()


def model_files(*, model_id="test-filter", release="1.0.0", k=2, n=3,
                bias=100, shift=8, relu=False, relu_required=False,
                min_bias_width=24, duplicate_key=False, bad_id=False,
                bias_over=False, shift_bad=False, wrong_weight_hash=False,
                traversal=False):
    """Return {relpath: bytes} for a fixture model bundle, mutated by kwargs."""
    files = {}
    weight_hashes = []
    for ch in range(k):
        data = mem_text([((0x40 + 0x10 * ch + i) % 256) for i in range(n * n)])
        files[f"weights/kernel_ch{ch}.mem"] = data
        weight_hashes.append(sha(data))
    cc = {"format_version": 3,
          "input_scale": {"numerator": 1, "denominator": 256},
          "channels": [{"channel": ch,
                        "weights_file": f"weights/kernel_ch{ch}.mem",
                        "bias_quantized": bias, "shift": shift,
                        "relu_en": relu,
                        "weight_scale": {"numerator": 1, "denominator": 128}}
                       for ch in range(k)]}
    if bias_over:
        cc["channels"][0]["bias_quantized"] = 1 << min_bias_width
    if shift_bad:
        cc["channels"][0]["shift"] = 32
    cc_bytes = json.dumps(cc, indent=1).encode()
    files["channel_config.json"] = cc_bytes
    weights_refs = [{"path": f"weights/kernel_ch{c}.mem",
                     "sha256": weight_hashes[c]} for c in range(k)]
    if wrong_weight_hash:
        weights_refs[0]["sha256"] = "0" * 64
    if traversal:
        weights_refs[0]["path"] = "../outside.mem"
    manifest = {
        "schema_version": 1, "model_id": model_id, "release_version": release,
        "kind": "custom",
        "compatibility": {
            "N": n, "K": k,
            "geometry": [{"W": 32, "H": 32}],
            "geometry_policies": ["exact"],
            "numerical": {"pixel_width": 8, "weight_width": 8,
                          "output_width": 16, "min_bias_width": min_bias_width,
                          "relu_required": relu_required},
            "abi": {"magic": "43564831",
                    "versions": [{"major": 1, "minor": 0}]}},
        "channel_config": {"path": "channel_config.json", "sha256": sha(cc_bytes)},
        "weights": weights_refs,
        "optional_assets": []}
    if bad_id:
        manifest["model_id"] = "Bad-Filter"
    if duplicate_key:
        text = json.dumps(manifest, indent=1)
        text = text.replace('"schema_version": 1,',
                            '"schema_version": 1, "schema_version": 1,', 1)
        files["model.json"] = text.encode()
    else:
        files["model.json"] = json.dumps(manifest, indent=1).encode()
    return files


def dataset_files(*, dataset_id="test-images", release="1.0.0",
                  bad_policy=False):
    from PIL import Image
    buf = io.BytesIO()
    Image.frombytes("L", (8, 8), bytes(range(64))).save(buf, format="PNG")
    png = buf.getvalue()
    policy, filt = ("crop", "NONE") if bad_policy else ("exact", "NONE")
    manifest = {
        "schema_version": 1, "dataset_id": dataset_id,
        "release_version": release,
        "images": [{"image_id": "tiny", "source": {"path": "images/tiny.png",
                                                   "sha256": sha(png)},
                    "preprocessing": {"geometry_policy": policy,
                                      "resize_filter": filt}}]}
    return {"dataset.json": json.dumps(manifest, indent=1).encode(),
            "images/tiny.png": png}


def tar_bytes(files, extra_members=0, traversal_member=False):
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for name, data in files.items():
            info = tarfile.TarInfo(name)
            info.size = len(data)
            tf.addfile(info, io.BytesIO(data))
        for i in range(extra_members):
            info = tarfile.TarInfo(f"pad/file{i:03d}.txt")
            info.size = 1
            tf.addfile(info, io.BytesIO(b"x"))
        if traversal_member:
            info = tarfile.TarInfo("../evil.txt")
            info.size = 1
            tf.addfile(info, io.BytesIO(b"x"))
    return buf.getvalue()


class ImportTests(unittest.TestCase):
    def write_transport(self, files, **kw):
        fd, path = tempfile.mkstemp(suffix=".tgz")
        os.close(fd)
        Path(path).write_bytes(tar_bytes(files, **kw))
        self.addCleanup(os.unlink, path)
        return path

    def test_model_import_idempotent_and_listed(self):
        t = self.write_transport(model_files(model_id="alpha-filter"))
        r1 = MI.import_bundle(t)
        self.assertEqual(r1["outcome"], "imported")
        target = MI.LIBRARY / "models" / "alpha-filter" / "1.0.0"
        self.assertTrue((target / "model.json").is_file())
        self.assertTrue((target / "weights" / "kernel_ch1.mem").is_file())
        self.assertTrue(any((MI.RECEIPTS).glob("*alpha-filter*.json")))
        r2 = MI.import_bundle(t)
        self.assertEqual(r2["outcome"], "already-imported")
        listing = io.StringIO()
        from contextlib import redirect_stdout
        with redirect_stdout(listing):
            MI.cmd_list(None)
        self.assertIn("models alpha-filter/1.0.0", listing.getvalue())

    def test_hash_mismatch_rejected_without_publish(self):
        t = self.write_transport(model_files(model_id="beta", wrong_weight_hash=True))
        with self.assertRaisesRegex(Exception, "hash mismatch"):
            MI.import_bundle(t)
        self.assertFalse((MI.LIBRARY / "models" / "beta").exists())

    def test_duplicate_key_rejected(self):
        t = self.write_transport(model_files(model_id="gamma", duplicate_key=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)
        self.assertFalse((MI.LIBRARY / "models" / "gamma").exists())

    def test_bad_identity_rejected(self):
        t = self.write_transport(model_files(model_id="delta", bad_id=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)

    def test_bias_out_of_signed24_rejected(self):
        t = self.write_transport(model_files(model_id="eps", bias_over=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)

    def test_shift_out_of_range_rejected(self):
        t = self.write_transport(model_files(model_id="zeta", shift_bad=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)

    def test_relu_required_mismatch_rejected(self):
        t = self.write_transport(model_files(model_id="eta", relu=False,
                                             relu_required=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)

    def test_traversal_fileref_rejected(self):
        t = self.write_transport(model_files(model_id="theta", traversal=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)

    def test_collision_rejected_original_intact(self):
        t1 = self.write_transport(model_files(model_id="iota", release="2.0.0"))
        MI.import_bundle(t1)
        target = MI.LIBRARY / "models" / "iota" / "2.0.0" / "model.json"
        before = target.read_bytes()
        t2 = self.write_transport(model_files(model_id="iota", release="2.0.0",
                                              k=2, bias=999))
        with self.assertRaisesRegex(Exception, "collision"):
            MI.import_bundle(t2)
        self.assertEqual(target.read_bytes(), before)

    def test_hardware_bundle_rejected(self):
        t = self.write_transport({"hardware.json": b"{}"})
        with self.assertRaisesRegex(Exception, "not supported"):
            MI.import_bundle(t)

    def test_no_manifest_rejected(self):
        t = self.write_transport({"readme.txt": b"hi"})
        with self.assertRaisesRegex(Exception, "no model.json"):
            MI.import_bundle(t)

    def test_member_limit_enforced(self):
        t = self.write_transport(model_files(model_id="kappa"), extra_members=300)
        with self.assertRaisesRegex(Exception, "members"):
            MI.import_bundle(t)

    def test_traversal_member_rejected(self):
        t = self.write_transport(model_files(model_id="lambda"),
                                 traversal_member=True)
        with self.assertRaisesRegex(Exception, "unsafe member path"):
            MI.import_bundle(t)

    def test_dataset_import(self):
        t = self.write_transport(dataset_files(dataset_id="omega-images"))
        r = MI.import_bundle(t)
        self.assertEqual(r["outcome"], "imported")
        self.assertTrue((MI.LIBRARY / "datasets" / "omega-images" / "1.0.0"
                         / "dataset.json").is_file())

    def test_bad_dataset_policy_rejected(self):
        t = self.write_transport(dataset_files(dataset_id="sigma",
                                               bad_policy=True))
        with self.assertRaises(Exception):
            MI.import_bundle(t)


from conv_lab.errors import AdmissionError  # noqa: E402  (after env setup)

if __name__ == "__main__":
    unittest.main(verbosity=2)
