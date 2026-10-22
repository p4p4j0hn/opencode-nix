"""Black-box OpenCode V2 integration tests; no model credentials required.

Run with OPENCODE_BIN=/path/to/opencode python3 -m unittest tests.test_backend_integration -v
Each test owns an isolated XDG profile and an ephemeral loopback listener.
"""

import base64
import json
import os
import socket
import subprocess
import tempfile
import time
import unittest
from pathlib import Path
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
    def __init__(self, root, *, password="ci-test-only-secret", config=None):
        self.root = Path(root)
        self.password = password
        self.config = config or {}
        self.process = None
        self._last_stderr = b""
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
        self.env.pop("OPENCODE_PASSWORD", None)
        self.env["OPENCODE_SERVER_PASSWORD"] = password

    def start(self):
        with socket.socket() as sock:
            sock.bind(("127.0.0.1", 0))
            port = sock.getsockname()[1]
        self.base = f"http://127.0.0.1:{port}"
        self.process = subprocess.Popen(
            [
                os.environ["OPENCODE_BIN"],
                "serve",
                "--hostname",
                "127.0.0.1",
                "--port",
                str(port),
            ],
            env=self.env,
            cwd=self.root,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.PIPE,
        )
        deadline = time.monotonic() + 20
        observations = []
        while time.monotonic() < deadline:
            if self.process.poll() is not None:
                raise AssertionError(
                    f"OpenCode exited early ({self.process.returncode}): "
                    f"{self.process.stderr.read()[-3000:]!r}"
                )
            try:
                code, health = request(self.base, "/api/info", password=self.password)
                if code == 200 and isinstance(health, dict):
                    return self
            except HTTPError as error:
                observations.append(f"HTTP {error.code}: {error.read(300)!r}")
            except (URLError, TimeoutError, ValueError) as error:
                observations.append(f"{type(error).__name__}: {str(error)[:200]}")
            time.sleep(0.25)
        self.stop()
        log = (self._last_stderr or b"")[-3000:].decode("utf-8", "replace")
        raise AssertionError(
            f"OpenCode API readiness check failed at {self.base}; "
            f"probes={observations[-5:]}; stderr={log}"
        )

    def stop(self):
        if self.process is not None:
            if self.process.poll() is None:
                self.process.terminate()
                try:
                    _, self._last_stderr = self.process.communicate(timeout=8)
                except subprocess.TimeoutExpired:
                    self.process.kill()
                    _, self._last_stderr = self.process.communicate(timeout=5)
            else:
                _, self._last_stderr = self.process.communicate()
            self.process = None


@unittest.skipUnless(
    os.environ.get("OPENCODE_BIN"), "Set OPENCODE_BIN to the packaged executable"
)
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
        server = self.launch(
            config={
                "compaction": {"auto": True, "keep": {"tokens": 24000}, "buffer": 24000}
            }
        )
        status, health = request(server.base, "/api/info", password=server.password)
        self.assertEqual(status, 200)
        self.assertIsInstance(health, dict)
        status, cfg = request(server.base, "/api/config", password=server.password)
        self.assertEqual(status, 200)
        self.assertIsInstance(cfg, list)
        self.assertGreaterEqual(len(cfg), 1)

    def test_password_protection(self):
        server = self.launch(password="integration-test-password")
        with self.assertRaises(HTTPError) as e:
            request(server.base, "/api/config")
        self.assertEqual(e.exception.code, 401)
        code, config = request(server.base, "/api/config", password=server.password)
        self.assertEqual(code, 200)
        self.assertIsInstance(config, list)

    def test_session_survives_backend_restart(self):
        server = self.launch()
        status, session = request(
            server.base,
            "/api/session",
            method="POST",
            payload={"title": "restart-test"},
            password=server.password,
        )
        self.assertIn(status, (200, 201))
        self.assertIsInstance(session, dict)
        session_id = session.get("data", session)["id"]
        server.stop()
        server.start()
        status, restored = request(
            server.base, "/api/session/" + session_id, password=server.password
        )
        self.assertEqual(status, 200)
        self.assertEqual(restored.get("data", restored)["id"], session_id)


if __name__ == "__main__":
    unittest.main()
