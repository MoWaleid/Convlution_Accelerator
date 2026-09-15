#!/usr/bin/env python3
"""G5 bounded-recovery check: hardware fault injection with clean recovery.

Register-level only (no DMA frames): provokes the two architecturally legal
hardware fault paths qualified by M5 against the live CVH1 accelerator, then
requires clean RESET recovery. The recovery proof frame is run afterwards by
the qualified m8_cli path, which re-admits parameters and verifies the
golden anchor end-to-end.

Usage (from /home/petalinux, sudo):
    python3 g5_fault_check.py A32_CFGLUT125

Fault mechanics are release-agnostic (shared CVH1 control ABI); the identity
binding is taken from the named release's admitted runtime manifest.
"""
import json
import mmap
import os
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m4_filebackend as fb

RELEASE = sys.argv[1] if len(sys.argv) > 1 else "A32_CFGLUT125"
MANIFEST = Path(f"/home/petalinux/profiles/hardware_{RELEASE}.json")


def check_status(accel, expected, what, seconds):
    # Bits-set semantics: PARAM_COMPLETE is retained across RESET on real
    # silicon (0x181 after any parameter programming; 0x101 only factory
    # fresh after full-PL reload).
    fb.wait_for(lambda: (fb.read32(accel, fb.REG_STATUS) & expected) == expected,
                f"{what}: STATUS 0x{fb.read32(accel, fb.REG_STATUS):08X} "
                f"lacks 0x{expected:08X}", seconds)
    status = fb.read32(accel, fb.REG_STATUS)
    fb.require((status & expected) == expected, f"{what} failed: 0x{status:08X}")


def reset_core(accel):
    fb.write32(accel, fb.REG_COMMAND, fb.CMD_RESET)
    check_status(accel, fb.STATUS_IDLE | fb.STATUS_QUIESCENT,
                 "RESET recovery", 2.0)
    status = fb.read32(accel, fb.REG_STATUS)
    fb.require(not (status & (fb.STATUS_ERROR | fb.STATUS_FAULT |
                              fb.STATUS_BUSY)),
               f"post-RESET state not clean: 0x{status:08X}")


def main():
    manifest = json.loads(MANIFEST.read_text())
    acc = manifest["accelerator"]
    print(f"G5 FAULT CHECK: target {RELEASE} "
          f"({acc['build_id_ascii']})", flush=True)

    dma_map = fb.map_uio(0, 0x40400000)
    accel_map = fb.map_uio(1, 0x43C00000)

    # Identity binding: the live PL must be the named release.
    build_id = 0
    for i in range(4):
        build_id |= fb.read32(accel_map, fb.REG_BUILD_ID_0 + 4 * i) << (32 * i)
    fb.require(f"{build_id:032x}" == acc["build_id_hex"],
               f"live BUILD_ID {build_id:032x} != {acc['build_id_hex']} "
               "- switch to the target release first")
    print("  live identity matches manifest", flush=True)

    # Ensure DMA is halted and core is quiescent before fault injection.
    fb.write32(dma_map, 0x00, 0)
    fb.write32(dma_map, 0x30, 0)
    fb.wait_for(lambda: bool(fb.read32(dma_map, 4) & fb.read32(dma_map, 0x34) & 1),
                "DMA did not halt")
    fb.require(not (fb.read32(accel_map, fb.REG_STATUS) & fb.STATUS_BUSY),
               "accelerator BUSY at entry - run this on an idle release")

    # --- 1. ABORT from IDLE -> FAULT with ABORTED flag latched alone -------
    fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_ABORT)
    status = fb.read32(accel_map, fb.REG_STATUS)
    fb.require(status & fb.STATUS_FAULT and status & fb.STATUS_ERROR,
               f"ABORT from IDLE did not fault: 0x{status:08X}")
    fb.require(fb.read32(accel_map, fb.REG_ERROR_FLAGS) == (1 << 8),
               "ABORTED flag not latched alone")
    print("  ABORT-from-IDLE: FAULT latched, ABORTED alone in ERROR_FLAGS",
          flush=True)
    reset_core(accel_map)
    print("  recovered to clean quiescent state", flush=True)

    # --- 2. ABORT-after-START race: either outcome is architecturally clean
    fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_START)
    fb.write32(accel_map, fb.REG_COMMAND, fb.CMD_ABORT)
    time.sleep(0.01)
    status = fb.read32(accel_map, fb.REG_STATUS)
    if status & fb.STATUS_FAULT:
        fb.require(fb.read32(accel_map, fb.REG_ERROR_FLAGS) == (1 << 8),
                   "race FAULT without ABORTED flag")
        reset_core(accel_map)
        print("  ABORT race: FAULT path taken, recovered", flush=True)
    else:
        fb.require(status & fb.STATUS_DONE and status & fb.STATUS_IDLE,
                   f"ABORT race landed in undefined state 0x{status:08X}")
        print("  ABORT race: completion won, core DONE+IDLE", flush=True)
        reset_core(accel_map)

    # --- final state: clean idle, retained parameters (0x181 expected; the
    # m8_cli recovery proof frame re-validates the anchor end-to-end) ---------
    check_status(accel_map, fb.STATUS_IDLE | fb.STATUS_QUIESCENT,
                 "final state", 2.0)
    status = fb.read32(accel_map, fb.REG_STATUS)
    fb.require(not (status & (fb.STATUS_ERROR | fb.STATUS_FAULT |
                              fb.STATUS_BUSY)),
               f"final state not clean: 0x{status:08X}")
    print(f"G5 FAULT CHECK: PASS ({RELEASE} fault paths + recovery clean; "
          "run m8_cli run --profile "
          f"{RELEASE} --frames 1 now for the recovery proof frame)", flush=True)


if __name__ == "__main__":
    main()
