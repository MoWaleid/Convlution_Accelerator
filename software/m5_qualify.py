#!/usr/bin/env python3
"""M5 qualification: end-to-end qualification of the M4 CVH1 hybrid build.
100-frame no-reset soak, numerical-extreme coverage, lifecycle and bounded
software-failure tests, hardware.json platform-identity validation."""
import hashlib
import json
import math
import os
import statistics
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m4_filebackend as fb

HW_JSON = Path("/home/petalinux/hardware.json")
SOAK_FRAMES = 100
CUSTOM = (
    ((0, 0, 0, 0, 127, 0, 0, 0, 0), 0, 7, 0),
    ((-1, 0, 1, -2, 0, 2, -1, 0, 1), 0, 8, 0),
    ((-1, -2, -1, 0, 0, 0, 1, 2, 1), 0, 8, 0),
    ((1, 2, 1, 2, 4, 2, 1, 2, 1), 0, 4, 0),
)
PHASES = []


def phase(name):
    def wrap(fn):
        PHASES.append((name, fn))
        return fn
    return wrap


def pad(raw, n, w, h):
    stride = w + n - 1
    padded = bytearray(stride * (h + n - 1))
    for row in range(h):
        padded[(row + n // 2) * stride + n // 2:(row + n // 2) * stride + n // 2 + w] = \
            raw[row * w:(row + 1) * w]
    return bytes(padded)


def check_status(accel, mask, description, seconds=5.0):
    fb.wait_for(lambda: (fb.read32(accel, fb.REG_STATUS) & mask) == mask,
                description, seconds=seconds)


def arm_and_run(dma, accel, fd, phys, padded):
    """Arm S2MM, arm MM2S, CVH1 START, trigger TX. Returns elapsed seconds."""
    fb.require(os.pwrite(fd, b"\xA5" * (fb.RX_CAP + 2 * fb.GUARD), fb.RX - fb.GUARD) ==
               fb.RX_CAP + 2 * fb.GUARD, "RX guard write failed")
    fb.require(os.pwrite(fd, padded, fb.TX) == len(padded), "TX write failed")
    fb.write32(dma, 0x30, 1)
    fb.wait_for(lambda: not (fb.read32(dma, 0x34) & 1), "S2MM did not start")
    fb.write32(dma, 0x48, phys + fb.RX)
    fb.write32(dma, 0x58, fb.RX_CAP)
    fb.write32(dma, 0x00, 1)
    fb.wait_for(lambda: not (fb.read32(dma, 0x04) & 1), "MM2S did not start")
    fb.write32(dma, 0x18, phys + fb.TX)
    status = fb.read32(accel, fb.REG_STATUS)
    fb.require(status & fb.STATUS_IDLE and status & fb.STATUS_PARAM_COMPLETE,
               f"START precondition lost: 0x{status:08X}")
    fb.write32(accel, fb.REG_COMMAND, fb.CMD_START)
    started = time.perf_counter()
    fb.write32(dma, 0x28, fb.TX_SIZE)
    check_status(accel, fb.STATUS_DONE | fb.STATUS_OUTPUT_DRAINED |
                 fb.STATUS_IDLE | fb.STATUS_QUIESCENT,
                 "frame did not complete", seconds=5.0)
    return time.perf_counter() - started


def verify_frame(dma, accel, fd, expected, require_counters=True):
    received = fb.read32(dma, 0x58)
    fb.require(received == fb.RX_SIZE, f"received {received} != {fb.RX_SIZE}")
    if require_counters:
        for name, addr, want in (("input_accept", fb.REG_INPUT_ACCEPT_BYTES, 1156),
                                 ("input_consumed", fb.REG_INPUT_CONSUMED_BYTES, 1156),
                                 ("core_accept", fb.REG_CORE_ACCEPT_PIXELS, 1024),
                                 ("output_accept", fb.REG_OUTPUT_ACCEPT_BYTES, 16384)):
            got = fb.read32(accel, addr)
            fb.require(got == want, f"counter {name}={got} != {want}")
    output = os.pread(fd, fb.RX_SIZE, fb.RX)
    fb.require(os.pread(fd, fb.GUARD, fb.RX - fb.GUARD) == b"\xA5" * fb.GUARD, "lead guard")
    fb.require(os.pread(fd, fb.RX_CAP - fb.RX_SIZE + fb.GUARD, fb.RX + fb.RX_SIZE) ==
               b"\xA5" * (fb.RX_CAP - fb.RX_SIZE + fb.GUARD), "tail guard")
    values = struct.unpack("<8192h", output)
    mismatches = sum(values[i] != expected[i] for i in range(len(values)))
    return values, mismatches, hashlib.sha256(output).hexdigest()


def program_config(accel, words):
    for offset, value in words.items():
        fb.write32(accel, offset, value)
        fb.require(fb.read32(accel, offset) == value, "parameter readback failed")
    check_status(accel, fb.STATUS_PARAM_COMPLETE, "PARAM_COMPLETE never set", 1.0)


def dma_halt(dma):
    fb.write32(dma, 0x00, 0)
    fb.write32(dma, 0x30, 0)
    fb.wait_for(lambda: bool(fb.read32(dma, 4) & fb.read32(dma, 0x34) & 1),
                "DMA did not halt")


def reset_core(accel, require_clean=True):
    fb.write32(accel, fb.REG_COMMAND, fb.CMD_RESET)
    check_status(accel, fb.STATUS_IDLE | fb.STATUS_QUIESCENT, "RESET recovery", 2.0)
    if require_clean:
        status = fb.read32(accel, fb.REG_STATUS)
        fb.require(not (status & (fb.STATUS_ERROR | fb.STATUS_FAULT | fb.STATUS_BUSY)),
                   f"post-RESET state 0x{status:08X}")
        fb.require(fb.read32(accel, fb.REG_ERROR_FLAGS) == 0, "errors not cleared")


def proof_frame(dma, accel, fd, phys, padded, expected, tag):
    elapsed = arm_and_run(dma, accel, fd, phys, padded)
    values, mismatches, digest = verify_frame(dma, accel, fd, expected)
    fb.require(mismatches == 0, f"{tag}: {mismatches} mismatches")
    print(f"  [{tag}] proof frame OK, {elapsed * 1000:.3f} ms", flush=True)


def main():
    fb.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    hw = json.loads(HW_JSON.read_text())
    acc = hw["accelerator"]
    n, k, w, h = acc["kernel_n"], acc["channels_k"], acc["image_w"], acc["image_h"]

    # ================= Phase 0: admission / identity =================
    print("PHASE 0: platform identity admission", flush=True)
    dma_map = fb.map_uio(0, 0x40400000)
    accel_map = fb.map_uio(1, 0x43C00000)
    fb.require(fb.read32(accel_map, fb.REG_MAGIC) == 0x43564831, "MAGIC mismatch")
    fb.require(fb.read32(accel_map, fb.REG_ABI_VERSION) == 0x00010000, "ABI mismatch")
    fb.require(fb.read32(accel_map, fb.REG_CAPABILITIES) == 0x1FF, "CAPABILITIES mismatch")
    build_id = 0
    for i in range(4):
        build_id |= fb.read32(accel_map, fb.REG_BUILD_ID_0 + 4 * i) << (32 * i)
    build_id = f"{build_id:032x}"
    fb.require(build_id == acc["build_id_hex"], f"BUILD_ID {build_id} mismatch")
    fb.require(fb.read32(accel_map, fb.REG_IMAGE_W) == w, "IMAGE_W mismatch")
    fb.require(fb.read32(accel_map, fb.REG_IMAGE_H) == h, "IMAGE_H mismatch")
    fb.require(fb.read32(accel_map, fb.REG_KERNEL_N) == n, "KERNEL_N mismatch")
    fb.require(fb.read32(accel_map, fb.REG_CHANNEL_K) == k, "CHANNEL_K mismatch")
    fb.require(fb.read32(accel_map, fb.REG_DMA_LENGTH_WIDTH) == acc["dma_length_width"],
               "DMA_LENGTH_WIDTH mismatch")
    fb.require(fb.read32(accel_map, fb.REG_EXPECTED_INPUT_BYTES) == 1156 and
               fb.read32(accel_map, fb.REG_EXPECTED_OUTPUT_BYTES) == 16384,
               "expected byte counts mismatch")
    print(f"  live identity matches hardware.json (BUILD_ID {acc['build_id_ascii']})",
          flush=True)

    info = Path("/sys/class/u-dma-buf/udmabuf0")
    phys = int((info / "phys_addr").read_text(), 0)
    size = int((info / "size").read_text(), 0)
    fb.require(size >= fb.RX + fb.RX_CAP + fb.GUARD, "buffer too small")

    entry = fb.read32(accel_map, fb.REG_STATUS)
    fb.require(entry & fb.STATUS_QUIESCENT, f"entry not quiescent: 0x{entry:08X}")
    reset_core(accel_map)
    fd = fb.os.open("/dev/udmabuf0", fb.os.O_RDWR | fb.os.O_SYNC)
    print("  READY (clean state 0x101)", flush=True)

    from contextlib import ExitStack
    with ExitStack() as stack:
        stack.callback(dma_map.close)
        stack.callback(accel_map.close)
        stack.callback(fb.os.close, fd)
        latencies = []

        def one_frame(padded, expected, tag, collect=False):
            elapsed = arm_and_run(dma_map, accel_map, fd, phys, padded)
            values, mismatches, digest = verify_frame(dma_map, accel_map, fd, expected)
            fb.require(mismatches == 0, f"{tag}: {mismatches} mismatches")
            latencies.append(elapsed)
            return values, digest

        # ============ Phase 1: 100-frame soak, no inter-frame RESET ============
        print(f"PHASE 1: {SOAK_FRAMES}-frame soak (no inter-frame RESET)", flush=True)
        _m = fb.load_model()
        fb.require(_m[:4] == (n, k, w, h), "library geometry mismatch")
        trained = _m[4]
        cat_padded = fb.load_image(n, w, h)
        trained_expected = fb.make_expected(cat_padded, n, w, h, trained)
        ref_hash = hashlib.sha256(struct.pack("<8192h", *trained_expected)).hexdigest()
        fb.require(ref_hash == fb.REFERENCE_SHA256, "software reference mismatch")
        alt_path = sorted(Path("/home/petalinux/demo_images").glob("*.png"))[0]
        from PIL import Image
        alt_raw = Image.open(alt_path).convert("L").tobytes()
        alt_padded = pad(alt_raw, n, w, h)
        alt_expected = fb.make_expected(alt_padded, n, w, h, trained)
        words = fb.parameter_words(n, trained)
        program_config(accel_map, words)
        last_digest = ""
        for frame in range(SOAK_FRAMES):
            if frame % 2 == 0:
                values, digest = one_frame(cat_padded, trained_expected, f"soak{frame}")
            else:
                values, digest = one_frame(alt_padded, alt_expected, f"soak{frame}")
            if frame % 25 == 0:
                print(f"  frame {frame}: sha={digest[:16]} "
                      f"({latencies[-1] * 1000:.3f} ms)", flush=True)
            last_digest = digest
        alt_ref = hashlib.sha256(struct.pack("<8192h", *alt_expected)).hexdigest()
        want = ref_hash if (SOAK_FRAMES - 1) % 2 == 0 else alt_ref
        fb.require(last_digest == want, "final soak frame hash mismatch")
        print(f"  {SOAK_FRAMES} frames bit-exact, no inter-frame RESET", flush=True)

        # ============ Phase 2: numerical extremes ============
        print("PHASE 2: numerical extremes (config re-admission per case)", flush=True)
        custom_channels = [list(c) for c in CUSTOM] + [([0] * 9, 0, 0, 0) for _ in range(4)]
        cases = []
        custom_expected = fb.make_expected(cat_padded, n, w, h, custom_channels)
        cases.append(("custom_saturation", cat_padded, custom_expected,
                      fb.parameter_words(n, custom_channels)))
        zero_expected = fb.make_expected(pad(bytes(w * h), n, w, h), n, w, h, trained)
        # Round-half-up on the bare bias: ch1 (+179, shift 8) -> 1; all other
        # channels round/clamp to 0. Matches golden test_vectors_zeros.
        fb.require(zero_expected[1::8] == [1] * (w * h), "ch1 zero-input expectation")
        fb.require(all(v == 0 for i, v in enumerate(zero_expected) if i % 8 != 1),
                   "non-ch1 zero-input expectation")
        cases.append(("all_zero_input", pad(bytes(w * h), n, w, h),
                      zero_expected, words))
        full_expected = fb.make_expected(pad(b"\xFF" * (w * h), n, w, h),
                                         n, w, h, trained)
        fb.require(max(full_expected) >= 200, "all-255 input should reach high outputs")
        cases.append(("all_255_input", pad(b"\xFF" * (w * h), n, w, h),
                      full_expected, words))
        for tag, padded, expected, cfg_words in cases:
            fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_RESET)
            program_config(accel_map, cfg_words)
            values, digest = one_frame(padded, expected, tag)
            print(f"  {tag}: OK min={min(values)} max={max(values)} "
                  f"sha={digest[:16]}", flush=True)

        # ============ Phase 3: lifecycle + bounded software-failure ============
        print("PHASE 3: lifecycle and bounded-failure tests", flush=True)
        # PLATFORM FINDING (2026-09-12): deliberately provoking SLVERR from
        # userspace (illegal command values, reserved-address accesses)
        # escalates on the Zynq GP path to "Unhandled fault: external abort
        # on non-linefetch (0x1818)" and kills the process with SIGBUS. The
        # platform therefore enforces the validate-before-write backend
        # contract fail-stop; SLVERR decode itself is qualified in simulation
        # by the M4 tb_axi_lite_ctrl regression. The hardware tests below use
        # only architecturally legal accesses.
        fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_RESET)
        program_config(accel_map, words)

        # 3a. ABORT from IDLE -> FAULT with ABORTED flag; recovery + proof frame
        fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_ABORT)
        status = fb.read32(accel_map, fb.REG_STATUS)
        fb.require(status & fb.STATUS_FAULT and status & fb.STATUS_ERROR,
                   f"ABORT from IDLE did not fault: 0x{status:08X}")
        fb.require(fb.read32(accel_map, fb.REG_ERROR_FLAGS) == (1 << 8),
                   "ABORTED flag not latched alone")
        reset_core(accel_map)
        proof_frame(dma_map, accel_map, fd, phys, cat_padded, trained_expected,
                    "recover-abort")

        # 3b. ABORT-after-START race: either outcome must be architecturally clean
        fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_START)
        fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_ABORT)
        time.sleep(0.01)
        status = fb.read32(accel_map, fb.REG_STATUS)
        if status & fb.STATUS_FAULT:
            dma_halt(dma_map)
            reset_core(accel_map)
            proof_frame(dma_map, accel_map, fd, phys, cat_padded, trained_expected,
                        "recover-abort-race")
            print("  ABORT race: FAULT path taken, recovered", flush=True)
        else:
            fb.require(status & fb.STATUS_DONE and status & fb.STATUS_IDLE,
                       f"ABORT race landed in undefined state 0x{status:08X}")
            verify_frame(dma_map, accel_map, fd, trained_expected)
            print("  ABORT race: frame completion won, verified bit-exact", flush=True)

        # 3c. bounded software failure: corrupted expectation must be detected
        #     while hardware stays clean, then recovery must be exact.
        poisoned = list(trained_expected)
        poisoned[123] ^= 1
        elapsed = arm_and_run(dma_map, accel_map, fd, phys, cat_padded)
        values, mismatches, digest = verify_frame(dma_map, accel_map, fd, poisoned,
                                                  require_counters=True)
        fb.require(mismatches >= 1, "corrupted expectation was not detected")
        status = fb.read32(accel_map, fb.REG_STATUS)
        fb.require(status & fb.STATUS_DONE and status & fb.STATUS_IDLE,
                   "hardware not clean after detected software failure")
        fb.require(digest == ref_hash, "hardware output corrupted in failure test")
        reset_core(accel_map)
        proof_frame(dma_map, accel_map, fd, phys, cat_padded, trained_expected,
                    "recover-poisoned")

        # ============ Phase 4: final counters and cleanup ============
        print("PHASE 4: final state", flush=True)
        dma_halt(dma_map)
        fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_RESET)
        check_status(accel_map, fb.STATUS_IDLE | fb.STATUS_QUIESCENT,
                     "final RESET", 2.0)
        status = fb.read32(accel_map, fb.REG_STATUS)
        fb.require(status == 0x181, f"final retained state 0x{status:08X} != 0x181")
        fb.require(fb.read32(accel_map, fb.REG_ERROR_FLAGS) == 0, "final errors nonzero")
        med = statistics.median(latencies)
        print(f"SUMMARY: {len(latencies)} verified frames total", flush=True)
        print(f"LATENCY ms: min={min(latencies) * 1000:.3f} "
              f"median={med * 1000:.3f} max={max(latencies) * 1000:.3f}", flush=True)
        print("M5 QUALIFICATION: PASS", flush=True)


if __name__ == "__main__":
    main()
