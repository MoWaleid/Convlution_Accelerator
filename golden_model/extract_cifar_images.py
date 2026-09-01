"""Extract CIFAR-10 images from the compressed archive into individual PNG files.

Reads the cifar-10-python.tar.gz archive, unpickles each batch, and saves
every image as a 32×32 PNG file organised by split and class:

    data/cifar10_images/
        train/
            airplane/  automobile/  bird/  cat/  deer/
            dog/       frog/        horse/ ship/ truck/
        test/
            (same ten subdirectories)
"""
import os
import tarfile
import pickle

import numpy as np
from PIL import Image

# ═══════════════════════ CONFIGURATION ═══════════════════════
ARCHIVE_PATH = "cifar-10-python.tar.gz"  # Path to the CIFAR-10 compressed archive (relative to golden_model/)
OUTPUT_DIR   = "data/cifar10_images"     # Directory where extracted PNGs are saved (train/ and test/ subdirs)
# ═════════════════════════════════════════════════════════════


def unpickle(file_path: str) -> dict:
    """Load a pickled CIFAR-10 batch file and return its contents as a dict."""
    with open(file_path, "rb") as f:
        batch_dict = pickle.load(f, encoding="bytes")
    return batch_dict


def save_batch_images(batch: dict, label_names: list[str], split: str) -> None:
    """Save all images from one CIFAR-10 batch to disk as PNGs.

    Args:
        batch:       unpickled batch dict with keys b'data', b'labels', b'filenames'
        label_names: list of human-readable class names (length 10)
        split:       'train' or 'test'
    """
    data      = batch[b"data"]
    labels    = batch[b"labels"]
    filenames = batch[b"filenames"]

    # CIFAR-10 stores each image as a flat 3072-byte vector:
    #   1024 red bytes + 1024 green bytes + 1024 blue bytes
    # Reshape to (N, 3, 32, 32) then transpose to (N, 32, 32, 3) for PIL
    images = data.reshape(-1, 3, 32, 32).transpose(0, 2, 3, 1)

    for img_array, label_idx, filename in zip(images, labels, filenames):
        class_name = label_names[label_idx]
        file_name  = filename.decode("utf-8")
        img        = Image.fromarray(img_array)
        save_path  = os.path.join(OUTPUT_DIR, split, class_name, file_name)
        img.save(save_path)


def extract_and_save_images() -> None:
    """Extract the CIFAR-10 archive and save all 60 000 images as PNGs."""
    print(f"Extracting archive: {ARCHIVE_PATH}")
    with tarfile.open(ARCHIVE_PATH, "r:gz") as tar:
        tar.extractall(path="data/cifar10_raw", filter="data")

    base_dir = "data/cifar10_raw/cifar-10-batches-py"

    # Load class names from metadata
    meta        = unpickle(os.path.join(base_dir, "batches.meta"))
    label_names = [label.decode("utf-8") for label in meta[b"label_names"]]
    print(f"Classes: {', '.join(label_names)}")

    # Create output directory structure
    for split in ["train", "test"]:
        for label in label_names:
            os.makedirs(os.path.join(OUTPUT_DIR, split, label), exist_ok=True)

    # Process training batches (5 batches × 10 000 images = 50 000)
    for i in range(1, 6):
        batch = unpickle(os.path.join(base_dir, f"data_batch_{i}"))
        save_batch_images(batch, label_names, "train")
        print(f"  Processed training batch {i}/5  (10 000 images)")

    # Process test batch (1 batch × 10 000 images)
    test_batch = unpickle(os.path.join(base_dir, "test_batch"))
    save_batch_images(test_batch, label_names, "test")
    print(f"  Processed test batch         (10 000 images)")

    print(f"\nExtraction complete. 60 000 images saved to {OUTPUT_DIR}/")


if __name__ == "__main__":
    os.chdir(os.path.dirname(os.path.abspath(__file__)))
    os.makedirs("data", exist_ok=True)
    extract_and_save_images()
