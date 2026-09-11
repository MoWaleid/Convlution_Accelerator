import dataclasses
import random
import struct
import unittest
from fractions import Fraction

from conv_lab.errors import AdmissionError
from conv_lab.reference import (compare,evaluate,interpreted_values,round_discarded_bit,
                                round_scaled,scales)
from conv_lab.types import Channel
from .fixtures import raw_context
from .oracle import oracle

DIFFERENTIAL_COUNT = 1000
SEED_BASE = 0x5EED000


def channel(n,weights=None,bias=0,shift=0,relu=False,index=0,scale=Fraction(1,128)):
    return Channel(index,(0,)*(n*n) if weights is None else tuple(weights),bias,shift,relu,scale)


class ExactCases(unittest.TestCase):
    def result(self,w,h,n,channels,pixels):
        ctx = raw_context(w,h,n,channels,pixels)
        result = evaluate(ctx)
        self.assertEqual(result.raw,oracle(w,h,n,channels,pixels))
        return ctx,result

    def test_hand_solvable_zero_and_center_minus128(self):
        for n in (3,5):
            _,result = self.result(2,1,n,(channel(n),),bytes((7,11)))
            self.assertEqual(result.raw,b"\0"*4)
        weights = [0]*9; weights[4] = -128
        _,result = self.result(1,1,3,(channel(3,weights),),b"\xff")
        self.assertEqual(result.raw,(-32640).to_bytes(2,"little",signed=True))

    def test_hand_solvable_n5_and_rectangular_orientation(self):
        _,result = self.result(1,1,5,(channel(5,[1]*25),),bytes((7,)))
        self.assertEqual(result.raw,b"\x07\x00")
        weights = [0]*9; weights[5] = 1
        _,result = self.result(2,1,3,(channel(3,weights),),bytes((7,11)))
        self.assertEqual(result.raw,b"\x0b\x00\x00\x00")
        for n in (3,5):
            self.result(1,4,n,(channel(n,list(range(n*n))),),bytes((1,2,3,4)))
            self.result(5,2,n,(channel(n,[-1]*(n*n)),),bytes(range(10)))

    def test_hand_solvable_rounding_and_saturation_relu(self):
        values = (1,-1,3,-3)
        channels = tuple(channel(3,bias=b,shift=1,index=i) for i,b in enumerate(values))
        _,result = self.result(1,1,3,channels,b"\0")
        self.assertEqual(tuple(v[0] for v in struct.iter_unpack("<h",result.raw)),(1,0,2,-1))
        for relu in (False,True):
            channels = tuple(channel(3,bias=b,relu=relu,index=i) for i,b in enumerate((32767,32768,-32768,-32769)))
            _,result = self.result(1,1,3,channels,b"\0")
            expected = (32767,32767,0,0) if relu else (32767,32767,-32768,-32768)
            self.assertEqual(tuple(v[0] for v in struct.iter_unpack("<h",result.raw)),expected)

    def test_all_shifts_ties_neighbors_and_optimized_equivalence(self):
        for shift in range(32):
            values = {-8388608,8388607,-1,0,1}
            if shift:
                half = 2**(shift-1)
                for q in (-3,-2,-1,0,1,2):
                    values.update(q*2**shift+half+delta for delta in (-1,0,1))
            for acc in sorted(values):
                with self.subTest(shift=shift,acc=acc):
                    divisor = 2**shift
                    quotient,remainder = divmod(acc,divisor)
                    expected = acc if not shift else quotient+int(2*remainder >= divisor)
                    self.assertEqual(round_scaled(acc,shift),expected)
                    self.assertEqual(round_discarded_bit(acc,shift),expected)
                    if -8388608 <= acc <= 8388607:
                        self.result(1,1,3,(channel(3,bias=acc,shift=shift),),b"\0")

    def test_extrema_bias_width_bounds_and_raw_rejection(self):
        for n in (3,5):
            positive_bound = 255*127*n*n
            negative_bound = -255*128*n*n
            sw = 21 if n == 3 else 22
            self.assertTrue(-(1 << (sw-1)) <= negative_bound <= positive_bound < (1 << (sw-1)))
            for pixel in (0,255):
                for coefficient in (-128,127):
                    for bias in (-8388608,8388607):
                        self.result(3,2,n,(channel(n,[coefficient]*(n*n),bias),),bytes([pixel])*6)
            for bias in (-8388609,8388608):
                with self.assertRaises(AdmissionError):
                    evaluate(raw_context(1,1,n,(channel(n,bias=bias),),b"\0"))
        for bad in (True,1.0,"1"):
            with self.assertRaises(AdmissionError):
                round_scaled(bad,0)

    def test_channel_fast_little_endian_and_exact_units(self):
        channels = tuple(channel(3,bias=b,index=i,scale=Fraction(1,128)) for i,b in enumerate((1,-1,32767,-32768)))
        ctx,result = self.result(2,1,3,channels,b"\x80\x00")
        self.assertEqual(result.raw,bytes.fromhex("0100ffffff7f0080")*2)
        self.assertEqual(scales(ctx)[0],(0,Fraction(1,32768),Fraction(1,32768)))
        self.assertEqual(tuple(interpreted_values(ctx,result))[:4],
                         (Fraction(1,32768),Fraction(-1,32768),Fraction(32767,32768),Fraction(-1)))
        shifted = raw_context(1,1,3,(channel(3,bias=16384,shift=8),),b"\x80")
        self.assertEqual(tuple(interpreted_values(shifted,evaluate(shifted))),(Fraction(1,2),))
        self.assertEqual(shifted.canonical,b"\x80")

    def test_mismatch_diagnostics_include_coordinates_and_lengths(self):
        expected = b"\x01\0\x02\0\x03\0\x04\0"
        value = compare(expected,b"\x01\0\x09\0\x03\0\x04\0",2,2)
        self.assertFalse(value.passed)
        self.assertEqual(value.first_mismatches,((0,0,1,2,9),))
        self.assertEqual(value.checked_values,4)
        self.assertEqual(compare(expected,expected,2,2).mismatch_values,0)
        for actual in (expected[:-1],expected[:-2],expected+b"\0",expected+b"\0\0"):
            self.assertFalse(compare(expected,actual,2,2).passed)


class SeededDifferential(unittest.TestCase):
    pass


def _case(seed):
    def test(self):
        rng = random.Random(seed)
        n,w,h,k = rng.choice((3,5)),rng.randint(1,5),rng.randint(1,4),rng.choice((1,2,4))
        pixels = bytes(rng.choice((0,255,rng.randrange(256))) for _ in range(w*h))
        channels = tuple(channel(n,[rng.choice((-128,127,rng.randint(-128,127))) for _ in range(n*n)],
                                 rng.choice((-8388608,8388607,rng.randint(-8388608,8388607))),
                                 rng.randrange(32),bool(rng.getrandbits(1)),i) for i in range(k))
        ctx = raw_context(w,h,n,channels,pixels)
        self.assertEqual(evaluate(ctx).raw,oracle(w,h,n,channels,pixels),f"seed={seed}")
    test.differential_seed = seed
    return test


# These test methods/fixtures are generated only when the user runs this module.
for _index in range(DIFFERENTIAL_COUNT):
    setattr(SeededDifferential,f"test_seed_{SEED_BASE+_index:08x}",_case(SEED_BASE+_index))
