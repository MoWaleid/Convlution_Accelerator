#!/usr/bin/env python3
"""M6 same-image full reload: 20x A32->A32 through the approved seven-phase
exclusive-owner lifecycle (VALIDATING -> QUIESCING -> DETACHED -> PROGRAMMING
-> REATTACHING -> SELF_TEST -> READY), with identity re-validation, stale-state
proofs and a bit-exact activation frame after every reload."""
import hashlib
import json
import os
import statistics
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m4_filebackend as fb

HW_JSON = Path("/home/petalinux/hardware.json")
FIRMWARE = Path("/lib/firmware/m4_accelerator_dma.bin")
FIRMWARE_NAME = "m4_accelerator_dma.bin"
FPGA_PATH = Path("/sys/class/fpga_manager/fpga0")
RELOADS = 20
EXPECTED_BIN_SHA256 = "b59378e4918f3c128d0d787546981e58b7508085c916780a21fef5db3a04130b"

TX, TX_SIZE = 0x1000, 34 * 34
RX, RX_SIZE, RX_CAP, GUARD = 0x10000, 32 * 32 * 8 * 2, 0x8000, 64


def require(condition, message):
    if not condition:
        raise RuntimeError(message)


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


def read_identity(accel):
    return {
        "magic": fb.read32(accel, fb.REG_MAGIC),
        "abi": fb.read32(accel, fb.REG_ABI_VERSION),
        "caps": fb.read32(accel, fb.REG_CAPABILITIES),
        "build_id": "".join(f"{fb.read32(accel, fb.REG_BUILD_ID_0 + 4 * i):08x}"
                            for i in (3, 2, 1, 0)),
        "image_w": fb.read32(accel, fb.REG_IMAGE_W),
        "image_h": fb.read32(accel, fb.REG_IMAGE_H),
        "kernel_n": fb.read32(accel, fb.REG_KERNEL_N),
        "channel_k": fb.read32(accel, fb.REG_CHANNEL_K),
        "expected_input": fb.read32(accel, fb.REG_EXPECTED_INPUT_BYTES),
        "expected_output": fb.read32(accel, fb.REG_EXPECTED_OUTPUT_BYTES),
        "len_width": fb.read32(accel, fb.REG_DMA_LENGTH_WIDTH),
    }


def validate_identity(identity, hw):
    acc = hw["accelerator"]
    require(identity["magic"] == 0x43564831, "MAGIC mismatch")
    require(identity["abi"] == 0x00010000, "ABI_VERSION mismatch")
    require(identity["caps"] == 0x1FF, "CAPABILITIES mismatch")
    require(identity["build_id"] == acc["build_id_hex"],
            f"BUILD_ID {identity['build_id']} mismatch")
    require((identity["image_w"], identity["image_h"]) == (acc["image_w"], acc["image_h"]),
            "geometry mismatch")
    require((identity["kernel_n"], identity["channel_k"]) == (acc["kernel_n"], acc["channels_k"]),
            "N/K mismatch")
    require((identity["expected_input"], identity["expected_output"]) ==
            (acc["expected_input_bytes"], acc["expected_output_bytes"]), "byte counts mismatch")
    require(identity["len_width"] == acc["dma_length_width"], "DMA_LENGTH_WIDTH mismatch")


def dma_halt(dma):
    fb.write32(dma, 0x00, 0)
    fb.write32(dma, 0x30, 0)
    fb.wait_for(lambda: bool(fb.read32(dma, 4) & fb.read32(dma, 0x34) & 1),
                "DMA did not halt")


def program_pl():
    """PROGRAMMING phase. Caller guarantees DETACHED (no open maps/fds)."""
    require(FIRMWARE.is_file(), "firmware image missing")
    digest = hashlib.sha256(FIRMWARE.read_bytes()).hexdigest()
    require(digest == EXPECTED_BIN_SHA256, "firmware image hash mismatch")
    (FPGA_PATH / "flags").write_text("0")
    (FPGA_PATH / "firmware").write_text(FIRMWARE_NAME)
    deadline = time.monotonic() + 10.0
    while True:
        state = (FPGA_PATH / "state").read_text().strip()
        if state == "operating":
            return
        if time.monotonic() >= deadline:
            raise RuntimeError(f"FPGA programming timed out, state={state}")
        time.sleep(0.01)


def open_handles():
    dma = fb.map_uio(0, 0x40400000)
    accel = fb.map_uio(1, 0x43C00000)
    fd = fb.os.open("/dev/udmabuf0", fb.os.O_RDWR | fb.os.O_SYNC)
    return dma, accel, fd


def close_handles(dma, accel, fd):
    """DETACHED phase: no MMIO/DMA access may survive programming."""
    dma.close()
    accel.close()
    fb.os.close(fd)


def program_config(accel, words):
    for offset, value in words.items():
        fb.write32(accel, offset, value)
        require(fb.read32(accel, offset) == value, "parameter readback failed")
    check_status(accel, fb.STATUS_PARAM_COMPLETE, "PARAM_COMPLETE never set", 1.0)


def run_frame(dma, accel, fd, phys, padded, expected):
    require(os.pwrite(fd, b"\xA5" * (RX_CAP + 2 * GUARD), RX - GUARD) ==
            RX_CAP + 2 * GUARD, "RX guard write failed")
    require(os.pwrite(fd, padded, TX) == len(padded), "TX write failed")
    fb.write32(dma, 0x30, 1)
    fb.wait_for(lambda: not (fb.read32(dma, 0x34) & 1), "S2MM did not start")
    fb.write32(dma, 0x48, phys + RX)
    fb.write32(dma, 0x58, RX_CAP)
    fb.write32(dma, 0x00, 1)
    fb.wait_for(lambda: not (fb.read32(dma, 0x04) & 1), "MM2S did not start")
    fb.write32(dma, 0x18, phys + TX)
    status = fb.read32(accel, fb.REG_STATUS)
    require(status & fb.STATUS_IDLE and status & fb.STATUS_PARAM_COMPLETE,
            f"START precondition lost: 0x{status:08X}")
    fb.write32(accel, fb.REG_COMMAND, fb.CMD_START)
    started = time.perf_counter()
    fb.write32(dma, 0x28, TX_SIZE)
    check_status(accel, fb.STATUS_DONE | fb.STATUS_OUTPUT_DRAINED |
                 fb.STATUS_IDLE | fb.STATUS_QUIESCENT, "frame did not complete")
    elapsed = time.perf_counter() - started
    received = fb.read32(dma, 0x58)
    require(received == RX_SIZE, f"received {received} != {RX_SIZE}")
    for name, addr, want in (("input_accept", fb.REG_INPUT_ACCEPT_BYTES, 1156),
                             ("input_consumed", fb.REG_INPUT_CONSUMED_BYTES, 1156),
                             ("core_accept", fb.REG_CORE_ACCEPT_PIXELS, 1024),
                             ("output_accept", fb.REG_OUTPUT_ACCEPT_BYTES, 16384)):
        got = fb.read32(accel, addr)
        require(got == want, f"counter {name}={got} != {want}")
    output = os.pread(fd, RX_SIZE, RX)
    require(os.pread(fd, GUARD, RX - GUARD) == b"\xA5" * GUARD, "lead guard")
    require(os.pread(fd, RX_CAP - RX_SIZE + GUARD, RX + RX_SIZE) ==
            b"\xA5" * (RX_CAP - RX_SIZE + GUARD), "tail guard")
    values = struct.unpack("<8192h", output)
    mismatches = sum(values[i] != expected[i] for i in range(len(values)))
    return values, mismatches, hashlib.sha256(output).hexdigest(), elapsed


def reload_cycle(index, hw, padded, expected, words, phys):
    """One full A32->A32 cycle through the approved phase machine."""
    # VALIDATING: candidate artifact + current live identity, before disturbance.
    require(FIRMWARE.is_file() and
            hashlib.sha256(FIRMWARE.read_bytes()).hexdigest() == EXPECTED_BIN_SHA256,
            "candidate firmware failed validation")
    # (live identity was validated by the caller on currently-open handles)
    # QUIESCING
    fb.write32(dma_handle[0], 0x00, 0)
    fb.write32(dma_handle[0], 0x30, 0)
    check_status(dma_handle[1], fb.STATUS_IDLE | fb.STATUS_QUIESCENT, "quiescing", 2.0)
    # DETACHED: close every hardware handle so nothing survives programming.
    close_handles(dma_handle[0], dma_handle[1], dma_handle[2])
    # PROGRAMMING
    started = time.monotonic()
    program_pl()
    program_seconds = time.monotonic() - started
    # REATTACHING: brand-new handles; verify identity and prove no stale state.
    dma, accel, fd = open_handles()
    dma_handle[0], dma_handle[1], dma_handle[2] = dma, accel, fd
    validate_identity(read_identity(accel), hw)
    status = fb.read32(accel, fb.REG_STATUS)
    require(status == 0x101, f"stale state survived reload: 0x{status:08X}")
    require(fb.read32(accel, fb.REG_ERROR_FLAGS) == 0, "errors survived reload")
    for addr in (fb.REG_INPUT_ACCEPT_BYTES, fb.REG_INPUT_CONSUMED_BYTES,
                 fb.REG_CORE_ACCEPT_PIXELS, fb.REG_OUTPUT_ACCEPT_BYTES):
        require(fb.read32(accel, addr) == 0, "counters survived reload")
    # SELF_TEST: full requested-model installation + reference-checked frame.
    program_config(accel, words)
    values, mismatches, digest, elapsed = run_frame(dma, accel, fd, phys, padded, expected)
    require(mismatches == 0, f"cycle {index}: {mismatches} mismatches")
    # READY
    print(f"  cycle {index:02d}: program {program_seconds * 1000:.0f} ms, "
          f"frame {elapsed * 1000:.3f} ms, sha={digest[:16]}", flush=True)
    return digest


# Mutable handle slot shared with reload_cycle (handles are recreated per cycle).
dma_handle = [None, None, None]


def main():
    fb.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    repeats = RELOADS
    if len(sys.argv) > 1 and sys.argv[1] == "--sample":
        repeats = 1
    hw = json.loads(HW_JSON.read_text())
    acc = hw["accelerator"]
    n, k, w, h = acc["kernel_n"], acc["channels_k"], acc["image_w"], acc["image_h"]
    require(FIRMWARE.is_file() and
            hashlib.sha256(FIRMWARE.read_bytes()).hexdigest() == EXPECTED_BIN_SHA256,
            "candidate firmware failed validation")
    print(f"PHASE VALIDATING: candidate {FIRMWARE_NAME} sha256 OK", flush=True)
    dma, accel, fd = open_handles()
    dma_handle[0], dma_handle[1], dma_handle[2] = dma, accel, fd
    validate_identity(read_identity(accel), hw)
    print("PHASE VALIDATING: live identity matches hardware.json", flush=True)
    entry = fb.read32(accel, fb.REG_STATUS)
    require(entry & fb.STATUS_QUIESCENT, f"entry not quiescent: 0x{entry:08X}")
    reset_core(accel)

    _m = fb.load_model()
    require(_m[:4] == (n, k, w, h), "library geometry mismatch")
    trained = _m[4]
    cat_padded = fb.load_image(n, w, h)
    trained_expected = fb.make_expected(cat_padded, n, w, h, trained)
    ref_hash = hashlib.sha256(struct.pack("<8192h", *trained_expected)).hexdigest()
    require(ref_hash == fb.REFERENCE_SHA256, "software reference mismatch")
    words = fb.parameter_words(n, trained)
    info = Path("/sys/class/u-dma-buf/udmabuf0")
    phys = int((info / "phys_addr").read_text(), 0)

    print(f"PHASE: {repeats}x same-image A32->A32 full reload", flush=True)
    digests = []
    program_times = []
    for cycle in range(1, repeats + 1):
        digests.append(reload_cycle(cycle, hw, cat_padded, trained_expected,
                                    words, phys))
    require(all(d == ref_hash for d in digests), "some activation frame mismatched")

    print("PHASE READY: final cleanup", flush=True)
    dma_halt(dma_handle[0])
    fb.write32(dma_handle[1], fb.REG_COMMAND, fb.CMD_RESET)
    check_status(dma_handle[1], fb.STATUS_IDLE | fb.STATUS_QUIESCENT, "final RESET", 2.0)
    status = fb.read32(dma_handle[1], fb.REG_STATUS)
    require(status & (fb.STATUS_PARAM_COMPLETE), f"final state 0x{status:08X}")
    print(f"SUMMARY: {repeats} full-PL reloads, {repeats} activation frames "
          f"bit-exact (sha {ref_hash[:16]})", flush=True)
    print("M6 SAME-IMAGE RELOAD: PASS", flush=True)


def reset_core(accel):
    fb.write32(accel, fb.REG_COMMAND, fb.CMD_RESET)
    check_status(accel, fb.STATUS_IDLE | fb.STATUS_QUIESCENT, "RESET recovery", 2.0)
    status = fb.read32(accel, fb.REG_STATUS)
    require(not (status & (fb.STATUS_ERROR | fb.STATUS_FAULT | fb.STATUS_BUSY)),
            f"post-RESET state 0x{status:08X}")


if __name__ == "__main__":
    main()
