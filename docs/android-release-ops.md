# Android Release Ops

このドキュメントは、HiMemo の Android 公開準備と日常運用の要点をまとめたものです。Firebase、Play Integrity、E2E、ディスク運用まで含めています。

## パッケージと Firebase

Firebase project:
- `himemo-app-2026`

Android package:
- production: `org.ruhenheim.himemo`
- development: `org.ruhenheim.himemo.dev`

基本方針:
- flavor ごとに package 名を分ける
- Firebase も flavor ごとに登録する
- `google-services.json` は flavor ごとに置く

## 公開前に入れている機能

- Firebase Crashlytics
- Firebase Performance Monitoring
- Firebase App Distribution
- Firebase App Check
- Play Integrity API
- In-app updates
- Android vitals を見る運用

## Crashlytics

方針:
- `debug` では送らない
- `release` で送る
- `FlutterError` と `PlatformDispatcher` の例外を拾う

HiMemo ではノート保存や同期まわりに breadcrumb / trace を入れている。

運用:
- Play Console の crash / ANR と Crashlytics を突き合わせる
- rollout 直後は vitals を最優先で確認する

## Performance Monitoring

release のみ有効。

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

Gradle plugin は導入済み。実配布時に使う主な環境変数:
- `GOOGLE_APPLICATION_CREDENTIALS`
- `HIMEMO_APPDIST_GROUPS`
- `HIMEMO_APPDIST_TESTERS`
- `HIMEMO_APPDIST_RELEASE_NOTES`
- `HIMEMO_APPDIST_RELEASE_NOTES_FILE`

例:

```powershell
$env:GOOGLE_APPLICATION_CREDENTIALS="D:\secrets\himemo-appdist.json"
.\gradlew.bat appDistributionUploadProductionRelease
```

## App Check

方針:
- production は強い provider を使う
- development は debug token で許可する
- backend 側でも App Check を必須にする

注意:
- debug token 登録前の development build は `app-check-required` で落ちる

## Play Integrity

方針:
- 毎回の通常利用には掛けない
- 高リスク操作に限定する
- challenge は server-side で発行する
- verify も server-side で行う

HiMemo では、クラウド同期を有効化する最初の操作に寄せて使っている。通常のローカルメモ利用はオフライン主体のままにする。

関連:
- [play-integrity-server.md](/C:/Users/mail/Documents/git/himemo/docs/play-integrity-server.md)

## In-app updates

Google Play 配布前提で使う。独自 updater は作らず、Play の仕組みに寄せる。

## Android vitals の見方

公開後に必ず見るもの:
- crash rate
- ANR rate
- startup
- slow rendering

見る順:
1. internal testing
2. closed testing
3. small production rollout
4. vitals と Crashlytics を確認
5. 問題なければ段階的に rollout 拡大

## 推奨検証順

1. `flutter analyze`
2. `flutter test`
3. `npm run e2e`
4. Windows integration test
5. Android integration test
6. `flutter build apk`
7. `flutter build appbundle`

実際に使っている例:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\mobile_native_flows_test.dart -d emulator-5554 --flavor development
.\.fvm\flutter_sdk\bin\flutter.bat build apk --debug --flavor development -t lib/main_development.dart
.\.fvm\flutter_sdk\bin\flutter.bat build appbundle --release --flavor production -t lib/main_production.dart
```

## ディスク運用

大きくなりやすいもの:
- `Android\Sdk`
- `AVD`
- `.gradle`
- `Pub\Cache`
- `build/`

HiMemo では次を D ドライブへ移している:
- `D:\Android\Sdk`
- `D:\Android\avd`
- `D:\CodexCaches\gradle`
- `D:\CodexCaches\PubCache`

必要に応じて junction を使う。

## 実務上の注意

- `android/build/` は生成物なのでコミットしない
- package 名は Play 公開前に固定する
- Firebase package 登録と `applicationId` をずらさない
- private / profile / sync の仕様変更後は integration test を追加してから公開する
