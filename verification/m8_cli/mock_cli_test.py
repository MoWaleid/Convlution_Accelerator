"""Mocked end-to-end test for software/m8_cli.py: the real CLI against the
fake-hardware harness from verification/m7_profiles/mock_switch_test.py
(fake AXI DMA + CVH1 registers, FPGA manager, u-dma-buf, activation PNG).

Covers: same-build run (anchor mode), full-reload run (B32), exact-reference
file run with a generated image, UNVERIFIED outcome when only sha is
available (M8-01), archive-collision allocation (M8-04), previews, benchmark,
list/record round-trip, and the failure-record path.

Usage (repo root, venv python):
    python verification/m8_cli/mock_cli_test.py
"""
import json
import os
import sys
import tempfile
import types
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / "verification" / "m7_profiles"))
import mock_switch_test as MH          # noqa: E402  (patches M = m7_switch)

ARCHIVE = Path(tempfile.mkdtemp(prefix="m8_mock_archive_"))
os.environ["M8_ARCHIVE_ROOT"] = str(ARCHIVE)
sys.path.insert(0, str(REPO / "software"))
import m8_cli as CLI                   # noqa: E402  (uses the patched M)

PNG = MH.PNG
CANONICAL_A32 = ("a240bb760e2a85951f5c4e27c95041e98d4919c5cc32114cc4f5191f6ffb6771")

# --- stage fixture: A32 firmware does not exist in the repo (board-only), so
# clone the profile stage and give the fixture an A32 image whose recorded
# hash matches; B/C/D keep their real artifact-matched firmware files. ------
import hashlib as hl
import shutil

STAGE_COPY = Path(tempfile.mkdtemp(prefix="m8_mock_stage_"))
shutil.copytree(MH.STAGE, STAGE_COPY, dirs_exist_ok=True)
FW_DIR = STAGE_COPY
for name in ("bn3k16_len22_2026-09-12.bit.bin", "cn5k08_len22_2026-09-12.bit.bin",
             "dn3k04_len22_2026-09-12.bit.bin", "dn3k04_w640480_2026-09-12.bit.bin"):
    shutil.copy(REPO / "bitstreams" / name, FW_DIR / name)
A32_FW = (REPO / "bitstreams" / "dn3k04_w640480_2026-09-12.bit.bin").read_bytes()
(FW_DIR / "m7_A32_mock.bin").write_bytes(A32_FW)
a32_hw_path = FW_DIR / "hardware_A32.json"
a32_hw = json.loads(a32_hw_path.read_text())
a32_hw["artifacts"]["firmware_bin_sha256"] = hl.sha256(A32_FW).hexdigest()
a32_hw_path.write_text(json.dumps(a32_hw))

MH.M.BASE = STAGE_COPY
MH.M.FW_DIR = FW_DIR
MH.M.FW_NAME = {"A32": "m7_A32_mock.bin",
                "B32": "bn3k16_len22_2026-09-12.bit.bin",
                "C32": "cn5k08_len22_2026-09-12.bit.bin",
                "D32": "dn3k04_len22_2026-09-12.bit.bin",
                "D640": "dn3k04_w640480_2026-09-12.bit.bin"}


def set_current(profile):
    hw = json.loads((MH.M.BASE / f"hardware_{profile}.json").read_text())["accelerator"]
    chans, _bundle = MH.M.load_params(profile, hw["kernel_n"], hw["channels_k"])
    MH.CURRENT.update(n=hw["kernel_n"], k=hw["channels_k"], w=hw["image_w"],
                      h=hw["image_h"], channels=chans)


def newest_record():
    recs = sorted(ARCHIVE.glob("*/record.json"), key=lambda p: p.stat().st_mtime)
    assert recs, "no records written"
    return json.loads(recs[-1].read_text()), recs[-1].parent


def main():
    MH.M.LOCK_FILE.unlink(missing_ok=True)   # clear stale mock locks
    MH.program_profile("A32")          # cold-start equivalent: A32 live

    # 1) same-build run, library image, anchor mode, previews on
    set_current("A32")
    CLI.main(["run", "--profile", "A32", "--frames", "2", "--previews"])
    rec, run_dir = newest_record()
    assert rec["outcome"] == "PASS", rec
    assert rec["verification"]["mode"] == "anchor_sha256"
    assert rec["cleanup"] == {"ok": True}
    assert rec["switch"]["reloaded"] is False, "A32→A32 must not reload"
    assert len(rec["frames"]) == 2
    assert all(f["mismatches"] is None for f in rec["frames"])   # anchor mode
    assert all(f["sha256"] == rec["verification"]["anchor"]
               for f in rec["frames"])
    assert rec["input"]["canonical_sha256"] == CANONICAL_A32, rec["input"]
    for name in rec["previews"]:
        assert (run_dir / name).is_file(), name
    assert (run_dir / "frame_001.s16le").is_file()
    print("MOCK OK: run A32 same-build (anchor mode, previews)")

    # 2) full-reload run to B32
    set_current("B32")
    CLI.main(["run", "--profile", "B32", "--frames", "1"])
    rec, _ = newest_record()
    assert rec["outcome"] == "PASS" and rec["switch"]["reloaded"] is True
    assert rec["verification"]["anchor"].startswith("5821c8b1")
    print("MOCK OK: run B32 reload (anchor mode)")

    # 3) file-driven run: exact software reference on a generated image.
    # Windows has no Linux decoder worker; mock the CLI's loader with a
    # fixture implementation standing in for the isolated worker.
    set_current("A32")
    from PIL import Image
    raw = bytes(range(256)) * 4       # deterministic 32x32 gradient pattern
    custom = ARCHIVE.parent / "m8_mock_custom.png"
    Image.frombytes("L", (32, 32), raw[:1024]).save(custom)
    real_loader = CLI.load_image_exact
    import hashlib as hl

    def fake_loader(path, w, h):
        canonical = Image.open(path).convert("L").tobytes()
        meta = {"source_path": str(path),
                "source_sha256": hl.sha256(Path(path).read_bytes()).hexdigest(),
                "source_format": "PNG", "source_mode": "L",
                "source_width": w, "source_height": h,
                "oriented_width": w, "oriented_height": h,
                "geometry_policy": "exact",
                "decode_policy": {"resource_strategy": "mock"}}
        return canonical, meta

    CLI.load_image_exact = fake_loader
    try:
        CLI.main(["run", "--profile", "A32", "--frames", "1", "--image",
                  str(custom)])
        rec, _ = newest_record()
        assert rec["outcome"] == "PASS"
        assert rec["verification"]["mode"] == "exact_reference"
        assert rec["input"]["source_sha256"] == hl.sha256(custom.read_bytes()).hexdigest()
        assert rec["input"]["canonical_sha256"] == hl.sha256(raw[:1024]).hexdigest()
        assert rec["frames"][0]["mismatches"] == 0
        print("MOCK OK: run --image (exact reference mode)")
        # 3b) M8-01: with the position limit forced to zero, a file run cannot
        # verify numerically -> outcome must be UNVERIFIED, mismatches null
        real_limit = MH.M.REF_POSITION_LIMIT
        MH.M.REF_POSITION_LIMIT = 0
        try:
            CLI.main(["run", "--profile", "A32", "--frames", "1", "--image",
                      str(custom)])
            rec, _ = newest_record()
            assert rec["outcome"] == "UNVERIFIED", rec["outcome"]
            assert rec["verification"]["mode"] == "sha_only"
            assert rec["frames"][0]["mismatches"] is None
        finally:
            MH.M.REF_POSITION_LIMIT = real_limit
        print("MOCK OK: sha_only -> UNVERIFIED (never a PASS)")
        # 3c) M8-04: two runs in the same clock second must not collide
        real_time = CLI.time

        class FakeTime:
            @staticmethod
            def strftime(_fmt, *_a):
                return "20260913T000000Z"

            @staticmethod
            def gmtime():
                return 0

            perf_counter = staticmethod(real_time.perf_counter)
            monotonic = staticmethod(real_time.monotonic)
            time = staticmethod(real_time.time)

        CLI.time = FakeTime
        try:
            CLI.main(["run", "--profile", "A32", "--frames", "1", "--image",
                      str(custom)])
            CLI.main(["run", "--profile", "A32", "--frames", "1", "--image",
                      str(custom)])
        finally:
            CLI.time = real_time
        recs = sorted(ARCHIVE.glob("20260913T000000Z-*/record.json"))
        assert len(recs) == 2, [p.parent.name for p in recs]
        ids = {json.loads(p.read_text())["run_id"] for p in recs}
        assert len(ids) == 2, ids
        assert all(json.loads(p.read_text())["outcome"] == "PASS" for p in recs)
    finally:
        CLI.load_image_exact = real_loader
    print("MOCK OK: archive collision -> distinct directories")

    # 4) benchmark harness
    set_current("A32")
    CLI.main(["benchmark", "--profile", "A32", "--frames", "20", "--warmup", "2"])
    rec, _ = newest_record()
    assert rec["outcome"] == "PASS" and len(rec["frames"]) == 20
    assert rec["timings"]["hw_ms"]["median"] > 0
    assert rec["timings"]["io_overhead_ms_median"] >= 0
    print("MOCK OK: benchmark (stats + environment recorded)")

    # 4b) E2 extremes: all-zero, all-255, saturation stimulus (both rails),
    # canonical reinstall + anchor revalidation
    set_current("A32")
    CLI.main(["extremes", "--profile", "A32"])
    rec, run_dir = newest_record()
    assert rec["outcome"] == "PASS", rec
    tags = [f["stimulus"] for f in rec["frames"]]
    assert tags == ["all_zero", "all_255", "saturation_params",
                    "reinstall_activation"], tags
    assert all(f["mismatches"] == 0 for f in rec["frames"])
    assert (run_dir / "frame_saturation_params.s16le").is_file()
    print("MOCK OK: extremes (4 stimulus frames, saturation rails exercised)")

    # 4c) M9 soak: library-anchor mode, then image exact-reference mode
    set_current("A32")
    CLI.main(["soak", "--profile", "A32", "--frames", "5"])
    rec, _ = newest_record()
    assert rec["outcome"] == "PASS" and len(rec["frames"]) == 5
    assert rec["verification"]["mode"] == "anchor_sha256"
    print("MOCK OK: soak library-anchor mode")
    set_current("B32")
    CLI.load_image_exact = fake_loader
    try:
        CLI.main(["soak", "--profile", "B32", "--frames", "2", "--image",
                  str(custom)])
    finally:
        CLI.load_image_exact = real_loader
    rec, _ = newest_record()
    assert rec["outcome"] == "PASS" and len(rec["frames"]) == 2
    assert rec["verification"]["mode"] == "exact_reference"
    assert all(f["mismatches"] == 0 for f in rec["frames"])
    print("MOCK OK: soak image exact-reference mode")

    # 5) failure path: injected frame error must still produce a record
    real_run_frame = MH.M.run_frame

    def boom(*a, **kw):
        raise RuntimeError("mock injected frame failure")
    MH.M.run_frame = boom
    try:
        CLI.main(["run", "--profile", "A32", "--frames", "1"])
        raise AssertionError("injected failure did not propagate")
    except RuntimeError as exc:
        assert "mock injected" in str(exc)
    finally:
        MH.M.run_frame = real_run_frame
    rec, _ = newest_record()
    assert rec["outcome"] == "FAILED" and "mock injected" in rec["failure"]["message"]
    print("MOCK OK: failure record (outcome FAILED, failure snapshot present)")

    # 6) list + record round-trip
    import io
    from contextlib import redirect_stdout
    out = io.StringIO()
    with redirect_stdout(out):
        CLI.main(["list"])
    listing = out.getvalue()
    n_runs = len(list(ARCHIVE.glob("*/record.json")))
    assert f"({n_runs} runs)" in listing, listing
    assert listing.count(": PASS") == 9, listing
    assert "UNVERIFIED" in listing and "FAILED" in listing, listing
    rec, _ = newest_record()
    out = io.StringIO()
    with redirect_stdout(out):
        CLI.main(["record", rec["run_id"]])
    assert json.loads(out.getvalue())["run_id"] == rec["run_id"]
    try:
        CLI.main(["record", "../escape"])
        raise AssertionError("traversal run id accepted")
    except RuntimeError as exc:
        assert "invalid run id" in str(exc)
    print("MOCK OK: list + record round-trip + traversal rejected")

    print(f"M8 MOCK SUITE: PASS (archive: {ARCHIVE})")


if __name__ == "__main__":
    main()
