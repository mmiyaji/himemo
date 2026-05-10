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
- Continued the cycle with another parallel pass focused on lock gate, mobile detail sheets, attachments, core notes, settings, and private profiles.
- Cleaned generated build artifacts after disk pressure caused Dart/Flutter web compilation failures.
- Re-ran Windows integration, Flutter unit/widget, and Playwright browser suites after each fix.

## Agent Findings

- Attachments and media: mixed attachment save was reported as suspicious because text extraction did not include the rendered card, but a focused retest saved the note and rendered the title, body, and four previews. Web audio needed a semantics-aware assertion.
- Attachments and media, second pass: attachment storage and duration metadata were stable. A real mobile editor overflow was found around the mode/media control row at 430 px width.
- Mobile UI: bottom overscroll dismissal worked, but dragging down from the detail header/top edge did not close the mobile detail sheet.
- Mobile UI, second pass: mobile detail sheets could remain open across route changes because shell navigation could not reliably pop the modal sheet.
- Private profiles and lock: after cancelling or closing an overlay, an immediate private-profile access click could be swallowed during the post-sheet suppression window.
- App lock, second pass: the lock gate replaced the router child from `MaterialApp.router.builder`, leaving the locked screen without a local `Overlay`; this caused Tooltip/Overlay assertions and render overflow in Windows integration.
- Settings and sync UI: cloud sync detail controls and external link confirmation dialogs needed fake-cloud integration coverage.
- Core notes: quick memo, search, and tag flows worked, but Playwright assertions were stale against the current editor and Flutter Web semantics.
- Core notes, second pass: mobile and desktop stress flows exposed brittle navigation assumptions, filter dialog dismissal assumptions, and export dialog assertions.

## Fixes

- `_NoteDetailPager` now handles downward vertical drags on the detail header row and reuses the existing pull-to-dismiss feedback/threshold.
- The private-profile app-bar access button now remains truly disabled during the 450 ms post-sheet suppression window and re-enables through a timer, so rapid cancel-then-unlock clicks no longer disappear silently.
- The app-lock gate now renders the lock screen in its own `Overlay`, keeps the router child mounted behind the lock, and uses a vertical layout on narrow viewports to avoid horizontal overflow.
- Mobile note detail sheets now listen for shell close requests and close reliably during route changes; the widget test seeds state directly to avoid storage/demo-note race conditions.
- The note editor mode/media control row now uses a right-aligned flexible `Wrap`, preventing mobile overflow around attachment controls.
- `playwright/tests/app.spec.js` now matches the current UI:
  - Add note opens the editor directly.
  - Quick/Rich mode is selected through the mode menu.
  - Audio recording verification checks the attachment block controls instead of relying on label text exposure.
  - Settings assertions target currently visible collapsed section summaries.
- Tag/search E2E checks the note card via the accessible note-card role, allowing for Flutter Web semantics to expose the card as either a button or group.
- `integration_test/mobile_native_flows_test.dart` adds fake-cloud coverage for Google Drive sync detail controls, manual refresh/upload, re-upload confirmation, bundle history, and external help/legal/contact link dialogs.
- The integration scroll helper now searches both down and up so later settings assertions do not depend on the previous scroll position.
- `integration_test/profile_lock_flow_test.dart` now drives route changes through the router and no longer depends on stale navigation semantics.
- `package.json` now starts the Playwright static server on fixed `127.0.0.1:4173` without silent port switching.

## Validation

- `flutter analyze`: pass.
- `npm run e2e`: pass, 11/11.
- `flutter test test/security_storage_test.dart --reporter expanded`: pass, 40/40.
- `flutter test test/app_test.dart --reporter expanded`: pass, 33/33.
- `flutter test -d windows integration_test/mobile_native_flows_test.dart --reporter expanded`: pass, 2/2.
- `flutter test -d windows integration_test/profile_lock_flow_test.dart --reporter expanded`: pass, 1/1.
- Focused top-edge mobile detail drag retest on static web build: pass.
- Mixed attachment quick memo focused retest: pass by screenshot verification.

## Remaining Notes

- Full `integration_test/mobile_native_flows_test.dart` on Android currently fails before the new fake-cloud test because the emulator run cannot load `libsqlite3.so` from the debug APK path.
- Browser audio recording can still be sensitive to fake microphone startup timing in isolated local runs, but the full Playwright suite passed after server/build stabilization.
- Drift emits debug warnings in `test/app_test.dart` about multiple in-memory databases; tests pass and the warning is pre-existing harness noise.
