import io
import json
import os
from pathlib import Path
import struct
import subprocess
import sys
import tempfile
import time
import unittest
from unittest import mock

from conv_lab.errors import AdmissionError,EnforcementUnavailable
from conv_lab.preprocessing import (ADDRESS_SPACE_BYTES,LinuxDecoder,TIMEOUT_SECONDS,
                                    _exchange,_host_supported,_worker_slot)
from .fixtures import png


class HostRejectionTests(unittest.TestCase):
    def test_nonlinux_fails_closed(self):
        with mock.patch.object(sys,"platform","win32"),self.assertRaises(EnforcementUnavailable):
            LinuxDecoder().decode(b"source",1,1,"exact")

    def test_root_fails_closed_no_invented_user(self):
        with mock.patch.object(sys,"platform","linux"),mock.patch.object(os,"geteuid",return_value=0,create=True):
            with self.assertRaises(EnforcementUnavailable):
                LinuxDecoder().decode(b"source",1,1,"exact")


class LinuxMechanismTests(unittest.TestCase):
    evidence_domain = "linux_worker_enforcement"

    def setUp(self):
        try:
            _host_supported()
        except EnforcementUnavailable as exc:
            self.skipTest(str(exc))

    def command(self,mode):
        return [sys.executable,"-I","-B",str(Path(__file__).with_name("fault_worker.py")),mode]

    def test_address_space_actually_rejects_allocation(self):
        data = _exchange(self.command("limit"),b"request",4096,5)
        result = json.loads(data)
        self.assertTrue(result["enforced"])
        self.assertGreater(result["uid"],0)
        self.assertLessEqual(result["limit"],ADDRESS_SPACE_BYTES)
        self.assertEqual(TIMEOUT_SECONDS,30)

    def test_single_worker_slot(self):
        with _worker_slot():
            with self.assertRaises(AdmissionError):
                with _worker_slot():
                    self.fail("second worker acquired slot")

    def test_timeout_oversized_output_errors_and_reaping(self):
        for mode in ("timeout","oversize","stderr","fail"):
            with self.subTest(mode=mode):
                children = []
                original = subprocess.Popen
                def tracked(*args,**kwargs):
                    child = original(*args,**kwargs)
                    children.append(child)
                    return child
                with mock.patch("conv_lab.preprocessing.subprocess.Popen",side_effect=tracked):
                    with self.assertRaises(AdmissionError):
                        _exchange(self.command(mode),b"request",100,0.5 if mode == "timeout" else 5)
                self.assertEqual(len(children),1)
                self.assertIsNotNone(children[0].poll())
                self.assertTrue(all(s.closed for s in (children[0].stdin,children[0].stdout,children[0].stderr)))

    def test_partial_and_late_result_not_admitted(self):
        for response in (b"\0\0",struct.pack(">I",20000)+b"x",b""):
            with self.subTest(response=response[:8]),mock.patch("conv_lab.preprocessing._exchange",return_value=response):
                with self.assertRaises(AdmissionError):
                    LinuxDecoder().decode(png(1,1,b"\0"),1,1,"exact")


class LinuxDecoderTests(LinuxMechanismTests):
    # Inherit the environment check only, not the mechanism test methods.
    test_address_space_actually_rejects_allocation = None
    test_single_worker_slot = None
    test_timeout_oversized_output_errors_and_reaping = None
    test_partial_and_late_result_not_admitted = None

    def setUp(self):
        super().setUp()
        try:
            import PIL
        except ImportError:
            self.skipTest("Pillow unavailable; Linux decoder enforcement is NOT PASS")

    def decode(self,data,w,h,policy="exact"):
        result = LinuxDecoder().decode(data,w,h,policy)
        if not hasattr(self,"worker_records"):
            self.worker_records = []
        self.worker_records.append(json.loads(result.record_json))
        return result

    def test_gray_preservation_descriptor_exclusion_and_record(self):
        pixels = bytes((0,7,255,64,128,1))
        with tempfile.TemporaryFile() as sentinel:
            os.set_inheritable(sentinel.fileno(),True)
            result = self.decode(png(3,2,pixels),3,2)
        self.assertEqual(result.canonical,pixels)
        record = json.loads(result.record_json)
        self.assertFalse(record["extensions"]["hardware_descriptors_inherited"])
        self.assertGreater(record["extensions"]["worker_uid"],0)
        self.assertLessEqual(record["extensions"]["address_space_limit"],134217728)
        self.assertTrue(record["extensions"]["no_new_privs"])
        self.assertTrue(record["pillow_version"])
        self.assertTrue(record["decoder_versions"][0]["version"])

    def test_rgb_to_grayscale_png_and_static_jpeg(self):
        from PIL import Image
        pixels = bytes((255,0,0,0,255,0,0,0,255))
        result = self.decode(png(3,1,pixels,color=2),3,1)
        # Pillow's documented ordinary RGB -> L conversion; hand-sized expected values.
        self.assertEqual(result.canonical,bytes((76,150,29)))
        image = Image.new("L",(2,2),128)
        out = io.BytesIO(); image.save(out,format="JPEG")
        self.assertEqual(self.decode(out.getvalue(),2,2).canonical,b"\x80"*4)

    def test_exif_orientation_before_geometry_and_explicit_resize(self):
        from PIL import Image
        image = Image.frombytes("L",(2,3),bytes((1,2,3,4,5,6)))
        exif = Image.Exif(); exif[274] = 6
        out = io.BytesIO(); image.save(out,format="PNG",exif=exif)
        result = self.decode(out.getvalue(),3,2)
        self.assertEqual(result.canonical,bytes((5,3,1,6,4,2)))
        with self.assertRaises(AdmissionError):
            self.decode(out.getvalue(),2,3)
        resized = self.decode(out.getvalue(),4,4,"resize_exact")
        record = json.loads(resized.record_json)
        self.assertEqual(len(resized.canonical),16)
        self.assertEqual(record["resize_filter"],"LANCZOS")
        self.assertTrue(record["aspect_ratio_changed"])
        # A constant image is hand-solvable under LANCZOS.
        self.assertEqual(self.decode(png(2,1,b"\x2a\x2a"),5,3,"resize_exact").canonical,b"\x2a"*15)
        # Source limits are not independently imposed as compiled target dimensions.
        self.assertEqual(self.decode(png(1,1,b"\x2a"),8192,1,"resize_exact").canonical,b"\x2a"*8192)

    def test_unsupported_modes_transparency_animation_and_corruption(self):
        from PIL import Image
        cases = [b"invalid",png(1,1,b"\0")[:-1],png(1,1,b"\0",depth=16),
                 png(1,1,b"\0",extras=((b"tRNS",b"\0\0"),))]
        for mode in ("1","P","RGBA","I;16"):
            out = io.BytesIO()
            Image.new(mode,(2,2)).save(out,format="PNG")
            cases.append(out.getvalue())
        out = io.BytesIO()
        Image.new("CMYK",(1,1)).save(out,format="JPEG"); cases.append(out.getvalue())
        out = io.BytesIO()
        Image.new("L",(2,2),0).save(out,format="PNG",save_all=True,
                                   append_images=[Image.new("L",(2,2),255)])
        cases.append(out.getvalue())
        for data in cases:
            with self.subTest(signature=data[:16]),self.assertRaises(AdmissionError):
                self.decode(data,2,2)
        with self.assertRaises(AdmissionError):
            self.decode(b"x"*8388609,1,1)

    def test_approved_source_pixel_boundary(self):
        # Actual Linux enforcement/decode, not a desktop header-only capacity claim.
        data = png(4096,512,b"\x07"*(4096*512))
        result = self.decode(data,2,1,"resize_exact")
        self.assertEqual(result.canonical,b"\x07\x07")
