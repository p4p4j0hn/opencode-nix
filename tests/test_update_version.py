import importlib.util
import unittest
from pathlib import Path

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
            all(package.startswith("@opencode/cli-") for package in updater.PACKAGES.values())
        )

    def test_registry_target_is_npm(self):
        self.assertEqual(updater.REGISTRY, "https://registry.npmjs.org")


if __name__ == "__main__":
    unittest.main()
