#!/usr/bin/env python3
"""Build the compact, hash-qualified CIFAR-10 board demo library.

The source images are the ten-per-class samples published on the official
CIFAR-10 page.  This generator selects samples 1..5 for every class, preserves
their PNG bytes, applies the same Pillow grayscale/LANCZOS pipeline as the
board decoder, and records exact D640_CFGLUT125 output hashes.  Golden tensors
are intentionally not stored: 50 D640 tensors would consume about 123 MB,
while their SHA-256 digests provide the runtime's bit-exact PASS oracle.
"""

from __future__ import annotations

import argparse
import hashlib
import io
import json
import shutil
import tempfile
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageOps, __version__ as PILLOW_VERSION


CLASSES = (
    "airplane", "automobile", "bird", "cat", "deer",
    "dog", "frog", "horse", "ship", "truck",
)
SOURCE_TEMPLATE = "https://cave.cs.toronto.edu/kriz/cifar-10-sample/{class_name}{index}.png"
PROFILE = "D640_CFGLUT125"
W, H, N, K = 640, 480, 3, 4
ARCHIVE_MD5 = "c58f30108f718f92721af3b95e74349a"


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def read_json(path: Path) -> dict:
    return json.loads(path.read_text(encoding="utf-8"))


def signed8(token: str) -> int:
    value = int(token, 16)
    if not 0 <= value <= 255:
        raise ValueError(f"coefficient out of range: {token}")
    return value - 256 if value >= 128 else value


def load_channels(profiles_root: Path) -> tuple[list[tuple[np.ndarray, int, int, bool]], dict]:
    bundle = profiles_root / "D640"
    config_path = bundle / "channel_config.json"
    config = read_json(config_path)
    if (config.get("N"), config.get("K"), config.get("bias_width")) != (N, K, 24):
        raise ValueError("D640 numerical contract changed")
    channels = []
    weight_hashes = {}
    for index, entry in enumerate(config["channels"]):
        if entry.get("channel") != index:
            raise ValueError("non-canonical channel order")
        weight_path = bundle / entry["weights_file"]
        tokens = weight_path.read_text(encoding="ascii").split()
        if len(tokens) != N * N:
            raise ValueError(f"{weight_path}: expected {N * N} coefficients")
        kernel = np.asarray([signed8(token) for token in tokens], dtype=np.int64).reshape(N, N)
        channels.append((kernel, int(entry["bias_quantized"]),
                         int(entry["shift"]), bool(entry["relu_en"])))
        weight_hashes[weight_path.name] = digest(weight_path.read_bytes())
    identity = {
        "bundle_dir": "D640",
        "channel_config_sha256": digest(config_path.read_bytes()),
        "weights": weight_hashes,
    }
    return channels, identity


def canonical_pixels(source: bytes) -> tuple[bytes, dict]:
    with Image.open(io.BytesIO(source), formats=("PNG",)) as image:
        if image.format != "PNG" or image.size != (32, 32):
            raise ValueError("official sample is not a 32x32 PNG")
        if getattr(image, "n_frames", 1) != 1:
            raise ValueError("multiframe sample")
        image.load()
        oriented = ImageOps.exif_transpose(image)
        if image.mode in ("LA", "RGBA") or "transparency" in image.info:
            rgba = oriented.convert("RGBA")
            white = Image.new("RGBA", rgba.size, (255, 255, 255, 255))
            gray = Image.alpha_composite(white, rgba).convert("L")
            alpha_policy = "composite_white"
        else:
            gray = oriented if image.mode == "L" else oriented.convert("L")
            alpha_policy = "none"
        resized = gray.resize((W, H), Image.Resampling.LANCZOS)
        pixels = resized.tobytes()
        metadata = {
            "source_format": image.format,
            "source_mode": image.mode,
            "source_width": image.width,
            "source_height": image.height,
            "target_width": W,
            "target_height": H,
            "geometry_policy": "resize_exact",
            "resize_filter": "LANCZOS",
            "alpha_policy": alpha_policy,
            "pillow_version": PILLOW_VERSION,
            "preprocessing_version": "1",
        }
    if len(pixels) != W * H:
        raise ValueError("canonical byte count mismatch")
    return pixels, metadata


def pad_pixels(raw: bytes) -> bytes:
    image = np.frombuffer(raw, dtype=np.uint8).reshape(H, W)
    return np.pad(image, 1, mode="constant").tobytes()


def golden_output(raw: bytes, channels: list[tuple[np.ndarray, int, int, bool]]) -> bytes:
    image = np.frombuffer(raw, dtype=np.uint8).reshape(H, W).astype(np.int64)
    padded = np.pad(image, 1, mode="constant")
    windows = np.lib.stride_tricks.sliding_window_view(padded, (N, N))
    planes = []
    for kernel, bias, shift, relu in channels:
        values = np.einsum("ijxy,xy->ij", windows, kernel, dtype=np.int64) + bias
        if shift:
            values = (values + (1 << (shift - 1))) >> shift
        values = np.clip(values, -32768, 32767)
        if relu:
            values = np.maximum(values, 0)
        planes.append(values.astype("<i2", copy=False))
    interleaved = np.stack(planes, axis=-1).astype("<i2", copy=False).tobytes()
    if len(interleaved) != W * H * K * 2:
        raise ValueError("golden output byte count mismatch")
    return interleaved


def fetch(url: str) -> bytes:
    request = urllib.request.Request(url, headers={"User-Agent": "ConvLab-library-builder/1"})
    with urllib.request.urlopen(request, timeout=30) as response:
        data = response.read(1_000_001)
    if not 0 < len(data) <= 1_000_000:
        raise ValueError(f"unexpected sample size from {url}")
    return data


def load_source(source_dir: Path | None, class_name: str, index: int) -> tuple[bytes, str]:
    url = SOURCE_TEMPLATE.format(class_name=class_name, index=index)
    if source_dir is None:
        return fetch(url), url
    path = source_dir / f"{class_name}{index}.png"
    return path.read_bytes(), url


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")


def main() -> None:
    repo = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output", type=Path, default=(
        repo / "deploy/petalinux/recipes-apps/conv-lab-starter/files/demo_library"))
    parser.add_argument("--source-dir", type=Path,
                        help="optional directory containing airplane1.png .. truck5.png")
    parser.add_argument("--replace", action="store_true")
    args = parser.parse_args()

    output = args.output.resolve()
    if output.exists() and not args.replace:
        raise SystemExit(f"output exists; pass --replace only after review: {output}")

    profiles_root = repo / "profiles"
    software_root = repo / "software"
    releases = read_json(profiles_root / "m7_profiles.json")
    hardware = read_json(software_root / f"hardware_{PROFILE}.json")["accelerator"]
    release = releases["releases"][PROFILE]
    channels, parameters = load_channels(profiles_root)

    # Prove the vectorized generator against the already qualified D640 anchor.
    anchor_source = (repo / "deploy/petalinux/recipes-apps/conv-lab-starter/files/"
                     "dataset/images/alley_cat_s_000013.png").read_bytes()
    anchor_raw, _ = canonical_pixels(anchor_source)
    anchor_actual = digest(golden_output(anchor_raw, channels))
    anchor_expected = read_json(profiles_root / "anchors_m7.json")[PROFILE]["output_sha256"]
    if anchor_actual != anchor_expected:
        raise SystemExit(f"D640 anchor self-check failed: {anchor_actual} != {anchor_expected}")

    output.parent.mkdir(parents=True, exist_ok=True)
    staging = Path(tempfile.mkdtemp(prefix="cifar10-demo-", dir=output.parent))
    try:
        images = []
        common_preprocessing = None
        for class_name in CLASSES:
            class_dir = staging / "images" / class_name
            class_dir.mkdir(parents=True)
            for index in range(1, 6):
                source, source_url = load_source(args.source_dir, class_name, index)
                raw, metadata = canonical_pixels(source)
                if common_preprocessing is None:
                    common_preprocessing = metadata
                elif metadata != common_preprocessing:
                    raise ValueError("sample preprocessing metadata differs")
                padded = pad_pixels(raw)
                output_bytes = golden_output(raw, channels)
                filename = f"{class_name}_{index:02d}.png"
                relative = f"images/{class_name}/{filename}"
                (class_dir / filename).write_bytes(source)
                images.append({
                    "id": f"cifar10-test-{class_name}-{index:02d}",
                    "class": class_name,
                    "display_name": f"{class_name.title()} {index}",
                    "relative_path": relative,
                    "source_url": source_url,
                    "source_sha256": digest(source),
                    "references": {
                        PROFILE: {
                            "canonical_sha256": digest(raw),
                            "padded_tx_sha256": digest(padded),
                            "output_sha256": digest(output_bytes),
                            "expected_output_bytes": len(output_bytes),
                        }
                    },
                })

        profile_identity = {
            "shape_id": release["shape_id"],
            "build_id_hex": release["build_id_hex"],
            "bundle_sha256": release["bundle_sha256"],
            "W": hardware["image_w"], "H": hardware["image_h"],
            "N": hardware["kernel_n"], "K": hardware["channels_k"],
            "expected_output_bytes": hardware["expected_output_bytes"],
            "parameters": parameters,
        }
        catalog = {
            "schema_version": 1,
            "catalog_id": "cifar10-official-samples-5-per-class-d640-v1",
            "dataset": {
                "name": "CIFAR-10",
                "split": "official-page-random-samples",
                "classes": list(CLASSES),
                "images_per_class": 5,
                "source_page": "https://cave.cs.toronto.edu/kriz/cifar.html",
                "official_python_archive_md5": ARCHIVE_MD5,
                "selection": "official sample images 1 through 5 for each class",
                "citation": "Alex Krizhevsky, Learning Multiple Layers of Features from Tiny Images, 2009",
            },
            "preprocessing": common_preprocessing,
            "profiles": {PROFILE: profile_identity},
            "images": images,
        }
        write_json(staging / "reference_catalog.json", catalog)
        write_json(staging / "dataset.json", {
            "schema_version": 1,
            "dataset_id": "cifar10-official-demo-50",
            "classes": list(CLASSES),
            "images_per_class": 5,
            "image_count": len(images),
            "reference_catalog": "reference_catalog.json",
        })
        (staging / "SOURCE.md").write_text(
            "# CIFAR-10 demo-library source\n\n"
            "These 50 PNGs are official CIFAR-10 page samples 1-5 for each of the ten "
            "classes. The catalog records the source URL and SHA-256 of every file. "
            "Cite Alex Krizhevsky, *Learning Multiple Layers of Features from Tiny "
            "Images* (2009). Redistribution clearance remains the responsibility of "
            "the project team; this file is provenance, not a license grant.\n",
            encoding="utf-8", newline="\n")

        files = sorted(path for path in staging.rglob("*") if path.is_file())
        sums = "".join(f"{digest(path.read_bytes())}  {path.relative_to(staging).as_posix()}\n"
                       for path in files)
        (staging / "SHA256SUMS.txt").write_text(sums, encoding="ascii", newline="\n")

        if output.exists():
            shutil.rmtree(output)
        staging.replace(output)
        print(json.dumps({
            "status": "PASS", "output": str(output), "images": len(images),
            "classes": len(CLASSES), "anchor_sha256": anchor_actual,
            "catalog_sha256": digest((output / "reference_catalog.json").read_bytes()),
        }, sort_keys=True))
    except BaseException:
        shutil.rmtree(staging, ignore_errors=True)
        raise


if __name__ == "__main__":
    main()
