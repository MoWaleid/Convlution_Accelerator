"""Train a CIFAR-10 classifier whose first convolutional layer matches the
FPGA numeric contract.

Conv1 is a stride-one, same-mode N×N convolution over single-channel
grayscale Q0.8 pixels (uint8 / 256).  The input is zero-padded by N//2
on each side so the spatial output matches the input (32×32).  Only Conv1
weights are deployed to hardware; the remaining layers exist solely to
provide a training gradient.

Numeric contract
────────────────
    Input:  uint8 / 256  →  Q0.8 fixed-point (range [0, 255/256])
    Conv1:  same-mode, stride 1, zero-padding = kernel_size // 2
    Output: signed int16 Q8 after quantization (see extract_weights.py)
"""
from __future__ import annotations

import random
from pathlib import Path

import numpy as np
import torch
import torch.nn as nn
import torch.optim as optim
import torchvision.datasets as datasets
import torchvision.transforms as transforms
from torch.optim.lr_scheduler import StepLR
from torch.utils.data import DataLoader

SCRIPT_DIR = Path(__file__).resolve().parent
DATA_DIR = SCRIPT_DIR / "data"

# ═══════════════════════ CONFIGURATION ═══════════════════════
EPOCHS         = 50     # Total training epochs (may stop earlier via PATIENCE)
LEARNING_RATE  = 1e-3   # Initial Adam optimizer learning rate (halved every 10 epochs)
BATCH_SIZE     = 128    # Number of images per training mini-batch
KERNEL_SIZE    = 3      # Spatial size of Conv1 filter (N×N); must be odd and >= 3
NUM_CHANNELS   = 8      # Number of Conv1 output channels (K) — deployed to FPGA
SEED           = 2026   # RNG seed for reproducible training (locks random, numpy, torch)
NUM_WORKERS    = 0      # DataLoader worker threads (0 = load in main thread)
DOWNLOAD       = False  # Set True to auto-download CIFAR-10 if not already extracted
PATIENCE       = 10     # Early-stopping: halt after this many epochs with no accuracy gain
# ═════════════════════════════════════════════════════════════

INPUT_SCALE_DIVISOR  = 256
OUTPUT_FRACTION_BITS = 8
MODEL_PATH           = DATA_DIR / "trained_model.pth"
LOG_PATH             = DATA_DIR / "training_log.txt"


# ──────────────────────────────────────────────────────────────
# Preprocessing
# ──────────────────────────────────────────────────────────────

class RGBToGrayscaleQ8Tensor:
    """Convert an RGB PIL image to the exact Q0.8 tensor used by the FPGA.

    Pipeline: PIL RGB → PIL grayscale ("L") → uint8 numpy → float32 / 256.
    The result is a (1, H, W) tensor with values in [0, 255/256].
    """

    def __call__(self, image) -> torch.Tensor:
        pixels = np.asarray(image.convert("L"), dtype=np.float32).copy()
        return torch.from_numpy(pixels).unsqueeze(0) / INPUT_SCALE_DIVISOR


# ──────────────────────────────────────────────────────────────
# Model definition
# ──────────────────────────────────────────────────────────────

class CIFAR10GrayCNN(nn.Module):
    """Small CIFAR-10 classifier with a hardware-compatible Conv1.

    Architecture
    ────────────
        Conv1 (same, NxN) → ReLU → MaxPool 2×2  →
        Conv2 (same, 3×3) → ReLU → MaxPool 2×2  →
        Conv3 (same, 3×3) → ReLU → Dropout(0.5) →
        FC1 (256)          → ReLU →
        FC2 (10)

    Only Conv1 is deployed to the FPGA.  All other layers exist purely to
    provide a training signal for Conv1's weights.
    """

    def __init__(self, kernel_size: int = 3, num_channels: int = NUM_CHANNELS,
                 input_size: int = 32):
        super().__init__()
        if kernel_size < 3 or kernel_size % 2 == 0:
            raise ValueError("kernel_size must be an odd integer >= 3")
        if input_size < kernel_size:
            raise ValueError("input_size must be >= kernel_size")

        self.kernel_size  = kernel_size
        self.num_channels = num_channels
        self.input_size   = input_size

        # Conv1: same-mode convolution (zero-padding = kernel_size // 2)
        self.conv1 = nn.Conv2d(1, num_channels, kernel_size,
                               stride=1, padding=kernel_size // 2, bias=True)
        self.relu1 = nn.ReLU()
        self.pool1 = nn.MaxPool2d(2, 2)

        self.conv2 = nn.Conv2d(num_channels, 32, 3, padding=1)
        self.relu2 = nn.ReLU()
        self.pool2 = nn.MaxPool2d(2, 2)

        self.conv3 = nn.Conv2d(32, 32, 3, padding=1)
        self.relu3 = nn.ReLU()

        self.dropout = nn.Dropout(0.5)

        # Dynamically compute the flattened feature count
        with torch.no_grad():
            dummy = torch.zeros(1, 1, input_size, input_size)
            feature_count = self._features(dummy).numel()

        self.fc1   = nn.Linear(feature_count, 256)
        self.relu4 = nn.ReLU()
        self.fc2   = nn.Linear(256, 10)

    def _features(self, x: torch.Tensor) -> torch.Tensor:
        """Extract spatial features through the convolutional backbone."""
        x = self.pool1(self.relu1(self.conv1(x)))
        x = self.pool2(self.relu2(self.conv2(x)))
        x = self.relu3(self.conv3(x))
        return x

    def forward(self, x: torch.Tensor) -> torch.Tensor:
        x = self._features(x).flatten(1)
        x = self.dropout(self.relu4(self.fc1(x)))
        return self.fc2(x)


# ──────────────────────────────────────────────────────────────
# Training helpers
# ──────────────────────────────────────────────────────────────

def set_reproducibility(seed: int) -> None:
    """Lock all random-number generators for deterministic training."""
    random.seed(seed)
    np.random.seed(seed)
    torch.manual_seed(seed)
    if torch.cuda.is_available():
        torch.cuda.manual_seed_all(seed)
    torch.backends.cudnn.deterministic = True
    torch.backends.cudnn.benchmark = False


def make_loaders() -> tuple[DataLoader, DataLoader]:
    """Create train and test DataLoaders with Q0.8 preprocessing."""
    train_tf = transforms.Compose([
        transforms.RandomCrop(32, padding=4),
        transforms.RandomHorizontalFlip(),
        RGBToGrayscaleQ8Tensor(),
    ])
    test_tf = transforms.Compose([RGBToGrayscaleQ8Tensor()])

    root = DATA_DIR / "cifar10_raw"
    try:
        train_ds = datasets.CIFAR10(str(root), train=True,
                                    download=DOWNLOAD, transform=train_tf)
        test_ds  = datasets.CIFAR10(str(root), train=False,
                                    download=DOWNLOAD, transform=test_tf)
    except RuntimeError as exc:
        raise RuntimeError(
            f"CIFAR-10 data not found under {root}. "
            f"Set DOWNLOAD = True in the configuration section to fetch it."
        ) from exc

    kwargs = dict(batch_size=BATCH_SIZE, num_workers=NUM_WORKERS,
                  pin_memory=torch.cuda.is_available())
    train_loader = DataLoader(
        train_ds, shuffle=True,
        generator=torch.Generator().manual_seed(SEED), **kwargs,
    )
    test_loader = DataLoader(test_ds, shuffle=False, **kwargs)
    return train_loader, test_loader


def run_epoch(model, loader, criterion, device, optimizer=None) -> tuple[float, float]:
    """Run one training or evaluation epoch.

    Returns:
        avg_loss:     mean cross-entropy loss over the dataset
        accuracy_pct: classification accuracy in percent
    """
    training = optimizer is not None
    model.train(training)
    total_loss = 0.0
    correct = 0
    total = 0

    ctx = torch.enable_grad() if training else torch.no_grad()
    with ctx:
        for images, labels in loader:
            images, labels = images.to(device), labels.to(device)
            if training:
                optimizer.zero_grad(set_to_none=True)
            logits = model(images)
            loss = criterion(logits, labels)
            if training:
                loss.backward()
                optimizer.step()
            total_loss += loss.item() * labels.size(0)
            correct += (logits.argmax(1) == labels).sum().item()
            total += labels.size(0)

    return total_loss / total, 100.0 * correct / total


# ──────────────────────────────────────────────────────────────
# Entry point
# ──────────────────────────────────────────────────────────────

def main() -> None:
    """Train the model, save the best checkpoint, and write a training log."""
    if min(EPOCHS, BATCH_SIZE, NUM_CHANNELS) <= 0:
        raise ValueError("EPOCHS, BATCH_SIZE, and NUM_CHANNELS must all be positive")

    DATA_DIR.mkdir(exist_ok=True)
    set_reproducibility(SEED)
    device = torch.device("cuda" if torch.cuda.is_available() else "cpu")
    print(f"Device: {device}")
    print(f"Model:  CIFAR10GrayCNN(N={KERNEL_SIZE}, K={NUM_CHANNELS})\n")

    train_loader, test_loader = make_loaders()
    model     = CIFAR10GrayCNN(KERNEL_SIZE, NUM_CHANNELS).to(device)
    optimizer = optim.Adam(model.parameters(), lr=LEARNING_RATE)
    criterion = nn.CrossEntropyLoss()
    scheduler = StepLR(optimizer, step_size=10, gamma=0.5)

    # Header (printed to terminal and saved to log)
    header_info = (
        f"FPGA contract: uint8/256 input, same-mode Conv1, stride 1, "
        f"output Q{OUTPUT_FRACTION_BITS}\n"
        f"Config: EPOCHS={EPOCHS}, LR={LEARNING_RATE}, BATCH={BATCH_SIZE}, "
        f"K={NUM_CHANNELS}, N={KERNEL_SIZE}, PATIENCE={PATIENCE}"
    )
    col_header = (
        f"{'Epoch':>5} | {'Train Loss':>10} | {'Train Acc':>9} | "
        f"{'Test Loss':>9} | {'Test Acc':>8} | {'LR':>8}"
    )
    separator = "-" * len(col_header)

    print(header_info)
    print(col_header)
    print(separator)
    log_lines = [header_info, col_header, separator]

    best_acc = -1.0
    epochs_without_improvement = 0

    for epoch in range(1, EPOCHS + 1):
        train_loss, train_acc = run_epoch(model, train_loader, criterion,
                                          device, optimizer)
        test_loss, test_acc   = run_epoch(model, test_loader, criterion, device)
        lr = optimizer.param_groups[0]["lr"]

        line = (
            f"{epoch:5d} | {train_loss:10.4f} | {train_acc:8.2f}% | "
            f"{test_loss:9.4f} | {test_acc:7.2f}% | {lr:.6f}"
        )
        print(line)
        log_lines.append(line)

        # Save checkpoint if this is a new best
        if test_acc > best_acc:
            best_acc = test_acc
            epochs_without_improvement = 0
            torch.save({
                "format_version":      2,
                "epoch":               epoch,
                "model_state_dict":    model.state_dict(),
                "optimizer_state_dict": optimizer.state_dict(),
                "test_acc":            test_acc,
                "kernel_size":         KERNEL_SIZE,
                "num_channels":        NUM_CHANNELS,
                "input_size":          model.input_size,
                "boundary_mode":       "same",
                "input_scale_divisor": INPUT_SCALE_DIVISOR,
                "output_fraction_bits": OUTPUT_FRACTION_BITS,
                "epochs":              EPOCHS,
                "learning_rate":       LEARNING_RATE,
                "batch_size":          BATCH_SIZE,
                "seed":                SEED,
            }, MODEL_PATH)
        else:
            epochs_without_improvement += 1

        scheduler.step()

        # Early stopping
        if epochs_without_improvement >= PATIENCE:
            stop_msg = (
                f"\nEarly stopping at epoch {epoch}: "
                f"no improvement for {PATIENCE} consecutive epochs."
            )
            print(stop_msg)
            log_lines.append(stop_msg)
            break

    # Summary
    summary = f"\nBest test accuracy: {best_acc:.2f}%"
    print(summary)
    log_lines.append(summary)

    LOG_PATH.write_text("\n".join(log_lines) + "\n", encoding="utf-8")
    print(f"Saved model → {MODEL_PATH}")
    print(f"Saved log   → {LOG_PATH}")


if __name__ == "__main__":
    main()
