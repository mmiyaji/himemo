#!/usr/bin/env python3
"""Validate the checked CloudKit schema manifest against native constants."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCHEMA_PATH = ROOT / "cloudkit" / "expected-schema.json"
APP_DELEGATE_PATH = ROOT / "ios" / "Runner" / "AppDelegate.swift"


def main() -> int:
    schema = json.loads(SCHEMA_PATH.read_text(encoding="utf-8"))
    app_delegate = APP_DELEGATE_PATH.read_text(encoding="utf-8")

    failures: list[str] = []
    container_id = schema["containerId"]
    if f'"{container_id}"' not in app_delegate:
        failures.append(f"Missing CloudKit container id in AppDelegate.swift: {container_id}")

    record_types = schema.get("recordTypes", {})
    if not isinstance(record_types, dict) or not record_types:
        failures.append("expected-schema.json must define recordTypes")

    swift_string_literals = set(re.findall(r'"([^"]+)"', app_delegate))
    for record_type, record_spec in record_types.items():
        if record_type not in swift_string_literals:
            failures.append(f"Missing record type constant in AppDelegate.swift: {record_type}")
        fields = record_spec.get("fields", {})
        if not isinstance(fields, dict) or not fields:
            failures.append(f"{record_type} must define fields")
            continue
        for field_name in fields:
            if field_name not in swift_string_literals:
                failures.append(
                    f"Missing field constant in AppDelegate.swift: {record_type}.{field_name}"
                )

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print(
        "CloudKit expected schema matches AppDelegate constants: "
        f"{len(record_types)} record types"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
