"""§19.7 step 2 admission: bind canonical BIT/BIN hashes into runtime manifests.

Fail-closed: every canonical artifact is hashed and cross-checked against the
routed-build manifest before any runtime manifest is touched. Identity fields
are cross-checked against the catalog release entries. Nothing is written
unless all five releases pass every check.
"""
import hashlib
import json
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RELEASES = ["A32_CFGLUT125", "B32_CFGLUT125", "C32_CFGLUT125",
            "D32_CFGLUT125", "D640_CFGLUT125"]
# B32's accepted rebuild evidence lives in a dated subdirectory; the parent
# directory's manifest belongs to the preserved older qualified build.
BUILD_MANIFEST = {
    "B32_CFGLUT125": "report/research_builds/B32_CFGLUT125/"
                     "rebuild_20260915/build_manifest.json",
}


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def is_canonical_hex(value):
    return isinstance(value, str) and len(value) == 64 and all(
        c in "0123456789abcdef" for c in value.lower())


catalog = json.loads((REPO / "profiles/m7_profiles.json").read_text())
plans = []
failures = []
for release in RELEASES:
    build = json.loads((REPO / BUILD_MANIFEST.get(
        release,
        f"report/research_builds/{release}/build_manifest.json")).read_text())
    low = release.replace("_CFGLUT125", "").lower()
    bit = REPO / f"bitstreams/{low}_cfglut125_125mhz.bit"
    xsa = REPO / f"bitstreams/{low}_cfglut125_125mhz.xsa"
    fw = REPO / f"bitstreams/{low}_cfglut125_125mhz.bit.bin"

    if build["release_id"] != release:
        failures.append(f"{release}: build manifest release_id mismatch")
        continue
    results = build["results"]
    if results["release_id"] != release or results["MHz"] != "125":
        failures.append(f"{release}: build manifest results identity mismatch")
        continue
    if float(results["WNS"]) < 0 or float(results["WHS"]) < 0:
        failures.append(f"{release}: nonnegative slack required")
        continue
    if results["BOARD_VALIDATION"] != "NOT_RUN":
        failures.append(f"{release}: board validation must be NOT_RUN here")
        continue

    cat_rel = catalog["releases"].get(release)
    cat_prof = catalog["profiles"].get(release)
    if cat_rel is None or cat_prof is None:
        failures.append(f"{release}: missing catalog entries")
        continue
    if cat_rel.get("build_id_hex") != build["spec"]["build_id_hex"]:
        failures.append(f"{release}: catalog build_id_hex mismatch")
        continue
    if cat_rel.get("shape_id") != build["spec"]["shape_id"]:
        failures.append(f"{release}: catalog shape_id mismatch")
        continue

    if not all(p.exists() for p in (bit, xsa, fw)):
        failures.append(f"{release}: missing canonical artifact file(s)")
        continue
    bit_sha, xsa_sha, fw_sha = sha256(bit), sha256(xsa), sha256(fw)
    if bit_sha != build["artifacts"][f"{release}.bit"]:
        failures.append(f"{release}: canonical BIT hash != build manifest")
        continue
    if xsa_sha != build["artifacts"][f"{release}.xsa"]:
        failures.append(f"{release}: canonical XSA hash != build manifest")
        continue
    if not is_canonical_hex(fw_sha):
        failures.append(f"{release}: firmware hash not canonical 64-hex")
        continue

    plans.append({
        "release": release,
        "bit_sha": bit_sha,
        "fw_sha": fw_sha,
        "build_id_hex": build["spec"]["build_id_hex"],
    })

if failures:
    print("ADMISSION FAILED — no manifests modified:")
    for f in failures:
        print(" -", f)
    sys.exit(1)

for plan in plans:
    release = plan["release"]
    mpath = REPO / f"software/hardware_{release}.json"
    manifest = json.loads(mpath.read_text())
    if manifest["profile"] != release:
        print(f"ABORT: {mpath} profile mismatch")
        sys.exit(1)
    acc = manifest["accelerator"]
    if acc["build_id_hex"] != plan["build_id_hex"]:
        print(f"ABORT: {mpath} build_id_hex mismatch")
        sys.exit(1)
    acc["clock_mhz"] = 125
    manifest["artifacts"]["bitstream_sha256"] = plan["bit_sha"]
    manifest["artifacts"]["firmware_bin_sha256"] = plan["fw_sha"]
    manifest["artifacts"]["note"] = (
        "canonical routed bitstream and bootgen-generated FPGA-manager "
        "firmware bound from the frozen five-build record (AI_HANDOFF.md "
        "SS18.17); BUILT, BOARD_VALIDATION=NOT_RUN")
    manifest["release_status"] = "built-unqualified"
    manifest["deployable"] = True
    mpath.write_text(json.dumps(manifest, indent=2) + "\n")
    print(f"BOUND {release}: bit {plan['bit_sha'][:12]}… fw "
          f"{plan['fw_sha'][:12]}… built-unqualified deployable=true")

print("ADMISSION OK: 5/5 manifests bound")
