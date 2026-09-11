"""Whole-selection admission and a capability boundary to a recording mock."""
import threading
import weakref
from dataclasses import dataclass

from . import __version__
from .bundles import fingerprint, read_bundle
from .dma import layout,pad_pixels
from .preprocessing import LinuxDecoder,validate_decoded
from .schemas import bundle_identity,dataset,hardware,model
from .strict import integer,require,sha256
from .types import RunContext


class IdentityCatalog:
    """In-process exclusive-owner catalog; register all embedded/imported roots."""
    def __init__(self):
        self._entries = {}
        self._lock = threading.RLock()

    def check(self,bundles):
        with self._lock:
            pending = dict(self._entries)
            for bundle in bundles:
                key,value = bundle_identity(bundle),fingerprint(bundle)
                if key in pending:
                    require(pending[key][0] == value,"immutable identity collision")
                else:
                    pending[key] = (value,bundle.origin)
            return pending

    def register(self,bundles):
        with self._lock:
            self._entries = self.check(bundles)

    @property
    def entries(self):
        with self._lock:
            return tuple(sorted((k,v) for k,v in self._entries.items()))


@dataclass(frozen=True,slots=True)
class MockPlatform:
    platform_id: str
    ps_digest: str
    dt_contract_id: str
    # Explicitly supplied fixture envelope; never a qualified geometry list.
    geometries: tuple[tuple[int,int,int,int], ...]

    def matches(self,hw):
        require(type(self.geometries) is tuple and
                all(type(x) is tuple and len(x) == 4 and all(type(v) is int for v in x) for x in self.geometries),
                "immutable mock geometry description")
        require(hw.synthetic and self.platform_id.startswith("fixture-") and
                hw.platform_id == self.platform_id and hw.ps_digest == self.ps_digest and
                hw.dt_contract_id == self.dt_contract_id,"synthetic mock platform mismatch")
        require((hw.W,hw.H,hw.N,hw.K) in self.geometries,"unadmitted mock geometry")


class RecordingMockBackend:
    """Records requests only. No hardware discovery, mapping, driver or programming code."""
    def __init__(self):
        self._events = []

    @property
    def events(self):
        return tuple(self._events)

    def _append_batch(self,events):
        self._events.extend(events)


def _parameter_words(channels):
    words = []
    for channel in channels:
        for start in range(0,len(channel.weights),4):
            value = sum((v & 255) << (8*i) for i,v in enumerate(channel.weights[start:start+4]))
            words.append((channel.channel*0x100+start,value))
        words.append((channel.channel*0x100+0xf8,channel.bias & 0xffffffff))
        words.append((channel.channel*0x100+0xfc,channel.shift | (int(channel.relu)<<8)))
    return tuple(words)


class AdmissionSession:
    def __init__(self,platform,allocation,*,decoder=None,catalog=None):
        require(type(platform) is MockPlatform,"only mock platform supported")
        self.platform,self.allocation = platform,allocation
        self.decoder = LinuxDecoder() if decoder is None else decoder
        self.catalog = IdentityCatalog() if catalog is None else catalog
        self._generation = 0
        self._accepted = weakref.WeakValueDictionary()
        self._lock = threading.RLock()

    def invalidate(self):
        with self._lock:
            self._generation += 1
            self._accepted.clear()

    def admit(self,hardware_root,model_root,dataset_root,image_id,*,purpose="mock"):
        require(purpose == "mock","production admission is not implemented; fixtures are not deployable")
        with self._lock:
            generation = self._generation
            allocation,platform = self.allocation,self.platform
        hb,mb,db = (read_bundle(root,kind) for root,kind in
                    ((hardware_root,"hardware"),(model_root,"model"),(dataset_root,"dataset")))
        hw = hardware(hb)
        platform.matches(hw)
        channels,input_scale,policies = model(mb,hw)
        source,policy = dataset(db,image_id,policies)
        admitted_layout = layout(hw.W,hw.H,hw.N,hw.K,allocation)
        self.catalog.check((hb,mb,db))
        result = self.decoder.decode(source,hw.W,hw.H,policy)
        validate_decoded(result,source,hw.W,hw.H,policy)
        padded = pad_pixels(result.canonical,hw.W,hw.H,hw.N)
        require(len(padded) == admitted_layout.tx_bytes,"TX packing length")
        ctx = RunContext(hw,channels,input_scale,hb,mb,db,image_id,source,sha256(source),
                         result.canonical,sha256(result.canonical),padded,sha256(padded),
                         result.record_json,allocation,admitted_layout,generation,__version__)
        with self._lock:
            require(generation == self._generation,"generation changed during admission")
            self.catalog.register((hb,mb,db))
            self._accepted[id(ctx)] = ctx
        return ctx

    def submit(self,ctx,backend):
        with self._lock:
            require(type(ctx) is RunContext and self._accepted.get(id(ctx)) is ctx and
                    ctx.generation == self._generation,"invalid/partial/stale context")
            require(type(backend) is RecordingMockBackend and ctx.mock_only and ctx.hardware.synthetic,
                    "only a recording mock backend is allowed")
            # Assemble everything before appending any request. This is intent recording,
            # not an implemented or qualified programming/activation/ownership lifecycle.
            events = (("programming",ctx.hardware.build_id,fingerprint(ctx.hardware_bundle)),
                      ("parameters",_parameter_words(ctx.channels)),
                      ("dma_rx",ctx.layout.rx_offset,ctx.layout.rx_bytes),
                      ("register",0x4110,1),
                      ("dma_tx",ctx.layout.tx_offset,ctx.layout.tx_bytes,ctx.padded_tx,ctx.canonical_sha256))
            backend._append_batch(events)


def reference_only(ctx):
    from .reference import evaluate
    return evaluate(ctx)  # No backend argument or hardware methods on this path.
