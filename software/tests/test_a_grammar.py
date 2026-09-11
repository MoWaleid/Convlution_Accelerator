import dataclasses
import unittest
from fractions import Fraction

from conv_lab.dma import layout,stream_beats,transfer_length,width_policy
from conv_lab.errors import AdmissionError
from conv_lab.preprocessing import source_bounds
from conv_lab.strict import coefficients,integer,parse_json,ratio
from conv_lab.bundles import relative_path
from .fixtures import fixture_allocation


class GrammarTests(unittest.TestCase):
    def test_mem_accepted_forms_and_rejections(self):
        for n in (3,5):
            for sep in (b"\n",b"\r\n"):
                for terminal in (b"",sep):
                    raw = sep.join([b"80",b"ff"]+[b"7F"]*(n*n-2))+terminal
                    self.assertEqual(coefficients(raw,n),(-128,-1)+(127,)*(n*n-2))
            valid = b"00\n"*(n*n)
            bad_forms = [valid+b"\n",valid+b"\r\n",b"\n"+valid,valid[:-3],
                         b"\xef\xbb\xbf"+valid,valid.replace(b"\n",b"\r",1)]
            for token in (b"0x00",b" 00",b"00 ",b"0",b"000",b"-1",b"gg",b"00\t",b"# comment",b"00,00"):
                bad_forms.append(valid.replace(b"00",token,1))
            for bad in bad_forms:
                with self.subTest(n=n,bad=bad[:24]),self.assertRaises(AdmissionError):
                    coefficients(bad,n)

    def test_duplicate_json_types_and_ratios(self):
        for raw in (b'{"a":1,"a":2}',b'{"a":{"b":1,"b":2}}',b'{"x":NaN}',
                    b'\xef\xbb\xbf{}',b'[]',b'{',b'{"x":Infinity}'):
            with self.subTest(raw=raw),self.assertRaises(AdmissionError):
                parse_json(raw)
        for value in (True,False,1.0,"1",None):
            with self.subTest(value=value),self.assertRaises(AdmissionError):
                integer(value)
        for value in (dict(numerator=2,denominator=512),dict(numerator=True,denominator=256),
                      dict(numerator=1,denominator=0),dict(numerator=-1,denominator=2),
                      dict(numerator=1.0,denominator=2),dict(numerator=1,denominator=2,Q8=True)):
            with self.subTest(value=value),self.assertRaises(AdmissionError):
                ratio(value)
        self.assertEqual(ratio(dict(numerator=1,denominator=256)),Fraction(1,256))

    def test_portable_path_rejection(self):
        for path in ("../x","/tmp/x","C:/x","C:x","\\\\host\\x","a/../../x","a\\b",
                     "a/./b","a//b","a/","CON","nul.txt","name.","name "):
            with self.subTest(path=path),self.assertRaises(AdmissionError):
                relative_path(path)

    def test_all_five_layouts_and_boundary_rejection(self):
        cases = ((32,32,3,8,1156,5440,16384,21888),(32,32,3,16,1156,5440,32768,38272),
                 (32,32,5,8,1296,5568,16384,22016),(32,32,3,4,1156,5440,8192,13696),
                 (640,480,3,4,309444,313728,2457600,2771392))
        for w,h,n,k,tx,rxoff,rx,end in cases:
            with self.subTest(shape=(w,h,n,k)):
                value = layout(w,h,n,k,fixture_allocation())
                self.assertEqual((value.tx_bytes,value.rx_offset,value.rx_bytes,value.regions[-1][2]),
                                 (tx,rxoff,rx,end))
                self.assertEqual(sum(b-a for name,a,b in value.regions if name.endswith(("pre","post"))),256)
                self.assertEqual(layout(w,h,n,k,fixture_allocation(size=end)).regions[-1][2],end)
                for allocation in (fixture_allocation(size=end-1),fixture_allocation(base=0x100001),
                                   dataclasses.replace(fixture_allocation(),length_width=16),
                                   dataclasses.replace(fixture_allocation(),aperture_end=10)):
                    with self.assertRaises(AdmissionError):
                        layout(w,h,n,k,allocation)
        self.assertEqual(transfer_length(4194303,22),4194303)
        for size in (0,4194304,True,-1):
            with self.assertRaises(AdmissionError):
                transfer_length(size,22)
        self.assertEqual(width_policy(3,24),(21,25))
        self.assertEqual(width_policy(5,24),(22,25))
        self.assertEqual(tuple(stream_beats(b"\x01\x02\x03")),((0x030201,7,True),))
        with self.assertRaises(AdmissionError):
            layout(640,480,3,8,fixture_allocation())

    def test_joint_source_limits(self):
        for values in ((8388608,4096,512),(1,512,4096),(1,2048,1024)):
            source_bounds(*values)
        for values in ((8388609,1,1),(1,4097,1),(1,1,4097),(1,4096,4096),
                       (True,1,1),(1,0,1),(1,2049,1024)):
            with self.subTest(values=values),self.assertRaises(AdmissionError):
                source_bounds(*values)
