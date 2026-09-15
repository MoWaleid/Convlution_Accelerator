"""Mocked full-activation test for software/m7_switch.py (feedback review gate:
exercise the actual manager end-to-end, not just its supporting helpers).

Emulates in one process: AXI DMA register semantics (Halted RO bit, W1C status,
length registers), CVH1 accelerator registers (START/RESET lifecycle, counters,
sticky events, factory-fresh state after programming), FPGA Manager programming,
u-dma-buf memory (golden convolution results written into the RX region), and
the activation PNG.

Usage (from the repo root, venv python):
    python verification/m7_profiles/mock_switch_test.py --matrix-seq
    python verification/m7_profiles/mock_switch_test.py --profile B32 3
Run --profile twice in a row to also exercise the same-build (no reload) path.
"""
import json
import os
import shutil
import struct
import sys
import types
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
STAGE = Path(os.environ.get(
    "M7_MOCK_STAGE", "C:/Users/moham/AppData/Local/Temp/m7_bundle2/profiles"))
PNG = REPO / "golden_model/data/cifar10_images/test/cat/alley_cat_s_000013.png"
BUFSZ = 4 * 1024 * 1024

# --- fake m4_filebackend before importing the manager -------------------------
fb = types.ModuleType("m4_filebackend")


class _Platform:
    @staticmethod
    def machine():
        return "armv7l"


fb.platform = _Platform


def _require(cond, msg):
    if not cond:
        raise RuntimeError(msg)


fb.require = _require
sys.modules["m4_filebackend"] = fb
sys.path.insert(0, str(REPO / "software"))
import m7_switch as M  # noqa: E402


def _ensure_stage_releases():
    """Gate-1 D2 fixture: the stage catalog gains the releases section the
    manager now requires (same binding computation as the repo catalog)."""
    M.BASE = STAGE
    cat_p = STAGE / "m7_profiles.json"
    cat = json.loads(cat_p.read_text())
    if "releases" in cat:
        return
    cat["releases"] = {}
    for name, prof in cat["profiles"].items():
        _chans, sha = M.load_params(name, prof["N"], prof["K"])
        cat["releases"][name] = {
            "shape_id": f"N{prof['N']}K{prof['K']}W{prof['W']}H{prof['H']}-CVH1",
            "bundle_sha256": sha,
            "manifest": f"hardware_{name}.json",
            "build_id_hex": json.loads(
                (STAGE / f"hardware_{name}.json").read_text()
            )["accelerator"]["build_id_hex"],
        }
    cat_p.write_text(json.dumps(cat, indent=2))


_ensure_stage_releases()

# --- fake hardware state -------------------------------------------------------
buf = bytearray(BUFSZ)          # u-dma-buf contents
FAKE_FD = 0x5D0                 # stand-in fd for /dev/udmabuf0
CURRENT = {}                    # profile context for completion emulation


class FakeRegs:
    def __init__(self):
        self.mem = bytearray(0x10000)

    def close(self):
        pass


dma_regs = FakeRegs()           # AXI DMA register map
acc_regs = FakeRegs()           # accelerator register map


def r32m(mem, off):
    return struct.unpack_from("<I", mem, off)[0]


def w32m(mem, off, val):
    struct.pack_into("<I", mem, off, val & 0xFFFFFFFF)


def program_profile(profile):
    """Emulate FPGA Manager programming: factory-fresh PL with target identity."""
    hw = json.loads((STAGE / f"hardware_{profile}.json").read_text())["accelerator"]
    groups = [bytes.fromhex(hw["build_id_hex"])[i * 4:(i + 1) * 4] for i in range(4)]
    for j in range(4):          # word @0x4150 holds group 3 (m4_filebackend order)
        w32m(acc_regs.mem, M.REG_BUILD_ID_0 + 4 * j, int.from_bytes(groups[3 - j], "big"))
    w32m(acc_regs.mem, M.REG_MAGIC, 0x43564831)
    w32m(acc_regs.mem, M.REG_ABI_VERSION, 0x00010000)
    w32m(acc_regs.mem, M.REG_CAPABILITIES, 0x1FF)
    w32m(acc_regs.mem, M.REG_IMAGE_W, hw["image_w"])
    w32m(acc_regs.mem, M.REG_IMAGE_H, hw["image_h"])
    w32m(acc_regs.mem, M.REG_KERNEL_N, hw["kernel_n"])
    w32m(acc_regs.mem, M.REG_CHANNEL_K, hw["channels_k"])
    w32m(acc_regs.mem, M.REG_EXPECTED_INPUT_BYTES, hw["expected_input_bytes"])
    w32m(acc_regs.mem, M.REG_EXPECTED_OUTPUT_BYTES, hw["expected_output_bytes"])
    w32m(acc_regs.mem, M.REG_DMA_LENGTH_WIDTH, 22)
    w32m(acc_regs.mem, 0x4130, 0x10180808)
    w32m(acc_regs.mem, 0x4134,
         0x1900 + 17 + (hw["kernel_n"] ** 2 - 1).bit_length())
    w32m(acc_regs.mem, M.REG_STATUS, 0x101)
    w32m(acc_regs.mem, M.REG_ERROR_FLAGS, 0)
    for a in (0x4140, 0x4144, 0x4148, 0x414C):
        w32m(acc_regs.mem, a, 0)


def complete_frame():
    """Write the golden output into the fake buffer and set completion bits."""
    tx = r32m(dma_regs.mem, 0x28)
    rx = r32m(dma_regs.mem, 0x58)
    running = (r32m(dma_regs.mem, 0x00) & 1) and (r32m(dma_regs.mem, 0x30) & 1)
    if not (tx and rx and running):
        return False            # transfer not armed yet
    layout = M.compute_layout(tx, rx, BUFSZ)
    padded = bytes(buf[layout["tx_offset"]:layout["tx_offset"] + tx])
    expected = M.make_expected(padded, CURRENT["n"], CURRENT["w"], CURRENT["h"],
                               CURRENT["channels"])
    packed = struct.pack(f"<{len(expected)}h", *expected)
    require_eq = len(packed) == rx
    assert require_eq, (len(packed), rx)
    buf[layout["rx_offset"]:layout["rx_offset"] + rx] = packed
    w32m(acc_regs.mem, 0x4140, tx)
    w32m(acc_regs.mem, 0x4144, tx)
    w32m(acc_regs.mem, 0x4148, rx // (2 * CURRENT["k"]))
    w32m(acc_regs.mem, 0x414C, rx)
    w32m(acc_regs.mem, M.REG_STATUS, 0x19D)  # IDLE|events|DONE|PARAM|QUIESCENT
    w32m(dma_regs.mem, 0x04, r32m(dma_regs.mem, 0x04) | 0x1000)  # MM2S IOC
    w32m(dma_regs.mem, 0x34, r32m(dma_regs.mem, 0x34) | 0x1000)  # S2MM IOC
    return True


# --- patch the manager's I/O surface ------------------------------------------
M.BASE = STAGE
M.LOCK_FILE = STAGE.parent / "mock.lock"
M.FW_DIR = REPO / "bitstreams"
M.FW_NAME = {
    "B32": "bn3k16_len22_2026-09-12.bit.bin",
    "C32": "cn5k08_len22_2026-09-12.bit.bin",
    "D32": "dn3k04_len22_2026-09-12.bit.bin",
    "D640": "dn3k04_w640480_2026-09-12.bit.bin",
    # GLM-F6 staging: candidate firmware names resolve, but no firmware file
    # exists until the routed builds fill the candidate manifests.
    "A32_CFGLUT125": "m7_A32_CFGLUT125.bin",
    "B32_CFGLUT125": "m7_B32_CFGLUT125.bin",
    "C32_CFGLUT125": "m7_C32_CFGLUT125.bin",
    "D32_CFGLUT125": "m7_D32_CFGLUT125.bin",
    "D640_CFGLUT125": "m7_D640_CFGLUT125.bin",
    "B32_CFGLUT100": "m7_B32_CFGLUT100.bin",
}


def fake_open_handles():
    return dma_regs, acc_regs, FAKE_FD, []


def fake_program(firmware):
    program_profile({v: k for k, v in M.FW_NAME.items()}[firmware.name])


def fake_load_input(n, w, h):
    from PIL import Image
    image = Image.open(PNG).convert("L")
    if image.size != (w, h):
        image = image.resize((w, h), Image.LANCZOS)
    raw = image.tobytes()
    stride = w + n - 1
    padded = bytearray(stride * (h + n - 1))
    for row in range(h):
        s = (row + n // 2) * stride + n // 2
        padded[s:s + w] = raw[row * w:(row + 1) * w]
    return bytes(padded)


def fake_wait(predicate, description, seconds=5.0):
    for _ in range(1000):
        if predicate():
            return
        if "PARAM_COMPLETE" in description:
            w32m(acc_regs.mem, M.REG_STATUS,
                 r32m(acc_regs.mem, M.REG_STATUS) | 0x80)
        elif "frame did not complete" in description:
            complete_frame()
    raise TimeoutError(description)


def fake_read32(regs, off):
    return r32m(regs.mem, off)


def fake_write32(regs, off, val):
    if regs is dma_regs and off in (0x04, 0x34):
        cur = r32m(regs.mem, off)
        w32m(regs.mem, off, cur & ~val & ~1)   # W1C status, Halted bit0 is RO
        return
    w32m(regs.mem, off, val)
    if regs is dma_regs and off in (0x00, 0x30):
        sr_off = 0x04 if off == 0x00 else 0x34
        sr = r32m(regs.mem, sr_off)
        w32m(regs.mem, sr_off, (sr & ~1) if val & 1 else (sr | 1))
    elif regs is acc_regs and off == M.REG_COMMAND:
        if val & 1:      # START: counters + events cleared, BUSY
            w32m(acc_regs.mem, M.REG_STATUS, 0x2)
            for a in (0x4140, 0x4144, 0x4148, 0x414C):
                w32m(acc_regs.mem, a, 0)
        elif val & 2:    # RESET: retained parameters, 0x181
            w32m(acc_regs.mem, M.REG_STATUS, 0x181)
            for a in (0x4140, 0x4144, 0x4148, 0x414C):
                w32m(acc_regs.mem, a, 0)


class FakeSysPath:
    def __init__(self, s):
        self.s = str(s)

    def __truediv__(self, name):
        return FakeSysPath(self.s + "/" + str(name))

    def read_text(self):
        if self.s.endswith("phys_addr"):
            return "0x1F100000"
        if self.s.endswith("size"):
            return str(BUFSZ)
        raise AssertionError(f"unexpected sysfs read: {self.s}")


_RealPath = Path


def fake_path(p):
    return FakeSysPath(p) if str(p).startswith("/sys/") else _RealPath(p)


# Windows os lacks pwrite/pread: give the manager a proxy os module whose
# pwrite/pread address the fake u-dma-buf when handed the fake fd.
_real_os = os


def fake_pwrite(fd, data, off):
    if fd == FAKE_FD:
        buf[off:off + len(data)] = data
        return len(data)
    return None


def fake_pread(fd, count, off):
    if fd == FAKE_FD:
        return bytes(buf[off:off + count])
    return b"\x00" * count


class _FakeOs:
    """Fakes pwrite/pread/close for the fake u-dma-buf fd; everything else
    (lock files, O_* constants, ftruncate, replace) passes through to the
    real os module."""

    O_RDWR = _real_os.O_RDWR
    O_CREAT = _real_os.O_CREAT
    O_EXCL = _real_os.O_EXCL
    O_TRUNC = _real_os.O_TRUNC
    O_WRONLY = _real_os.O_WRONLY
    O_RDONLY = _real_os.O_RDONLY

    def getpid(self):
        return _real_os.getpid()

    def open(self, *a):
        return _real_os.open(*a)

    def stat(self, *a):
        return _real_os.stat(*a)

    def replace(self, *a):
        return _real_os.replace(*a)

    def ftruncate(self, *a):
        return _real_os.ftruncate(*a)

    def write(self, fd, data):
        if fd == FAKE_FD:
            raise AssertionError("os.write to the fake u-dma-buf fd")
        return _real_os.write(fd, data)

    def close(self, fd):
        if fd == FAKE_FD:
            return None
        return _real_os.close(fd)

    def pwrite(self, fd, data, off):
        return fake_pwrite(fd, data, off)

    def pread(self, fd, count, off):
        return fake_pread(fd, count, off)


fake_os = _FakeOs()

M.open_handles = fake_open_handles
M.program_fpga = fake_program
M.load_input = fake_load_input
M.wait_for = fake_wait
M.read32 = fake_read32
M.write32 = fake_write32
M.Path = fake_path
M.os = fake_os


# The fake fabric computes golden results from the ACTUALLY INSTALLED
# parameters, like real silicon: intercept program_params_accel so the
# emulated output tracks parameter installations (saturation stimuli,
# reinstallation) instead of a stale snapshot.
_real_ppa = M.program_params_accel


def fake_program_params(accel, n, channels):
    CURRENT["channels"] = channels
    return _real_ppa(accel, n, channels)


M.program_params_accel = fake_program_params


def run(argv):
    profile = argv[1]
    hw = json.loads((STAGE / f"hardware_{profile}.json").read_text())["accelerator"]
    chans, _bundle = M.load_params(profile, hw["kernel_n"], hw["channels_k"])
    CURRENT.update(n=hw["kernel_n"], k=hw["channels_k"], w=hw["image_w"],
                   h=hw["image_h"], channels=chans)
    sys.argv = ["m7_switch.py"] + argv
    M.main()
    print(f"MOCK OK: {' '.join(argv)}", flush=True)


if __name__ == "__main__":
    args = sys.argv[1:]
    if args == ["--matrix-seq"]:
        need = {(a, b) for a in M.ORDER for b in M.ORDER if a != b}
        for start in M.ORDER:
            seq = M.build_matrix_sequence(start)
            pairs, cur = set(), start
            for t in seq:
                assert t in M.ORDER, t
                pairs.add((cur, t))
                cur = t
            assert need <= pairs, (start, need - pairs)
            print(f"matrix from {start}: {len(seq)} switches, all 20 pairs covered")
        print("MOCK OK: --matrix-seq")
    else:
        if args and args[0] == "--same-build":
            frames = args[2] if len(args) > 2 else "3"
            program_profile("A32")
            run(["--profile", args[1], frames])
            run(["--profile", args[1], frames])   # live build already matches
        elif args == ["--d640-input-hash"]:
            import hashlib
            from PIL import Image
            image = Image.open(PNG).convert("L").resize((640, 480), Image.LANCZOS)
            digest = hashlib.sha256(image.tobytes()).hexdigest()
            want = json.loads((STAGE / "anchors_m7.json").read_text())[
                "D640_preprocessing"]["canonical_sha256"]
            print("D640 canonical input:", digest)
            assert digest == want, (digest, want)
            print("MOCK OK: --d640-input-hash")
        elif args[:2] in (["--candidate-undeployable", "profile"],
                          ["--candidate-undeployable", "soak"]):
            # GLM-F6/F7: candidate releases resolve their bundle and firmware
            # name, but their placeholder manifests must fail closed BEFORE
            # any hardware mutation until a routed build fills the hashes.
            release = "A32_CFGLUT125"
            mode = "--profile" if args[1] == "profile" else "--soak"
            # Sync the stage with the authoritative repo catalog and the
            # candidate manifests so the test exercises the current staging.
            repo_catalog = json.loads(
                (REPO / "profiles/m7_profiles.json").read_text())
            (STAGE / "m7_profiles.json").write_text(
                json.dumps(repo_catalog, indent=2))
            for cand in ("A32_CFGLUT125", "C32_CFGLUT125",
                         "D32_CFGLUT125", "D640_CFGLUT125"):
                cand_doc = json.loads(
                    (REPO / f"software/hardware_{cand}.json").read_text())
                # The repo manifests are admitted since the five-build
                # freeze (built-unqualified, deployable); fabricate the
                # pre-build candidate state in the stage so this negative
                # test keeps proving the GLM-F7 fail-closed gate.
                cand_doc["artifacts"]["bitstream_sha256"] = "TBD_FIRST_BUILD"
                cand_doc["artifacts"]["firmware_bin_sha256"] = "TBD_FIRST_BUILD"
                cand_doc["release_status"] = "candidate-unbuilt"
                cand_doc["deployable"] = False
                (STAGE / f"hardware_{cand}.json").write_text(
                    json.dumps(cand_doc, indent=2))
            program_profile("A32")   # board starts with the A32 build live
            before_acc = bytes(acc_regs.mem)
            before_dma = bytes(dma_regs.mem)
            program_calls = []
            real_program = M.program_fpga
            M.program_fpga = lambda fw: program_calls.append(fw.name)
            try:
                sys.argv = ["m7_switch.py", mode, release, "1"]
                try:
                    M.main()
                except (RuntimeError, FileNotFoundError) as exc:
                    assert "A32_CFGLUT125" in str(exc), exc
                else:
                    raise AssertionError("candidate release was admitted")
                # Even with a firmware file present, the explicit candidate
                # status must reject the release before hashes or hardware.
                import tempfile
                with tempfile.TemporaryDirectory() as temp_fw:
                    dummy = Path(temp_fw) / "m7_A32_CFGLUT125.bin"
                    dummy.write_bytes(b"\x00" * 16)
                    M.FW_DIR = Path(temp_fw)
                    try:
                        catalog_doc = json.loads(
                            (STAGE / "m7_profiles.json").read_text())
                        anchors = json.loads(
                            (STAGE / "anchors_m7.json").read_text())
                        M.switch_to(release, catalog_doc, anchors, None)
                    except RuntimeError as exc:
                        assert "explicitly marks this release non-deployable" in str(exc), exc
                    else:
                        raise AssertionError("placeholder manifest admitted")
            finally:
                M.program_fpga = real_program
                M.FW_DIR = REPO / "bitstreams"
            assert program_calls == [], program_calls
            assert bytes(acc_regs.mem) == before_acc, "accelerator registers mutated"
            assert bytes(dma_regs.mem) == before_dma, "DMA registers mutated"
            print(f"MOCK OK: candidate {release} rejected before hardware "
                  f"mutation ({mode}; GLM-F7 admission verified)")
        else:
            program_profile("A32")   # board starts with the A32 build live
            run(args)
