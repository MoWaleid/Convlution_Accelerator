"""Strict loader for exported post-Conv1 classifier tensors."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path

import numpy as np

from .export_tail import TAIL_TENSORS

MAX_MANIFEST_BYTES = 128 * 1024


def load_tail_bundle(directory: str | Path) -> tuple[dict, dict[str, np.ndarray]]:
    """Validate an exported bundle completely before returning its tensors."""
    directory = Path(directory)
    blob = (directory / "manifest.json").read_bytes()
    if not blob or len(blob) > MAX_MANIFEST_BYTES:
        raise ValueError("tail manifest size is invalid")
    manifest = json.loads(blob.decode("utf-8"))
    if type(manifest) is not dict or manifest.get("schema_version") != 1:
        raise ValueError("unsupported tail manifest")
    records = manifest.get("tensors")
    if type(records) is not dict or set(records) != set(TAIL_TENSORS):
        raise ValueError("tail tensor inventory mismatch")

    arrays: dict[str, np.ndarray] = {}
    for name in TAIL_TENSORS:
        record = records[name]
        if type(record) is not dict:
            raise ValueError(f"invalid tensor record: {name}")
        filename = record.get("file")
        shape = record.get("shape")
        if (type(filename) is not str or Path(filename).name != filename or
                record.get("dtype") != "float32-little-endian" or
                type(shape) is not list or not shape or
                any(type(value) is not int or value <= 0 for value in shape)):
            raise ValueError(f"invalid tensor metadata: {name}")
        tensor_blob = (directory / filename).read_bytes()
        expected_bytes = 4 * int(np.prod(shape, dtype=np.int64))
        if record.get("bytes") != expected_bytes or len(tensor_blob) != expected_bytes:
            raise ValueError(f"tensor byte count mismatch: {name}")
        if hashlib.sha256(tensor_blob).hexdigest() != record.get("sha256"):
            raise ValueError(f"tensor checksum mismatch: {name}")
        arrays[name] = np.frombuffer(tensor_blob, dtype="<f4").reshape(shape).copy()
    return manifest, arrays
