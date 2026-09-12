"""Export FPGA-ready Conv1 filters from a trained checkpoint.

Reads the trained model's Conv1 weights (float32), quantizes every output
channel to signed int8 coefficients + signed 32-bit bias, and writes the
per-channel configuration consumed by the VHDL register bank.

All channels are exported sequentially (channel 0, 1, 2, …, K-1).

Numeric contract
────────────────
    Input pixels:  uint8 Q0.8  (pixel / 256)
    Coefficients:  signed int8 [-127, +127]
    Bias:          signed 32-bit integer
    Output:        signed int16 Q8 (after round-half-up shift)

Quantization scheme
───────────────────
    q_weight = round(weight × 2^Fw)         Fw = floor(log2(127 / max|w|))
    q_bias   = round(bias   × 2^(Fw + 8))
    shift    = Fw + 8 − F_out
    q_out    = round_half_up((Σ pixel×q_weight + q_bias) >> shift)
"""
from __future__ import annotations

import json
import math
import os
from pathlib import Path

import numpy as np
import torch

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR   = SCRIPT_DIR / "data"

# ═══════════════════════ CONFIGURATION ═══════════════════════
# Overridable via environment for per-profile runs (defaults = profile A):
#   CNN_MODEL, CNN_WEIGHTS_DIR — see M7_CONTINUATION.md.
OUTPUT_FRACTION_BITS = 8     # Fractional bits in the int16 output: Q(16-F).F format (8 → Q8.8)
RELU_EN              = True  # Enable ReLU on all exported channels (clamp negatives to 0)
# ═════════════════════════════════════════════════════════════

PIXEL_FRACTION_BITS = 8
INT8_MAX            = 127
MODEL_PATH          = Path(os.environ.get("CNN_MODEL", str(DATA_DIR / "trained_model.pth")))
WEIGHTS_DIR         = Path(os.environ.get("CNN_WEIGHTS_DIR", str(DATA_DIR / "weights")))


# ──────────────────────────────────────────────────────────────
# Quantization
# ──────────────────────────────────────────────────────────────

def quantize_channel(kernel: np.ndarray, bias: float,
                     output_fraction_bits: int) -> tuple[np.ndarray, int, int, int]:
    """Quantize one Conv1 channel to the FPGA's fixed-point format.

    Args:
        kernel:               float32 array (N, N) — one Conv1 filter
        bias:                 float32 bias for this channel
        output_fraction_bits: number of fractional bits in the int16 output

    Returns:
        q_kernel: int8 array (N, N) of quantized coefficients
        q_bias:   quantized bias (signed 32-bit integer)
        shift:    right-shift applied after accumulation
        fw:       weight fraction bits (scale = 2^fw)

    Raises:
        ValueError: if the computed shift falls outside the hardware's
                    5-bit range [0, 31] or the bias doesn't fit 32 bits.
    """
    max_abs = float(np.max(np.abs(kernel)))
    if max_abs == 0.0:
        fw = 0
    else:
        fw = max(0, math.floor(math.log2(INT8_MAX / max_abs)))

    scale    = 1 << fw
    q_kernel = np.clip(np.rint(kernel * scale), -INT8_MAX, INT8_MAX).astype(np.int8)

    shift = fw + PIXEL_FRACTION_BITS - output_fraction_bits
    if not 0 <= shift <= 31:
        raise ValueError(
            f"Computed shift={shift} is outside the hardware's 5-bit range [0, 31]"
        )

    q_bias = int(np.rint(float(bias) * (1 << (fw + PIXEL_FRACTION_BITS))))
    if not -(1 << 31) <= q_bias < (1 << 31):
        raise ValueError(
            f"Quantized bias {q_bias} does not fit in signed 32 bits"
        )

    return q_kernel, q_bias, shift, fw


# ──────────────────────────────────────────────────────────────
# File I/O
# ──────────────────────────────────────────────────────────────

def write_kernel_mem(path: Path, values: np.ndarray) -> None:
    """Write kernel coefficients as two's-complement hex bytes, one per line.

    Each signed int8 value is masked to an unsigned byte and written as a
    2-digit uppercase hex string.  This is the format expected by the VHDL
    testbench ($readmemh).
    """
    lines = [f"{int(v) & 0xFF:02X}\n" for v in values.reshape(-1)]
    path.write_text("".join(lines), encoding="ascii")


def export_checkpoint(model_path: Path, output_dir: Path,
                      output_fraction_bits: int, relu_en: bool) -> dict:
    """Load a checkpoint, quantize all Conv1 channels, write FPGA files.

    Files written to output_dir:
        kernel_ch{i}.mem    – hex coefficient file per channel
        channel_config.json – complete hardware configuration
        quant_info.txt      – human-readable quantization summary

    Args:
        model_path:          path to the trained .pth checkpoint
        output_dir:          directory to write exported files into
        output_fraction_bits: fractional bits for the int16 output
        relu_en:             whether to enable ReLU on all channels

    Returns:
        The channel_config dictionary that was written to JSON.
    """
    checkpoint = torch.load(model_path, map_location="cpu", weights_only=True)

    # Validate checkpoint contract
    if checkpoint.get("format_version") != 2:
        raise ValueError(
            "Checkpoint is not format_version 2. "
            "Retrain with the current train_cifar10.py."
        )
    if checkpoint.get("boundary_mode") != "same":
        raise ValueError(
            "Checkpoint boundary_mode is not 'same'. "
            "Retrain with the current train_cifar10.py."
        )
    if checkpoint.get("input_scale_divisor") != 256:
        raise ValueError(
            "Checkpoint does not use the required uint8/256 input convention."
        )

    state   = checkpoint["model_state_dict"]
    weights = state["conv1.weight"].detach().cpu().numpy()   # [K, 1, N, N]
    biases  = state["conv1.bias"].detach().cpu().numpy()     # [K]

    if (weights.ndim != 4 or weights.shape[1] != 1
            or weights.shape[2] != weights.shape[3]):
        raise ValueError(
            f"Expected Conv1 weights shaped [K, 1, N, N], got {weights.shape}"
        )

    num_channels = weights.shape[0]
    n            = int(weights.shape[2])

    # Prepare output directory (overwrite previous export)
    if output_dir.exists():
        for f in output_dir.iterdir():
            f.unlink()
    output_dir.mkdir(parents=True, exist_ok=True)

    # Quantize and export every channel
    channels = []
    report_lines = [
        "# FPGA Conv1 Quantization Report",
        f"# Source model: {model_path.name}",
        f"# Test accuracy: {checkpoint.get('test_acc', 'N/A'):.2f}%",
        f"# Kernel size (N): {n}",
        f"# Output channels (K): {num_channels}",
        f"# Output fraction bits: {output_fraction_bits}",
        "#",
        f"# {'Ch':>3}  {'Shift':>5}  {'Fw':>3}  {'Bias_Q':>10}  {'MaxAbsW':>12}",
        f"# {'---':>3}  {'-----':>5}  {'---':>3}  {'----------':>10}  {'------------':>12}",
    ]

    for ch in range(num_channels):
        q_kernel, q_bias, shift, fw = quantize_channel(
            weights[ch, 0], float(biases[ch]), output_fraction_bits,
        )
        write_kernel_mem(output_dir / f"kernel_ch{ch}.mem", q_kernel)

        channels.append({
            "channel":             ch,
            "source_channel":      ch,
            "shift":               shift,
            "weight_fraction_bits": fw,
            "bias_fraction_bits":  fw + PIXEL_FRACTION_BITS,
            "bias_quantized":      q_bias,
            "relu_en":             int(relu_en),
        })
        report_lines.append(
            f"  {ch:3d}  {shift:5d}  {fw:3d}  "
            f"{q_bias:10d}  {np.max(np.abs(weights[ch, 0])):12.8f}"
        )

    # Write channel configuration JSON
    config = {
        "format_version":       2,
        "N":                    n,
        "K":                    num_channels,
        "boundary_mode":        "same",
        "stride":               1,
        "pixel_format":         "uint8_q0.8",
        "input_scale_divisor":  256,
        "coefficient_format":   "int8_raw",
        "bias_bits":            32,
        "output_format":        f"int16_q{output_fraction_bits}",
        "output_fraction_bits": output_fraction_bits,
        "accumulator_width_min": 8 + 8 + math.ceil(math.log2(n * n)) + 1,
        "channels":             channels,
    }
    (output_dir / "channel_config.json").write_text(
        json.dumps(config, indent=2) + "\n", encoding="utf-8",
    )

    # Write human-readable quantization report
    (output_dir / "quant_info.txt").write_text(
        "\n".join(report_lines) + "\n", encoding="utf-8",
    )

    return config


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

def main() -> None:
    """Export all Conv1 filters from the trained model."""
    if not MODEL_PATH.exists():
        raise FileNotFoundError(
            f"Trained model not found at {MODEL_PATH}. "
            f"Run train_cifar10.py first."
        )

    checkpoint  = torch.load(MODEL_PATH, map_location="cpu", weights_only=True)
    output_frac = checkpoint.get("output_fraction_bits", OUTPUT_FRACTION_BITS)
    if not 0 <= output_frac <= 15:
        raise ValueError(f"output_fraction_bits={output_frac} is out of range [0, 15]")

    config = export_checkpoint(MODEL_PATH, WEIGHTS_DIR, output_frac, RELU_EN)

    print(f"Exported {config['K']} channels, {config['N']}×{config['N']} kernels")
    print(f"  Output directory : {WEIGHTS_DIR}")
    print(f"  Boundary mode    : {config['boundary_mode']}")
    print(f"  Output format    : {config['output_format']}")
    print(f"  ReLU             : {'ON' if RELU_EN else 'OFF'}")
    print()
    for ch_info in config["channels"]:
        print(
            f"  ch{ch_info['channel']:2d}:  shift={ch_info['shift']},  "
            f"bias_q={ch_info['bias_quantized']:>7d},  "
            f"relu={'ON' if ch_info['relu_en'] else 'OFF'}"
        )


if __name__ == "__main__":
    main()
