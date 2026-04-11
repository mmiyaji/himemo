# HiMemo

Flutter で構築するクロスプラットフォームのメモアプリ試作です。対象は `iOS (iPhone / iPad)` `Android` `Web` です。

この初期実装では、次の方向性をコードに落としています。

- 普段使いのメモと日記を中心にしたシンプルUI
- 解除方式ごとに見えるメモ領域が変わる「通常表示 / カバー表示 / 機密表示」の設計デモ
- 写真・動画を含むダミーメモの表現
- `fvm` で Flutter SDK をプロジェクト固定

## Run

```powershell
$env:PATH += ";$env:LOCALAPPDATA\Pub\Cache\bin"
fvm flutter pub get
fvm flutter run -d chrome --flavor development -t lib/main_development.dart
```

モバイル向け確認例:

```powershell
fvm flutter run -d android --flavor development -t lib/main_development.dart
fvm flutter run -d ios -t lib/main_development.dart
```

本番 flavor の例:

```powershell
fvm flutter run -d chrome -t lib/main_production.dart
fvm flutter run -d android --flavor production -t lib/main_production.dart
fvm flutter build apk --flavor production -t lib/main_production.dart
```

## SDK management

このリポジトリは `.fvmrc` で `Flutter 3.41.6` に固定しています。グローバルの `flutter` ではなく、基本的に `fvm flutter ...` を使う前提です。

## Flavors

Flutter entrypoint は次の 2 つです。

- `lib/main_development.dart`
- `lib/main_production.dart`

Android では `development` / `production` の `productFlavor` を定義しています。

- `development`
  `applicationIdSuffix ".dev"` を付与し、アプリ名は `HiMemo Dev`
- `production`
  本番用のアプリ ID / 表示名

デバッグ時のリボンは [`flutter_flavor`](https://pub.dev/packages/flutter_flavor) を使っています。`debug` ビルドでのみ `DEV` / `PROD` のリボンが表示されます。

## Current structure

- `lib/app`
  アプリ設定とテーマ。
- `lib/features/home/domain`
  メモ、添付、表示領域、解除プロファイルのモデル。
- `lib/features/home/presentation`
  ホーム画面と簡易 ViewModel。

## Important product notes

このアプリの中核要件である「解除パスワードによって別のメモを見せる」仕様は、公開配布時にかなり慎重な整理が必要です。

- Apple / Google の審査では、説明されていない hidden functionality や deceptive behavior と判断される余地があります。
- そのため、まずは `公開ストア向け版` と `個人配布や検証向け版` を分けて考える前提が安全です。
- 法的な適法性は国・用途・保存データ次第なので、公開前に弁護士確認が必要です。特にプライバシー表示、暗号化の説明、ストア申請時の機能説明は要確認です。

## Encryption and sync roadmap

このリポジトリにはまだ本番用暗号化は入れていません。理由は、中途半端な暗号化を「実装済み」と見せる方が危険だからです。次の順番を推奨します。

1. ローカル保存を `encrypted envelope` 方式に切り替える。
2. 通常PIN / 秘密PIN / デコイPIN で鍵導出を分離する。
3. 添付ファイルも本文と別鍵で暗号化する。
4. クラウド同期は暗号化後の blob のみを送る。

同期候補:

- `iCloud (CloudKit)`:
  Apple寄りだが Android が難しい。
- `Google Drive / Firebase`:
  Android と Web の足場は強いが、秘密メモ用途ではサーバ側に平文を置かない設計が必須。
- `独自E2EE同期層`:
  実装コストは高いが、要件との整合は最も取りやすい。

現時点の推奨は、`Web は確認用`、`本番データは iOS / Android 優先`、`同期は E2EE 前提で後付け` です。
