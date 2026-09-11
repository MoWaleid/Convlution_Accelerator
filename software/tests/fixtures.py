"""Synthetic fixture constructors; executed only by the user's tests.

These assets are not trained/custom starter releases. No legacy assets are read.
"""
import json
import struct
import zlib
from fractions import Fraction
from pathlib import Path

from conv_lab.admission import AdmissionSession,MockPlatform
from conv_lab.dma import layout,pad_pixels,width_policy
from conv_lab.preprocessing import RESOURCE_STRATEGY
from conv_lab.strict import sha256
from conv_lab.types import Allocation,Blob,Bundle,Channel,Decoded,Hardware,RunContext

FIXTURE_DIGEST = "a"*64


def encoded_json(value):
    return json.dumps(value,separators=(",",":"),allow_nan=False).encode()


def png(w,h,pixels,*,depth=8,color=0,extras=()):
    def chunk(name,data):
        return struct.pack(">I",len(data))+name+data+struct.pack(">I",zlib.crc32(name+data)&0xffffffff)
    channels = 3 if color == 2 else 1
    raw = b"".join(b"\0"+pixels[y*w*channels:(y+1)*w*channels] for y in range(h))
    return (b"\x89PNG\r\n\x1a\n"+chunk(b"IHDR",struct.pack(">IIBBBBB",w,h,depth,color,0,0,0))+
            b"".join(chunk(k,v) for k,v in extras)+chunk(b"IDAT",zlib.compress(raw))+chunk(b"IEND",b""))


def ref(path,data):
    return dict(path=path,sha256=sha256(data))


def fixture_allocation(base=0x100000,size=4194304):
    # Arbitrary synthetic address, NOT a historical/current buffer address.
    return Allocation(base,size,0,0x20000000)


def platform(w,h,n,k):
    return MockPlatform("fixture-zedboard",FIXTURE_DIGEST,"fixture-dt",((w,h,n,k),))


class FixtureDecoder:
    """Explicit test double. Provides no Linux isolation or decoder evidence."""
    def __init__(self,pixels,*,fail=False):
        self.pixels,self.calls,self.fail = pixels,0,fail

    def decode(self,source,w,h,policy):
        from conv_lab.errors import AdmissionError
        self.calls += 1
        if self.fail:
            raise AdmissionError("synthetic late decoder failure")
        record = dict(source_sha256=sha256(source),source_format="PNG",source_mode="L",
                      source_width=w,source_height=h,exif_orientation=None,oriented_width=w,
                      oriented_height=h,target_width=w,target_height=h,geometry_policy=policy,
                      resize_filter="NONE" if policy == "exact" else "LANCZOS",aspect_ratio_changed=False,
                      canonical_sha256=sha256(self.pixels),pillow_version="SYNTHETIC-NO-DECODER",
                      decoder_versions=[dict(name="fixture",version="NOT-RUN")],preprocessing_version="1",
                      decode_policy=dict(max_source_bytes=8388608,max_width=4096,max_height=4096,
                                         max_pixels=2097152,resource_strategy=RESOURCE_STRATEGY),
                      extensions=dict(evidence="SYNTHETIC-TEST-DOUBLE-NOT-LINUX-ENFORCEMENT"))
        return Decoded(self.pixels,encoded_json(record))


def write_selection(root,*,w=3,h=2,n=3,k=4,pixels=None,channels=None,policy="exact",image=None):
    root = Path(root)
    pixels = bytes(i % 256 for i in range(w*h)) if pixels is None else pixels
    image = png(w,h,pixels) if image is None else image
    channels = tuple(Channel(i,(0,)*(n*n),i-2,0,False,Fraction(1,128)) for i in range(k)) if channels is None else channels
    roots = tuple(root/name for name in ("hardware","model","dataset"))
    for directory in roots:
        directory.mkdir(parents=True)
    hr,mr,dr = roots
    sw,aw = width_policy(n,24)
    artifacts = []
    for kind,suffix in (("bitstream","bit"),("fpga_manager_image","bin"),("xsa","xsa")):
        name = "SYNTHETIC-NOT-PROGRAMMABLE."+suffix
        data = ("fixture only: "+kind).encode()
        (hr/name).write_bytes(data)
        artifacts.append(dict(kind=kind,**ref(name,data)))
    hardware = dict(schema_version=1,build_id="123456789abcdef0123456789abcdef0",
        platform=dict(id="fixture-zedboard",board="zedboard",fpga_part="fixture-part-not-a-release",
                      dt_contract_id="fixture-dt",ps_config_sha256=FIXTURE_DIGEST,clock_hz=100000000),
        abi=dict(magic="43564831",major=1,minor=0),W=w,H=h,N=n,K=k,
        widths=dict(pixel=8,weight=8,bias=24,sum=sw,accumulator=aw,output=16,m_axi_mm2s=64,m_axi_s2mm=64,
                    m_axis_mm2s=64,s_axis_s2mm=64,axi_lite=32,dma_length=22),capabilities=511,artifacts=artifacts,
        provenance=dict(source_snapshot_id="fixture-source",source_snapshot_sha256=FIXTURE_DIGEST,
                        tools=[dict(name="synthetic-fixture",version="1")],external_prerequisites=[]),
        extensions=dict(synthetic_fixture=True))
    (hr/"hardware.json").write_bytes(encoded_json(hardware))
    (mr/"weights").mkdir()
    weights,configs = [],[]
    for c in channels:
        name = f"weights/kernel_ch{c.channel}.mem"
        data = b"".join(f"{value & 255:02X}\n".encode() for value in c.weights)
        (mr/name).write_bytes(data); weights.append(ref(name,data))
        configs.append(dict(channel=c.channel,weights_file=name,bias_quantized=c.bias,shift=c.shift,
                            relu_en=c.relu,weight_scale=dict(numerator=c.weight_scale.numerator,
                                                          denominator=c.weight_scale.denominator)))
    cfg = encoded_json(dict(format_version=3,input_scale=dict(numerator=1,denominator=256),channels=configs))
    (mr/"channel_config.json").write_bytes(cfg)
    model = dict(schema_version=1,model_id="fixture-model",release_version="1",kind="custom",
                 compatibility=dict(N=n,K=k,geometry=[dict(W=w,H=h)],geometry_policies=["exact","resize_exact"],
                   numerical=dict(pixel_width=8,weight_width=8,output_width=16,min_bias_width=24,
                                  relu_required=any(c.relu for c in channels)),
                   abi=dict(magic="43564831",versions=[dict(major=1,minor=0)])),
                 channel_config=ref("channel_config.json",cfg),weights=weights,optional_assets=[])
    (mr/"model.json").write_bytes(encoded_json(model))
    (dr/"image.png").write_bytes(image)
    dataset = dict(schema_version=1,dataset_id="fixture-images",release_version="1",images=[dict(
        image_id="sample",source=ref("image.png",image),preprocessing=dict(geometry_policy=policy,
        resize_filter="NONE" if policy == "exact" else "LANCZOS"))])
    (dr/"dataset.json").write_bytes(encoded_json(dataset))
    return roots,pixels


def selection_session(roots,pixels,w=3,h=2,n=3,k=4,decoder=None,catalog=None):
    return AdmissionSession(platform(w,h,n,k),fixture_allocation(),
                            decoder=FixtureDecoder(pixels) if decoder is None else decoder,catalog=catalog)


def raw_context(w,h,n,channels,pixels,*,bias_width=24):
    """Immutable synthetic reference fixture; not issued by AdmissionSession."""
    k = len(channels); sw,aw = width_policy(n,bias_width)
    hw = Hardware(w,h,n,k,bias_width,sw,aw,"1"*32,"fixture-zedboard",FIXTURE_DIGEST,"fixture-dt",100000000,True)
    dummy = Bundle("fixture","synthetic",(Blob("fixture",b"fixture",sha256(b"fixture")),))
    padded = pad_pixels(pixels,w,h,n)
    return RunContext(hw,tuple(channels),Fraction(1,256),dummy,dummy,dummy,"fixture",b"fixture",
                      sha256(b"fixture"),bytes(pixels),sha256(pixels),padded,sha256(padded),b"{}",
                      fixture_allocation(),layout(w,h,n,k,fixture_allocation()),0,"synthetic-fixture")


def change_json(path,edit):
    value = json.loads(Path(path).read_bytes())
    edit(value)
    Path(path).write_bytes(encoded_json(value))


def refresh_model(root):
    root = Path(root)
    def edit(m):
        for item in [m["channel_config"]]+m["weights"]+m["optional_assets"]:
            item["sha256"] = sha256((root/item["path"]).read_bytes())
    change_json(root/"model.json",edit)
