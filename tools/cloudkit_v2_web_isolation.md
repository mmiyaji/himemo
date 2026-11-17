# CloudKit v2 Web isolation

The read-only screen is available from Web settings and the standalone entry,
`tools/v2_cloudkit_readonly.dart`. It requires an API token and an explicit
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

The separate development entry `tools/v2_cloudkit_sandbox.dart` enables V2
editing only within such a named development sandbox. It requires an explicit
user action, an API token, and Apple authentication before it connects. The
application's production entry does not enable this screen. Its working
database and credentials are memory-only; save the generated recovery codes
and trigger sync before leaving if the test data needs to be reopened. Any
unsent changes are lost when the session ends. Do not use real notes, recovery
codes, or production data for this experiment.

`disconnect` blocks new operations and invalidates pending responses. A
CloudKit request already dispatched cannot be retracted, so sandbox separation
is still required during logout. The CloudKit SDK, live Apple authentication,
zone limits, asset behavior, pagination, and conflict semantics remain
unverified with a real Apple account. Automated tests use synthetic data and a
mock transport or SDK; they do not establish CloudKit production readiness.
