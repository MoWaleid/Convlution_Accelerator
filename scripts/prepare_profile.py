"""User-run only: freeze one explicit profile into a NEW isolated RTL snapshot."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "software"))
from conv_lab.profiles import load_profiles

RTL_NAMES = (
    "config_pkg.vhd", "conv_pkg.vhd", "coeff_bias_shift_regfile.vhd",
    "axi_lite_ctrl.vhd", "sync_fifo.vhd", "axi_stream_input_frontend.vhd",
    "axi_stream_output_serializer.vhd", "window_generator.vhd",
    "conv_channel.vhd", "conv_engine.vhd", "conv_top.vhd",
    "conv_axis_wrapper.vhd", "conv_axis_wrapper_bd.v",
)


def render_config(template, profile):
    block = f"""    -- BEGIN SELECTED PROFILE: derived from profiles/m7_profiles.json.
    -- Use scripts/prepare_profile.py for an explicit isolated selection.
    constant CFG_PROFILE : string := "{profile.name}";
    constant CFG_BUILD_ID : std_logic_vector(127 downto 0) :=
        x"{profile.build_id}";

    -- Number of parallel output channels (K).
    constant CFG_K : integer := {profile.K};

    -- Kernel spatial dimension (N x N).
    constant CFG_N : integer := {profile.N};

    -- Image spatial dimensions.
    constant CFG_UNPADDED_WIDTH  : integer := {profile.W};
    constant CFG_UNPADDED_HEIGHT : integer := {profile.H};
    -- END SELECTED PROFILE"""
    text, count = re.subn(r"    -- BEGIN SELECTED PROFILE:.*?    -- END SELECTED PROFILE",
                         lambda _: block, template, flags=re.S)
    if count != 1:
        raise ValueError("exactly one selected-profile block required")
    return text


def prepare(profile_name, output):
    profiles = load_profiles(ROOT / "profiles/m7_profiles.json")
    if profile_name not in profiles:
        raise ValueError("explicit approved profile required")
    profile = profiles[profile_name]
    output = Path(output).resolve()
    # Never put generated configuration inside the production sources.
    source = ROOT / "Convlution_Accelerator.srcs"
    if output == ROOT or output == source or source in output.parents:
        raise ValueError("output cannot be production source/project directory")
    output.mkdir(parents=True, exist_ok=False)
    rtl = output / "rtl"
    rtl.mkdir()
    originals = {}
    for name in RTL_NAMES:
        data = (source / "sources_1/new" / name).read_bytes()
        originals[name] = hashlib.sha256(data).hexdigest()
        if name == "config_pkg.vhd":
            data = render_config(data.decode("utf-8"), profile).encode("utf-8")
        (rtl / name).write_bytes(data)
    catalog = (ROOT / "profiles/m7_profiles.json").read_bytes()
    (output / "m7_profiles.json").write_bytes(catalog)
    metadata = {
        "purpose": "M7 build input; NOT a deployable hardware manifest or qualification",
        "profile": profile.name, "W": profile.W, "H": profile.H,
        "N": profile.N, "K": profile.K, "build_id": profile.build_id,
        "catalog_sha256": hashlib.sha256(catalog).hexdigest(),
        "source_original_sha256": originals,
    }
    (output / "profile.json").write_text(json.dumps(metadata, indent=2)+"\n", encoding="utf-8")
    # Simulation expectations are cross-checked against independent contract
    # anchors by the focused software tests before RTL testing.
    (output / "expected.svh").write_text(
        f'localparam [127:0] EXPECT_ID = 128\'h{profile.build_id};\n'
        f'localparam integer EXPECT_W={profile.W}, EXPECT_H={profile.H}, '
        f'EXPECT_N={profile.N}, EXPECT_K={profile.K};\n', encoding="ascii")
    files = sorted(p for p in output.rglob("*") if p.is_file())
    (output / "SHA256SUMS.txt").write_text("".join(
        f"{hashlib.sha256(p.read_bytes()).hexdigest()}  {p.relative_to(output).as_posix()}\n"
        for p in files), encoding="ascii")
    print(f"M7_PROFILE_PREPARED {profile.name} {profile.build_id} {output}")


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", required=True, choices=("A32", "B32", "C32", "D32", "D640"))
    parser.add_argument("--out", required=True, type=Path)
    args = parser.parse_args()
    prepare(args.profile, args.out)

