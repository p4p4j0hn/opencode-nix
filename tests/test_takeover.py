#!/usr/bin/env python3
"""Unit tests: no real processes are signalled."""
import importlib.util
from pathlib import Path
import signal
import unittest
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("takeover_port", Path(__file__).resolve().parents[1] / "scripts" / "takeover-port.py")
takeover = importlib.util.module_from_spec(spec)
spec.loader.exec_module(takeover)


class TakeoverTests(unittest.TestCase):
    def test_empty_port_is_noop(self):
        with patch.object(takeover, "listening_pids", return_value=set()), patch.object(takeover.os, "kill") as kill:
            takeover.takeover(4096, 0)
            kill.assert_not_called()

    def test_unknown_process_fails_closed(self):
        with patch.object(takeover, "listening_pids", return_value={123}), patch.object(takeover, "opencode_server", return_value=False), patch.object(takeover.os, "kill") as kill:
            with self.assertRaisesRegex(RuntimeError, "unrecognized listener"):
                takeover.takeover(4096, 0)
            kill.assert_not_called()

    def test_known_server_terminated(self):
        with patch.object(takeover, "listening_pids", side_effect=[{123}, set()]), patch.object(takeover, "opencode_server", return_value=True), patch.object(takeover.os, "kill") as kill:
            takeover.takeover(4096, 1)
            kill.assert_called_once_with(123, signal.SIGTERM)

    def test_known_server_escalates_after_timeout(self):
        with patch.object(takeover, "listening_pids", side_effect=[{123}, {123}, set()]), patch.object(takeover, "opencode_server", return_value=True), patch.object(takeover.os, "kill") as kill:
            takeover.takeover(4096, 0)
            self.assertEqual(kill.call_args_list[0].args, (123, signal.SIGTERM))
            self.assertEqual(kill.call_args_list[1].args, (123, signal.SIGKILL))

    def test_unknown_process_after_grace_fails_closed(self):
        with patch.object(takeover, "listening_pids", side_effect=[{123}, {456}]), patch.object(takeover, "opencode_server", side_effect=[True, False]), patch.object(takeover.os, "kill") as kill:
            with self.assertRaisesRegex(RuntimeError, "unknown process"):
                takeover.takeover(4096, 0)
            kill.assert_called_once_with(123, signal.SIGTERM)


if __name__ == "__main__":
    unittest.main()
