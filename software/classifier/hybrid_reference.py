"""NumPy reference for FPGA Conv1 followed by the trained software tail."""

from __future__ import annotations

from dataclasses import dataclass
import hashlib
import json
from pathlib import Path

import numpy as np

from .checkpoint_reader import load_checkpoint


CLASS_NAMES = (
    "airplane", "automobile", "bird", "cat", "deer",
    "dog", "frog", "horse", "ship", "truck",
)


@dataclass(frozen=True)
class ProfileAssets:
    profile: str
    checkpoint: Path
    parameters: Path


def load_grayscale(path: str | Path, width: int = 32, height: int = 32) -> np.ndarray:
    from PIL import Image
    with Image.open(path) as image:
        image.load()
        gray = image.convert("L")
        if gray.size != (width, height):
            gray = gray.resize((width, height), Image.Resampling.LANCZOS)
        return np.asarray(gray, dtype=np.uint8).copy()


def _signed_byte(text: str) -> int:
    value = int(text, 16)
    if not 0 <= value <= 255:
        raise ValueError("kernel byte is out of range")
    return value - 256 if value >= 128 else value


def load_parameters(directory: str | Path) -> list[tuple[np.ndarray, int, int, bool]]:
    directory = Path(directory)
    config = json.loads((directory / "channel_config.json").read_text(encoding="utf-8"))
    n, k = int(config["N"]), int(config["K"])
    channels = []
    if len(config["channels"]) != k:
        raise ValueError("channel configuration count mismatch")
    for index, channel in enumerate(config["channels"]):
        if int(channel["channel"]) != index:
            raise ValueError("channels must be contiguous and ordered")
        lines = (directory / channel["weights_file"]).read_text(
            encoding="ascii").splitlines()
        weights = np.array([_signed_byte(line.strip()) for line in lines if line.strip()],
                           dtype=np.int64)
        if weights.size != n * n:
            raise ValueError("kernel coefficient count mismatch")
        channels.append((weights.reshape(n, n), int(channel["bias_quantized"]),
                         int(channel["shift"]), bool(channel["relu_en"])))
    return channels


def fpga_conv1(image: np.ndarray, parameters: str | Path) -> np.ndarray:
    """Return K×H×W signed-int16 output using the RTL arithmetic contract."""
    if image.ndim != 2 or image.dtype != np.uint8:
        raise ValueError("FPGA input must be a two-dimensional uint8 image")
    channels = load_parameters(parameters)
    n = channels[0][0].shape[0]
    radius = n // 2
    height, width = image.shape
    padded = np.pad(image.astype(np.int64), radius, mode="constant")
    outputs = []
    for kernel, bias, shift, relu in channels:
        total = np.full((height, width), bias, dtype=np.int64)
        for row in range(n):
            for column in range(n):
                total += padded[row:row + height, column:column + width] * kernel[row, column]
        if shift:
            total = (total + (1 << (shift - 1))) >> shift
        total = np.clip(total, -32768, 32767)
        if relu:
            total = np.maximum(total, 0)
        outputs.append(total.astype(np.int16))
    return np.stack(outputs)


def interleaved_output_sha256(values: np.ndarray) -> str:
    raw = values.transpose(1, 2, 0).astype("<i2", copy=False).tobytes()
    return hashlib.sha256(raw).hexdigest()


def _conv2d_same(x: np.ndarray, weight: np.ndarray, bias: np.ndarray) -> np.ndarray:
    if weight.ndim != 4 or x.ndim != 3 or weight.shape[1] != x.shape[0]:
        raise ValueError("convolution shape mismatch")
    kh, kw = weight.shape[2:]
    if kh % 2 != 1 or kw % 2 != 1:
        raise ValueError("only odd same-mode kernels are supported")
    padded = np.pad(x, ((0, 0), (kh // 2, kh // 2), (kw // 2, kw // 2)))
    windows = np.lib.stride_tricks.sliding_window_view(
        padded, (kh, kw), axis=(1, 2))
    result = np.einsum("chwkl,ockl->ohw", windows, weight,
                       optimize=True, dtype=np.float32)
    return result + bias[:, None, None]


def _maxpool2(x: np.ndarray) -> np.ndarray:
    channels, height, width = x.shape
    if height % 2 or width % 2:
        raise ValueError("2x2 pooling requires even spatial dimensions")
    return x.reshape(channels, height // 2, 2, width // 2, 2).max(axis=(2, 4))


def _tail(conv1_output: np.ndarray, state: dict[str, np.ndarray]) -> np.ndarray:
    x = np.maximum(conv1_output.astype(np.float32), 0.0)
    x = _maxpool2(x)
    x = np.maximum(_conv2d_same(x, state["conv2.weight"], state["conv2.bias"]), 0.0)
    x = _maxpool2(x)
    x = np.maximum(_conv2d_same(x, state["conv3.weight"], state["conv3.bias"]), 0.0)
    x = x.reshape(-1)
    x = np.maximum(state["fc1.weight"] @ x + state["fc1.bias"], 0.0)
    return state["fc2.weight"] @ x + state["fc2.bias"]


def _softmax(logits: np.ndarray) -> np.ndarray:
    shifted = logits.astype(np.float64) - float(np.max(logits))
    values = np.exp(shifted)
    return values / values.sum()


class HybridClassifier:
    def __init__(self, assets: ProfileAssets):
        self.assets = assets
        checkpoint = load_checkpoint(assets.checkpoint)
        self.metadata = checkpoint["metadata"]
        self.state = checkpoint["model_state_dict"]
        if self.metadata["input_size"] != 32 or self.metadata["input_scale_divisor"] != 256:
            raise ValueError("checkpoint input contract is incompatible")

    def float_logits(self, image: np.ndarray) -> np.ndarray:
        x = image.astype(np.float32)[None, :, :] / 256.0
        conv1 = _conv2d_same(x, self.state["conv1.weight"], self.state["conv1.bias"])
        return _tail(conv1, self.state)

    def hybrid_logits(self, image: np.ndarray) -> tuple[np.ndarray, np.ndarray]:
        hardware = fpga_conv1(image, self.assets.parameters)
        logits = _tail(hardware.astype(np.float32) / 256.0, self.state)
        return logits, hardware

    @staticmethod
    def prediction(logits: np.ndarray) -> dict:
        probabilities = _softmax(logits)
        order = np.argsort(probabilities)[::-1]
        return {
            "class_index": int(order[0]),
            "class_name": CLASS_NAMES[int(order[0])],
            "confidence": float(probabilities[order[0]]),
            "top3": [
                {"class_index": int(index), "class_name": CLASS_NAMES[int(index)],
                 "confidence": float(probabilities[index])}
                for index in order[:3]
            ],
        }
