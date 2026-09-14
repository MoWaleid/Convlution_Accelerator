"""Focused M7 foundation tests; no hardware access or training."""
import dataclasses
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from unittest import mock

import m8_cli
from conv_lab.dma import layout, transfer_length, validate_layout
from conv_lab.errors import AdmissionError
from conv_lab.profiles import load_profiles, profile_layout, validate_discovery
from conv_lab.types import Allocation, Layout

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "profiles/m7_profiles.json"
# Independent approved geometry/layout anchors. These are not generated.
# C32/D32/D640 identities are the reconciled frozen IDs matching the built
# artifacts' manifests (feedback finding 4, fix PHASE 2.1); the former
# 4d37... placeholders never shipped in any bitstream.
CASES = {
    "A32": (32,32,3,8,1156,5440,16384,21888,"4d344e334b385733322d323630393131"),
    "B32": (32,32,3,16,1156,5440,32768,38272,"424e334b31365733322d323630393132"),
    "C32": (32,32,5,8,1296,5568,16384,22016,"434e354b30385733322d323630393132"),
    "D32": (32,32,3,4,1156,5440,8192,13696,"444e334b30345733322d323630393132"),
    "D640": (640,480,3,4,309444,313728,2457600,2771392,"443634304e334b30342d323630393132"),
    "B32_CFGLUT125": (32,32,3,16,1156,5440,32768,38272,
                       "45463132354b31364e33573332523031"),
    "B32_CFGLUT100": (32,32,3,16,1156,5440,32768,38272,
                       "45463130304b31364e33573332523031"),
}


class M7Profiles(unittest.TestCase):
    def setUp(self):
        self.profiles = load_profiles(CATALOG)
        self.allocation = Allocation(0x10000000, 4194304, 0, 0x20000000)

    def test_seven_release_layouts_and_frozen_ids(self):
        self.assertEqual(set(self.profiles), set(CASES))
        for name, (w,h,n,k,tx,rxoff,rx,end,identity) in CASES.items():
            with self.subTest(profile=name):
                p = self.profiles[name]
                self.assertEqual((p.W,p.H,p.N,p.K,p.build_id),(w,h,n,k,identity))
                result = profile_layout(p, self.allocation)
                self.assertEqual((result.tx_offset,result.tx_bytes,result.rx_offset,
                                  result.rx_bytes,result.regions[-1][2]),
                                 (4096,tx,rxoff,rx,end))
                self.assertEqual(result, layout(w,h,n,k,self.allocation))
                self.assertEqual(profile_layout(p,self.allocation,result),result)
                for first,second in zip(result.regions,result.regions[1:]):
                    self.assertLessEqual(first[2],second[1])
                self.assertEqual(result.rx_offset % 64,0)
                self.assertEqual(result.rx_bytes,2*w*h*k)

    def test_old_d640_fixed_offset_overlaps_and_is_rejected(self):
        p = self.profiles["D640"]
        old = Layout(4096,309444,65536,2457600,(
            ("tx_pre",4032,4096),("tx",4096,313540),("tx_post",313540,313604),
            ("rx_pre",65472,65536),("rx",65536,2523136),("rx_post",2523136,2523200)))
        self.assertLess(old.rx_offset,old.tx_offset+old.tx_bytes)
        self.assertLess(old.regions[-1][2],self.allocation.size)
        with self.assertRaisesRegex(AdmissionError,"overlap"):
            profile_layout(p,self.allocation,old)

    def test_reject_bounds_alignment_aperture_and_dma_width(self):
        p = self.profiles["D640"]
        for allocation in (
            dataclasses.replace(self.allocation,size=2771391),
            dataclasses.replace(self.allocation,base=self.allocation.base+1),
            dataclasses.replace(self.allocation,alignment=0),
            dataclasses.replace(self.allocation,alignment=3),
            dataclasses.replace(self.allocation,alignment=256),
            dataclasses.replace(self.allocation,aperture_end=self.allocation.base+100),
            dataclasses.replace(self.allocation,length_width=16),
        ):
            with self.subTest(allocation=allocation), self.assertRaises(AdmissionError):
                profile_layout(p,allocation)
        self.assertEqual(transfer_length(4194303,22),4194303)
        with self.assertRaises(AdmissionError):
            transfer_length(4194304,22)
        with self.assertRaises(AdmissionError):
            layout(1024,1024,3,4,Allocation(0,16000000,0,16000000))

    def test_reject_margins_allocation_as_rx_and_changed_guards(self):
        p = self.profiles["B32"]
        correct = profile_layout(p,self.allocation)
        for bad in (
            dataclasses.replace(correct,rx_bytes=correct.rx_bytes+64),
            dataclasses.replace(correct,rx_bytes=self.allocation.size),
            dataclasses.replace(correct,tx_offset=4097),
            dataclasses.replace(correct,rx_offset=correct.rx_offset+1),
            dataclasses.replace(correct,rx_offset=65536),
            dataclasses.replace(correct,regions=()),
        ):
            with self.subTest(layout=bad), self.assertRaises(AdmissionError):
                validate_layout(p.W,p.H,p.N,p.K,self.allocation,bad)

    def test_a32_original_already_canonical_and_numerically_preserved(self):
        old = json.loads((ROOT/"profiles/history/hardware_A32_original_20260912.json").read_bytes())
        current = json.loads((ROOT/"software/hardware.json").read_bytes())
        old_id = old["accelerator"]["build_id_hex"]
        self.assertEqual(len(old_id),32)
        self.assertEqual(int(old_id,16),int(self.profiles["A32"].build_id,16))
        self.assertEqual(old_id,self.profiles["A32"].build_id)
        self.assertEqual(old,current)  # historical layouts and artifact references unchanged

    def test_invalid_catalog_ids(self):
        original = json.loads(CATALOG.read_bytes())
        for bad in ("0"*32,"a"*30,"A"*32,original["profiles"]["A32"]["build_id"]):
            data = json.loads(json.dumps(original))
            data["profiles"]["B32"]["build_id"] = bad
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp)/"catalog.json"
                path.write_text(json.dumps(data),encoding="utf-8")
                with self.assertRaises(AdmissionError):
                    load_profiles(path)

    def test_release_bindings_are_complete_and_identity_exact(self):
        original = json.loads(CATALOG.read_bytes())
        mutations = []
        missing = json.loads(json.dumps(original))
        del missing["releases"]["B32_CFGLUT125"]
        mutations.append(missing)
        mismatched = json.loads(json.dumps(original))
        mismatched["releases"]["B32_CFGLUT125"]["build_id_hex"] = \
            original["profiles"]["B32"]["build_id"]
        mutations.append(mismatched)
        bad_hash = json.loads(json.dumps(original))
        bad_hash["releases"]["B32_CFGLUT125"]["bundle_sha256"] = "A" * 64
        mutations.append(bad_hash)
        for data in mutations:
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp)/"catalog.json"
                path.write_text(json.dumps(data),encoding="utf-8")
                with self.assertRaises(AdmissionError):
                    load_profiles(path)

    def test_m8_release_resolves_shared_parameter_bundle(self):
        catalog = json.loads(CATALOG.read_bytes())
        self.assertEqual(m8_cli.release_bundle_dir("B32", catalog), "B32")
        self.assertEqual(m8_cli.release_bundle_dir("B32_CFGLUT125", catalog),
                         "B32")
        self.assertEqual(m8_cli.release_bundle_dir("B32_CFGLUT100", catalog),
                         "B32")
        with mock.patch.object(m8_cli.m7, "BASE", ROOT / "profiles"):
            identity = m8_cli.parameter_identity("B32")
        self.assertEqual(identity["bundle_dir"], "B32")
        self.assertEqual(set(identity["weights"]),
                         {f"kernel_ch{i}.mem" for i in range(16)})

        escaped = json.loads(json.dumps(catalog))
        escaped["releases"]["B32_CFGLUT125"]["bundle_dir"] = "../B32"
        with self.assertRaises(RuntimeError):
            m8_cli.release_bundle_dir("B32_CFGLUT125", escaped)

    def test_research_high_shift_stimulus_covers_signed_branches(self):
        padded = bytes([255] * ((32 + 3 - 1) * (32 + 3 - 1)))
        for shift in range(24, 32):
            channels = m8_cli.high_shift_channels(3, 16, shift)
            self.assertEqual({entry[2] for entry in channels}, {shift})
            self.assertTrue(all(entry[3] == 0 for entry in channels))
            values = m8_cli.m7.make_expected(padded, 3, 32, 32, channels)
            if shift == 24:
                self.assertIn(1, values)
                self.assertIn(-1, values)
            else:
                self.assertEqual(set(values), {0})
        with self.assertRaises(RuntimeError):
            m8_cli.high_shift_channels(3, 16, 23)
        with self.assertRaises(RuntimeError):
            m8_cli.high_shift_channels(3, 16, 32)

    def test_wrapper_clock_metadata_is_profile_agnostic(self):
        wrapper = (ROOT / "Convlution_Accelerator.srcs/sources_1/new/"
                   "conv_axis_wrapper_bd.v").read_text()
        self.assertIn("ASSOCIATED_BUSIF S_AXI:S_AXIS:M_AXIS", wrapper)
        self.assertNotIn("FREQ_HZ", "\n".join(
            line for line in wrapper.splitlines()
            if "X_INTERFACE_PARAMETER" in line))

    def test_b32_rejects_legacy_a32_id_in_otherwise_correct_discovery(self):
        p = self.profiles["B32"]
        r = {0x4100:0x43564831,0x4104:0x10000,0x4108:0x1ff,
             0x4120:32,0x4124:32,0x4128:3,0x412c:16,
             0x4130:0x10180808,0x4134:0x1915,0x4138:1156,0x413c:32768,0x4160:22}
        identity = int(p.build_id,16)
        r.update({0x4150+4*i:(identity>>(32*i))&0xffffffff for i in range(4)})
        self.assertEqual(validate_discovery(p,r),p)
        identity = int(self.profiles["A32"].build_id,16)
        r.update({0x4150+4*i:(identity>>(32*i))&0xffffffff for i in range(4)})
        with self.assertRaises(AdmissionError):
            validate_discovery(p,r)

    def test_render_all_configs_and_current_d640_projection(self):
        spec = importlib.util.spec_from_file_location("prepare_profile",ROOT/"scripts/prepare_profile.py")
        module = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(module)
        template = (ROOT/"Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd").read_text()
        # prepare_profile.py is the legacy five-profile build generator.
        # The research release has its own isolated generator and must not be
        # projected through this path.
        for name in ("A32", "B32", "C32", "D32", "D640"):
            p = self.profiles[name]
            rendered = module.render_config(template,p)
            self.assertIn(f'CFG_PROFILE : string := "{name}"',rendered)
            self.assertIn(f'x"{p.build_id}"',rendered)
            for key,value in (("CFG_K",p.K),("CFG_N",p.N),
                              ("CFG_UNPADDED_WIDTH",p.W),("CFG_UNPADDED_HEIGHT",p.H)):
                self.assertRegex(rendered,rf"{key}\s*: integer := {value};")
        # Rendering an already-rendered isolated snapshot must be idempotent.
        d640 = module.render_config(template,self.profiles["D640"])
        self.assertEqual(d640,module.render_config(d640,self.profiles["D640"]))
