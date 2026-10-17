#!/usr/bin/env python3
"""Optionally reclaim a backend port from a matching, same-user OpenCode server.

Fail closed if an unknown process owns the port. Linux only: uses /proc and lsof.
"""
import argparse
import os
from pathlib import Path
import signal
import subprocess
import sys
import time


def listening_pids(port):
    result = subprocess.run(
        ["lsof", "-nP", "-t", "-sTCP:LISTEN", f"-iTCP:{port}"],
        capture_output=True, text=True, check=False,
    )
    if result.returncode not in (0, 1):
        raise RuntimeError(f"lsof failed (exit {result.returncode}): {result.stderr.strip()}")
    return {int(s) for s in result.stdout.splitlines() if s.isdigit()}


def opencode_server(pid, port):
    """Require a same-user OpenCode 'serve' command explicitly naming this port."""
    proc = Path("/proc") / str(pid)
    try:
        if proc.stat().st_uid != os.geteuid():
            return False
        argv = (proc / "cmdline").read_bytes().rstrip(b"\0").decode(
            "utf-8", errors="replace"
        ).split("\0")
    except (FileNotFoundError, ProcessLookupError, PermissionError):
        return False
    if not argv or "opencode" not in Path(argv[0]).name.lower():
        return False
    if "serve" not in argv:
        return False
    for i, arg in enumerate(argv):
        if arg == f"--port={port}":
            return True
        if arg == "--port" and i + 1 < len(argv) and argv[i + 1] == str(port):
            return True
    return False


def takeover(port, grace_seconds):
    owners = listening_pids(port)
    if not owners:
        return
    if any(not opencode_server(pid, port) for pid in owners):
        raise RuntimeError(
            f"port {port} has an unrecognized listener; refusing to terminate it: "
            f"{sorted(owners)}"
        )
    for pid in owners:
        print(f"Reclaiming OpenCode port {port} from PID {pid}", flush=True)
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    until = time.monotonic() + grace_seconds
    while time.monotonic() < until:
        if not listening_pids(port):
            return
        time.sleep(0.2)

    remaining = listening_pids(port)
    if any(not opencode_server(pid, port) for pid in remaining):
        raise RuntimeError(f"port {port} was reacquired by an unknown process")
    for pid in remaining:
        print(f"OpenCode PID {pid} ignored SIGTERM; sending SIGKILL", flush=True)
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    for _ in range(20):
        if not listening_pids(port):
            return
        time.sleep(0.1)
    raise RuntimeError(f"port {port} remains occupied after takeover")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--port", type=int, required=True)
    parser.add_argument("--grace-seconds", type=float, default=5)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535 or args.grace_seconds < 0:
        parser.error("invalid port or grace period")
    try:
        takeover(args.port, args.grace_seconds)
    except RuntimeError as exc:
        print(f"OpenCode backend takeover: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
