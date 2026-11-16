#!/usr/bin/env python3
"""Launch a prebuilt iOS simulator app and run its Flutter driver smoke test."""

from __future__ import annotations

import argparse
import json
import socket
import shlex
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import IO, Sequence


def choose_loopback_port() -> int:
    """Choose an unused ephemeral TCP port on the loopback interface."""
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as listener:
        listener.bind(("127.0.0.1", 0))
        return int(listener.getsockname()[1])


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
            log.write(output)
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
        log.write(completed.stdout)
    log.write(f"\n{label} exit code: {completed.returncode}\n")
    log.flush()
    if completed.returncode and not allow_failure:
        raise RuntimeError(f"{label} failed with exit code {completed.returncode}")
    return completed.returncode


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

    with transcript_path.open("w", encoding="utf-8") as log:
        log.write(f"Simulator: {args.device}\nBundle: {args.bundle_id}\n")
        port = choose_loopback_port()
        log.write(f"Chosen VM service loopback port: {port}\n")
        log.flush()
        try:
            print("Booting iOS simulator and installing the app...", flush=True)
            run_command(
                [xcrun, "simctl", "boot", args.device],
                timeout_seconds=30,
                log=log,
                label="simulator boot",
                allow_failure=True,
            )
            run_command(
                [xcrun, "simctl", "bootstatus", args.device, "-b"],
                timeout_seconds=args.boot_timeout_seconds,
                log=log,
                label="simulator bootstatus",
            )
            run_command(
                [xcrun, "simctl", "install", args.device, args.app_path],
                timeout_seconds=120,
                log=log,
                label="simulator install",
            )

            launch_command = [
                xcrun,
                "simctl",
                "launch",
                "--console-pty",
                args.device,
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
                args.startup_timeout_seconds,
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
                args.device,
                f"--use-existing-app=http://127.0.0.1:{port}/",
                f"--target={args.target}",
                f"--driver={args.driver}",
                f"--timeout={args.driver_timeout_seconds}",
            ]
            print("VM service is ready; running Flutter driver startup/native-channel checks.", flush=True)
            exit_code = run_command(
                drive_command,
                timeout_seconds=args.driver_timeout_seconds + 60,
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
        finally:
            run_command(
                [xcrun, "simctl", "io", args.device, "screenshot", str(screenshot_path)],
                timeout_seconds=30,
                log=log,
                label="simulator screenshot",
                allow_failure=True,
            )
            terminate_process(console_process, log)
            run_command(
                [xcrun, "simctl", "terminate", args.device, args.bundle_id],
                timeout_seconds=30,
                log=log,
                label="simulator app terminate",
                allow_failure=True,
            )
            run_command(
                [xcrun, "simctl", "shutdown", args.device],
                timeout_seconds=60,
                log=log,
                label="simulator shutdown",
                allow_failure=True,
            )
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
    parser.add_argument("--device", required=True)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--app-path", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--driver", required=True)
    parser.add_argument("--evidence-dir", required=True)
    parser.add_argument("--xcrun", default="xcrun")
    parser.add_argument("--flutter", default="flutter")
    parser.add_argument("--boot-timeout-seconds", type=int, default=180)
    parser.add_argument("--startup-timeout-seconds", type=int, default=180)
    parser.add_argument("--driver-timeout-seconds", type=int, default=480)
    return parser.parse_args(argv)


if __name__ == "__main__":
    raise SystemExit(run_smoke(parse_args()))
