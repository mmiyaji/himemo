import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from unittest.mock import patch

import ios_launch_smoke
from ios_launch_smoke import choose_loopback_port, is_vm_service_response


class FakeConsoleProcess:
    def __init__(self, events):
        self.events = events
        self.returncode = None

    def poll(self):
        return self.returncode

    def terminate(self):
        self.events.append("console-terminate")
        self.returncode = 0

    def wait(self, timeout=None):
        return self.returncode


def smoke_args(evidence_dir):
    return Namespace(
        device="simulator-id",
        bundle_id="org.example.app",
        app_path="Runner.app",
        target="test_driver/app.dart",
        driver="test_driver/app_test.dart",
        evidence_dir=evidence_dir,
        xcrun="xcrun",
        flutter="flutter",
        boot_timeout_seconds=10,
        startup_timeout_seconds=1,
        driver_timeout_seconds=5,
    )


class IOSLaunchSmokeTests(unittest.TestCase):
    def test_choose_loopback_port_returns_valid_port(self):
        port = choose_loopback_port()

        self.assertGreater(port, 0)
        self.assertLessEqual(port, 65535)

    def test_accepts_json_rpc_vm_service_response(self):
        self.assertTrue(
            is_vm_service_response(
                {"jsonrpc": "2.0", "result": {"type": "VM", "isolates": []}}
            )
        )

    def test_accepts_raw_vm_service_response(self):
        self.assertTrue(is_vm_service_response({"type": "VM", "isolates": []}))

    def test_rejects_non_vm_json_and_non_object(self):
        for payload in (
            {"jsonrpc": "2.0", "result": {"type": "Isolate"}},
            {"type": "not-a-vm"},
            {"jsonrpc": "2.0", "error": {"code": -32601}},
            None,
            "{}",
        ):
            with self.subTest(payload=payload):
                self.assertFalse(is_vm_service_response(payload))

    def test_success_uses_direct_loopback_service_and_collects_evidence_before_cleanup(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            commands = []
            console = FakeConsoleProcess(events)

            def record_command(command, *, label, allow_failure=False, **kwargs):
                events.append(label)
                commands.append((label, command))
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9123),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console) as popen,
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 0)
            launch = popen.call_args.args[0]
            self.assertIn("--console-pty", launch)
            self.assertIn("--vm-service-port=9123", launch)
            self.assertIn("--vm-service-host=127.0.0.1", launch)
            self.assertNotIn("--start-paused", launch)
            driver_command = next(command for label, command in commands if label == "Flutter driver smoke")
            self.assertIn("--no-dds", driver_command)
            self.assertIn("--use-existing-app=http://127.0.0.1:9123/", driver_command)
            self.assertIn("simulator screenshot", events)
            self.assertLess(events.index("simulator screenshot"), events.index("console-terminate"))
            self.assertIn("simulator app terminate", events)
            self.assertIn("simulator shutdown", events)
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("Smoke exit code: 0", transcript)

    def test_invalid_vm_service_skips_driver_but_cleans_up_and_screenshots(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            console = FakeConsoleProcess(events)

            def record_command(command, *, label, allow_failure=False, **kwargs):
                events.append(label)
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9124),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=False),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertNotIn("Flutter driver smoke", events)
            self.assertIn("simulator screenshot", events)
            self.assertLess(events.index("simulator screenshot"), events.index("console-terminate"))
            self.assertIn("simulator app terminate", events)
            self.assertIn("simulator shutdown", events)
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("did not expose a valid Dart VM service", transcript)

    def test_driver_failure_returns_nonzero_and_still_collects_screenshot(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            console = FakeConsoleProcess(events)

            def record_command(command, *, label, allow_failure=False, **kwargs):
                events.append(label)
                return 7 if label == "Flutter driver smoke" else 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9125),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertIn("Flutter driver smoke", events)
            self.assertIn("simulator screenshot", events)
            self.assertIn("simulator app terminate", events)
            self.assertIn("simulator shutdown", events)


if __name__ == "__main__":
    unittest.main()
