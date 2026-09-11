"""Run state contains only bytes, tuples and frozen scalar value objects."""
from dataclasses import dataclass
from fractions import Fraction


@dataclass(frozen=True, slots=True)
class Blob:
    path: str
    data: bytes
    sha256: str


@dataclass(frozen=True, slots=True)
class Bundle:
    kind: str
    origin: str
    files: tuple[Blob, ...]

    def blob(self, path):
        return next(b for b in self.files if b.path == path)


@dataclass(frozen=True, slots=True)
class Hardware:
    W: int
    H: int
    N: int
    K: int
    bias_width: int
    sum_width: int
    acc_width: int
    build_id: str
    platform_id: str
    ps_digest: str
    dt_contract_id: str
    clock_hz: int
    synthetic: bool


@dataclass(frozen=True, slots=True)
class Channel:
    channel: int
    weights: tuple[int, ...]
    bias: int
    shift: int
    relu: bool
    weight_scale: Fraction


@dataclass(frozen=True, slots=True)
class Allocation:
    """Supplied MOCK description; never discovers or opens a physical device."""
    base: int
    size: int
    aperture_start: int
    aperture_end: int
    alignment: int = 64
    length_width: int = 22


@dataclass(frozen=True, slots=True)
class Layout:
    tx_offset: int
    tx_bytes: int
    rx_offset: int
    rx_bytes: int
    regions: tuple[tuple[str, int, int], ...]


@dataclass(frozen=True, slots=True)
class Decoded:
    canonical: bytes
    record_json: bytes


@dataclass(frozen=True, slots=True, weakref_slot=True)
class RunContext:
    hardware: Hardware
    channels: tuple[Channel, ...]
    input_scale: Fraction
    hardware_bundle: Bundle
    model_bundle: Bundle
    dataset_bundle: Bundle
    image_id: str
    source: bytes
    source_sha256: str
    canonical: bytes
    canonical_sha256: str
    padded_tx: bytes
    padded_tx_sha256: str
    preprocessing_record: bytes
    allocation: Allocation
    layout: Layout
    generation: int
    software_version: str
    mock_only: bool = True


@dataclass(frozen=True, slots=True)
class NumericalTarget:
    """Offline numerical requirements, never a compiled/live hardware identity."""
    W: int
    H: int
    N: int
    K: int
    bias_width: int

    def __post_init__(self):
        from .strict import integer, require
        from .dma import width_policy, transfer_length
        integer(self.W, 1, 0xffffffff); integer(self.H, 1, 0xffffffff)
        integer(self.K, 1, 64)
        width_policy(self.N, self.bias_width)
        transfer_length((self.W+self.N-1)*(self.H+self.N-1), 22)
        transfer_length(self.W*self.H*self.K*2, 22)


@dataclass(frozen=True, slots=True)
class OfflineContext:
    """Not a RunContext: cannot be issued or submitted by AdmissionSession."""
    target: NumericalTarget
    channels: tuple[Channel, ...]
    input_scale: Fraction
    model_bundle: Bundle
    dataset_bundle: Bundle
    image_id: str
    source: bytes
    source_sha256: str
    canonical: bytes
    canonical_sha256: str
    padded_tx: bytes
    padded_tx_sha256: str
    preprocessing_record: bytes
