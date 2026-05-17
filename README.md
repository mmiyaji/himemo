# HiMemo

HiMemo is a cross-platform private memo app built with Flutter for iOS, Android, and Web. The name is a quiet reference to "秘メモ": notes that can stay personal while still being quick to capture and easy to organize.

The app is local-first. Notes, attachments, private profiles, app lock settings, and sync state are stored on the user's device, with optional cloud sync and backup through services the user chooses.

## Current Features

- Fast note capture with a quick memo flow where the first line can become the title
- Notes, calendar, insights, and settings views
- Search, tags, pinning, archive-oriented organization, and date-based review
- Photo, video, audio, file, and location attachments
- Private profiles that open only when the entered password matches that profile
- Multi-profile lock behavior that avoids listing configured profile names or vault IDs in Settings
- App lock with PIN or device authentication where supported
- File backup/export for local archives
- Optional cloud sync with iCloud and Google Drive app-data storage
- Cloud recovery key handling for reading encrypted sync bundles on another device
- External quick memo entry points for widget/share-style capture flows
- Light, dark, and system theme support
- Localized UI and store assets for Japanese and English

## Store And Public Assets

- App Store screenshots and promotional composites are generated under `store-assets/app-store/`.
- Store listing copy is maintained in `store-assets/store-listing-copy.md`.
- The generator is `tools/store_assets/generate_app_store_screenshots.js`.
- Legal and help pages are under `docs/`.
- Release notes are stored in `assets/release_notes/release_notes.json`.

Generate store screenshots:

```powershell
node tools\store_assets\generate_app_store_screenshots.js
```

The generator builds the development web app, seeds localized demo data, captures iPhone/iPad screenshots, and renders promotional frames. It also includes a multi-profile lock screen because that is one of the app's key differentiators.

## Technical Stack

- Flutter / Dart
- Riverpod / riverpod_generator
- go_router
- Drift / SQLite
- shared_preferences
- flutter_secure_storage
- cryptography
- Firebase Crashlytics / Performance
- Google Drive API integration
- Playwright for Web E2E and store asset capture

## Setup

This repository expects FVM. The pinned Flutter version is defined in `.fvmrc`.

```powershell
$env:PATH += ";$env:LOCALAPPDATA\Pub\Cache\bin"
fvm flutter pub get
npm install
```

## Run

Development flavor:

```powershell
fvm flutter run -d chrome --flavor development -t lib/main_development.dart
fvm flutter run -d android --flavor development -t lib/main_development.dart
fvm flutter run -d ios -t lib/main_development.dart
```

Production flavor:

```powershell
fvm flutter run -d chrome -t lib/main_production.dart
fvm flutter run -d android --flavor production -t lib/main_production.dart
fvm flutter build apk --flavor production -t lib/main_production.dart
```

Web build:

```powershell
fvm flutter build web --no-wasm-dry-run -t lib/main_development.dart
npm run web:build
```

## Google Drive Sync For Local Builds

Create a local `.env` file from `.env.example` and set the Google OAuth client IDs. The `.env` file is ignored by git.

```powershell
Copy-Item .env.example .env
notepad .env
```

Run Flutter through the wrapper when those values need to be passed as `--dart-define` entries:

```powershell
.\tools\flutter_with_env.ps1 run -d emulator-5554 --flavor development -t lib/main_development.dart
.\tools\flutter_with_env.ps1 build apk --debug --flavor development -t lib/main_development.dart
```

For Web testing without OAuth, enable the fake Google Drive sync transport:

```powershell
fvm flutter run -d chrome --flavor development -t lib/main_development.dart --dart-define=HIMEMO_FAKE_GOOGLE_DRIVE_SYNC=true
```

## Tests

```powershell
fvm flutter test
fvm flutter test integration_test
npm run e2e
npm run e2e:headed
```

## Repository Layout

```text
lib/
  app/                     App startup, routing, lock gate, sync scheduling
  features/home/
    data/                  Seed data and stores
    domain/                Note, profile, vault, and sync models
    presentation/          Screens, widgets, and Riverpod controllers
  features/security/       Encrypted storage and key-value stores
  features/sync/           Sync bundle and transport logic
docs/                      Help, privacy policy, terms, and public support pages
internal-docs/             Release, build, and operations notes
store-assets/              Store screenshots and listing copy
tools/                     Build, sync, and store asset helper scripts
test/                      Unit and widget tests
integration_test/          Flutter integration tests
playwright/tests/          Web E2E tests
```

## Release Notes

The public 1.0.0 release is documented in `assets/release_notes/release_notes.json`. Keep it aligned with store listing copy and help pages whenever user-facing features change.
