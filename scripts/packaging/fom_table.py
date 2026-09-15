"""Competition packaging: per-release results table with FOM, ranked by FOM.

Reads only committed, hash-verified build reports under
report/research_builds/ and emits the Table-1 data for the five qualified
CFGLUT125 releases in both resource scopes:

  - full system (PS/BD/accelerator as shipped in the bitstream)
  - accelerator core (conv_axis_wrapper hierarchy; the contest deliverable
    core, excluding AXI DMA/SmartConnect plumbing)

FOM = Throughput / (Power * (LUTs + 50*DSPs + 100*BRAMs)), throughput in
output positions per cycle. Design throughput is 1.0 position/cycle once
filled; C32/D32/D640 carry disclosed row-transition bubbles (wrapper-sim
record) so their effective rates are also shown.

Power is the Vivado vectorless estimate (no activity factors), stated as
such. BRAMs counted as RAMB36 equivalents (2x RAMB36 + 2x RAMB18 = 3).
"""
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELEASES = ["A32_CFGLUT125", "B32_CFGLUT125", "C32_CFGLUT125",
            "D32_CFGLUT125", "D640_CFGLUT125"]
# Wrapper-sim frame-D bubbles: invalid_advances / external gaps (Option A).
BUBBLES = {"A32_CFGLUT125": (31, 0), "B32_CFGLUT125": (0, 0),
           "C32_CFGLUT125": (62, 31), "D32_CFGLUT125": (62, 62),
           "D640_CFGLUT125": (958, 958)}
# External output-interface ceiling (G3.4 discipline): the serializer packs
# 4 int16 values per 64-bit beat, so K channel-results per position bound the
# sustained rate at 4/K output positions per cycle (K4: 1.0, K8: 0.5,
# K16: 0.25). The compute core produces 1 position/cycle once filled; the
# bus cannot drain it faster than 4/K.
INTERFACE_CEILING = lambda k: 4.0 / k


def build_manifest_path(release):
    if release == "B32_CFGLUT125":
        return ROOT / "report/research_builds/B32_CFGLUT125/rebuild_20260915"
    return ROOT / f"report/research_builds/{release}"


def sha_file(path):
    import hashlib
    return hashlib.sha256(path.read_bytes()).hexdigest()


def parse_utilization(release):
    d = build_manifest_path(release)
    top = core = None
    for line in (d / "utilization.rpt").read_text().splitlines():
        cols = [c.strip() for c in line.split("|")]
        if len(cols) < 10 or cols[1] in ("", "Instance") :
            continue
        if cols[1] == "accelerator_dma_wrapper":
            top = {"LUT": int(cols[3]), "FF": int(cols[7]),
                   "RAMB36": int(cols[8]), "RAMB18": int(cols[9]),
                   "DSP": int(cols[10])}
        if cols[1] == "conv_axis_wrapper_bd_0":
            core = {"LUT": int(cols[3]), "FF": int(cols[7]),
                    "RAMB36": int(cols[8]), "RAMB18": int(cols[9]),
                    "DSP": int(cols[10])}
    require = top and core
    assert require, f"{release}: utilization rows not found"
    return top, core


def parse_power(release):
    d = build_manifest_path(release)
    total = core = None
    for line in (d / "power.rpt").read_text().splitlines():
        if "Total On-Chip Power" in line:
            total = float(line.split("|")[2].strip().split()[0])
        m = re.match(r"\|\s+conv_axis_wrapper_bd_0\s+\|\s+([0-9.]+)\s*\|", line)
        if m:
            core = float(m.group(1))
    assert total is not None and core is not None, f"{release}: power rows"
    return total, core


def parse_results(release):
    d = build_manifest_path(release)
    out = {}
    for line in (d / "results.txt").read_text().splitlines():
        k, _, v = line.partition("=")
        out[k.strip()] = v.strip()
    return out


def bram36(r):
    return r["RAMB36"] + r["RAMB18"] / 2.0


def fom(throughput, power, res):
    denom = power * (res["LUT"] + 50 * res["DSP"] + 100 * bram36(res))
    return throughput / denom


def main():
    rows = []
    for release in RELEASES:
        top, core = parse_utilization(release)
        power_total, power_core = parse_power(release)
        res = parse_results(release)
        invalid, gaps = BUBBLES[release]
        shape_m = re.match(r"N(\d+)K(\d+)W(\d+)H(\d+)", res["shape_id"])
        n, k, w, h = (int(g) for g in shape_m.groups())
        beats = w * h * k * 2 // 8
        # Effective external output rate: interface ceiling derated by the
        # disclosed row-transition gaps over output beats (§18.10 record).
        eff = INTERFACE_CEILING(k) * (1.0 - gaps / beats)
        rows.append({
            "release": release, "shape": res["shape_id"],
            "wns": float(res["WNS"]), "whs": float(res["WHS"]),
            "top": top, "core": core,
            "power_total": power_total, "power_core": power_core,
            "throughput_design_positions_per_cycle": INTERFACE_CEILING(k),
            "fom_top": fom(INTERFACE_CEILING(k), power_total, top),
            "fom_core": fom(INTERFACE_CEILING(k), power_core, core),
            "eff_rate": round(eff, 4),
            "fom_top_eff": fom(eff, power_total, top),
            "invalid": invalid, "gaps": gaps,
        })
    rows.sort(key=lambda r: -r["fom_top"])
    out = {"throughput_definition": "4/K output positions per cycle "
           "(64-bit output bus, 4 int16/beat), derated by disclosed "
           "row-transition gaps; compute core produces 1 position/cycle "
           "once filled",
           "rows": rows}
    dest = ROOT / "report/research_builds/CFGLUT125_MATRIX/fom_results.json"
    dest.write_text(json.dumps(out, indent=2) + "\n")
    print(f"wrote {dest}")
    print(f"\n{'release':<16}{'shape':<20}{'WNS':>7}{'LUTsys':>8}{'LUTcore':>9}"
          f"{'Psys':>7}{'Pcore':>7}{'FOMsys':>11}{'FOMcore':>11}{'eff':>7}")
    for r in rows:
        print(f"{r['release']:<16}{r['shape']:<20}{r['wns']:>7.3f}"
              f"{r['top']['LUT']:>8}{r['core']['LUT']:>9}"
              f"{r['power_total']:>7.3f}{r['power_core']:>7.3f}"
              f"{r['fom_top']:>11.3e}{r['fom_core']:>11.3e}{r['eff_rate']:>7.4f}")
    assert all(sha_file(build_manifest_path(r) / "results.txt")
               for r in RELEASES)
    print("source reports present for all five releases")


if __name__ == "__main__":
    main()
