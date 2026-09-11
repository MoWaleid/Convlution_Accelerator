"""Explicit known format-2 adapter. No guessing, training, clipping or decoding."""
from fractions import Fraction
from ._decoder_worker import _header
from .dma import width_policy
from .strict import (array, coefficients, identity, integer, obj, parse_json,
                     require, sha256)
from .release_io import json_bytes
from .types import Blob, Bundle, NumericalTarget
from .schemas import model, dataset

ROOT_FIELDS = ("format_version N K boundary_mode stride pixel_format input_scale_divisor "
               "coefficient_format bias_bits output_format output_fraction_bits accumulator_width_min channels")
CHANNEL_FIELDS = "channel source_channel shift weight_fraction_bits bias_fraction_bits bias_quantized relu_en"


def exact_object(value, fields):
    obj(value, fields)
    require(set(value) == set(fields.split()), "unsupported legacy field/extension")
    return value


def rational(value):
    return {"numerator": value.numerator, "denominator": value.denominator}


def validate_legacy(config_bytes, weights):
    cfg = exact_object(parse_json(config_bytes), ROOT_FIELDS)
    integer(cfg["format_version"], 2, 2)
    # This adapter intentionally supports the first selected trained candidate only.
    integer(cfg["N"], 3, 3); integer(cfg["K"], 8, 8)
    require(cfg["boundary_mode"] == "same", "unsupported boundary convention")
    integer(cfg["stride"], 1, 1)
    require(cfg["pixel_format"] == "uint8_q0.8" and
            cfg["coefficient_format"] == "int8_raw", "unsupported legacy numeric convention")
    divisor = integer(cfg["input_scale_divisor"], 1)
    require(divisor == 256, "uint8_q0.8 requires divisor 256")
    input_scale = Fraction(1, divisor)
    pixel_fraction = divisor.bit_length()-1
    integer(cfg["bias_bits"], 32, 32)  # original representation; target is checked below
    output_fraction = integer(cfg["output_fraction_bits"], 0, 15)
    require(cfg["output_format"] == f"int16_q{output_fraction}", "output format/fraction mismatch")
    sw, _ = width_policy(cfg["N"], 24)
    require(integer(cfg["accumulator_width_min"], 1) == sw, "legacy product-sum width mismatch")
    require(type(weights) is dict and set(weights) == set(range(cfg["K"])) and
            all(type(k) is int for k in weights), "exact channel weight set required")
    channels, mapping, canonical = {}, {}, {}
    for raw in array(cfg["channels"]):
        c = exact_object(raw, CHANNEL_FIELDS)
        index = integer(c["channel"], 0, cfg["K"]-1)
        require(index not in channels, "duplicate legacy channel")
        # Known exporter preserves source channel IDs. Remapped conventions need a new adapter.
        require(integer(c["source_channel"], 0, cfg["K"]-1) == index,
                "unsupported source-channel remapping")
        shift = integer(c["shift"], 0, 31)
        fw = integer(c["weight_fraction_bits"], 0, 38)
        fb = integer(c["bias_fraction_bits"], 0, 46)
        require(fb == pixel_fraction+fw, "bias scale is not accumulator scale")
        require(shift == fb-output_fraction, "shift/output-fraction relationship")
        weight_scale = Fraction(1, 1 << fw)
        require(input_scale*weight_scale*(1 << shift) == Fraction(1, 1 << output_fraction),
                "output scale relationship")
        bias = integer(c["bias_quantized"], -(1 << 23), (1 << 23)-1)
        relu = integer(c["relu_en"], 0, 1)  # rejects JSON booleans
        values = coefficients(weights[index], cfg["N"])
        path = f"weights/kernel_ch{index}.mem"
        canonical[path] = "".join(f"{v & 255:02X}\n" for v in values).encode("ascii")
        channels[index] = {"channel": index, "weights_file": path, "bias_quantized": bias,
                           "shift": shift, "relu_en": bool(relu), "weight_scale": rational(weight_scale)}
        mapping[index] = {"channel": index, "source_channel": c["source_channel"],
                          "source_sha256": sha256(weights[index]),
                          "converted_sha256": sha256(canonical[path]),
                          "numerical_values_unchanged": True, "bias_scale": rational(input_scale*weight_scale),
                          "output_scale": rational(input_scale*weight_scale*(1 << shift))}
    require(set(channels) == set(range(cfg["K"])), "missing legacy channel")
    v3 = {"format_version": 3, "input_scale": rational(input_scale),
          "channels": [channels[i] for i in range(cfg["K"])]}
    return cfg, v3, canonical, [mapping[i] for i in range(cfg["K"])]


def conversion_plan(config_bytes, weights, png, *, model_id, model_release,
                    dataset_id, dataset_release, image_id):
    for value in (model_id, model_release, dataset_id, dataset_release, image_id):
        identity(value)
    cfg, v3, canonical, mapping = validate_legacy(config_bytes, weights)
    require(type(png) is bytes and 0 < len(png) <= 8388608, "PNG byte budget")
    try:
        fmt, (w, h, _) = _header(png)
    except (ValueError, TypeError) as exc:
        from .errors import AdmissionError
        raise AdmissionError("PNG structural check: "+str(exc)) from exc
    require(fmt == "PNG" and (w, h) == (32, 32), "initial candidate requires source PNG 32x32")
    # Header inspection is not decoding or proof of canonical geometry after EXIF.
    model_files = dict(canonical)
    model_files["channel_config.json"] = json_bytes(v3)
    ref = lambda name, data: {"path": name, "sha256": sha256(data)}
    manifest = {
        "schema_version": 1, "model_id": model_id, "release_version": model_release, "kind": "trained",
        "compatibility": {
            "N": cfg["N"], "K": cfg["K"], "geometry": [{"W": 32, "H": 32}],
            "geometry_policies": ["exact"],
            "numerical": {"pixel_width": 8, "weight_width": 8, "output_width": 16,
                          "min_bias_width": 24, "relu_required": any(c["relu_en"] for c in v3["channels"])},
            "abi": {"magic": "43564831", "versions": [{"major": 1, "minor": 0}]}},
        "channel_config": ref("channel_config.json", model_files["channel_config.json"]),
        "weights": [ref(p, canonical[p]) for p in sorted(canonical)], "optional_assets": []}
    model_files["model.json"] = json_bytes(manifest)
    image_path = "images/"+image_id+".png"
    dataset_files = {image_path: png}
    dataset_files["dataset.json"] = json_bytes({
        "schema_version": 1, "dataset_id": dataset_id, "release_version": dataset_release,
        "images": [{"image_id": image_id, "source": ref(image_path, png),
                    "preprocessing": {"geometry_policy": "exact", "resize_filter": "NONE"}}]})
    target = NumericalTarget(32, 32, 3, 8, 24)
    def snapshot(kind, files):
        return Bundle(kind, "unpublished-conversion", tuple(Blob(p, b, sha256(b)) for p, b in files.items()))
    _, _, policies = model(snapshot("model", model_files), target)
    dataset(snapshot("dataset", dataset_files), image_id, policies)
    files = {"model/"+p: b for p, b in model_files.items()}
    files.update({"dataset/"+p: b for p, b in dataset_files.items()})
    record = {"adapter": "known-format2-n3-k8-v1", "legacy_configuration": cfg,
              "source_config_sha256": sha256(config_bytes), "source_png_sha256": sha256(png),
              "channel_mapping": mapping, "numerical_target": {"W": 32, "H": 32, "N": 3, "K": 8, "bias_width": 24},
              "input_scale": v3["input_scale"], "png_copied_unchanged": True,
              "normalization": "MEM uppercase two-digit bytes, LF and one terminal newline only",
              "excluded": ["expected .hex", "optional .pth"], "requantization": "NONE",
              "image_decoding": "NOT RUN by converter; Linux offline validation required",
              "qualification": "NOT RUN", "licensing": "UNRESOLVED; no permission inferred",
              "training_provenance": "Legacy quantized snapshot only; complete training provenance unproven"}
    return files, record
