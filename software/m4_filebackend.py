#!/usr/bin/env python3
"""M4 file-driven inference: model and dataset loaded from the installed
conv-lab library; CVH1 control/status ABI with bit-exact DMA verification."""
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
DMA_ERRORS = 0x4770

# M4 / CVH1 accelerator register map
REG_MAGIC                 = 0x4100
REG_ABI_VERSION           = 0x4104
REG_CAPABILITIES          = 0x4108
REG_STATUS                = 0x410C
REG_COMMAND               = 0x4110
REG_EVENT_CLEAR           = 0x4114
REG_ERROR_FLAGS           = 0x4118

REG_IMAGE_W               = 0x4120
REG_IMAGE_H               = 0x4124
REG_KERNEL_N              = 0x4128
REG_CHANNEL_K             = 0x412C
REG_WIDTHS_0              = 0x4130
REG_WIDTHS_1              = 0x4134
REG_EXPECTED_INPUT_BYTES  = 0x4138
REG_EXPECTED_OUTPUT_BYTES = 0x413C

REG_INPUT_ACCEPT_BYTES    = 0x4140
REG_INPUT_CONSUMED_BYTES  = 0x4144
REG_CORE_ACCEPT_PIXELS    = 0x4148
REG_OUTPUT_ACCEPT_BYTES   = 0x414C

REG_BUILD_ID_0            = 0x4150
REG_BUILD_ID_1            = 0x4154
REG_BUILD_ID_2            = 0x4158
REG_BUILD_ID_3            = 0x415C
REG_DMA_LENGTH_WIDTH      = 0x4160

CMD_START = 0x1
CMD_RESET = 0x2
CMD_ABORT = 0x4

STATUS_IDLE           = 1 << 0
STATUS_BUSY           = 1 << 1
STATUS_CORE_COMPLETE  = 1 << 2
STATUS_OUTPUT_DRAINED = 1 << 3
STATUS_DONE           = 1 << 4
STATUS_ERROR          = 1 << 5
STATUS_FAULT          = 1 << 6
STATUS_PARAM_COMPLETE = 1 << 7
STATUS_QUIESCENT      = 1 << 8

EXPECTED_MAGIC        = 0x43564831
EXPECTED_ABI_VERSION  = 0x00010000
EXPECTED_CAPABILITIES = 0x000001FF
EXPECTED_DMA_WIDTH    = 22
EXPECTED_BUILD_ID     = "4d344e334b385733322d323630393131"
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


def run_transfer(dma, accel, fd, phys, size, padded, expected, words, positions, n, k, w, h):
    require(phys % 8 == 0 and 0 <= phys < phys + size <= 0x20000000,
            "DMA allocation is unaligned or outside the HP0 DDR range")
    require(TX + TX_SIZE < RX - GUARD and RX + RX_CAP + GUARD <= size,
            "DMA buffer regions do not fit")
    initial = (read32(dma, 0x04), read32(dma, 0x34))
    require(all((status & 1) and not (status & (DMA_ERRORS | 8)) for status in initial),
            f"DMA must already be halted, error-free, and in simple mode: {initial}")
    require(read32(accel, REG_MAGIC) == EXPECTED_MAGIC,
        "Unexpected accelerator ABI magic")
    require(read32(accel, REG_ABI_VERSION) == EXPECTED_ABI_VERSION,
        "Unexpected accelerator ABI version")
    require(read32(accel, REG_CAPABILITIES) == EXPECTED_CAPABILITIES,
        "Unexpected accelerator capabilities")
    require(read32(accel, REG_DMA_LENGTH_WIDTH) == EXPECTED_DMA_WIDTH,
        "Unexpected accelerator DMA length width")

    build_id = (
        (read32(accel, REG_BUILD_ID_3) << 96) |
        (read32(accel, REG_BUILD_ID_2) << 64) |
        (read32(accel, REG_BUILD_ID_1) << 32) |
        read32(accel, REG_BUILD_ID_0)
    )
    build_id_hex = f"{build_id:032x}"
    require(build_id_hex == EXPECTED_BUILD_ID,
            f"Unexpected accelerator BUILD_ID: {build_id_hex}")
    print(f"BUILD_ID: {build_id_hex}", flush=True)

    expected_input_bytes = (w + n - 1) * (h + n - 1)
    expected_output_bytes = 2 * w * h * k
    expected_widths_0 = 0x10180808
    expected_widths_1 = {3: 0x00001915, 5: 0x00001916}.get(n)

    require(expected_widths_1 is not None,
            f"Unsupported kernel width discovery expectation for N={n}")
    require(positions == w * h, "Internal output-position count mismatch")
    require(len(padded) == expected_input_bytes == TX_SIZE,
            "Software input-size assumptions do not match model geometry")
    require(expected_output_bytes == RX_SIZE,
            "Software output-size assumptions do not match model geometry")

    require(read32(accel, REG_IMAGE_W) == w,
            "Hardware IMAGE_W does not match selected model")
    require(read32(accel, REG_IMAGE_H) == h,
            "Hardware IMAGE_H does not match selected model")
    require(read32(accel, REG_KERNEL_N) == n,
            "Hardware KERNEL_N does not match selected model")
    require(read32(accel, REG_CHANNEL_K) == k,
            "Hardware CHANNEL_K does not match selected model")
    require(read32(accel, REG_WIDTHS_0) == expected_widths_0,
            "Unexpected hardware WIDTHS_0")
    require(read32(accel, REG_WIDTHS_1) == expected_widths_1,
            "Unexpected hardware WIDTHS_1")
    require(read32(accel, REG_EXPECTED_INPUT_BYTES) == expected_input_bytes,
            "Hardware EXPECTED_INPUT_BYTES does not match selected model")
    require(read32(accel, REG_EXPECTED_OUTPUT_BYTES) == expected_output_bytes,
            "Hardware EXPECTED_OUTPUT_BYTES does not match selected model")

    print(f"DISCOVERY: W={w} H={h} N={n} K={k} "
          f"input={expected_input_bytes} output={expected_output_bytes} "
          f"widths0=0x{expected_widths_0:08x} "
          f"widths1=0x{expected_widths_1:08x}", flush=True)

    status = read32(accel, REG_STATUS)
    require(status & STATUS_IDLE,
            f"Accelerator not idle at startup: STATUS=0x{status:08X}")
    require(status & STATUS_QUIESCENT,
            f"Accelerator not quiescent at startup: STATUS=0x{status:08X}")
    require(not (status & (STATUS_BUSY | STATUS_ERROR | STATUS_FAULT)),
            f"Accelerator in bad startup state: STATUS=0x{status:08X}")
    require(read32(accel, REG_ERROR_FLAGS) == 0,
            "Accelerator error flags set at startup")

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
        require(not ((tx | rx) & DMA_ERRORS),
                f"DMA error: MM2S=0x{tx:08X}, S2MM=0x{rx:08X}")
        return tx, rx

    success = False
    try:
        write32(dma, 0x00, 4)
        wait_for(lambda: not ((read32(dma, 0x00) | read32(dma, 0x30)) & 4),
                 "DMA reset timed out")
        require(read32(dma, 4) == read32(dma, 0x34) == 1,
                "Unexpected DMA reset state")

        # Reset runtime state before parameter programming.
        write32(accel, REG_COMMAND, CMD_RESET)
        wait_for(
            lambda: read32(accel, REG_STATUS) in (
                STATUS_IDLE | STATUS_QUIESCENT,
                STATUS_IDLE | STATUS_PARAM_COMPLETE | STATUS_QUIESCENT),
            "Accelerator reset timed out")
        require(read32(accel, REG_ERROR_FLAGS) == 0,
                "Accelerator reported an error after reset")

        for offset, value in words.items():
            write32(accel, offset, value)
            require(read32(accel, offset) == value,
                    f"Parameter readback failed at +0x{offset:04X}")

        status = read32(accel, REG_STATUS)
        require(status & STATUS_PARAM_COMPLETE,
                f"Parameter set incomplete: STATUS=0x{status:08X}")
        print("ALL PARAMETER WORDS VERIFIED; PARAM_COMPLETE=1", flush=True)

        for frame in range(FRAMES):
            put(RX - GUARD, b"\xA5" * (RX_CAP + 2 * GUARD))

            status = read32(accel, REG_STATUS)
            require(status & STATUS_IDLE,
                    f"Accelerator not idle before frame {frame + 1}: 0x{status:08X}")
            require(status & STATUS_QUIESCENT,
                    f"Accelerator not quiescent before frame {frame + 1}: 0x{status:08X}")
            require(status & STATUS_PARAM_COMPLETE,
                    f"Parameters incomplete before frame {frame + 1}: 0x{status:08X}")
            require(not (status & (STATUS_ERROR | STATUS_FAULT)),
                    f"Accelerator fault before frame {frame + 1}: 0x{status:08X}")
            require(read32(accel, REG_ERROR_FLAGS) == 0,
                    "Accelerator error flags set before START")

            # Arm receive path before allowing the accelerator to produce output.
            write32(dma, 0x30, 1)
            wait_for(lambda: not (statuses()[1] & 1), "S2MM did not start")
            write32(dma, 0x48, phys + RX)
            require(read32(dma, 0x48) == phys + RX,
                    "RX address readback failed")
            write32(dma, 0x58, RX_CAP)

            # Prepare MM2S, but do not release input until the accelerator is BUSY.
            write32(dma, 0x00, 1)
            wait_for(lambda: not (statuses()[0] & 1), "MM2S did not start")
            write32(dma, 0x18, phys + TX)

            started = time.perf_counter()
            write32(accel, REG_COMMAND, CMD_START)
            wait_for(lambda: bool(read32(accel, REG_STATUS) & STATUS_BUSY),
                     "Accelerator did not enter BUSY state")

            write32(dma, 0x28, TX_SIZE)

            wait_for(lambda: all((s & 0x1003) == 0x1002 for s in statuses()),
                     "DMA completion timed out", seconds=5.0)

            wait_for(
                lambda: (read32(accel, REG_STATUS) &
                         (STATUS_DONE | STATUS_OUTPUT_DRAINED | STATUS_QUIESCENT)) ==
                        (STATUS_DONE | STATUS_OUTPUT_DRAINED | STATUS_QUIESCENT),
                "Accelerator completion timed out", seconds=5.0)

            elapsed = time.perf_counter() - started
            received = read32(dma, 0x58)
            require(received == RX_SIZE, "Incorrect received packet length")

            status = read32(accel, REG_STATUS)
            require(status & STATUS_IDLE,
                    f"Accelerator remained busy: STATUS=0x{status:08X}")
            require(status & STATUS_CORE_COMPLETE,
                    f"CORE_COMPLETE missing: STATUS=0x{status:08X}")
            require(not (status & (STATUS_BUSY | STATUS_ERROR | STATUS_FAULT)),
                    f"Accelerator ended in bad state: STATUS=0x{status:08X}")
            require(read32(accel, REG_ERROR_FLAGS) == 0,
                    "Accelerator reported an error during frame")

            input_accept = read32(accel, REG_INPUT_ACCEPT_BYTES)
            input_consumed = read32(accel, REG_INPUT_CONSUMED_BYTES)
            core_accept = read32(accel, REG_CORE_ACCEPT_PIXELS)
            output_accept = read32(accel, REG_OUTPUT_ACCEPT_BYTES)

            require(input_accept == TX_SIZE,
                    f"INPUT_ACCEPT_BYTES={input_accept}, expected {TX_SIZE}")
            require(input_consumed == TX_SIZE,
                    f"INPUT_CONSUMED_BYTES={input_consumed}, expected {TX_SIZE}")
            require(core_accept == positions,
                    f"CORE_ACCEPT_PIXELS={core_accept}, expected {positions}")
            require(output_accept == RX_SIZE,
                    f"OUTPUT_ACCEPT_BYTES={output_accept}, expected {RX_SIZE}")

            print(f"CVH1 COUNTERS: input_accept={input_accept} "
                  f"input_consumed={input_consumed} core_accept={core_accept} "
                  f"output_accept={output_accept}", flush=True)
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
              f"STATUS=0x{read32(accel, REG_STATUS):08X}, "
              f"ERROR_FLAGS=0x{read32(accel, REG_ERROR_FLAGS):08X}",
              flush=True)
        raise
    finally:
        write32(dma, 0x00, 0)
        write32(dma, 0x30, 0)
        wait_for(lambda: bool(read32(dma, 4) & read32(dma, 0x34) & 1),
                 "DMA did not halt: reboot before another test")
        print("DMA channels halted.", flush=True)
        if success:
            write32(accel, REG_COMMAND, CMD_RESET)
            wait_for(
                lambda: read32(accel, REG_STATUS) ==
                        (STATUS_IDLE | STATUS_PARAM_COMPLETE | STATUS_QUIESCENT),
                "Accelerator cleanup reset timed out")
            require(read32(accel, REG_ERROR_FLAGS) == 0,
                    "Accelerator error flags remained after cleanup reset")
            print("Accelerator reset to clean state. M4 FILE-DRIVEN INFERENCE: PASS",
                  flush=True)
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
                     parameter_words(n, channels), w * h, n, k, w, h)


if __name__ == "__main__":
    main()


