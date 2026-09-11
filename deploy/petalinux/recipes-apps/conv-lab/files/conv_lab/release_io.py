"""Bounded new-location output and source identity; no deployment/catalog mutation."""
from datetime import datetime, timezone
import os
from pathlib import Path
import shutil
import json

from .bundles import relative_path, _read
from .storage import SpaceLedger, write_bounded
from .strict import require, sha256

MAX_OUTPUT_BYTES = 32*1024*1024


def json_bytes(value):
    return (json.dumps(value, indent=2, allow_nan=False)+"\n").encode("utf-8")


def code_identity():
    root = Path(__file__).resolve().parent
    return {"recorded_utc": datetime.now(timezone.utc).isoformat(),
            "files": {p.name: sha256(_read(root, p.name, 1048576))
                      for p in sorted(root.glob("*.py"))},
            "scope": "Source files observed by this invocation; not authenticated execution attestation."}


def write_new_tree(destination, files):
    """Exclusive mkdir reserves the namespace. COMPLETE.json is written last.

    Failures retain their partial directory. No replace, cleanup, catalog insertion,
    filesystem-quota claim or atomic multi-file visibility is implied.
    """
    destination = Path(destination).absolute()
    parent = destination.parent.resolve(strict=True)
    require(parent.is_dir() and not destination.exists() and not destination.is_symlink(),
            "output parent must exist and output must be new")
    destination = parent/destination.name
    require(type(files) is dict and files and len(files) <= 256, "bounded output inventory")
    require(not {"SHA256SUMS.txt", "COMPLETE.json"} & files.keys(), "reserved output metadata")
    require(len({p.casefold() for p in files}) == len(files), "output aliases")
    for name, data in files.items():
        relative_path(name)
        require(type(data) is bytes, "immutable output bytes")
    # Add completion and manifest before reserving/writing; the hashes are acyclic.
    payload = dict(files)
    payload["COMPLETE.json"] = json_bytes({"status": "COMPLETE", "files": sorted(files),
                                         "meaning": "Output write complete, not qualification."})
    sums = "".join(f"{sha256(data)}  {name}\n" for name, data in sorted(payload.items())).encode("ascii")
    payload["SHA256SUMS.txt"] = sums
    size = sum(map(len, payload.values()))
    require(size <= MAX_OUTPUT_BYTES, "output byte budget")
    ledger = SpaceLedger(lambda: shutil.disk_usage(parent).free)
    with ledger.reserve(temporary=65536+4096*len(payload), final=size) as reservation:
        destination.mkdir(mode=0o700, exist_ok=False)
        ordered = sorted(k for k in payload if k != "COMPLETE.json")+["COMPLETE.json"]
        for name in ordered:
            path = destination/name
            path.parent.mkdir(parents=True, exist_ok=True)
            with path.open("xb") as stream:
                data = payload[name]
                write_bounded(stream, (data[p:p+65536] for p in range(0, len(data), 65536)),
                              len(data), reservation)
                stream.flush()
                os.fsync(stream.fileno())
            require(sha256(_read(destination, name, len(data))) == sha256(data),
                    "written copy verification failed")
    return destination
