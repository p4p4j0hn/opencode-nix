"""Unit tests for automated OpenCode release PR verification."""

import base64
import hashlib
import importlib.util
import json
import unittest
from pathlib import Path

script = Path(__file__).resolve().parents[1] / "scripts" / "verify-release-pr.py"
spec = importlib.util.spec_from_file_location("verify_release_pr", script)
policy = importlib.util.module_from_spec(spec)
spec.loader.exec_module(policy)


def hash_data(data):
    return "sha256-" + base64.b64encode(hashlib.sha256(data).digest()).decode()


class ReleasePolicyTests(unittest.TestCase):
    def setUp(self):
        self.version = "2.2.0"
        self.pr = {
            "head": {
                "ref": "automation/opencode-release",
                "repo": {"full_name": "p4p4j0hn/opencode-nix"},
            },
            "user": {"login": "opencode-nix-updater[bot]"},
        }
        self.changes = [{"filename": "version.json", "status": "modified"}]
        self.schemas = {
            name: json.dumps(
                {
                    "$id": url,
                    "$schema": "https://json-schema.org/draft/2020-12/schema",
                    "properties": {("tabs" if name == "cli" else "agents"): {}},
                }
            ).encode()
            for name, url in policy.SCHEMAS.items()
        }
        self.archive = b"fake-but-consistent-npm-archive"
        self.package_sha256 = hash_data(self.archive)
        self.package_integrity = (
            "sha512-"
            + base64.b64encode(hashlib.sha512(self.archive).digest()).decode()
        )
        self.pins = {
            "version": self.version,
            "hashes": {name: self.package_sha256 for name in policy.PACKAGES},
            "schemaHashes": {
                name: hash_data(data) for name, data in self.schemas.items()
            },
        }

    def registry(self, name, version):
        self.assertIn(name, policy.PACKAGES.values())
        return {
            "name": name,
            "version": version,
            "dist": {
                "tarball": policy.tarball_url(name, version),
                "integrity": self.package_integrity,
            },
        }

    def archive_hashes(self, url):
        self.assertTrue(url.startswith(policy.REGISTRY + "/"))
        return self.package_sha256, self.package_integrity

    def schema_bytes(self, url):
        name = next(name for name, val in policy.SCHEMAS.items() if val == url)
        return self.schemas[name]

    def run_verify(self):
        return policy.verify_release(
            self.pr,
            self.changes,
            self.pins,
            "p4p4j0hn/opencode-nix",
            self.registry,
            self.archive_hashes,
            self.schema_bytes,
        )

    def test_app_authored_update_passes(self):
        self.assertEqual(self.run_verify(), "verified")

    def test_github_actions_bot_still_supported(self):
        self.pr["user"]["login"] = "github-actions[bot]"
        self.assertEqual(self.run_verify(), "verified")

    def test_rejects_wrong_author(self):
        self.pr["user"]["login"] = "random-user"
        with self.assertRaisesRegex(ValueError, "author"):
            self.run_verify()

    def test_rejects_unexpected_files(self):
        self.changes.append({"filename": "arbitrary.nix", "status": "added"})
        with self.assertRaisesRegex(ValueError, "Unexpected"):
            self.run_verify()

    def test_policy_change_requires_manual_review(self):
        self.changes.extend(
            [
                {"filename": "scripts/verify-release-pr.py", "status": "modified"},
                {
                    "filename": ".github/workflows/release-policy.yml",
                    "status": "modified",
                },
                {"filename": "tests/test_verify_release_pr.py", "status": "added"},
            ]
        )
        self.assertEqual(self.run_verify(), "manual-review-required")

    def test_rejects_bad_package_hash(self):
        self.pins["hashes"]["x86_64-linux"] = hash_data(b"tampered")
        with self.assertRaisesRegex(ValueError, "SHA-256 mismatch"):
            self.run_verify()

    def test_rejects_bad_npm_integrity(self):
        original = self.package_integrity
        self.package_integrity = (
            "sha512-" + base64.b64encode(bytes(64)).decode()
        )
        self.archive_hashes = lambda url: (self.package_sha256, original)
        with self.assertRaisesRegex(ValueError, "npm integrity mismatch"):
            self.run_verify()

    def test_rejects_schema_hash_change(self):
        self.pins["schemaHashes"]["cli"] = hash_data(b"stale schema")
        with self.assertRaisesRegex(ValueError, "schema hash mismatch"):
            self.run_verify()

    def test_rejects_legacy_version_structure(self):
        self.pins.pop("schemaHashes")
        with self.assertRaisesRegex(ValueError, "Unexpected version.json"):
            self.run_verify()

    def test_rejects_inconsistent_package_name(self):
        registry = lambda name, version: {
            **self.registry(name, version),
            "name": "another-package",
        }
        with self.assertRaisesRegex(ValueError, "package metadata"):
            policy.verify_release(
                self.pr,
                self.changes,
                self.pins,
                "p4p4j0hn/opencode-nix",
                registry,
                self.archive_hashes,
                self.schema_bytes,
            )


if __name__ == "__main__":
    unittest.main()
