import dataclasses
import tempfile
import unittest
from pathlib import Path

from conv_lab.admission import IdentityCatalog,RecordingMockBackend
from conv_lab.bundles import read_bundle
from conv_lab.errors import AdmissionError
from conv_lab.strict import sha256
from .fixtures import FixtureDecoder,change_json,refresh_model,selection_session,write_selection


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="m2-admission-")
        self.addCleanup(self.tmp.cleanup)
        self.roots,self.pixels = write_selection(self.tmp.name)
        self.session = selection_session(self.roots,self.pixels)
        self.backend = RecordingMockBackend()

    def admit(self):
        return self.session.admit(*self.roots,"sample")

    def rejected(self):
        with self.assertRaises(AdmissionError):
            self.admit()
        self.assertEqual(self.backend.events,())
        self.assertEqual(self.session.catalog.entries,())
        with self.assertRaises(AdmissionError):
            self.session.submit(None,self.backend)
        self.assertEqual(self.backend.events,())

    def cfg_change(self,edit):
        change_json(self.roots[1]/"channel_config.json",edit)
        refresh_model(self.roots[1])

    def test_success_deep_freeze_and_post_validation_file_mutation(self):
        ctx = self.admit()
        self.assertIs(type(ctx.channels),tuple)
        self.assertIs(type(ctx.channels[0].weights),tuple)
        self.assertIs(type(ctx.hardware_bundle.files),tuple)
        for value,attr,new in ((ctx,"canonical",b"bad"),(ctx.channels[0],"bias",999)):
            with self.assertRaises(dataclasses.FrozenInstanceError):
                setattr(value,attr,new)
        (self.roots[2]/"image.png").write_bytes(b"changed after admission")
        (self.roots[1]/"weights/kernel_ch0.mem").write_bytes(b"bad")
        self.assertEqual(ctx.canonical,self.pixels)
        self.assertEqual(ctx.source_sha256,sha256(ctx.source))
        self.assertNotEqual(ctx.source_sha256,ctx.canonical_sha256)
        self.assertNotEqual(ctx.canonical_sha256,ctx.padded_tx_sha256)
        self.session.submit(ctx,self.backend)
        self.assertEqual({e[0] for e in self.backend.events},
                         {"programming","parameters","register","dma_rx","dma_tx"})

    def test_forged_copy_stale_and_production_rejected(self):
        ctx = self.admit()
        with self.assertRaises(AdmissionError):
            self.session.submit(dataclasses.replace(ctx),self.backend)
        with self.assertRaises(AdmissionError):
            self.session.admit(*self.roots,"sample",purpose="production")
        self.session.invalidate()
        with self.assertRaises(AdmissionError):
            self.session.submit(ctx,self.backend)
        self.assertEqual(self.backend.events,())

    def test_missing_root_and_model_geometry_rejection(self):
        with self.assertRaises(AdmissionError):
            self.session.admit(Path(self.tmp.name)/"absent",self.roots[1],self.roots[2],"sample")
        change_json(self.roots[1]/"model.json",lambda m:m["compatibility"].update(geometry=[dict(W=32,H=32)]))
        self.rejected()

    def test_last_weight_corruption(self):
        (self.roots[1]/"weights/kernel_ch3.mem").write_bytes(b"00\n")
        self.rejected()

    def test_undeclared_and_missing_optional_payload(self):
        extra = self.roots[0]/"extra.txt"
        extra.write_bytes(b"extra"); self.rejected(); extra.unlink()
        change_json(self.roots[1]/"model.json",
                    lambda m:m["optional_assets"].append(dict(path="weights.pth",sha256="a"*64)))
        self.rejected()

    def test_wrong_hardware_fields_and_no_extension_override(self):
        path = self.roots[0]/"hardware.json"; original = path.read_bytes()
        for key,value in (("schema_version",True),("schema_version",2),("W",True),
                          ("capabilities",510),("build_id","0"*32),("N",5),("K",16)):
            with self.subTest(key=key,value=value):
                path.write_bytes(original)
                change_json(path,lambda m:m.update({key:value}))
                self.rejected()
        path.write_bytes(original)
        change_json(path,lambda m:m["widths"].update(bias=32))
        self.rejected()
        path.write_bytes(original)
        change_json(path,lambda m:m["extensions"].update(synthetic_fixture=False))
        self.rejected()

    def test_mock_parameter_word_representation(self):
        (self.roots[1]/"weights/kernel_ch0.mem").write_bytes(b"80\nFF\n00\n7F\n00\n00\n00\n00\nA5\n")
        self.cfg_change(lambda c:c["channels"][0].update(shift=8,relu_en=True))
        change_json(self.roots[1]/"model.json",lambda m:m["compatibility"]["numerical"].update(relu_required=True))
        ctx = self.admit()
        self.session.submit(ctx,self.backend)
        words = dict(next(e[1] for e in self.backend.events if e[0] == "parameters"))
        self.assertEqual(words[0],0x7f00ff80)
        self.assertEqual(words[8],0xa5)
        self.assertEqual(words[0xf8],0xfffffffe)
        self.assertEqual(words[0xfc],0x108)

    def test_shuffled_channels(self):
        self.cfg_change(lambda c:c["channels"].reverse())
        ctx = self.admit()
        self.assertEqual(tuple(c.channel for c in ctx.channels),(0,1,2,3))
        self.assertEqual(tuple(c.bias for c in ctx.channels),(-2,-1,0,1))

    def test_invalid_configuration_and_signed24_rejection(self):
        path = self.roots[1]/"channel_config.json"; original = path.read_bytes()
        edits = [lambda c:c.update(format_version=2),lambda c:c.update(unknown=1),
                 lambda c:c.update(input_scale=dict(numerator=2,denominator=512)),
                 lambda c:c["channels"].pop(),lambda c:c["channels"].append(c["channels"][0])]
        for key,value in (("channel",True),("channel",4),("weights_file","weights/kernel_ch1.mem"),
                          ("bias_quantized",8388608),("bias_quantized",-8388609),("bias_quantized",1.0),
                          ("shift",32),("shift",-1),("shift",True),("relu_en",1),
                          ("weight_scale",dict(numerator=1,denominator=False))):
            edits.append(lambda c,key=key,value=value:c["channels"][0].update({key:value}))
        for index,edit in enumerate(edits):
            with self.subTest(edit=index):
                path.write_bytes(original); self.cfg_change(edit); self.rejected()

    def test_configurable_bias_width_declared_and_validated(self):
        change_json(self.roots[0]/"hardware.json",lambda m:m["widths"].update(bias=32,accumulator=33))
        self.cfg_change(lambda c:c["channels"][0].update(bias_quantized=-2147483648))
        ctx = self.admit()
        self.assertEqual(ctx.hardware.bias_width,32)
        self.assertEqual(ctx.channels[0].bias,-2147483648)

    def test_bias_extrema_duplicate_json(self):
        self.cfg_change(lambda c:(c["channels"][0].update(bias_quantized=-8388608),
                                  c["channels"][1].update(bias_quantized=8388607)))
        ctx = self.admit()
        self.assertEqual((ctx.channels[0].bias,ctx.channels[1].bias),(-8388608,8388607))
        self.session = selection_session(self.roots,self.pixels)
        path = self.roots[1]/"channel_config.json"
        path.write_bytes(path.read_bytes().replace(b'"format_version":3',b'"format_version":3,"format_version":3'))
        refresh_model(self.roots[1]); self.rejected()

    def test_late_decoder_failure_invalid_result_generation_change(self):
        self.session.decoder = FixtureDecoder(self.pixels,fail=True); self.rejected()
        self.session.decoder = FixtureDecoder(self.pixels+b"x"); self.rejected()
        base,session = FixtureDecoder(self.pixels),self.session
        class RacingDecoder:
            def decode(self,*args):
                result = base.decode(*args); session.invalidate(); return result
        self.session.decoder = RacingDecoder(); self.rejected()

    def test_collision_across_origins(self):
        catalog = IdentityCatalog()
        catalog.register((read_bundle(self.roots[1],"model"),))
        self.cfg_change(lambda c:c["channels"][0].update(bias_quantized=9))
        self.session = selection_session(self.roots,self.pixels,catalog=catalog)
        before = catalog.entries
        with self.assertRaises(AdmissionError):
            self.admit()
        self.assertEqual(catalog.entries,before)
        self.assertEqual(self.backend.events,())

    def test_traversal_and_symlink_escape(self):
        path = self.roots[0]/"hardware.json"; original = path.read_bytes()
        change_json(path,lambda m:m["artifacts"][0].update(path="../outside.bit"))
        self.rejected(); path.write_bytes(original)
        outside = Path(self.tmp.name)/"outside.bit"; outside.write_bytes(b"outside")
        target = self.roots[0]/"SYNTHETIC-NOT-PROGRAMMABLE.bit"; target.unlink()
        try:
            target.symlink_to(outside)
        except OSError as exc:
            self.skipTest(f"host symlinks unavailable: {exc}")
        self.rejected()
