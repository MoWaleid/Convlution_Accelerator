"""Independent integer correctness reference; no timeout or hardware access."""
import struct
from dataclasses import dataclass
from fractions import Fraction

from . import __version__
from .strict import integer,require,sha256
from .types import Channel,RunContext,OfflineContext,NumericalTarget


def round_scaled(acc,shift):
    require(type(acc) is int,"arbitrary-precision integer accumulator required")
    integer(shift,0,31)
    return acc if shift == 0 else (acc+(1 << (shift-1))) >> shift


def round_discarded_bit(acc,shift):
    """Equivalence candidate; Python >> supplies sign extension beyond any width."""
    require(type(acc) is int,"integer accumulator required")
    integer(shift,0,31)
    return acc if shift == 0 else (acc >> shift)+((acc >> (shift-1)) & 1)


def numerical_target(ctx):
    require(type(ctx) in (RunContext, OfflineContext), "immutable numerical context required")
    if type(ctx) is OfflineContext:
        require(type(ctx.target) is NumericalTarget, "offline target required")
        return ctx.target
    return ctx.hardware


def _validate_context(ctx):
    hw = numerical_target(ctx)
    for value in (hw.W,hw.H,hw.K):
        integer(value,1)
    integer(hw.N,3,5); integer(hw.bias_width,1,32)
    require(hw.W*hw.H*hw.K*2 <= 4194303,"reference output envelope")
    require(type(ctx.canonical) is bytes and len(ctx.canonical) == hw.W*hw.H and
            sha256(ctx.canonical) == ctx.canonical_sha256,"canonical identity")
    require(hw.N in (3,5) and type(ctx.channels) is tuple and len(ctx.channels) == hw.K and
            tuple(c.channel for c in ctx.channels) == tuple(range(hw.K)),"channel/kernel contract")
    require(type(ctx.input_scale) is Fraction and ctx.input_scale > 0,"input scale")
    for c in ctx.channels:
        require(type(c) is Channel and type(c.weights) is tuple and len(c.weights) == hw.N*hw.N,"channel structure")
        integer(c.channel,0,hw.K-1)
        for weight in c.weights:
            integer(weight,-128,127)
        integer(c.bias,-(1 << (hw.bias_width-1)),(1 << (hw.bias_width-1))-1)
        integer(c.shift,0,31)
        require(type(c.relu) is bool and type(c.weight_scale) is Fraction and c.weight_scale > 0,"channel metadata")


def raw_values(ctx):
    _validate_context(ctx)
    hw = numerical_target(ctx)
    radius = (hw.N-1)//2
    for y in range(hw.H):
        for x in range(hw.W):
            for channel in ctx.channels:
                acc = channel.bias
                for ky in range(hw.N):
                    iy = y+ky-radius
                    if not 0 <= iy < hw.H:
                        continue
                    for kx in range(hw.N):
                        ix = x+kx-radius
                        if 0 <= ix < hw.W:
                            acc += ctx.canonical[iy*hw.W+ix]*channel.weights[ky*hw.N+kx]
                scaled = round_scaled(acc,channel.shift)
                value = min(32767,max(-32768,scaled))
                yield max(0,value) if channel.relu else value


@dataclass(frozen=True,slots=True)
class ReferenceResult:
    raw: bytes
    sha256: str
    canonical_sha256: str
    values: int
    reference_version: str


def evaluate(ctx):
    # Only the serialized output is retained; no K full-frame integer-sum arrays.
    _validate_context(ctx)
    output = bytearray(numerical_target(ctx).W*numerical_target(ctx).H*numerical_target(ctx).K*2)
    count = 0
    for count,value in enumerate(raw_values(ctx),1):
        struct.pack_into("<h",output,(count-1)*2,value)
    raw = bytes(output)
    return ReferenceResult(raw,sha256(raw),ctx.canonical_sha256,count,__version__)


def scales(ctx):
    _validate_context(ctx)
    return tuple((c.channel,ctx.input_scale*c.weight_scale,
                  ctx.input_scale*c.weight_scale*(1 << c.shift)) for c in ctx.channels)


def interpreted_values(ctx,result):
    require(result.canonical_sha256 == ctx.canonical_sha256,"different canonical input")
    factors = tuple(s[2] for s in scales(ctx))
    for i,(value,) in enumerate(struct.iter_unpack("<h",result.raw)):
        yield value*factors[i % numerical_target(ctx).K]


@dataclass(frozen=True,slots=True)
class Comparison:
    passed: bool
    expected_bytes: int
    received_bytes: int
    checked_values: int
    mismatch_values: int
    # y,x,channel,expected,actual; missing values are None.
    first_mismatches: tuple[tuple[int,int,int,int | None,int | None], ...]


def compare(expected,actual,w,k,diagnostic_limit=20):
    require(type(expected) is bytes and type(actual) is bytes and len(expected)%2 == 0,"signed16 bytes")
    integer(w,1); integer(k,1); integer(diagnostic_limit,0)
    en,an = len(expected)//2,len(actual)//2
    mismatches,details = 0,[]
    for i in range(max(en,an)):
        ev = struct.unpack_from("<h",expected,i*2)[0] if i < en else None
        av = struct.unpack_from("<h",actual,i*2)[0] if i < an else None
        if ev != av:
            mismatches += 1
            if len(details) < diagnostic_limit:
                details.append((i//k//w,(i//k)%w,i%k,ev,av))
    return Comparison(len(expected) == len(actual) and mismatches == 0,len(expected),len(actual),
                      min(en,an),mismatches,tuple(details))
