"""Generate test vectors (stimulus + expected outputs) for Vivado RTL simulation.

Produces four categories of test vectors:
    1. Trained  – using the exported Conv1 weights from the trained model
    2. Custom   – using hand-crafted demo filters (identity, Sobel, blur)
    3. Zeros    – all-zero input with trained weights (corner case)
    4. Ones     – all-255 input with trained weights (corner case)

Each test vector set contains:
    input.hex            – row-major uint8 pixel values  (2-digit hex, one per line)
    expected_ch{i}.hex   – row-major int16 output values (4-digit hex, one per line)
    manifest.txt         – metadata about the generation parameters
    png/                 – visual inspection images      (.png)

File format
───────────
    All .hex files use one value per line, uppercase hex, no address prefix.
    This is compatible with Verilog's $readmemh directive.
    Negative int16 values are stored as 16-bit two's-complement (e.g. -1 → FFFF).
"""
from __future__ import annotations

import datetime
from pathlib import Path

import numpy as np
from PIL import Image

from golden_conv import (
    golden_conv2d,
    run_golden_conv_all_channels,
    DATA_DIR,
    IMAGE_PATH,
    WEIGHTS_DIR,
)


# ──────────────────────────────────────────────────────────────
# Custom demo filters
# ──────────────────────────────────────────────────────────────

def get_custom_filters() -> tuple[list[np.ndarray], dict]:
    """Return hand-crafted demo filters and their hardware configuration.

    Filters
    ───────
        ch0 – Identity (scaled): passes the image through with ≈1.0 gain
        ch1 – Sobel X:           horizontal edge detector
        ch2 – Sobel Y:           vertical edge detector
        ch3 – Box blur:          3×3 weighted average

    ReLU is disabled for custom filters to preserve their full signed
    output range (e.g. Sobel filters produce meaningful negative values
    for edges in both directions).
    """
    config = {
        "format_version": 2,
        "N": 3,
        "K": 4,
        "boundary_mode": "same",
        "stride": 1,
        "pixel_format": "uint8_q0.8",
        "input_scale_divisor": 256,
        "coefficient_format": "int8_raw",
        "bias_bits": 32,
        "output_format": "int16_q8",
        "output_fraction_bits": 8,
        "channels": [
            {"channel": 0, "shift": 7, "bias_quantized": 0, "relu_en": 0},
            {"channel": 1, "shift": 8, "bias_quantized": 0, "relu_en": 0},
            {"channel": 2, "shift": 8, "bias_quantized": 0, "relu_en": 0},
            {"channel": 3, "shift": 4, "bias_quantized": 0, "relu_en": 0},
        ],
    }

    # Validate shift ranges against hardware constraint
    for ch in config["channels"]:
        if not 0 <= ch["shift"] <= 31:
            raise ValueError(
                f"Custom filter ch{ch['channel']} has shift={ch['shift']} "
                f"outside the hardware range [0, 31]"
            )

    # Identity: scaled by 127/128 ≈ 0.992 (centre tap only)
    c0 = np.zeros((3, 3), dtype=np.int8)
    c0[1, 1] = 127

    # Sobel X: horizontal edge detector
    c1 = np.array([[-1,  0,  1],
                    [-2,  0,  2],
                    [-1,  0,  1]], dtype=np.int8)

    # Sobel Y: vertical edge detector
    c2 = np.array([[-1, -2, -1],
                    [ 0,  0,  0],
                    [ 1,  2,  1]], dtype=np.int8)

    # Box blur: 3×3 weighted average (approximates Gaussian)
    c3 = np.array([[1, 2, 1],
                    [2, 4, 2],
                    [1, 2, 1]], dtype=np.int8)

    return [c0, c1, c2, c3], config


# ──────────────────────────────────────────────────────────────
# File writers
# ──────────────────────────────────────────────────────────────

def write_test_vectors(image: np.ndarray, outputs: np.ndarray,
                       output_dir: str | Path) -> None:
    """Write RTL-compatible hex test vectors: uint8 input, int16 output.

    Files are formatted for Verilog $readmemh: one hex value per line,
    row-major order, no address prefix.

    Args:
        image:      2-D uint8 input image
        outputs:    3-D int16 array (K, H, W) — one feature map per channel
        output_dir: directory to write the .hex files into
    """
    directory = Path(output_dir)
    directory.mkdir(parents=True, exist_ok=True)

    # Write input pixels as 2-digit unsigned hex
    input_hex = "".join(f"{int(pixel):02X}\n" for pixel in image.flat)
    (directory / "input.hex").write_text(input_hex, encoding="ascii")

    # Write expected outputs as 4-digit two's-complement hex
    for ch_idx, feature_map in enumerate(outputs):
        output_hex = "".join(
            f"{int(val) & 0xFFFF:04X}\n" for val in feature_map.flat
        )
        (directory / f"expected_ch{ch_idx}.hex").write_text(
            output_hex, encoding="ascii"
        )


def write_manifest(output_dir: Path, image_source: str, weights_source: str,
                   image_shape: tuple, output_shape: tuple,
                   num_channels: int, description: str) -> None:
    """Write a manifest file documenting how the test vectors were generated.

    Args:
        output_dir:     directory containing the test vector files
        image_source:   human-readable description of the input image
        weights_source: human-readable description of the weight source
        image_shape:    (H, W) of the input image
        output_shape:   (H, W) of each output feature map
        num_channels:   number of output channels
        description:    free-text description of this test vector set
    """
    timestamp = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    lines = [
        "# Test Vector Manifest",
        f"# Generated: {timestamp}",
        "#",
        f"Description     : {description}",
        f"Image source    : {image_source}",
        f"Image size      : {image_shape[0]}×{image_shape[1]}",
        f"Weights source  : {weights_source}",
        f"Output channels : {num_channels}",
        f"Output size     : {output_shape[0]}×{output_shape[1]} per channel",
        f"Convolution     : same-mode, stride 1, zero-padded",
    ]
    (Path(output_dir) / "manifest.txt").write_text(
        "\n".join(lines) + "\n", encoding="utf-8"
    )


def save_feature_map_pngs(image: np.ndarray, outputs: np.ndarray,
                           output_dir: str | Path) -> None:
    """Save the input image and each feature map as .png for visual inspection.

    Feature maps are normalised to [0, 255] using min–max scaling so the
    full dynamic range is visible.  Constant-valued maps are saved as
    uniform mid-gray (128).

    Output structure:
        {output_dir}/png/input.png
        {output_dir}/png/ch0.png
        {output_dir}/png/ch1.png
        ...
    """
    png_dir = Path(output_dir) / "png"
    png_dir.mkdir(parents=True, exist_ok=True)

    # Save the raw input image
    Image.fromarray(image).save(png_dir / "input.png")

    # Save each output channel as a normalised grayscale image
    for ch_idx, feature_map in enumerate(outputs):
        fmap = feature_map.astype(np.float64)
        fmin, fmax = fmap.min(), fmap.max()
        if fmax > fmin:
            normalised = ((fmap - fmin) / (fmax - fmin) * 255.0).astype(np.uint8)
        else:
            normalised = np.full_like(fmap, 128, dtype=np.uint8)
        Image.fromarray(normalised).save(png_dir / f"ch{ch_idx}.png")


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

def main() -> None:
    """Generate all test vector sets: trained, custom, and corner-cases."""
    # Load test image
    if not IMAGE_PATH.exists():
        raise FileNotFoundError(f"Test image not found: {IMAGE_PATH}")
    image = np.asarray(Image.open(IMAGE_PATH).convert("L"), dtype=np.uint8)
    print(f"Input image: {IMAGE_PATH.name}  ({image.shape[0]}×{image.shape[1]})")

    # ── 1. Trained model filters ──────────────────────────────
    print("\n[1/4] Generating trained-weight vectors...")
    if not WEIGHTS_DIR.exists():
        raise FileNotFoundError(
            f"Weights directory not found: {WEIGHTS_DIR}. "
            f"Run extract_weights.py first."
        )
    outputs_trained, config = run_golden_conv_all_channels(image, WEIGHTS_DIR)
    out_dir = DATA_DIR / "test_vectors_trained"
    write_test_vectors(image, outputs_trained, out_dir)
    write_manifest(
        out_dir, IMAGE_PATH.name, WEIGHTS_DIR.name,
        image.shape, outputs_trained.shape[1:], outputs_trained.shape[0],
        "Trained CIFAR-10 Conv1 filters",
    )
    save_feature_map_pngs(image, outputs_trained, out_dir)
    print(
        f"  → {out_dir}  "
        f"({outputs_trained.shape[0]} ch, "
        f"{outputs_trained.shape[1]}×{outputs_trained.shape[2]})"
    )

    # ── 2. Custom demo filters ────────────────────────────────
    print("\n[2/4] Generating custom demo vectors...")
    kernels, custom_config = get_custom_filters()
    outputs_custom = np.stack([
        golden_conv2d(
            image, k,
            int(ch["bias_quantized"]),
            int(ch["shift"]),
            bool(ch["relu_en"]),
        )
        for ch, k in zip(custom_config["channels"], kernels)
    ])
    out_dir = DATA_DIR / "test_vectors_custom"
    write_test_vectors(image, outputs_custom, out_dir)
    write_manifest(
        out_dir, IMAGE_PATH.name, "custom hand-crafted filters",
        image.shape, outputs_custom.shape[1:], outputs_custom.shape[0],
        "Custom demo filters: Identity, Sobel X, Sobel Y, Blur (ReLU OFF)",
    )
    save_feature_map_pngs(image, outputs_custom, out_dir)
    print(
        f"  → {out_dir}  "
        f"({outputs_custom.shape[0]} ch, "
        f"{outputs_custom.shape[1]}×{outputs_custom.shape[2]})"
    )

    # ── 3. Corner case: all-zeros input ───────────────────────
    print("\n[3/4] Generating all-zeros corner-case vectors...")
    zeros = np.zeros_like(image)
    outputs_zeros, _ = run_golden_conv_all_channels(zeros, WEIGHTS_DIR)
    out_dir = DATA_DIR / "test_vectors_zeros"
    write_test_vectors(zeros, outputs_zeros, out_dir)
    write_manifest(
        out_dir, "synthetic all-zero image", WEIGHTS_DIR.name,
        zeros.shape, outputs_zeros.shape[1:], outputs_zeros.shape[0],
        "Corner case: all-zero input pixels",
    )
    save_feature_map_pngs(zeros, outputs_zeros, out_dir)
    print(f"  → {out_dir}  ({outputs_zeros.shape[0]} ch)")

    # ── 4. Corner case: all-255 input ─────────────────────────
    print("\n[4/4] Generating all-255 corner-case vectors...")
    ones = np.full_like(image, 255)
    outputs_ones, _ = run_golden_conv_all_channels(ones, WEIGHTS_DIR)
    out_dir = DATA_DIR / "test_vectors_ones"
    write_test_vectors(ones, outputs_ones, out_dir)
    write_manifest(
        out_dir, "synthetic all-255 image", WEIGHTS_DIR.name,
        ones.shape, outputs_ones.shape[1:], outputs_ones.shape[0],
        "Corner case: all-255 (maximum value) input pixels",
    )
    save_feature_map_pngs(ones, outputs_ones, out_dir)
    print(f"  → {out_dir}  ({outputs_ones.shape[0]} ch)")

    print("\nDone. All test vectors generated successfully.")


if __name__ == "__main__":
    main()
