# Codemagic iOS Build Guide

このドキュメントは、Windows 主体で Flutter アプリの iOS ビルドを回すための Codemagic 設定メモです。HiMemo で実際に通した構成を整理しています。

関連ファイル:
- [codemagic.yaml](/C:/Users/mail/Documents/git/himemo/codemagic.yaml)
- [ios/Runner.xcodeproj/project.pbxproj](/C:/Users/mail/Documents/git/himemo/ios/Runner.xcodeproj/project.pbxproj)
- [ios/Podfile](/C:/Users/mail/Documents/git/himemo/ios/Podfile)

## 方針

- iOS のローカル archive は前提にしない
- `codemagic.yaml` を正として build 設定を repo に残す
- app 本体と widget / extension は別 bundle id と別 profile で扱う
- Apple API key は environment variable 直貼りより Codemagic の integration を優先する
- 最初は internal signed build を通してから TestFlight に進む

## HiMemo の識別子

bundle ID:
- app: `org.ruhenheim.himemo`
- widget extension: `org.ruhenheim.himemo.QuickCaptureWidget`

App Group:
- `group.org.ruhenheim.himemo`

Codemagic integration:
- `Codemagic HiMemo`

workflow:
- `ios-internal-production`
- `ios-testflight-production`

## Apple 側で必要なもの

最低限必要:
- Apple Developer Program
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

HiMemo で追加したもの:
- App Groups
  - `group.org.ruhenheim.himemo`
- iCloud / CloudKit
  - CloudKit を使う場合は capability 追加後に profile を再生成する

App Store Connect app record:
- Name: `HiMemo Secure Notes`
- Bundle ID: `org.ruhenheim.himemo`
- Primary language: `Japanese`

## Codemagic 側の設定

### 1. Apple integration

Codemagic の UI で Apple Developer Portal integration を追加する。HiMemo では `Codemagic HiMemo` を使っている。

理由:
- `.p8` を env var に直接貼るより壊れにくい
- build と publish の両方で同じ integration を使える

### 2. Signing

登録するもの:
- certificate
  - `HiMemo Apple Distribution`
- App Store profile
  - `HiMemo App Store Profile`
  - `HiMemo Widget App Store Profile`
- Ad Hoc profile
  - `HiMemo Ad Hoc`
  - `HiMemo Widget Ad Hoc`

### 3. Build workflow

最初に回す:
- `ios-internal-production`

目的:
- signing
- archive
- IPA export
- widget extension を含む build 成功確認

次に回す:
- `ios-testflight-production`

目的:
- App Store profile で archive / export
- App Store Connect / TestFlight upload

## HiMemo で実際に詰まった点

### 1. `DEVELOPMENT_TEAM`

Codemagic の code signing step では Xcode project に Team ID が入っていないと失敗しやすい。HiMemo では `project.pbxproj` に Team ID `B8LGAS7YHH` を入れている。

### 2. BOM 付き `project.pbxproj`

UTF-8 BOM が入ると Codemagic の `xcode-project use-profiles` が Xcode project として読めず失敗する。`project.pbxproj` は BOM なしで保存する。

### 3. profile reference 名

`codemagic.yaml` 側の profile reference は、Codemagic UI に登録した名前と一致している必要がある。

### 4. `--flavor` 指定

iOS の Xcode scheme が `Runner` ベースなら、Flutter の `--flavor production` は不要なことがある。HiMemo では iOS build から `--flavor production` を外し、entrypoint だけ `lib/main_production.dart` にしている。

### 5. iOS 17 `#Preview`

Widget extension 内の `#Preview` は archive で落ちる場合がある。古い deployment target と混ざるなら削除する。

### 6. export 時の signing

archive が通っても `exportArchive No profiles were found` で落ちることがある。HiMemo では `signingStyle: automatic` を外し、Codemagic が解決した profile を使う形に寄せた。

## 推奨確認順

1. internal signed build
2. IPA artifact の生成確認
3. TestFlight workflow
4. 実機インストール
5. widget / iCloud / private profile の smoke test

## 公開前に確認するもの

- app record が App Store Connect にある
- bundle id が app / widget ともに一致している
- profile が capability 追加後の最新状態で再生成されている
- TestFlight build が処理完了する
- 実機で起動、widget、private profile、同期が最低限動く
