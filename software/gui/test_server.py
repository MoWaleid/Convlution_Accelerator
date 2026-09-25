"""Focused host tests for the board-local GUI service."""

from __future__ import annotations

import base64
import json
import tempfile
import threading
import time
import unittest
import urllib.error
import urllib.request
from dataclasses import replace
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

from server import Application, Config, GuiError, ThreadingHTTPServer, make_handler


PNG_1X1 = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk+A8AAQUBAScY42YAAAAASUVORK5CYII="
)


class GuiServiceTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.static = Path(__file__).resolve().parent / "static"
        self.catalog = self.root / "m7_profiles.json"
        self.profiles = self.root / "profiles"
        self.results = self.root / "results"
        self.uploads = self.root / "uploads"
        self.images = self.root / "board-images"
        self.profiles.mkdir()
        (self.images / "demo").mkdir(parents=True)
        (self.images / "demo" / "cat.png").write_bytes(PNG_1X1)
        (self.images / "ignored.txt").write_text("not an image", encoding="utf-8")
        self.catalog.write_text(json.dumps({
            "profiles": {
                "A32_CFGLUT125": {
                    "W": 32, "H": 32, "N": 3, "K": 8, "build_id": "test",
                },
            },
            "releases": {
                "A32_CFGLUT125": {
                    "shape_id": "N3K8W32H32-CVH1",
                    "manifest": "hardware_A32_CFGLUT125.json",
                    "bundle_sha256": "1" * 64,
                },
            },
        }), encoding="utf-8")
        self.config = Config(
            self.static, self.catalog, self.profiles, self.results, self.uploads,
            (self.images,), Path(__file__), "python", "127.0.0.1", 0, True,
            "",
        )
        self.app = Application(self.config)

    def tearDown(self):
        self.temp.cleanup()

    def wait_for_job(self):
        for _ in range(100):
            status = self.app.status()
            if status["last"]:
                return status["last"]
            time.sleep(.01)
        self.fail("demo job did not finish")

    def test_image_library_is_bounded_and_opaque(self):
        images = self.app.images()
        self.assertEqual(len(images), 1)
        image = images[0]
        self.assertEqual(image["relative_path"], "demo/cat.png")
        self.assertNotIn(str(self.root), json.dumps(image))
        path, content_type = self.app.board_image_content(image["id"])
        self.assertEqual(path.read_bytes(), PNG_1X1)
        self.assertEqual(content_type, "image/png")
        with self.assertRaises(GuiError):
            self.app.board_image_path("../../etc/passwd")

    def test_board_image_job_uses_catalogued_identity(self):
        image_id = self.app.images()[0]["id"]
        job = self.app.submit({
            "mode": "run", "profile": "A32_CFGLUT125", "frames": 1,
            "previews": True, "board_image": image_id,
        })
        self.assertIn("board library", job["source"])
        completed = self.wait_for_job()
        self.assertEqual(completed["state"], "complete")
        self.assertEqual(completed["profile"], "A32_CFGLUT125")

    def test_real_runtime_request_uses_on_board_resize_policy(self):
        image = self.images / "demo" / "cat.png"
        request = {
            "mode": "run", "profile": "A32_CFGLUT125", "frames": 1,
            "previews": True, "trusted_library": True,
        }
        with patch("server.subprocess.run") as run:
            run.return_value = SimpleNamespace(returncode=0, stdout="PASS", stderr="")
            self.app._invoke_runtime(request, image)
        command = run.call_args.args[0]
        self.assertEqual(command[command.index("--image-policy") + 1], "resize_exact")
        self.assertEqual(command[command.index("--image") + 1], str(image))
        self.assertEqual(command[command.index("--image-label") + 1], "image")
        self.assertIn("--trusted-library", command)

    def test_unknown_profile_and_image_are_rejected(self):
        with self.assertRaises(GuiError):
            self.app.submit({"mode": "run", "profile": "unknown", "frames": 1})
        with self.assertRaises(GuiError):
            self.app.submit({
                "mode": "run", "profile": "A32_CFGLUT125", "frames": 1,
                "board_image": "0" * 20,
            })

    def test_result_exposes_all_recorded_channel_previews(self):
        run = self.results / "run-1"
        run.mkdir()
        previews = [f"preview_ch{index}.png" for index in (5, 2, 0, 4, 1, 3)]
        for name in previews:
            (run / name).write_bytes(PNG_1X1)
        (run / "record.json").write_text(json.dumps({
            "run_id": "run-1", "outcome": "PASS", "profile": {
                "name": "B32_CFGLUT125", "N": 3, "K": 16, "W": 32, "H": 32,
            },
            "frames": [{"hw_ms": 1.0, "wall_ms": 2.0, "sha256": "abc"}],
            "previews": previews,
        }), encoding="utf-8")
        result = self.app.result("run-1")
        self.assertEqual(result["preview_total"], 6)
        self.assertEqual([item["name"] for item in result["previews"]], [
            "preview_ch0.png", "preview_ch1.png", "preview_ch2.png", "preview_ch3.png",
            "preview_ch4.png", "preview_ch5.png",
        ])
        self.assertEqual(self.app.preview_path("run-1", "preview_ch5.png").read_bytes(), PNG_1X1)

    def test_http_api_serves_profiles_images_and_security_headers(self):
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(self.app))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            with urllib.request.urlopen(base + "/api/profiles") as response:
                document = json.load(response)
                self.assertEqual(document["profiles"][0]["id"], "A32_CFGLUT125")
                self.assertIn("default-src 'self'", response.headers["Content-Security-Policy"])
            with urllib.request.urlopen(base + "/api/images") as response:
                image_id = json.load(response)["images"][0]["id"]
            with urllib.request.urlopen(base + f"/api/images/{image_id}/content") as response:
                self.assertEqual(response.read(), PNG_1X1)
                self.assertEqual(response.headers.get_content_type(), "image/png")
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(base + "/api/images/../../etc/passwd/content")
            self.assertEqual(rejected.exception.code, 404)
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)

    def test_production_authentication_guards_static_and_api_routes(self):
        token = "0123456789abcdef0123456789abcdef"
        secure_app = Application(replace(self.config, demo=False, auth_token=token))
        server = ThreadingHTTPServer(("127.0.0.1", 0), make_handler(secure_app))
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base = f"http://127.0.0.1:{server.server_address[1]}"
        try:
            with self.assertRaises(urllib.error.HTTPError) as rejected:
                urllib.request.urlopen(base + "/api/status")
            self.assertEqual(rejected.exception.code, 401)
            credentials = base64.b64encode(f"conv:{token}".encode()).decode()
            request = urllib.request.Request(
                base + "/api/status", headers={"Authorization": f"Basic {credentials}"},
            )
            with urllib.request.urlopen(request) as response:
                self.assertEqual(json.load(response)["authentication"], "basic")
        finally:
            server.shutdown()
            server.server_close()
            thread.join(timeout=2)


if __name__ == "__main__":
    unittest.main(verbosity=2)
