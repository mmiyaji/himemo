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

Security verifier stores live in `features/security/data/`. Key providers and
profile-store composition are in `features/security/presentation/`; sync providers
and controllers are in `features/sync/presentation/`. These presentation files
remain parts of the home provider library so existing Riverpod consumers and
generated providers keep their public API during the incremental extraction.

Key creation/import is serialized per storage namespace and key within one Dart
isolate, including separate service instances. This is not a distributed lock
between devices. Invalid stored keys are reported rather than replaced. Display
of recovery-key information must use the `existing*` methods, never create a key.

App-managed PIN/password verification backs off after five failed attempts
(30 seconds, doubling to at most one hour). Native counters use secure storage;
OS device authentication retains its own policy. Keep scratch logs under
`.codex/logs/` (ignored); do not reset personal `.vscode` settings during cleanup.

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


### 同期履歴とWebデモの制約

Web版は操作確認用のデモです。ブラウザのlocalStorageに全メモと最新の暗号化同期バンドルを保存するため、保存容量はブラウザの上限に制約されます。大きな添付や永続的な保管にはネイティブ版を使用してください。

新しい全件バンドルには、取り込み済みのバンドルIDを暗号化して記録します。履歴のメタデータを全ページ取得し、未適用のIDを更新時刻の位置にかかわらず取り込みます。整理では全件バンドルが明示的に包含するIDだけを削除し、同時公開などで未包含のバンドルは残します。

iCloudとGoogle Driveの添付は、新形式の送信予約で公開前から保護します。整理時には、残存バンドルから参照されず、送信予約がなく、更新から7日以上経過した新形式の添付だけを回収します。削除直前にサーバー上の世代を条件付き更新し、途中で他端末が予約した場合は削除を中止します。公開済みの予約はバンドル内の公開証跡で回復できます。公開結果が確認できない予約と、予約に対応していない旧形式の添付は安全のため残します。利用する全端末を更新してから同期・整理してください。

旧形式の添付は、同期中に新形式へコピーせず、既存のオブジェクトをそのまま参照します。更新後の全件アップロードを理由とする添付の移行ダウンロード・二重保存は行いません。新形式の添付は安全な公開のため参照ごとに予約するので、全件アップロードの処理量は添付数に比例します。通常の同期では変更対象を処理し、Driveの管理一覧はページ単位で取得します。公開証跡は空結果も含め端末にキャッシュし、未解決の予約が残っても同じ履歴を毎回ダウンロード・復号しません。削除時の世代照合は維持します。

**この同期形式は旧版と混在できません。** 旧版iOSの整理処理は新形式の管理添付を削除する可能性があり、旧版Androidは新形式の添付を取得できません。配布前に利用端末を確認し、全端末で旧版の同期・整理を停止してから更新し、更新完了後に同期を再開してください。この運用で管理できない公開配布では、互換性を保つ移行方式が必要です。

Windowsで添付同期のブラウザ回帰テストを実行する場合は `./tools/test_sync_browser.ps1` を使用します。固定済みSDKのCanvasKitをテスト中だけ静的配信し、終了時に一時ファイルを削除します。WindowsではSQLiteのDLLを共有するため、通常のFlutterテストと同時に実行しないでください。

除外タグを含む全件バックアップでは、除外・未保持メモのIDと、そのクラウド上の版を保持するバンドルIDを暗号化されたバックアップ内に記録します。整理はそれらの保存先を残し、新しい端末は指定されたメモだけを保存先から追加取得します。除外中に端末で加えた変更はアップロードしません。

PBKDF2を使う重いテスト群はライブラリ単位のタイムアウトを2分に設定しています。CIの単体・ウィジェットテストは `--concurrency=2` で実行します。
