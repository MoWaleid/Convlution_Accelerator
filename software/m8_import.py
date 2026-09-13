#!/usr/bin/env python3
"""M8 Phase B bundle importer: validated import of model/dataset bundles from
the FAT transport area (or any host path under test) into the ext4 library.

Contract sources: M1_BUNDLE_IDENTITY (immutable identity; same-identity
different-content is a collision), M1_FILE_CONTRACT (coefficient grammar,
channel core fields), M1_METADATA_PREPROCESSING (reduced rational scales,
preprocessing policy), M1_DEPLOYMENT_POLICY (bounds, staging, headroom,
protected retention). The importer never touches hardware, never mutates or
overwrites a published bundle, and writes its receipts outside bundle contents.

Usage:
  sudo python3 /home/petalinux/m8_import.py <transport.tar.gz>
  sudo python3 /home/petalinux/m8_import.py list

M8_IMPORT_ROOT overrides /var/lib/conv-lab (host mock tests only).
"""
import argparse
import json
import os
import sys
import tarfile
import time
import uuid
from pathlib import Path, PurePosixPath

sys.path.insert(0, "/home/petalinux")
from conv_lab.errors import AdmissionError            # noqa: E402
from conv_lab.strict import (array, boolean, coefficients, hex_string,  # noqa: E402
                             identity, integer, obj, parse_json, ratio,
                             require, sha256, string)

MAX_ARCHIVE = 33554432          # 32 MiB compressed transport
MAX_MEMBERS = 256
MAX_UNCOMPRESSED = 67108864     # 64 MiB extracted
HEADROOM = 536870912            # 512 MiB free after the reservation (policy)

_BASE = Path(os.environ.get("M8_IMPORT_ROOT", "/var/lib/conv-lab"))
STAGING = _BASE / "staging"
RECEIPTS = _BASE / "results" / "imports"
LIBRARY = _BASE / "library"
LOCK_FILE = _BASE / "import.lock"

_lock_fd = None
try:
    import fcntl
except ImportError:             # mock hosts only; the board is Linux
    fcntl = None


def acquire_lock():
    global _lock_fd
    require(_lock_fd is None, "import lock already held by this process")
    LOCK_FILE.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(LOCK_FILE, os.O_RDWR | os.O_CREAT, 0o600)
    if fcntl is not None:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:
            os.close(fd)
            raise AdmissionError(f"another import holds {LOCK_FILE}")
    os.write(fd, str(os.getpid()).encode())
    _lock_fd = fd


def release_lock():
    global _lock_fd
    if _lock_fd is not None:
        try:
            os.close(_lock_fd)
        finally:
            _lock_fd = None


def storage_admission(estimate):
    import shutil
    free = shutil.disk_usage(_BASE if _BASE.exists() else _BASE.parent).free
    require(free - estimate >= HEADROOM,
            f"insufficient storage headroom: {free} B free, estimate "
            f"{estimate} B, policy requires {HEADROOM} B after reservation")


def safe_extract(tgz_path, dest):
    """Bounded, traversal-safe extraction of regular files/directories only.
    Defense in depth: own member vetting plus tarfile's 'data' filter."""
    size = tgz_path.stat().st_size
    require(0 < size <= MAX_ARCHIVE, f"transport size {size} outside policy")
    with tarfile.open(tgz_path, "r:*") as tf:
        members = tf.getmembers()
        require(len(members) <= MAX_MEMBERS,
                f"{len(members)} members exceeds {MAX_MEMBERS}")
        total = 0
        for m in members:
            require(m.isreg() or m.isdir(), f"unsafe member type: {m.name}")
            parts = PurePosixPath(m.name).parts
            require(parts and not PurePosixPath(m.name).is_absolute()
                    and ".." not in parts and not m.name.startswith("/"),
                    f"unsafe member path: {m.name}")
            total += m.size
            require(total <= MAX_UNCOMPRESSED,
                    f"extracted size exceeds {MAX_UNCOMPRESSED}")
        tf.extractall(dest, members=members, filter="data")


def fileref(value, root):
    """Verified FileRef: safe bundle-relative path, hash over actual bytes,
    bytes returned so parsing consumes exactly the hashed content."""
    o = obj(value, "path sha256")
    p = string(o["path"])
    parts = PurePosixPath(p).parts
    require(parts and not p.startswith("/") and ".." not in parts
            and "\\" not in p, f"unsafe reference path: {p}")
    hex_string(o["sha256"])
    f = root / p
    require(f.is_file(), f"referenced file missing: {p}")
    data = f.read_bytes()
    require(sha256(data) == o["sha256"], f"hash mismatch: {p}")
    return {"path": p, "sha256": o["sha256"], "bytes": data}


def _abi(value):
    a = obj(value, "magic versions")
    require(string(a["magic"]) == "43564831", "unsupported ABI magic")
    versions = array(a["versions"], nonempty=True)
    seen = set()
    for v in versions:
        vo = obj(v, "major minor")
        seen.add((integer(vo["major"], 0, 65535),
                  integer(vo["minor"], 0, 65535)))
    require (1, 0) in seen, "ABI 1.0 must be declared"
    return seen


def _numerical(value):
    n = obj(value, "pixel_width weight_width output_width min_bias_width "
                   "relu_required")
    require(integer(n["pixel_width"], 1) == 8, "pixel width")
    require(integer(n["weight_width"], 1) == 8, "weight width")
    require(integer(n["output_width"], 1) == 16, "output width")
    bw = integer(n["min_bias_width"], 1, 32)
    relu_required = boolean(n["relu_required"])
    return bw, relu_required


def _channel_config(ref, root, n, k, min_bias_width, relu_required):
    cc = parse_json(ref["bytes"])
    obj(cc, "format_version input_scale channels")
    require(integer(cc["format_version"], 1) == 3, "channel_config format 3")
    ratio(cc["input_scale"])
    channels = array(cc["channels"], nonempty=True)
    require(len(channels) == k, f"expected {k} channels, got {len(channels)}")
    seen = set()
    any_relu = False
    for entry in channels:
        e = obj(entry, "channel weights_file bias_quantized shift relu_en "
                       "weight_scale")
        ch = integer(e["channel"], 0, k - 1)
        require(ch not in seen, f"duplicate channel {ch}")
        seen.add(ch)
        require(string(e["weights_file"]) == f"weights/kernel_ch{ch}.mem",
                "weights_file must be weights/kernel_ch<channel>.mem")
        low, high = -(1 << (min_bias_width - 1)), (1 << (min_bias_width - 1)) - 1
        integer(e["bias_quantized"], low, high)
        integer(e["shift"], 0, 31)
        relu = boolean(e["relu_en"])
        any_relu = any_relu or relu
        ratio(e["weight_scale"])
    require(seen == set(range(k)), "channel IDs must cover exactly 0..K-1")
    require(any_relu == relu_required,
            "compatibility.relu_required disagrees with channel ReLU enables")
    # Coefficient grammar over the hashed bytes of every declared weight file.
    for ch in range(k):
        data = (root / f"weights/kernel_ch{ch}.mem").read_bytes()
        coefficients(data, n)


def validate_model(root):
    manifest_name = "model.json"
    manifest_bytes = (root / manifest_name).read_bytes()
    m = parse_json(manifest_bytes)
    obj(m, "schema_version model_id release_version kind compatibility "
           "channel_config weights optional_assets")
    require(integer(m["schema_version"], 1) == 1, "schema_version 1")
    model_id = identity(m["model_id"])
    release = identity(m["release_version"])
    require(string(m["kind"]) in ("trained", "custom"), "model kind")
    comp = obj(m["compatibility"], "N K geometry geometry_policies numerical abi")
    n = integer(comp["N"], 1, 64)
    require(n % 2 == 1, "kernel N must be odd")
    k = integer(comp["K"], 1, 64)
    geometry = array(comp["geometry"], nonempty=True)
    pairs = set()
    for g in geometry:
        go = obj(g, "W H")
        pairs.add((integer(go["W"], 1, 4096), integer(go["H"], 1, 4096)))
    require(len(pairs) == len(geometry), "duplicate geometry entries")
    policies = array(comp["geometry_policies"], nonempty=True)
    require(all(string(p) in ("exact", "resize_exact") for p in policies)
            and len(set(policies)) == len(policies), "geometry policies")
    min_bias_width, relu_required = _numerical(comp["numerical"])
    _abi(comp["abi"])

    cc_ref = fileref(m["channel_config"], root)
    weight_refs = [fileref(w, root) for w in array(m["weights"], nonempty=True)]
    for o in array(m["optional_assets"], nonempty=False):
        fileref(o, root)
    require(sorted(w["path"] for w in weight_refs)
            == sorted(f"weights/kernel_ch{c}.mem" for c in range(k)),
            "weights inventory must cover every channel exactly once")
    _channel_config(cc_ref, root, n, k, min_bias_width, relu_required)
    return {"kind": "model", "id": model_id, "release": release,
            "manifest": manifest_name, "manifest_sha256": sha256(manifest_bytes)}


def validate_dataset(root):
    manifest_name = "dataset.json"
    manifest_bytes = (root / manifest_name).read_bytes()
    d = parse_json(manifest_bytes)
    obj(d, "schema_version dataset_id release_version images")
    require(integer(d["schema_version"], 1) == 1, "schema_version 1")
    dataset_id = identity(d["dataset_id"])
    release = identity(d["release_version"])
    images = array(d["images"], nonempty=True)
    ids = set()
    for e in images:
        eo = obj(e, "image_id source preprocessing")
        iid = identity(eo["image_id"])
        require(iid not in ids, f"duplicate image_id {iid}")
        ids.add(iid)
        fileref(eo["source"], root)
        pre = obj(eo["preprocessing"], "geometry_policy resize_filter")
        policy, filt = string(pre["geometry_policy"]), string(pre["resize_filter"])
        require((policy, filt) in (("exact", "NONE"), ("resize_exact", "LANCZOS")),
                f"inconsistent preprocessing policy: {policy}/{filt}")
    return {"kind": "dataset", "id": dataset_id, "release": release,
            "manifest": manifest_name, "manifest_sha256": sha256(manifest_bytes)}


def chown_tree(path):
    try:
        st = os.stat("/home/petalinux")
        for p in [path, *path.rglob("*")]:
            os.chown(p, st.st_uid, st.st_gid)
    except OSError:
        pass


def import_bundle(tgz_path):
    tgz_path = Path(tgz_path)
    require(tgz_path.is_file(), f"transport missing: {tgz_path}")
    storage_admission(tgz_path.stat().st_size * 3 + (1 << 20))
    STAGING.mkdir(parents=True, exist_ok=True)
    RECEIPTS.mkdir(parents=True, exist_ok=True)
    staged = STAGING / uuid.uuid4().hex
    staged.mkdir()
    outcome = "imported"
    try:
        safe_extract(tgz_path, staged)
        names = {p.name for p in staged.iterdir()}
        if "hardware.json" in names:
            raise AdmissionError(
                "hardware bundle import is not supported in this release")
        if "model.json" in names and "dataset.json" in names:
            raise AdmissionError("both model.json and dataset.json at bundle root")
        if "model.json" in names:
            info = validate_model(staged)
        elif "dataset.json" in names:
            info = validate_dataset(staged)
        else:
            raise AdmissionError("no model.json or dataset.json at bundle root")

        group = "models" if info["kind"] == "model" else "datasets"
        target = LIBRARY / group / info["id"] / info["release"]
        if target.exists():
            existing = (target / info["manifest"]).read_bytes()
            if sha256(existing) == info["manifest_sha256"]:
                outcome = "already-imported"
            else:
                raise AdmissionError(
                    f"identity collision: {info['id']}/{info['release']} "
                    "already exists with different content")
        else:
            target.parent.mkdir(parents=True, exist_ok=True)
            os.replace(staged, target)     # atomic same-filesystem move
        chown_tree(target)

        receipt = {"schema": "m8-import-receipt/1",
                   "outcome": outcome,
                   "transport": str(tgz_path),
                   "transport_sha256": sha256(tgz_path.read_bytes()),
                   "kind": info["kind"], "id": info["id"],
                   "release": info["release"],
                   "manifest": info["manifest"],
                   "manifest_sha256": info["manifest_sha256"],
                   "target": str(target),
                   "utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
        rpath = RECEIPTS / (time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
                            + f"-{info['kind']}-{info['id']}-{info['release']}.json")
        rpath.write_text(json.dumps(receipt, indent=2) + "\n")
        chown_tree(rpath)
        return receipt
    finally:
        if staged.exists():
            import shutil
            shutil.rmtree(staged, ignore_errors=True)


def cmd_import(args):
    acquire_lock()
    try:
        receipt = import_bundle(args.transport)
        print(f"M8 IMPORT {receipt['outcome']}: {receipt['kind']} "
              f"{receipt['id']}/{receipt['release']} "
              f"(manifest {receipt['manifest_sha256'][:16]}) -> {receipt['target']}")
    finally:
        release_lock()


def cmd_list(_args):
    for group in ("models", "datasets"):
        base = LIBRARY / group
        if not base.is_dir():
            continue
        for idir in sorted(base.iterdir()):
            for rdir in sorted(idir.iterdir()):
                manifest = rdir / ("model.json" if group == "models"
                                   else "dataset.json")
                if manifest.is_file():
                    print(f"{group} {idir.name}/{rdir.name} "
                          f"manifest {sha256(manifest.read_bytes())[:16]}")


def main(argv=None):
    p = argparse.ArgumentParser(prog="m8_import", description=__doc__)
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("import", help="import a transport archive")
    i.add_argument("transport")
    sub.add_parser("list", help="list imported bundles")
    args = p.parse_args(argv)
    {"import": cmd_import, "list": cmd_list}[args.cmd](args)


if __name__ == "__main__":
    main()
