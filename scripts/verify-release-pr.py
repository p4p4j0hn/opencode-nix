#!/usr/bin/env python3
"""Verify automated OpenCode V2 npm binary and JSON schema release updates."""

import base64
import hashlib
import json
import os
import re
from pathlib import Path
from urllib.parse import quote
from urllib.request import Request, urlopen

API = "https://api.github.com"
REGISTRY = "https://registry.npmjs.org"
PACKAGES = {
    "x86_64-linux": "@opencode/cli-linux-x64",
    "aarch64-linux": "@opencode/cli-linux-arm64",
    "x86_64-darwin": "@opencode/cli-darwin-x64",
    "aarch64-darwin": "@opencode/cli-darwin-arm64",
}
SCHEMAS = {
    "cli": "https://opencode.ai/v2/cli.json",
    "config": "https://opencode.ai/config.json",
}
BOT_AUTHORS = {"github-actions[bot]", "opencode-nix-updater[bot]"}
# These are permitted only for a manually reviewed release-policy maintenance PR.
POLICY_FILES = {
    "scripts/verify-release-pr.py",
    ".github/workflows/release-policy.yml",
    "tests/test_verify_release_pr.py",
}


def get_bytes(url, token=None):
    headers = {"User-Agent": "opencode-nix-release-policy"}
    if url.startswith(API + "/") and token:
        headers["Authorization"] = "Bearer " + token
        headers["Accept"] = "application/vnd.github+json"
    with urlopen(Request(url, headers=headers), timeout=120) as response:
        return response.read()


def get_json(url, token=None):
    return json.loads(get_bytes(url, token))


def tarball_url(name, version):
    package = name.split("/")[-1]
    return f"{REGISTRY}/{name}/-/{package}-{version}.tgz"


def download_hashes(url):
    sha256 = hashlib.sha256()
    sha512 = hashlib.sha512()
    with urlopen(
        Request(url, headers={"User-Agent": "opencode-nix-release-policy"}),
        timeout=120,
    ) as response:
        while chunk := response.read(1024 * 1024):
            sha256.update(chunk)
            sha512.update(chunk)
    return (
        "sha256-" + base64.b64encode(sha256.digest()).decode(),
        "sha512-" + base64.b64encode(sha512.digest()).decode(),
    )


def is_sha256(value):
    if not isinstance(value, str) or not value.startswith("sha256-"):
        return False
    try:
        return len(base64.b64decode(value[7:], validate=True)) == 32
    except (ValueError, base64.binascii.Error):
        return False


def verify_release(
    pr, changed, pins, repo, registry_metadata, archive_hashes, schema_bytes
):
    if pr["head"]["ref"] != "automation/opencode-release":
        return "ignored"
    if pr["head"]["repo"]["full_name"] != repo:
        raise ValueError("Release automation branch must belong to this repository.")
    if pr["user"]["login"] not in BOT_AUTHORS:
        raise ValueError("Release PR author must be the approved updater bot.")

    changed_files = {item["filename"]: item["status"] for item in changed}
    if len(changed_files) != len(changed):
        raise ValueError("Unexpected duplicate changed files.")
    if changed_files.get("version.json") != "modified":
        raise ValueError("Automated release PR must modify version.json.")
    if not set(changed_files).issubset({"version.json"} | POLICY_FILES):
        raise ValueError("Unexpected files in automated release PR.")
    if any(
        status not in {"added", "modified"}
        for name, status in changed_files.items()
        if name in POLICY_FILES
    ):
        raise ValueError("Unexpected policy file change status.")
    manual_review = len(changed_files) > 1

    if set(pins) != {"version", "hashes", "schemaHashes"}:
        raise ValueError("Unexpected version.json structure.")
    version = pins["version"]
    if not isinstance(version, str) or not re.fullmatch(r"2\.[0-9]+\.[0-9]+", version):
        raise ValueError("Expected stable OpenCode V2 semver.")
    if not isinstance(pins["hashes"], dict) or set(pins["hashes"]) != set(PACKAGES):
        raise ValueError("Unexpected binary hash set.")
    if not isinstance(pins["schemaHashes"], dict) or set(pins["schemaHashes"]) != set(
        SCHEMAS
    ):
        raise ValueError("Unexpected JSON schema hash set.")
    if not all(is_sha256(value) for value in pins["hashes"].values()):
        raise ValueError("Invalid SHA-256 binary hash.")
    if not all(is_sha256(value) for value in pins["schemaHashes"].values()):
        raise ValueError("Invalid SHA-256 JSON schema hash.")

    for system, package in PACKAGES.items():
        metadata = registry_metadata(package, version)
        dist = metadata.get("dist", {})
        expected_tarball = tarball_url(package, version)
        if (
            metadata.get("name") != package
            or metadata.get("version") != version
            or dist.get("tarball") != expected_tarball
        ):
            raise ValueError(f"Unexpected npm package metadata for {system}.")
        integrity = dist.get("integrity")
        if not isinstance(integrity, str) or not re.fullmatch(
            r"sha512-[A-Za-z0-9+/]{86}==", integrity
        ):
            raise ValueError(f"Missing or invalid npm integrity for {system}.")
        actual_sha256, actual_sha512 = archive_hashes(expected_tarball)
        if actual_sha512 != integrity:
            raise ValueError(f"npm integrity mismatch for {system}.")
        if actual_sha256 != pins["hashes"][system]:
            raise ValueError(f"SHA-256 mismatch for {system}.")
        print(f"{system}: npm SHA-512 integrity and SHA-256 pin verified.")

    for name, url in SCHEMAS.items():
        body = schema_bytes(url)
        schema = json.loads(body)
        expected_field = "tabs" if name == "cli" else "agents"
        if (
            not isinstance(schema, dict)
            or schema.get("$id") != url
            or schema.get("$schema") != "https://json-schema.org/draft/2020-12/schema"
            or not isinstance(schema.get("properties"), dict)
            or expected_field not in schema["properties"]
        ):
            raise ValueError(f"Unexpected {name} schema content.")
        actual = "sha256-" + base64.b64encode(hashlib.sha256(body).digest()).decode()
        if actual != pins["schemaHashes"][name]:
            raise ValueError(f"{name} schema hash mismatch.")
        print(f"{name}: upstream schema SHA-256 verified.")

    if manual_review:
        print("Release-policy maintenance files changed: manual review required.")
        return "manual-review-required"
    return "verified"


def main():
    repo = os.environ["GITHUB_REPOSITORY"]
    pr_number = os.environ["PR_NUMBER"]
    token = os.environ["GH_TOKEN"]
    pull_request = get_json(f"{API}/repos/{repo}/pulls/{pr_number}", token)
    if pull_request["head"]["ref"] != "automation/opencode-release":
        print("Not an automated release PR; normal CI applies.")
        return
    changed = []
    page = 1
    while True:
        batch = get_json(
            f"{API}/repos/{repo}/pulls/{pr_number}/files?per_page=100&page={page}",
            token,
        )
        changed.extend(batch)
        if len(batch) < 100:
            break
        page += 1
    pins = json.loads(Path("version.json").read_text(encoding="utf-8"))
    result = verify_release(
        pull_request,
        changed,
        pins,
        repo,
        lambda name, version: get_json(f"{REGISTRY}/{quote(name, safe='')}/{version}"),
        download_hashes,
        get_bytes,
    )
    if result == "verified":
        print("Automated release metadata verified. Eligible for auto-merge.")
    else:
        print("Release metadata verified; policy changes require manual review.")


if __name__ == "__main__":
    try:
        main()
    except ValueError as exc:
        raise SystemExit(str(exc)) from exc
