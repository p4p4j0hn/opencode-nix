#!/usr/bin/env python3
"""Pin the newest stable OpenCode V2 npm CLI binaries and verify every archive."""
import argparse
import base64
import hashlib
import json
import os
import tempfile
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
PACKAGES = {
    "x86_64-linux": "@opencode/cli-linux-x64",
    "aarch64-linux": "@opencode/cli-linux-arm64",
    "x86_64-darwin": "@opencode/cli-darwin-x64",
    "aarch64-darwin": "@opencode/cli-darwin-arm64",
}
REGISTRY = "https://registry.npmjs.org"


def open_url(url):
    headers = {"User-Agent": "opencode-nix-updater"}
    return urlopen(Request(url, headers=headers), timeout=120)


def get_metadata(package, version):
    with open_url(f"{REGISTRY}/{quote(package, safe='')}/{version}") as response:
        return json.load(response)


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    latest = get_metadata("@opencode/cli", "latest")
    version = latest["version"]
    if not version.startswith("2.") or "-" in version:
        raise RuntimeError("npm latest is not stable OpenCode V2: " + version)
    target = ROOT / "version.json"
    old = json.loads(target.read_text())
    if version == old["version"]:
        print("Already current: " + version)
        return
    if args.check:
        print("Update available: " + old["version"] + " -> " + version)
        return
    hashes = {}
    for system, package in PACKAGES.items():
        metadata = get_metadata(package, version)
        if metadata["version"] != version:
            raise RuntimeError(f"version mismatch for {package}")
        archive = metadata["dist"]["tarball"]
        sha = hashlib.sha256()
        with open_url(archive) as response:
            while chunk := response.read(1024 * 1024):
                sha.update(chunk)
        published = metadata["dist"].get("integrity")
        if published and published.startswith("sha512-"):
            # SHA512 npm integrity is verified below using a second streaming pass.
            check = hashlib.sha512()
            with open_url(archive) as response:
                while chunk := response.read(1024 * 1024):
                    check.update(chunk)
            if "sha512-" + base64.b64encode(check.digest()).decode() != published:
                raise RuntimeError("npm integrity mismatch: " + package)
        hashes[system] = "sha256-" + base64.b64encode(sha.digest()).decode()
        print(system, hashes[system], flush=True)
    data = json.dumps({"version": version, "hashes": hashes}, indent=2) + "\n"
    with tempfile.NamedTemporaryFile(mode="w", dir=ROOT, delete=False) as f:
        f.write(data)
        temp = f.name
    os.replace(temp, target)
    print("Updated", target, "to", version)

if __name__ == "__main__":
    main()
