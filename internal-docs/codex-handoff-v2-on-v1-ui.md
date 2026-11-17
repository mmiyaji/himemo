# 引き継ぎ指示書: v1 画面で Sync v2 を扱う統合作業

作成日: 2026-11-18 / ブランチ: `feature/v2-on-v1-ui`（`feature/v2-attachment-viewer` から分岐。実装の基点 `bf765a2`、引き継ぎ資料 `a3eea96`。フェーズ2/3は `699ffaa` にコミット済み）

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
| 同一パスコード | プロファイル同士は許可（同時に開く）。管理パスコードとの重複は禁止（設定・作成・変更時に検査） |
| Argon2id | m=19MiB, t=2, p=1。鍵レコード `formatVersion` = 3（旧形式は読まない） |
| 誤入力の待ち時間 | 1〜4 回: なし / 5: 30 秒 / 6: 1 分 / 7: 5 分 / 8: 15 分 / 9 以降: 1 時間。プロファイル解除と管理パスコード解除で共有（`syncV2UnlockAttemptsKey`、`syncV2UnlockDelay`） |
| 開発用回避 | development フレーバーかつ v2 バックエンドのみ、解除ダイアログのタイトルを 3 秒以内に 5 回タップで待ち時間リセット |
| 管理パスコード | 端末ローカルのみ保存（同期しない） |
| 管理者の優先 | 設定画面経由の管理者もパスコード変更・修復可。ADMIN 鍵自体の管理（生体登録・管理者 QR）は ADMIN 鍵を直接解除したセッションのみ |
| Web 版 | リリースしない。同期スタブ（`v2-local`）で開発し、iOS 実機確認は GitHub Actions（`ios-testflight.yml`） |

## 3. 実装済みの構成（要点）

- `lib/features/home/data/note_store.dart` — `NoteStore` インターフェース。`NotesController` は `noteStoreProvider` 経由で保存。
- `lib/features/sync/data/sync_v2_note_store.dart` — v2 実装。ID 変換: v1 `X` ⇔ v2 `note_X`、`everyday` ⇔ v2 通常プロファイル、プライベートは `private_profile:...` のまま。競合中・本文未着のノートは保存・削除を拒否（`SyncV2StaleNote`）。添付はv2チャンク参照としてノートと同じトランザクションで保存。
- `lib/features/sync/presentation/sync_v2_note_store_provider.dart` — `HIMEMO_NOTE_BACKEND`（`v1` 既定 / `v2` / `v2-local`）で切替。ワークスペースの変化（プロファイル解除・同期受信）で `NotesController.reloadFromStorage()`。
- `SyncV2WorkspaceController.noteStoreSession`、`debugResetUnlockThrottle()` を追加。
- `home_providers.dart`: v2 モード時、`PrivateProfileUnlockController` / `AdminModeSessionController` / `UnlockedPrivateProfileVaultIdController` / `PrivateMemoProfilesController` が v2 ワークスペースに委譲（関数 `_unlockSyncV2`、`_addSyncV2Profile` など）。プロファイル作成は端末認証 → 管理者モード → `createProfile`。
- `app_router.dart`: v2 バックエンド時は iOS の `/notes` → `/sync-v2` 転送をしない。
- `bootstrap.dart`: development で `HiMemo note backend: <値>` をコンソール出力。

## 4. 残作業（この順で）

### フェーズ 2（2026-11-18に残りを実装）
- 管理パスコードでの管理者解除UI、管理・プロファイル間のパスコード重複禁止、プロファイルの名前変更・削除をv2に接続した。
- 名前変更・削除は同期先の解除済みセッションにも反映する。削除はノートとカタログをトランザクション内で処理し、競合・未受信データがあれば中止する。
- `v2-local` の管理パスコードは開発用の `preview-password`（`sync_v2_note_store_provider.dart` の自動登録処理）。
- フェーズ3の添付も下記のとおり実装。

### フェーズ 3: 添付（実装済み）
- `SyncV2AttachmentStore` でv1の画像・動画・音声ビューアをv2へ接続。一時添付は端末内の専用領域 `sync_v2_drafts`、確定した参照は `v2attachment:<id>`。
- `SyncV2NoteStore` がチャンクとノートを同じトランザクションで保存し、確定した参照を `NotesController` に返す。本文編集時の参照保持、プロファイル移動時の再暗号化、ロック後の読み出し拒否に対応。
- 下書き本体・一時添付はv2プロファイル鍵で保護。保存中の下書きは維持し、エディタの保存完了後に不要な一時添付を削除。古い下書き参照からの再保存には確定参照の対応表を使用。
- v2バックエンド時はv1同期を停止し、v1 ZIP取り込みを処理開始前に拒否する。
- Opusで設計・実装レビューを実施し、領域分離、プレースホルダ保護、保存エラーの再試行等を修正。再レビューはClaude Codeの利用上限により未実施。
- 大きい添付の読み込みがDBトランザクションを占有する点は、フェーズ6で性能評価・改善する。
- Webの `v2-local` で画像・動画・音声の取り込み、保存後の画像表示、動画・音声の再生を手動確認済み（ブラウザerrorログなし）。完成したビルドで再確認し、画像表示・動画再生完了・音声再生を確認。
- フェーズ4も下記のとおり実装。iOS実機のメディア再生・CloudKitは未確認。

### フェーズ 4: 管理者解除方式と端末追加（実装済み）
- v1設定の「同期とセキュリティ」に `SyncV2DeviceSecuritySettings` を追加。端末ごとに生体認証／管理パスコードを選択し、新しい方式の保存後に以前の方式を削除する。鍵管理はADMIN鍵を直接解除したセッションのみ。
- 通常の端末追加QRはSYNC＋ADMINの1種類。詳細設定に管理者なしのSYNC-only QRを配置。SYNC-onlyでもプロファイルのパスコードを知っていればそのプロファイルは開ける（管理者権限を付けない）。
- `SyncV2DeviceTransfer` はQRと復元ファイルの共通形式。SYNCとADMINの世代を照合し、受信時にはクラウド登録情報でADMINも検証してから端末登録を保存する。不正ADMINでは登録も端末管理者鍵も残さない。
- 復元ファイルは `himemo-recovery.json` の1ファイル。受信端末で自分の解除方式を選び、管理パスコードは端末内だけに保存する。復元ファイルからの再登録は詳細設定でも可能。
- QR等のダイアログはバックグラウンド移行時に閉じ、保護セッションを破棄する。管理者の解除状態はv1の一覧へも反映する。
- 検証: 全体832件成功、v2専用1件も別途成功。静的解析・Webビルド成功。Webで設定表示・統合QR・復元ファイルの実出力を確認。iOSの生体認証・カメラ読み取りは未確認。
- Opusへの相談は利用上限（2026-11-18 02:20 JST解除予定）により未実施。次回利用可能になったらこの差分を優先レビューする。
- 次はフェーズ5。旧v2専用画面の別々のQR等の重複導線は、フェーズ5で整理・削除する。

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
flutter test test/sync_v2_device_transfer_test.dart test/sync_v2_device_security_settings_test.dart test/sync_v2_note_store_test.dart test/sync_v2_unlock_throttle_test.dart test/sync_v2_workspace_test.dart test/sync_v2_workspace_screen_test.dart test/sync_v2_profile_keys_test.dart test/sync_v2_admin_store_test.dart test/home_providers_logic_test.dart test/app_test.dart
```
- 2026-11-18 フェーズ2完了時: `flutter test` 全817件成功。`flutter analyze lib` と変更テストの解析は指摘なし。development / `v2-local` のWebビルド成功。iOS実機の生体認証・CloudKitは未確認。
- フェーズ3: 全体823件成功（v2専用テスト1件は通常実行時スキップし、`--dart-define=HIMEMO_NOTE_BACKEND=v2-local` を付けて別途成功）。静的解析・Webビルド成功。
- `test/sync_v2_cloudkit_web_test.js` は flutter test の対象外（読み込みエラーになるが無関係）。

### Web で画面確認（重要な落とし穴あり）
`flutter run -d web-server` は dart-define が反映されない／アセット欠落のビルドが配信されたことがある（見た目は同じでも実際は v1 で動いていた）。必ず次の手順で:
```bash
powershell -NoProfile -ExecutionPolicy Bypass -File tools/flutter_with_env.ps1 build web --no-wasm-dry-run -t lib/main_development.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
python -m http.server 8765 --directory build/web
```
- Webビルド後に生成済みl10nファイルが削除される場合は、`flutter gen-l10n` で再生成してから解析・テストする。テストとWebビルドは同時実行しない。
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


### 2026-11-18: 同期操作の整理（ユーザー指示）
- v1の詳細同期・個別アップロード／ダウンロード／適用／修復という操作体系は引き継がない。v2設定は自動同期の状態と「今すぐ同期」（失敗時「同期を再試行」）、別端末の追加用QR、復元用ファイルの保存、端末内の管理者解除方式に整理。
- 管理者未登録の端末だけ「管理者権限を追加」からQR／復元ファイルを受け取る。未登録端末には端末追加と初回設定の入口を表示。SYNC-onlyの例外操作は用途を明記した折りたたみに配置。
- v2では旧CloudKit閲覧画面・v2検証用画面・v1 ZIPバックアップへの重複入口を非表示。ヘッダーは同期中／要確認の状態から設定を開く。一覧の下方向スワイプもv2の同期処理を呼ぶ。
- 最終同期時刻とエラーは実際のv2同期結果から更新（セッション内の状態）。生体認証への切替で管理パスコードが削除されることと復元手段を説明。
- Opusレビュー実施。通知の重複、日付、復元入口と生体切替の説明を修正。SYNC-onlyの書き出し制限変更は既存仕様の変更なので今回は行わない。受信途中の通信失敗・解除方式設定失敗ではSYNCのみ登録済みになり得るが、同じ世代のQR／ファイルを「管理者権限を追加」で再読込できる。受信の一括確定・その場の再入力は今後の改善候補。
- 検証: 全体833件成功・1件スキップ、v2専用テストは別途成功、変更関連33件成功。Webビルド成功。iOS実機でのiCloud・生体認証・カメラ操作は未確認。v2既定化と旧バックエンド自体の削除はフェーズ5の残作業。
