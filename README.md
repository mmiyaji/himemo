# HiMemo

HiMemo is a Flutter private memo app. This development branch connects the existing note UI to Sync v2. Native CloudKit transport currently supports iOS. Web is a local development preview; Android cloud sync is not implemented by the current transport. Windows native apps are unsupported.

## Current Features

- Quick and rich notes, search, tags, pinning, archive, calendar, insights, and trash
- Photo, video, audio, file, and location attachments
- Private profiles opened by matching passcodes; profiles with the same passcode open together
- Administrator access to all profiles, with a device-local administrator passcode or biometrics
- App lock with PIN or device authentication where supported
- Encrypted Sync v2 history and attachment chunks through iCloud
- Device enrollment using a combined QR code or recovery file
- Widget and share capture into the normal profile
- Light, dark, and system themes with localized UI

Notes and attachment drafts are encrypted locally. Sync settings are under **Sync and security**. Synchronization is automatic; **Sync now** becomes **Retry sync** after a failure. Individual legacy upload/download/repair controls, ZIP backups, Google Drive sync, and sync exclusion tags have been retired. This branch does not migrate old data or announce a store release.

## Setup

The pinned Flutter version is defined in `.fvmrc`. Install it through FVM, then run:

```powershell
fvm flutter pub get
fvm flutter gen-l10n
npm install
```

`.env.example` contains optional store/build metadata. `tools/flutter_with_env.ps1` passes supported values to Flutter. Google OAuth configuration is no longer used.

## Run

Local Web preview:

```powershell
fvm flutter run -d chrome -t lib/main_development.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
```

Build the preview for a local server:

```powershell
fvm flutter build web --no-wasm-dry-run -t lib/main_development.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
python -m http.server 8765 --bind 127.0.0.1 --directory build/web
```

`v2-local` uses an isolated browser database, in-process registration/transport, and keys held only in memory. Reloading loses those keys. It is permitted only in the development flavor. The normal backend defaults to `v2`; unsupported values, including `v1`, are rejected.

On a Mac with the iOS toolchain and signing configured:

```powershell
fvm flutter run -d ios -t lib/main_development.dart
```

## Tests

```powershell
fvm flutter gen-l10n
fvm flutter analyze --fatal-infos
fvm flutter test test --concurrency=2
node --test test/sync_v2_cloudkit_web_test.js
npm run e2e
```

Run Flutter builds, tests, localization, and code generation sequentially. After a Web build, regenerate localization before analysis if needed. Native iOS integration tests require the corresponding simulator/device environment; do not run Windows native app tests.

For the encrypted save/recovery browser smoke, build `tools/v2_web_local_preview.dart` with the same v2-local flag, serve it locally, then run `node tools/check_v2_local_preview.cjs http://127.0.0.1:8765/`.

Unit/widget and two-store tests cover protocol and UI behavior. Actual CloudKit, biometrics, camera scanning, and media playback still require [iOS acceptance checks](internal-docs/sync-v2-acceptance.md). Build/simulator CI does not replace physical-device acceptance. Performance measurements and their limits are in [sync-v2-performance.md](internal-docs/sync-v2-performance.md).

## Architecture

- Flutter/Dart, Riverpod, go_router, Drift/SQLite, cryptography, secure storage, Firebase observability, and Playwright
- `lib/features/home/data/note_store.dart`: UI persistence interface
- `lib/features/sync/data/`: encrypted immutable history, latest-state projection, attachments, and CloudKit transport
- `lib/features/sync/presentation/`: workspace, enrollment, synchronization, and device security settings
- `lib/features/security/`: profile keys, local administrator credentials, biometrics, and app lock
- `lib/features/home/presentation/`: shared note UI and controllers

Sync v2 profile keys use format version 3 and Argon2id with 19MiB memory, two iterations, and one lane. Passcodes require at least four characters. Administrator/passcode duplication is rejected; profile-to-profile duplication is allowed. Failed profile and administrator passcode attempts share the documented delay schedule. See [the unified UI design](internal-docs/sync-v2-unified-ui-design.md) and [handoff/status](internal-docs/codex-handoff-v2-on-v1-ui.md).

## Store And Public Assets

Store assets are under `store-assets/`, listing copy is in `store-assets/store-listing-copy.md`, and the screenshot source is `tools/store_assets/generate_app_store_screenshots.js`. Legal/help pages are under `docs/`; release notes are in `assets/release_notes/release_notes.json`. Existing public material describes the released app and should be reconciled before a new release.

The screenshot generator requires a development/v2-local build, including when reusing an existing server. It creates profile fixtures through the UI and avoids reloading memory-only keys. Full screenshot generation was not rerun during this migration; existing generated assets were preserved.
