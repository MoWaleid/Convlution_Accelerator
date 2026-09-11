#!/usr/bin/env python3
"""M3 file-driven inference: model and dataset loaded from the installed
conv-lab library; TX generated from the PNG; bit-exact DMA verification."""
import ctypes
import hashlib
import json
import mmap
import os
import platform
import struct
import time
from pathlib import Path

LIB = Path("/opt/conv-lab/library")
MODEL_DIR = LIB / "models/N3_K8/m0-trained-cifar-k8/converted-1"
DATASET_DIR = LIB / "datasets/m0-cifar-cat/converted-1"
FRAMES = 3

TX, TX_SIZE = 0x1000, 34 * 34
RX, RX_SIZE, RX_CAP, GUARD = 0x10000, 32 * 32 * 8 * 2, 0x8000, 64
ERRORS = 0x4770
CANONICAL_SHA256 = "a240bb760e2a85951f5c4e27c95041e98d4919c5cc32114cc4f5191f6ffb6771"
PADDED_SHA256 = "967c1c7687d3775d4512bd30eaa7f07fc8e1956145ed82326b35eb8cff28f74e"
REFERENCE_SHA256 = "cb3975593073652b9d5f2fcb206748ad70c4abf621339ea19878b6863d9be705"


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


def load_model():
    model = json.loads((MODEL_DIR / "model.json").read_text())
    compat = model["compatibility"]
    n, k = compat["N"], compat["K"]
    geom = compat["geometry"][0]
    w, h = geom["W"], geom["H"]
    require(model["model_id"] == "m0-trained-cifar-k8", "Unexpected model id")
    cfg = json.loads((MODEL_DIR / "channel_config.json").read_text())
    channels = []
    for entry in cfg["channels"]:
        raw = [line.strip() for line in
               (MODEL_DIR / entry["weights_file"]).read_text().splitlines() if line.strip()]
        kernel = [v - 256 if v >= 128 else v for v in (int(x, 16) for x in raw)]
        require(len(kernel) == n * n, "Wrong kernel size: " + entry["weights_file"])
        channels.append((kernel, entry["bias_quantized"], entry["shift"],
                         1 if entry["relu_en"] else 0))
    require(len(channels) == k, "Wrong channel count")
    require(cfg["input_scale"]["numerator"] == 1 and
            cfg["input_scale"]["denominator"] == 256, "Unexpected input scale")
    return n, k, w, h, channels


def load_image(n, w, h):
    dataset = json.loads((DATASET_DIR / "dataset.json").read_text())
    image = dataset["images"][0]
    require(image["preprocessing"]["geometry_policy"] == "exact", "Geometry policy changed")
    png = DATASET_DIR / image["source"]["path"]
    require(hashlib.sha256(png.read_bytes()).hexdigest() == image["source"]["sha256"],
            "Dataset PNG hash mismatch")
    from PIL import Image
    grayscale = Image.open(png).convert("L")
    require(grayscale.size == (w, h), "Image geometry mismatch")
    raw = grayscale.tobytes()
    require(hashlib.sha256(raw).hexdigest() == CANONICAL_SHA256, "Canonical pixel hash mismatch")
    padded = bytearray((h + n - 1) * (w + n - 1))
    stride = w + n - 1
    for row in range(h):
        padded[(row + n // 2) * stride + n // 2:(row + n // 2) * stride + n // 2 + w] = \
            raw[row * w:(row + 1) * w]
    require(hashlib.sha256(bytes(padded)).hexdigest() == PADDED_SHA256, "Padded TX hash mismatch")
    return bytes(padded)


def make_expected(padded, n, w, h, channels):
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


def parameter_words(n, channels):
    words = {}
    for ch, (kernel, bias, shift, relu) in enumerate(channels):
        for group in range((n * n + 3) // 4):
            part = kernel[group * 4:group * 4 + 4]
            words[ch * 0x100 + group * 4] = sum((v & 255) << (8 * lane)
                                                for lane, v in enumerate(part))
        words[ch * 0x100 + 0xF8] = bias & 0xFFFFFFFF
        words[ch * 0x100 + 0xFC] = shift | (relu << 8)
    return words


def read32(regs, offset):
    return ctypes.c_uint32.from_buffer(regs, offset).value


def write32(regs, offset, value):
    ctypes.c_uint32.from_buffer(regs, offset).value = value


def wait_for(predicate, description, seconds=1.0):
    deadline = time.monotonic() + seconds
    while True:
        if predicate():
            return
        if time.monotonic() >= deadline:
            raise TimeoutError(description)
        time.sleep(0.001)


def map_uio(number, address):
    info = Path(f"/sys/class/uio/uio{number}/maps/map0")
    require(int((info / "addr").read_text(), 0) == address, "Wrong UIO address")
    require(int((info / "offset").read_text(), 0) == 0, "Unexpected UIO offset")
    size = int((info / "size").read_text(), 0)
    require(size >= 0x10000, "UIO aperture too small")
    fd = os.open(f"/dev/uio{number}", os.O_RDWR | os.O_SYNC)
    try:
        return mmap.mmap(fd, size, flags=mmap.MAP_SHARED,
                         prot=mmap.PROT_READ | mmap.PROT_WRITE)
    finally:
        os.close(fd)


def run_transfer(dma, accel, fd, phys, size, padded, expected, words, positions):
    require(phys % 8 == 0 and 0 <= phys < phys + size <= 0x20000000,
            "DMA allocation is unaligned or outside the HP0 DDR range")
    require(TX + TX_SIZE < RX - GUARD and RX + RX_CAP + GUARD <= size,
            "DMA buffer regions do not fit")
    initial = (read32(dma, 0x04), read32(dma, 0x34))
    require(all((status & 1) and not (status & (ERRORS | 8)) for status in initial),
            f"DMA must already be halted, error-free, and in simple mode: {initial}")
    require(read32(accel, 0x4008) == 0x803 and
            read32(accel, 0x400C) == 0x00200020 and
            read32(accel, 0x4000) == 1, "Unexpected accelerator configuration/state")
    original = {offset: read32(accel, offset) for offset in words}
    require(all(value == 0 for value in original.values()),
            "Expected zero configuration after boot or a passing test; nothing changed")

    def put(offset, data):
        require(os.pwrite(fd, data, offset) == len(data), "Short DMA-buffer write")

    def get(offset, count):
        data = os.pread(fd, count, offset)
        require(len(data) == count, "Short DMA-buffer read")
        return data

    put(TX, padded)
    put(RX - GUARD, b"\xA5" * (RX_CAP + 2 * GUARD))
    require(get(TX, TX_SIZE) == padded, "Input-buffer readback failed")
    print(f"TX: 0x{phys + TX:08X}, {TX_SIZE} bytes", flush=True)
    print(f"RX: 0x{phys + RX:08X}, capacity {RX_CAP} bytes", flush=True)

    def statuses():
        tx, rx = read32(dma, 0x04), read32(dma, 0x34)
        require(not ((tx | rx) & ERRORS),
                f"DMA error: MM2S=0x{tx:08X}, S2MM=0x{rx:08X}")
        return tx, rx

    success = False
    try:
        write32(dma, 0x00, 4)
        wait_for(lambda: not ((read32(dma, 0x00) | read32(dma, 0x30)) & 4),
                 "DMA reset timed out")
        require(read32(dma, 4) == read32(dma, 0x34) == 1, "Unexpected DMA reset state")
        for offset, value in words.items():
            write32(accel, offset, value)
            require(read32(accel, offset) == value, f"Parameter readback failed at +0x{offset:04X}")
        print("ALL PARAMETER WORDS VERIFIED", flush=True)
        write32(accel, 0x4004, 1)
        require(read32(accel, 0x4000) == 1, "Accelerator reset did not leave it idle")

        for frame in range(FRAMES):
            put(RX - GUARD, b"\xA5" * (RX_CAP + 2 * GUARD))
            write32(dma, 0x30, 1)
            wait_for(lambda: not (statuses()[1] & 1), "S2MM did not start")
            write32(dma, 0x48, phys + RX)
            require(read32(dma, 0x48) == phys + RX, "RX address readback failed")
            write32(dma, 0x58, RX_CAP)
            write32(dma, 0x00, 1)
            wait_for(lambda: not (statuses()[0] & 1), "MM2S did not start")
            write32(dma, 0x18, phys + TX)
            started = time.perf_counter()
            write32(dma, 0x28, TX_SIZE)
            wait_for(lambda: all((s & 0x1003) == 0x1002 for s in statuses()),
                     "DMA completion timed out", seconds=5.0)
            elapsed = time.perf_counter() - started
            received = read32(dma, 0x58)
            require(received == RX_SIZE, "Incorrect received packet length")
            require(read32(accel, 0x4000) == 1, "Accelerator remained busy")
            output = get(RX, RX_SIZE)
            values = struct.unpack("<8192h", output)
            mismatches = sum(values[i] != expected[i] for i in range(len(values)))
            require(get(RX - GUARD, GUARD) == b"\xA5" * GUARD, "Leading guard changed")
            require(get(RX + RX_SIZE, RX_CAP - RX_SIZE + GUARD) ==
                    b"\xA5" * (RX_CAP - RX_SIZE + GUARD), "Receive tail/guard changed")
            digest = hashlib.sha256(output).hexdigest()
            print(f"FRAME {frame + 1}: mismatches={mismatches}/{len(values)} "
                  f"guards=OK sha256={digest} "
                  f"time={elapsed * 1000:.3f} ms "
                  f"({positions / elapsed:.0f} positions/s)", flush=True)
            require(mismatches == 0, "Output mismatch")
            require(digest == REFERENCE_SHA256, "Output hash mismatch")

        put(TX, padded)
        require(get(TX, TX_SIZE) == padded, "Input buffer changed")
        print("OUTPUT AND GUARDS: PASS")
        success = True
    except BaseException:
        print(f"FAILURE SNAPSHOT: MM2S=0x{read32(dma, 4):08X}, "
              f"S2MM=0x{read32(dma, 0x34):08X}, "
              f"ACCEL=0x{read32(accel, 0x4000):08X}", flush=True)
        raise
    finally:
        write32(dma, 0x00, 0)
        write32(dma, 0x30, 0)
        wait_for(lambda: bool(read32(dma, 4) & read32(dma, 0x34) & 1),
                 "DMA did not halt: reboot before another test")
        print("DMA channels halted.", flush=True)
        if success:
            for offset, value in original.items():
                write32(accel, offset, value)
                require(read32(accel, offset) == value, "Parameter restore failed")
            print("Parameters restored. M3 FILE-DRIVEN INFERENCE: PASS", flush=True)
        else:
            print("Parameters retained for diagnosis. Do not rerun yet.", flush=True)


def main():
    require(platform.machine() == "armv7l", "Run this on the ZedBoard, not the VM")
    n, k, w, h, channels = load_model()
    print(f"MODEL: m0-trained-cifar-k8 converted-1 (N={n}, K={k}, geometry {w}x{h})", flush=True)
    padded = load_image(n, w, h)
    expected = make_expected(padded, n, w, h, channels)
    reference_hash = hashlib.sha256(struct.pack("<8192h", *expected)).hexdigest()
    require(reference_hash == REFERENCE_SHA256, "Software reference checksum mismatch")
    print("SOFTWARE REFERENCE VERIFIED AGAINST GOLDEN ANCHOR", flush=True)
    info = Path("/sys/class/u-dma-buf/udmabuf0")
    phys = int((info / "phys_addr").read_text(), 0)
    size = int((info / "size").read_text(), 0)
    from contextlib import ExitStack
    with ExitStack() as stack:
        dma = stack.enter_context(map_uio(0, 0x40400000))
        accel = stack.enter_context(map_uio(1, 0x43C00000))
        fd = os.open("/dev/udmabuf0", os.O_RDWR | os.O_SYNC)
        stack.callback(os.close, fd)
        run_transfer(dma, accel, fd, phys, size, padded, expected,
                     parameter_words(n, channels), w * h)


if __name__ == "__main__":
    main()
