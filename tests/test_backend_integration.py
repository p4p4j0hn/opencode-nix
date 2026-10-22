"""Black-box OpenCode V2 integration tests; no model credentials required.

Run with OPENCODE_BIN=/path/to/opencode python3 -m unittest tests.test_backend_integration -v
Each test owns an isolated XDG profile and an ephemeral loopback listener.
"""
import base64
import contextlib
import json
import os
from pathlib import Path
import socket
import subprocess
import tempfile
import time
import unittest
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen


def request(base, path, *, method="GET", payload=None, password=None):
    headers = {}
    if payload is not None:
        headers["Content-Type"] = "application/json"
    if password is not None:
        token = base64.b64encode(("opencode:" + password).encode()).decode()
        headers["Authorization"] = "Basic " + token
    data = None if payload is None else json.dumps(payload).encode()
    req = Request(base + path, data=data, headers=headers, method=method)
    with urlopen(req, timeout=4) as response:
        body = response.read()
        return response.status, json.loads(body) if body else None


class Backend:
    def __init__(self, root, *, password=None, config=None):
        self.root = Path(root)
        self.password = password
        self.config = config or {}
        self.process = None
        self.root.mkdir(parents=True, exist_ok=True)
        self.config_dir = self.root / "config" / "opencode"
        self.config_dir.mkdir(parents=True, exist_ok=True)
        (self.config_dir / "opencode.json").write_text(json.dumps(self.config))
        self.env = os.environ.copy()
        for key, directory in (
            ("XDG_CONFIG_HOME", "config"),
            ("XDG_DATA_HOME", "data"),
            ("XDG_STATE_HOME", "state"),
            ("XDG_CACHE_HOME", "cache"),
        ):
            p = self.root / directory
            p.mkdir(exist_ok=True)
            self.env[key] = str(p)
        self.env["HOME"] = str(self.root)
        self.env.pop("OPENCODE_SERVER_PASSWORD", None)
        if password is not None:
            self.env["OPENCODE_SERVER_PASSWORD"] = password

    def start(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        self.base = f"http://127.0.0.1:{port}"
        self.process = subprocess.Popen(
            [os.environ["OPENCODE_BIN"], "serve", "--hostname", "127.0.0.1", "--port", str(port)],
            env=self.env, cwd=self.root, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 35
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError(f"OpenCode exited early ({self.process.returncode}): {self.process.stderr.read()[-3000:]!r}")
            try:
                code, health = request(self.base, "/api/health", password=self.password)
                if code == 200 and isinstance(health, dict):
                    return self
            except (HTTPError, URLError, TimeoutError, ValueError):
                pass
            time.sleep(0.25)
        self.stop()
        raise AssertionError(f"OpenCode failed V2 /api/health check within 35 seconds at {self.base}")

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    self.process.communicate(timeout=8)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    self.process.communicate(timeout=5)
            else:
                self.process.communicate()
            self.process = None


@unittest.skipUnless(os.environ.get("OPENCODE_BIN"), "Set OPENCODE_BIN to the packaged executable")
class BackendIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="opencode-v2-test-")
        self.addCleanup(self.tmp.cleanup)
        self.backend = None

    def launch(self, **kwargs):
        self.backend = Backend(self.tmp.name, **kwargs).start()
        self.addCleanup(self.backend.stop)
        return self.backend

    def test_health_and_config(self):
        server = self.launch(config={"compaction": {"auto": True, "keep": {"tokens": 24000}, "buffer": 24000}})
        status, health = request(server.base, "/api/health")
        self.assertEqual(status, 200)
        self.assertIsInstance(health, dict)
        status, cfg = request(server.base, "/api/config")
        self.assertEqual(status, 200)
        cfg = cfg.get("data", cfg)
        self.assertTrue(cfg["compaction"]["auto"])
        self.assertEqual(cfg["compaction"]["keep"]["tokens"], 24000)
        self.assertEqual(cfg["compaction"]["buffer"], 24000)

    def test_password_protection(self):
        server = self.launch(password="integration-test-password")
        with self.assertRaises(HTTPError) as e:
            request(server.base, "/api/config")
        self.assertEqual(e.exception.code, 401)
        code, config = request(server.base, "/api/config", password=server.password)
        self.assertEqual(code, 200)
        self.assertIsInstance(config, dict)

    def test_session_survives_backend_restart(self):
        server = self.launch()
        status, session = request(server.base, "/api/session", method="POST", payload={"title": "restart-test"})
        self.assertIn(status, (200, 201))
        self.assertIsInstance(session, dict)
        session_id = session.get("data", session)["id"]
        server.stop()
        server.start()
        status, restored = request(server.base, "/api/session/" + session_id)
        self.assertEqual(status, 200)
        self.assertEqual(restored.get("data", restored)["id"], session_id)


if __name__ == "__main__":
    unittest.main()
