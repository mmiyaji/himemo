#!/usr/bin/env python3
"""Launch a prebuilt iOS simulator app and run its Flutter driver smoke test."""

from __future__ import annotations

import argparse
import json
import re
import shlex
import shutil
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Callable, IO, Sequence


def choose_loopback_port() -> int:
    """Choose an unused ephemeral TCP port on the loopback interface."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


def _runtime_sort_key(runtime: dict[str, object]) -> tuple[object, ...]:
    version_text = str(runtime.get("version", ""))
    parts = tuple(int(part) for part in re.findall(r"\d+", version_text))
    major_minor = parts[:2]
    priority = {(27, 1): 0, (27, 0): 1, (27, 2): 2}.get(major_minor, 3)
    return (priority, tuple(-part for part in parts), version_text)


def _device_type_sort_key(device_type: dict[str, object]) -> tuple[object, ...]:
    name = str(device_type.get("name", ""))
    if name == "iPhone 18 Pro":
        return (0, 0, 0, name)
    match = re.match(r"iPhone\s+(\d+)(?:\s+(.*))?$", name)
    generation = int(match.group(1)) if match else 0
    variant = (match.group(2) or "") if match else ""
    variant_rank = 0 if variant == "Pro" else 1 if not variant else 2
    return (1, -generation, variant_rank, name)


def select_simulator_candidates(
    runtimes_payload: object,
    device_types_payload: object,
) -> list[tuple[str, str, str, str]]:
    """Return supported iOS runtime/device-type pairs from simctl metadata."""
    if not isinstance(runtimes_payload, dict) or not isinstance(device_types_payload, dict):
        raise ValueError("simctl runtime and device-type metadata must be JSON objects")
    runtimes = runtimes_payload.get("runtimes")
    device_types = device_types_payload.get("devicetypes", device_types_payload.get("deviceTypes"))
    if not isinstance(runtimes, list) or not isinstance(device_types, list):
        raise ValueError("simctl metadata is missing runtimes or devicetypes")

    available_runtimes = [
        runtime
        for runtime in runtimes
        if isinstance(runtime, dict)
        and runtime.get("isAvailable", True) is True
        and str(runtime.get("identifier", "")).startswith(
            "com.apple.CoreSimulator.SimRuntime.iOS-"
        )
        and str(runtime.get("version", "")).startswith("27.")
    ]
    standard_iphones = [
        device_type
        for device_type in device_types
        if isinstance(device_type, dict)
        and device_type.get("isAvailable", True) is True
        and str(device_type.get("name", "")).startswith("iPhone")
        and "duo" not in str(device_type.get("name", "")).casefold()
        and isinstance(device_type.get("identifier"), str)
        and (
            device_type.get("productFamily") == "iPhone"
            or (
                device_type.get("productFamily") is None
                and str(device_type.get("identifier", "")).startswith(
                    "com.apple.CoreSimulator.SimDeviceType.iPhone-"
                )
            )
        )
    ]
    available_runtimes.sort(key=_runtime_sort_key)
    standard_iphones.sort(key=_device_type_sort_key)

    candidates: list[tuple[str, str, str, str]] = []
    for runtime in available_runtimes:
        runtime_id = runtime["identifier"]
        runtime_version = str(runtime.get("version", "unknown"))
        supported_types = runtime.get("supportedDeviceTypes")
        supported_ids = {
            item.get("identifier")
            for item in supported_types
            if isinstance(item, dict) and isinstance(item.get("identifier"), str)
        } if isinstance(supported_types, list) else None
        for device_type in standard_iphones:
            type_id = device_type["identifier"]
            if supported_ids is not None and type_id not in supported_ids:
                continue
            candidates.append(
                (
                    str(runtime_id),
                    runtime_version,
                    str(type_id),
                    str(device_type.get("name", "")),
                )
            )
    if not candidates:
        raise ValueError("simctl reports no available iOS runtime with a standard iPhone type")
    return candidates


def create_simulator(
    xcrun: str,
    name: str,
    device_type_id: str,
    runtime_id: str,
    *,
    timeout_seconds: float,
    log: IO[str],
) -> str | None:
    command = [xcrun, "simctl", "create", name, device_type_id, runtime_id]
    log.write(f"\n$ {shlex.join(command)}\n")
    log.flush()
    try:
        completed = subprocess.run(
            command,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        log.write(f"simulator create timed out after {timeout_seconds:g}s\n")
        log.flush()
        raise RuntimeError(f"simulator create timed out after {timeout_seconds:g}s") from error
    except OSError as error:
        log.write(f"simulator create could not start: {error}\n")
        log.flush()
        raise RuntimeError("simulator create could not start") from error

    output = completed.stdout or ""
    log.write(output)
    log.write(f"simulator create exit code: {completed.returncode}\n")
    log.flush()
    if completed.returncode != 0:
        return None
    created_id = output.strip().splitlines()[-1].strip() if output.strip() else ""
    if re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", created_id) is None:
        raise RuntimeError("simctl create succeeded without returning a simulator UUID")
    return created_id


def is_vm_service_response(payload: object) -> bool:
    """Return true only for a Dart VM service getVM response."""
    if not isinstance(payload, dict):
        return False
    result = payload.get("result", payload)
    return isinstance(result, dict) and result.get("type") == "VM"


def probe_vm_service(port: int, timeout_seconds: float = 2.0) -> bool:
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}/getVM",
        headers={"Accept": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:
            if response.status != 200:
                return False
            payload = response.read(1024 * 1024 + 1)
            if len(payload) > 1024 * 1024:
                return False
            return is_vm_service_response(json.loads(payload))
    except (OSError, TimeoutError, urllib.error.URLError, json.JSONDecodeError):
        return False


def run_command(
    command: Sequence[str],
    *,
    timeout_seconds: float,
    log: IO[str],
    label: str,
    allow_failure: bool = False,
    max_output_chars: int | None = None,
    output_callback: Callable[[str], None] | None = None,
) -> int:
    log.write(f"\n$ {shlex.join(list(command))}\n")
    log.flush()
    try:
        completed = subprocess.run(
            list(command),
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
            timeout=timeout_seconds,
            check=False,
        )
    except subprocess.TimeoutExpired as error:
        output = error.stdout
        if isinstance(output, bytes):
            output = output.decode(errors="replace")
        if output:
            log.write(_limit_output(output, max_output_chars))
        log.write(f"\n{label} timed out after {timeout_seconds:g}s\n")
        log.flush()
        if not allow_failure:
            raise RuntimeError(f"{label} timed out after {timeout_seconds:g}s") from error
        return 124
    except OSError as error:
        log.write(f"\n{label} could not start: {error}\n")
        log.flush()
        if not allow_failure:
            raise RuntimeError(f"{label} could not start") from error
        return 127

    if completed.stdout:
        log.write(_limit_output(completed.stdout, max_output_chars))
        if output_callback is not None:
            output_callback(completed.stdout)
    log.write(f"\n{label} exit code: {completed.returncode}\n")
    log.flush()
    if completed.returncode and not allow_failure:
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}")
    return completed.returncode


def _limit_output(output: str, max_chars: int | None) -> str:
    if max_chars is None or len(output) <= max_chars:
        return output
    return output[:max_chars] + f"\n[output truncated at {max_chars} characters]\n"


def _bounded_timeout(limit_seconds: float, deadline: float, label: str) -> float:
    remaining = deadline - time.monotonic()
    if remaining <= 0:
        raise RuntimeError(f"iOS simulator smoke time budget expired before {label}.")
    return min(float(limit_seconds), remaining)


def recover_owned_simulator_delete(
    xcrun: str, device_id: str, *, enabled: bool, log: IO[str]
) -> bool:
    """Restart the current user's CoreSimulatorService once, then retry one owned UUID."""
    if not enabled:
        return False
    uid = subprocess.run(["id", "-u"], capture_output=True, text=True, check=False)
    if uid.returncode != 0 or not uid.stdout.strip().isdigit():
        log.write("Could not resolve current user ID; CoreSimulatorService recovery skipped.\n")
        log.flush()
        return False
    service = f"gui/{uid.stdout.strip()}/com.apple.CoreSimulator.CoreSimulatorService"
    result = run_command(
        ["launchctl", "kickstart", "-k", service], timeout_seconds=30,
        log=log, label="CoreSimulatorService recovery", allow_failure=True,
    )
    if result != 0:
        return False
    return run_command(
        [xcrun, "simctl", "delete", device_id], timeout_seconds=30,
        log=log, label="owned simulator delete after service recovery", allow_failure=True,
    ) == 0


def parse_migration_statuses(output: str) -> dict[str, str]:
    """Parse simctl bootstatus migration rows, rejecting unknown output formats."""
    lines = output.splitlines()
    try:
        marker = next(
            i for i, line in enumerate(lines) if line.strip() == "Data migration details:"
        )
    except StopIteration as error:
        raise RuntimeError("simctl bootstatus output omitted data migration details") from error

    statuses: dict[str, str] = {}
    row_pattern = re.compile(
        r"^\s*(\S+)\s*:\s*duration:\s*[^,]+,\s*status:\s*([a-zA-Z_-]+)\s*$"
    )
    for line in lines[marker + 1 :]:
        if not line.strip():
            break
        match = row_pattern.fullmatch(line)
        if match is None:
            raise RuntimeError("could not parse a simctl data migration status row")
        name, status = match.groups()
        status = status.casefold()
        if status not in {"success", "pending", "running"}:
            raise RuntimeError(
                f"simctl reports unsuccessful data migration state: {name}={status}"
            )
        statuses[name] = status
    if not statuses:
        raise RuntimeError("simctl bootstatus reported no parseable data migration statuses")
    return statuses


def collect_failure_diagnostics(
    xcrun: str,
    device_id: str,
    app_path: str,
    log: IO[str],
) -> None:
    commands = (
        (["du", "-sh", app_path], 10, "simulator app bundle size"),
        ([xcrun, "simctl", "spawn", device_id, "log", "show", "--last", "5m", "--style", "compact", "--predicate", 'process == "installd" OR process == "SpringBoard"'], 20, "simulator install system logs"),
        (["/usr/bin/log", "show", "--last", "5m", "--style", "compact", "--predicate", 'process == "CoreSimulatorService" OR process == "Simulator"'], 20, "host simulator system logs"),
    )
    for command, timeout_seconds, label in commands:
        run_command(command, timeout_seconds=timeout_seconds, log=log, label=label, allow_failure=True, max_output_chars=100_000)


def wait_for_vm_service(
    port: int,
    timeout_seconds: float,
    log: IO[str],
    launch_process: subprocess.Popen[bytes] | None = None,
) -> bool:
    deadline = time.monotonic() + timeout_seconds
    attempts = 0
    while time.monotonic() < deadline:
        attempts += 1
        if launch_process is not None:
            launch_exit_code = launch_process.poll()
            if launch_exit_code not in (None, 0):
                log.write(
                    "simctl launch --console-pty exited before VM service startup "
                    f"with {launch_exit_code}.\n"
                )
                log.flush()
                return False
        if probe_vm_service(port):
            log.write(f"VM service getVM probe succeeded on loopback port {port}.\n")
            log.flush()
            return True
        time.sleep(min(1.0, max(0.0, deadline - time.monotonic())))
    log.write(
        f"VM service getVM probe did not succeed within {timeout_seconds:g}s "
        f"({attempts} attempts; port {port}).\n"
    )
    log.flush()
    return False


def terminate_process(process: subprocess.Popen[bytes] | None, log: IO[str]) -> None:
    if process is None or process.poll() is not None:
        return
    try:
        process.terminate()
    except OSError as error:
        log.write(f"Warning: could not stop console capture: {error}\n")
        log.flush()
        return
    try:
        process.wait(timeout=5)
    except subprocess.TimeoutExpired:
        process.kill()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            log.write("Warning: console capture process did not exit after kill.\n")
            log.flush()


def run_smoke(args: argparse.Namespace) -> int:
    evidence = Path(args.evidence_dir)
    evidence.mkdir(parents=True, exist_ok=True)
    transcript_path = evidence / "smoke-run.log"
    console_path = evidence / "simulator-console.log"
    screenshot_path = evidence / "simulator-final.png"
    console_process: subprocess.Popen[bytes] | None = None
    exit_code = 1
    xcrun = args.xcrun
    # The CI step reserves time beyond this deadline for diagnostics and cleanup.
    operation_deadline = time.monotonic() + args.operation_timeout_seconds
    created_device_udid: str | None = None
    device_id: str | None = None
    service_recovery_attempted = False
    device_name = args.device_name

    with transcript_path.open("w", encoding="utf-8") as log:
        log.write(f"Requested owned simulator name: {device_name}\nBundle: {args.bundle_id}\n")
        shutil.copyfile(args.runtimes_file, evidence / "simulator-runtimes.json")
        shutil.copyfile(args.device_types_file, evidence / "simulator-device-types.json")
        port = choose_loopback_port()
        log.write(f"Chosen VM service loopback port: {port}\n")
        log.flush()
        try:
            runtimes = json.loads(Path(args.runtimes_file).read_text(encoding="utf-8"))
            device_types = json.loads(Path(args.device_types_file).read_text(encoding="utf-8"))
            candidates = select_simulator_candidates(runtimes, device_types)
            log.write(f"Available supported simulator candidates: {len(candidates)}\n")
            log.flush()
            device_name = f"{device_name}-01"
            # Reserve enough of the common operation deadline for the driver and
            # startup check. Divide the remaining boot allowance across
            # at most two different candidates.
            candidates = candidates[:2]
            for index, (runtime_id, runtime_version, type_id, type_name) in enumerate(candidates):
                created_device_udid = None
                device_id = None
                remaining_attempts = len(candidates) - index
                prep_budget = max(
                    1.0,
                    (operation_deadline - time.monotonic()
                     - args.driver_timeout_seconds - args.startup_timeout_seconds - 60)
                    / remaining_attempts,
                )
                attempt_deadline = min(
                    operation_deadline - args.driver_timeout_seconds - args.startup_timeout_seconds - 60,
                    time.monotonic() + prep_budget,
                )
                print(
                    f"Creating owned {type_name} simulator on iOS {runtime_version} "
                    f"(candidate {index + 1}/{len(candidates)})...",
                    flush=True,
                )
                created_device_udid = create_simulator(
                    xcrun,
                    f"{device_name}-{index + 1:02d}",
                    type_id,
                    runtime_id,
                    timeout_seconds=_bounded_timeout(45, operation_deadline, "simulator create"),
                    log=log,
                )
                if created_device_udid is None:
                    raise RuntimeError("simctl could not create a fresh standard iPhone simulator")
                device_id = created_device_udid
                log.write(
                    f"Created owned simulator ({device_id}), type={type_name}, "
                    f"runtime=iOS {runtime_version} ({runtime_id}).\n"
                )
                log.flush()
                try:
                    print("Booting owned iOS simulator...", flush=True)
                    boot_result = run_command(
                        [xcrun, "simctl", "boot", device_id],
                        timeout_seconds=_bounded_timeout(30, attempt_deadline, "simulator boot"),
                        log=log,
                        label="simulator boot",
                        allow_failure=True,
                    )
                    if boot_result != 0:
                        raise RuntimeError(f"simulator boot failed with exit code {boot_result}")
                    bootstatus_output: list[str] = []
                    run_command(
                        [xcrun, "simctl", "bootstatus", device_id, "-bd"],
                        timeout_seconds=_bounded_timeout(
                            args.boot_timeout_seconds, attempt_deadline, "simulator bootstatus"
                        ),
                        log=log,
                        label="simulator bootstatus",
                        output_callback=bootstatus_output.append,
                    )
                    if not bootstatus_output:
                        raise RuntimeError("simctl bootstatus produced no output")
                    break
                except Exception as error:
                    log.write(f"Candidate {index + 1} boot/migration failed: {error}\n")
                    log.flush()
                    # A fresh, owned simulator is the only device ever cleaned up.
                    run_command([xcrun, "simctl", "shutdown", device_id], timeout_seconds=30,
                                log=log, label="simulator shutdown", allow_failure=True)
                    delete_result = run_command(
                        [xcrun, "simctl", "delete", device_id], timeout_seconds=30,
                        log=log, label="owned simulator delete", allow_failure=True,
                    )
                    retry_deadline = min(operation_deadline, time.monotonic() + 20)
                    for retry_index in range(1, 3):
                        remaining = min(retry_deadline, operation_deadline) - time.monotonic()
                        if delete_result == 0 or remaining <= 0:
                            break
                        log.write(
                            f"Owned simulator delete failed; short retry "
                            f"{retry_index}/2 for {device_id} ({remaining:.0f}s retry budget remains).\n"
                        )
                        log.flush()
                        delete_result = run_command(
                            [xcrun, "simctl", "delete", device_id],
                            timeout_seconds=min(10.0, remaining),
                            log=log,
                            label=f"owned simulator delete retry {retry_index}/2",
                            allow_failure=True,
                        )
                    if (delete_result != 0 and not service_recovery_attempted
                            and getattr(args, "recover_simulator_service", False)):
                        service_recovery_attempted = True
                        if recover_owned_simulator_delete(
                            xcrun, device_id, enabled=True, log=log,
                        ):
                            delete_result = 0
                    if delete_result != 0:
                        raise RuntimeError(
                            f"failed simulator candidate {device_id} could not be confirmed deleted; "
                            "refusing to create another simulator"
                        ) from error
                    created_device_udid = None
                    device_id = None
                    if index + 1 >= len(candidates):
                        raise
                    log.write("Retrying boot/migration with the next supported runtime/device candidate.\n")
                    log.flush()
            if device_id is None:
                raise RuntimeError("no simulator candidate completed OS boot")
            migration_statuses = parse_migration_statuses(bootstatus_output[-1])
            running_migrations = sorted(
                name for name, status in migration_statuses.items() if status == "running"
            )
            pending_migrations = sorted(
                name for name, status in migration_statuses.items() if status == "pending"
            )
            if running_migrations or pending_migrations:
                log.write(
                    "OS boot completed; continuing while data migrations remain active. "
                    f"running={running_migrations}, pending={pending_migrations}\n"
                )
                log.flush()
            else:
                log.write("OS boot completed; all reported data migrations succeeded.\n")
                log.flush()
            print("Simulator OS boot completed; installing the app...", flush=True)
            run_command(
                [xcrun, "simctl", "install", device_id, args.app_path],
                # iOS may continue first-boot MobileAsset/data migration after
                # bootstatus reports boot completion. Let install wait for the
                # simulator service to become ready, but retain a hard ceiling.
                timeout_seconds=_bounded_timeout(
                    args.install_timeout_seconds, operation_deadline, "simulator install"
                ),
                log=log,
                label="simulator install",
            )

            launch_command = [
                xcrun,
                "simctl",
                "launch",
                "--console-pty",
                device_id,
                args.bundle_id,
                "--enable-dart-profiling",
                f"--vm-service-port={port}",
                "--vm-service-host=127.0.0.1",
                "--disable-service-auth-codes",
                "--disable-vm-service-publication",
                "--enable-checked-mode",
                "--verify-entry-points",
            ]
            log.write(f"\n$ {subprocess.list2cmdline(launch_command)}\n")
            log.flush()
            console_file = console_path.open("wb")
            try:
                console_process = subprocess.Popen(
                    launch_command,
                    stdout=console_file,
                    stderr=subprocess.STDOUT,
                    stdin=subprocess.DEVNULL,
                )
            finally:
                console_file.close()

            print(
                f"Waiting up to {args.startup_timeout_seconds}s for the loopback VM service; "
                f"console output: {console_path}",
                flush=True,
            )
            if not wait_for_vm_service(
                port,
                min(
                    args.startup_timeout_seconds,
                    max(0, operation_deadline - time.monotonic()),
                ),
                log,
                launch_process=console_process,
            ):
                raise RuntimeError("Simulator app did not expose a valid Dart VM service.")
            if console_process.poll() not in (None, 0):
                raise RuntimeError(
                    f"simctl launch --console-pty exited with {console_process.returncode}"
                )

            drive_command = [
                args.flutter,
                "drive",
                "--verbose",
                "--debug",
                "--no-pub",
                "--no-dds",
                "-d",
                device_id,
                f"--use-existing-app=http://127.0.0.1:{port}/",
                f"--target={args.target}",
                f"--driver={args.driver}",
                f"--timeout={args.driver_timeout_seconds}",
            ]
            print("VM service is ready; running Flutter driver startup/native-channel checks.", flush=True)
            exit_code = run_command(
                drive_command,
                timeout_seconds=_bounded_timeout(
                    args.driver_timeout_seconds + 60,
                    operation_deadline,
                    "Flutter driver smoke",
                ),
                log=log,
                label="Flutter driver smoke",
                allow_failure=True,
            )
            if exit_code != 0:
                raise RuntimeError(f"Flutter driver smoke failed with exit code {exit_code}")
            print("Flutter driver startup/native-channel checks passed.", flush=True)
        except Exception as error:  # Preserve the original failure while collecting evidence.
            log.write(f"\nSMOKE FAILURE: {type(error).__name__}: {error}\n")
            log.flush()
            print(f"iOS launch smoke failed: {error}", file=sys.stderr, flush=True)
            exit_code = 1
            if created_device_udid is not None:
                try:
                    collect_failure_diagnostics(xcrun, created_device_udid, args.app_path, log)
                except Exception as diagnostic_error:  # Keep the original smoke failure.
                    log.write(f"Diagnostic collection failed: {type(diagnostic_error).__name__}\n")
                    log.flush()
        finally:
            if device_id is not None:
                run_command(
                    [xcrun, "simctl", "io", device_id, "screenshot", str(screenshot_path)],
                    timeout_seconds=20,
                    log=log,
                    label="simulator screenshot",
                    allow_failure=True,
                )
                terminate_process(console_process, log)
                run_command(
                    [xcrun, "simctl", "terminate", device_id, args.bundle_id],
                    timeout_seconds=20,
                    log=log,
                    label="simulator app terminate",
                    allow_failure=True,
                )
                run_command(
                    [xcrun, "simctl", "shutdown", device_id],
                    timeout_seconds=30,
                    log=log,
                    label="simulator shutdown",
                    allow_failure=True,
                )
                delete_result = run_command(
                    [xcrun, "simctl", "delete", created_device_udid],
                    timeout_seconds=30,
                    log=log,
                    label="owned simulator delete",
                    allow_failure=True,
                )
                if delete_result != 0 and not service_recovery_attempted:
                    recover_owned_simulator_delete(
                        xcrun, created_device_udid,
                        enabled=getattr(args, "recover_simulator_service", False), log=log,
                    )
            else:
                log.write("No owned simulator was created; no existing simulator was modified.\n")
                log.flush()
            log.write(f"\nSmoke exit code: {exit_code}\n")
            log.flush()
            print(f"Simulator evidence saved under {evidence}.", flush=True)

    if not console_path.exists():
        console_path.write_text("No simulator console output captured.\n", encoding="utf-8")
    if not screenshot_path.exists():
        print("Simulator screenshot was not produced.", file=sys.stderr, flush=True)
    return exit_code


def parse_args(argv: Sequence[str] | None = None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--device-name", required=True)
    parser.add_argument("--runtimes-file", required=True)
    parser.add_argument("--device-types-file", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-path", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--driver", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--xcrun", default="xcrun")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--boot-timeout-seconds", type=int, default=150)
    parser.add_argument("--install-timeout-seconds", type=int, default=600)
    parser.add_argument("--startup-timeout-seconds", type=int, default=180)
    parser.add_argument("--driver-timeout-seconds", type=int, default=480)
    parser.add_argument("--operation-timeout-seconds", type=int, default=960)
    parser.add_argument("--recover-simulator-service", action="store_true",
                        help="Restart the current user's CoreSimulatorService once after owned-device delete failure.")
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run_smoke(parse_args()))
