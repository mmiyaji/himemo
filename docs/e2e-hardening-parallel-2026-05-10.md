# E2E Hardening Parallel Run - 2026-05-10

Branch: `codex/e2e-hardening-parallel`

## Goal

Run parallel E2E and monkey-style checks across major HiMemo user flows, identify reproducible issues, fix them, and confirm fixes with focused retests.

## Parallel Scopes

- Attachments and media: image, video, audio, file attachment flows, media preview, fullscreen behavior.
- Mobile UI: note detail bottom sheet, drag-to-dismiss, rapid open/close, mobile editor flows.
- Private profiles and lock: profile creation/cancel, profile switching, lock-related flows.
- Settings and sync UI: sync details, manual sync actions, app info links, help links.
- Core notes: quick/rich editor, first-line title behavior, tags, search, navigation.

## Timeline

- Created branch `codex/e2e-hardening-parallel`.
- Started five parallel worker agents with the scopes above.
- Initial `npm run e2e` failed because Playwright reused an old server on port `4173`; stopping that process allowed the current build to run.
- Updated Playwright flows for the current editor/settings UI.
- Fixed mobile note detail top-edge downward drag dismissal.

## Agent Findings

- Attachments and media: mixed attachment save was reported as suspicious because text extraction did not include the rendered card, but a focused retest saved the note and rendered the title, body, and four previews. Web audio needed a semantics-aware assertion.
- Mobile UI: bottom overscroll dismissal worked, but dragging down from the detail header/top edge did not close the mobile detail sheet.
- Private profiles and lock: after cancelling or closing an overlay, an immediate private-profile access click could be swallowed during the post-sheet suppression window.
- Settings and sync UI: cloud sync detail controls and external link confirmation dialogs needed fake-cloud integration coverage.
- Core notes: quick memo, search, and tag flows worked, but Playwright assertions were stale against the current editor and Flutter Web semantics.

## Fixes

- `_NoteDetailPager` now handles downward vertical drags on the detail header row and reuses the existing pull-to-dismiss feedback/threshold.
- The private-profile app-bar access button now remains truly disabled during the 450 ms post-sheet suppression window and re-enables through a timer, so rapid cancel-then-unlock clicks no longer disappear silently.
- `playwright/tests/app.spec.js` now matches the current UI:
  - Add note opens the editor directly.
  - Quick/Rich mode is selected through the mode menu.
  - Audio recording verification checks the attachment block controls instead of relying on label text exposure.
  - Settings assertions target currently visible collapsed section summaries.
- Tag/search E2E checks the note card via the accessible note-card role, allowing for Flutter Web semantics to expose the card as either a button or group.
- `integration_test/mobile_native_flows_test.dart` adds fake-cloud coverage for Google Drive sync detail controls, manual refresh/upload, re-upload confirmation, bundle history, and external help/legal/contact link dialogs.
- The integration scroll helper now searches both down and up so later settings assertions do not depend on the previous scroll position.

## Validation

- `flutter analyze`: pass.
- `npm run e2e`: pass, 9/9.
- `flutter test test/security_storage_test.dart --reporter expanded`: pass, 40/40.
- `flutter test test/app_test.dart --plain-name "private profile create dialog can be cancelled safely" --reporter expanded`: pass.
- `flutter test -d windows integration_test/mobile_native_flows_test.dart --plain-name "settings sync detail controls and app links use fake cloud"`: pass.
- Focused top-edge mobile detail drag retest on static web build: pass.
- Mixed attachment quick memo focused retest: pass by screenshot verification.

## Remaining Notes

- Full `integration_test/mobile_native_flows_test.dart` on Android currently fails before the new fake-cloud test because the emulator run cannot load `libsqlite3.so` from the debug APK path.
- Full `integration_test/mobile_native_flows_test.dart` on Windows still fails in the older simulator flow after forcing the app lock gate with `No Overlay widget found` and a large render overflow. The new sync/settings fake-cloud test is isolated and passing.
- `test/app_test.dart --plain-name "mobile tab switch closes open note detail sheet"` timed out in the widget harness. Browser-level mobile drag behavior was reproduced and fixed separately.
