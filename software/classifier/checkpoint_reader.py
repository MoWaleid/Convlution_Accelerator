"""Read the tensor state from a modern ``torch.save`` ZIP without PyTorch.

The project checkpoints contain ordinary CPU tensors.  Deployment/export
tools need their values, but installing the full PyTorch runtime merely to
extract immutable weights is unnecessary.  This deliberately small reader
supports the storage and tensor reconstruction records emitted by the three
qualified training checkpoints and rejects unsupported storage types.
"""

from __future__ import annotations

from collections import OrderedDict
from dataclasses import dataclass
import io
import pickle
from pathlib import Path
import zipfile

import numpy as np


@dataclass(frozen=True)
class _StorageType:
    name: str


@dataclass(frozen=True)
class _StorageRef:
    kind: _StorageType
    key: str
    location: str
    elements: int


@dataclass(frozen=True)
class _TensorRef:
    storage: _StorageRef
    offset: int
    shape: tuple[int, ...]
    stride: tuple[int, ...]


def _rebuild_tensor(storage, offset, shape, stride, *unused):
    if not isinstance(storage, _StorageRef):
        raise ValueError("checkpoint tensor has no supported storage")
    return _TensorRef(storage, int(offset), tuple(shape), tuple(stride))


def _rebuild_parameter(tensor, *unused):
    return tensor


class _CheckpointUnpickler(pickle.Unpickler):
    def persistent_load(self, saved_id):
        if (not isinstance(saved_id, tuple) or len(saved_id) != 5 or
                saved_id[0] != "storage" or
                not isinstance(saved_id[1], _StorageType)):
            raise pickle.UnpicklingError("unsupported persistent checkpoint record")
        _, kind, key, location, elements = saved_id
        return _StorageRef(kind, str(key), str(location), int(elements))

    def find_class(self, module, name):
        if module == "torch._utils" and name.startswith("_rebuild_tensor"):
            return _rebuild_tensor
        if module == "torch._utils" and name == "_rebuild_parameter":
            return _rebuild_parameter
        if module == "torch" and name.endswith("Storage"):
            return _StorageType(name)
        return super().find_class(module, name)


_DTYPES = {
    "FloatStorage": np.dtype("f4"),
    "DoubleStorage": np.dtype("f8"),
    "HalfStorage": np.dtype("f2"),
    "LongStorage": np.dtype("i8"),
    "IntStorage": np.dtype("i4"),
    "ShortStorage": np.dtype("i2"),
    "CharStorage": np.dtype("i1"),
    "ByteStorage": np.dtype("u1"),
    "BoolStorage": np.dtype("?"),
}


def _materialize(archive: zipfile.ZipFile, prefix: str, byteorder: str,
                 tensor: _TensorRef) -> np.ndarray:
    try:
        dtype = _DTYPES[tensor.storage.kind.name].newbyteorder(
            "<" if byteorder == "little" else ">")
    except KeyError as exc:
        raise ValueError(f"unsupported checkpoint storage {tensor.storage.kind.name}") from exc
    blob = archive.read(f"{prefix}/data/{tensor.storage.key}")
    required = tensor.storage.elements * dtype.itemsize
    if len(blob) != required:
        raise ValueError("checkpoint storage length mismatch")
    base = np.frombuffer(blob, dtype=dtype, count=tensor.storage.elements)
    if tensor.offset < 0 or tensor.offset > base.size:
        raise ValueError("checkpoint tensor offset is out of range")
    view = np.lib.stride_tricks.as_strided(
        base[tensor.offset:], shape=tensor.shape,
        strides=tuple(value * dtype.itemsize for value in tensor.stride),
        writeable=False,
    )
    return np.array(view, dtype=dtype.newbyteorder("="), copy=True)


def load_checkpoint(path: str | Path) -> dict:
    """Return checkpoint metadata and a NumPy ``model_state_dict``."""
    path = Path(path)
    with zipfile.ZipFile(path) as archive:
        members = archive.namelist()
        pickles = [name for name in members if name.endswith("/data.pkl")]
        if len(pickles) != 1:
            raise ValueError("checkpoint must contain exactly one data.pkl")
        pickle_member = pickles[0]
        prefix = pickle_member.rsplit("/", 1)[0]
        byteorder = archive.read(f"{prefix}/byteorder").decode("ascii").strip()
        if byteorder not in ("little", "big"):
            raise ValueError("unsupported checkpoint byte order")
        document = _CheckpointUnpickler(
            io.BytesIO(archive.read(pickle_member))).load()
        if not isinstance(document, dict):
            raise ValueError("checkpoint root must be a dictionary")
        state = document.get("model_state_dict")
        if not isinstance(state, (dict, OrderedDict)):
            raise ValueError("checkpoint has no model_state_dict")
        arrays = {}
        for name, tensor in state.items():
            if not isinstance(name, str) or not isinstance(tensor, _TensorRef):
                raise ValueError("unsupported model state entry")
            arrays[name] = _materialize(archive, prefix, byteorder, tensor)

    metadata_keys = (
        "format_version", "epoch", "test_acc", "kernel_size", "num_channels",
        "input_size", "boundary_mode", "input_scale_divisor",
        "output_fraction_bits",
    )
    metadata = {key: document.get(key) for key in metadata_keys}
    return {"metadata": metadata, "model_state_dict": arrays}
