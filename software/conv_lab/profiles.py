"""M7 build inputs and pure admission/layout helpers; no device access.

m7_profiles.json is the authority. Callers explicitly supply its path and profile.
This is not a production hardware manifest or a qualification database.
"""
from dataclasses import dataclass
from pathlib import Path
import re

from .dma import layout, validate_layout
from .strict import hex_string, integer, obj, parse_json, require, string


@dataclass(frozen=True, slots=True)
class Profile:
    name: str
    W: int
    H: int
    N: int
    K: int
    build_id: str


def load_profiles(path):
    data = parse_json(Path(path).read_bytes())
    obj(data, "schema_version profiles releases")
    require(type(data["schema_version"]) is int and data["schema_version"] == 2,
            "profile schema")
    entries = data["profiles"]
    require(type(entries) is dict and
            set(entries) == {"A32", "B32", "C32", "D32", "D640",
                             "B32_CFGLUT125", "B32_CFGLUT100"},
            "explicit seven-release catalog required")
    result = {}
    ids = set()
    for name, entry in entries.items():
        obj(entry, "W H N K build_id")
        for key in ("W", "H", "N", "K"):
            integer(entry[key], 1, 0xffffffff)
        require(entry["N"] in (3, 5) and entry["K"] <= 64, "profile N/K")
        identity = entry["build_id"]
        require(type(identity) is str and
                re.fullmatch(r"[0-9a-f]{32}", identity) is not None and
                int(identity, 16) != 0, "canonical nonzero 128-bit build ID")
        require(identity not in ids, "duplicate profile identity")
        ids.add(identity)
        result[name] = Profile(name, **entry)

    releases = data["releases"]
    require(type(releases) is dict and set(releases) == set(entries),
            "release bindings must exactly cover profiles")
    for name, release in releases.items():
        obj(release, "shape_id bundle_sha256 manifest build_id_hex", "bundle_dir")
        string(release["shape_id"])
        hex_string(release["bundle_sha256"])
        require(type(release["manifest"]) is str and
                re.fullmatch(r"hardware_[A-Za-z0-9_]+\.json",
                             release["manifest"]) is not None,
                "release manifest basename")
        hex_string(release["build_id_hex"], 32)
        require(release["build_id_hex"] == entries[name]["build_id"],
                "release/profile build ID mismatch")
        if "bundle_dir" in release:
            string(release["bundle_dir"])
            require(release["bundle_dir"] in entries,
                    "release bundle_dir must name a profile")
    return result


def profile_layout(profile, allocation, proposed=None):
    """Use runtime-discovered allocation facts, never the historical fixed RX.

    proposed can be checked before submission; no MMIO or DMA is performed.
    """
    require(type(profile) is Profile, "explicit selected Profile required")
    if proposed is not None:
        return validate_layout(profile.W, profile.H, profile.N, profile.K,
                               allocation, proposed)
    return layout(profile.W, profile.H, profile.N, profile.K, allocation)


def validate_discovery(profile, registers):
    """Validate an already-read register snapshot before any backend writes."""
    require(type(profile) is Profile, "explicit selected Profile required")
    for value in registers.values():
        integer(value, 0, 0xffffffff)
    expected = {
        0x4100: 0x43564831, 0x4104: 0x10000, 0x4108: 0x1ff,
        0x4120: profile.W, 0x4124: profile.H,
        0x4128: profile.N, 0x412c: profile.K,
        0x4130: 0x10180808,
        0x4134: 0x1900 + 17 + (profile.N * profile.N - 1).bit_length(),
        0x4138: (profile.W + profile.N - 1) * (profile.H + profile.N - 1),
        0x413c: 2 * profile.W * profile.H * profile.K, 0x4160: 22,
    }
    build_id = int(profile.build_id, 16)
    expected.update({0x4150 + 4*i: (build_id >> (32*i)) & 0xffffffff
                     for i in range(4)})
    for address, value in expected.items():
        require(registers.get(address) == value,
                f"{profile.name} discovery mismatch at 0x{address:04x}")
    return profile
