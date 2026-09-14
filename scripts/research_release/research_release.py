#!/usr/bin/env python3
"""Research-line release driver (M10 Gate 1, D3).

Discipline layered on the adapted fresh-project Vivado flow
(research_build.tcl):
  - the build spec (builds/<ID>.spec.tcl) is cross-checked against the
    catalog's `releases` entry (shape_id + build_id_hex) before anything runs;
  - config_pkg.vhd is rendered into the build tree from the repo template
    by replacing each selected-profile constant exactly once; the repo
    template is never mutated;
  - after the build, every source and artifact is hashed into
    work/research_<ID>/artifacts/build_manifest.json (IP-08).

Subcommands:
  check <ID>      validate spec vs catalog + source presence; print hashes
  verify-render <ID> prove the prepared config is the deterministic spec render
  build <ID>      check + render + run Vivado batch + manifest
  prepare <ID>    check + render only (then run research_build.tcl yourself,
                  e.g. from the Vivado GUI Tcl console), then `manifest <ID>`
  manifest <ID>   hash sources + artifacts into build_manifest.json

The spec files are Tcl (`set spec(key) value`) so research_build.tcl can
source them directly; this driver parses the same controlled format.
"""
import argparse
import hashlib
import json
import re
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SPEC_KEYS = ("release_id", "shape_id", "n", "k", "w", "h", "build_id_hex",
             "clock_mhz", "profile", "render_config_pkg", "sources")
CONFIG_PKG = ROOT / "Convlution_Accelerator.srcs/sources_1/new/config_pkg.vhd"
CATALOG = ROOT / "profiles/m7_profiles.json"
BUILD_TCL = ROOT / "scripts/research_release/research_build.tcl"
BLOCK_DESIGN = ROOT / (
    "Convlution_Accelerator.srcs/sources_1/bd/accelerator_dma/"
    "accelerator_dma.bd"
)
BOARD_XDC = ROOT / "Zedboard-Master.xdc"


def spec_path(release_id):
    return Path(__file__).resolve().parent / "builds" / f"{release_id}.spec.tcl"


def parse_spec(release_id):
    text = spec_path(release_id).read_text()
    spec = {}
    for m in re.finditer(r"^set spec\((\w+)\)\s+(.+?)\s*$", text, re.M):
        key, val = m.group(1), m.group(2)
        if val.startswith("{") and val.endswith("}"):
            inner = val[1:-1].split()
            val = inner[0] if len(inner) == 1 else inner
        spec[key] = val
    missing = [k for k in SPEC_KEYS if k not in spec]
    if missing:
        raise RuntimeError(f"spec missing keys: {missing}")
    return spec


def load_catalog():
    return json.loads(CATALOG.read_text())


def crosscheck(spec, catalog):
    """GLM-F3: the spec is bound to the catalog on identity AND numerical
    geometry. A spec that renders different N/K/W/H than the catalog profile
    must be rejected before any render or Vivado invocation."""
    rel = (catalog.get("releases") or {}).get(spec["release_id"])
    if rel is None:
        raise RuntimeError(f"{spec['release_id']}: no releases entry in catalog")
    prof = (catalog.get("profiles") or {}).get(spec["release_id"])
    if prof is None:
        raise RuntimeError(f"{spec['release_id']}: no profiles entry in catalog")
    if str(spec["profile"]) != str(spec["release_id"]):
        raise RuntimeError(f"{spec['release_id']}: spec profile {spec['profile']!r} "
                           f"!= release id")
    for key, cat_key in (("n", "N"), ("k", "K"), ("w", "W"), ("h", "H")):
        if int(spec[key]) != int(prof[cat_key]):
            raise RuntimeError(f"{spec['release_id']}: spec {key}={spec[key]} "
                               f"!= catalog profiles {cat_key}={prof[cat_key]}")
    canonical_shape = (f"N{int(spec['n'])}K{int(spec['k'])}"
                       f"W{int(spec['w'])}H{int(spec['h'])}-CVH1")
    if rel["shape_id"] != spec["shape_id"]:
        raise RuntimeError(f"{spec['release_id']}: spec shape {spec['shape_id']} "
                           f"!= catalog {rel['shape_id']}")
    if spec["shape_id"] != canonical_shape:
        raise RuntimeError(f"{spec['release_id']}: shape {spec['shape_id']} is not "
                           f"the canonical {canonical_shape} for the bound geometry")
    if str(prof["build_id"]) != str(rel["build_id_hex"]) or \
            str(rel["build_id_hex"]) != str(spec["build_id_hex"]):
        raise RuntimeError(f"{spec['release_id']}: profile/release/spec build IDs "
                           f"disagree")
    if str(spec["release_id"]).endswith("_CFGLUT125") and \
            int(spec["clock_mhz"]) != 125:
        raise RuntimeError(f"{spec['release_id']}: CFGLUT125 releases run at "
                           f"125 MHz, spec says {spec['clock_mhz']}")
    return rel


def out_dir(release_id):
    return ROOT / "work" / f"research_{release_id}"


def render_config_text(spec):
    template = CONFIG_PKG.read_text()
    text = template

    def replace_one(label, pattern, replacement):
        nonlocal text
        text, count = re.subn(pattern, replacement, text, flags=re.M)
        if count != 1:
            raise RuntimeError(
                f"config_pkg template: expected exactly one {label}, "
                f"replaced {count}"
            )

    replace_one(
        "CFG_PROFILE",
        r'^(\s*constant CFG_PROFILE\s*:\s*string\s*:=\s*)"[^"]*"\s*;',
        rf'\g<1>"{spec["profile"]}";',
    )
    replace_one(
        "CFG_BUILD_ID",
        r'^(\s*constant CFG_BUILD_ID\s*:\s*std_logic_vector\s*'
        r'\(127 downto 0\)\s*:=\s*)x"[0-9A-Fa-f]{32}"\s*;',
        rf'\g<1>x"{spec["build_id_hex"]}";',
    )
    for label, value in (
        ("CFG_K", spec["k"]),
        ("CFG_N", spec["n"]),
        ("CFG_UNPADDED_WIDTH", spec["w"]),
        ("CFG_UNPADDED_HEIGHT", spec["h"]),
    ):
        replace_one(
            label,
            rf'^(\s*constant {label}\s*:\s*integer\s*:=\s*)\d+\s*;',
            rf'\g<1>{value};',
        )

    return text


def render_config_pkg(spec, dest):
    text = render_config_text(spec)
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, newline="\n")


def verify_rendered_config(release_id, path=None):
    """Fail if the untracked prepared config differs by even one byte from
    the deterministic render of the current checked spec and tracked template."""
    spec = parse_spec(release_id)
    crosscheck(spec, load_catalog())
    path = Path(path) if path is not None else \
        out_dir(release_id) / "src" / "config_pkg.vhd"
    if not path.is_file():
        raise RuntimeError(f"{release_id}: rendered config missing: {path}")
    expected = render_config_text(spec).encode("utf-8")
    actual = path.read_bytes()
    if actual != expected:
        raise RuntimeError(
            f"{release_id}: rendered config is stale or modified; "
            "run research_release.py prepare after preserving the old build"
        )
    print(f"RENDER VERIFIED: {release_id} "
          f"{hashlib.sha256(actual).hexdigest()}")
    return path


def source_paths(spec, release_id):
    rtl = ROOT / "Convlution_Accelerator.srcs/sources_1/new"
    paths = []
    for name in spec["sources"]:
        if name == "config_pkg.vhd" and str(spec["render_config_pkg"]) == "1":
            paths.append(out_dir(release_id) / "src" / "config_pkg.vhd")
        else:
            paths.append(rtl / name)
    return paths


def build_input_paths(release_id):
    return [
        Path(__file__).resolve(),
        BUILD_TCL,
        spec_path(release_id),
        CATALOG,
        BLOCK_DESIGN,
        BOARD_XDC,
    ]


def do_check(release_id):
    spec = parse_spec(release_id)
    rel = crosscheck(spec, load_catalog())
    paths = source_paths(spec, release_id)
    missing = []
    for p in paths:
        if p.is_file():
            continue
        if p == out_dir(release_id) / "src" / "config_pkg.vhd":
            continue   # rendered by prepare/build, not required at check time
        missing.append(str(p))
    if missing:
        raise RuntimeError(f"sources missing (transplant pending?):\n  " +
                           "\n  ".join(missing))
    print(f"SPEC OK: {release_id} shape={spec['shape_id']} "
          f"clock={spec['clock_mhz']} MHz, build_id {spec['build_id_hex'][:16]}…")
    print(f"catalog binding: {rel['shape_id']} / {rel['bundle_sha256'][:16]}…")
    for p in paths:
        if p == out_dir(release_id) / "src" / "config_pkg.vhd":
            print("  (rendered at prepare/build)  config_pkg.vhd")
        else:
            print(f"  {hashlib.sha256(p.read_bytes()).hexdigest()[:16]}…  "
                  f"{p.relative_to(ROOT)}")
    if (out_dir(release_id)).exists():
        print(f"WARNING: build dir exists: {out_dir(release_id)} "
              "(archive before rebuilding)")
    return spec


def do_manifest(release_id):
    spec = parse_spec(release_id)
    rel = crosscheck(spec, load_catalog())
    artifacts = out_dir(release_id) / "artifacts"
    results = {}
    rf = artifacts / "results.txt"
    if rf.is_file():
        for line in rf.read_text().splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                results[k.strip()] = v.strip()
    git_commit = subprocess.run(
        ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
        text=True, check=True).stdout.strip()
    git_status = subprocess.run(
        ["git", "status", "--porcelain", "--untracked-files=no"],
        cwd=ROOT, capture_output=True, text=True, check=True).stdout.splitlines()
    manifest = {
        "release_id": release_id,
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "git_commit": git_commit,
        "git_tracked_worktree_clean": not git_status,
        "git_tracked_status_porcelain": git_status,
        "spec": {k: v for k, v in spec.items()},
        "catalog_binding": rel,
        "results": results,
        "board_validation": "NOT_RUN",
        "sources": {str(p.relative_to(ROOT)):
                    hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in source_paths(spec, release_id)},
        "build_inputs": {str(p.relative_to(ROOT)):
                         hashlib.sha256(p.read_bytes()).hexdigest()
                         for p in build_input_paths(release_id)},
        "artifacts": {
            p.name: hashlib.sha256(p.read_bytes()).hexdigest()
            for p in sorted(artifacts.iterdir())
            if p.is_file() and p.name != "build_manifest.json"
        },
    }
    out = artifacts / "build_manifest.json"
    out.write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"MANIFEST OK: {out}")
    return manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["check", "verify-render", "build",
                                        "prepare", "manifest"])
    ap.add_argument("release_id")
    ap.add_argument("--vivado", default="vivado")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()

    if args.command == "check":
        do_check(args.release_id)
        return
    if args.command == "verify-render":
        verify_rendered_config(args.release_id)
        return
    if args.command == "manifest":
        do_manifest(args.release_id)
        return

    spec = do_check(args.release_id)          # check + (render below)
    if str(spec["render_config_pkg"]) == "1":
        render_config_pkg(spec, out_dir(args.release_id) / "src" / "config_pkg.vhd")
        print("config_pkg rendered into the build tree")
    if args.command == "prepare":
        print("next: research_build.tcl from Vivado (batch or GUI), then "
              f"`research_release.py manifest {args.release_id}`")
        return
    tcl = Path(__file__).resolve().parent / "research_build.tcl"
    cmd = [args.vivado, "-mode", "batch", "-source", str(tcl),
           "-tclargs", args.release_id,
           "-log", str(out_dir(args.release_id) / "build.log"),
           "-journal", str(out_dir(args.release_id) / "build.jou")]
    print("running:", " ".join(cmd))
    r = subprocess.run(cmd, cwd=ROOT)
    if r.returncode != 0:
        raise RuntimeError("Vivado build failed; inspect the log "
                           "(reports are preserved under artifacts/)")
    do_manifest(args.release_id)


if __name__ == "__main__":
    main()
