#!/usr/bin/env python3
"""Create a checked, unqualified hardware profile and its Vivado build spec."""

import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "profiles/development_profiles.json"
SPECS = Path(__file__).resolve().parent / "builds"
MAX_DMA_BYTES = (1 << 22) - 1
SOURCES = (
    "config_pkg.vhd conv_pkg.vhd sync_fifo.vhd "
    "coeff_bias_shift_regfile.vhd axi_lite_ctrl.vhd window_generator.vhd "
    "cfglut5_kcm.vhd cfglut5_bitheap_3x3.vhd "
    "cfglut5_bitheap_5x5.vhd conv_channel.vhd conv_engine.vhd conv_top.vhd "
    "axi_stream_input_frontend.vhd axi_stream_output_serializer.vhd "
    "conv_axis_wrapper.vhd conv_axis_wrapper_bd.v"
)


def automatic_build_id(release_id, n, k, width, height, clock_mhz):
    seed = f"{release_id}:{n}:{k}:{width}:{height}:{clock_mhz}".encode()
    label = "DEV" + hashlib.sha256(seed).hexdigest()[:13].upper()
    return label.encode("ascii").hex().upper()


def validate(args):
    if not re.fullmatch(r"[A-Z][A-Z0-9_]{2,63}", args.release_id):
        raise ValueError("release ID must be 3-64 uppercase letters, digits or underscores")
    if args.n not in (3, 5):
        raise ValueError("the current exact bit-heap RTL supports N=3 or N=5")
    if not 1 <= args.k <= 64:
        raise ValueError("K must be in 1..64 (the 0x0000-0x3FFF channel region)")
    if args.width < args.n or args.height < args.n:
        raise ValueError("width and height must each be at least N")
    padded_w = args.width + 2 * (args.n // 2)
    padded_h = args.height + 2 * (args.n // 2)
    tx_bytes = padded_w * padded_h
    rx_bytes = args.width * args.height * args.k * 2
    if tx_bytes > MAX_DMA_BYTES or rx_bytes > MAX_DMA_BYTES:
        raise ValueError(
            f"22-bit DMA length exceeded: TX={tx_bytes}, RX={rx_bytes}, "
            f"maximum={MAX_DMA_BYTES}"
        )
    return tx_bytes, rx_bytes


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("release_id")
    parser.add_argument("--n", type=int, required=True)
    parser.add_argument("--k", type=int, required=True)
    parser.add_argument("--width", type=int, required=True)
    parser.add_argument("--height", type=int, required=True)
    parser.add_argument("--clock-mhz", type=int, default=125)
    parser.add_argument("--build-id-hex",
                        help="optional 32-hex-digit hardware identity")
    args = parser.parse_args()
    tx_bytes, rx_bytes = validate(args)

    build_id = args.build_id_hex or automatic_build_id(
        args.release_id, args.n, args.k, args.width, args.height,
        args.clock_mhz,
    )
    if not re.fullmatch(r"[0-9A-Fa-f]{32}", build_id):
        raise ValueError("build ID must contain exactly 32 hexadecimal digits")
    build_id = build_id.upper()
    shape_id = f"N{args.n}K{args.k}W{args.width}H{args.height}-CVH1"
    spec_path = SPECS / f"{args.release_id}.spec.tcl"
    catalog = json.loads(CATALOG.read_text())
    qualified = json.loads((ROOT / "profiles/m7_profiles.json").read_text())
    if spec_path.exists() or args.release_id in catalog.get("profiles", {}) or \
            args.release_id in qualified.get("profiles", {}):
        raise RuntimeError(f"profile already exists: {args.release_id}")

    catalog.setdefault("profiles", {})[args.release_id] = {
        "W": args.width,
        "H": args.height,
        "N": args.n,
        "K": args.k,
        "build_id": build_id,
        "clock_mhz": args.clock_mhz,
        "status": "DEVELOPMENT_UNQUALIFIED",
    }
    CATALOG.write_text(json.dumps(catalog, indent=2) + "\n", newline="\n")

    spec = f"""# Generated development profile. Build output is unqualified until board tests pass.
set spec(release_id) {args.release_id}
set spec(shape_id) {{{shape_id}}}
set spec(n) {args.n}
set spec(k) {args.k}
set spec(w) {args.width}
set spec(h) {args.height}
set spec(build_id_hex) {build_id}
set spec(clock_mhz) {args.clock_mhz}
set spec(profile) {args.release_id}
set spec(render_config_pkg) 1
set spec(sources) {{{SOURCES}}}
"""
    spec_path.write_text(spec, newline="\n")
    print(f"CREATED: {args.release_id} ({shape_id})")
    print(f"DMA payloads: TX={tx_bytes} bytes, RX={rx_bytes} bytes")
    print(f"build ID: {build_id}")
    print(f"next: python -B scripts/research_release/research_release.py check {args.release_id}")
    print(f"then: python -B scripts/research_release/research_release.py prepare {args.release_id}")


if __name__ == "__main__":
    main()
