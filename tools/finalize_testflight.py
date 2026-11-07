"""Wait for an uploaded build, save Japanese test notes and enable its internal group.

Uses Apple's App Store Connect API; never uploads a binary or alters export compliance.
Requires Python's standard library and the openssl executable available on macOS CI.
"""

import argparse
import base64
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import time
from urllib.error import HTTPError, URLError
from urllib.parse import urlencode, urlsplit
from urllib.request import Request, urlopen

BASE = "https://api.appstoreconnect.apple.com"


class ApiError(RuntimeError):
    def __init__(self, status, codes="", operation="", detail=""):
        self.status = status
        hint = " Check App Store Connect API key permissions." if status in (401, 403) else ""
        super().__init__(f"App Store Connect API HTTP {status} ({codes or 'request failed'}) "
                         f"at {operation or 'request'}. {detail}{hint}")


def b64(data):
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def der_to_raw(signature):
    """Convert OpenSSL's ASN.1 ECDSA signature to JOSE's fixed-width R || S."""
    def length(offset):
        if offset >= len(signature):
            raise ValueError("Truncated ECDSA signature")
        value = signature[offset]
        offset += 1
        if value & 128:
            count = value & 127
            if not count or count > 2 or offset + count > len(signature):
                raise ValueError("Invalid ECDSA length")
            value = int.from_bytes(signature[offset:offset + count], "big")
            offset += count
        return value, offset

    if not signature or signature[0] != 0x30:
        raise ValueError("Invalid ECDSA sequence")
    size, offset = length(1)
    if offset + size != len(signature):
        raise ValueError("Invalid ECDSA sequence length")
    values = []
    for _ in range(2):
        if offset >= len(signature) or signature[offset] != 2:
            raise ValueError("Invalid ECDSA integer")
        size, offset = length(offset + 1)
        value = signature[offset:offset + size]
        if len(value) != size or not value or value[0] & 128:
            raise ValueError("Invalid ECDSA integer value")
        value = value.lstrip(b"\0")
        if len(value) > 32:
            raise ValueError("ES256 requires P-256 integers")
        values.append(value.rjust(32, b"\0"))
        offset += size
    if offset != len(signature):
        raise ValueError("Trailing ECDSA data")
    return b"".join(values)


class Signer:
    def __init__(self, key_id, issuer, key_file):
        self.key_id, self.issuer, self.key_file = key_id, issuer, key_file
        self.cached = None
        self.refresh_at = 0

    def token(self):
        now = int(time.time())
        if self.cached and now < self.refresh_at:
            return self.cached
        header = b64(json.dumps({"alg": "ES256", "kid": self.key_id, "typ": "JWT"}).encode())
        payload = b64(json.dumps({"iss": self.issuer, "iat": now - 5,
                                  "exp": now + 1140, "aud": "appstoreconnect-v1"}).encode())
        unsigned = f"{header}.{payload}".encode("ascii")
        signed = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(self.key_file)],
            input=unsigned, stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
        if signed.returncode:
            # OpenSSL diagnostics can contain key file data; do not echo stderr.
            raise RuntimeError("Could not sign App Store Connect API token with openssl.")
        self.cached = unsigned.decode() + "." + b64(der_to_raw(signed.stdout))
        self.refresh_at = now + 900
        return self.cached


class Api:
    def __init__(self, signer):
        self.signer = signer

    def request(self, method, path, query=None, data=None):
        url = path if path.startswith("https://") else BASE + path
        if urlsplit(url).scheme != "https" or urlsplit(url).netloc != urlsplit(BASE).netloc:
            raise RuntimeError("Unexpected App Store Connect pagination host.")
        if query:
            url += "?" + urlencode(query)
        body = None if data is None else json.dumps(data).encode("utf-8")
        for attempt in range(6):
            request = Request(url, data=body, method=method, headers={
                "Authorization": "Bearer " + self.signer.token(),
                "Content-Type": "application/json", "Accept": "application/json",
            })
            try:
                with urlopen(request, timeout=60) as response:
                    content = response.read()
                    return json.loads(content) if content else {}
            except HTTPError as error:
                if (error.code == 429 or 500 <= error.code < 600) and attempt < 5:
                    retry = error.headers.get("Retry-After", "") if error.headers else ""
                    delay = min(int(retry), 60) if retry.isdigit() else min(2 ** attempt * 2, 30)
                    time.sleep(delay)
                    continue
                try:
                    details = json.loads(error.read())
                    errors = details.get("errors", [])
                    codes = ",".join(str(e.get("code", "")) for e in errors)
                    # Metadata validation messages explain 422 failures; auth
                    # errors never echo server details or request credentials.
                    explanation = " ".join(str(e.get("detail", e.get("title", "")))
                                           for e in errors)[:1200] if error.code == 422 else ""
                except (ValueError, AttributeError, TypeError):
                    codes, explanation = "", ""
                raise ApiError(error.code, codes, method + " " + urlsplit(url).path,
                               explanation) from None
            except (URLError, TimeoutError):
                if attempt == 5:
                    raise RuntimeError("App Store Connect API network request failed after retries.") from None
                time.sleep(min(2 ** attempt * 2, 30))

    def list(self, path, query=None):
        result = []
        while path:
            response = self.request("GET", path, query=query)
            data = response.get("data")
            if not isinstance(data, list):
                raise RuntimeError("Invalid App Store Connect list response.")
            result.extend(data)
            path = response.get("links", {}).get("next")
            query = None
        return result


def one(items, label):
    if len(items) != 1:
        raise RuntimeError(f"Expected exactly one {label}; found {len(items)}.")
    return items[0]


def wait_build(api, app_id, build_number, timeout):
    deadline = time.monotonic() + timeout
    last_state = None
    while True:
        matches = [item for item in api.list("/v1/builds", {
            "filter[app]": app_id, "filter[version]": build_number, "limit": "200",
        }) if item.get("attributes", {}).get("version") == build_number]
        if matches:
            build = one(matches, "uploaded build")
            state = build.get("attributes", {}).get("processingState")
            if state in ("FAILED", "INVALID"):
                raise RuntimeError(f"Apple build processing ended with {state}; no upload was retried.")
            if state == "VALID":
                if build.get("attributes", {}).get("expired"):
                    raise RuntimeError("Uploaded build is already expired.")
                return build
        else:
            state = "NOT_VISIBLE"
        if state != last_state:
            print(f"Apple processing: {state}", flush=True)
            last_state = state
        if time.monotonic() >= deadline:
            raise RuntimeError("Timed out waiting for Apple processing; rerun finalization without re-uploading.")
        time.sleep(min(20, max(0, deadline - time.monotonic())))


def set_notes(api, build_id, notes):
    def existing():
        return [item for item in api.list("/v1/betaBuildLocalizations", {
            "filter[build]": build_id, "limit": "200",
        }) if item.get("attributes", {}).get("locale") == "ja"]

    def update(localization):
        api.request("PATCH", "/v1/betaBuildLocalizations/" + localization["id"], data={"data": {
            "type": "betaBuildLocalizations", "id": localization["id"],
            "attributes": {"whatsNew": notes},
        }})

    found = existing()
    if found:
        update(one(found, "Japanese test localization"))
    else:
        try:
            api.request("POST", "/v1/betaBuildLocalizations", data={"data": {
                "type": "betaBuildLocalizations", "attributes": {"locale": "ja", "whatsNew": notes},
                "relationships": {"build": {"data": {"type": "builds", "id": build_id}}},
            }})
        except ApiError as error:
            if error.status != 409:
                raise
            update(one(existing(), "Japanese test localization after concurrent creation"))
    saved = one(existing(), "saved Japanese test localization")
    if saved.get("attributes", {}).get("whatsNew") != notes:
        raise RuntimeError("Japanese test notes were not confirmed by read-back.")


def attach_group(api, app_id, build_id, group_name):
    group = one([item for item in api.list("/v1/betaGroups", {
        "filter[app]": app_id, "limit": "200",
    }) if item.get("attributes", {}).get("name") == group_name], "named tester group")
    if group.get("attributes", {}).get("isInternalGroup") is not True:
        raise RuntimeError("Refusing to distribute to a group that is not internal.")
    if group.get("attributes", {}).get("hasAccessToAllBuilds") is True:
        # Automatic internal groups already grant access. Their relationship
        # list need not enumerate implicitly available builds; do not POST.
        print(f"Internal group {group_name}: automatic access to all builds", flush=True)
        return group["id"]
    path = "/v1/betaGroups/" + group["id"] + "/relationships/builds"
    if not any(item.get("id") == build_id for item in api.list(path, {"limit": "200"})):
        api.request("POST", path, data={"data": [{"type": "builds", "id": build_id}]})
    if not any(item.get("id") == build_id for item in api.list(path, {"limit": "200"})):
        raise RuntimeError("Internal tester group access was not confirmed by read-back.")
    return group["id"]


def wait_internal_testing(api, build_id, timeout):
    """Processing VALID is separate from availability to internal testers."""
    deadline = time.monotonic() + timeout
    previous = None
    while True:
        detail = api.request("GET", "/v1/builds/" + build_id + "/buildBetaDetail").get("data", {})
        state = detail.get("attributes", {}).get("internalBuildState")
        if state != previous:
            print(f"Internal tester availability: {state}", flush=True)
            previous = state
        if state == "IN_BETA_TESTING":
            return state
        if state in ("EXPIRED", "PROCESSING_EXCEPTION", "MISSING_EXPORT_COMPLIANCE",
                     "IN_EXPORT_COMPLIANCE_REVIEW"):
            raise RuntimeError(f"Internal testing is blocked by {state}; export compliance was not changed.")
        if time.monotonic() >= deadline:
            raise RuntimeError(f"Build is VALID and assigned, but internal testing remains {state}; "
                               "rerun finalization to verify availability without re-uploading.")
        time.sleep(min(20, max(0, deadline - time.monotonic())))


def finalize(api, bundle_id, build_number, group, notes, timeout):
    app = one([item for item in api.list("/v1/apps", {"filter[bundleId]": bundle_id, "limit": "200"})
               if item.get("attributes", {}).get("bundleId") == bundle_id], "app")
    build = wait_build(api, app["id"], build_number, timeout)
    print(f"Apple processing VALID: app={app['id']} build={build['id']} number={build_number}", flush=True)
    initial_detail = api.request("GET", "/v1/builds/" + build["id"] + "/buildBetaDetail")
    print("Observed internal state: " + str(initial_detail.get("data", {}).get("attributes", {})
                                            .get("internalBuildState")), flush=True)
    set_notes(api, build["id"], notes)
    print("Japanese test notes confirmed", flush=True)
    group_id = attach_group(api, app["id"], build["id"], group)
    internal_state = wait_internal_testing(api, build["id"], timeout)
    result = {"appId": app["id"], "buildId": build["id"], "buildNumber": build_number,
              "processingState": "VALID", "internalGroupId": group_id,
              "usesNonExemptEncryption": build.get("attributes", {}).get("usesNonExemptEncryption"),
              "internalBuildState": internal_state,
              "url": f"https://appstoreconnect.apple.com/apps/{app['id']}/testflight/ios/{build['id']}"}
    print(json.dumps(result, ensure_ascii=False), flush=True)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bundle-id", required=True)
    parser.add_argument("--build-number", required=True)
    parser.add_argument("--group", required=True)
    parser.add_argument("--notes-file", type=Path, required=True)
    parser.add_argument("--timeout-seconds", type=int, default=1200)
    parser.add_argument("--private-key-file", type=Path,
                        default=os.environ.get("APP_STORE_CONNECT_API_PRIVATE_KEY_PATH"))
    args = parser.parse_args()
    key_id = os.environ.get("APP_STORE_CONNECT_API_KEY_ID")
    issuer = os.environ.get("APP_STORE_CONNECT_API_ISSUER_ID")
    if not key_id or not issuer:
        parser.error("APP_STORE_CONNECT_API_KEY_ID and APP_STORE_CONNECT_API_ISSUER_ID are required")
    notes = args.notes_file.read_text(encoding="utf-8").strip()
    if not notes or len(notes) > 4000 or args.timeout_seconds < 1:
        parser.error("Notes must contain 1–4000 characters and timeout must be positive")
    with tempfile.TemporaryDirectory(prefix="asc-finalize-") as directory:
        key_file = args.private_key_file
        if key_file is None:
            private_key = os.environ.get("APP_STORE_CONNECT_API_PRIVATE_KEY")
            if not private_key:
                parser.error("Provide --private-key-file or APP_STORE_CONNECT_API_PRIVATE_KEY")
            key_file = Path(directory) / "AuthKey.p8"
            key_file.write_text(private_key, encoding="utf-8")
            key_file.chmod(0o600)
        finalize(Api(Signer(key_id, issuer, key_file)), args.bundle_id,
                 args.build_number, args.group, notes, args.timeout_seconds)


if __name__ == "__main__":
    try:
        main()
    except (RuntimeError, ValueError, OSError) as error:
        print(f"TestFlight finalization failed: {error}", file=sys.stderr)
        sys.exit(1)
