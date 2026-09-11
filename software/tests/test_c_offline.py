"""Offline integration uses the existing independent oracle, never saved .hex."""
import copy
from dataclasses import FrozenInstanceError
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

from conv_lab.admission import AdmissionSession, RecordingMockBackend
from conv_lab.errors import AdmissionError, EnforcementUnavailable
from conv_lab.offline import prepare_offline, audit_anchor, validation_record, main
from conv_lab.preprocessing import _host_supported
from conv_lab.reference import evaluate, scales
from conv_lab.release_io import json_bytes
from conv_lab.strict import sha256
from conv_lab.types import NumericalTarget
from .fixtures import FixtureDecoder, fixture_allocation, platform
from .oracle import oracle
from .test_c_conversion import write_inputs, convert_fixture, TARGET


class OfflineIntegration(unittest.TestCase):
    def test_one_canonical_no_hardware_identity_and_independent_oracle(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-offline-") as tmp:
            source, out = Path(tmp)/"source", Path(tmp)/"converted"
            _, _, _, pixels = write_inputs(source); convert_fixture(source, out)
            decoder = FixtureDecoder(pixels)
            ctx = prepare_offline(out/"model", out/"dataset", "fixture-image", NumericalTarget(*TARGET),
                                  _test_decoder=decoder)
            result = evaluate(ctx)
            self.assertEqual(result.raw, oracle(32, 32, 3, ctx.channels, pixels))
            self.assertEqual(result.values, 8192)
            self.assertEqual(decoder.calls, 1)
            self.assertEqual(result.canonical_sha256, sha256(pixels))
            expected_tx = b"\0"*34+b"".join(b"\0"+pixels[y*32:(y+1)*32]+b"\0" for y in range(32))+b"\0"*34
            self.assertEqual(ctx.padded_tx, expected_tx)
            self.assertEqual(ctx.padded_tx_sha256, sha256(expected_tx))
            self.assertFalse(hasattr(ctx, "hardware"))
            self.assertFalse(hasattr(ctx, "generation"))
            with self.assertRaises(FrozenInstanceError):
                ctx.canonical = b"changed"
            (source/"image.png").write_bytes(b"changed legacy input")
            self.assertEqual(evaluate(ctx).raw, result.raw)
            session = AdmissionSession(platform(*TARGET[:4]), fixture_allocation())
            backend = RecordingMockBackend()
            with self.assertRaises(AdmissionError):
                session.submit(ctx, backend)
            self.assertEqual(backend.events, ())
            record = validation_record(ctx, result)
            self.assertIsNone(record["hardware_identity"])
            self.assertEqual(record["hardware_submission"], "UNAVAILABLE")
            self.assertEqual(record["historical_regression"]["status"], "NOT RUN")
            self.assertEqual(scales(ctx)[0][2].denominator, 256)

    def test_hash_failure_geometry_failure_and_no_decode(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-offline-") as tmp:
            source, out = Path(tmp)/"source", Path(tmp)/"converted"
            _, _, _, pixels = write_inputs(source); convert_fixture(source, out)
            decoder = FixtureDecoder(pixels)
            with self.assertRaises(AdmissionError):
                prepare_offline(out/"model", out/"dataset", "fixture-image", NumericalTarget(31, 32, 3, 8, 24),
                                _test_decoder=decoder)
            (out/"model/weights/kernel_ch7.mem").write_bytes(b"00\n"*9)
            with self.assertRaises(AdmissionError):
                prepare_offline(out/"model", out/"dataset", "fixture-image", NumericalTarget(*TARGET),
                                _test_decoder=decoder)
            self.assertEqual(decoder.calls, 0)

    def test_historical_hash_domains_are_distinct_regression_only(self):
        with tempfile.TemporaryDirectory(prefix="m2-c-offline-") as tmp:
            source, out = Path(tmp)/"source", Path(tmp)/"converted"
            _, _, image, pixels = write_inputs(source); convert_fixture(source, out)
            ctx = prepare_offline(out/"model", out/"dataset", "fixture-image", NumericalTarget(*TARGET),
                                  _test_decoder=FixtureDecoder(pixels))
            expected = oracle(32, 32, 3, ctx.channels, pixels)
            padded = b"\0"*34+b"".join(b"\0"+pixels[y*32:(y+1)*32]+b"\0" for y in range(32))+b"\0"*34
            audit = {"status": "PASS", "image_name": "historical.png",
                     "source_sha256": {"old/golden_model/data/cifar10_images/test/cat/historical.png": sha256(image)},
                     "configs": [[list(c.weights), c.bias, c.shift, c.relu] for c in ctx.channels],
                     "input_sha256": sha256(pixels), "padded_input_sha256": sha256(padded),
                     "expected_output_sha256": sha256(expected)}
            result = evaluate(ctx)
            self.assertEqual(audit_anchor(json_bytes(audit), ctx, result)["status"], "PASS")
            for field in ("input_sha256", "padded_input_sha256", "expected_output_sha256"):
                with self.subTest(field=field):
                    changed = copy.deepcopy(audit); changed[field] = sha256(image)
                    self.assertEqual(audit_anchor(json_bytes(changed), ctx, result)["status"], "FAIL")
            changed = copy.deepcopy(audit); changed["configs"][0][1] += 1
            with self.assertRaises(AdmissionError):
                audit_anchor(json_bytes(changed), ctx, result)
            self.assertEqual(evaluate(ctx).raw, expected)

    def test_cli_has_no_decoder_injection_and_no_production_bypass(self):
        with self.assertRaises(SystemExit):
            main(["--test-decoder", "fixture"])
        with tempfile.TemporaryDirectory(prefix="m2-c-offline-") as tmp:
            source, out = Path(tmp)/"source", Path(tmp)/"converted"
            write_inputs(source); convert_fixture(source, out)
            args = ["--model", str(out/"model"), "--dataset", str(out/"dataset"),
                    "--image-id", "fixture-image", "--W", "32", "--H", "32", "--N", "3", "--K", "8",
                    "--bias-width", "24", "--report-output", str(Path(tmp)/"report")]
            with mock.patch("conv_lab.offline.LinuxDecoder.decode",
                            side_effect=EnforcementUnavailable("unsupported host")):
                self.assertEqual(main(args), 1)
            self.assertFalse((Path(tmp)/"report/output.s16le").exists())


class LinuxOfflineIntegration(unittest.TestCase):
    evidence_domain = "linux_worker_enforcement"

    def test_actual_worker_converter_cli_reference_and_report(self):
        try:
            _host_supported()
        except EnforcementUnavailable as exc:
            self.skipTest(str(exc))
        with tempfile.TemporaryDirectory(prefix="m2-c-linux-") as tmp:
            source, out, report = Path(tmp)/"source", Path(tmp)/"converted", Path(tmp)/"evidence"
            _, _, _, pixels = write_inputs(source); convert_fixture(source, out)
            args = ["--model", str(out/"model"), "--dataset", str(out/"dataset"), "--image-id", "fixture-image",
                    "--W", "32", "--H", "32", "--N", "3", "--K", "8", "--bias-width", "24",
                    "--report-output", str(report)]
            self.assertEqual(main(args), 0)
            r = json.loads((report/"VALIDATION.json").read_bytes())
            self.worker_records = [r["preprocessing"]]
            ctx = prepare_offline(out/"model", out/"dataset", "fixture-image", NumericalTarget(*TARGET))
            self.assertEqual(ctx.canonical, pixels)
            self.assertEqual((report/"output.s16le").read_bytes(), oracle(32, 32, 3, ctx.channels, pixels))
            self.assertEqual(r["status"], "PASS")
            self.assertEqual(r["hashes"]["source_png_or_jpeg"], sha256((source/"image.png").read_bytes()))
            self.assertEqual(r["hashes"]["canonical_pixels"], sha256(pixels))
            self.assertEqual(r["output"]["bytes"], 16384)
            self.assertNotEqual(r["preprocessing"]["pillow_version"], "SYNTHETIC-NO-DECODER")
            self.assertEqual(main(args), 1)
