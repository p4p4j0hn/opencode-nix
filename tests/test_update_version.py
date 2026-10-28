import base64
import hashlib
import importlib.util
import io
import json
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location(
    "updater", Path(__file__).resolve().parents[1] / "scripts" / "update-version.py"
)
updater = importlib.util.module_from_spec(spec)
spec.loader.exec_module(updater)


class UpdateVersionTests(unittest.TestCase):
    def test_all_four_native_packages_are_v2(self):
        self.assertEqual(
            set(updater.PACKAGES),
            {"x86_64-linux", "aarch64-linux", "x86_64-darwin", "aarch64-darwin"},
        )
        self.assertTrue(
            all(
                package.startswith("@opencode/cli-")
                for package in updater.PACKAGES.values()
            )
        )

    def test_registry_target_is_npm(self):
        self.assertEqual(updater.REGISTRY, "https://registry.npmjs.org")

    def test_hashes_valid_schema(self):
        url = "https://opencode.ai/v2/cli.json"
        schema = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": url,
            "type": "object",
            "properties": {"tabs": {"type": "object"}},
        }
        payload = json.dumps(schema).encode()
        with patch.object(updater, "open_url", return_value=io.BytesIO(payload)):
            actual = updater.get_schema_hash("cli", url)
        expected = (
            "sha256-" + base64.b64encode(hashlib.sha256(payload).digest()).decode()
        )
        self.assertEqual(actual, expected)

    def test_rejects_schema_from_wrong_id(self):
        url = "https://opencode.ai/config.json"
        schema = {
            "$schema": "https://json-schema.org/draft/2020-12/schema",
            "$id": "https://unrelated.example/config.json",
            "properties": {"agents": {}},
        }
        with patch.object(
            updater, "open_url", return_value=io.BytesIO(json.dumps(schema).encode())
        ):
            with self.assertRaisesRegex(ValueError, "schema id"):
                updater.get_schema_hash("config", url)


if __name__ == "__main__":
    unittest.main()
