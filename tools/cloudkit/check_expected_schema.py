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

CKDB_TYPE_MAP = {
    "ASSET": "Asset",
    "INT64": "Int(64)",
    "STRING": "String",
    "TIMESTAMP": "Date/Time",
}


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

    for ckdb_path in [Path(arg) for arg in sys.argv[1:]]:
        failures.extend(validate_ckdb_schema(schema, ckdb_path))

    if failures:
        for failure in failures:
            print(f"ERROR: {failure}", file=sys.stderr)
        return 1

    print(
        "CloudKit expected schema matches AppDelegate constants: "
        f"{len(record_types)} record types"
    )
    if len(sys.argv) > 1:
        print(f"Validated {len(sys.argv) - 1} exported CloudKit schema file(s)")
    return 0


def validate_ckdb_schema(schema: dict, ckdb_path: Path) -> list[str]:
    if not ckdb_path.exists():
        return [f"CloudKit schema export not found: {ckdb_path}"]

    exported = parse_ckdb_schema(ckdb_path.read_text(encoding="utf-8"))
    failures: list[str] = []
    for record_type, record_spec in schema.get("recordTypes", {}).items():
        exported_fields = exported.get(record_type)
        if exported_fields is None:
            failures.append(f"Missing record type in {ckdb_path}: {record_type}")
            continue
        for field_name, expected_type in record_spec.get("fields", {}).items():
            actual_type = exported_fields.get(field_name)
            if actual_type is None:
                failures.append(f"Missing field in {ckdb_path}: {record_type}.{field_name}")
            elif actual_type != expected_type:
                failures.append(
                    f"Field type mismatch in {ckdb_path}: "
                    f"{record_type}.{field_name} expected {expected_type}, got {actual_type}"
                )
    return failures


def parse_ckdb_schema(contents: str) -> dict[str, dict[str, str]]:
    record_types: dict[str, dict[str, str]] = {}
    for match in re.finditer(r"RECORD TYPE\s+(\w+)\s+\((.*?)\n\s*\);", contents, re.S):
        record_type = match.group(1)
        body = match.group(2)
        fields: dict[str, str] = {}
        for raw_line in body.splitlines():
            line = raw_line.strip().rstrip(",")
            if not line or line.startswith("GRANT "):
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            field_name, ckdb_type = parts[0].strip('"'), parts[1]
            if field_name.startswith("___"):
                continue
            mapped_type = CKDB_TYPE_MAP.get(ckdb_type)
            if mapped_type:
                fields[field_name] = mapped_type
        record_types[record_type] = fields
    return record_types


if __name__ == "__main__":
    raise SystemExit(main())
