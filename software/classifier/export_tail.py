#!/usr/bin/env python3
"""Export trained post-Conv1 tensors into a compact runtime-neutral bundle."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path

import numpy as np

from .checkpoint_reader import load_checkpoint
from .hybrid_reference import CLASS_NAMES


TAIL_TENSORS = (
    "conv2.weight", "conv2.bias", "conv3.weight", "conv3.bias",
    "fc1.weight", "fc1.bias", "fc2.weight", "fc2.bias",
)


def sha256_bytes(blob: bytes) -> str:
    return hashlib.sha256(blob).hexdigest()


def sha256_file(path: Path) -> str:
    return sha256_bytes(path.read_bytes())


def export(checkpoint_path: Path, profile: str, output: Path) -> dict:
    if output.exists():
        raise FileExistsError(f"refusing to overwrite existing tail bundle: {output}")
    checkpoint = load_checkpoint(checkpoint_path)
    metadata, state = checkpoint["metadata"], checkpoint["model_state_dict"]
    expected = set(TAIL_TENSORS) | {"conv1.weight", "conv1.bias"}
    if set(state) != expected:
        raise ValueError("checkpoint tensor inventory does not match the approved network")

    output.mkdir(parents=True)
    tensors = {}
    for name in TAIL_TENSORS:
        array = np.ascontiguousarray(state[name], dtype="<f4")
        filename = name.replace(".", "_") + ".f32le"
        blob = array.tobytes(order="C")
        (output / filename).write_bytes(blob)
        tensors[name] = {
            "file": filename,
            "dtype": "float32-little-endian",
            "shape": list(array.shape),
            "bytes": len(blob),
            "sha256": sha256_bytes(blob),
        }

    manifest = {
        "schema_version": 1,
        "profile": profile,
        "checkpoint_sha256": sha256_file(checkpoint_path),
        "checkpoint_metadata": metadata,
        "input": {
            "layout": "pixel-major-channel-interleaved",
            "dtype": "signed-int16-little-endian",
            "shape": [32, 32, int(metadata["num_channels"])],
            "scale": {"numerator": 1, "denominator": 256},
            "activation": "ReLU",
        },
        "network": [
            "maxpool2x2", "conv2-same3x3", "relu", "maxpool2x2",
            "conv3-same3x3", "relu", "flatten-CHW", "fc1", "relu", "fc2",
            "softmax",
        ],
        "classes": list(CLASS_NAMES),
        "tensors": tensors,
    }
    manifest_blob = (json.dumps(manifest, indent=2, sort_keys=True) + "\n").encode()
    (output / "manifest.json").write_bytes(manifest_blob)

    checksum_lines = [f"{sha256_bytes(manifest_blob)}  manifest.json"]
    checksum_lines.extend(f"{item['sha256']}  {item['file']}"
                          for item in tensors.values())
    (output / "SHA256SUMS.txt").write_text("\n".join(checksum_lines) + "\n",
                                             encoding="ascii", newline="\n")
    return manifest


def main(argv=None):
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--profile", choices=("A32_CFGLUT125", "B32_CFGLUT125",
                                               "C32_CFGLUT125"),
                        default="B32_CFGLUT125")
    parser.add_argument("--output", type=Path)
    args = parser.parse_args(argv)
    checkpoints = {
        "A32_CFGLUT125": root / "golden_model/data/trained_model.pth",
        "B32_CFGLUT125": root / "golden_model/data/trained_k16.pth",
        "C32_CFGLUT125": root / "golden_model/data/trained_n5.pth",
    }
    output = args.output or root / "software/classifier/bundles" / args.profile
    manifest = export(checkpoints[args.profile], args.profile, output)
    print(f"EXPORTED: {output}")
    print(f"TENSORS: {len(manifest['tensors'])}")
    print(f"BYTES: {sum(item['bytes'] for item in manifest['tensors'].values())}")


if __name__ == "__main__":
    main()
