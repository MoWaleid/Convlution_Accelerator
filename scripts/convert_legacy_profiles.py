#!/usr/bin/env python3
"""Explicit legacy conversion of the M7 parameter bundles to the canonical
flat-2 dialect admitted by software/m7_switch.py load_params().

Per M1_FILE_CONTRACT S5, format-2 exports are preserved unchanged; this tool
produces a SEPARATELY IDENTIFIED canonical conversion (dialect marker
"canonical-flat-2") with: boolean relu_en (no integer coercion), a required
exact weights_file per channel, an explicit bundle-declared signed bias width
(24, replacing the stale legacy bias_bits=32 declaration), exact field sets,
and a recorded conversion receipt over source and output hashes.

The kernel .mem bytes are copied untouched — only metadata is canonicalized.
"""
import hashlib
import json
import shutil
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
SOURCE = Path(sys.argv[1]) if len(sys.argv) > 1 else \
    Path(r"C:\Users\moham\AppData\Local\Temp\m7_bundle2\profiles")
OUT = REPO / "profiles"
HISTORY = REPO / "profiles" / "history"
PROFILES = ("A32", "B32", "C32", "D32", "D640")
BIAS_WIDTH = 24   # the hardware's implemented policy (config_pkg CFG_BIAS_WIDTH)


def sha(data):
    return hashlib.sha256(data).hexdigest()


def convert(name):
    src = SOURCE / name
    legacy = json.loads((src / "channel_config.json").read_bytes())
    if legacy.get("format_version") != 2:
        raise SystemExit(f"{name}: expected legacy format_version 2")
    n, k = legacy["N"], legacy["K"]
    out = OUT / name
    out.mkdir(parents=True, exist_ok=True)

    channels_out = []
    files = {"channel_config.json": None}
    for entry in legacy["channels"]:
        ch = entry["channel"]
        weights_file = entry.get("weights_file", f"kernel_ch{ch}.mem")
        require_valid = (src / weights_file)
        if not require_valid.is_file():
            raise SystemExit(f"{name}: missing weight file {weights_file}")
        relu = entry["relu_en"]
        if isinstance(relu, int):
            if relu not in (0, 1):
                raise SystemExit(f"{name}: non-boolean relu_en {relu!r}")
            relu = bool(relu)
        if not isinstance(relu, bool):
            raise SystemExit(f"{name}: non-boolean relu_en {relu!r}")
        bias = entry["bias_quantized"]
        lo, hi = -(1 << (BIAS_WIDTH - 1)), (1 << (BIAS_WIDTH - 1)) - 1
        if not (lo <= bias <= hi):
            raise SystemExit(f"{name}: bias {bias} exceeds signed-{BIAS_WIDTH}")
        channels_out.append({"channel": ch, "weights_file": weights_file,
                             "bias_quantized": bias, "shift": entry["shift"],
                             "relu_en": relu})
        dst = out / weights_file
        data = require_valid.read_bytes()
        dst.write_bytes(data)
        files[weights_file] = data

    canonical = {"format_version": 2, "dialect": "canonical-flat-2",
                 "N": n, "K": k, "bias_width": BIAS_WIDTH,
                 "channels": channels_out}
    cfg_bytes = json.dumps(canonical, indent=1).encode() + b"\n"
    (out / "channel_config.json").write_bytes(cfg_bytes)
    files["channel_config.json"] = cfg_bytes

    receipt = {
        "profile": name, "converted_utc": "2026-09-14",
        "source_dir": str(src),
        "source_channel_config_sha256": sha((src / "channel_config.json").read_bytes()),
        "output_channel_config_sha256": sha(cfg_bytes),
        "weights": {w: sha(data) for w, data in files.items() if w != "channel_config.json"},
        "notes": "explicit legacy-flat-2 -> canonical-flat-2 conversion; "
                 "relu_en canonicalized to JSON boolean; weights_file made "
                 "explicit; bias_width 24 declared (legacy bias_bits=32 "
                 "declaration was stale); kernel .mem bytes untouched",
    }
    return receipt, files


def main():
    HISTORY.mkdir(parents=True, exist_ok=True)
    receipts = {}
    for name in PROFILES:
        receipts[name], _files = convert(name)
        print(f"{name}: converted "
              f"({receipts[name]['output_channel_config_sha256'][:16]})")
    rpath = HISTORY / "legacy_conversion_20260914.json"
    rpath.write_text(json.dumps(receipts, indent=1) + "\n")
    print(f"receipts: {rpath}")


if __name__ == "__main__":
    main()
