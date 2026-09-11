"""User-run synthetic conversion/offline tests. Never reads M0 or real assets."""
import copy
from fractions import Fraction
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from conv_lab.admission import AdmissionSession, RecordingMockBackend
from conv_lab.bundles import read_bundle
from conv_lab.convert_legacy import convert, verify_provenance, main as convert_main
from conv_lab.errors import AdmissionError, EnforcementUnavailable
from conv_lab.legacy import conversion_plan, validate_legacy
from conv_lab.offline import prepare_offline, audit_anchor, validation_record, main as offline_main
from conv_lab.preprocessing import LinuxDecoder, _host_supported
from conv_lab.reference import evaluate, scales
from conv_lab.release_io import write_new_tree, json_bytes
from conv_lab.schemas import model
from conv_lab.strict import sha256
from conv_lab.types import NumericalTarget
from .fixtures import png, FixtureDecoder, fixture_allocation, platform
from .oracle import oracle

IDS = dict(model_id="test-trained", model_release="test-1", dataset_id="test-images",
           dataset_release="test-1", image_id="fixture-image")
TARGET = (32, 32, 3, 8, 24)


def inputs():
    # Constructed synthetic fields/weights only; not the historical trained arrays.
    channels = [dict(channel=i, source_channel=i, shift=8, weight_fraction_bits=8,
                     bias_fraction_bits=16, bias_quantized=(i-4)*100, relu_en=i % 2)
                for i in range(8)]
    cfg = dict(format_version=2, N=3, K=8, boundary_mode="same", stride=1,
               pixel_format="uint8_q0.8", input_scale_divisor=256, coefficient_format="int8_raw",
               bias_bits=32, output_format="int16_q8", output_fraction_bits=8,
               accumulator_width_min=21, channels=channels)
    weights = {i: b"80\r\nff\r\n01\r\n02\r\n03\r\n04\r\n05\r\n06\r\n7f" for i in range(8)}
    pixels = bytes(i % 256 for i in range(1024))
    return cfg, weights, png(32, 32, pixels), pixels


def write_inputs(root):
    cfg, weights, image, pixels = inputs()
    root = Path(root); root.mkdir()
    (root/"weights").mkdir()
    (root/"weights/channel_config.json").write_bytes(json_bytes(cfg))
    for i, data in weights.items():
        (root/f"weights/kernel_ch{i}.mem").write_bytes(data)
    (root/"image.png").write_bytes(image)
    return cfg, weights, image, pixels


def convert_fixture(root, output):
    return convert(source_config=root/"weights/channel_config.json", weights_dir=root/"weights",
                   source_png=root/"image.png", output_root=output, **IDS)


class LosslessConversion(unittest.TestCase):
    def test_lossless_values_mapping_scales_and_bytes(self):
        cfg, weights, image, _ = inputs()
        cfg["channels"].reverse()
        files, record = conversion_plan(json_bytes(cfg), weights, image, **IDS)
        converted = json.loads(files["model/channel_config.json"])
        self.assertEqual(converted["input_scale"], {"numerator": 1, "denominator": 256})
        for i, c in enumerate(converted["channels"]):
            original = next(c for c in cfg["channels"] if c["channel"] == i)
            self.assertEqual(c["channel"], i)
            self.assertEqual(c["bias_quantized"], original["bias_quantized"])
            self.assertEqual(c["shift"], original["shift"])
            self.assertIs(type(c["relu_en"]), bool)
            self.assertEqual(c["relu_en"], bool(original["relu_en"]))
            self.assertEqual(c["weights_file"], f"weights/kernel_ch{i}.mem")
            self.assertEqual(files["model/"+c["weights_file"]], b"80\nFF\n01\n02\n03\n04\n05\n06\n7F\n")
        self.assertEqual(files["dataset/images/fixture-image.png"], image)
        self.assertEqual(record["requantization"], "NONE")
        self.assertFalse(any(p.endswith((".hex", ".pth")) for p in files))
        self.assertNotIn("hardware/hardware.json", files)

    def test_scales_derived_per_channel_not_fixed_eight(self):
        cfg, weights, _, _ = inputs()
        for i, c in enumerate(cfg["channels"]):
            c.update(weight_fraction_bits=i, bias_fraction_bits=i+8, shift=i)
        _, v3, _, mapping = validate_legacy(json_bytes(cfg), weights)
        for i, c in enumerate(v3["channels"]):
            self.assertEqual(c["weight_scale"], {"numerator": 1, "denominator": 1 << i})
            self.assertEqual(mapping[i]["output_scale"], {"numerator": 1, "denominator": 256})

    def test_bias_endpoints_no_clipping(self):
        cfg, weights, _, _ = inputs()
        for value in (-(1 << 23), (1 << 23)-1):
            with self.subTest(value=value):
                cfg["channels"][0]["bias_quantized"] = value
                self.assertEqual(validate_legacy(json_bytes(cfg), weights)[1]["channels"][0]["bias_quantized"], value)
        for value in (-(1 << 23)-1, 1 << 23, True, 1.0, "1"):
            with self.subTest(rejected=value), self.assertRaises(AdmissionError):
                cfg["channels"][0]["bias_quantized"] = value
                validate_legacy(json_bytes(cfg), weights)

    def test_malformed_legacy_root_fields(self):
        cfg, weights, _, _ = inputs()
        bad = {"format_version": [True, 3, 2.0], "N": [5, True], "K": [4, 9],
               "boundary_mode": ["valid"], "stride": [2, True], "pixel_format": ["uint8"],
               "input_scale_divisor": [255, True], "coefficient_format": ["q8"], "bias_bits": [24, True],
               "output_format": ["int16_q7"], "output_fraction_bits": [-1, 16, True],
               "accumulator_width_min": [20, True], "extra": [1], "extensions": [{}]}
        for key, values in bad.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(AdmissionError):
                    altered = copy.deepcopy(cfg); altered[key] = value
                    validate_legacy(json_bytes(altered), weights)
        raw = json_bytes(cfg)
        with self.assertRaises(AdmissionError):
            validate_legacy(raw.replace(b'"format_version": 2', b'"format_version": 2, "format_version": 2'), weights)
        for key in list(cfg):
            with self.subTest(missing=key), self.assertRaises(AdmissionError):
                altered = copy.deepcopy(cfg); del altered[key]
                validate_legacy(json_bytes(altered), weights)

    def test_channel_types_mapping_and_scale_inconsistencies(self):
        cfg, weights, _, _ = inputs()
        bad = {"channel": [True, 1, -1, 8], "source_channel": [1, True],
               "shift": [7, -1, 32, True], "weight_fraction_bits": [7, -1, 39, True],
               "bias_fraction_bits": [15, True], "relu_en": [True, False, 2, "1", None],
               "extra": [0], "extensions": [{}]}
        for key, values in bad.items():
            for value in values:
                with self.subTest(key=key, value=value), self.assertRaises(AdmissionError):
                    altered = copy.deepcopy(cfg); altered["channels"][0][key] = value
                    validate_legacy(json_bytes(altered), weights)
        with self.assertRaises(AdmissionError):
            altered = copy.deepcopy(cfg); altered["channels"].pop()
            validate_legacy(json_bytes(altered), weights)

    def test_weights_and_png_rejections(self):
        cfg, weights, image, _ = inputs()
        for data in (b"00\n"*8, b"00\n"*10, b" 00\n"*9, b"# comment\n"+weights[0]):
            with self.subTest(data=data), self.assertRaises(AdmissionError):
                validate_legacy(json_bytes(cfg), weights | {0: data})
        for bad in (b"not png", image[:-4], png(31, 32, bytes(31*32)),
                    png(32, 32, bytes(1024), extras=((b"tRNS", b"\0\0"),))):
            with self.subTest(image_length=len(bad)), self.assertRaises(AdmissionError):
                conversion_plan(json_bytes(cfg), weights, bad, **IDS)

    def test_cli_conversion_existing_output_and_manifest(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-") as tmp:
            root, output = Path(tmp)/"source", Path(tmp)/"converted"
            _, _, image, _ = write_inputs(root)
            argv = ["--source-config", str(root/"weights/channel_config.json"), "--weights-dir", str(root/"weights"),
                    "--source-png", str(root/"image.png"), "--output-root", str(output)]
            for key, value in IDS.items():
                argv += ["--"+key.replace("_", "-"), value]
            self.assertEqual(convert_main(argv), 0)
            mb = read_bundle(output/"model", "model")
            model(mb, NumericalTarget(*TARGET))
            self.assertEqual((output/"dataset/images/fixture-image.png").read_bytes(), image)
            sums = (output/"SHA256SUMS.txt").read_text().splitlines()
            for line in sums:
                digest, path = line.split("  ", 1)
                self.assertEqual(sha256((output/path).read_bytes()), digest)
            before = {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()}
            self.assertEqual(convert_main(argv), 1)
            self.assertEqual(before, {p.relative_to(output): p.read_bytes() for p in output.rglob("*") if p.is_file()})

    def test_no_output_on_rejected_input_or_headroom(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-") as tmp:
            root, output = Path(tmp)/"source", Path(tmp)/"out"
            write_inputs(root)
            with mock.patch("conv_lab.release_io.shutil.disk_usage", return_value=type("D", (), {"free": 10})()):
                with self.assertRaises(AdmissionError):
                    convert_fixture(root, output)
            self.assertFalse(output.exists())
            with self.assertRaises(AdmissionError):
                convert_fixture(root, root/"must-not-write-here")
            self.assertFalse((root/"must-not-write-here").exists())
            (root/"weights/kernel_ch8.mem").write_bytes(b"00\n"*9)
            with self.assertRaises(AdmissionError):
                convert_fixture(root, output)
            self.assertFalse(output.exists())

    def test_checkpoint_and_audit_association(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-") as tmp:
            root = Path(tmp)
            rel = "current_project/golden_model/data/weights/channel_config.json"
            (root/rel).parent.mkdir(parents=True)
            (root/rel).write_bytes(b"test bytes")
            audit = root/"audit.json"
            audit.write_bytes(json_bytes({"status": "PASS", "source_sha256": {
                r"D:\old\golden_model\data\weights\channel_config.json": sha256(b"test bytes")}}))
            (root/"SHA256SUMS.txt").write_text(
                sha256(b"test bytes")+"  "+rel+"\n"+sha256(audit.read_bytes())+"  audit.json\n")
            evidence = verify_provenance([(root/rel, b"test bytes")], root, audit)
            self.assertEqual(evidence["status"], "CHECKPOINT_AND_AUDIT_HASH_MATCH")
            with self.assertRaises(AdmissionError):
                verify_provenance([(root/rel, b"changed")], root, audit)
