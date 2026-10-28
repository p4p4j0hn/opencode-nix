#!/usr/bin/env python3
"""Pin the newest stable OpenCode V2 binaries and upstream JSON schemas."""

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
SCHEMAS = {
    "cli": "https://opencode.ai/v2/cli.json",
    "config": "https://opencode.ai/config.json",
}


def open_url(url):
    headers = {"User-Agent": "opencode-nix-updater"}
    return urlopen(Request(url, headers=headers), timeout=120)


def get_metadata(package, version):
    with open_url(f"{REGISTRY}/{quote(package, safe='')}/{version}") as response:
        return json.load(response)


def get_schema_hash(kind, url):
    with open_url(url) as response:
        payload = response.read()
    schema = json.loads(payload)
    expected_field = "tabs" if kind == "cli" else "agents"
    if (
        not isinstance(schema, dict)
        or schema.get("$id") != url
        or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema"
        or not isinstance(schema.get("properties"), dict)
        or expected_field not in schema["properties"]
    ):
        raise ValueError(f"Unexpected OpenCode schema id or content: {url}")
    return "sha256-" + base64.b64encode(hashlib.sha256(payload).digest()).decode()


def hash_native_archives(version):
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
            # Verify the npm integrity value before trusting an archive.
            check = hashlib.sha512()
            with open_url(archive) as response:
                while chunk := response.read(1024 * 1024):
                    check.update(chunk)
            if "sha512-" + base64.b64encode(check.digest()).decode() != published:
                raise RuntimeError("npm integrity mismatch: " + package)
        hashes[system] = "sha256-" + base64.b64encode(sha.digest()).decode()
        print(system, hashes[system], flush=True)
    return hashes


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
    if version != old["version"] and args.check:
        print("Update available: " + old["version"] + " -> " + version)
        return

    hashes = (
        old["hashes"] if version == old["version"] else hash_native_archives(version)
    )
    schema_hashes = {}
    for name, url in SCHEMAS.items():
        schema_hashes[name] = get_schema_hash(name, url)
        print(f"schema {name}: {schema_hashes[name]}", flush=True)

    new = {"version": version, "hashes": hashes, "schemaHashes": schema_hashes}
    if old == new:
        print("Already current: " + version)
        return
    if args.check:
        print("Updated schema hashes are available for " + version)
        return

    with tempfile.NamedTemporaryFile(mode="w", dir=ROOT, delete=False) as f:
        f.write(json.dumps(new, indent=2) + "\n")
        temp = f.name
    os.replace(temp, target)
    print("Updated", target, "to", version)


if __name__ == "__main__":
    main()
