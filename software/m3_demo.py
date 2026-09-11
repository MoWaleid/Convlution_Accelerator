#!/usr/bin/env python3
"""M3 demo runner: trained + custom filter frames over library and demo
images; renders feature maps to PNGs on the board. Built on m3_filebackend."""
import hashlib
import math
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m3_filebackend as fb

DEMO_DIRS = [Path("/home/petalinux/demo_images")]
OUT = Path("/home/petalinux/demo_out")
FRAMES_PER_CONFIG = 2
CUSTOM = (
    ((0, 0, 0, 0, 127, 0, 0, 0, 0), 0, 7, 0),
    ((-1, 0, 1, -2, 0, 2, -1, 0, 1), 0, 8, 0),
    ((-1, -2, -1, 0, 0, 0, 1, 2, 1), 0, 8, 0),
    ((1, 2, 1, 2, 4, 2, 1, 2, 1), 0, 4, 0),
)
CUSTOM_NAMES = ("identity", "sobel_x", "sobel_y", "blur")


def pad(raw, n, w, h):
    require = fb.require
    stride = w + n - 1
    padded = bytearray(stride * (h + n - 1))
    for row in range(h):
        padded[(row + n // 2) * stride + n // 2:(row + n // 2) * stride + n // 2 + w] = \
            raw[row * w:(row + 1) * w]
    return bytes(padded)


def collect_images(n, w, h):
    from PIL import Image
    images = []
    cat = fb.load_image(n, w, h)
    images.append(("library_alley_cat", cat))
    for directory in DEMO_DIRS:
        for path in sorted(directory.glob("*.png")):
            im = Image.open(path).convert("L")
            fb.require(im.size == (w, h), "demo image geometry: " + path.name)
            images.append((path.stem, im.tobytes()))
    return images


def render_plane(values, offset, stride, w, h, path):
    from PIL import Image
    plane = values[offset::stride]
    lo, hi = min(plane), max(plane)
    span = (hi - lo) or 1
    pixels = bytes(int((v - lo) * 255 / span) for v in plane)
    Image.frombytes("L", (w, h), pixels).resize((w * 8, h * 8), Image.NEAREST).save(path)


def render_sobel(values, k, w, h, path):
    from PIL import Image
    sx = values[1::k]
    sy = values[2::k]
    mag = [min(1443, int(math.sqrt(a * a + b * b))) for a, b in zip(sx, sy)]
    lo, hi = min(mag), max(mag)
    span = (hi - lo) or 1
    pixels = bytes(int((v - lo) * 255 / span) for v in mag)
    Image.frombytes("L", (w, h), pixels).resize((w * 8, h * 8), Image.NEAREST).save(path)


def run_frame(dma, accel, fd, phys, padded, expected, words):
    fb.write32(accel, 0x4004, 1)
    fb.require(fb.read32(accel, 0x4000) == 1, "Accelerator not idle after soft reset")
    for offset, value in words.items():
        fb.write32(accel, offset, value)
        fb.require(fb.read32(accel, offset) == value, "Parameter readback failed")
    os_pwrite, os_pread = fb.os.pwrite, fb.os.pread
    fb.require(os_pwrite(fd, padded, fb.TX) == len(padded), "TX write failed")
    fb.require(os_pread(fd, len(padded), fb.TX) == padded, "TX readback failed")
    fb.require(os_pwrite(fd, b"\xA5" * (fb.RX_CAP + 2 * fb.GUARD), fb.RX - fb.GUARD) ==
               fb.RX_CAP + 2 * fb.GUARD, "RX guard write failed")
    fb.write32(dma, 0x30, 1)
    fb.wait_for(lambda: not (dma_status(dma)[1] & 1), "S2MM did not start")
    fb.write32(dma, 0x48, phys + fb.RX)
    fb.write32(dma, 0x58, fb.RX_CAP)
    fb.write32(dma, 0x00, 1)
    fb.wait_for(lambda: not (dma_status(dma)[0] & 1), "MM2S did not start")
    fb.write32(dma, 0x18, phys + fb.TX)
    started = time.perf_counter()
    fb.write32(dma, 0x28, fb.TX_SIZE)
    fb.wait_for(lambda: all((s & 0x1003) == 0x1002 for s in dma_status(dma)),
                "DMA completion timed out", seconds=5.0)
    elapsed = time.perf_counter() - started
    received = fb.read32(dma, 0x58)
    fb.require(received == fb.RX_SIZE, "Incorrect received packet length")
    output = os_pread(fd, fb.RX_SIZE, fb.RX)
    values = struct.unpack("<8192h", output)
    mismatches = sum(values[i] != expected[i] for i in range(len(values)))
    fb.require(os_pread(fd, fb.GUARD, fb.RX - fb.GUARD) == b"\xA5" * fb.GUARD, "Lead guard")
    fb.require(os_pread(fd, fb.RX_CAP - fb.RX_SIZE + fb.GUARD, fb.RX + fb.RX_SIZE) ==
               b"\xA5" * (fb.RX_CAP - fb.RX_SIZE + fb.GUARD), "Tail guard")
    return values, mismatches, elapsed, hashlib.sha256(output).hexdigest()


def dma_status(dma):
    tx, rx = fb.read32(dma, 0x04), fb.read32(dma, 0x34)
    fb.require(not ((tx | rx) & fb.ERRORS), f"DMA error: MM2S=0x{tx:08X}, S2MM=0x{rx:08X}")
    return tx, rx


def main():
    fb.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    n, k, w, h, trained = fb.load_model()
    print(f"MODEL: m0-trained-cifar-k8 (N={n}, K={k}, {w}x{h})", flush=True)
    images = collect_images(n, w, h)
    print(f"IMAGES: {len(images)}", flush=True)
    OUT.mkdir(parents=True, exist_ok=True)
    zero_channels = [([0] * (n * n), 0, 0, 0) for _ in range(k)]
    custom_channels = [list(cfg) for cfg in CUSTOM] + zero_channels[:k - len(CUSTOM)]
    configs = (("trained", trained), ("custom", custom_channels))
    info = Path("/sys/class/u-dma-buf/udmabuf0")
    phys = int((info / "phys_addr").read_text(), 0)
    size = int((info / "size").read_text(), 0)
    from contextlib import ExitStack
    with ExitStack() as stack:
        dma = stack.enter_context(fb.map_uio(0, 0x40400000))
        accel = stack.enter_context(fb.map_uio(1, 0x43C00000))
        fd = fb.os.open("/dev/udmabuf0", fb.os.O_RDWR | fb.os.O_SYNC)
        stack.callback(fb.os.close, fd)
        initial = {o: fb.read32(accel, o) for o in
                   range(0, 0x4000, 4) if (o & 0xFF) in (0, 4, 8, 0xF8, 0xFC)}
        fb.require(all(v == 0 for v in initial.values()),
                   "Expected zero configuration; reboot for a clean state")
        fb.write32(dma, 0x00, 4)
        fb.wait_for(lambda: not ((fb.read32(dma, 0x00) | fb.read32(dma, 0x30)) & 4),
                    "DMA reset timed out")
        fb.require(fb.read32(dma, 4) == fb.read32(dma, 0x34) == 1, "DMA reset state")
        total_frames = 0
        digests = []
        success = False
        try:
            for name, raw in images:
                padded = pad(raw, n, w, h)
                for tag, channels in configs:
                    expected = fb.make_expected(padded, n, w, h, channels)
                    words = fb.parameter_words(n, channels)
                    for rep in range(FRAMES_PER_CONFIG):
                        values, mismatches, elapsed, digest = run_frame(
                            dma, accel, fd, phys, padded, expected, words)
                        fb.require(mismatches == 0, f"mismatch {name}/{tag}")
                        total_frames += 1
                        if rep == 0:
                            stem = f"{name}_{tag}"
                            (OUT / (stem + ".s16le")).write_bytes(struct.pack(
                                f"<{len(values)}h", *values))
                            digests.append(digest)
                            render_from(values, k, w, h, OUT, stem, tag)
                            print(f"{stem}: OK sha256={digest[:16]} "
                                  f"time={elapsed * 1000:.3f} ms", flush=True)
            print(f"TOTAL FRAMES: {total_frames} (verified bit-exact each)", flush=True)
            print(f"OUTPUTS: {len(list(OUT.iterdir()))} files in {OUT}", flush=True)
            combined = hashlib.sha256("".join(sorted(digests)).encode()).hexdigest()
            print(f"MANIFEST SHA256: {combined}", flush=True)
            success = True
        except BaseException:
            print(f"FAILURE SNAPSHOT: MM2S=0x{fb.read32(dma, 4):08X}, "
                  f"S2MM=0x{fb.read32(dma, 0x34):08X}", flush=True)
            raise
        finally:
            fb.write32(dma, 0x00, 0)
            fb.write32(dma, 0x30, 0)
            fb.wait_for(lambda: bool(fb.read32(dma, 4) & fb.read32(dma, 0x34) & 1),
                        "DMA did not halt")
            for offset in initial:
                fb.write32(accel, offset, 0)
                fb.require(fb.read32(accel, offset) == 0, "Parameter restore failed")
            print("Parameters zeroed.", flush=True)
            if success:
                print("M3 DEMO RUNNER: PASS", flush=True)
            else:
                print("M3 DEMO RUNNER: FAILED - state zeroed, safe to rerun", flush=True)


def render_from(values, k, w, h, out, stem, tag):
    if tag == "trained":
        for ch in range(k):
            render_plane(values, ch, k, w, h, out / f"{stem}_ch{ch}.png")
    else:
        for ch in range(len(CUSTOM)):
            render_plane(values, ch, k, w, h, out / f"{stem}_{CUSTOM_NAMES[ch]}.png")
        render_sobel(values, k, w, h, out / f"{stem}_sobel_mag.png")


if __name__ == "__main__":
    main()
