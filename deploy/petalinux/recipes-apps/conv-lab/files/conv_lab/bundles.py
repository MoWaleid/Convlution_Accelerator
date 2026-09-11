"""Bounded filesystem snapshot and acyclic inventory integrity.

The snapshot, not a later filesystem read, is the only consumer input.
"""
import os
import stat
from dataclasses import dataclass
from pathlib import Path, PurePosixPath

from .errors import AdmissionError
from .strict import array, hex_string, integer, obj, parse_json, require, sha256, string
from .types import Blob, Bundle


@dataclass(frozen=True, slots=True)
class ReadBudget:
    # Parser/import guardrails, not new image/hardware qualification limits.
    max_bundle_bytes: int = 67108864
    max_files: int = 4096
    max_manifest_bytes: int = 1048576

    def __post_init__(self):
        for v in (self.max_bundle_bytes, self.max_files, self.max_manifest_bytes):
            integer(v, 1)


def relative_path(value):
    string(value)
    parts = value.split("/")
    require(not any(p in ("", ".", "..") or p.endswith((" ", ".")) for p in parts),
            "noncanonical or traversing path")
    require(not any(c in value for c in "\\:\0"), "absolute/drive/UNC/alias path")
    require(not PurePosixPath(value).is_absolute(), "absolute path")
    for part in parts:
        stem = part.split(".", 1)[0].upper()
        require(stem not in {"CON", "PRN", "AUX", "NUL"} and
                stem not in {f"{p}{n}" for p in ("COM", "LPT") for n in range(1,10)},
                "device path")
    return value


def file_ref(value, artifact=False):
    obj(value, "path sha256 kind" if artifact else "path sha256")
    return relative_path(value["path"]), hex_string(value["sha256"])


def references(kind, manifest):
    if kind == "hardware":
        obj(manifest, "schema_version build_id platform abi W H N K widths capabilities artifacts provenance")
        refs = [file_ref(r, True) for r in array(manifest["artifacts"])]
    elif kind == "model":
        obj(manifest, "schema_version model_id release_version kind compatibility channel_config weights optional_assets")
        refs = [file_ref(manifest["channel_config"])]
        refs += [file_ref(r) for r in array(manifest["weights"])]
        refs += [file_ref(r) for r in array(manifest["optional_assets"], False)]
    elif kind == "dataset":
        obj(manifest, "schema_version dataset_id release_version images")
        refs = []
        for entry in array(manifest["images"]):
            obj(entry, "image_id source preprocessing")
            refs.append(file_ref(entry["source"]))
    else:
        raise AdmissionError("unknown bundle kind")
    require(integer(manifest["schema_version"], 1, 1) == 1, "schema version")
    paths = [p for p, _ in refs]
    require(len(set(p.casefold() for p in paths)) == len(paths), "duplicate/conflicting reference")
    require(f"{kind}.json" not in paths, "manifest hash cycle")
    return tuple(refs)


def _within(path, root):
    return path == root or root in path.parents


def _descriptor_path(fd):
    if os.name == "nt":
        import ctypes
        import msvcrt
        from ctypes import wintypes
        func = ctypes.WinDLL("kernel32", use_last_error=True).GetFinalPathNameByHandleW
        func.argtypes = (wintypes.HANDLE, wintypes.LPWSTR, wintypes.DWORD, wintypes.DWORD)
        func.restype = wintypes.DWORD
        buf = ctypes.create_unicode_buffer(32768)
        count = func(msvcrt.get_osfhandle(fd), buf, len(buf), 0)
        require(0 < count < len(buf), "cannot prove open-file containment")
        path = buf.value
        if path.startswith("\\\\?\\UNC\\"):
            path = "\\\\" + path[8:]
        elif path.startswith("\\\\?\\"):
            path = path[4:]
        return Path(path).resolve(strict=True)
    if os.path.isdir("/proc/self/fd"):
        return Path(os.readlink(f"/proc/self/fd/{fd}")).resolve(strict=True)
    raise AdmissionError("open-file containment requires Windows or Linux /proc")


def _read(root, rel, maximum):
    path = (root / relative_path(rel)).resolve(strict=True)
    require(_within(path, root), "resolved path escapes bundle")
    fd = os.open(path, os.O_RDONLY | getattr(os, "O_BINARY", 0) | getattr(os, "O_NOFOLLOW", 0))
    try:
        require(_within(_descriptor_path(fd), root), "opened file escapes bundle")
        before = os.fstat(fd)
        require(stat.S_ISREG(before.st_mode), "not a regular file")
        require(before.st_size <= maximum, "asset byte budget")
        with os.fdopen(fd, "rb", closefd=False) as stream:
            data = stream.read(maximum+1)
        after = os.fstat(fd)
        require(len(data) <= maximum and len(data) == before.st_size, "file size changed/budget")
        require((before.st_dev,before.st_ino,before.st_size,before.st_mtime_ns) ==
                (after.st_dev,after.st_ino,after.st_size,after.st_mtime_ns), "file changed during read")
        return data
    finally:
        os.close(fd)


def _inventory(root, maximum):
    names = set()
    entry_count = 0

    def visit(directory, logical, ancestors):
        nonlocal entry_count
        real = directory.resolve(strict=True)
        require(_within(real, root) and real not in ancestors, "directory escape/cycle")
        require(len(ancestors) <= 64,"directory depth budget")
        with os.scandir(directory) as entries:
            for entry in entries:
                entry_count += 1
                require(entry_count <= maximum,"inventory entry budget")
                rel = (logical / entry.name).as_posix()
                relative_path(rel)
                resolved = Path(entry.path).resolve(strict=True)
                require(_within(resolved, root), "inventory escape")
                if entry.is_dir():
                    visit(Path(entry.path), logical / entry.name, ancestors | {real})
                else:
                    require(entry.is_file(), "non-file payload")
                    names.add(rel)
                    require(len(names) <= maximum, "file-count budget")
    visit(root, PurePosixPath(), set())
    require(len({n.casefold() for n in names}) == len(names), "case-alias payload")
    return names


def read_bundle(root, kind, budget=ReadBudget()):
    manifest_name = f"{kind}.json"
    try:
        root = Path(root).resolve(strict=True)
        require(root.is_dir(), "bundle root")
        raw = _read(root, manifest_name, min(budget.max_manifest_bytes, budget.max_bundle_bytes))
        manifest = parse_json(raw, budget.max_manifest_bytes)
        refs = references(kind, manifest)
        wanted = {manifest_name} | {p for p, _ in refs}
        require(_inventory(root, budget.max_files) == wanted, "missing/undeclared payload")
        blobs, total = [Blob(manifest_name, raw, sha256(raw))], len(raw)
        for path, expected in refs:
            maximum = budget.max_bundle_bytes-total
            if kind == "dataset":
                maximum = min(maximum, 8388608)
            data = _read(root, path, maximum)
            require(sha256(data) == expected, f"hash mismatch: {path}")
            total += len(data)
            blobs.append(Blob(path, data, expected))
        require(_inventory(root, budget.max_files) == wanted, "inventory changed")
        return Bundle(kind, str(root), tuple(blobs))
    except (OSError, RuntimeError) as exc:
        raise AdmissionError(f"bundle read failed: {exc}") from exc


def fingerprint(bundle):
    return tuple(sorted((b.path, b.sha256) for b in bundle.files))
