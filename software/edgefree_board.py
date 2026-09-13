"""Validate an already-booted EdgeFree release. Never programs PL or PS clocks."""
import argparse
import hashlib
import json
import platform
from pathlib import Path

# Bind the packaged backend before m7 adds its historical /home/petalinux path.
import m4_filebackend
import m7_switch as driver


def verify_package(package):
    package = package.resolve()
    for line in (package / 'SHA256SUMS.txt').read_text().splitlines():
        digest, relative = line.split('  ', 1)
        path = (package / relative).resolve()
        if package not in path.parents or not path.is_file():
            raise RuntimeError(f'Invalid package entry: {relative}')
        if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
            raise RuntimeError(f'Package hash mismatch: {relative}')
    hw = json.loads((package / 'hardware.json').read_text())
    acc = hw['accelerator']
    if (acc['kernel_n'], acc['channels_k'], acc['image_w'], acc['image_h']) != (3, 16, 32, 32):
        raise RuntimeError('This runner supports the released N3/K16/W32 geometry only')
    driver.BASE = package / 'params'
    channels = driver.load_params('B32', 3, 16)
    raw = (package / 'input_u8.bin').read_bytes()
    if len(raw) != 1024:
        raise RuntimeError('Expected exactly 1024 unsigned pixels')
    padded = bytearray(34*34)
    for row in range(32):
        padded[(row+1)*34+1:(row+1)*34+33] = raw[row*32:(row+1)*32]
    expected = driver.make_expected(bytes(padded), 3, 32, 32, channels)
    return hw, channels, bytes(padded), expected


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package', type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument('--check-only', action='store_true', help='Host-only integrity/reference test; no device access')
    parser.add_argument('--frames', type=int, default=3)
    parser.add_argument('--confirmed-clock-mhz', type=int,
                        help='Actual PS FCLK0 verified after boot; this option does not set or measure the clock')
    args = parser.parse_args()
    hw, channels, padded, expected = verify_package(args.package)
    if args.check_only:
        print(f'PACKAGE_HOST_PASS: {len(expected)} expected int16 outputs; no board tested')
        return
    if args.frames < 1 or platform.machine() != 'armv7l':
        raise RuntimeError('Run on the ZedBoard with a positive frame count')
    if args.confirmed_clock_mhz != hw['accelerator']['clock_mhz']:
        raise RuntimeError('Verify FCLK0 from the matching boot platform, then pass --confirmed-clock-mhz')
    info = Path('/sys/class/u-dma-buf/udmabuf0')
    if int((info / 'sync_mode').read_text(), 0) != 1:
        raise RuntimeError('Expected the qualified u-dma-buf sync_mode=1 platform')
    phys = int((info / 'phys_addr').read_text(), 0)
    size = int((info / 'size').read_text(), 0)
    layout = driver.compute_layout(len(padded), len(expected)*2, size)
    driver.acquire_lock()
    handles = None
    admitted = False
    try:
        handles = driver.open_handles()
        dma, accel, buf_fd, _ = handles
        driver.validate_identity(driver.read_identity(accel), hw)
        # Check data-width registers too; m7's helper checks geometry and ID.
        driver.require(driver.read32(accel, 0x4130) == 0x10180808, 'WIDTHS_0 mismatch')
        driver.require(driver.read32(accel, 0x4134) == 0x00001915, 'WIDTHS_1 mismatch')
        status = driver.read32(accel, driver.REG_STATUS)
        driver.require(bool(status & driver.STATUS_IDLE) and bool(status & driver.STATUS_QUIESCENT)
                       and not (status & (driver.STATUS_ERROR | driver.STATUS_FAULT)),
                       f'Accelerator is not safely idle: {status:#x}')
        admitted = True
        driver.program_params_accel(accel, 3, channels)
        for frame in range(args.frames):
            _, mismatches, digest, elapsed = driver.run_frame(
                dma, accel, buf_fd, phys, layout, padded, expected, 16)
            driver.require(mismatches == 0, f'Frame {frame}: {mismatches} mismatches')
            print(f'FRAME_PASS {frame+1}/{args.frames} elapsed_ms={elapsed*1000:.3f} sha256={digest}')
        driver.dma_halt(dma)
        driver.write32(accel, driver.REG_COMMAND, driver.CMD_RESET)
        final_mask = driver.STATUS_IDLE | driver.STATUS_QUIESCENT
        driver.wait_for(lambda: (driver.read32(accel, driver.REG_STATUS) & final_mask) == final_mask,
                        'Final RESET/quiescence')
        driver.require(not (driver.read32(accel, driver.REG_STATUS) &
                            (driver.STATUS_ERROR | driver.STATUS_FAULT)), 'Final reset left a fault')
        print('EDGEFREE_BOARD_PASS: exact outputs, counters and guards passed')
    except Exception:
        if admitted and handles is not None:
            # Bound outstanding DMA before returning ownership after a failed test.
            try:
                driver.dma_halt(handles[0])
                driver.write32(handles[1], driver.REG_COMMAND, driver.CMD_ABORT)
            except Exception as cleanup_error:
                print(f'RECOVERY_REQUIRED: {cleanup_error}')
        raise
    finally:
        if handles is not None:
            driver.close_handles(handles)
        driver.release_lock()


if __name__ == '__main__':
    main()
