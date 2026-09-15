#!/usr/bin/env python3
"""M7 profile switch manager: request a compiled profile, reprogram the PL
only when the live build identity differs, re-validate identity, install
that profile's parameters, and prove the activation frame bit-exact against
the on-board software reference.

Modes: --profile X [frames] | --soak X frames | --matrix

Frames are checked value-by-value against the on-board pure-Python reference
when that is cheap (all 32x32 profiles); profiles whose position count exceeds
REF_POSITION_LIMIT (D640) would need minutes of Python per frame, so they are
checked against the recorded golden anchor SHA-256 instead - the same evidence
style as the M0-M6 board runs.
"""
import hashlib
import json
import os
import re
import statistics
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m4_filebackend as fb
from conv_lab.strict import boolean, coefficients, integer, obj, parse_json, string

# ─── Paths ────────────────────────────────────────────────────────────────────
BASE = Path("/home/petalinux/profiles")
FW_DIR = Path("/lib/firmware")
try:
    import fcntl
except ImportError:  # mock hosts only; the board is Linux
    fcntl = None
LOCK_FILE = (Path("/run/lock/m7_switch.lock") if Path("/run/lock").is_dir()
             else Path("/tmp/m7_switch.lock"))
_lock_fd = None
FW_NAME = {"A32_CFGLUT125": "m7_A32_CFGLUT125.bin",
           "B32_CFGLUT125": "m7_B32_CFGLUT125.bin",
           "C32_CFGLUT125": "m7_C32_CFGLUT125.bin",
           "D32_CFGLUT125": "m7_D32_CFGLUT125.bin",
           "D640_CFGLUT125": "m7_D640_CFGLUT125.bin"}
ORDER = ["A32_CFGLUT125", "B32_CFGLUT125", "C32_CFGLUT125",
         "D32_CFGLUT125", "D640_CFGLUT125"]

# ─── FPGA Manager sysfs ──────────────────────────────────────────────────────
FPGA_FLAGS = Path("/sys/class/fpga_manager/fpga0/flags")
FPGA_FIRMWARE = Path("/sys/class/fpga_manager/fpga0/firmware")
FPGA_STATE = Path("/sys/class/fpga_manager/fpga0/state")

# ─── DMA register offsets (AXI DMA simple mode) ──────────────────────────────
DMA_MM2S_DMACR = 0x00
DMA_MM2S_SR = 0x04
DMA_MM2S_SA = 0x18
DMA_MM2S_LENGTH = 0x28
DMA_S2MM_DMACR = 0x30
DMA_S2MM_SR = 0x34
DMA_S2MM_DA = 0x48
DMA_S2MM_LENGTH = 0x58
DMA_ERRORS = 0x4770

# ─── CVH1 register offsets ───────────────────────────────────────────────────
REG_MAGIC = 0x4100
REG_ABI_VERSION = 0x4104
REG_CAPABILITIES = 0x4108
REG_STATUS = 0x410C
REG_COMMAND = 0x4110
REG_ERROR_FLAGS = 0x4118
REG_IMAGE_W = 0x4120
REG_IMAGE_H = 0x4124
REG_KERNEL_N = 0x4128
REG_CHANNEL_K = 0x412C
REG_EXPECTED_INPUT_BYTES = 0x4138
REG_EXPECTED_OUTPUT_BYTES = 0x413C
REG_INPUT_ACCEPT_BYTES = 0x4140
REG_INPUT_CONSUMED_BYTES = 0x4144
REG_CORE_ACCEPT_PIXELS = 0x4148
REG_OUTPUT_ACCEPT_BYTES = 0x414C
REG_BUILD_ID_0 = 0x4150
REG_DMA_LENGTH_WIDTH = 0x4160

CMD_START = 0x1
CMD_RESET = 0x2
CMD_ABORT = 0x4

STATUS_IDLE = 1 << 0
STATUS_BUSY = 1 << 1
STATUS_CORE_COMPLETE = 1 << 2
STATUS_OUTPUT_DRAINED = 1 << 3
STATUS_DONE = 1 << 4
STATUS_ERROR = 1 << 5
STATUS_FAULT = 1 << 6
STATUS_PARAM_COMPLETE = 1 << 7
STATUS_QUIESCENT = 1 << 8

TX_OFFSET = 0x1000
GUARD_SIZE = 64
GUARD_BYTE = 0xA5
# On-board reference cost is O(W*H*K*N^2) Python ops. At 32x32 that is <=2.4M
# ops (sub-second); D640 is 11M ops per frame (~minutes on the 650 MHz ARM),
# so above this position count the golden anchor SHA-256 is the frame check.
REF_POSITION_LIMIT = 65536


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def log(message):
    print(message, flush=True)


# ─── Profile parameter loading (strict validation) ───────────────────────────

def load_params(profile, n, k, hw_bias_width=None, max_shift=23):
    """Strictly admit the profile's canonical-flat-2 parameter bundle
    (explicit legacy conversion, see profiles/history/legacy_conversion_*):
    exact root/entry field sets, canonical JSON types, boolean relu_en (no
    integer coercion), required exact per-channel weight paths, coefficient
    grammar, bundle-declared signed bias width, and an immutable whole-bundle
    SHA-256 over every admitted byte. Returns (channels, bundle_sha256).

    hw_bias_width (R14-04): when given, the bundle must declare exactly the
    target hardware's signed bias width and every bias is bounded by it - a
    bundle's self-declaration alone never widens admission.

    max_shift (R14-01 containment, decision b): the MAC S4 rounding add is
    defective for shifts 24..31 (the round-up constant overflows/wraps at
    the fixed 25-bit width), so admission rejects shift >= 24. Shifts 0..23
    are arithmetically safe for this geometry and 4/7/8/9 are
    board-qualified; the research line lifts this bound explicitly."""
    d = BASE / profile
    cfg_bytes = (d / "channel_config.json").read_bytes()
    cfg = parse_json(cfg_bytes)
    obj(cfg, "format_version dialect N K bias_width channels")
    require(integer(cfg["format_version"], 1) == 2, f"{profile}: format_version 2")
    require(string(cfg["dialect"]) == "canonical-flat-2",
            f"{profile}: unknown bundle dialect")
    require(integer(cfg["N"], 1, 64) == n, f"{profile}: config N mismatch")
    require(integer(cfg["K"], 1, 64) == k, f"{profile}: config K mismatch")
    bias_width = integer(cfg["bias_width"], 1, 32)
    if hw_bias_width is not None:
        require(bias_width == hw_bias_width,
                f"{profile}: bundle bias_width {bias_width} != hardware "
                f"bias width {hw_bias_width}")
    lo, hi = -(1 << (bias_width - 1)), (1 << (bias_width - 1)) - 1

    digest = __import__("hashlib").sha256()
    digest.update(b"channel_config.json\0" + str(len(cfg_bytes)).encode() + b"\0"
                  + cfg_bytes)
    channels = []
    seen_channels = set()
    for entry in cfg["channels"]:
        e = obj(entry, "channel weights_file bias_quantized shift relu_en")
        ch = integer(e["channel"], 0, k - 1)
        require(ch not in seen_channels, f"{profile}: duplicate channel {ch}")
        require(ch == len(channels), f"{profile}: non-sequential channel {ch}")
        seen_channels.add(ch)

        require(string(e["weights_file"]) == f"kernel_ch{ch}.mem",
                f"{profile}: weights_file must be kernel_ch{ch}.mem")
        raw = (d / e["weights_file"]).read_bytes()
        digest.update(e["weights_file"].encode() + b"\0"
                      + str(len(raw)).encode() + b"\0" + raw)
        kernel = list(coefficients(raw, n))

        bias = integer(e["bias_quantized"], lo, hi)
        shift = integer(e["shift"], 0, 31)
        require(shift <= max_shift,
                f"{profile}: shift {shift} exceeds the frozen-baseline "
                f"admission scope 0..{max_shift} (R14-01 containment)")
        relu = boolean(e["relu_en"])

        channels.append((kernel, bias, shift, 1 if relu else 0))

    require(len(channels) == k, f"{profile}: channel count {len(channels)} != {k}")
    return channels, digest.hexdigest()


# ─── Activation input loading ─────────────────────────────────────────────────

def load_input(n, w, h):
    """Load or generate the activation input for a profile geometry.
    For 32×32: the library alley-cat PNG, converted to grayscale.
    For D640: the same source, LANCZOS-resized to 640×480 (recorded
    preprocessing per anchors_m7.json D640_preprocessing)."""
    from PIL import Image
    png = Path("/opt/conv-lab/library/datasets/m0-cifar-cat/converted-1/images/"
               "alley_cat_s_000013.png")
    require(hashlib.sha256(png.read_bytes()).hexdigest() ==
            "200f5baa120d957838037c7e28052ac998e82ddd94aef937173e37c3dfb470b0",
            "source PNG hash mismatch")
    image = Image.open(png).convert("L")
    if image.size != (w, h):
        image = image.resize((w, h), Image.LANCZOS)
    require(image.size == (w, h), f"input geometry {image.size} != {w}x{h}")
    raw = image.tobytes()
    stride = w + n - 1
    padded = bytearray(stride * (h + n - 1))
    for row in range(h):
        padded[(row + n // 2) * stride + n // 2:(row + n // 2) * stride + n // 2 + w] = \
            raw[row * w:(row + 1) * w]
    return bytes(padded)


# ─── Layout computation (per-profile, derived from M4 validated layout) ──────

def compute_layout(tx_bytes, rx_bytes, buffer_size):
    """Approved M1_DMA_CAPACITY guarded layout: G=64, TX_OFFSET=0x1000,
    RX_OFFSET = ALIGN_UP(TX_OFFSET + TX_BYTES + 2*G, 64), four 64-byte
    guards, RX DMA capacity exactly RX_BYTES, both transfer lengths bounded
    by the 22-bit DMA length field."""
    g = GUARD_SIZE
    require(tx_bytes > 0 and rx_bytes > 0, "TX/RX sizes must be positive")
    require(tx_bytes <= (1 << 22) - 1 and rx_bytes <= (1 << 22) - 1,
            "transfer exceeds the 22-bit DMA length field")
    tx_offset = TX_OFFSET
    require(tx_offset >= g, "TX leading guard would fall below buffer start")
    rx_offset = ((tx_offset + tx_bytes + 2 * g + 63) // 64) * 64
    extent = rx_offset + rx_bytes + g
    require(extent <= buffer_size,
            f"layout needs {extent} B but buffer is {buffer_size} B")
    require(tx_offset % 64 == 0 and rx_offset % 64 == 0, "payload alignment")
    return {
        "tx_offset": tx_offset, "tx_bytes": tx_bytes,
        "tx_lead_guard": tx_offset - g, "tx_tail_guard": tx_offset + tx_bytes,
        "rx_offset": rx_offset, "rx_bytes": rx_bytes,
        "rx_lead_guard": rx_offset - g, "rx_tail_guard": rx_offset + rx_bytes,
        "extent": extent,
    }


# ─── Hardware handle management ───────────────────────────────────────────────

def open_handles():
    import mmap
    dma_info = Path("/sys/class/uio/uio0/maps/map0")
    require(int((dma_info / "addr").read_text(), 0) == 0x40400000, "Wrong DMA UIO addr")
    accel_info = Path("/sys/class/uio/uio1/maps/map0")
    require(int((accel_info / "addr").read_text(), 0) == 0x43C00000, "Wrong accel UIO addr")
    dma_fd = os.open("/dev/uio0", os.O_RDWR | os.O_SYNC)
    accel_fd = os.open("/dev/uio1", os.O_RDWR | os.O_SYNC)
    buf_fd = os.open("/dev/udmabuf0", os.O_RDWR | os.O_SYNC)
    try:
        dma = mmap.mmap(dma_fd, 0x10000, flags=mmap.MAP_SHARED,
                        prot=mmap.PROT_READ | mmap.PROT_WRITE)
        accel = mmap.mmap(accel_fd, 0x10000, flags=mmap.MAP_SHARED,
                          prot=mmap.PROT_READ | mmap.PROT_WRITE)
        return dma, accel, buf_fd, [dma_fd, accel_fd]
    finally:
        os.close(dma_fd)
        os.close(accel_fd)


def close_handles(handles):
    dma, accel, buf_fd, _fds = handles
    dma.close()
    accel.close()
    os.close(buf_fd)


def read32(regs, offset):
    import ctypes
    return ctypes.c_uint32.from_buffer(regs, offset).value


def write32(regs, offset, value):
    import ctypes
    ctypes.c_uint32.from_buffer(regs, offset).value = value


def wait_for(predicate, description, seconds=5.0):
    deadline = time.monotonic() + seconds
    while True:
        if predicate():
            return
        if time.monotonic() >= deadline:
            raise TimeoutError(description)
        time.sleep(0.001)


def dma_halt(dma):
    write32(dma, DMA_MM2S_DMACR, 0)
    write32(dma, DMA_S2MM_DMACR, 0)
    wait_for(lambda: bool(read32(dma, DMA_MM2S_SR) & read32(dma, DMA_S2MM_SR) & 1),
             "DMA did not halt")


def dma_check_errors(dma):
    mm2s = read32(dma, DMA_MM2S_SR)
    s2mm = read32(dma, DMA_S2MM_SR)
    require(not ((mm2s | s2mm) & DMA_ERRORS),
            f"DMA error: MM2S=0x{mm2s:08X}, S2MM=0x{s2mm:08X}")
    return mm2s, s2mm


# ─── Identity ─────────────────────────────────────────────────────────────────

def read_identity(accel):
    return {
        "magic": read32(accel, REG_MAGIC),
        "abi": read32(accel, REG_ABI_VERSION),
        "caps": read32(accel, REG_CAPABILITIES),
        "build_id": "".join(f"{read32(accel, REG_BUILD_ID_0 + 4 * i):08x}"
                            for i in (3, 2, 1, 0)),
        "image_w": read32(accel, REG_IMAGE_W),
        "image_h": read32(accel, REG_IMAGE_H),
        "kernel_n": read32(accel, REG_KERNEL_N),
        "channel_k": read32(accel, REG_CHANNEL_K),
        "expected_input": read32(accel, REG_EXPECTED_INPUT_BYTES),
        "expected_output": read32(accel, REG_EXPECTED_OUTPUT_BYTES),
        "len_width": read32(accel, REG_DMA_LENGTH_WIDTH),
        "widths0": read32(accel, 0x4130),
        "widths1": read32(accel, 0x4134),
    }


def validate_identity(identity, hw):
    acc = hw["accelerator"]
    require(identity["magic"] == 0x43564831, "MAGIC mismatch")
    require(identity["abi"] == 0x00010000, "ABI_VERSION mismatch")
    require(identity["caps"] == 0x1FF, "CAPABILITIES mismatch")
    require(identity["build_id"] == acc["build_id_hex"],
            f"BUILD_ID {identity['build_id']} != {acc['build_id_hex']}")
    require((identity["image_w"], identity["image_h"]) ==
            (acc["image_w"], acc["image_h"]), "geometry mismatch")
    require((identity["kernel_n"], identity["channel_k"]) ==
            (acc["kernel_n"], acc["channels_k"]), "N/K mismatch")
    require((identity["expected_input"], identity["expected_output"]) ==
            (acc["expected_input_bytes"], acc["expected_output_bytes"]),
            "byte counts mismatch")
    require(identity["len_width"] == acc["dma_length_width"], "DMA_LENGTH_WIDTH mismatch")
    require(identity["widths0"] == 0x10180808, "WIDTHS_0 mismatch")
    require(identity["widths1"] == 0x1900 + 17 + (acc["kernel_n"] ** 2 - 1).bit_length(),
            "WIDTHS_1 mismatch")


# ─── FPGA Manager programming ─────────────────────────────────────────────────

def program_fpga(firmware_path):
    require(firmware_path.is_file(), f"firmware missing: {firmware_path}")
    FPGA_FLAGS.write_text("0")
    FPGA_FIRMWARE.write_text(firmware_path.name)
    wait_for(lambda: FPGA_STATE.read_text().strip() == "operating",
             "FPGA programming timed out", 10.0)


FPGA_STATE = Path("/sys/class/fpga_manager/fpga0/state")


# ─── Frame execution ──────────────────────────────────────────────────────────

def run_frame(dma, accel, buf_fd, phys, layout, padded, expected, k):
    tx_offset = layout["tx_offset"]
    tx_bytes = layout["tx_bytes"]
    rx_offset = layout["rx_offset"]
    rx_bytes = layout["rx_bytes"]
    require((phys + tx_offset) % 64 == 0 and (phys + rx_offset) % 64 == 0,
            "physical payload alignment")

    # Write all four guards, then the TX payload
    guard = b"\xA5" * GUARD_SIZE
    require(os.pwrite(buf_fd, guard, layout["tx_lead_guard"]) == GUARD_SIZE,
            "TX lead guard write failed")
    require(os.pwrite(buf_fd, guard, layout["tx_tail_guard"]) == GUARD_SIZE,
            "TX tail guard write failed")
    require(os.pwrite(buf_fd, padded, tx_offset) == len(padded), "TX write failed")
    # Verify TX readback
    require(os.pread(buf_fd, len(padded), tx_offset) == padded, "TX readback failed")

    # Clear stale channel status (write-1-to-clear; Halted bit0 is read-only)
    write32(dma, DMA_MM2S_SR, 0xFFFFFFFF)
    write32(dma, DMA_S2MM_SR, 0xFFFFFFFF)

    # Write RX guards (lead before RX, tail after RX)
    require(os.pwrite(buf_fd, b"\xA5" * GUARD_SIZE, rx_offset - GUARD_SIZE) == GUARD_SIZE,
            "RX lead guard write failed")
    require(os.pwrite(buf_fd, b"\xA5" * GUARD_SIZE, rx_offset + rx_bytes) == GUARD_SIZE,
            "RX tail guard write failed")

    # Arm S2MM first (before MM2S starts streaming)
    write32(dma, DMA_S2MM_DMACR, 1)
    wait_for(lambda: not (read32(dma, DMA_S2MM_SR) & 1), "S2MM did not start")
    write32(dma, DMA_S2MM_DA, phys + rx_offset)
    require(read32(dma, DMA_S2MM_DA) == phys + rx_offset, "RX address readback failed")
    write32(dma, DMA_S2MM_LENGTH, rx_bytes)

    # Arm MM2S
    write32(dma, DMA_MM2S_DMACR, 1)
    wait_for(lambda: not (read32(dma, DMA_MM2S_SR) & 1), "MM2S did not start")
    write32(dma, DMA_MM2S_SA, phys + tx_offset)
    require(read32(dma, DMA_MM2S_SA) == phys + tx_offset, "TX address readback failed")

    # CVH1 START arms the frame (counters zeroed, state RUN) before the MM2S
    # length release starts the stream - the proven M4 sequence.
    write32(accel, REG_COMMAND, CMD_START)
    wait_for(lambda: read32(accel, REG_STATUS) & STATUS_BUSY,
             "accelerator did not start")

    started = time.perf_counter()
    write32(dma, DMA_MM2S_LENGTH, tx_bytes)  # This triggers the transfer

    # Wait for both DMA channels to complete AND accelerator to be done.
    # DMA completion: both SR have bit12 (IOC) set and bit0 (halt) clear.
    # Accelerator completion: STATUS has DONE and IDLE bits.
    def both_complete():
        mm2s = read32(dma, DMA_MM2S_SR)
        s2mm = read32(dma, DMA_S2MM_SR)
        status = read32(accel, REG_STATUS)
        # Check for DMA errors
        if (mm2s | s2mm) & DMA_ERRORS:
            raise RuntimeError(f"DMA error: MM2S=0x{mm2s:08X}, S2MM=0x{s2mm:08X}")
        # Check for accelerator fault
        if status & (STATUS_FAULT | STATUS_ERROR):
            raise RuntimeError(f"Accelerator fault: STATUS=0x{status:08X}")
        # DMA IOC (bit12) set for both channels, accelerator fully drained
        return ((mm2s & 0x1000) and (s2mm & 0x1000)
                and (status & STATUS_DONE)
                and (status & STATUS_OUTPUT_DRAINED)
                and (status & STATUS_QUIESCENT))

    wait_for(both_complete, "frame did not complete", 10.0)
    elapsed = time.perf_counter() - started

    # Verify received length
    received = read32(dma, DMA_S2MM_LENGTH)
    require(received == rx_bytes, f"received {received} != {rx_bytes}")

    # Verify accelerator counters
    for name, addr, want in (
            ("input_accept", REG_INPUT_ACCEPT_BYTES, tx_bytes),
            ("input_consumed", REG_INPUT_CONSUMED_BYTES, tx_bytes),
            ("core_accept", REG_CORE_ACCEPT_PIXELS, rx_bytes // (2 * k)),
            ("output_accept", REG_OUTPUT_ACCEPT_BYTES, rx_bytes)):
        got = read32(accel, addr)
        require(got == want, f"counter {name}={got} != {want}")

    # Verify accelerator is idle (not faulted)
    status = read32(accel, REG_STATUS)
    require(not (status & (STATUS_FAULT | STATUS_ERROR)),
            f"accelerator fault after frame: 0x{status:08X}")

    # Read output and verify all four guards
    output = os.pread(buf_fd, rx_bytes, rx_offset)
    require(os.pread(buf_fd, GUARD_SIZE, layout["tx_lead_guard"]) == b"\xA5" * GUARD_SIZE,
            "TX lead guard corrupted")
    require(os.pread(buf_fd, GUARD_SIZE, layout["tx_tail_guard"]) == b"\xA5" * GUARD_SIZE,
            "TX tail guard corrupted")
    require(os.pread(buf_fd, GUARD_SIZE, layout["rx_lead_guard"]) == b"\xA5" * GUARD_SIZE,
            "RX lead guard corrupted")
    require(os.pread(buf_fd, GUARD_SIZE, layout["rx_tail_guard"]) == b"\xA5" * GUARD_SIZE,
            "RX tail guard corrupted")

    values = struct.unpack(f"<{rx_bytes // 2}h", output)
    mismatches = 0 if expected is None else \
        sum(values[i] != expected[i] for i in range(len(values)))
    return values, mismatches, hashlib.sha256(output).hexdigest(), elapsed


# ─── Profile switch (full lifecycle) ──────────────────────────────────────────

def resolve_release(release_id, catalog):
    """Gate-1 identity resolution (M10 D2): a hardware release binds one
    shape/ABI ID, one firmware manifest and one admitted parameter bundle.
    Releases are orthogonal to model bundles; the bundle's content hash is
    cross-checked at admission time against the release binding."""
    rel = (catalog.get("releases") or {}).get(release_id)
    require(rel is not None, f"{release_id}: no release entry in catalog")
    for key in ("shape_id", "bundle_sha256", "manifest", "build_id_hex"):
        require(key in rel, f"{release_id}: release entry missing {key}")
    return rel


def release_bundle_dir(profile, catalog_doc):
    """Parameter directory for a release: catalog bundle_dir when bound,
    otherwise the release name itself (GLM-F6: every load_params call site
    must go through this, never the raw release name)."""
    rel = resolve_release(profile, catalog_doc)
    bundle = rel.get("bundle_dir", profile)
    require(type(bundle) is str and bundle not in ("", ".", "..")
            and Path(bundle).name == bundle,
            f"{profile}: invalid release bundle_dir")
    return bundle


def switch_to(profile, catalog, anchors, ctx):
    """One full profile request through the seven-phase lifecycle.
    Returns True if the PL was reprogrammed, False for parameter-only change."""
    hw = json.loads((BASE / f"hardware_{profile}.json").read_text())
    acc = hw["accelerator"]
    profs = catalog.get("profiles", catalog)
    cat = profs.get(profile) or {}
    require(cat, f"{profile}: missing catalog entry")
    require((acc["image_w"], acc["image_h"], acc["kernel_n"], acc["channels_k"],
             acc["build_id_hex"]) ==
            (cat["W"], cat["H"], cat["N"], cat["K"], cat["build_id"]),
            f"{profile}: manifest disagrees with catalog")
    rel = resolve_release(profile, catalog)
    require(rel["build_id_hex"] == acc["build_id_hex"],
            f"{profile}: release build_id disagrees with manifest")
    shape = (f"N{acc['kernel_n']}K{acc['channels_k']}"
             f"W{acc['image_w']}H{acc['image_h']}-CVH1")
    require(rel["shape_id"] == shape,
            f"{profile}: release shape {rel['shape_id']} != manifest shape {shape}")
    require(hw.get("deployable", True) is True,
            f"{profile}: manifest explicitly marks this release non-deployable")
    n = acc["kernel_n"]
    k = acc["channels_k"]
    w = acc["image_w"]
    h = acc["image_h"]
    tx_bytes = acc["expected_input_bytes"]
    rx_bytes = acc["expected_output_bytes"]

    # Phase: VALIDATING — candidate firmware + parameter files + live identity
    declared_bin = hw["artifacts"]["firmware_bin_sha256"]
    declared_bit = hw["artifacts"]["bitstream_sha256"]
    require(re.fullmatch(r"[0-9a-f]{64}", declared_bin) is not None
            and re.fullmatch(r"[0-9a-f]{64}", declared_bit) is not None,
            f"{profile}: manifest artifact hashes are not canonical SHA-256 "
            "- non-deployable candidate/placeholder manifest (GLM-F7)")
    firmware = FW_DIR / FW_NAME[profile]
    require(firmware.is_file(), f"firmware missing: {firmware}")
    firmware_hash = hashlib.sha256(firmware.read_bytes()).hexdigest()
    require(firmware_hash == hw["artifacts"]["firmware_bin_sha256"],
            f"{profile}: firmware hash mismatch")
    channels, bundle_hash = load_params(rel.get("bundle_dir", profile), n, k,
                                        hw_bias_width=acc["bias_width"])
    require(bundle_hash == rel["bundle_sha256"],
            f"{profile}: admitted bundle {bundle_hash[:16]} != release-bound "
            f"bundle {rel['bundle_sha256'][:16]}")
    log(f"  admitted {profile} parameter bundle {bundle_hash[:16]}")

    require(ctx.get("buffer_size"), "runtime buffer size not discovered")
    layout = compute_layout(tx_bytes, rx_bytes, ctx["buffer_size"])

    # VALIDATING: read live identity (safe, read-only)
    if ctx["handles"] is None:
        ctx["handles"] = open_handles()
    dma, accel, buf_fd, _fds = ctx["handles"]
    live = read_identity(accel)
    status = read32(accel, REG_STATUS)
    require(status & STATUS_QUIESCENT, f"not quiescent: 0x{status:08X}")
    require(not (status & (STATUS_ERROR | STATUS_FAULT)),
            f"entry state has errors/fault: 0x{status:08X}")

    reload_needed = live["build_id"] != acc["build_id_hex"]

    if reload_needed:
        # Phase: QUIESCING + DETACHED
        dma_halt(dma)
        close_handles(ctx["handles"])
        ctx["handles"] = None

        # Phase: PROGRAMMING
        program_fpga(firmware)

        # Phase: REATTACHING
        ctx["handles"] = open_handles()
        dma, accel, buf_fd, _fds = ctx["handles"]
        identity = read_identity(accel)
        validate_identity(identity, hw)
        status = read32(accel, REG_STATUS)
        require(status == 0x101,
                f"stale state survived reload: 0x{status:08X} (expected 0x101)")
        require(read32(accel, REG_ERROR_FLAGS) == 0, "errors survived reload")
        log(f"  reprogrammed fabric -> {profile} ({acc['build_id_ascii']})")
    else:
        validate_identity(live, hw)
        log(f"  live build already {profile}: parameter re-admission only")

    # Phase: SELF_TEST — install parameters + reference-checked activation frame
    program_params_accel(accel, n, channels)
    padded = load_input(n, w, h)
    expected = make_expected(padded, n, w, h, channels) \
        if w * h * k <= REF_POSITION_LIMIT else None
    values, mismatches, out_sha, elapsed = run_frame(
        dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
    require(mismatches == 0, f"{profile}: {mismatches} mismatches")

    anchor = anchors.get(profile, {}).get("output_sha256")
    require(anchor is not None or expected is not None,
            f"{profile}: no golden anchor for reference-free validation")
    if anchor:
        require(out_sha == anchor,
                f"{profile}: output SHA {out_sha[:16]} != anchor {anchor[:16]}")

    log(f"  [{profile}] activation OK {elapsed * 1000:.3f} ms sha={out_sha[:16]}")
    ctx["digests"].append((profile, out_sha))
    return reload_needed


def program_params_accel(accel, n, channels):
    """Program all channel parameters and wait for PARAM_COMPLETE."""
    words = {}
    for ch, (kernel, bias, shift, relu) in enumerate(channels):
        n_words = (len(kernel) + 3) // 4
        for group in range(n_words):
            part = kernel[group * 4:group * 4 + 4]
            addr = ch * 0x100 + group * 4
            words[addr] = sum((v & 0xFF) << (8 * lane) for lane, v in enumerate(part))
        words[ch * 0x100 + 0xF8] = bias & 0xFFFFFFFF
        words[ch * 0x100 + 0xFC] = shift | (relu << 8)
    for offset, value in words.items():
        write32(accel, offset, value)
        require(read32(accel, offset) == value, f"param readback failed @ +0x{offset:04X}")
    wait_for(lambda: read32(accel, REG_STATUS) & STATUS_PARAM_COMPLETE,
             "PARAM_COMPLETE never set", 1.0)
    return words


def make_expected(padded, n, w, h, channels):
    """Software reference: exact same arithmetic as the RTL."""
    expected = []
    for row in range(h):
        for col in range(w):
            for kernel, bias, shift, relu in channels:
                total = bias
                for kr in range(n):
                    for kc in range(n):
                        total += padded[(row + kr) * (w + n - 1) + col + kc] * kernel[kr * n + kc]
                if shift:
                    total = (total + (1 << (shift - 1))) >> shift
                value = min(32767, max(-32768, total))
                expected.append(max(0, value) if relu else value)
    return expected


# ─── Matrix construction (with termination guarantee) ─────────────────────────

def build_matrix_sequence(start_profile):
    """Build a switch sequence: establish A32_CFGLUT125, then 20 consecutive
    A32→B32→A32 cycles, then every other ordered pair. Greedy walk with
    bridge jumps; returns list of release names. The initial bridge makes the
    twenty cycles provably consecutive regardless of the live start release."""
    sequence = []
    current = start_profile
    covered = set()
    anchor_a = ORDER[0]   # A32_CFGLUT125
    anchor_b = ORDER[1]   # B32_CFGLUT125

    # Establish A32 before the counted block (E2: without this, a non-A32
    # start yields only 19 consecutive full cycles).
    if current != anchor_a:
        sequence.append(anchor_a)
        covered.add((current, anchor_a))
        current = anchor_a

    # 20 consecutive A32→B32→A32 cycles
    for _ in range(20):
        sequence.append(anchor_b)
        covered.add((current, anchor_b))
        current = anchor_b
        sequence.append(anchor_a)
        covered.add((current, anchor_a))
        current = anchor_a

    # Remaining ordered pairs
    all_ordered = [(a, b) for a in ORDER for b in ORDER if a != b]
    remaining = [p for p in all_ordered if p not in covered]

    while remaining:
        # Try to find a pair starting from current
        step = next((p for p in remaining if p[0] == current), None)
        if step is None:
            # Bridge: find any remaining pair, go to its source first
            step = remaining[0]
            if current != step[0]:
                sequence.append(step[0])
                covered.add((current, step[0]))
                current = step[0]
        sequence.append(step[1])
        covered.add((current, step[1]))
        current = step[1]
        remaining.remove(step)

    return sequence


# ─── Modes ────────────────────────────────────────────────────────────────────

def acquire_lock():
    """OS-backed exclusive ownership (M1_ACTIVATION_LIFECYCLE): an flock is
    held for the process lifetime and released by the kernel even on abrupt
    exit; release never unlinks by name. Hosts without fcntl (mock tests)
    get pid recording only - no exclusivity there."""
    global _lock_fd
    require(_lock_fd is None, "lock already held by this process")
    if fcntl is not None:
        fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            raise RuntimeError(f"another instance holds {LOCK_FILE}")
        os.ftruncate(fd, 0)
        os.write(fd, str(os.getpid()).encode())
        _lock_fd = fd
    else:
        fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
        os.write(fd, str(os.getpid()).encode())
        _lock_fd = fd


def release_lock():
    global _lock_fd
    if _lock_fd is None:
        return
    try:
        os.close(_lock_fd)
    finally:
        _lock_fd = None


def main():
    fb.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    mode = sys.argv[1] if len(sys.argv) > 1 else "--help"

    acquire_lock()
    ctx = None
    mode_result = {"label": None, "ok": False}
    try:
        catalog_doc = json.loads((BASE / "m7_profiles.json").read_text())
        catalog = catalog_doc["profiles"]
        anchors = json.loads((BASE / "anchors_m7.json").read_text())
        info = Path("/sys/class/u-dma-buf/udmabuf0")
        ctx = {
            "phys": int((info / "phys_addr").read_text(), 0),
            "buffer_size": int((info / "size").read_text(), 0),
            "anchors": anchors,
            "handles": None,
            "digests": [],
        }

        if mode == "--profile":
            require(len(sys.argv) >= 3, "usage: --profile X [frames]")
            profile = sys.argv[2]
            frames = int(sys.argv[3]) if len(sys.argv) > 3 else 3
            require(profile in catalog, f"unknown profile {profile}")
            reloaded = switch_to(profile, catalog_doc, anchors, ctx)
            do_switch_frames(profile, catalog_doc, anchors, ctx, frames)
            mode_result["label"] = (f"M7_SWITCH {profile}: PASS ({frames} frames, "
                                    f"reload={'yes' if reloaded else 'no'})")
            mode_result["ok"] = True

        elif mode == "--matrix":
            # Determine starting profile from live hardware
            preflight = open_handles()
            live = read_identity(preflight[1])
            start_profile = next((p for p, d in catalog.items()
                                  if d["build_id"] == live["build_id"]), None)
            require(start_profile is not None,
                    f"live BUILD_ID {live['build_id']} does not match any catalog profile")
            close_handles(preflight)
            ctx["handles"] = None

            sequence = build_matrix_sequence(start_profile)
            log(f"PHASE MATRIX: starting from {start_profile}, "
                f"{len(sequence)} switches")

            reloaded_count = 0
            started = time.monotonic()
            observed_transitions = set()
            prev = start_profile
            try:
                for i, target in enumerate(sequence):
                    was_reload = switch_to(target, catalog_doc, anchors, ctx)
                    observed_transitions.add((prev, target))
                    reloaded_count += 1 if was_reload else 0
                    prev = target
                    if (i + 1) % 10 == 0:
                        log(f"  ... {i + 1}/{len(sequence)} switches, "
                            f"{reloaded_count} reloads")

                # Verify coverage
                all_pairs = {(a, b) for a in ORDER for b in ORDER if a != b}
                missing = all_pairs - observed_transitions
                require(not missing, f"uncovered pairs: {missing}")
                log(f"SUMMARY: {len(sequence)} switches, {reloaded_count} full-PL "
                    f"reloads, {len(observed_transitions)} ordered pairs covered, "
                    f"{time.monotonic() - started:.1f} s")
                mode_result["label"] = "M7 SWITCH MATRIX: PASS"
            except BaseException:
                if ctx["handles"]:
                    print(f"FAILURE SNAPSHOT: MM2S=0x{read32(ctx['handles'][0], 4):08X}, "
                          f"S2MM=0x{read32(ctx['handles'][0], 0x34):08X}", flush=True)
                raise
            finally:
                if ctx["handles"]:
                    dma_halt(ctx["handles"][0])
                    status = read32(ctx["handles"][1], REG_STATUS)
                    if ((status & (STATUS_IDLE | STATUS_FAULT))
                            and (status & STATUS_QUIESCENT)):
                        write32(ctx["handles"][1], REG_COMMAND, CMD_RESET)
                        wait_for(lambda: read32(ctx["handles"][1], REG_STATUS) &
                                 STATUS_IDLE, "final RESET", 2.0)
                        final = read32(ctx["handles"][1], REG_STATUS)
                        require(final == 0x181, f"final state 0x{final:08X} != 0x181")
                        mode_result["ok"] = True
                    else:
                        print(f"final state unresolved 0x{status:08X} - recovery "
                              f"required; PASS withheld", flush=True)
                    close_handles(ctx["handles"])
                    ctx["handles"] = None
                    print("handles closed", flush=True)

        elif mode == "--soak":
            require(len(sys.argv) >= 4, "usage: --soak X frames")
            profile, frames = sys.argv[2], int(sys.argv[3])
            require(profile in catalog, f"unknown profile {profile}")
            switch_to(profile, catalog_doc, anchors, ctx)
            hw = json.loads((BASE / f"hardware_{profile}.json").read_text())
            acc = hw["accelerator"]
            n, k, w, h = acc["kernel_n"], acc["channels_k"], acc["image_w"], acc["image_h"]
            channels, _bundle = load_params(
                release_bundle_dir(profile, catalog_doc), n, k,
                hw_bias_width=acc["bias_width"])
            padded = load_input(n, w, h)
            expected = make_expected(padded, n, w, h, channels) \
                if w * h * k <= REF_POSITION_LIMIT else None
            anchor = anchors.get(profile, {}).get("output_sha256")
            require(expected is not None or anchor is not None,
                    f"{profile}: no reference available")
            layout = compute_layout(acc["expected_input_bytes"],
                                    acc["expected_output_bytes"], ctx["buffer_size"])
            dma, accel, buf_fd, _fds = ctx["handles"]
            latencies = []
            for frame in range(frames):
                values, mismatches, out_sha, elapsed = run_frame(
                    dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
                require(mismatches == 0, f"frame {frame + 1}: {mismatches} mismatches")
                if anchor:
                    require(out_sha == anchor,
                            f"frame {frame + 1}: output SHA {out_sha[:16]} != anchor")
                latencies.append(elapsed)
                if (frame + 1) % 10 == 0:
                    log(f"  {frame + 1}/{frames} frames bit-exact")
            med = statistics.median(latencies)
            log(f"M7 SOAK {profile}: SUMMARY — {frames} frames, "
                f"median {med * 1000:.3f} ms, min {min(latencies) * 1000:.3f}, "
                f"max {max(latencies) * 1000:.3f}")
            mode_result["label"] = (f"M7 SOAK {profile}: PASS — {frames} frames, "
                                    f"median {med * 1000:.3f} ms, "
                                    f"min {min(latencies) * 1000:.3f}, "
                                    f"max {max(latencies) * 1000:.3f}")
            mode_result["ok"] = True

        else:
            print("usage: m7_switch.py --profile X [frames] | --soak X N | --matrix")
            sys.exit(2)
    finally:
        try:
            safe_cleanup(ctx)
        except Exception as exc:
            print(f"cleanup issue: {exc}", flush=True)
            mode_result["ok"] = False
        release_lock()
        if mode_result["label"] and mode_result["ok"]:
            print(mode_result["label"], flush=True)


def safe_cleanup(ctx):
    """Guaranteed post-run cleanup: halt DMA, then CVH1 RESET only from a
    legal quiescent state (IDLE or FAULT *with* QUIESCENT) - the ABI admits
    RESET only there, and resetting faulted-but-unquiescent fabric risks the
    known SLVERR/SIGBUS behavior. Unresolved states are refused and left for
    qualified recovery instead of being silently reset."""
    if not ctx or not ctx.get("handles"):
        return
    dma, accel, buf_fd, _fds = ctx["handles"]
    try:
        dma_halt(dma)
        status = read32(accel, REG_STATUS)
        if (status & (STATUS_IDLE | STATUS_FAULT)) and (status & STATUS_QUIESCENT):
            write32(accel, REG_COMMAND, CMD_RESET)
            wait_for(lambda: read32(accel, REG_STATUS) & STATUS_IDLE,
                     "cleanup RESET", 2.0)
            final = read32(accel, REG_STATUS)
            require(final == 0x181, f"cleanup final state 0x{final:08X} != 0x181")
            log(f"  cleanup: final STATUS 0x{final:08X}")
        else:
            raise RuntimeError(
                f"cleanup refused: illegal reset state 0x{status:08X} "
                "- recovery required")
    finally:
        close_handles(ctx["handles"])
        ctx["handles"] = None


def do_switch_frames(profile, catalog_doc, anchors, ctx, frames):
    hw = json.loads((BASE / f"hardware_{profile}.json").read_text())
    acc = hw["accelerator"]
    n, k, w, h = acc["kernel_n"], acc["channels_k"], acc["image_w"], acc["image_h"]
    channels, _bundle = load_params(
        release_bundle_dir(profile, catalog_doc), n, k,
        hw_bias_width=acc["bias_width"])
    padded = load_input(n, w, h)
    expected = make_expected(padded, n, w, h, channels) \
        if w * h * k <= REF_POSITION_LIMIT else None
    anchor = anchors.get(profile, {}).get("output_sha256")
    require(expected is not None or anchor is not None,
            f"{profile}: no reference available")
    layout = compute_layout(acc["expected_input_bytes"], acc["expected_output_bytes"],
                            ctx["buffer_size"])
    dma, accel, buf_fd, _fds = ctx["handles"]
    for frame in range(frames - 1):
        values, mismatches, out_sha, elapsed = run_frame(
            dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
        require(mismatches == 0, f"frame {frame + 2}: {mismatches} mismatches")
        if anchor:
            require(out_sha == anchor,
                    f"frame {frame + 2}: output SHA {out_sha[:16]} != anchor")
        log(f"  [{profile}] frame {frame + 2} OK {elapsed * 1000:.3f} ms")


if __name__ == "__main__":
    main()
