# Android Release Ops

HiMemo の Android 公開前後に確認する項目です。公開運用は `production` flavor を基準にします。

## 導入済み機能

- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase App Distribution
- Play Integrity API
- Firebase App Check
- In-app updates

## Firebase project

- Firebase project
  - `himemo-app-2026`
- Android package
  - production: `org.ruhenheim.himemo`
  - development: `org.ruhenheim.himemo.dev`

## Crashlytics

- Android で Firebase 初期化後に有効化
- `debug` では送信しない
- `release` で `FlutterError` と `PlatformDispatcher` の例外を送信
- ノート保存と同期処理の主要箇所で breadcrumb / custom trace を追加

公開後は Play Console の crash / ANR と Crashlytics の両方を見ます。

## Performance Monitoring

- Android `release` で有効
- 次の custom trace を記録
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

Gradle plugin は導入済みです。実配布には service account と配布先指定が必要です。

### 必要な環境変数

- `GOOGLE_APPLICATION_CREDENTIALS`
  - Firebase App Distribution Admin 権限を持つ service account JSON
- `HIMEMO_APPDIST_GROUPS`
  - 例: `android-testers`
- `HIMEMO_APPDIST_TESTERS`
  - 例: `example1@example.com,example2@example.com`
- `HIMEMO_APPDIST_RELEASE_NOTES`
  - 1 行の release note
- `HIMEMO_APPDIST_RELEASE_NOTES_FILE`
  - release note ファイルのパス

### 例

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\secrets\himemo-appdist.json"
$env:HIMEMO_APPDIST_GROUPS="android-testers"
$env:HIMEMO_APPDIST_RELEASE_NOTES="Internal QA build"
.\android\gradlew.bat appDistributionUploadProductionRelease
```

## Android vitals の運用

公開後は Play Console の Android vitals を継続監視します。

重点項目:

- Crash rate
- User-perceived crash rate
- ANR rate
- User-perceived ANR rate
- Excessive wakeups
- Stuck partial wake locks
- バッテリー / background behavior

運用ルール:

- 公開直後 24 時間は vitals を重点確認
- Crash / ANR が悪化したら rollout を止める
- Crashlytics の stack trace と Play Console vitals の傾向をセットで見る

## Play Integrity と App Check

### 役割

- `Play Integrity`
  - Android 端末が Google Play 配布の正規アプリかを確認
- `Firebase App Check`
  - backend endpoint へのアクセス元を Firebase 登録アプリに寄せる

### 現在の適用箇所

Play Integrity はクラウド同期を最初に有効化するときだけ使います。通常のオフラインメモ操作には使いません。

### Flutter 側

- production
  - `AndroidProvider.playIntegrity`
- development
  - `AndroidProvider.debug`

development では Firebase Console に表示される debug token を App Check に登録する必要があります。

関連:

- [C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart](C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart)
- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart)
- [C:\Users\mail\Documents\git\himemo\docs\play-integrity-server.md](C:\Users\mail\Documents\git\himemo\docs\play-integrity-server.md)

## Quick Capture の注意

ホームウィジェットや外部共有からの `quick capture` は、通常のアプリロックを開かずに `Daily Notes` へテキストだけを書き込みます。

これは利便性のための例外導線です。公開前に次を確認します。

- 既定値は `off`
- private vault へは書き込まない
- 既存ノートや秘密データは開かない
- 設定画面に注意書きがある

## リリース確認コマンド

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
npm.cmd run e2e
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\app_flow_test.dart -d windows
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\mobile_native_flows_test.dart -d emulator-5554 --flavor development
.\.fvm\flutter_sdk\bin\flutter.bat build appbundle --release --flavor production -t lib/main_production.dart
```
