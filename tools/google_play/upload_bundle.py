#!/usr/bin/env python3
"""Upload an Android App Bundle to a Google Play track."""

from __future__ import annotations

import argparse
import pathlib

import httplib2
from google.auth import default
from google_auth_httplib2 import AuthorizedHttp
from googleapiclient.discovery import build
from googleapiclient.http import MediaFileUpload


ANDROID_PUBLISHER_SCOPE = "https://www.googleapis.com/auth/androidpublisher"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--package-name", required=True)
    parser.add_argument("--bundle", required=True, type=pathlib.Path)
    parser.add_argument("--track", required=True)
    parser.add_argument("--status", default="completed")
    parser.add_argument("--release-name", default="")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    if not args.bundle.is_file():
        raise SystemExit(f"Bundle not found: {args.bundle}")

    credentials, _ = default(scopes=[ANDROID_PUBLISHER_SCOPE])
    authorized_http = AuthorizedHttp(
        credentials,
        http=httplib2.Http(timeout=600),
    )
    service = build(
        "androidpublisher",
        "v3",
        http=authorized_http,
        cache_discovery=False,
    )

    edit = service.edits().insert(packageName=args.package_name, body={}).execute()
    edit_id = edit["id"]

    media = MediaFileUpload(
        str(args.bundle),
        mimetype="application/octet-stream",
        resumable=True,
    )
    bundle = (
        service.edits()
        .bundles()
        .upload(
            packageName=args.package_name,
            editId=edit_id,
            media_body=media,
        )
        .execute()
    )
    version_code = str(bundle["versionCode"])

    release = {
        "versionCodes": [version_code],
        "status": args.status,
    }
    if args.release_name:
        release["name"] = args.release_name

    service.edits().tracks().update(
        packageName=args.package_name,
        editId=edit_id,
        track=args.track,
        body={
            "track": args.track,
            "releases": [release],
        },
    ).execute()
    service.edits().commit(
        packageName=args.package_name,
        editId=edit_id,
    ).execute()

    print(
        f"Uploaded {args.bundle} to {args.package_name} "
        f"track={args.track} versionCode={version_code} status={args.status}"
    )


if __name__ == "__main__":
    main()
