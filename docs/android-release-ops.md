# Android Release Ops

HiMemo Android 公開前後の運用メモです。公開運用は `production` flavor を前提にします。

## 導入済み

- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase App Distribution
- Play Integrity API の Android ブリッジ

## Firebase project

- Firebase project: `himemo-app-2026`
- Android package
  - production: `org.ruhenheim.himemo`
  - development: `org.ruhenheim.himemo.dev`

## Crashlytics

- Android で Firebase 初期化後に自動有効化
- `debug` では送信しない
- `release` で `FlutterError` と `PlatformDispatcher` の例外を送信
- ノート保存、同期の要所には breadcrumb / trace を追加済み

公開後は Play Console の crash/ANR と Firebase Crashlytics を両方見る。

## Performance Monitoring

- Android `release` で有効
- 自動 trace に加えて以下の custom trace を追加済み
  - `notes_upsert`
  - `notes_delete`
  - `sync_refresh_remote_status`
  - `sync_prepare_snapshot`
  - `sync_write_local_bundle`
  - `sync_read_local_bundle_payload`
  - `sync_upload_remote_bundle`
  - `sync_download_latest_bundle`
  - `sync_download_selected_bundle`
  - `sync_read_downloaded_bundle`

## App Distribution

Gradle plugin は導入済み。配布先や release notes は環境変数から渡す。

### 推奨環境変数

- `GOOGLE_APPLICATION_CREDENTIALS`
  - Firebase App Distribution Admin を持つ service account JSON
- `HIMEMO_APPDIST_GROUPS`
  - 例: `android-testers`
- `HIMEMO_APPDIST_TESTERS`
  - 例: `example1@example.com,example2@example.com`
- `HIMEMO_APPDIST_RELEASE_NOTES`
  - 1 行の release note
- `HIMEMO_APPDIST_RELEASE_NOTES_FILE`
  - release note ファイルパス

### 例

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\secrets\himemo-appdist.json"
$env:HIMEMO_APPDIST_GROUPS="android-testers"
$env:HIMEMO_APPDIST_RELEASE_NOTES="Internal QA build"
.\android\gradlew.bat appDistributionUploadProductionRelease
```

## Android vitals 運用

公開後は Play Console の Android vitals を定期確認する。

毎リリースで見るもの:

- Crash rate
- User-perceived crash rate
- ANR rate
- User-perceived ANR rate
- Excessive wakeups
- Stuck partial wake locks
- Battery / background behavior の警告

運用ルール:

- 段階ロールアウト中は 24 時間以内に vitals を確認
- Crash / ANR が悪化したら rollout を停止
- Crashlytics の stack trace と Play Console vitals の機種偏りをセットで見る

## Play Integrity

現状は Android 側で classic token request を発行できる状態です。

重要:

- これだけでは保護にならない
- token はサーバーで decode / verify して初めて意味がある
- 同期や機密機能に本適用する前に backend を用意する

Flutter 側の入口:

- `lib/app/play_integrity_service.dart`

Android 側の入口:

- `android/app/src/main/kotlin/org/ruhenheim/himemo/MainActivity.kt`

必要な次工程:

1. backend に token decode エンドポイントを追加
2. `requestHash` を API リクエスト単位で生成
3. 同期アップロードなど高リスク操作の直前に token を要求
4. サーバー判定が悪い場合は操作を止める

## リリース確認コマンド

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
npm.cmd run e2e
.\.fvm\flutter_sdk\bin\flutter.bat build appbundle --release --flavor production -t lib/main_production.dart
```
