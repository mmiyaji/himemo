# CloudKit v2 Web isolation

The read-only screen is available only from the standalone development entry
`tools/v2_cloudkit_readonly.dart`; it is not part of application settings. It requires an API token and an explicit
Apple connection. It defaults to development and can read production after an
explicit selection. It never enables writes; its database and recovery
credentials are memory-only. It has not been tested against an Apple CloudKit
account and cannot edit or synchronize changes.

The bridge rejects `enableWrites: true` in production. In development it also
requires `sandboxNamespace`, a 16–32 character ASCII identifier consisting of
letters, numbers, `_`, or `-`. With that option every generation, including
`metadata-v1`, uses `HiMemoSyncV2WebTest-<namespace>-<generation>` instead of
the iOS `HiMemoSyncV2-<generation>` zone. The same namespace must be used by
all experimental participants; different namespaces cannot discover one
another. Keep the identifier non-secret and randomly generated to avoid
accidental reuse.

The retired V2 workspace screen and its standalone CloudKit sandbox UI entry
have been removed. The namespaced sandbox transport and its automated tests
remain for protocol experiments. No application route enables sandbox writes.
Use the unified local preview for UI development:

```sh
flutter run -d chrome -t tools/v2_web_local_preview.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
```

This preview uses an isolated browser database and in-memory credentials. It
never contacts iCloud. Reloading cannot recover those in-memory keys; use only
sample data.

`disconnect` blocks new operations and invalidates pending responses. A
CloudKit request already dispatched cannot be retracted, so sandbox separation
is still required during logout. The CloudKit SDK, live Apple authentication,
zone limits, asset behavior, pagination, and conflict semantics remain
unverified with a real Apple account. Automated tests use synthetic data and a
mock transport or SDK; they do not establish CloudKit production readiness.
