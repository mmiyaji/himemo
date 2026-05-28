# Sync E2E Hardening - 2026-05-28

## Scope

- Added Playwright coverage for the fake Google Drive sync path.
- Enabled `HIMEMO_FAKE_GOOGLE_DRIVE_SYNC=true` for the E2E web build only.
- Covered simulator connection, manual sync control visibility, repeated remote-status refreshes, empty-remote download handling, and rapid upload clicks while no remote bundle is available.

## Findings And Fixes

- Finding: Existing Playwright E2E served the development web build without the fake Google Drive transport enabled, so browser E2E could not exercise authenticated sync behavior without a real Google account.
- Fix: Added `web:build:e2e` and wired `web:serve:test` to build with the fake Google Drive sync dart define.
- Finding: Sync E2E coverage focused on the exclusion tag UI and did not cover a full cloud-sync transfer loop from settings.
- Fix: Added `playwright/tests/sync-google-drive.spec.js` with fake Google Drive connection, repeated refresh, empty-remote, and rapid-click flows.
- Finding: Web sync actions failed with `Could not access the sql.js javascript library` because Drift's legacy web executor expected `initSqlJs` and the wasm asset at runtime.
- Fix: Added a local `sql.js` dependency, a copy script for `web/vendor/sqljs/`, and `locateFile` wiring in `web/index.html`.
- Finding: Re-upload on Web can reach upload with pending note state in memory but an empty pending-change table.
- Fix: `uploadCurrentBundle` now derives pending changes from in-memory `pendingUpload` / `pendingDelete` notes when the persistent queue is empty.

## Test Notes

- Passed: `npm run e2e -- sync-google-drive.spec.js` (2 tests)
- Passed: `.\\.fvm\\flutter_sdk\\bin\\flutter.bat analyze`
- Additional focused reruns should be used when this file is changed because the tests exercise asynchronous Flutter web semantics and sync state transitions.
