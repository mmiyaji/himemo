import json
import tempfile
import unittest
from argparse import Namespace
from pathlib import Path
from subprocess import CompletedProcess
from unittest.mock import patch

import ios_launch_smoke
from ios_launch_smoke import (
    choose_loopback_port,
    is_vm_service_response,
    create_simulator,
    parse_migration_statuses,
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
                        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                        "version": "27.0",
                        "isAvailable": True,
                        "supportedDeviceTypes": [
                            {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"}
                        ],
                    },
                    {
                        "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                        "version": "27.2",
                        "isAvailable": True,
                        "supportedDeviceTypes": [
                            {
                                "identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                                "name": "iPhone 18 Pro",
                            }
                        ],
                    },
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
        install_timeout_seconds=600,
        startup_timeout_seconds=1,
        driver_timeout_seconds=5,
        operation_timeout_seconds=960,
    )


class IOSLaunchSmokeTests(unittest.TestCase):
    def test_migration_status_parser_ignores_persistent_pending_but_detects_running(self):
        statuses = parse_migration_statuses(
            """Monitoring boot status.\nData migration details:
\tcom.apple.MobileAsset : duration: 1.25, status: success
\tcom.apple.PreferencesMigrator : duration: 0.000000, status: running
\tcom.apple.StocksMigrator : duration: 0.000000, status: pending

"""
        )

        self.assertEqual(statuses["com.apple.MobileAsset"], "success")
        self.assertEqual(statuses["com.apple.PreferencesMigrator"], "running")
        self.assertEqual(statuses["com.apple.StocksMigrator"], "pending")

    def test_migration_status_parser_fails_closed_on_missing_or_unknown_status(self):
        for output in (
            "Device already booted, nothing to do.",
            "Data migration details:\nnot a recognized migration row\n",
            "Data migration details:\ncom.apple.example : duration: 1, status: failed\n",
        ):
            with self.subTest(output=output), self.assertRaises(RuntimeError):
                parse_migration_statuses(output)

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
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1-1",
                    "version": "27.1.1",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                    "version": "27.0.0",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-2",
                    "version": "27.2.0",
                    "isAvailable": True,
                    "supportedDeviceTypes": [
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro"},
                        {"identifier": "com.apple.CoreSimulator.SimDeviceType.iPhone-Duo"},
                    ],
                },
                {
                    "identifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-1",
                    "version": "27.1.0",
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
                "com.apple.CoreSimulator.SimRuntime.iOS-27-1-1",
                "27.1.1",
                "com.apple.CoreSimulator.SimDeviceType.iPhone-18-Pro",
                "iPhone 18 Pro",
            ),
        )
        self.assertTrue(all("Duo" not in name for _, _, _, name in candidates))
        self.assertEqual(
            [candidate[1] for candidate in candidates],
            ["27.1.1", "27.1.0", "27.1.0", "27.0.0", "27.2.0"],
        )

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

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                commands.append((label, command))
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.PreferencesMigrator : duration: 0, status: running\n\n"
                    )
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9123),
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console) as popen,
                patch.object(ios_launch_smoke.time, "sleep"),
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
            bootstatus = next(command for label, command in commands if label == "simulator bootstatus")
            self.assertEqual(bootstatus[-1], "-bd")
            self.assertEqual(events.count("simulator bootstatus"), 1)
            self.assertNotIn("simulator bootstatus migration check", events)
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
            self.assertTrue(Path(directory, "simulator-runtimes.json").exists())

    def test_invalid_vm_service_skips_driver_but_cleans_up_and_screenshots(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            console = FakeConsoleProcess(events)

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.MobileAsset : duration: 1, status: success\n\n"
                    )
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

    def test_boot_failure_retries_next_candidate_then_runs_driver(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            ids = iter(("failed-uuid", "ready-uuid"))
            console = FakeConsoleProcess(events)

            def record_command(command, *, label, allow_failure=False, output_callback=None, **kwargs):
                events.append(label)
                if label == "simulator boot" and events.count(label) == 1:
                    return 1
                if label == "simulator bootstatus" and output_callback:
                    output_callback("Data migration details:\ncom.apple.MobileAsset : duration: 1, status: success\n\n")
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9130),
                patch.object(ios_launch_smoke, "create_simulator", side_effect=lambda *a, **k: next(ids)),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 0)
            self.assertEqual(events.count("simulator boot"), 2)
            self.assertEqual(events.count("owned simulator delete"), 2)
            self.assertIn("Flutter driver smoke", events)
            self.assertIn("ready-uuid", Path(directory, "smoke-run.log").read_text(encoding="utf-8"))

    def test_all_boot_candidates_fail_and_each_owned_simulator_is_deleted(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            ids = iter(("failed-one", "failed-two"))

            def record_command(command, *, label, allow_failure=False, **kwargs):
                events.append(label)
                return 1 if label == "simulator boot" else 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9131),
                patch.object(ios_launch_smoke, "create_simulator", side_effect=lambda *a, **k: next(ids)),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertEqual(events.count("simulator boot"), 2)
            self.assertEqual(events.count("owned simulator delete"), 2)
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("SMOKE FAILURE", transcript)
            self.assertNotIn("Flutter driver smoke", events)

    def test_unparseable_migration_status_fails_without_retrying_boot_candidate(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            def record_command(command, *, label, allow_failure=False, output_callback=None, **kwargs):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback("Data migration details:\nunrecognized migration output\n")
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9133),
                patch.object(ios_launch_smoke, "create_simulator", return_value="migration-invalid") as create,
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertEqual(events.count("simulator bootstatus"), 1)
            self.assertNotIn("simulator install", events)
            create.assert_called_once()
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("could not parse a simctl data migration status row", transcript)

    def test_failed_candidate_must_be_confirmed_deleted_before_retry(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []

            def record_command(command, *, label, allow_failure=False, **kwargs):
                events.append(label)
                if label in {"simulator boot", "owned simulator delete"}:
                    return 1
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9132),
                patch.object(ios_launch_smoke, "create_simulator", return_value="undeleted") as create,
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertEqual(events.count("simulator boot"), 1)
            create.assert_called_once()

    def test_unparseable_bootstatus_fails_before_install_and_driver(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback("Device already booted, nothing to do.\n")
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9127),
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke.subprocess, "Popen") as popen,
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertNotIn("simulator install", events)
            self.assertNotIn("Flutter driver smoke", events)
            popen.assert_not_called()
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("omitted data migration details", transcript)

    def test_running_and_pending_migrations_do_not_block_required_launch_checks(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            console = FakeConsoleProcess(events)

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.PreferencesMigrator : duration: 0, status: running\n"
                        "com.apple.StocksMigrator : duration: 0, status: pending\n\n"
                    )
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9128),
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 0)
            self.assertIn("simulator install", events)
            self.assertIn("Flutter driver smoke", events)
            self.assertEqual(events.count("simulator bootstatus"), 1)
            self.assertNotIn("simulator bootstatus migration check", events)
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("continuing while data migrations remain active", transcript)

    def test_driver_failure_returns_nonzero_and_still_collects_screenshot(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            console = FakeConsoleProcess(events)

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.PreferencesMigrator : duration: 0, status: running\n\n"
                    )
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
            self.assertIn("simulator app bundle size", events)
            self.assertIn("simulator install system logs", events)
            self.assertIn("host simulator system logs", events)

    def test_slow_simulator_install_gets_extended_timeout_and_still_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            commands = []
            console = FakeConsoleProcess(events)

            def record_command(
                command,
                *,
                label,
                timeout_seconds,
                allow_failure=False,
                output_callback=None,
                **kwargs,
            ):
                events.append(label)
                commands.append((label, timeout_seconds))
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.MobileAsset : duration: 1, status: success\n\n"
                    )
                if label == "simulator install":
                    raise RuntimeError("simulator install timed out after 600s")
                return 0

            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9126),
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke, "wait_for_vm_service", return_value=True),
                patch.object(ios_launch_smoke.subprocess, "Popen", return_value=console),
            ):
                result = ios_launch_smoke.run_smoke(smoke_args(directory))

            self.assertEqual(result, 1)
            self.assertEqual(
                next(timeout for label, timeout in commands if label == "simulator install"),
                600,
            )
            self.assertNotIn("Flutter driver smoke", events)
            self.assertIn("simulator install system logs", events)
            self.assertIn("host simulator system logs", events)
            self.assertIn("simulator screenshot", events)
            self.assertIn("simulator shutdown", events)
            self.assertIn("owned simulator delete", events)
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn(
                "SMOKE FAILURE: RuntimeError: simulator install timed out after 600s",
                transcript,
            )


if __name__ == "__main__":
    unittest.main()
