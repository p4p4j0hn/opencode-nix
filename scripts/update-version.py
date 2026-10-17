#!/usr/bin/env python3
"""Fetch every official CLI release archive and atomically update version.json."""
import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import tempfile
from urllib.request import Request, urlopen

ROOT = Path(__file__).resolve().parents[1]
ASSETS = {
    "x86_64-linux": "opencode-linux-x64.tar.gz",
    "aarch64-linux": "opencode-linux-arm64.tar.gz",
    "x86_64-darwin": "opencode-darwin-x64.zip",
    "aarch64-darwin": "opencode-darwin-arm64.zip",
}
API = "https://api.github.com/repos/anomalyco/opencode/releases/latest"

def open_url(url):
    headers = {"User-Agent": "opencode-nix-updater", "Accept": "application/vnd.github+json"}
    token = os.environ.get("GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if token and url.startswith("https://api.github.com/"):
        headers["Authorization"] = "Bearer " + token
    return urlopen(Request(url, headers=headers), timeout=60)

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    with open_url(API) as response:
        release = json.load(response)
    if release.get("prerelease") or release.get("draft"):
        raise RuntimeError("latest release is not stable")
    tag = release["tag_name"]
    if not tag.startswith("v"):
        raise RuntimeError("unexpected upstream tag: " + tag)
    version = tag[1:]
    target = ROOT / "version.json"
    old = json.loads(target.read_text())
    if version == old["version"]:
        print("Already current: " + version)
        return
    if args.check:
        print("Update available: " + old["version"] + " -> " + version)
        return
    available = {a["name"]: a for a in release["assets"]}
    if any(name not in available for name in ASSETS.values()):
        raise RuntimeError("release missing one or more platform assets")
    hashes = {}
    for system, name in ASSETS.items():
        asset = available[name]
        sha = hashlib.sha256()
        with open_url(asset["browser_download_url"]) as response:
            while chunk := response.read(1024 * 1024):
                sha.update(chunk)
        published = asset.get("digest")
        if published and published != "sha256:" + sha.hexdigest():
            raise RuntimeError("published digest mismatch: " + name)
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
