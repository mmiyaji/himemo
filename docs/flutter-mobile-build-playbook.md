# Flutter Mobile Build Playbook

このドキュメントは、Flutter アプリを Android / iOS で公開・運用するための実務メモです。HiMemo で実際に使っている構成をベースにしていますが、他の Flutter アプリでもそのまま参考にしやすい形に寄せています。

関連ドキュメント:
- [android-release-ops.md](/C:/Users/mail/Documents/git/himemo/docs/android-release-ops.md)
- [codemagic-ios.md](/C:/Users/mail/Documents/git/himemo/docs/codemagic-ios.md)
- [play-integrity-server.md](/C:/Users/mail/Documents/git/himemo/docs/play-integrity-server.md)

## 方針

- Android はローカル Windows 環境と CI の両方で検証する
- iOS は Windows 主体でも回せるように Codemagic を前提にする
- build / signing / publishing の設定はできるだけ repo 側に残す
- テストは 1 レイヤーに寄せず、複数レイヤーで分ける
- SDK やキャッシュなどの大きいファイルは可能なら D ドライブへ寄せる

## テストレイヤー

### 1. unit / widget test

用途:
- 純ロジック
- Provider / state
- UI の基本状態

基本コマンド:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test
```

### 2. `integration_test`

用途:
- Flutter レイヤーの通し確認
- 画面遷移
- 設定変更
- ノート作成や同期まわりの主要フロー

HiMemo で通しているもの:
- Windows desktop integration test
- Android emulator integration test

例:

```powershell
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\app_flow_test.dart -d windows
.\.fvm\flutter_sdk\bin\flutter.bat test integration_test\mobile_native_flows_test.dart -d emulator-5554 --flavor development
```

### 3. Playwright

用途:
- Web の black-box 回帰
- role / text / localization の確認

例:

```powershell
npm.cmd run e2e
```

### 4. Patrol

用途:
- モバイル固有 UI
- ダイアログ
- ネイティブ寄り挙動

HiMemo では雛形追加まで進めているが、実行レイヤーとしてはまだ育成途中。まずは `integration_test` を主軸にして、必要なモバイル固有ケースだけ Patrol を足す方針にしている。

### 5. Maestro

用途:
- さらに外側の black-box 確認
- smoke flow を YAML で固定

HiMemo では flow 追加まで。普段の主力テストではなく、将来のリグレッション監視用レイヤーとして扱う。

## 推奨ビルド順

### Android

1. `flutter analyze`
2. `flutter test`
3. Web E2E
4. desktop integration
5. Android integration
6. `flutter build apk`
7. `flutter build appbundle`

### iOS

1. Codemagic internal signed build
2. widget / extension を含めて IPA が生成できることを確認
3. TestFlight upload
4. 実機 smoke test

## Android の基本ルール

- package 名は `development` と `production` で分ける
- Firebase も flavor ごとに分ける
- observability は `release` で有効化する
- Play Integrity / App Check は高リスク操作だけに絞る
- SDK / Gradle / Pub cache / AVD は必要なら D ドライブへ逃がす

## iOS の基本ルール

- Windows 主体なら Codemagic を前提にする
- app と widget / extension は bundle ID と provisioning profile を分ける
- `codemagic.yaml` に build 方針を残す
- Apple API key は env var より Codemagic UI integration を優先する
- 最初は internal signed build を通してから TestFlight へ進む

## ディスク運用

大きくなりやすいもの:
- Android SDK
- AVD
- Gradle cache
- Pub cache
- `build/`

HiMemo では次を D ドライブに寄せている:
- `D:\Android\Sdk`
- `D:\Android\avd`
- `D:\CodexCaches\gradle`
- `D:\CodexCaches\PubCache`

必要に応じて junction を使う。

## 実務上の注意

- 生成物の `android/build/` はコミットしない
- flavor, bundle id, Firebase, signing は公開前に固定する
- iOS は App Store Connect の app record 作成前提で TestFlight を回す
- private / lock / sync のような機能は、機能追加後に integration test を増やしてから公開する

## HiMemo で特に重要だった点

- iCloud / Google Drive の同期は通常メモ利用と切り離し、オフライン主体を崩さない
- private profile の挙動は unit だけでなく integration で通す
- iOS build は Codemagic で、internal signed build と TestFlight を分離する
- Android は observability と Play Integrity を release 準備の一部として扱う
