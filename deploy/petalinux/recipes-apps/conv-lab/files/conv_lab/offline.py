"""Explicit Linux offline validation; no backend, hardware manifest or submission API."""
import argparse
from dataclasses import asdict
import json
from pathlib import Path
import sys

from .bundles import read_bundle, _read
from .dma import pad_pixels, width_policy
from .errors import AdmissionError
from .preprocessing import LinuxDecoder, validate_decoded
from .reference import evaluate
from .schemas import model, dataset, bundle_identity
from .strict import require, sha256, parse_json, hex_string
from .types import NumericalTarget, OfflineContext
from .release_io import write_new_tree, code_identity, json_bytes


def prepare_offline(model_root, dataset_root, image_id, target, *, _test_decoder=None):
    """Pure schemas plus one decode. Injection is a trusted user-test seam only."""
    require(type(target) is NumericalTarget, "explicit numerical target required")
    mb, db = read_bundle(model_root, "model"), read_bundle(dataset_root, "dataset")
    channels, scale, policies = model(mb, target)
    source, policy = dataset(db, image_id, policies)
    decoder = LinuxDecoder() if _test_decoder is None else _test_decoder
    decoded = validate_decoded(decoder.decode(source, target.W, target.H, policy),
                               source, target.W, target.H, policy)
    padded = pad_pixels(decoded.canonical, target.W, target.H, target.N)
    return OfflineContext(target, channels, scale, mb, db, image_id, source, sha256(source),
                          decoded.canonical, sha256(decoded.canonical), padded, sha256(padded),
                          decoded.record_json)


def audit_anchor(audit_bytes, ctx, output):
    """Historical evidence only. Never supplies pixels, parameters or reference values."""
    audit = parse_json(audit_bytes)
    require(audit.get("status") == "PASS", "historical audit not PASS")
    require((ctx.target.W, ctx.target.H, ctx.target.N, ctx.target.K) == (32, 32, 3, 8),
            "this historical audit adapter is N3/K8/32x32 only")
    files = audit.get("source_sha256")
    require(type(files) is dict, "historical source inventory")
    def historical(suffix):
        matches = [hex_string(h) for p, h in files.items()
                   if p.replace("\\", "/").endswith("/"+suffix)]
        require(len(matches) == 1, "ambiguous/missing historical source")
        return matches[0]
    image_paths = [b.path for b in ctx.dataset_bundle.files if b.sha256 == ctx.source_sha256]
    require(len(image_paths) == 1 and type(audit.get("image_name")) is str,
            "historical image association")
    source_expected = historical("cifar10_images/test/cat/"+audit["image_name"])
    # Config arrays check association only; evaluate already computed independently.
    actual_cfg = [[list(c.weights), c.bias, c.shift, c.relu] for c in ctx.channels]
    expected_cfg = audit.get("configs")
    require(type(expected_cfg) is list and len(expected_cfg) == len(actual_cfg),
            "historical channel association")
    for entry in expected_cfg:
        require(type(entry) is list and len(entry) == 4 and type(entry[0]) is list and
                all(type(x) is int for x in entry[0]) and
                type(entry[1]) is int and type(entry[2]) is int and type(entry[3]) is bool,
                "historical parameter types")
    require(actual_cfg == expected_cfg, "historical parameters differ")
    values = {
        "source_png": (ctx.source_sha256, source_expected),
        "canonical_pixels": (ctx.canonical_sha256, hex_string(audit["input_sha256"])),
        "padded_tx": (ctx.padded_tx_sha256, hex_string(audit["padded_input_sha256"])),
        "serialized_signed16_output": (output.sha256, hex_string(audit["expected_output_sha256"])),
    }
    return {"audit_sha256": sha256(audit_bytes),
            "status": "PASS" if all(a == b for a, b in values.values()) else "FAIL",
            "domains": {k: {"actual": a, "historical": b, "status": "PASS" if a == b else "FAIL"}
                        for k, (a, b) in values.items()},
            "scope": "Additional historical regression; not independent algorithm proof or board test."}


def validation_record(ctx, result, historical=None):
    sw, aw = width_policy(ctx.target.N, ctx.target.bias_width)
    return {
        "status": "PASS" if historical is None or historical["status"] == "PASS" else "FAIL",
        "scope": "Offline host model/dataset validation and integer reference execution only.",
        "numerical_target": asdict(ctx.target), "derived_widths": {"sum": sw, "accumulator": aw},
        "output": {"W": ctx.target.W, "H": ctx.target.H, "K": ctx.target.K,
                   "values": result.values, "bytes": len(result.raw),
                   "order": "y,x,channel; little-endian signed16"},
        "hashes": {"source_png_or_jpeg": ctx.source_sha256, "canonical_pixels": ctx.canonical_sha256,
                   "padded_tx": ctx.padded_tx_sha256, "serialized_output": result.sha256},
        "bundle_files": {b.kind: {f.path: f.sha256 for f in b.files}
                         for b in (ctx.model_bundle, ctx.dataset_bundle)},
        "bundle_identities": {b.kind: bundle_identity(b) for b in (ctx.model_bundle, ctx.dataset_bundle)},
        "image_id": ctx.image_id, "preprocessing": parse_json(ctx.preprocessing_record),
        "historical_regression": historical if historical is not None else {"status": "NOT RUN"},
        "reference_independent_oracle": "NOT RUN by this CLI; separate user-run C/B tests",
        "software": code_identity(), "python": sys.version,
        "hardware_identity": None, "hardware_submission": "UNAVAILABLE",
        "board_qualification": "NOT RUN", "arm_petalinux_qualification": "NOT RUN",
        "limitations": ["Compatibility is a numerical requirement, not live hardware discovery.",
                        "No throughput claim; reference runtime has no decoder deadline.",
                        "Licensing and full training provenance require separate review."]
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--model", type=Path, required=True)
    parser.add_argument("--dataset", type=Path, required=True)
    parser.add_argument("--image-id", required=True)
    for arg in ("W", "H", "N", "K", "bias-width"):
        parser.add_argument("--"+arg, type=int, required=True)
    parser.add_argument("--historical-audit", type=Path)
    parser.add_argument("--report-output", type=Path, required=True,
                        help="New directory; existing paths are refused.")
    args = parser.parse_args(argv)
    try:
        require(not args.report_output.exists() and not args.report_output.is_symlink(),
                "report output already exists")
        report_path = args.report_output.resolve()
        require(all(report_path != p and p not in report_path.parents
                    for p in (args.model.resolve(), args.dataset.resolve())),
                "report must be outside immutable model/dataset bundles")
        target = NumericalTarget(args.W, args.H, args.N, args.K, args.bias_width)
        audit = None
        if args.historical_audit is not None:
            p = args.historical_audit.resolve(strict=True)
            audit = _read(p.parent, p.name, 1048576)
        ctx = prepare_offline(args.model, args.dataset, args.image_id, target)
        output = evaluate(ctx)  # Always derive from actual files, before regression comparison.
        anchor = audit_anchor(audit, ctx, output) if audit is not None else None
        record = validation_record(ctx, output, anchor)
        write_new_tree(args.report_output, {"VALIDATION.json": json_bytes(record),
                                           "output.s16le": output.raw})
        print(json.dumps({"status": record["status"], "report": str(args.report_output)}))
        return 0 if record["status"] == "PASS" else 1
    except (AdmissionError, OSError, ValueError, KeyError) as exc:
        print("OFFLINE VALIDATION FAILED: "+str(exc), file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
