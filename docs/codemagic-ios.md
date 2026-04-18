# Codemagic iOS Build Guide

このドキュメントは、Windows を主開発環境にした Flutter アプリで iOS ビルドを Codemagic に任せるときの実務メモです。HiMemo で実際に通した設定と、ハマりやすいポイントを残しています。

関連ファイル:
- [C:\Users\mail\Documents\git\himemo\codemagic.yaml](C:\Users\mail\Documents\git\himemo\codemagic.yaml)
- [C:\Users\mail\Documents\git\himemo\ios\Runner.xcodeproj\project.pbxproj](C:\Users\mail\Documents\git\himemo\ios\Runner.xcodeproj\project.pbxproj)
- [C:\Users\mail\Documents\git\himemo\ios\Podfile](C:\Users\mail\Documents\git\himemo\ios\Podfile)

## 方針

- iOS のローカル archive は前提にしない
- iOS は `codemagic.yaml` を正本にする
- app 本体と widget / extension は bundle ID と provisioning profile を分ける
- Apple の API key は `.p8` を環境変数に手貼りするより、Codemagic UI の integration を優先する
- 最初は `internal signed build` を通してから TestFlight に進む

## HiMemo の前提値

bundle ID:
- app: `org.ruhenheim.himemo`
- widget extension: `org.ruhenheim.himemo.QuickCaptureWidget`

Codemagic integration:
- `Codemagic HiMemo`

workflow:
- `ios-internal-production`
- `ios-testflight-production`

## Apple 側で必要なもの

最低限必要なもの:
- Apple Developer Program 加入
- App Store Connect API key
- App ID
  - `org.ruhenheim.himemo`
  - `org.ruhenheim.himemo.QuickCaptureWidget`
- Apple Distribution certificate
- Provisioning profile
  - App Store 用
    - app
    - widget
  - Ad Hoc 用
    - app
    - widget

HiMemo ではさらに次も設定しています。
- App Groups
  - `group.org.ruhenheim.himemo`
- iCloud / CloudKit
  - CloudKit を使う場合は capability 追加後に profile を再生成する

App Store Connect の app record:
- Name: `HiMemo Secure Notes`
- Bundle ID: `org.ruhenheim.himemo`
- Primary language: `Japanese`

## Codemagic の設定

### 1. Apple integration を先に作る

Codemagic の `Settings > Integrations` で App Store Connect API key を登録します。

HiMemo では:
- Integration 名: `Codemagic HiMemo`

この方式を使う理由:
- `.p8` の PEM 形式崩れを避けやすい
- `APP_STORE_CONNECT_PRIVATE_KEY` の改行事故を避けられる
- signing と publishing を同じ Apple 連携へ寄せられる

### 2. Code signing identities の reference 名を固定する

Codemagic UI で保存した reference 名と `codemagic.yaml` を必ず一致させます。

HiMemo の reference 名:
- certificate
  - `HiMemo Apple Distribution`
- App Store profile
  - `HiMemo App Store Profile`
  - `HiMemo Widget App Store Profile`
- Ad Hoc profile
  - `HiMemo Ad Hoc`
  - `HiMemo Widget Ad Hoc`

## codemagic.yaml の考え方

### iOS では Flutter flavor を無理に使わない

Android の `--flavor production` をそのまま iOS に持ち込まない方が安全です。
HiMemo では iOS 側に `production` scheme を作らず、entrypoint だけ production 用に切り替えています。

使う形:
- `-t lib/main_production.dart`

外すもの:
- `--flavor production`

### export options は manual profile 前提にする

`xcode-project use-profiles` で profile を解決した後に、export だけ `signingStyle: automatic` にすると IPA export で失敗しやすくなります。

HiMemo では:
- TestFlight: `{"method":"app-store"}`
- Internal: `{"method":"ad-hoc"}`

にしています。

### publishing は integration 認証に寄せる

HiMemo では:
- `integrations.app_store_connect: Codemagic HiMemo`
- `publishing.app_store_connect.auth: integration`

を使っています。

## 実際にハマったポイント

### 1. `project.pbxproj` の BOM

症状:
- `Invalid character "\xEF"`
- `... is not a valid Xcode project`

原因:
- `ios/Runner.xcodeproj/project.pbxproj` の先頭に UTF-8 BOM が入っていた

対策:
- BOM を除去する

### 2. `DEVELOPMENT_TEAM` 未設定

症状:
- `Failed to set code signing settings for ios/Runner.xcodeproj`

原因:
- project に team id が入っていない

HiMemo の team id:
- `B8LGAS7YHH`

### 3. Widget の `#Preview`

症状:
- `Preview(_:as:widget:timeline:) is only available in iOS 17.0 or newer`

原因:
- deployment target が低いのに iOS 17 preview を含めていた

対策:
- preview を削除する

### 4. profile の reference 名不一致

症状:
- `No provisioning profile with reference ... were found`

原因:
- Codemagic UI の profile 名と `codemagic.yaml` の参照名が違う

対策:
- reference 名を UI に合わせる

### 5. `.p8` を環境変数へ直接入れて publish 失敗

症状:
- `Provided value is not a valid PEM encoded private key`

原因:
- `.p8` の改行や PEM 形式を env var で壊した

対策:
- UI integration に寄せる

## 推奨の確認順

1. `ios-internal-production`
2. archive と export が通ることを確認
3. widget extension を含めて IPA ができることを確認
4. `ios-testflight-production`
5. App Store Connect upload
6. TestFlight で実機確認

## 他の Flutter アプリでも使えるルール

- iOS CI は YAML を正本にする
- app / extension / notification service は bundle ID と profile を分ける
- API key は UI integration を優先する
- capability を増やしたら profile を再生成する
- Xcode project は UTF-8 BOM を入れない
- Android flavor と iOS scheme は別概念として扱う
- まず internal build、次に TestFlight の順で切り分ける
