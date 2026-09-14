#!/usr/bin/env python3
"""Research-line release driver (M10 Gate 1, D3).

Discipline layered on the adapted fresh-project Vivado flow
(research_build.tcl):
  - the build spec (builds/<ID>.spec.tcl) is cross-checked against the
    catalog's `releases` entry (shape_id + build_id_hex) before anything runs;
  - config_pkg.vhd is rendered into the build tree from the repo template
    (selected-profile block) - the repo template is never mutated;
  - after the build, every source and artifact is hashed into
    work/research_<ID>/artifacts/build_manifest.json (IP-08).

Subcommands:
  check <ID>      validate spec vs catalog + source presence; print hashes
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
    return json.loads((ROOT / "profiles" / "m7_profiles.json").read_text())


def crosscheck(spec, catalog):
    rel = (catalog.get("releases") or {}).get(spec["release_id"])
    if rel is None:
        raise RuntimeError(f"{spec['release_id']}: no releases entry in catalog")
    if rel["shape_id"] != spec["shape_id"]:
        raise RuntimeError(f"{spec['release_id']}: spec shape {spec['shape_id']} "
                           f"!= catalog {rel['shape_id']}")
    if rel["build_id_hex"] != spec["build_id_hex"]:
        raise RuntimeError(f"{spec['release_id']}: spec build_id != catalog")
    return rel


def out_dir(release_id):
    return ROOT / "work" / f"research_{release_id}"


def render_config_pkg(spec, dest):
    template = CONFIG_PKG.read_text()
    block = f"""    -- BEGIN SELECTED PROFILE: derived from profiles/m7_profiles.json.
    -- Use scripts/prepare_profile.py for an explicit isolated selection.
    constant CFG_PROFILE : string := "{spec['profile']}";
    constant CFG_BUILD_ID : std_logic_vector(127 downto 0) :=
        x"{spec['build_id_hex']}";

    -- Number of parallel output channels (K).
    constant CFG_K : integer := {spec['k']};

    -- Kernel spatial dimension (N x N).
    constant CFG_N : integer := {spec['n']};

    -- Image spatial dimensions.
    constant CFG_UNPADDED_WIDTH  : integer := {spec['w']};
    constant CFG_UNPADDED_HEIGHT : integer := {spec['h']};
    -- END SELECTED PROFILE"""
    text, count = re.subn(r"    -- BEGIN SELECTED PROFILE:.*?    -- END SELECTED PROFILE",
                          lambda _: block, template, flags=re.S)
    if count != 1:
        raise RuntimeError(f"config_pkg template: expected 1 selected-profile "
                           f"block, replaced {count}")
    dest.parent.mkdir(parents=True, exist_ok=True)
    dest.write_text(text, newline="\n")


def source_paths(spec, release_id):
    rtl = ROOT / "Convlution_Accelerator.srcs/sources_1/new"
    paths = []
    for name in spec["sources"]:
        if name == "config_pkg.vhd" and str(spec["render_config_pkg"]) == "1":
            paths.append(out_dir(release_id) / "src" / "config_pkg.vhd")
        else:
            paths.append(rtl / name)
    return paths


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
    manifest = {
        "release_id": release_id,
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "git_commit": subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True,
            text=True).stdout.strip(),
        "spec": {k: v for k, v in spec.items()},
        "catalog_binding": rel,
        "results": results,
        "board_validation": "NOT_RUN",
        "sources": {str(p.relative_to(ROOT)):
                    hashlib.sha256(p.read_bytes()).hexdigest()
                    for p in source_paths(spec, release_id)},
        "artifacts": {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                      for p in sorted(artifacts.iterdir()) if p.is_file()},
    }
    out = artifacts / "build_manifest.json"
    out.write_text(json.dumps(manifest, indent=1) + "\n")
    print(f"MANIFEST OK: {out}")
    return manifest


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["check", "build", "prepare", "manifest"])
    ap.add_argument("release_id")
    ap.add_argument("--vivado", default="vivado")
    ap.add_argument("--jobs", type=int, default=4)
    args = ap.parse_args()

    if args.command == "check":
        do_check(args.release_id)
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
