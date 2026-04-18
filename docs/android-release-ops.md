# Android Release Ops

このドキュメントは、HiMemo の Android 公開準備と日常運用のメモです。Firebase、Play Integrity、App Check、E2E、ディスク運用まで含めて整理しています。

## パッケージと Firebase

Firebase project:
- `himemo-app-2026`

Android package:
- production: `org.ruhenheim.himemo`
- development: `org.ruhenheim.himemo.dev`

## 現在入れている公開運用機能

- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase App Distribution
- Firebase App Check
- Play Integrity API
- In-app updates
- Android vitals を見る運用

## Crashlytics

方針:
- `debug` では送信しない
- `release` で送信する
- `FlutterError` と `PlatformDispatcher` の例外を送る

HiMemo では、ノート保存と同期処理に breadcrumb / trace を入れています。

運用:
- Play Console の crash / ANR と Crashlytics を合わせて見る
- rollout 初日は vitals を優先監視する

## Performance Monitoring

release のみ有効です。

HiMemo の custom trace:
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

Gradle plugin は導入済みです。配布時に使う主な環境変数:
- `GOOGLE_APPLICATION_CREDENTIALS`
- `HIMEMO_APPDIST_GROUPS`
- `HIMEMO_APPDIST_TESTERS`
- `HIMEMO_APPDIST_RELEASE_NOTES`
- `HIMEMO_APPDIST_RELEASE_NOTES_FILE`

例:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\secrets\himemo-appdist.json"
$env:HIMEMO_APPDIST_GROUPS="android-testers"
$env:HIMEMO_APPDIST_RELEASE_NOTES="Internal QA build"
.\android\gradlew.bat appDistributionUploadProductionRelease
```

## Android vitals

公開後に最低限見る指標:
- Crash rate
- User-perceived crash rate
- ANR rate
- User-perceived ANR rate
- Excessive wakeups
- Stuck partial wake locks

運用ルール:
- 公開 24 時間は vitals を優先確認する
- Crash / ANR が悪化したら rollout を止める
- Crashlytics の stack trace と Play Console vitals をセットで見る

## Play Integrity と App Check

### 役割分担

- Play Integrity
  - Google Play 配布アプリとしての整合性確認
- Firebase App Check
  - backend endpoint へのアクセス元確認

### HiMemo の方針

- 基本はオフラインメモ
- 毎回の通常メモ操作に Play Integrity は使わない
- 高リスク操作だけに絞る
- 現在は `クラウド同期の初回有効化` だけで検証する

### App Check

Flutter 側:
- production: `AndroidProvider.playIntegrity`
- development: `AndroidProvider.debug`

development では Firebase Console に debug token 登録が必要です。

関連:
- [C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart](C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart)
- [C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart](C:\Users\mail\Documents\git\himemo\lib\app\play_integrity_verifier.dart)
- [C:\Users\mail\Documents\git\himemo\docs\play-integrity-server.md](C:\Users\mail\Documents\git\himemo\docs\play-integrity-server.md)

## Quick Capture のセキュリティ方針

ホーム画面ウィジェットからの `quick capture` は:
- 通常領域の `Daily Notes` にのみ保存
- private 領域には保存しない
- 初期値は `off`
- 設定画面から明示的に有効化する

これは「通常メモへの最小入力口」であり、ロック領域とは分ける前提です。

## Android テストコマンド

HiMemo で実際に回している主なコマンド:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat analyze
.\.fvm\flutter_sdk\bin\flutter.bat test
npm.cmd run e2e
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\app_flow_test.dart -d windows
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\mobile_native_flows_test.dart -d emulator-5554 --flavor development
.\.fvm\flutter_sdk\bin\flutter.bat build appbundle --release --flavor production -t lib/main_production.dart
```

## ディスクとキャッシュ運用

Windows では Android / Flutter のキャッシュで C ドライブが膨らみやすいので、HiMemo では D ドライブへ逃がしています。

現在の配置:
- Android SDK: `D:\Android\Sdk`
- Android AVD: `D:\Android\avd`
- Gradle user home: `D:\CodexCaches\gradle`
- Pub cache: `D:\CodexCaches\PubCache`

元の場所:
- `C:\Users\mail\.gradle`
- `C:\Users\mail\AppData\Local\Pub\Cache`

は junction にしています。

ルール:
- 大きな build 後は `build/` を消す
- AVD と SDK は C に置かない
- `.gradle` と `Pub\Cache` も D に寄せる

## 他の Flutter アプリでも使えるルール

- package 名と Firebase app 登録は flavor ごとに分ける
- Crashlytics と Performance は release だけにする
- App Check / Integrity は毎操作ではなく高リスク操作に限定する
- Play Console vitals を release 直後の主監視にする
- SDK / AVD / Gradle / Pub cache は大きいので D ドライブへ逃がす
- Windows では emulator と integration_test を別レイヤーで定期実行する
