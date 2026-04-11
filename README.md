# HiMemo

HiMemo は、Flutter で作られたクロスプラットフォームのメモアプリ試作です。対象は `iOS` `Android` `Web` で、複数の unlock profile に応じて表示する vault を切り替えるローカルファースト構成になっています。

現状はプロトタイプ段階で、ノート作成体験、プロフィール切り替え、ローカル保存、テーマ切り替え、Web E2E テスト基盤までを含みます。クラウド同期や実ファイル暗号化はまだ未実装です。

## できること

- Notes / Calendar / Settings の 3 画面を `go_router` で遷移
- unlock profile の切り替えに応じて見える vault / note を変更
- メモの作成、編集、削除、検索、ピン留め
- 作成日の変更
- 添付ファイルのプレースホルダー追加
  - `photo`
  - `video`
  - `audio`
- `shared_preferences` を使った端末内保存
- Light / System / Dark テーマ切り替え
- 開発用 / 本番用 flavor の切り替え

## 技術スタック

- Flutter
- Riverpod / riverpod_generator
- go_router
- freezed / json_serializable
- shared_preferences
- Playwright

## セットアップ

このリポジトリは `fvm` 前提です。.fvmrc では `Flutter 3.41.6` を指定しています。

```powershell
$env:PATH += ";$env:LOCALAPPDATA\Pub\Cache\bin"
fvm flutter pub get
npm install
```

## 実行

### 開発用 flavor

```powershell
fvm flutter run -d chrome --flavor development -t lib/main_development.dart
```

他ターゲット:

```powershell
fvm flutter run -d android --flavor development -t lib/main_development.dart
fvm flutter run -d ios -t lib/main_development.dart
```

### 本番用 flavor

```powershell
fvm flutter run -d chrome -t lib/main_production.dart
fvm flutter run -d android --flavor production -t lib/main_production.dart
fvm flutter build apk --flavor production -t lib/main_production.dart
```

## テスト

### Flutter テスト

```powershell
fvm flutter test
```

### Flutter integration test

```powershell
fvm flutter test integration_test
```

### Web E2E

Playwright は開発 flavor の Web ビルドを起動して検証します。

```powershell
npm run e2e
```

ヘッドあり実行:

```powershell
npm run e2e:headed
```

## ディレクトリ構成

```text
lib/
  app/                     アプリ初期化、flavor、router
  features/home/
    data/                  seed repository
    domain/                note / vault のモデル
    presentation/          画面、provider、状態管理
test/                      widget / provider テスト
integration_test/          Flutter integration test
playwright/tests/          Web E2E
```

## Flavors

entrypoint は 2 つあります。

- `lib/main_development.dart`
- `lib/main_production.dart`

Android では `development` / `production` の `productFlavor` を使っています。

- `development`
  - アプリ名: `HiMemo Dev`
  - debug 時は `DEV` バナーを表示
- `production`
  - アプリ名: `HiMemo`
  - debug 時は `PROD` バナーを表示

## 現状の制約

- 永続化は端末ローカルのみ
- 実ファイルの添付は未対応で、添付はプレースホルダー表示のみ
- クラウド同期、E2EE、鍵管理は roadmap 段階
- seed データを元に挙動を確認する前提のプロトタイプ

## 補足

README は実装に合わせて更新していますが、プロダクト方針に関わる仕様はコードを正として扱ってください。特に挙動確認が必要な場合は以下を先に見ると早いです。

- `lib/features/home/presentation/home_page.dart`
- `lib/features/home/presentation/home_providers.dart`
- `playwright/tests/app.spec.js`
