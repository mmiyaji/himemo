import base64
import io
import json
from pathlib import Path
import sys
import unittest
from unittest.mock import Mock, patch
from urllib.error import HTTPError

sys.path.insert(0, str(Path(__file__).resolve().parent))
import finalize_testflight as target


class FinalizationTests(unittest.TestCase):
    def test_der_signature_sign_padding_and_fixed_width(self):
        r = b"\0" + b"\x80" * 32
        s = b"\x01"
        body = b"\x02" + bytes([len(r)]) + r + b"\x02\x01" + s
        self.assertEqual(target.der_to_raw(b"\x30" + bytes([len(body)]) + body),
                         b"\x80" * 32 + b"\0" * 31 + b"\x01")
        for malformed in (b"", b"\x30\x00", b"\x30\x03\x02\x01\xff"):
            with self.assertRaises(ValueError):
                target.der_to_raw(malformed)

    @patch.object(target.subprocess, "run")
    def test_jwt_uses_es256_raw_signature_and_does_not_resign_every_request(self, run):
        run.return_value = Mock(returncode=0, stdout=b"\x30\x06\x02\x01\x01\x02\x01\x02")
        signer = target.Signer("key", "issuer", Path("private.p8"))
        token = signer.token()
        self.assertEqual(signer.token(), token)
        self.assertEqual(run.call_count, 1)
        header, payload, signature = token.split(".")
        self.assertEqual(json.loads(base64.urlsafe_b64decode(header + "=="))["alg"], "ES256")
        self.assertEqual(json.loads(base64.urlsafe_b64decode(payload + "=="))["aud"], "appstoreconnect-v1")
        self.assertEqual(len(base64.urlsafe_b64decode(signature + "==")), 64)

    @patch.object(target.time, "sleep")
    def test_processing_checks_exact_build_number_then_valid(self, sleep):
        api = Mock()
        api.list.side_effect = [[], [{"id": "other", "attributes": {"version": "9"}},
                                      {"id": "wanted", "attributes": {"version": "10", "processingState": "VALID"}}]]
        self.assertEqual(target.wait_build(api, "app", "10", 5)["id"], "wanted")
        sleep.assert_called_once()

    def test_failed_build_never_reuploads(self):
        api = Mock()
        api.list.return_value = [{"id": "b", "attributes": {"version": "10", "processingState": "INVALID"}}]
        with self.assertRaisesRegex(RuntimeError, "INVALID"):
            target.wait_build(api, "app", "10", 5)
        api.request.assert_not_called()

    def test_automatic_internal_group_requires_no_explicit_build_assignment(self):
        api = Mock()
        api.list.return_value = [{"id": "g", "attributes": {
            "name": "team", "isInternalGroup": True, "hasAccessToAllBuilds": True}}]
        self.assertEqual(target.attach_group(api, "app", "b", "team"), "g")
        api.request.assert_not_called()
        self.assertEqual(api.list.call_count, 1)

    def test_existing_internal_group_membership_is_idempotent(self):
        api = Mock()
        api.list.side_effect = [[{"id": "g", "attributes": {"name": "team", "isInternalGroup": True}}],
                                [{"id": "b"}], [{"id": "b"}]]
        self.assertEqual(target.attach_group(api, "app", "b", "team"), "g")
        api.request.assert_not_called()

    def test_refuses_external_group(self):
        api = Mock()
        api.list.return_value = [{"id": "g", "attributes": {"name": "team", "isInternalGroup": False}}]
        with self.assertRaisesRegex(RuntimeError, "not internal"):
            target.attach_group(api, "app", "b", "team")

    @patch.object(target.time, "sleep")
    def test_valid_build_is_not_mistaken_for_internal_availability(self, sleep):
        api = Mock()
        api.request.side_effect = [
            {"data": {"attributes": {"internalBuildState": "READY_FOR_BETA_TESTING"}}},
            {"data": {"attributes": {"internalBuildState": "IN_BETA_TESTING"}}},
        ]
        self.assertEqual(target.wait_internal_testing(api, "b", 5), "IN_BETA_TESTING")
        sleep.assert_called_once()

    def test_export_compliance_is_only_reported_never_changed(self):
        api = Mock()
        api.request.return_value = {"data": {"attributes": {"internalBuildState": "MISSING_EXPORT_COMPLIANCE"}}}
        with self.assertRaisesRegex(RuntimeError, "was not changed"):
            target.wait_internal_testing(api, "b", 5)
        self.assertEqual(api.request.call_args.args, ("GET", "/v1/builds/b/buildBetaDetail"))

    def test_existing_japanese_notes_are_patched_and_read_back(self):
        api = Mock()
        api.list.side_effect = [[{"id": "j", "attributes": {"locale": "ja", "whatsNew": "old"}}],
                               [{"id": "j", "attributes": {"locale": "ja", "whatsNew": "new"}}]]
        target.set_notes(api, "b", "new")
        self.assertEqual(api.request.call_args.args, ("PATCH", "/v1/betaBuildLocalizations/j"))

    @patch.object(target.time, "sleep")
    @patch.object(target, "urlopen")
    def test_unauthorized_is_not_retried_or_logged_with_token(self, urlopen, sleep):
        urlopen.side_effect = HTTPError(target.BASE, 403, "Forbidden", {}, io.BytesIO(b'{"errors":[{"code":"FORBIDDEN"}]}'))
        with self.assertRaisesRegex(target.ApiError, "permissions"):
            target.Api(Mock(token=lambda: "secret-token")).request("GET", "/v1/apps")
        sleep.assert_not_called()
        self.assertEqual(urlopen.call_count, 1)

    @patch.object(target.time, "sleep")
    @patch.object(target, "urlopen")
    def test_transient_response_is_retried(self, urlopen, sleep):
        response = Mock()
        response.__enter__ = Mock(return_value=response)
        response.__exit__ = Mock(return_value=False)
        response.read.return_value = b'{"data":[]}'
        urlopen.side_effect = [HTTPError(target.BASE, 429, "Limit", {"Retry-After": "1"}, io.BytesIO()), response]
        self.assertEqual(target.Api(Mock(token=lambda: "token")).request("GET", "/v1/apps"), {"data": []})
        sleep.assert_called_once_with(1)

    def test_pagination_rejects_external_host(self):
        with self.assertRaisesRegex(RuntimeError, "pagination host"):
            target.Api(Mock()).request("GET", "https://example.com/stolen")


if __name__ == "__main__":
    unittest.main()
