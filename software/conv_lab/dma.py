"""Pure layout arithmetic/packing; supplied mock allocation only."""
from .strict import integer, require
from .types import Allocation, Layout


def width_policy(n, bias_width):
    integer(n, 1)
    integer(bias_width, 1, 32)
    require(n in (3, 5), "M2 implements N3/N5 only")
    total = 8 + 8 + (n*n - 1).bit_length() + 1
    return total, max(total, bias_width) + 1


def transfer_length(value, width):
    integer(width, 1, 32)
    return integer(value, 1, (1 << width)-1)


def _layout(w, h, n, k, allocation, proposed=None):
    require(type(allocation) is Allocation, "mock allocation required")
    for value in (w, h, k):
        integer(value, 1, 0xffffffff)
    require(n in (3, 5) and type(n) is int, "N3/N5 required")
    require(allocation.length_width == 22 and type(allocation.length_width) is int,
            "new family requires 22-bit DMA length")
    for name in ("base", "size", "aperture_start", "aperture_end", "alignment"):
        integer(getattr(allocation, name), 0 if name in ("base", "aperture_start") else 1)
    require(allocation.aperture_start <= allocation.base < allocation.aperture_end,
            "allocation outside supplied aperture")
    require(allocation.base + allocation.size <= allocation.aperture_end,
            "allocation extends beyond supplied aperture")
    require(allocation.alignment & (allocation.alignment - 1) == 0,
            "DMA alignment must be a power of two")
    tx = transfer_length((w+n-1)*(h+n-1), allocation.length_width)
    rx = transfer_length(w*h*k*2, allocation.length_width)
    expected_rxoff = ((4096+tx+128+63)//64)*64
    rxoff = expected_rxoff
    if proposed is not None:
        require(type(proposed) is Layout, "Layout required")
        for value in (proposed.tx_offset, proposed.tx_bytes,
                      proposed.rx_offset, proposed.rx_bytes):
            integer(value, 0)
        require(proposed.tx_offset == 4096 and proposed.tx_bytes == tx and
                proposed.rx_bytes == rx, "exact complete-frame lengths required")
        rxoff = proposed.rx_offset
    regions = (("tx_pre",4032,4096), ("tx",4096,4096+tx),
               ("tx_post",4096+tx,4096+tx+64), ("rx_pre",rxoff-64,rxoff),
               ("rx",rxoff,rxoff+rx), ("rx_post",rxoff+rx,rxoff+rx+64))
    previous = 0
    for _, start, end in regions:
        require(previous <= start < end <= allocation.size, "overlap/allocation bounds")
        previous = end
    for offset in (4096, rxoff):
        require((allocation.base+offset) % 64 == 0 and
                (allocation.base+offset) % allocation.alignment == 0,
                "physical payload alignment")
    require(rxoff == expected_rxoff, "approved RX offset required")
    result = Layout(4096, tx, rxoff, rx, regions)
    if proposed is not None:
        require(proposed == result, "payload/guard inventory differs from contract")
    return result


def layout(w, h, n, k, allocation):
    return _layout(w, h, n, k, allocation)


def validate_layout(w, h, n, k, allocation, proposed):
    """Validate a proposed layout through the same bounds/guard implementation."""
    return _layout(w, h, n, k, allocation, proposed)


def pad_pixels(canonical, w, h, n):
    require(type(canonical) is bytes and len(canonical) == w*h, "canonical byte count")
    require(n in (3, 5), "kernel")
    p, stride = (n-1)//2, w+n-1
    result = bytearray(stride*(h+n-1))
    for y in range(h):
        start = (y+p)*stride+p
        result[start:start+w] = canonical[y*w:(y+1)*w]
    return bytes(result)


def stream_beats(payload):
    """(64-bit word, TKEEP, TLAST); filler lanes never add transfer length."""
    require(type(payload) is bytes and len(payload) > 0, "empty stream")
    for pos in range(0, len(payload), 8):
        part = payload[pos:pos+8]
        yield int.from_bytes(part.ljust(8, b"\0"), "little"), (1 << len(part))-1, pos+8 >= len(payload)
