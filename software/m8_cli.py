#!/usr/bin/env python3
"""M8 reproducible operation CLI: file-driven inference runs, a run archive
with complete hashes/status, display-only previews, and a measurement harness.

Everything hardware-related goes through the exclusive-owner M7 switch manager
(m7_switch): identity validation, full-PL reload / parameter-only switching,
approved guarded layout, frames, cleanup. This CLI never maps devices or
programs the PL itself. All m7 entry points are referenced through the module
(m7.func) so the mock harness can patch the I/O surface.

Board usage (archive default /var/lib/conv-lab/results; M8_ARCHIVE_ROOT env
override exists for host mock tests only):
  sudo python3 /home/petalinux/m8_cli.py run --profile A32 [--frames 3]
       [--image PATH] [--previews] [--reference]
  sudo python3 /home/petalinux/m8_cli.py benchmark --profile A32
       [--frames 200] [--warmup 10]
  sudo python3 /home/petalinux/m8_cli.py list
  sudo python3 /home/petalinux/m8_cli.py record <run-id>

Outcomes: PASS (executed + independently verified: exact reference or golden
anchor), UNVERIFIED (executed, transfer verified, but no independent
numerical check was available - sha recorded only), FAILED, CANCELLED.
"""
import argparse
import hashlib
import json
import os
import platform
import re
import statistics
import struct
import sys
import time
from pathlib import Path

sys.path.insert(0, "/home/petalinux")
import m4_filebackend as fb   # noqa: E402  (fake in mock tests)
import m7_switch as m7        # noqa: E402

# M1_DEPLOYMENT_POLICY approved values.
MAX_SOURCE_BYTES = 8388608
MAX_DIM = 4096
MAX_PIXELS = 2097152
DISPOSABLE_BUDGET = 268435456        # 256 MiB run-payload budget
HEADROOM_REQUIRED = 536870912        # 512 MiB free after the reservation

D_PROFILES = ("D32", "D640")   # channels 1,2 are Sobel X/Y by construction
DEFAULT_RESULTS = Path("/var/lib/conv-lab/results")
FALLBACK_RESULTS = Path("/home/petalinux/runs")
def file_md5(path):
    return hashlib.md5(Path(path).read_bytes()).hexdigest()


def archive_root():
    root = os.environ.get("M8_ARCHIVE_ROOT")
    candidates = [Path(root)] if root else [DEFAULT_RESULTS, FALLBACK_RESULTS]
    for cand in candidates:
        try:
            cand.mkdir(parents=True, exist_ok=True)
            return cand, str(cand)
        except OSError:
            continue
    raise RuntimeError("no writable archive root")


def storage_admission(root, estimate):
    """M1_DEPLOYMENT_POLICY: peak-operation estimate against the disposable
    budget, and 512 MiB free headroom after the reservation. Runs before any
    hardware mutation."""
    require_local = m7.require
    require_local(estimate <= DISPOSABLE_BUDGET,
                  f"run payload estimate {estimate} B exceeds the "
                  f"{DISPOSABLE_BUDGET} B disposable budget")
    import shutil
    free = shutil.disk_usage(root).free
    require_local(free - estimate >= HEADROOM_REQUIRED,
                  f"insufficient storage headroom: {free} B free, estimate "
                  f"{estimate} B, policy requires {HEADROOM_REQUIRED} B free "
                  "after the reservation")


def chown_tree(path):
    """Best-effort: hand root-created files to the board user. Only files
    this run created are inside run_dir, which is freshly allocated."""
    try:
        st = os.stat("/home/petalinux")
        for p in [path, *path.rglob("*")]:
            os.chown(p, st.st_uid, st.st_gid)
    except OSError:
        pass


def allocate_run_dir(root, base_id):
    """Exclusively allocate a fresh run directory; never reuse or overwrite
    an existing one (M8-04)."""
    cand = root / base_id
    n = 0
    while True:
        try:
            cand.mkdir(parents=True)
            return cand
        except FileExistsError:
            n += 1
            cand = root / f"{base_id}.{n}"


def unpad(padded, n, w, h):
    stride = w + n - 1
    off = n // 2
    return b"".join(padded[(r + off) * stride + off:(r + off) * stride + off + w]
                    for r in range(h))


def pad_bytes(raw, n, w, h):
    stride = w + n - 1
    padded = bytearray(stride * (h + n - 1))
    for row in range(h):
        s = (row + n // 2) * stride + n // 2
        padded[s:s + w] = raw[row * w:(row + 1) * w]
    return bytes(padded)


def _decoder():
    """The M2 isolated bounded decoder worker (conv_lab.preprocessing):
    unprivileged RLIMIT-AS subprocess, 30 s supervisor deadline, bounded IPC,
    no inherited descriptors. Under the sudo backend the supervisor is root,
    so the worker subprocess is demoted to the board user before exec; the
    worker still refuses privileged/non-Linux hosts and installs its own
    limits. Fail closed — there is no in-process decode fallback."""
    import conv_lab.preprocessing as pp
    if hasattr(os, "geteuid") and os.geteuid() == 0:
        st = os.stat("/home/petalinux")
        return pp.LinuxDecoder(demote_to=(st.st_uid, st.st_gid))
    return pp.LinuxDecoder()


def load_image_exact(path, w, h):
    """Approved pipeline via the isolated decoder worker: source read once
    and hashed by the worker, decoded under the address-space ceiling and
    supervisor deadline, canonical W*H bytes plus the validated preprocessing
    record returned. Exact geometry; no resize. The supervisor read itself is
    bounded (R14-05): non-regular inputs are rejected before any read, at
    most MAX_SOURCE_BYTES+1 bytes ever enter root memory, and oversize
    sources fail admission here instead of inside the worker."""
    p = Path(path)
    m7.require(p.is_file(), f"source is not a regular file: {p}")
    with open(p, "rb") as fh:
        blob = fh.read(MAX_SOURCE_BYTES + 1)
    m7.require(len(blob) <= MAX_SOURCE_BYTES,
               f"source exceeds the {MAX_SOURCE_BYTES} B limit: {p}")
    result = _decoder().decode(blob, w, h, "exact")
    meta = json.loads(result.record_json)
    meta["source_path"] = str(p)
    return result.canonical, meta


def render_plane(values, ch, k, w, h, path):
    from PIL import Image
    plane = values[ch::k]
    lo, hi = min(plane), max(plane)
    span = (hi - lo) or 1
    pixels = bytes(int((v - lo) * 255 / span) for v in plane)
    scale = 8 if w <= 64 else 1
    Image.frombytes("L", (w, h), pixels).resize((w * scale, h * scale),
                                                Image.NEAREST).save(path)


def render_sobel(values, k, w, h, path):
    """Sobel magnitude map, display-only; D profiles carry Sobel X/Y at ch 1,2."""
    import math
    from PIL import Image
    sx, sy = values[1::k], values[2::k]
    mag = [min(1443, int(math.sqrt(a * a + b * b))) for a, b in zip(sx, sy)]
    lo, hi = min(mag), max(mag)
    span = (hi - lo) or 1
    pixels = bytes(int((v - lo) * 255 / span) for v in mag)
    scale = 8 if w <= 64 else 1
    Image.frombytes("L", (w, h), pixels).resize((w * scale, h * scale),
                                                Image.NEAREST).save(path)


def environment(clock_mhz):
    gov = None
    bogomips = None
    try:
        gov = Path("/sys/devices/system/cpu/cpu0/cpufreq/scaling_governor") \
            .read_text().strip()
    except OSError:
        pass
    try:
        for line in Path("/proc/cpuinfo").read_text().splitlines():
            if line.startswith("BogoMIPS"):
                bogomips = float(line.split(":", 1)[1])
                break
    except OSError:
        pass
    return {"kernel": platform.release(), "machine": platform.machine(),
            "python": platform.python_version(), "cpu_governor": gov,
            "bogomips": bogomips,
            "fclk0_hz": int(clock_mhz * 1_000_000),
            "fclk0_source": "release manifest; not a live measurement"}


def counter_snapshot(accel):
    return {name: m7.read32(accel, addr) for name, addr in (
        ("input_accept", m7.REG_INPUT_ACCEPT_BYTES),
        ("input_consumed", m7.REG_INPUT_CONSUMED_BYTES),
        ("core_accept", m7.REG_CORE_ACCEPT_PIXELS),
        ("output_accept", m7.REG_OUTPUT_ACCEPT_BYTES),
        ("status", m7.REG_STATUS),
        ("error_flags", m7.REG_ERROR_FLAGS))}


def new_record(profile, hw, image_tag, catalog=None):
    rel = (catalog or {}).get("releases", {}).get(profile) if catalog else None
    clock_mhz = hw["clock_mhz"]
    return {
        "schema": "m8-run-record/3",
        "run_id": None,
        "outcome": None,
        "started_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "command": " ".join(sys.argv),
        "profile": {"name": profile, "release_id": profile,
                    "shape_id": (rel or {}).get("shape_id"),
                    "build_id_ascii": hw["build_id_ascii"],
                    "build_id_hex": hw["build_id_hex"], "N": hw["kernel_n"],
                    "K": hw["channels_k"], "W": hw["image_w"], "H": hw["image_h"],
                    "tx_bytes": hw["expected_input_bytes"],
                    "rx_bytes": hw["expected_output_bytes"]},
        "image_tag": image_tag,
        "input": {},
        "parameters": {},
        "switch": {},
        "verification": {},
        "cleanup": {},
        "frames": [],
        "timings": {"scope": "hw_ms = host-clock interval from MM2S length "
                            "release to completion-poll success (includes "
                            "polling); wall_ms = whole run_frame call; "
                            "neither is a hardware cycle count; declared "
                            f"fabric clock {clock_mhz} MHz"},
        "previews": [],
        "versions": {"m8_cli_md5": file_md5(Path(__file__)),
                     "m7_switch_md5": file_md5(m7.__file__)},
        "environment": environment(clock_mhz),
        "archive_root": None,
        "failure": None,
    }


def file_sha256(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def parameter_identity(profile):
    """Content identity of the admitted parameter bundle (M8-07 partial):
    the channel config and every kernel mem file the manager will load."""
    d = m7.BASE / profile
    out = {"channel_config_sha256": file_sha256(d / "channel_config.json"),
           "weights": {}}
    for f in sorted(d.glob("kernel_*.mem")):
        out["weights"][f.name] = file_sha256(f)
    return out


def write_record(run_dir, rec):
    """Atomic publication: temp file + rename, so an interrupted write can
    never leave a truncated record.json (M8-04)."""
    tmp = run_dir / "record.json.tmp"
    tmp.write_text(json.dumps(rec, indent=2) + "\n")
    os.replace(tmp, run_dir / "record.json")
    chown_tree(run_dir)


def finalize_run(rec, ctx, run_dir):
    """Shared finalization for every hardware mode (R14-02): cleanup runs
    first and demotes a PASS/UNVERIFIED outcome on failure, the record is
    always persisted atomically, and the ownership lock is released
    unconditionally BEFORE anything re-raises - a KeyboardInterrupt raised
    inside cleanup or persistence must never leave the lock held for an
    embedding caller. Cleanup or persistence failure re-raises after the
    unlock, so the invocation exits nonzero and no terminal PASS line is
    printed for a degraded run. Returns only for a run that ended, cleaned
    up, and was durably archived."""
    failure = None
    try:
        m7.safe_cleanup(ctx)
        rec["cleanup"] = {"ok": True}
    except BaseException as cexc:
        failure = cexc
        rec["cleanup"] = {"ok": False, "error": repr(cexc)}
        if rec["outcome"] in ("PASS", "UNVERIFIED"):
            rec["outcome"] = "FAILED"
    persisted = True
    try:
        write_record(run_dir, rec)
    except BaseException as pexc:
        persisted = False
        rec["persistence_error"] = repr(pexc)
        print(f"M8: record persistence failed: {pexc}", flush=True)
        if failure is None:
            failure = pexc
    m7.release_lock()
    if failure is not None:
        raise failure
    return rec


def cmd_run(args):
    m7.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    catalog_doc = json.loads((m7.BASE / "m7_profiles.json").read_text())
    catalog = catalog_doc["profiles"]
    m7.require(args.profile in catalog, f"unknown profile {args.profile}")
    anchors = json.loads((m7.BASE / "anchors_m7.json").read_text())
    hw = json.loads((m7.BASE / f"hardware_{args.profile}.json").read_text())["accelerator"]
    n, k, w, h = hw["kernel_n"], hw["channels_k"], hw["image_w"], hw["image_h"]

    image_tag = Path(args.image).stem if args.image else "library_alley_cat"
    rec = new_record(args.profile, hw, image_tag, catalog_doc)
    root, root_name = archive_root()
    rec["archive_root"] = root_name
    run_dir = allocate_run_dir(root, time.strftime("%Y%m%dT%H%M%SZ",
                                                   time.gmtime())
                               + f"-{args.profile}-{image_tag}")
    rec["run_id"] = run_dir.name

    m7.require(args.frames >= 1, "--frames must be >= 1")

    m7.acquire_lock()
    ctx = None
    t_start = time.perf_counter()
    try:
        rec["catalog_sha256"] = file_sha256(m7.BASE / "m7_profiles.json")
        rec["anchors_sha256"] = file_sha256(m7.BASE / "anchors_m7.json")
        info = m7.Path("/sys/class/u-dma-buf/udmabuf0")
        ctx = {"phys": int((info / "phys_addr").read_text(), 0),
               "buffer_size": int((info / "size").read_text(), 0),
               "anchors": anchors, "handles": None, "digests": []}

        # --- admission BEFORE any hardware mutation (M8-02/M8-06) ---------
        channels, pbundle = m7.load_params(args.profile, n, k,   # read-only files
                                           hw_bias_width=hw["bias_width"])
        rec["parameters"] = parameter_identity(args.profile)
        rec["parameters"]["bundle_sha256"] = pbundle
        t0 = time.perf_counter()
        if args.image:
            raw, meta = load_image_exact(args.image, w, h)
            padded = pad_bytes(raw, n, w, h)
            canonical = raw
            library_mode = False
        else:
            padded = m7.load_input(n, w, h)
            canonical = unpad(padded, n, w, h)
            meta = {"source_path": "library:alley_cat_s_000013",
                    "source_sha256": "200f5baa120d957838037c7e28052ac998e82ddd94a"
                                     "ef937173e37c3dfb470b0",
                    "geometry_policy": "exact" if (w, h) == (32, 32) else
                                       "resize_exact(LANCZOS, recorded D640)"}
            library_mode = True
        rec["input"] = {**meta,
                        "canonical_sha256": hashlib.sha256(canonical).hexdigest(),
                        "padded_tx_sha256": hashlib.sha256(padded).hexdigest()}
        rec["timings"]["preprocess_s"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        if library_mode:
            expected = None
            anchor = anchors.get(args.profile, {}).get("output_sha256")
            m7.require(anchor, f"{args.profile}: no golden anchor")
            rec["verification"] = {"mode": "anchor_sha256", "anchor": anchor}
        elif w * h * k <= m7.REF_POSITION_LIMIT or args.reference:
            expected = m7.make_expected(padded, n, w, h, channels)
            rec["verification"] = {"mode": "exact_reference"}
        else:
            expected = None
            rec["verification"] = {
                "mode": "sha_only", "status": "UNVERIFIED",
                "note": f"{w * h * k} positions > {m7.REF_POSITION_LIMIT}; "
                        "output SHA is recorded but nothing checks it - "
                        "pass --reference for exact compare"}
        rec["timings"]["reference_s"] = time.perf_counter() - t0

        estimate = args.frames * (hw["expected_output_bytes"] + 4096) + 1048576
        if args.previews:
            estimate += k * w * h * (8 if w <= 64 else 1)
        storage_admission(root, estimate)

        # --- exclusive-owner switch (may reload the PL) --------------------
        t0 = time.perf_counter()
        reloaded = m7.switch_to(args.profile, catalog_doc, anchors, ctx)
        rec["switch"] = {"reloaded": reloaded, "wall_s": time.perf_counter() - t0}
        dma, accel, buf_fd, _fds = ctx["handles"]
        layout = m7.compute_layout(hw["expected_input_bytes"],
                                   hw["expected_output_bytes"],
                                   ctx["buffer_size"])

        # --- frames ---------------------------------------------------------
        last_values = None
        for i in range(args.frames):
            w0 = time.perf_counter()
            values, mismatches, sha, hw_ms = m7.run_frame(
                dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
            wall = time.perf_counter() - w0
            if expected is not None:
                m7.require(mismatches == 0, f"frame {i + 1}: {mismatches} mismatches")
            if library_mode:
                m7.require(sha == rec["verification"]["anchor"],
                           f"frame {i + 1}: output sha {sha[:16]} != anchor")
            rec["frames"].append({"index": i + 1, "sha256": sha,
                                  "mismatches": (mismatches
                                                 if expected is not None else None),
                                  "hw_ms": hw_ms * 1000.0, "wall_ms": wall * 1000.0})
            (run_dir / f"frame_{i + 1:03d}.s16le").write_bytes(
                struct.pack(f"<{len(values)}h", *values))
            last_values = values
        rec["timings"]["frames_total_s"] = \
            sum(f["wall_ms"] for f in rec["frames"]) / 1000.0
        rec["counters_final"] = counter_snapshot(accel)

        # Previews: display normalization only, never used for comparison.
        if args.previews and last_values is not None:
            t0 = time.perf_counter()
            previews = []
            for ch in range(k):
                name = f"preview_ch{ch}.png"
                render_plane(last_values, ch, k, w, h, run_dir / name)
                previews.append(name)
            if args.profile in D_PROFILES:
                render_sobel(last_values, k, w, h, run_dir / "preview_sobel_mag.png")
                previews.append("preview_sobel_mag.png")
            rec["previews"] = previews
            rec["timings"]["previews_s"] = time.perf_counter() - t0

        rec["outcome"] = ("UNVERIFIED"
                          if rec["verification"]["mode"] == "sha_only" else "PASS")
    except BaseException as exc:
        rec["outcome"] = ("CANCELLED" if isinstance(exc, KeyboardInterrupt)
                          else "FAILED")
        rec["failure"] = {"type": type(exc).__name__, "message": str(exc)}
        if ctx and ctx.get("handles"):
            try:
                dma = ctx["handles"][0]
                rec["failure"]["dma_mm2s_sr"] = m7.read32(dma, 0x04)
                rec["failure"]["dma_s2mm_sr"] = m7.read32(dma, 0x34)
            except Exception:
                pass
        raise
    finally:
        rec["timings"]["total_wall_s"] = time.perf_counter() - t_start
        finalize_run(rec, ctx, run_dir)
        if rec["outcome"] == "PASS":
            lat = [f["hw_ms"] for f in rec["frames"]]
            print(f"M8 RUN {rec['run_id']}: PASS ({args.frames} frames, "
                  f"median {statistics.median(lat):.3f} ms) -> "
                  f"{rec['archive_root']}/{rec['run_id']}", flush=True)
        elif rec["outcome"] == "UNVERIFIED":
            print(f"M8 RUN {rec['run_id']}: UNVERIFIED ({args.frames} frames "
                  f"executed, output sha recorded, no independent numerical "
                  f"check) -> {rec['archive_root']}/{rec['run_id']}", flush=True)


def cmd_soak(args):
    """Baseline soak (M9): N frames under one activation. Library-anchor mode
    verifies every frame against the golden anchor SHA-256; image mode
    verifies every frame value-by-value against the exact reference computed
    once from the worker-decoded canonical bytes (32x32 profiles only)."""
    m7.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    catalog_doc = json.loads((m7.BASE / "m7_profiles.json").read_text())
    catalog = catalog_doc["profiles"]
    m7.require(args.profile in catalog, f"unknown profile {args.profile}")
    anchors = json.loads((m7.BASE / "anchors_m7.json").read_text())
    hw = json.loads((m7.BASE / f"hardware_{args.profile}.json").read_text())["accelerator"]
    n, k, w, h = hw["kernel_n"], hw["channels_k"], hw["image_w"], hw["image_h"]

    image_tag = Path(args.image).stem if args.image else "library_alley_cat"
    rec = new_record(args.profile, hw, image_tag, catalog_doc)
    rec["soak"] = {"frames": args.frames}
    root, root_name = archive_root()
    rec["archive_root"] = root_name
    run_dir = allocate_run_dir(root, time.strftime("%Y%m%dT%H%M%SZ",
                                                   time.gmtime())
                               + f"-soak{args.frames}-{args.profile}-{image_tag}")
    rec["run_id"] = run_dir.name
    m7.require(args.frames >= 1, "--frames must be >= 1")

    m7.acquire_lock()
    ctx = None
    t_start = time.perf_counter()
    try:
        info = m7.Path("/sys/class/u-dma-buf/udmabuf0")
        ctx = {"phys": int((info / "phys_addr").read_text(), 0),
               "buffer_size": int((info / "size").read_text(), 0),
               "anchors": anchors, "handles": None, "digests": []}
        channels, pbundle = m7.load_params(args.profile, n, k,
                                           hw_bias_width=hw["bias_width"])
        rec["parameters"] = {**parameter_identity(args.profile),
                             "bundle_sha256": pbundle}
        storage_admission(root, args.frames * 4096 + 1048576)

        # --- admit the input and build the reference BEFORE any hardware
        # mutation (R14-03: a bad image must never reach switch_to) --------
        t0 = time.perf_counter()
        if args.image:
            m7.require(w * h * k <= m7.REF_POSITION_LIMIT,
                       f"image soak needs an exact-reference profile "
                       f"({w}*{h}*{k} positions > {m7.REF_POSITION_LIMIT}); "
                       "use the library-anchor soak for this profile")
            raw, meta = load_image_exact(args.image, w, h)
            padded = pad_bytes(raw, n, w, h)
            expected = m7.make_expected(padded, n, w, h, channels)
            rec["input"] = {**meta,
                            "canonical_sha256": hashlib.sha256(raw).hexdigest(),
                            "padded_tx_sha256": hashlib.sha256(padded).hexdigest()}
            rec["verification"] = {"mode": "exact_reference"}
        else:
            padded = m7.load_input(n, w, h)
            expected = None
            anchor = anchors.get(args.profile, {}).get("output_sha256")
            m7.require(anchor, f"{args.profile}: no golden anchor")
            rec["input"] = {"source_path": "library:alley_cat_s_000013",
                            "padded_tx_sha256": hashlib.sha256(padded).hexdigest()}
            rec["verification"] = {"mode": "anchor_sha256", "anchor": anchor}
        rec["timings"]["preprocess_s"] = time.perf_counter() - t0

        t0 = time.perf_counter()
        reloaded = m7.switch_to(args.profile, catalog_doc, anchors, ctx)
        rec["switch"] = {"reloaded": reloaded, "wall_s": time.perf_counter() - t0}
        dma, accel, buf_fd, _fds = ctx["handles"]
        layout = m7.compute_layout(hw["expected_input_bytes"],
                                   hw["expected_output_bytes"],
                                   ctx["buffer_size"])

        hw_ms, wall_ms = [], []
        for i in range(args.frames):
            w0 = time.perf_counter()
            values, mismatches, sha, ms = m7.run_frame(
                dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
            wall_ms.append((time.perf_counter() - w0) * 1000.0)
            hw_ms.append(ms * 1000.0)
            if expected is not None:
                m7.require(mismatches == 0,
                           f"frame {i + 1}: {mismatches} mismatches")
            else:
                m7.require(sha == anchor,
                           f"frame {i + 1}: output sha {sha[:16]} != anchor")
            rec["frames"].append({"index": i + 1, "sha256": sha,
                                  "mismatches": (mismatches if expected
                                                 is not None else None),
                                  "hw_ms": hw_ms[-1], "wall_ms": wall_ms[-1]})
            if (i + 1) % 25 == 0:
                print(f"  {i + 1}/{args.frames} soak frames bit-exact", flush=True)

        def stats(xs):
            xs = sorted(xs)
            p95 = xs[min(len(xs) - 1, int(round(0.95 * len(xs) + 0.499)) - 1)]
            return {"median": statistics.median(xs), "min": xs[0],
                    "max": xs[-1], "p95": p95}
        rec["timings"]["hw_ms"] = stats(hw_ms)
        rec["timings"]["wall_ms"] = stats(wall_ms)
        rec["counters_final"] = counter_snapshot(accel)
        rec["outcome"] = "PASS"
    except BaseException as exc:
        rec["outcome"] = ("CANCELLED" if isinstance(exc, KeyboardInterrupt)
                          else "FAILED")
        rec["failure"] = {"type": type(exc).__name__, "message": str(exc)}
        raise
    finally:
        rec["timings"]["total_wall_s"] = time.perf_counter() - t_start
        finalize_run(rec, ctx, run_dir)
        if rec["outcome"] == "PASS":
            s = rec["timings"]["hw_ms"]
            print(f"M8 SOAK {rec['run_id']}: PASS ({args.frames} frames, "
                  f"median {s['median']:.3f} ms / p95 {s['p95']:.3f}) -> "
                  f"{rec['archive_root']}/{rec['run_id']}", flush=True)


def cmd_extremes(args):
    """M5-grade per-profile extremes (E2): all-zero and all-255 stimulus
    frames under the profile's admitted parameters, a temporary saturation
    parameter stimulus (weights ±full-scale, biases at the signed-24
    endpoints, shift 0 — proving genuine ±32768 saturation), then explicit
    reinstallation of the canonical bundle with an anchor-checked activation
    frame (M1_ACTIVATION_LIFECYCLE: requested parameters reinstalled and
    revalidated after procedural tests). Every frame is verified against the
    exact on-board reference with zero tolerance."""
    m7.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    catalog_doc = json.loads((m7.BASE / "m7_profiles.json").read_text())
    catalog = catalog_doc["profiles"]
    m7.require(args.profile in catalog, f"unknown profile {args.profile}")
    anchors = json.loads((m7.BASE / "anchors_m7.json").read_text())
    hw = json.loads((m7.BASE / f"hardware_{args.profile}.json").read_text())["accelerator"]
    n, k, w, h = hw["kernel_n"], hw["channels_k"], hw["image_w"], hw["image_h"]

    rec = new_record(args.profile, hw, "extremes")
    rec["extremes"] = {"stimuli": ["all_zero", "all_255", "saturation_params",
                                   "reinstall_activation"]}
    root, root_name = archive_root()
    rec["archive_root"] = root_name
    run_dir = allocate_run_dir(root, time.strftime("%Y%m%dT%H%M%SZ",
                                                   time.gmtime())
                               + f"-extremes-{args.profile}")
    rec["run_id"] = run_dir.name

    m7.acquire_lock()
    ctx = None
    t_start = time.perf_counter()
    try:
        info = m7.Path("/sys/class/u-dma-buf/udmabuf0")
        ctx = {"phys": int((info / "phys_addr").read_text(), 0),
               "buffer_size": int((info / "size").read_text(), 0),
               "anchors": anchors, "handles": None, "digests": []}
        channels, pbundle = m7.load_params(args.profile, n, k,
                                           hw_bias_width=hw["bias_width"])
        rec["parameters"] = {**parameter_identity(args.profile),
                             "bundle_sha256": pbundle}
        storage_admission(root, 8 * (hw["expected_output_bytes"] + 4096)
                          + 1048576)

        t0 = time.perf_counter()
        reloaded = m7.switch_to(args.profile, catalog_doc, anchors, ctx)
        rec["switch"] = {"reloaded": reloaded, "wall_s": time.perf_counter() - t0}
        dma, accel, buf_fd, _fds = ctx["handles"]
        layout = m7.compute_layout(hw["expected_input_bytes"],
                                   hw["expected_output_bytes"],
                                   ctx["buffer_size"])
        anchor = anchors.get(args.profile, {}).get("output_sha256")
        m7.require(anchor, f"{args.profile}: no golden anchor")

        tx_bytes = hw["expected_input_bytes"]
        stimuli = (("all_zero", bytes(tx_bytes)),
                   ("all_255", b"\xff" * tx_bytes))
        for tag, padded in stimuli:
            expected = m7.make_expected(padded, n, w, h, channels)
            w0 = time.perf_counter()
            values, mismatches, sha, hw_ms = m7.run_frame(
                dma, accel, buf_fd, ctx["phys"], layout, padded, expected, k)
            m7.require(mismatches == 0,
                       f"{tag}: {mismatches} mismatches vs exact reference")
            rec["frames"].append({"stimulus": tag, "sha256": sha,
                                  "mismatches": mismatches,
                                  "hw_ms": hw_ms * 1000.0,
                                  "wall_ms": (time.perf_counter() - w0) * 1000.0})
            (run_dir / f"frame_{tag}.s16le").write_bytes(
                struct.pack(f"<{len(values)}h", *values))

        # Temporary saturation parameters: even channels saturate +32767
        # (weights +127, bias at the signed-24 maximum, shift 0), odd channels
        # saturate -32768 (weights -128, bias at the signed-24 minimum).
        sat_channels = []
        for c in range(k):
            if c % 2 == 0:
                sat_channels.append(([127] * (n * n), (1 << 23) - 1, 0, 0))
            else:
                sat_channels.append(([-128] * (n * n), -(1 << 23), 0, 0))
        m7.program_params_accel(accel, n, sat_channels)
        sat_expected = m7.make_expected(stimuli[1][1], n, w, h, sat_channels)
        values, mismatches, sha, hw_ms = m7.run_frame(
            dma, accel, buf_fd, ctx["phys"], layout, stimuli[1][1],
            sat_expected, k)
        m7.require(mismatches == 0,
                   f"saturation_params: {mismatches} mismatches")
        m7.require(32767 in values and -32768 in values,
                   "saturation stimulus did not exercise both rails")
        rec["frames"].append({"stimulus": "saturation_params", "sha256": sha,
                              "mismatches": mismatches,
                              "hw_ms": hw_ms * 1000.0,
                              "wall_ms": 0.0})
        (run_dir / "frame_saturation_params.s16le").write_bytes(
            struct.pack(f"<{len(values)}h", *values))

        # Reinstall the admitted canonical bundle and revalidate the requested
        # model with an anchor-checked activation frame.
        m7.program_params_accel(accel, n, channels)
        padded = m7.load_input(n, w, h)
        values, mismatches, sha, hw_ms = m7.run_frame(
            dma, accel, buf_fd, ctx["phys"], layout, padded, None, k)
        m7.require(sha == anchor,
                   f"reinstall_activation: output sha {sha[:16]} != anchor")
        rec["frames"].append({"stimulus": "reinstall_activation",
                              "sha256": sha, "mismatches": 0,
                              "hw_ms": hw_ms * 1000.0, "wall_ms": 0.0})
        rec["counters_final"] = counter_snapshot(accel)
        rec["outcome"] = "PASS"
    except BaseException as exc:
        rec["outcome"] = ("CANCELLED" if isinstance(exc, KeyboardInterrupt)
                          else "FAILED")
        rec["failure"] = {"type": type(exc).__name__, "message": str(exc)}
        raise
    finally:
        rec["timings"]["total_wall_s"] = time.perf_counter() - t_start
        finalize_run(rec, ctx, run_dir)
        if rec["outcome"] == "PASS":
            print(f"M8 EXTREMES {rec['run_id']}: PASS ({len(rec['frames'])} "
                  f"verified stimulus frames) -> "
                  f"{rec['archive_root']}/{rec['run_id']}", flush=True)


def cmd_benchmark(args):
    m7.require(fb.platform.machine() == "armv7l", "Run on the ZedBoard")
    catalog_doc = json.loads((m7.BASE / "m7_profiles.json").read_text())
    catalog = catalog_doc["profiles"]
    m7.require(args.profile in catalog, f"unknown profile {args.profile}")
    anchors = json.loads((m7.BASE / "anchors_m7.json").read_text())
    hw = json.loads((m7.BASE / f"hardware_{args.profile}.json").read_text())["accelerator"]
    n, k, w, h = hw["kernel_n"], hw["channels_k"], hw["image_w"], hw["image_h"]

    rec = new_record(args.profile, hw, "library_alley_cat")
    rec["benchmark"] = {"frames": args.frames, "warmup": args.warmup}
    root, root_name = archive_root()
    rec["archive_root"] = root_name
    run_dir = allocate_run_dir(root, time.strftime("%Y%m%dT%H%M%SZ",
                                                   time.gmtime())
                               + f"-bench-{args.profile}")
    rec["run_id"] = run_dir.name
    m7.require(args.frames >= 1 and args.warmup >= 0,
               "--frames >= 1 and --warmup >= 0 required")

    m7.acquire_lock()
    ctx = None
    t_start = time.perf_counter()
    try:
        info = m7.Path("/sys/class/u-dma-buf/udmabuf0")
        ctx = {"phys": int((info / "phys_addr").read_text(), 0),
               "buffer_size": int((info / "size").read_text(), 0),
               "anchors": anchors, "handles": None, "digests": []}
        padded = m7.load_input(n, w, h)
        rec["timings"]["preprocess_s"] = 0.0
        storage_admission(root, 1048576)   # record only; no frame payloads

        t0 = time.perf_counter()
        reloaded = m7.switch_to(args.profile, catalog_doc, anchors, ctx)
        rec["switch"] = {"reloaded": reloaded, "wall_s": time.perf_counter() - t0}
        dma, accel, buf_fd, _fds = ctx["handles"]
        layout = m7.compute_layout(hw["expected_input_bytes"],
                                   hw["expected_output_bytes"],
                                   ctx["buffer_size"])
        anchor = anchors.get(args.profile, {}).get("output_sha256")
        m7.require(anchor, f"{args.profile}: no golden anchor")
        rec["verification"] = {"mode": "anchor_sha256", "anchor": anchor}

        for i in range(args.warmup):
            _, _, sha, _ = m7.run_frame(dma, accel, buf_fd, ctx["phys"], layout,
                                        padded, None, k)
            m7.require(sha == anchor, f"warmup {i + 1}: sha mismatch")

        hw_ms, wall_ms = [], []
        for i in range(args.frames):
            w0 = time.perf_counter()
            _, _, sha, ms = m7.run_frame(dma, accel, buf_fd, ctx["phys"], layout,
                                         padded, None, k)
            wall_ms.append((time.perf_counter() - w0) * 1000.0)
            hw_ms.append(ms * 1000.0)
            m7.require(sha == anchor, f"frame {i + 1}: sha mismatch")
            rec["frames"].append({"index": i + 1, "sha256": sha,
                                  "mismatches": 0, "hw_ms": hw_ms[-1],
                                  "wall_ms": wall_ms[-1]})

        def stats(xs):
            xs = sorted(xs)
            p95 = xs[min(len(xs) - 1, int(round(0.95 * len(xs) + 0.499)) - 1)]
            return {"median": statistics.median(xs), "min": xs[0],
                    "max": xs[-1], "p95": p95}
        rec["timings"]["hw_ms"] = stats(hw_ms)
        rec["timings"]["wall_ms"] = stats(wall_ms)
        rec["timings"]["io_overhead_ms_median"] = \
            statistics.median(wall_ms) - statistics.median(hw_ms)
        rec["counters_final"] = counter_snapshot(accel)
        rec["outcome"] = "PASS"
    except BaseException as exc:
        rec["outcome"] = ("CANCELLED" if isinstance(exc, KeyboardInterrupt)
                          else "FAILED")
        rec["failure"] = {"type": type(exc).__name__, "message": str(exc)}
        raise
    finally:
        rec["timings"]["total_wall_s"] = time.perf_counter() - t_start
        finalize_run(rec, ctx, run_dir)
        if rec["outcome"] == "PASS":
            s = rec["timings"]["hw_ms"]
            print(f"M8 BENCH {rec['run_id']}: PASS ({args.frames} frames) "
                  f"hw median {s['median']:.3f} ms / p95 {s['p95']:.3f} / "
                  f"min {s['min']:.3f} / max {s['max']:.3f} | "
                  f"record: {rec['archive_root']}/{rec['run_id']}", flush=True)


def cmd_list(_args):
    root, root_name = archive_root()
    runs = sorted(p for p in root.iterdir() if (p / "record.json").is_file()) \
        if root.is_dir() else []
    print(f"archive: {root_name} ({len(runs)} runs)")
    for p in runs:
        try:
            rec = json.loads((p / "record.json").read_text())
        except Exception as exc:
            print(f"  {p.name}: UNREADABLE RECORD ({exc})")
            continue
        bench = " bench" if "benchmark" in rec else ""
        print(f"  {rec['run_id']}: {rec['outcome']} {rec['profile']['name']}"
              f"{bench} frames={len(rec['frames'])}")


def cmd_record(args):
    m7.require(re.fullmatch(r"[A-Za-z0-9._-]+", args.run_id) is not None
               and ".." not in args.run_id, "invalid run id")
    root, _ = archive_root()
    run_dir = (root / args.run_id).resolve()
    m7.require(str(run_dir.parent) == str(Path(root).resolve()),
               "run id escapes archive root")
    path = run_dir / "record.json"
    m7.require(path.is_file(), f"no record: {path}")
    print(path.read_text(), end="")


def main(argv=None):
    p = argparse.ArgumentParser(prog="m8_cli", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)

    r = sub.add_parser("run", help="switch + file-driven verified frames")
    r.add_argument("--profile", required=True)
    r.add_argument("--frames", type=int, default=3)
    r.add_argument("--image", help="exact-geometry grayscale-able PNG/JPEG")
    r.add_argument("--previews", action="store_true",
                   help="render display-only channel planes (+ Sobel mag on D)")
    r.add_argument("--reference", action="store_true",
                   help="force exact reference above the position limit")

    b = sub.add_parser("benchmark", help="measurement harness (anchor mode)")
    b.add_argument("--profile", required=True)
    b.add_argument("--frames", type=int, default=200)
    b.add_argument("--warmup", type=int, default=10)

    e = sub.add_parser("extremes", help="M5-grade per-profile extremes (E2)")
    e.add_argument("--profile", required=True)

    s = sub.add_parser("soak", help="baseline soak (M9), archived record")
    s.add_argument("--profile", required=True)
    s.add_argument("--frames", type=int, default=100)
    s.add_argument("--image", help="exact-geometry image (32x32 profiles only)")

    sub.add_parser("list", help="list archived runs")
    c = sub.add_parser("record", help="print one archived record")
    c.add_argument("run_id")

    args = p.parse_args(argv)
    {"run": cmd_run, "benchmark": cmd_benchmark, "extremes": cmd_extremes,
     "soak": cmd_soak, "list": cmd_list, "record": cmd_record}[args.cmd](args)


if __name__ == "__main__":
    main()
