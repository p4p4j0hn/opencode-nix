#!/usr/bin/env python3
"""Verify that a bot-generated version bump matches an official OpenCode release."""
import base64
import json
import os
import re
import urllib.request

REPO = os.environ["GITHUB_REPOSITORY"]
PR = os.environ["PR_NUMBER"]
TOKEN = os.environ["GH_TOKEN"]
API = "https://api.github.com"
SYSTEM_ASSETS = {
    "x86_64-linux": "opencode-linux-x64.tar.gz",
    "aarch64-linux": "opencode-linux-arm64.tar.gz",
    "x86_64-darwin": "opencode-darwin-x64.zip",
    "aarch64-darwin": "opencode-darwin-arm64.zip",
}


def api(url):
    if url.startswith(API + "/"):
        headers["Authorization"] = "Bearer " + TOKEN
    with urllib.request.urlopen(
        urllib.request.Request(url, headers=headers), timeout=40
    ) as response:
        return json.load(response)


pr = api(f"{API}/repos/{REPO}/pulls/{PR}")
if pr["head"]["ref"] != "automation/opencode-release":
    print("Not the automated release branch; normal CI and branch protection apply.")
    raise SystemExit(0)
if pr["head"]["repo"]["full_name"] != REPO:
    raise SystemExit("Release automation branch must be local to this repository.")
if pr["user"]["login"] != "github-actions[bot]":
    raise SystemExit("Release PR author must be github-actions[bot].")
changed = []
page = 1
while True:
    chunk = api(f"{API}/repos/{REPO}/pulls/{PR}/files?per_page=100&page={page}")
    changed.extend(chunk)
    if len(chunk) < 100:
        break
    page += 1
if (
    len(changed) != 1
    or changed[0]["filename"] != "version.json"
    or changed[0]["status"] != "modified"
):
    raise SystemExit("Automated PRs must modify only version.json.")
with open("version.json", encoding="utf-8") as f:
    version = json.load(f)
if set(version) != {"version", "hashes"} or set(version["hashes"]) != set(
    SYSTEM_ASSETS
):
    raise SystemExit("Unexpected version.json schema.")
tag = "v" + version["version"]
if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
    raise SystemExit("Expected a stable semver release.")
release = api(f"{API}/repos/anomalyco/opencode/releases/tags/{tag}")
if release["draft"] or release["prerelease"] or release["tag_name"] != tag:
    raise SystemExit("Not a published stable release.")
assets = {asset["name"]: asset for asset in release["assets"]}
for system, name in SYSTEM_ASSETS.items():
    asset = assets.get(name)
    if not asset:
        raise SystemExit(f"Missing upstream binary: {name}")
    digest = asset.get("digest", "")
    if not re.fullmatch(r"sha256:[a-f0-9]{64}", digest):
        raise SystemExit(f"Upstream digest missing for {name}; require human review")
    expected = "sha256-" + base64.b64encode(bytes.fromhex(digest[7:])).decode("ascii")
    if version["hashes"][system] != expected:
        raise SystemExit(f"Hash mismatch for {system}")
print(f"Official release {tag}: four hashes verified against upstream release digests.")
