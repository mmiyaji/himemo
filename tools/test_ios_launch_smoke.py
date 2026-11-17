import io
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
    wait_for_migration_quiescence,
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

    def test_migration_wait_polls_running_rows_until_terminal_state(self):
        outputs = iter(
            [
                "Data migration details:\ncom.apple.PreferencesMigrator : duration: 2, status: success\n",
            ]
        )
        calls = []

        def record_poll(command, *, output_callback, **kwargs):
            calls.append(command)
            output_callback(next(outputs))
            return 0

        with (
            patch.object(ios_launch_smoke, "run_command", side_effect=record_poll),
            patch.object(ios_launch_smoke.time, "sleep"),
        ):
            wait_for_migration_quiescence(
                "xcrun",
                "device-uuid",
                "Data migration details:\ncom.apple.PreferencesMigrator : duration: 0, status: running\n",
                deadline=ios_launch_smoke.time.monotonic() + 60,
                log=io.StringIO(),
            )

        self.assertEqual(len(calls), 1)
        self.assertEqual(calls[0], ["xcrun", "simctl", "bootstatus", "device-uuid", "-b", "-d"])

    def test_migration_poll_timeout_is_retried_until_success(self):
        calls = []

        def record_poll(command, *, output_callback, **kwargs):
            calls.append(command)
            if len(calls) == 1:
                return 124
            output_callback(
                "Data migration details:\n"
                "com.apple.PreferencesMigrator : duration: 2, status: success\n"
            )
            return 0

        with (
            patch.object(ios_launch_smoke, "run_command", side_effect=record_poll),
            patch.object(ios_launch_smoke.time, "sleep"),
        ):
            wait_for_migration_quiescence(
                "xcrun",
                "device-uuid",
                "Data migration details:\ncom.apple.PreferencesMigrator : duration: 0, status: running\n",
                deadline=ios_launch_smoke.time.monotonic() + 60,
                log=io.StringIO(),
            )

        self.assertEqual(len(calls), 2)
        self.assertTrue(all(call == calls[0] for call in calls))

    def test_migration_wait_fails_closed_when_running_past_deadline(self):
        with patch.object(ios_launch_smoke, "run_command") as run_command:
            with self.assertRaisesRegex(RuntimeError, "remained running"):
                wait_for_migration_quiescence(
                    "xcrun",
                    "device-uuid",
                    "Data migration details:\ncom.apple.PreferencesMigrator : duration: 0, status: running\n",
                    deadline=ios_launch_smoke.time.monotonic() - 1,
                    log=io.StringIO(),
                )

        run_command.assert_not_called()

    def test_migration_poll_timeout_cannot_extend_total_deadline(self):
        clock = [100.0]
        calls = []

        def timed_out_poll(*args, **kwargs):
            calls.append(args[0])
            clock[0] = 111.0
            return 124

        with (
            patch.object(ios_launch_smoke, "run_command", side_effect=timed_out_poll),
            patch.object(ios_launch_smoke.time, "monotonic", side_effect=lambda: clock[0]),
            patch.object(ios_launch_smoke.time, "sleep"),
        ):
            with self.assertRaisesRegex(RuntimeError, "remained running"):
                wait_for_migration_quiescence(
                    "xcrun",
                    "device-uuid",
                    "Data migration details:\ncom.apple.PreferencesMigrator : duration: 0, status: running\n",
                    deadline=110.0,
                    log=io.StringIO(),
                )

        self.assertEqual(len(calls), 1)

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
            ["27.1.1", "27.1.0", "27.1.0", "27.2.0", "27.0.0"],
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
                elif label == "simulator bootstatus migration check" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.PreferencesMigrator : duration: 2, status: success\n\n"
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
            migration_poll = next(
                command
                for label, command in commands
                if label == "simulator bootstatus migration check"
            )
            self.assertEqual(migration_poll[-2:], ["-b", "-d"])
            self.assertLess(
                events.index("simulator bootstatus migration check"),
                events.index("simulator install"),
            )
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

    def test_migration_deadline_prevents_install_and_driver(self):
        with tempfile.TemporaryDirectory() as directory:
            events = []
            clock = [100.0]

            def record_command(
                command, *, label, allow_failure=False, output_callback=None, **kwargs
            ):
                events.append(label)
                if label == "simulator bootstatus" and output_callback:
                    output_callback(
                        "Data migration details:\n"
                        "com.apple.PreferencesMigrator : duration: 0, status: running\n"
                    )
                    clock[0] = 130.0
                return 0

            args = smoke_args(directory)
            args.operation_timeout_seconds = 30
            with (
                patch.object(ios_launch_smoke, "choose_loopback_port", return_value=9128),
                patch.object(ios_launch_smoke, "create_simulator", return_value="owned-uuid"),
                patch.object(ios_launch_smoke, "run_command", side_effect=record_command),
                patch.object(ios_launch_smoke.time, "monotonic", side_effect=lambda: clock[0]),
                patch.object(ios_launch_smoke.subprocess, "Popen") as popen,
            ):
                result = ios_launch_smoke.run_smoke(args)

            self.assertEqual(result, 1)
            self.assertNotIn("simulator install", events)
            self.assertNotIn("Flutter driver smoke", events)
            popen.assert_not_called()
            transcript = Path(directory, "smoke-run.log").read_text(encoding="utf-8")
            self.assertIn("simulator data migrations remained running", transcript)

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
                        "com.apple.MobileAsset : duration: 1, status: success\n\n"
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
