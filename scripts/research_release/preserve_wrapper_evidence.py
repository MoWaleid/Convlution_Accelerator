#!/usr/bin/env python3
"""Collect source-bound official wrapper results without running Vivado.

The user runs ``test_profile_wrappers.tcl`` in Vivado.  That runner creates a
unique ``work/profile_wrapper_*`` directory containing ``run_meta.txt``,
``run_result.txt`` and the XSim log.  This utility verifies those bindings
against the current clean commit, copies the evidence into a new immutable
session directory, and writes a checksum manifest.

Usage after all five Tcl runs:

    python -B scripts/research_release/preserve_wrapper_evidence.py

Use ``--release ID`` one or more times only for a deliberately partial
diagnostic collection.  A partial collection is never labelled a full matrix.
"""

import argparse
import hashlib
import json
import re
import shutil
import subprocess
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
EVIDENCE_PARENT = ROOT / "report/research_builds/CFGLUT125_MATRIX"
RUNS = (
    ("B32_CFGLUT125", "optimized"),
    ("A32_CFGLUT125", "optimized"),
    ("C32_CFGLUT125", "optimized_relaxed"),
    ("D32_CFGLUT125", "optimized_relaxed"),
    ("D640_CFGLUT125", "optimized_relaxed"),
)
RUNNER = ROOT / "scripts/research_release/test_profile_wrappers.tcl"
TESTBENCH = ROOT / (
    "Convlution_Accelerator.srcs/sim_1/imports/new/"
    "tb_conv_axis_wrapper.vhd"
)


def sha256_of(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def git(*args: str) -> str:
    return subprocess.run(
        ["git", *args], cwd=ROOT, check=True, capture_output=True,
        text=True, encoding="utf-8", errors="strict"
    ).stdout.strip()


def parse_meta(path: Path) -> dict[str, str]:
    result = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        key, separator, value = line.partition("=")
        if not separator or not key or key in result:
            raise RuntimeError(f"malformed metadata line in {path}: {line!r}")
        result[key] = value
    required = {
        "release_id", "variant", "git_commit", "vivado",
        "runner", "runner_sha256", "testbench", "testbench_sha256",
        "rendered_config", "rendered_config_sha256",
    }
    if set(result) != required:
        raise RuntimeError(
            f"{path}: metadata keys differ: missing={sorted(required-set(result))} "
            f"extra={sorted(set(result)-required)}"
        )
    return result


def latest_bound_run(release_id: str, variant: str) -> Path:
    candidates = sorted(
        (ROOT / "work").glob(f"profile_wrapper_{release_id}_{variant}_*"),
        key=lambda path: path.stat().st_mtime_ns,
        reverse=True,
    )
    for candidate in candidates:
        if (candidate / "run_meta.txt").is_file() and \
                (candidate / "run_result.txt").is_file():
            return candidate
    raise RuntimeError(
        f"no completed source-bound run for {release_id} {variant}; "
        "run the fixed Tcl qualification first"
    )


def validate_and_copy(release_id: str, variant: str, destination: Path,
                      current_commit: str) -> dict:
    run_dir = latest_bound_run(release_id, variant)
    meta_path = run_dir / "run_meta.txt"
    result_path = run_dir / "run_result.txt"
    log_path = run_dir / "profile_wrapper_sim.sim/sim_1/behav/xsim/simulate.log"
    if not log_path.is_file():
        raise RuntimeError(f"simulation log missing: {log_path}")

    meta = parse_meta(meta_path)
    if meta["release_id"] != release_id or meta["variant"] != variant:
        raise RuntimeError(f"run identity mismatch in {meta_path}")
    if meta["git_commit"] != current_commit:
        raise RuntimeError(
            f"{release_id}: run commit {meta['git_commit']} != current "
            f"{current_commit}"
        )

    rendered = ROOT / f"work/research_{release_id}/src/config_pkg.vhd"
    bindings = (
        ("runner", "runner_sha256", RUNNER),
        ("testbench", "testbench_sha256", TESTBENCH),
        ("rendered_config", "rendered_config_sha256", rendered),
    )
    for path_key, hash_key, expected_path in bindings:
        if Path(meta[path_key]).resolve() != expected_path.resolve():
            raise RuntimeError(f"{release_id}: {path_key} path mismatch")
        if not expected_path.is_file() or sha256_of(expected_path) != meta[hash_key]:
            raise RuntimeError(f"{release_id}: {hash_key} binding mismatch")

    result_text = result_path.read_text(encoding="utf-8")
    expected_marker = f"PROFILE_WRAPPER_PASS: {release_id} {variant}"
    if re.search(rf"(?m)^{re.escape(expected_marker)}$", result_text) is None:
        raise RuntimeError(f"{release_id}: exact terminal PASS marker missing")
    claim = "yes" if release_id in {"A32_CFGLUT125", "B32_CFGLUT125"} else "no"
    if f"OPTION_A_EXTERNAL_GAPLESS_CLAIM={claim}" not in result_text:
        raise RuntimeError(f"{release_id}: Option-A claim-scope record mismatch")

    log_text = log_path.read_text(encoding="utf-8", errors="replace")
    if "CONV_AXIS_WRAPPER COMPLETE M4 INTEGRATION REGRESSION PASS" not in log_text:
        raise RuntimeError(f"{release_id}: wrapper completion marker missing")
    if re.search(r"(?im)^(error:|failure:|fatal:)", log_text):
        raise RuntimeError(f"{release_id}: failure marker exists in XSim log")

    destination.mkdir()
    copied = {}
    for source in (meta_path, result_path, log_path):
        target = destination / source.name
        shutil.copy2(source, target)
        copied[target.name] = sha256_of(target)

    windows = re.findall(
        r"WINDOW_METRICS seq=(\d+) prefetch=(true|false) "
        r"invalid_advances=(\d+)[^\r\n]*", log_text
    )
    edges = re.findall(
        r"EDGE_METRICS prefetch=(\w+) ready_mode=(\d+) gaps=(\d+)[^\r\n]*",
        log_text,
    )
    if len(windows) != 3 or len(edges) != 3:
        raise RuntimeError(f"{release_id}: expected three window/edge records")

    return {
        "release_id": release_id,
        "variant": variant,
        "result": "PASS",
        "source_directory": str(run_dir.relative_to(ROOT)).replace("\\", "/"),
        "source_bindings": meta,
        "terminal_marker": expected_marker,
        "window_metrics": [
            {"seq": int(seq), "prefetch": pre == "true",
             "invalid_advances": int(invalid)}
            for seq, pre, invalid in windows
        ],
        "edge_metrics": [
            {"prefetch": pre == "true", "ready_mode": int(mode),
             "gaps": int(gaps)}
            for pre, mode, gaps in edges
        ],
        "files": copied,
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--release", action="append",
                        choices=[release for release, _ in RUNS])
    parser.add_argument("--evidence-id")
    args = parser.parse_args()

    if git("status", "--porcelain", "--untracked-files=no"):
        raise SystemExit("tracked worktree is not clean; commit before collection")
    current_commit = git("rev-parse", "HEAD")
    selected = [item for item in RUNS
                if args.release is None or item[0] in set(args.release)]
    complete_matrix = len(selected) == len(RUNS)

    evidence_id = args.evidence_id or (
        "wrapper_official_user_" + time.strftime("%Y%m%dT%H%M%SZ", time.gmtime())
    )
    if re.fullmatch(r"[A-Za-z0-9_.-]+", evidence_id) is None:
        raise SystemExit("evidence ID must be a safe basename")
    destination = EVIDENCE_PARENT / evidence_id
    if destination.exists():
        raise SystemExit(f"refusing to reuse evidence directory: {destination}")

    # Validate all requested runs before creating the evidence directory.
    sources = [(release, variant, latest_bound_run(release, variant))
               for release, variant in selected]
    del sources  # validation/copy resolves the same newest immutable paths
    destination.mkdir(parents=True)
    records = []
    try:
        for release, variant in selected:
            records.append(validate_and_copy(
                release, variant, destination / f"{release}__{variant}",
                current_commit,
            ))
        manifest = {
            "schema": "wrapper-official-evidence/2",
            "recorded_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "executed_by": "user-executed Vivado Tcl qualification",
            "git_commit": current_commit,
            "complete_five_profile_matrix": complete_matrix,
            "option_a": {
                "external_gapless_claim": ["A32_CFGLUT125", "B32_CFGLUT125"],
                "measured_transition_bubbles": [
                    "C32_CFGLUT125", "D32_CFGLUT125", "D640_CFGLUT125"
                ],
            },
            "runs": records,
        }
        manifest_path = destination / "MANIFEST.json"
        manifest_path.write_text(json.dumps(manifest, indent=2) + "\n",
                                 encoding="utf-8", newline="\n")
        checksum_lines = []
        for path in sorted(destination.rglob("*")):
            if path.is_file() and path.name != "SHA256SUMS.txt":
                relative = path.relative_to(destination).as_posix()
                checksum_lines.append(f"{sha256_of(path)}  {relative}")
        (destination / "SHA256SUMS.txt").write_text(
            "\n".join(checksum_lines) + "\n", encoding="utf-8", newline="\n"
        )
    except BaseException:
        # Never leave a partial directory that could be mistaken for evidence.
        shutil.rmtree(destination)
        raise

    label = "COMPLETE" if complete_matrix else "PARTIAL"
    print(f"OFFICIAL WRAPPER EVIDENCE {label}: {destination}")


if __name__ == "__main__":
    main()
