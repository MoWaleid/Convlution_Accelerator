#!/usr/bin/env python3
"""Board-local HTTP service for the convolution accelerator demonstration UI.

The service deliberately wraps the qualified command-line runtime instead of
reimplementing hardware access.  It accepts only catalogued profile IDs,
serializes every hardware operation, invokes subprocesses without a shell, and
serves only explicitly admitted result previews.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
import re
import secrets
import socket
import statistics
import subprocess
import sys
import threading
import time
import uuid
from dataclasses import dataclass
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote, urlparse


MAX_JSON_BYTES = 64 * 1024
MAX_UPLOAD_BYTES = 8 * 1024 * 1024
MAX_LIBRARY_IMAGES = 512
TRUSTED_LIBRARY_ROOT = Path(os.environ.get(
    "CONV_GUI_TRUSTED_LIBRARY_ROOT",
    "/opt/conv-lab/library/datasets/cifar10-demo/v1/images"))
SAFE_RUN_ID = re.compile(r"[A-Za-z0-9._-]+")
SAFE_IMAGE_ID = re.compile(r"[0-9a-f]{20}")
STATIC_FILES = {
    "/": ("index.html", "text/html; charset=utf-8"),
    "/index.html": ("index.html", "text/html; charset=utf-8"),
    "/app.css": ("app.css", "text/css; charset=utf-8"),
    "/app.js": ("app.js", "text/javascript; charset=utf-8"),
    "/favicon.svg": ("favicon.svg", "image/svg+xml"),
}


def json_bytes(value) -> bytes:
    return (json.dumps(value, separators=(",", ":"), ensure_ascii=False) + "\n").encode()


def percentile(values: list[float], fraction: float) -> float | None:
    if not values:
        return None
    ordered = sorted(values)
    index = min(len(ordered) - 1, max(0, int((len(ordered) - 1) * fraction + 0.999999)))
    return ordered[index]


@dataclass(frozen=True)
class Config:
    static_root: Path
    catalog_path: Path
    profiles_root: Path
    results_root: Path
    uploads_root: Path
    image_roots: tuple[Path, ...]
    cli_path: Path
    python: str
    bind: str
    port: int
    demo: bool
    auth_token: str


class GuiError(RuntimeError):
    def __init__(self, status: int, message: str):
        super().__init__(message)
        self.status = status


class Application:
    def __init__(self, config: Config):
        self.config = config
        self._mutex = threading.Lock()
        self._current: dict | None = None
        self._last: dict | None = None
        self._profiles = self._load_profiles()
        self._images: dict[str, dict] = {}
        self.refresh_images()
        config.uploads_root.mkdir(parents=True, exist_ok=True)
        config.results_root.mkdir(parents=True, exist_ok=True)

    def _load_profiles(self) -> list[dict]:
        document = json.loads(self.config.catalog_path.read_text(encoding="utf-8"))
        profiles = document.get("profiles")
        releases = document.get("releases")
        if not isinstance(profiles, dict) or not isinstance(releases, dict):
            raise RuntimeError("profile catalog is malformed")
        result = []
        for name in sorted(profiles):
            value = profiles[name]
            release = releases.get(name)
            if not isinstance(value, dict) or not isinstance(release, dict):
                continue
            manifest = self.config.profiles_root / f"hardware_{name}.json"
            hardware = {}
            if manifest.is_file():
                try:
                    hardware = json.loads(manifest.read_text(encoding="utf-8")).get("accelerator", {})
                except (OSError, ValueError):
                    hardware = {}
            result.append({
                "id": name,
                "label": name.replace("_CFGLUT125", ""),
                "W": int(value["W"]), "H": int(value["H"]),
                "N": int(value["N"]), "K": int(value["K"]),
                "clock_mhz": int(hardware.get("clock_mhz", 125)),
                "shape_id": release.get("shape_id"),
                "build_id": value.get("build_id"),
                "qualified": bool(release.get("manifest") and release.get("bundle_sha256")),
            })
        if not result:
            raise RuntimeError("catalog contains no qualified profiles")
        return result

    def profiles(self) -> list[dict]:
        return self._profiles

    def profile_ids(self) -> set[str]:
        return {item["id"] for item in self._profiles}

    @staticmethod
    def _matches_image_signature(path: Path) -> bool:
        try:
            if not path.is_file() or not (0 < path.stat().st_size <= MAX_UPLOAD_BYTES):
                return False
            with path.open("rb") as stream:
                signature = stream.read(8)
        except OSError:
            return False
        suffix = path.suffix.lower()
        return ((suffix == ".png" and signature == b"\x89PNG\r\n\x1a\n") or
                (suffix in {".jpg", ".jpeg"} and signature.startswith(b"\xff\xd8\xff")))

    def refresh_images(self) -> list[dict]:
        images: dict[str, dict] = {}
        for root_index, configured_root in enumerate(self.config.image_roots):
            root = configured_root.resolve()
            if not root.is_dir():
                continue
            collection = root.name or f"library-{root_index + 1}"
            try:
                candidates = root.rglob("*")
                for candidate in candidates:
                    if len(images) >= MAX_LIBRARY_IMAGES:
                        break
                    try:
                        resolved = candidate.resolve(strict=True)
                        relative = resolved.relative_to(root)
                    except (OSError, ValueError):
                        continue
                    if not self._matches_image_signature(resolved):
                        continue
                    image_id = hashlib.sha256(
                        f"{root_index}:{relative.as_posix()}".encode("utf-8")
                    ).hexdigest()[:20]
                    images[image_id] = {
                        "id": image_id,
                        "name": resolved.name,
                        "relative_path": relative.as_posix(),
                        "collection": collection,
                        "size_bytes": resolved.stat().st_size,
                        "content_url": f"/api/images/{image_id}/content",
                        "_path": resolved,
                        "_root": root,
                    }
            except OSError:
                continue
        with self._mutex:
            self._images = images
        return self.images()

    def images(self) -> list[dict]:
        with self._mutex:
            values = list(self._images.values())
        return [{key: value for key, value in image.items() if not key.startswith("_")}
                for image in values]

    def board_image_path(self, image_id: str) -> Path:
        if not SAFE_IMAGE_ID.fullmatch(image_id):
            raise GuiError(HTTPStatus.BAD_REQUEST, "invalid board image ID")
        with self._mutex:
            image = dict(self._images.get(image_id, {}))
        if not image:
            raise GuiError(HTTPStatus.NOT_FOUND, "board image is no longer available")
        path, root = image["_path"].resolve(), image["_root"].resolve()
        try:
            path.relative_to(root)
        except ValueError as exc:
            raise GuiError(HTTPStatus.NOT_FOUND, "board image escaped its admitted library") from exc
        if not self._matches_image_signature(path):
            raise GuiError(HTTPStatus.NOT_FOUND, "board image changed or is unreadable")
        return path

    def board_image_content(self, image_id: str) -> tuple[Path, str]:
        path = self.board_image_path(image_id)
        content_type = "image/png" if path.suffix.lower() == ".png" else "image/jpeg"
        return path, content_type

    @staticmethod
    def _trusted_library_path(path: Path) -> bool:
        try:
            path.resolve().relative_to(TRUSTED_LIBRARY_ROOT.resolve())
            return True
        except (OSError, ValueError):
            return False

    @staticmethod
    def _trusted_library_reference(path: Path, profile: str) -> bool:
        """Admit trust only when this exact image has a profile oracle."""
        try:
            root = TRUSTED_LIBRARY_ROOT.resolve()
            relative = path.resolve().relative_to(root)
            catalog = json.loads((root.parent / "reference_catalog.json").read_text(
                encoding="utf-8"))
            catalog_path = (Path("images") / relative).as_posix()
            for image in catalog.get("images", []):
                if (type(image) is dict and image.get("relative_path") == catalog_path and
                        type(image.get("references")) is dict):
                    return profile in image["references"]
            return False
        except (OSError, ValueError, TypeError, json.JSONDecodeError):
            return False

    def status(self) -> dict:
        with self._mutex:
            current = dict(self._current) if self._current else None
            last = dict(self._last) if self._last else None
        return {
            "service": "ready",
            "hostname": socket.gethostname(),
            "demo": self.config.demo,
            "authentication": "basic" if self.config.auth_token else "disabled-demo-only",
            "busy": bool(current and current.get("state") in {"queued", "running"}),
            "current": current,
            "last": last,
        }

    def recent_results(self, limit: int = 12) -> list[dict]:
        records = []
        if self.config.results_root.is_dir():
            paths = sorted(self.config.results_root.iterdir(), key=lambda p: p.stat().st_mtime,
                           reverse=True)
            for directory in paths:
                if len(records) >= limit or not directory.is_dir() or not SAFE_RUN_ID.fullmatch(directory.name):
                    continue
                record_path = directory / "record.json"
                if not record_path.is_file() or record_path.stat().st_size > 2 * 1024 * 1024:
                    continue
                try:
                    records.append(self._summary(json.loads(record_path.read_text(encoding="utf-8"))))
                except (OSError, ValueError, TypeError, KeyError):
                    continue
        return records

    def result(self, run_id: str) -> dict:
        directory = self._run_directory(run_id)
        path = directory / "record.json"
        if not path.is_file() or path.stat().st_size > 2 * 1024 * 1024:
            raise GuiError(HTTPStatus.NOT_FOUND, "run record not found")
        try:
            record = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise GuiError(HTTPStatus.INTERNAL_SERVER_ERROR, "run record is unreadable") from exc
        detail = self._summary(record)
        detail["input"] = record.get("input", {})
        detail["verification"] = record.get("verification", {})
        detail["switch"] = record.get("switch", {})
        detail["cleanup"] = record.get("cleanup", {})
        detail["failure"] = record.get("failure")
        detail["timing_scope"] = record.get("timings", {}).get("scope")
        admitted_previews = [
            {"name": name, "url": f"/api/results/{run_id}/preview/{name}"}
            for name in record.get("previews", [])
            if isinstance(name, str) and Path(name).name == name and name.endswith(".png")
        ]
        channel_previews = [item for item in admitted_previews
                            if re.fullmatch(r"preview_ch\d+\.png", item["name"])]
        channel_previews.sort(key=lambda item: int(item["name"][10:-4]))
        detail["preview_total"] = len(channel_previews)
        detail["previews"] = channel_previews
        return detail

    def preview_path(self, run_id: str, name: str) -> Path:
        if Path(name).name != name or not re.fullmatch(r"preview_[A-Za-z0-9_-]+\.png", name):
            raise GuiError(HTTPStatus.NOT_FOUND, "preview not found")
        detail = self.result(run_id)
        if name not in {item["name"] for item in detail["previews"]}:
            raise GuiError(HTTPStatus.NOT_FOUND, "preview not admitted by record")
        path = self._run_directory(run_id) / name
        if not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
            raise GuiError(HTTPStatus.NOT_FOUND, "preview not found")
        return path

    def _run_directory(self, run_id: str) -> Path:
        if not SAFE_RUN_ID.fullmatch(run_id) or ".." in run_id:
            raise GuiError(HTTPStatus.BAD_REQUEST, "invalid run ID")
        directory = (self.config.results_root / run_id).resolve()
        if directory.parent != self.config.results_root.resolve():
            raise GuiError(HTTPStatus.BAD_REQUEST, "invalid run ID")
        return directory

    @staticmethod
    def _summary(record: dict) -> dict:
        profile = record.get("profile", {})
        frames = record.get("frames", [])
        hardware = [float(item["hw_ms"]) for item in frames if isinstance(item, dict)
                    and isinstance(item.get("hw_ms"), (int, float))]
        wall = [float(item["wall_ms"]) for item in frames if isinstance(item, dict)
                and isinstance(item.get("wall_ms"), (int, float))]
        benchmark = record.get("timings", {}).get("hw_ms")
        if isinstance(benchmark, dict):
            hw_stats = {key: benchmark.get(key) for key in ("median", "p95", "min", "max")}
        else:
            hw_stats = {
                "median": statistics.median(hardware) if hardware else None,
                "p95": percentile(hardware, .95),
                "min": min(hardware) if hardware else None,
                "max": max(hardware) if hardware else None,
            }
        return {
            "run_id": record.get("run_id"),
            "outcome": record.get("outcome"),
            "started_utc": record.get("started_utc"),
            "profile": {
                "name": profile.get("name"), "N": profile.get("N"), "K": profile.get("K"),
                "W": profile.get("W"), "H": profile.get("H"),
            },
            "image_tag": record.get("image_tag"),
            "frame_count": len(frames),
            "hardware_ms": hw_stats,
            "wall_ms": {
                "median": statistics.median(wall) if wall else None,
                "p95": percentile(wall, .95),
                "min": min(wall) if wall else None,
                "max": max(wall) if wall else None,
            },
            "classification": record.get("classification"),
            "output_sha256": frames[-1].get("sha256") if frames else None,
        }

    def submit(self, request: dict, upload: bytes | None = None, filename: str = "") -> dict:
        request = dict(request)
        profile = request.get("profile")
        mode = request.get("mode", "run")
        if profile not in self.profile_ids():
            raise GuiError(HTTPStatus.BAD_REQUEST, "unknown or unqualified profile")
        if mode not in {"run", "benchmark"}:
            raise GuiError(HTTPStatus.BAD_REQUEST, "unsupported operation")
        frames = request.get("frames", 3 if mode == "run" else 100)
        warmup = request.get("warmup", 10)
        if type(frames) is not int or not (1 <= frames <= (20 if mode == "run" else 500)):
            raise GuiError(HTTPStatus.BAD_REQUEST, "frame count is outside the admitted range")
        if type(warmup) is not int or not (0 <= warmup <= 100):
            raise GuiError(HTTPStatus.BAD_REQUEST, "warm-up count is outside the admitted range")
        if upload is not None and mode != "run":
            raise GuiError(HTTPStatus.BAD_REQUEST, "uploads are supported only for inference runs")

        board_image_id = request.get("board_image")
        if board_image_id is not None and (upload is not None or mode != "run"):
            raise GuiError(HTTPStatus.BAD_REQUEST, "board images are supported only for inference runs")
        board_image_path = None
        board_image_label = None
        if board_image_id is not None:
            board_image_path = self.board_image_path(board_image_id)
            with self._mutex:
                board_image_label = self._images[board_image_id]["relative_path"]
            request["image_label"] = Path(board_image_label).stem
            request["trusted_library"] = self._trusted_library_reference(
                board_image_path, profile)

        upload_path = None
        if upload is not None:
            suffix = self._image_suffix(upload, filename)
            upload_path = self.config.uploads_root / f"gui-{uuid.uuid4().hex}{suffix}"
            upload_path.write_bytes(upload)
            request["image_label"] = Path(filename).name.rsplit(".", 1)[0]

        with self._mutex:
            if self._current and self._current.get("state") in {"queued", "running"}:
                if upload_path:
                    upload_path.unlink(missing_ok=True)
                raise GuiError(HTTPStatus.CONFLICT, "another hardware operation is running")
            job = {
                "id": uuid.uuid4().hex[:12], "state": "queued", "mode": mode,
                "profile": profile, "frames": frames, "warmup": warmup,
                "submitted_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
                "source": ("upload" if upload_path else
                           f"board library · {board_image_label}" if board_image_path else
                           "verified library image"),
            }
            self._current = job
        thread = threading.Thread(target=self._run_job,
                                  args=(job["id"], request, board_image_path or upload_path,
                                        upload_path), daemon=True)
        thread.start()
        return job

    @staticmethod
    def _image_suffix(data: bytes, filename: str) -> str:
        if not data or len(data) > MAX_UPLOAD_BYTES:
            raise GuiError(HTTPStatus.BAD_REQUEST, "image is empty or too large")
        lower = filename.lower()
        if data.startswith(b"\x89PNG\r\n\x1a\n") and lower.endswith(".png"):
            return ".png"
        if data.startswith(b"\xff\xd8\xff") and lower.endswith((".jpg", ".jpeg")):
            return ".jpg"
        raise GuiError(HTTPStatus.BAD_REQUEST, "only signature-matched PNG and JPEG files are accepted")

    def _run_job(self, job_id: str, request: dict, image_path: Path | None,
                 cleanup_path: Path | None):
        started = time.monotonic()
        with self._mutex:
            if not self._current or self._current["id"] != job_id:
                return
            self._current["state"] = "running"
            self._current["started_utc"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
        try:
            if self.config.demo:
                time.sleep(.35)
                result = {
                    "returncode": 0, "stdout": "demo operation completed", "stderr": "",
                    "run_id": None,
                    "demo_metrics": {"median": .128, "p95": .133, "min": .124, "max": .136},
                }
            else:
                result = self._invoke_runtime(request, image_path)
            state = "complete" if result["returncode"] == 0 else "failed"
            completed = {
                "id": job_id, "state": state, "mode": request.get("mode", "run"),
                "profile": request["profile"], "frames": request["frames"],
                "elapsed_s": round(time.monotonic() - started, 3),
                "run_id": result.get("run_id"),
                "stdout": result.get("stdout", "")[-8192:],
                "stderr": result.get("stderr", "")[-8192:],
                "demo_metrics": result.get("demo_metrics"),
            }
        except BaseException as exc:
            completed = {
                "id": job_id, "state": "failed", "mode": request.get("mode", "run"),
                "profile": request.get("profile"), "elapsed_s": round(time.monotonic() - started, 3),
                "error": f"{type(exc).__name__}: {exc}",
            }
        finally:
            if cleanup_path:
                cleanup_path.unlink(missing_ok=True)
        with self._mutex:
            self._current = completed
            self._last = completed

    def _invoke_runtime(self, request: dict, image_path: Path | None) -> dict:
        before = {p.name for p in self.config.results_root.iterdir() if p.is_dir()}
        mode = request.get("mode", "run")
        command = [self.config.python, "-B", str(self.config.cli_path), mode,
                   "--profile", request["profile"], "--frames", str(request["frames"])]
        if mode == "benchmark":
            command += ["--warmup", str(request["warmup"])]
        else:
            if request.get("previews", True):
                command.append("--previews")
            if image_path:
                command += ["--image", str(image_path),
                            "--image-policy", "resize_exact",
                            "--image-label", str(request.get("image_label", "image"))]
                if request.get("trusted_library"):
                    command.append("--trusted-library")
        environment = dict(os.environ)
        environment["M8_ARCHIVE_ROOT"] = str(self.config.results_root)
        completed = subprocess.run(command, shell=False, text=True, capture_output=True,
                                   timeout=300, env=environment, check=False)
        after = {p.name for p in self.config.results_root.iterdir()
                 if p.is_dir() and (p / "record.json").is_file()}
        new = sorted(after - before)
        run_id = new[-1] if len(new) == 1 else None
        return {"returncode": completed.returncode, "stdout": completed.stdout,
                "stderr": completed.stderr, "run_id": run_id}


def make_handler(app: Application):
    class Handler(BaseHTTPRequestHandler):
        server_version = "ConvLabGUI/1.0"

        def log_message(self, fmt, *args):
            sys.stderr.write("%s - %s\n" % (self.address_string(), fmt % args))

        def require_authentication(self) -> bool:
            if not app.config.auth_token:
                return True
            header = self.headers.get("Authorization", "")
            valid = False
            if header.startswith("Basic "):
                try:
                    decoded = base64.b64decode(header[6:], validate=True).decode("utf-8")
                    username, password = decoded.split(":", 1)
                    valid = (secrets.compare_digest(username, "conv") and
                             secrets.compare_digest(password, app.config.auth_token))
                except (ValueError, UnicodeError):
                    valid = False
            if valid:
                return True
            body = json_bytes({"error": "authentication required"})
            self.send_response(HTTPStatus.UNAUTHORIZED)
            self.send_header("WWW-Authenticate", 'Basic realm="Convolution Lab", charset="UTF-8"')
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
            return False

        def end_headers(self):
            self.send_header("X-Content-Type-Options", "nosniff")
            self.send_header("X-Frame-Options", "DENY")
            self.send_header("Referrer-Policy", "no-referrer")
            self.send_header("Cache-Control", "no-store")
            self.send_header("Content-Security-Policy",
                             "default-src 'self'; img-src 'self' data:; "
                             "style-src 'self'; script-src 'self'; connect-src 'self'")
            super().end_headers()

        def send_payload(self, status: int, body: bytes, content_type: str):
            self.send_response(status)
            self.send_header("Content-Type", content_type)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def send_json(self, status: int, value):
            self.send_payload(status, json_bytes(value), "application/json; charset=utf-8")

        def read_body(self, limit: int) -> bytes:
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError as exc:
                raise GuiError(HTTPStatus.BAD_REQUEST, "invalid content length") from exc
            if length < 1 or length > limit:
                raise GuiError(HTTPStatus.REQUEST_ENTITY_TOO_LARGE, "request body is outside the admitted size")
            return self.rfile.read(length)

        def do_GET(self):
            if not self.require_authentication():
                return
            try:
                path = unquote(urlparse(self.path).path)
                if path in STATIC_FILES:
                    name, content_type = STATIC_FILES[path]
                    self.send_payload(HTTPStatus.OK,
                                      (app.config.static_root / name).read_bytes(), content_type)
                elif path == "/api/status":
                    self.send_json(HTTPStatus.OK, app.status())
                elif path == "/api/profiles":
                    self.send_json(HTTPStatus.OK, {"profiles": app.profiles()})
                elif path == "/api/images":
                    self.send_json(HTTPStatus.OK, {"images": app.refresh_images()})
                elif re.fullmatch(r"/api/images/[0-9a-f]{20}/content", path):
                    image_id = path.split("/")[3]
                    image, content_type = app.board_image_content(image_id)
                    self.send_payload(HTTPStatus.OK, image.read_bytes(), content_type)
                elif path == "/api/results":
                    self.send_json(HTTPStatus.OK, {"results": app.recent_results()})
                elif re.fullmatch(r"/api/results/[^/]+", path):
                    self.send_json(HTTPStatus.OK, app.result(path.rsplit("/", 1)[1]))
                elif re.fullmatch(r"/api/results/[^/]+/preview/[^/]+", path):
                    _, _, _, run_id, _, name = path.split("/", 5)
                    preview = app.preview_path(run_id, name)
                    self.send_payload(HTTPStatus.OK, preview.read_bytes(), "image/png")
                else:
                    raise GuiError(HTTPStatus.NOT_FOUND, "not found")
            except GuiError as exc:
                self.send_json(exc.status, {"error": str(exc)})
            except (OSError, ValueError) as exc:
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

        def do_POST(self):
            if not self.require_authentication():
                return
            try:
                path = unquote(urlparse(self.path).path)
                if path == "/api/jobs":
                    if self.headers.get_content_type() != "application/json":
                        raise GuiError(HTTPStatus.UNSUPPORTED_MEDIA_TYPE, "expected application/json")
                    request = json.loads(self.read_body(MAX_JSON_BYTES))
                    if not isinstance(request, dict):
                        raise GuiError(HTTPStatus.BAD_REQUEST, "JSON body must be an object")
                    self.send_json(HTTPStatus.ACCEPTED, app.submit(request))
                elif path == "/api/upload-jobs":
                    profile = self.headers.get("X-Profile", "")
                    filename = self.headers.get("X-Filename", "")
                    try:
                        frames = int(self.headers.get("X-Frames", "1"))
                    except ValueError as exc:
                        raise GuiError(HTTPStatus.BAD_REQUEST, "invalid frame count") from exc
                    request = {"mode": "run", "profile": profile, "frames": frames,
                               "previews": self.headers.get("X-Previews", "1") == "1"}
                    self.send_json(HTTPStatus.ACCEPTED,
                                   app.submit(request, self.read_body(MAX_UPLOAD_BYTES), filename))
                else:
                    raise GuiError(HTTPStatus.NOT_FOUND, "not found")
            except json.JSONDecodeError:
                self.send_json(HTTPStatus.BAD_REQUEST, {"error": "malformed JSON"})
            except GuiError as exc:
                self.send_json(exc.status, {"error": str(exc)})
            except (OSError, ValueError) as exc:
                self.send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"error": str(exc)})

    return Handler


def parse_args(argv=None):
    here = Path(__file__).resolve().parent
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--static", type=Path, default=here / "static")
    parser.add_argument("--catalog", type=Path,
                        default=Path(os.environ.get("CONV_GUI_CATALOG",
                                                   "/home/petalinux/profiles/m7_profiles.json")))
    parser.add_argument("--profiles", type=Path,
                        default=Path(os.environ.get("CONV_GUI_PROFILES", "/home/petalinux/profiles")))
    parser.add_argument("--results", type=Path,
                        default=Path(os.environ.get("CONV_GUI_RESULTS", "/var/lib/conv-lab/results")))
    parser.add_argument("--uploads", type=Path,
                        default=Path(os.environ.get("CONV_GUI_UPLOADS", "/var/lib/conv-lab/uploads")))
    parser.add_argument("--image-root", type=Path, action="append", dest="image_roots",
                        help="admitted board image directory; repeat for more roots")
    parser.add_argument("--cli", type=Path,
                        default=Path(os.environ.get("CONV_GUI_CLI", "/home/petalinux/m8_classify_cli.py")))
    parser.add_argument("--python", default=os.environ.get("CONV_GUI_PYTHON", sys.executable))
    parser.add_argument("--bind", default=os.environ.get("CONV_GUI_BIND", "0.0.0.0"))
    parser.add_argument("--port", type=int, default=int(os.environ.get("CONV_GUI_PORT", "8080")))
    parser.add_argument("--auth-token-file", type=Path,
                        default=Path(os.environ.get("CONV_GUI_AUTH_TOKEN_FILE",
                                                   "/etc/conv-lab-gui.token")))
    parser.add_argument("--demo", action="store_true")
    return parser.parse_args(argv)


def main(argv=None):
    args = parse_args(argv)
    env_roots = [Path(value) for value in os.environ.get("CONV_GUI_IMAGE_ROOTS", "").split(os.pathsep)
                 if value]
    image_roots = tuple(args.image_roots or env_roots or (
        Path("/opt/conv-lab/library/datasets"),
        Path("/home/petalinux/images"),
        Path("/var/lib/conv-lab/images"),
    ))
    auth_token = ""
    if args.auth_token_file.is_file():
        auth_token = args.auth_token_file.read_text(encoding="ascii").strip()
        if not re.fullmatch(r"[A-Za-z0-9._~-]{20,128}", auth_token):
            raise SystemExit("GUI authentication token is malformed")
    elif not args.demo:
        raise SystemExit(f"GUI authentication token not found: {args.auth_token_file}")
    config = Config(args.static.resolve(), args.catalog.resolve(), args.profiles.resolve(),
                    args.results.resolve(), args.uploads.resolve(),
                    tuple(path.resolve() for path in image_roots), args.cli.resolve(),
                    args.python, args.bind, args.port, args.demo, auth_token)
    if not config.static_root.is_dir():
        raise SystemExit(f"static asset directory not found: {config.static_root}")
    if not config.catalog_path.is_file():
        raise SystemExit(f"profile catalog not found: {config.catalog_path}")
    if not config.demo and not config.cli_path.is_file():
        raise SystemExit(f"runtime CLI not found: {config.cli_path}")
    app = Application(config)
    server = ThreadingHTTPServer((config.bind, config.port), make_handler(app))
    print(f"Conv Lab GUI listening on http://{config.bind}:{config.port}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
