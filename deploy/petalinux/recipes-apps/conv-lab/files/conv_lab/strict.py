"""Exact JSON/text grammar. Never normalize bytes before integrity checks."""
import hashlib
import json
import math
import re
from fractions import Fraction

from .errors import AdmissionError


def require(condition, message):
    if not condition:
        raise AdmissionError(message)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def _pairs(items):
    result = {}
    for key, value in items:
        require(key not in result, f"duplicate JSON key: {key}")
        result[key] = value
    return result


def _constant(value):
    raise AdmissionError(f"non-JSON number: {value}")


def _float(value):
    parsed = float(value)
    require(math.isfinite(parsed),"nonfinite JSON number")
    return parsed


def parse_json(data, maximum=1048576):
    require(type(data) is bytes and len(data) <= maximum, "JSON byte budget")
    require(not data.startswith(b"\xef\xbb\xbf"), "JSON BOM")
    try:
        value = json.loads(data.decode("utf-8"), object_pairs_hook=_pairs,
                           parse_constant=_constant,parse_float=_float)
    except (UnicodeError, ValueError, RecursionError) as exc:
        raise AdmissionError(f"invalid JSON: {exc}") from exc
    require(type(value) is dict, "JSON root must be an object")
    return value


def obj(value, required, optional=()):
    require(type(value) is dict, "expected object")
    required = set(required.split()) if isinstance(required, str) else set(required)
    optional = set(optional.split()) if isinstance(optional, str) else set(optional)
    require(required <= value.keys(), f"missing fields: {required - value.keys()}")
    require(value.keys() <= required | optional | {"extensions"}, "unknown field")
    if "extensions" in value:
        require(type(value["extensions"]) is dict, "extensions must be object")
    return value


def integer(value, low=0, high=None):
    require(type(value) is int, "expected JSON integer, not bool/float")
    require(value >= low and (high is None or value <= high), "integer range")
    return value


def boolean(value):
    require(type(value) is bool, "expected JSON boolean")
    return value


def string(value):
    require(type(value) is str and bool(value) and not any(ord(c) < 32 for c in value),
            "expected nonempty string without control characters")
    return value


def identity(value):
    string(value)
    require(re.fullmatch(r"[a-z0-9][a-z0-9._-]*", value) is not None, "identity syntax")
    return value


def hex_string(value, digits=64):
    require(type(value) is str and re.fullmatch(f"[0-9a-f]{{{digits}}}", value),
            "noncanonical hexadecimal identity")
    return value


def array(value, nonempty=True):
    require(type(value) is list and (value or not nonempty), "expected array")
    return value


def ratio(value):
    obj(value, "numerator denominator")
    n, d = integer(value["numerator"], 1), integer(value["denominator"], 1)
    require(math.gcd(n, d) == 1, "scale must already be reduced")
    return Fraction(n, d)


def coefficients(data, n):
    require(type(data) is bytes, "coefficient bytes required")
    if data.endswith(b"\r\n"):
        data = data[:-2]
    elif data.endswith(b"\n"):
        data = data[:-1]
    lines = data.replace(b"\r\n", b"\n").split(b"\n")
    require(len(lines) == n*n, "coefficient count")
    require(all(re.fullmatch(b"[0-9A-Fa-f]{2}", v) for v in lines), "coefficient grammar")
    return tuple((v if v < 128 else v - 256) for v in (int(x, 16) for x in lines))
