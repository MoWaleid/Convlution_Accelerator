"""Bit-exact golden model for the FPGA convolution accelerator.

Implements the same arithmetic the RTL performs, using Python arbitrary-
precision integers to guarantee bit-exact results.  Also provides a
comparison utility against PyTorch's floating-point Conv1 output.

Numeric contract (same-mode convolution)
────────────────────────────────────────
    Input:       uint8 Q0.8 (pixel / 256), zero-padded by N//2
    Weights:     signed int8 [-127, +127]
    Bias:        signed 32-bit integer
    Accumulator: Python arbitrary-precision int  (≥ 21 bits in RTL)
    Rounding:    round-half-up  →  (acc + (1 << (shift-1))) >> shift
    Saturation:  clamp to signed int16  [-32768, +32767]
    ReLU:        clamp negatives to 0  (independently enabled per channel)
"""
from __future__ import annotations

import json
import math
from pathlib import Path

import numpy as np
from PIL import Image

DATA_DIR = Path(__file__).resolve().parent / "data"
OUT_MIN  = -(1 << 15)      # -32768
OUT_MAX  = (1 << 15) - 1   #  32767

# ═══════════════════════ CONFIGURATION ═══════════════════════
IMAGE_PATH = DATA_DIR / "cifar10_images" / "test" / "cat" / "alley_cat_s_000013.png"  # Test image for golden-vs-PyTorch comparison
# ═════════════════════════════════════════════════════════════

MODEL_PATH  = DATA_DIR / "trained_model.pth"
WEIGHTS_DIR = DATA_DIR / "weights"


# ──────────────────────────────────────────────────────────────
# Core arithmetic (must match RTL exactly)
# ──────────────────────────────────────────────────────────────

def round_half_up(value: int, shift: int) -> int:
    """Arithmetic right-shift with round-half-up (toward +∞) tie-breaking.

    This matches the RTL rounding: add 0.5 ULP (= 1 << (shift-1)) before
    shifting.  Python's ``>>`` is an arithmetic right-shift, so negative
    values are handled correctly.

    Examples
    ────────
        round_half_up( 5, 2) →  1    ( 5 + 2 =  7,   7 >> 2 =  1)
        round_half_up( 6, 2) →  2    ( 6 + 2 =  8,   8 >> 2 =  2)
        round_half_up(-5, 2) → -1    (-5 + 2 = -3,  -3 >> 2 = -1)
        round_half_up(-6, 2) → -1    (-6 + 2 = -4,  -4 >> 2 = -1)
    """
    if shift < 0:
        raise ValueError("shift must be non-negative")
    if shift == 0:
        return value
    return (value + (1 << (shift - 1))) >> shift


def saturate_int16(value: int) -> int:
    """Clamp an integer to the signed 16-bit range [-32768, +32767]."""
    return min(OUT_MAX, max(OUT_MIN, value))


# ──────────────────────────────────────────────────────────────
# Golden convolution
# ──────────────────────────────────────────────────────────────

def golden_conv2d(image: np.ndarray, kernel: np.ndarray,
                  bias: int, shift: int, relu_en: bool = True) -> np.ndarray:
    """Compute one same-mode convolution feature map exactly as the RTL does.

    The input image is zero-padded by N//2 on each side so the output has
    the same spatial dimensions as the input (same-mode convolution).

    Args:
        image:    2-D uint8 array (H, W) — raw pixel values [0, 255]
        kernel:   2-D int8 array  (N, N) — quantized filter coefficients
        bias:     signed 32-bit integer bias (pre-scaled to accumulator units)
        shift:    right-shift amount applied after accumulation
        relu_en:  if True, clamp negative output values to zero

    Returns:
        2-D int16 array (H, W) — the convolution output feature map
    """
    if image.ndim != 2 or image.dtype != np.uint8:
        raise ValueError("image must be a 2-D uint8 array")
    if (kernel.ndim != 2 or kernel.shape[0] != kernel.shape[1]
            or kernel.dtype != np.int8):
        raise ValueError("kernel must be a square int8 array")

    n      = kernel.shape[0]
    h, w   = image.shape
    pad    = n // 2

    # Zero-pad the input (same-mode convolution)
    padded = np.pad(image, pad, mode="constant", constant_values=0)

    # Output has the same spatial dimensions as the original (unpadded) input
    result = np.empty((h, w), dtype=np.int16)

    for row in range(h):
        for col in range(w):
            acc = int(bias)
            for kr in range(n):
                for kc in range(n):
                    acc += int(padded[row + kr, col + kc]) * int(kernel[kr, kc])
            value = saturate_int16(round_half_up(acc, shift))
            result[row, col] = max(0, value) if relu_en else value

    return result


# ──────────────────────────────────────────────────────────────
# Weight loading
# ──────────────────────────────────────────────────────────────

def load_weights_and_config(weights_dir: str | Path) -> tuple[dict, list[np.ndarray]]:
    """Load channel configuration and kernel coefficients from an export directory.

    Validates the format_version, boundary_mode, and kernel dimensions.
    Converts hex byte values in .mem files to signed int8 numpy arrays.

    Args:
        weights_dir: path to the directory containing channel_config.json
                     and kernel_ch*.mem files

    Returns:
        config:  the parsed channel_config.json dictionary
        kernels: list of (N, N) int8 numpy arrays, one per channel
    """
    directory = Path(weights_dir)
    config = json.loads(
        (directory / "channel_config.json").read_text(encoding="utf-8")
    )

    # Validate contract
    required_keys = {
        "format_version", "N", "K", "boundary_mode",
        "output_fraction_bits", "channels",
    }
    missing = required_keys - set(config.keys())
    if missing:
        raise ValueError(f"channel_config.json is missing required keys: {missing}")
    if config["format_version"] != 2:
        raise ValueError(
            f"Expected format_version 2, got {config['format_version']}. "
            f"Re-export with the current extract_weights.py."
        )
    if config["boundary_mode"] != "same":
        raise ValueError(
            f"Expected boundary_mode 'same', got '{config['boundary_mode']}'. "
            f"Re-export with the current extract_weights.py."
        )
    if len(config["channels"]) != config["K"]:
        raise ValueError(
            f"K={config['K']} but found {len(config['channels'])} channel entries"
        )

    # Load kernel coefficients from .mem files
    n = config["N"]
    kernels = []
    for channel in config["channels"]:
        ch_idx   = channel["channel"]
        mem_path = directory / f"kernel_ch{ch_idx}.mem"
        raw_lines = [
            line.strip()
            for line in mem_path.read_text(encoding="ascii").splitlines()
            if line.strip() and not line.startswith("#")
        ]
        if len(raw_lines) != n * n:
            raise ValueError(
                f"kernel_ch{ch_idx}.mem has {len(raw_lines)} values, "
                f"expected {n * n}"
            )

        # Parse hex bytes and convert to signed int8
        unsigned_vals = [int(word, 16) for word in raw_lines]
        if any(v > 0xFF for v in unsigned_vals):
            raise ValueError(f"kernel_ch{ch_idx}.mem contains a value exceeding 0xFF")
        signed_vals = [v - 256 if v >= 128 else v for v in unsigned_vals]
        kernels.append(
            np.asarray(signed_vals, dtype=np.int8).reshape(n, n)
        )

    return config, kernels


def run_golden_conv_all_channels(image: np.ndarray,
                                 weights_dir: str | Path) -> tuple[np.ndarray, dict]:
    """Run the golden convolution for every channel in the weights directory.

    Args:
        image:       2-D uint8 array (H, W)
        weights_dir: directory containing channel_config.json + kernel files

    Returns:
        outputs: (K, H, W) int16 array — one feature map per channel
        config:  the parsed channel configuration dictionary
    """
    config, kernels = load_weights_and_config(weights_dir)
    outputs = [
        golden_conv2d(
            image, kernel,
            int(ch["bias_quantized"]),
            int(ch["shift"]),
            bool(ch["relu_en"]),
        )
        for ch, kernel in zip(config["channels"], kernels)
    ]
    return np.stack(outputs), config


# ──────────────────────────────────────────────────────────────
# PyTorch reference comparison
# ──────────────────────────────────────────────────────────────

def run_pytorch_conv1(image: np.ndarray, model_path: str | Path) -> np.ndarray:
    """Run PyTorch's float32 Conv1 + ReLU on a raw uint8 image for comparison.

    This loads the full model but only executes Conv1 + ReLU, producing the
    floating-point reference that the golden model's quantized output should
    closely approximate.

    Note: torch and train_cifar10 are imported inside this function to avoid
    loading the heavy PyTorch library when only the golden convolution (pure
    numpy) is needed.

    Returns:
        (K, H, W) float32 array — one feature map per Conv1 output channel
    """
    import torch
    from train_cifar10 import CIFAR10GrayCNN

    checkpoint = torch.load(model_path, map_location="cpu", weights_only=True)
    if checkpoint.get("format_version") != 2:
        raise ValueError("Checkpoint is not format_version 2")
    if checkpoint.get("boundary_mode") != "same":
        raise ValueError("Checkpoint boundary_mode is not 'same'")
    if checkpoint.get("input_scale_divisor") != 256:
        raise ValueError("Checkpoint does not use uint8/256 input convention")

    model = CIFAR10GrayCNN(
        checkpoint["kernel_size"],
        checkpoint["num_channels"],
        checkpoint.get("input_size", 32),
    )
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()

    tensor = (
        torch.from_numpy(image.astype(np.float32))
        .unsqueeze(0).unsqueeze(0) / 256.0
    )
    with torch.no_grad():
        output = model.relu1(model.conv1(tensor))
    return output.squeeze(0).numpy()


def compare_golden_vs_pytorch(golden: np.ndarray, pytorch: np.ndarray,
                              config: dict) -> list[dict]:
    """Compare quantized golden output against PyTorch float reference.

    For each channel, reports maximum and mean absolute error (in float
    units after de-scaling the golden fixed-point values) and Pearson
    correlation coefficient.

    Returns:
        List of dicts with keys: channel, source_channel, max_abs_error,
        mean_abs_error, correlation
    """
    scale = float(1 << config["output_fraction_bits"])
    rows  = []

    for ch_info in config["channels"]:
        g_ch = ch_info["channel"]
        p_ch = ch_info.get("source_channel", g_ch)

        # Convert golden fixed-point to float for comparison
        fixed_float = golden[g_ch].astype(np.float64) / scale
        reference   = pytorch[p_ch].astype(np.float64)

        if fixed_float.shape != reference.shape:
            raise ValueError(
                f"Shape mismatch on ch{g_ch}: "
                f"golden {fixed_float.shape} vs PyTorch {reference.shape}"
            )

        abs_diff = np.abs(fixed_float - reference)
        if np.std(fixed_float) > 0 and np.std(reference) > 0:
            corr = float(np.corrcoef(fixed_float.flat, reference.flat)[0, 1])
        else:
            corr = math.nan

        rows.append({
            "channel":        g_ch,
            "source_channel": p_ch,
            "max_abs_error":  float(np.max(abs_diff)),
            "mean_abs_error": float(np.mean(abs_diff)),
            "correlation":    corr,
        })

    return rows


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

def main() -> None:
    """Run the golden model and compare against the PyTorch reference."""
    # Load test image
    if not IMAGE_PATH.exists():
        raise FileNotFoundError(f"Test image not found: {IMAGE_PATH}")
    image = np.asarray(Image.open(IMAGE_PATH).convert("L"), dtype=np.uint8)
    print(f"Input image : {IMAGE_PATH.name}  ({image.shape[0]}×{image.shape[1]})")

    # Run golden convolution
    if not WEIGHTS_DIR.exists():
        raise FileNotFoundError(
            f"Weights directory not found: {WEIGHTS_DIR}. "
            f"Run extract_weights.py first."
        )
    outputs, config = run_golden_conv_all_channels(image, WEIGHTS_DIR)
    print(
        f"Golden output: {config['K']} channels, "
        f"{outputs.shape[1]}×{outputs.shape[2]} each"
    )
    print(
        f"Output range : [{outputs.min()}, {outputs.max()}]  "
        f"(signed Q{config['output_fraction_bits']})"
    )

    # Compare against PyTorch reference
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Trained model not found: {MODEL_PATH}. "
            f"Run train_cifar10.py first."
        )
    pytorch_out = run_pytorch_conv1(image, MODEL_PATH)
    rows = compare_golden_vs_pytorch(outputs, pytorch_out, config)

    print(f"\n{'Ch':>3} {'Src':>4} {'Max Err':>10} {'Mean Err':>10} {'Corr':>8}")
    print("-" * 40)
    for r in rows:
        print(
            f"{r['channel']:3d} {r['source_channel']:4d} "
            f"{r['max_abs_error']:10.6f} {r['mean_abs_error']:10.6f} "
            f"{r['correlation']:8.6f}"
        )


if __name__ == "__main__":
    main()
