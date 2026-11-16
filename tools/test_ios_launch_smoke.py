import tempfile
import unittest
from argparse import Namespace
import json
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

import ios_launch_smoke
from ios_launch_smoke import (
    choose_loopback_port,
    is_vm_service_response,
    create_simulator,
    select_simulator_candidates,
)


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
    runtimes_file = Path(evidence_dir, "runtimes.json")
    device_types_file = Path(evidence_dir, "device-types.json")
    runtimes_file.write_text(
        json.dumps(
            {
                "runtimes": [
                    {
                        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                        "version": "27.1",
                        "isAvailable": True,
                        "supportedDeviceTypes": [
                            {
                                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                                "name": "iPhone 18 Pro",
                            }
                        ],
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    device_types_file.write_text(
        json.dumps(
            {
                "devicetypes": [
                    {
                        "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                        "name": "iPhone 18 Pro",
                        "productFamily": "iPhone",
                    }
                ]
            }
        ),
        encoding="utf-8",
    )
    return Namespace(
        device_name="himemo-ci-1234-1",
        runtimes_file=str(runtimes_file),
        device_types_file=str(device_types_file),
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
    def test_created_simulator_uses_uuid_from_final_output_line(self):
        created_uuid = "12345678-1234-1234-1234-123456789abc"
        warning_uuid = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
        with tempfile.TemporaryDirectory() as directory:
            with patch(
                "ios_launch_smoke.subprocess.run",
                return_value=CompletedProcess(
                    args=[],
                    returncode=0,
                    stdout=f"Warning mentions existing simulator {warning_uuid}\n{created_uuid}\n",
                ),
            ):
                with Path(directory, "create.log").open("w", encoding="utf-8") as log:
                    actual = create_simulator(
                        "xcrun", "owned-device", "type-id", "runtime-id", timeout_seconds=1, log=log
                    )
        self.assertEqual(actual, created_uuid)

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

    def test_simulator_selection_prefers_sdk_runtime_and_standard_iphone_18_pro(self):
        runtimes = {
            "runtimes": [
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-26-4",
                    "version": "26.4",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                    "version": "27.2",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                    "version": "27.1",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17"},
                    ],
                },
            ]
        }
        device_types = {
            "devicetypes": [
                {
                    "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo",
                    "name": "iPhone Duo",
                    "productFamily": "iPhone",
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                    "name": "iPhone 17",
                    "productFamily": "iPhone",
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                    "name": "iPhone 18 Pro",
                    "productFamily": "iPhone",
                },
            ]
        }

        candidates = select_simulator_candidates(runtimes, device_types)

        self.assertEqual(
            candidates[0],
            (
                "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                "27.1",
                "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                "iPhone 18 Pro",
            ),
        )
        self.assertTrue(all("Duo" not in name for _, _, _, name in candidates))

    def test_simulator_selection_falls_back_to_an_available_standard_iphone(self):
        candidates = select_simulator_candidates(
            {
                "runtimes": [
                    {
                        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                        "version": "27.2",
                        "isAvailable": True,
                    }
                ]
            },
            {
                "devicetypes": [
                    {
                        "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo",
                        "name": "iPhone Duo",
                        "productFamily": "iPhone",
                    },
                    {
                        "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-17",
                        "name": "iPhone 17",
                    },
                ]
            },
        )

        self.assertEqual(len(candidates), 1)
        self.assertEqual(candidates[0][3], "iPhone 17")

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
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
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
            self.assertIn("owned simulator delete", events)
            self.assertEqual(popen.call_args.args[0][4], "owned-uuid")
            delete_command = next(
                command for label, command in commands if label == "owned simulator delete"
            )
            self.assertEqual(delete_command, ["xcrun", "simctl", "delete", "owned-uuid"])
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
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
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
            self.assertIn("owned simulator delete", events)
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
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
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
            self.assertIn("owned simulator delete", events)


if __name__ == "__main__":
    unittest.main()
