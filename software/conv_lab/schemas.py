"""Schema-1/format-3 validation with no hardware access."""
from fractions import Fraction

from .bundles import file_ref, references
from .dma import width_policy
from .strict import (array, boolean, coefficients, hex_string, identity, integer,
                     obj, parse_json, ratio, require, string)
from .types import Channel, Hardware


def manifest(bundle):
    value = parse_json(bundle.blob(f"{bundle.kind}.json").data)
    references(bundle.kind, value)
    return value


def abi(value):
    obj(value, "magic major minor")
    require(hex_string(value["magic"], 8) == "43564831", "ABI magic")
    require((integer(value["major"],0,65535),integer(value["minor"],0,65535)) == (1,0),
            "unsupported ABI version")


def hardware(bundle):
    m = manifest(bundle)
    build = hex_string(m["build_id"],32)
    require(int(build,16) != 0, "zero release ID")
    p = obj(m["platform"], "id board fpga_part dt_contract_id ps_config_sha256 clock_hz")
    for key in ("id","board","fpga_part","dt_contract_id"):
        string(p[key])
    hex_string(p["ps_config_sha256"])
    require(integer(p["clock_hz"],1) == 100000000, "100 MHz family clock")
    abi(m["abi"])
    w,h,n,k = (integer(m[key],1,0xffffffff) for key in ("W","H","N","K"))
    require(n in (3,5) and k <= 64, "implemented numerical/ABI envelope")
    widths = obj(m["widths"], "pixel weight bias sum accumulator output m_axi_mm2s m_axi_s2mm m_axis_mm2s s_axis_s2mm axi_lite dma_length")
    for key in widths.keys()-{"extensions"}:
        integer(widths[key],1)
    for key, value in (("pixel",8),("weight",8),("output",16),("axi_lite",32),
                       ("dma_length",22),("m_axi_mm2s",64),("m_axi_s2mm",64),
                       ("m_axis_mm2s",64),("s_axis_s2mm",64)):
        require(widths[key] == value, f"width mismatch: {key}")
    sw, aw = width_policy(n,widths["bias"])
    require((widths["sum"],widths["accumulator"]) == (sw,aw), "derived widths")
    require(integer(m["capabilities"]) == 0x1ff, "capability mask")
    kinds = set()
    for a in m["artifacts"]:
        require(a["kind"] in ("bitstream","fpga_manager_image","xsa","ltx","build_input",
                              "build_report","supporting_document"), "artifact kind")
        kinds.add(a["kind"])
    require({"bitstream","fpga_manager_image","xsa"} <= kinds, "missing hardware artifact role")
    provenance = obj(m["provenance"], "source_snapshot_id source_snapshot_sha256 tools external_prerequisites")
    string(provenance["source_snapshot_id"])
    hex_string(provenance["source_snapshot_sha256"])
    for tool in array(provenance["tools"]):
        obj(tool,"name version"); string(tool["name"]); string(tool["version"])
    for prerequisite in array(provenance["external_prerequisites"],False):
        obj(prerequisite,"name identity"); string(prerequisite["name"]); string(prerequisite["identity"])
    synthetic = m.get("extensions",{}).get("synthetic_fixture") is True
    return Hardware(w,h,n,k,widths["bias"],sw,aw,build,p["id"],p["ps_config_sha256"],
                    p["dt_contract_id"],p["clock_hz"],synthetic)


def model(bundle, hw):
    m = manifest(bundle)
    identity(m["model_id"]); identity(m["release_version"])
    require(m["kind"] in ("trained","custom"), "model kind")
    compat = obj(m["compatibility"], "N K geometry geometry_policies numerical abi")
    require(integer(compat["N"],1) == hw.N and integer(compat["K"],1) == hw.K, "N/K incompatibility")
    shapes = []
    for g in array(compat["geometry"]):
        obj(g,"W H")
        shapes.append((integer(g["W"],1),integer(g["H"],1)))
    require(len(set(shapes)) == len(shapes) and (hw.W,hw.H) in shapes, "geometry compatibility")
    policies = array(compat["geometry_policies"])
    require(all(type(x) is str and x in ("exact","resize_exact") for x in policies), "geometry policy")
    require(len(set(policies)) == len(policies), "duplicate policy")
    numerical = obj(compat["numerical"], "pixel_width weight_width output_width min_bias_width relu_required")
    for key,width in (("pixel_width",8),("weight_width",8),("output_width",16)):
        require(integer(numerical[key],1) == width, "model numerical width")
    require(integer(numerical["min_bias_width"],1,32) <= hw.bias_width, "required bias width")
    boolean(numerical["relu_required"])
    a = obj(compat["abi"],"magic versions")
    require(hex_string(a["magic"],8) == "43564831", "model ABI magic")
    versions = []
    for version in array(a["versions"]):
        obj(version,"major minor")
        versions.append((integer(version["major"],0,65535),integer(version["minor"],0,65535)))
    require(len(set(versions)) == len(versions) and (1,0) in versions, "ABI compatibility")
    cfg_path,_ = file_ref(m["channel_config"])
    require(cfg_path == "channel_config.json", "configuration path")
    for ref in m["optional_assets"]:
        require(ref["path"].endswith(".pth"), "unsupported optional asset adapter")
    cfg = obj(parse_json(bundle.blob(cfg_path).data),"format_version input_scale channels")
    integer(cfg["format_version"],3,3)
    input_scale = ratio(cfg["input_scale"])
    if m["kind"] == "trained":
        require(input_scale == Fraction(1,256), "trained input convention")
    result, paths = {}, set()
    for c in array(cfg["channels"]):
        obj(c,"channel weights_file bias_quantized shift relu_en weight_scale")
        index = integer(c["channel"],0,hw.K-1)
        require(index not in result, "duplicate channel")
        path = f"weights/kernel_ch{index}.mem"
        require(c["weights_file"] == path, "explicit channel/path mismatch")
        require(path in {r["path"] for r in m["weights"]}, "missing weight reference")
        weight = coefficients(bundle.blob(path).data,hw.N)
        bias = integer(c["bias_quantized"],-(1 << (hw.bias_width-1)),(1 << (hw.bias_width-1))-1)
        result[index] = Channel(index,weight,bias,integer(c["shift"],0,31),
                                boolean(c["relu_en"]),ratio(c["weight_scale"]))
        paths.add(path)
    require(set(result) == set(range(hw.K)), "missing channel")
    require(paths == {r["path"] for r in m["weights"]}, "weight inventory mismatch")
    channels = tuple(result[i] for i in range(hw.K))
    require(numerical["relu_required"] == any(c.relu for c in channels), "ReLU requirement mismatch")
    return channels,input_scale,tuple(policies)


def dataset(bundle, selected_image, allowed_policies):
    m = manifest(bundle)
    identity(m["dataset_id"]); identity(m["release_version"]); identity(selected_image)
    images, selected = set(), None
    for e in m["images"]:
        image_id = identity(e["image_id"])
        require(image_id not in images, "duplicate image ID")
        images.add(image_id)
        policy = obj(e["preprocessing"],"geometry_policy resize_filter")
        name = policy["geometry_policy"]
        require(type(name) is str and name in ("exact","resize_exact"), "preprocessing policy")
        require(policy["resize_filter"] == ("NONE" if name == "exact" else "LANCZOS"), "resize filter")
        if image_id == selected_image:
            require(name in allowed_policies, "model disallows preprocessing")
            selected = (bundle.blob(e["source"]["path"]).data,name)
    require(selected is not None, "unknown image ID")
    return selected


def bundle_identity(bundle):
    m = manifest(bundle)
    if bundle.kind == "hardware":
        return ("hardware",string(m["platform"]["id"]),hex_string(m["build_id"],32))
    field = "model_id" if bundle.kind == "model" else "dataset_id"
    return bundle.kind,identity(m[field]),identity(m["release_version"])
