"""User-invoked lossless conversion; creates a new, unqualified bundle pair."""
import argparse
from pathlib import Path
import sys
import json

from .bundles import _read, relative_path
from .errors import AdmissionError
from .legacy import conversion_plan
from .release_io import write_new_tree, json_bytes, code_identity
from .strict import require, sha256, parse_json, hex_string


def read_input(path, maximum):
    path = Path(path).resolve(strict=True)
    return path, _read(path.parent, path.name, maximum)


def verify_provenance(inputs, checkpoint_root, audit_path):
    require((checkpoint_root is None) == (audit_path is None),
            "supply both checkpoint root and historical audit, or neither")
    sources = [{"path": str(p), "sha256": sha256(data)} for p, data in inputs]
    if checkpoint_root is None:
        return {"status": "UNVERIFIED external provenance", "sources": sources,
                "scope": "Explicit input bytes only; no checkpoint/audit association"}
    root = Path(checkpoint_root).resolve(strict=True)
    manifest = _read(root, "SHA256SUMS.txt", 1048576)
    entries = {}
    for line in manifest.decode("ascii").splitlines():
        require(len(line) > 66 and line[64:66] == "  ", "checkpoint manifest grammar")
        digest, name = hex_string(line[:64]), relative_path(line[66:])
        require(name not in entries, "duplicate checkpoint path")
        entries[name] = digest
    audit_path, audit_raw = read_input(audit_path, 1048576)
    audit = parse_json(audit_raw)
    require(audit.get("status") == "PASS" and type(audit.get("source_sha256")) is dict,
            "unsupported historical audit")
    mapping = []
    for path, data in inputs + [(audit_path, audit_raw)]:
        try:
            rel = path.relative_to(root).as_posix()
        except ValueError as exc:
            raise AdmissionError("input/audit outside supplied frozen checkpoint") from exc
        require(entries.get(rel) == sha256(data), "checkpoint hash mismatch: "+rel)
        mapping.append({"original_path": str(path), "checkpoint_path": rel, "sha256": sha256(data)})
    # The audit uses historical workstation paths. Compare suffixes only for a
    # unique association; never read those mutable historical paths.
    for path, data in inputs:
        rel = path.relative_to(root).as_posix()
        marker = "current_project/golden_model/data/"
        require(rel.startswith(marker), "unsupported checkpoint source mapping")
        suffix = "/golden_model/data/"+rel[len(marker):]
        matches = [hex_string(h) for p, h in audit["source_sha256"].items()
                   if p.replace("\\", "/").endswith(suffix)]
        require(matches == [sha256(data)], "historical source association mismatch: "+rel)
    return {"status": "CHECKPOINT_AND_AUDIT_HASH_MATCH", "sources": sources,
            "checkpoint_root": str(root), "checkpoint_manifest_sha256": sha256(manifest),
            "audit_sha256": sha256(audit_raw), "mapping": mapping,
            "scope": "Byte identity only; historical PASS is not a fresh execution or licensing grant"}


def convert(*, source_config, weights_dir, source_png, output_root, model_id,
            model_release, dataset_id, dataset_release, image_id,
            checkpoint_root=None, historical_audit=None):
    output_root = Path(output_root)
    require(not output_root.exists() and not output_root.is_symlink(), "output already exists")
    cfg_path, cfg = read_input(source_config, 1048576)
    png_path, png = read_input(source_png, 8388608)
    directory = Path(weights_dir).resolve(strict=True)
    resolved_output = output_root.resolve()
    protected = (cfg_path.parent, png_path.parent, directory)
    if checkpoint_root is not None:
        protected += (Path(checkpoint_root).resolve(strict=True),)
    require(all(resolved_output != p and p not in resolved_output.parents for p in protected),
            "output must be outside input/checkpoint directories")
    expected = {f"kernel_ch{i}.mem" for i in range(8)}
    require({p.name for p in directory.glob("kernel_ch*.mem")} == expected,
            "missing/extra legacy channel files")
    weights, inputs = {}, [(cfg_path, cfg), (png_path, png)]
    for i in range(8):
        p = directory/f"kernel_ch{i}.mem"
        # Root containment for weights; all bytes frozen before conversion.
        data = _read(directory, p.name, 4096)
        weights[i] = data
        inputs.append((p.resolve(strict=True), data))
    files, record = conversion_plan(cfg, weights, png, model_id=model_id,
        model_release=model_release, dataset_id=dataset_id, dataset_release=dataset_release, image_id=image_id)
    record["provenance"] = verify_provenance(inputs, checkpoint_root, historical_audit)
    record["software"] = code_identity()
    record["outputs"] = {p: sha256(b) for p, b in files.items()}
    record["identities"] = {"model_id": model_id, "model_release": model_release,
                            "dataset_id": dataset_id, "dataset_release": dataset_release, "image_id": image_id}
    # Record is a sibling of bundles, never an undeclared payload inside them.
    files["CONVERSION.json"] = json_bytes(record)
    return write_new_tree(output_root, files)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ("source-config", "weights-dir", "source-png", "output-root"):
        parser.add_argument("--"+name, type=Path, required=True)
    for name in ("model-id", "model-release", "dataset-id", "dataset-release", "image-id"):
        parser.add_argument("--"+name, required=True)
    parser.add_argument("--checkpoint-root", type=Path)
    parser.add_argument("--historical-audit", type=Path)
    args = parser.parse_args(argv)
    try:
        path = convert(**vars(args))
        print(json.dumps({"status": "CONVERTED_UNQUALIFIED", "output": str(path)}))
        return 0
    except (AdmissionError, OSError, ValueError) as exc:
        print("CONVERSION FAILED: "+str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
