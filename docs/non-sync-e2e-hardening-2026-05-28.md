# Non-sync E2E hardening - 2026-05-28

## Scope

- Expanded E2E coverage outside sync, focusing on abnormal startup/storage behavior and home search responsiveness.
- Used a parallel read-only agent to review existing non-sync coverage and identify gaps around import/export, search stress, private storage, and storage failures.

## Added coverage

- `playwright/tests/non-sync-abnormal-performance.spec.js`
  - Seeds malformed legacy note storage and verifies the app starts, hides raw Flutter errors, quarantines the malformed payload, and keeps the note editor usable.
  - Seeds 240 large local notes and verifies search can find a rare note within a conservative 8 second threshold.
- `test/security_storage_test.dart`
  - Verifies malformed legacy plaintext notes are quarantined instead of blocking startup.

## Bug found and fixed

- Malformed legacy plaintext notes in `notes.entries.v1` could throw during migration and prevent the app from reaching a usable home screen.
- `EncryptedNoteStore.load` now moves malformed legacy payloads to `notes.entries.v1.corrupt`, removes the active legacy key, and returns fallback notes so the app can start and remain writable.

## Test runs

- `flutter test test/security_storage_test.dart --plain-name "quarantines malformed legacy notes and keeps fallback notes"`: passed.
- `flutter analyze`: passed.
- `npm run e2e -- non-sync-abnormal-performance.spec.js`: passed, 2 tests.
- The new Playwright spec was run repeatedly while hardening the abnormal/performance cases. Early runs exposed overly strict UI assertions around Flutter Web semantics and a pre-search virtualized list assumption; the final spec now asserts the storage recovery behavior directly and measures search after entering the query.

## Follow-up risks

- Local ZIP import/export still needs deeper malformed archive coverage: missing `manifest.json`, missing `notes.json`, wrong password, malformed note JSON, and missing attachment files.
- Search stress now has E2E coverage at 240 notes; provider-level stress tests at 1,000+ notes would give tighter performance signals without browser variance.
