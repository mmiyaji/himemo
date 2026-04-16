# Codemagic iOS Build Setup

HiMemo は Windows 上で日常開発していますが、iPhone 向け IPA ビルドと TestFlight 配布は Codemagic の macOS ビルドで回せます。

設定ファイル:

- [C:\Users\mail\Documents\git\himemo\codemagic.yaml](C:\Users\mail\Documents\git\himemo\codemagic.yaml)

対象 bundle ID:

- app
  - `org.ruhenheim.himemo`
- widget extension
  - `org.ruhenheim.himemo.QuickCaptureWidget`

Codemagic では親 bundle ID を指定すると extension の署名ファイルも一緒に解決される前提です。

## 用意するもの

1. Apple Developer Program 加入済みアカウント
2. App Store Connect API key
3. `org.ruhenheim.himemo` の App ID
4. `org.ruhenheim.himemo.QuickCaptureWidget` の App ID
5. App と widget extension の provisioning profile
6. 配布用 certificate

## Codemagic 側で必要な設定

### Environment group

Codemagic の `Environment variables` で `app_store_connect` という group を作り、少なくとも次を入れます。

- `APP_STORE_CONNECT_PRIVATE_KEY`
- `APP_STORE_CONNECT_KEY_IDENTIFIER`
- `APP_STORE_CONNECT_ISSUER_ID`

## ワークフロー

### 1. iOS TestFlight (Production)

目的:

- `production` flavor を IPA 化
- TestFlight へ送る

使う workflow:

- `ios-testflight-production`

主な流れ:

1. `flutter pub get`
2. `pod install`
3. `xcode-project use-profiles`
4. `flutter build ipa --release --flavor production -t lib/main_production.dart`
5. TestFlight へ publish

### 2. iOS Internal Signed Build

目的:

- App Store 提出前に署名済み IPA を確認する

使う workflow:

- `ios-internal-production`

これは `ad_hoc` 署名前提です。端末配布や社内検証用に使います。

## Podfile

このリポジトリには Windows 開発由来で `ios/Podfile` が無かったため、Codemagic 用に標準 Podfile を追加しています。

- [C:\Users\mail\Documents\git\himemo\ios\Podfile](C:\Users\mail\Documents\git\himemo\ios\Podfile)

Codemagic では `pod install` を明示実行します。

## Firebase について

現時点の iOS 側は Firebase の本初期化をまだ入れていません。

- `firebase_core` は依存にあります
- ただし [C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart](C:\Users\mail\Documents\git\himemo\lib\app\firebase_initializer.dart) は Android のみ初期化します

そのため、iOS ビルドを通すだけなら `GoogleService-Info.plist` は必須ではありません。今後 iOS でも Crashlytics / Performance を使うなら追加設定が必要です。

## 公開前チェック

1. Codemagic で `ios-internal-production` を 1 回回す
2. widget extension の署名が通ることを確認する
3. `ios-testflight-production` を回して TestFlight へ上がることを確認する
4. 実機で
   - 起動
   - quick capture widget
   - language/theme
   - rich memo / media
   - app lock
   を確認する

## 補足

- Apple の提出要件変更に合わせて、Codemagic 側の Xcode image は `latest` を使っています
- iOS 側はまだこの Windows 環境でローカル archive 検証していません。最初の信頼できる検証は Codemagic build result になります
