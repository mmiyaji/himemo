# 引き継ぎ指示書: v1 画面で Sync v2 を扱う統合作業

作成日: 2026-11-18 / ブランチ: `feature/v2-on-v1-ui`（`feature/v2-attachment-viewer` から分岐。最新 `bf765a2`）

## 0. 最初に読むもの

1. `internal-docs/sync-v2-unified-ui-design.md` — 設計方針・決定事項・実装状況（必読。§7 決定事項、§8 実装状況）
2. `AGENTS.md`（リポジトリ直下、未追跡）とグローバルな作業ルール（下記 §6）

## 1. ゴールと前提

- **最初のゴール**: v1 の画面導線のまま、v2（Sync v2）のデータを正しく扱う。v2 専用ワークスペース画面は使わない方向。
- **過去データはすべて破棄してよい**。移行処理は作らない。
- アプリは自分専用メモ。隠しコンセプトとして「パスコードでプロファイルを使い分ける（ダミープロファイル的）」使い方ができる。UI で前面に出さない。
- 鍵の考え方: 外部からの防御は SYNC 鍵に集約。端末内のロック（プロファイルのパスコード、管理者解除）は手軽にする。**管理者はすべてに優先する**。

## 2. 決定済み事項（変更しないこと）

| 項目 | 決定 |
|---|---|
| パスコード最短長 | 4 文字（`SyncV2ProfileKeys.minimumPasscodeLength`） |
| 同一パスコード | プロファイル同士は許可（同時に開く）。管理パスコードとの重複は禁止（未実装） |
| Argon2id | m=19MiB, t=2, p=1。鍵レコード `formatVersion` = 3（旧形式は読まない） |
| 誤入力の待ち時間 | 1〜4 回: なし / 5: 30 秒 / 6: 1 分 / 7: 5 分 / 8: 15 分 / 9 以降: 1 時間。プロファイル解除と管理パスコード解除で共有（`syncV2UnlockAttemptsKey`、`syncV2UnlockDelay`） |
| 開発用回避 | development フレーバーかつ v2 バックエンドのみ、解除ダイアログのタイトルを 3 秒以内に 5 回タップで待ち時間リセット |
| 管理パスコード | 端末ローカルのみ保存（同期しない） |
| 管理者の優先 | 設定画面経由の管理者もパスコード変更・修復可。ADMIN 鍵自体の管理（生体登録・管理者 QR）は ADMIN 鍵を直接解除したセッションのみ |
| Web 版 | リリースしない。同期スタブ（`v2-local`）で開発し、iOS 実機確認は GitHub Actions（`ios-testflight.yml`） |

## 3. 実装済みの構成（要点）

- `lib/features/home/data/note_store.dart` — `NoteStore` インターフェース。`NotesController` は `noteStoreProvider` 経由で保存。
- `lib/features/sync/data/sync_v2_note_store.dart` — v2 実装。ID 変換: v1 `X` ⇔ v2 `note_X`、`everyday` ⇔ v2 通常プロファイル、プライベートは `private_profile:...` のまま。競合中・本文未着のノートは保存・削除を拒否（`SyncV2StaleNote`）。添付参照は空で保存（フェーズ 3 で対応）。
- `lib/features/sync/presentation/sync_v2_note_store_provider.dart` — `HIMEMO_NOTE_BACKEND`（`v1` 既定 / `v2` / `v2-local`）で切替。ワークスペースの変化（プロファイル解除・同期受信）で `NotesController.reloadFromStorage()`。
- `SyncV2WorkspaceController.noteStoreSession`、`debugResetUnlockThrottle()` を追加。
- `home_providers.dart`: v2 モード時、`PrivateProfileUnlockController` / `AdminModeSessionController` / `UnlockedPrivateProfileVaultIdController` / `PrivateMemoProfilesController` が v2 ワークスペースに委譲（関数 `_unlockSyncV2`、`_addSyncV2Profile` など）。プロファイル作成は端末認証 → 管理者モード → `createProfile`。
- `app_router.dart`: v2 バックエンド時は iOS の `/notes` → `/sync-v2` 転送をしない。
- `bootstrap.dart`: development で `HiMemo note backend: <値>` をコンソール出力。

## 4. 残作業（この順で）

### フェーズ 2 の残り
1. **管理パスコードによる管理者解除 UI**: v1 の管理者モード入口（`home_settings_screen.dart` の `_enterAdminMode`）で、生体認証が使えない/オフの端末では管理パスコード入力 → `SyncV2WorkspaceController.unlockAdmin(password)` を使う。
2. **管理パスコードとプロファイルパスコードの重複禁止**: 管理パスコード設定・変更時と、プロファイル作成・パスコード変更時に検査。
3. **プロファイル削除・名前変更を v2 に接続**: `PrivateMemoProfilesController.deleteProfile` / `renameProfile`。v2 側に API が無ければ追加。

### フェーズ 3: 添付
- `encryptedAttachmentStoreProvider` を v2 の添付処理（`lib/features/sync/data/sync_v2_attachment_service.dart`）へ。`SyncV2NoteStore._write` の `'attachments': []` を実際の参照に。画像・動画・音声の追加と表示を確認。

### フェーズ 4: 管理者解除方式と端末追加
- 端末ごとに「生体認証 / 管理パスコード」を選択可能に。
- 端末追加 QR を 1 種類（SYNC + ADMIN）に。詳細設定に「管理者なしで追加（SYNC のみ）」。
- 復元コード（SYNC / ADMIN）を 1 ファイルで出力。

### フェーズ 5: 整理と削除
- v2 固有操作（QR ペアリング・復元コード・生体登録・プロファイル作成）を v1 設定画面の「同期とセキュリティ」に集約。
- v1 ローカルノート DB、Google Drive 同期、旧 iCloud 同期、`sync_v2_legacy_import.dart`、v1 アーカイブ取り込み、v2 専用画面の重複部分を削除。
- v2 を既定にし、`HIMEMO_NOTE_BACKEND` の切替を撤去。

### フェーズ 6: 性能と実機
- `SyncV2NoteRepository.readProfile` が毎回全履歴を走査している → プロファイル別の最新状態テーブル＋インデックス。
- 解除時の KDF はプロファイル数に比例 → 必要なら Isolate で並列化。
- GitHub Actions の iOS で CloudKit・生体認証を確認。

## 5. 開発・確認の手順

### テスト
```bash
flutter analyze lib
flutter test test/sync_v2_note_store_test.dart test/sync_v2_unlock_throttle_test.dart test/sync_v2_workspace_test.dart test/sync_v2_workspace_screen_test.dart test/sync_v2_profile_keys_test.dart test/sync_v2_admin_store_test.dart test/home_providers_logic_test.dart test/app_test.dart
```
- テスト全体（`flutter test`）は未実行。区切りで一度実行すること。
- `test/sync_v2_cloudkit_web_test.js` は flutter test の対象外（読み込みエラーになるが無関係）。

### Web で画面確認（重要な落とし穴あり）
`flutter run -d web-server` は dart-define が反映されない／アセット欠落のビルドが配信されたことがある（見た目は同じでも実際は v1 で動いていた）。必ず次の手順で:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/flutter_with_env.ps1 build web --no-wasm-dry-run -t lib/main_development.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
python -m http.server 8765 --directory build/web
```
- ブラウザのコンソールに `HiMemo note backend: v2-local`、IndexedDB に `himemo_sync_v2_local_preview_wasm` があることを確認してから判断する。
- `v2-local` は鍵をメモリにしか置かないため、再読み込みで以前のデータは読めない（仕様）。確認前に localStorage / IndexedDB を消すと確実。
- Web では管理者モードの端末認証が無いので、`v2-local` かつ development のときだけ省略している。

## 6. 作業ルール

- 回答・コミットメッセージは日本語可。接頭辞: 新機能 `add:` / 改善 `update:` / 修正 `fix:` / リファクタ `refactor:`。
- Co-Authored-By などの共著表記は付けない。
- 既定ブランチ（`main`）へ直接コミットしない。push・マージ・PR はユーザーの許可を得てから。
- 適切な区切りでコミットしてよい。依頼範囲外の変更・無関係なリファクタは避ける。
- 未追跡の `AGENTS.md`、`artifacts/`、`store-assets/...`、`.claude/` はユーザーの持ち物。コミットしない。
- 改善案・機能追加案は番号付きで提示し、ユーザーに選ばせてから実装する。
- CRLF のファイルがある。スクリプトで編集するときは改行コードに注意。
- セキュリティ上の判断を覆す変更（既存テストが意図した仕様として守っている制限など）は、勝手に変えずユーザーに確認する。
