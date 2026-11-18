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
- `lib/features/sync/presentation/sync_v2_note_store_provider.dart` — `HIMEMO_NOTE_BACKEND`（`v2` 既定 / 開発用 `v2-local`（`v1` は旧互換テストのみ））で切替。ワークスペースの変化（プロファイル解除・同期受信）で `NotesController.reloadFromStorage()`。
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
- v2既定化と旧画面の通常ルート撤去は実装済み。`HIMEMO_NOTE_BACKEND=v1` は旧回帰テストのみで使用し、実アプリ起動では拒否する。旧実装・旧テストの削除後にv1分岐も撤去する。

### フェーズ 6: 性能と実機
- `SyncV2NoteRepository.readProfile` が毎回全履歴を走査している → プロファイル別の最新状態テーブル＋インデックス。
- 解除時の KDF はプロファイル数に比例 → 必要なら Isolate で並列化。
- GitHub Actions の iOS で CloudKit・生体認証を確認。

## 5. 開発・確認の手順

### テスト
```bash
flutter analyze --fatal-infos
flutter test --exclude-tags legacy
flutter test --tags legacy --dart-define=HIMEMO_NOTE_BACKEND=v1
flutter test test/sync_v2_default_configuration_test.dart --dart-define=HIMEMO_NOTE_BACKEND=v2-local
flutter test test/sync_v2_default_configuration_test.dart --dart-define=HIMEMO_NOTE_BACKEND=v1
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


### 2026-11-18: フェーズ5・初回設定の集約
- 「初めて使う：iCloud同期を始める」は旧ワークスペースへ遷移せず、設定内で解除方式の選択→復元用ファイル保存→保管確認→登録まで完了する。個別のSYNC／ADMINコード表示を使わない。
- ネイティブ保存のキャンセルでは保管確認を有効にしない。Webはダウンロード完了をOSパスで判定できないため、ダウンロード開始後にユーザーが保管を確認する。保存中は重複操作を止める。
- 準備中の登録の取消と、保留中のクラウド登録の再開を設定に配置。間違った管理パスコードは専用の文言で表示。
- 生体認証の鍵が無効になっても復元できるよう、登録済み端末の「QR・ファイルから管理者権限を復元」は常時表示する（Opusレビュー反映）。
- v2バックエンドでは旧 `/sync-v2` と `/sync-v2-web-readonly` の直接URLも設定へ転送する。v1バックエンドの互換コードは後続で削除する。
- 検証: 設定＋ワークスペース34件成功、appを含む148件成功。静的解析は指摘なし。初回設定の取消・保管確認前の登録防止・登録完了をウィジェットテストで確認。iOSの保存・生体認証は実機未確認。
- Opusが指摘した既存コントローラの取消時の未登録世代の鍵掃除、公開後に端末への取付が失敗した際の再開改善は引き続き確認対象。バックグラウンド時は既存 `background()` が `_setupAdmin` を破棄する。SYNC-onlyの仕様変更は行っていない。
- フェーズ5の残り: v2既定化とバックエンド切替廃止、旧DB・旧同期・アーカイブ移行処理と旧専用画面のソース削除。


### 2026-11-18: 初回設定取消時の鍵の後片付け
- 未公開・未登録の準備を取り消すと、その世代の管理パスコード、生体キー／フラグ、端末ADMIN記憶を削除する。生体認証未使用の場合は未対応プラットフォームの生体削除APIを呼ばない。
- クラウド登録の保留記録または端末登録がある世代は、再開に必要な資格情報を保持する。保留記録は公開処理より先に永続化されることを確認。
- 永続化領域の読み込みや削除に失敗した場合も、finallyで読み込んだSYNC鍵とメモリ上の準備鍵を破棄し、通常のエラー経路で失敗を知らせる。永続化領域の失敗によって古い資格情報が残る可能性はある。
- Opusレビュー実施。読み込み途中の失敗による鍵の破棄漏れと、削除失敗時に準備状態が残る点を反映。
- ルーターから旧画面を全面撤去する差分は見送った。既定がv1のまま撤去すると、v2専用画面を使っていた端末のデータへの入口を失う（Opus指摘）。旧画面の入口撤去はv2既定化と同じ変更単位で行う。


### 2026-11-18: フェーズ5・v2既定化と旧画面のルート撤去
- 通常ビルドの既定はv2。旧 `/sync-v2`、`/sync-v2-web-readonly` は常に統合設定へ転送し、ルーターから旧画面・閲覧専用画面のimportを削除。旧設定フラグによるiOS一覧からの自動転送も撤去。
- 設定内の旧専用画面への入口を削除。未登録の端末でメモ作成を押した場合は、入力前に同期設定を開く。
- v1は旧回帰テストの指定としてのみ保持。bootstrapの `noteBackendOverrides()` はv1指定の実アプリ起動を拒否する。v2-localはdevelopmentフレーバーのみ。productionではプレビュー用の固定パスコード・メモリ鍵を使わない。
- noteStoreの再生成で登録済みセッションを再度attachしてロックしない。未登録時の初期化Futureを共有し、初期化エラーはcontrollerに保持して未処理の非同期例外を避ける。
- CIは legacyタグの旧DB／旧同期テストを明示v1で実行し、それ以外の全テストを既定v2で実行。UIレイアウト・チュートリアルの共通ハーネスもv2のインメモリ登録へ移した。Google Drive固有のUIテストだけlegacyタグ。
- Opusレビュー反映: 共有テストを既定v2で回す構成、productionフレーバーのテスト前提の明示、初期化Futureの共有。通常のビルド設定にv1指定が残っていないことを確認。
- 旧DB・Google Drive・旧iCloud・ZIP移行・開発用旧ワークスペースのソースと旧テストの削除は残作業。互換テストを退役させた段階で `HIMEMO_NOTE_BACKEND` のv1分岐も完全撤去する。
- この変更でiOS実機のCloudKit・生体認証を検証したわけではない。通常のv2 transportは現在iOSのみ対応、Webではv2-localで開発する。Android配布の確認はしていない。
- 検証: 既定v2の共有テスト599件、明示v1の旧回帰244件成功。初期化共有の最終修正後に関連26件も成功。v1実アプリ起動拒否とproductionのv2-local拒否を別途確認。解析対象からローカルの `.claude/**` を除外（worktree自体は変更しない）。
- 最終確認: 既定v2／v2-localのWebビルド成功、`flutter analyze --fatal-infos` 指摘なし、変更Dartファイルのフォーマット確認成功。Opus再レビューでも重大な問題なし。iOS実機・Androidのアプリ実行と配布は未実施。


### 2026-11-18: フェーズ5・旧ワークスペース画面を削除
- `sync_v2_workspace_screen.dart`（5,085行）と専用の画面テスト（4,515行）を削除。通常アプリ・開発ツール・テストに残存参照はない。統合画面のテスト、コントローラ、共有エディタ／ビューアのテストは維持。
- `tools/v2_web_local_preview.dart` は通常のbootstrap＋v2-localで統合アプリを表示し、v2-local指定がない起動は拒否する。`v2_web_preview.dart` は同じ入口へ委譲する互換エントリに変更。既存のローカルsmoke分岐は維持。
- 旧画面専用だったCloudKitサンドボックスUIツールを撤去。名前空間で分離する通信実装とテスト、独立した閲覧専用ツールは残す。Webはローカルプレビュー中心という既定方針に合わせる。
- Opusレビューで重大な不整合なし。指摘された分離の前提は、bootstrapのv2-local override→専用DB名 `himemo_sync_v2_local_preview_wasm`、MemorySecureKeyValueStore、LocalPreviewRegistration、クラウドを呼ばないsyncOperationで確認。統合設定の同期操作も同じcontrollerを利用し、旧同期はv2モードで無効。
- 検証: 残るv2共有テスト515件成功、静的解析指摘なし。互換プレビューエントリのWebビルド成功。ブラウザで通常のノート画面→設定→同期操作まで確認し、最終同期表示の更新とerrorログなしを確認。iOS・CloudKit実機の検証はしていない。
- 旧ZIP処理はcontroller・添付アーカイブの下層テスト・ローカルsmokeから依存されている。次はこの依存を整理してZIP移行APIを削除し、その後に旧DB／旧同期／v1互換分岐を削除する。


### 2026-11-18: フェーズ5・v2の旧ZIP移行APIを削除
- `sync_v2_archive_service.dart`、`sync_v2_legacy_import.dart` とcontrollerのZIP検査・取り込み・管理者一括復元・書き出しAPIを削除。プロファイルの自動取り込み先作成とlegacyImportメタデータの引継ぎも撤去。
- ZIP取り込みだけが使っていた本文未受信／復号失敗を無視する読み出しと上書きAPIをrepositoryから削除。通常の読み取り・既知head照合・本文検証を通る保存だけを使う。一括保存も空headとの照合を行い、既知head・本文未受信を上書きしないことをテストで追加確認。
- インポート専用だったadmin-onlyのプロファイル鍵(version2)を削除。鍵の仕様は現行formatVersion=3のみ。旧version2鍵を含むクラウド世代は非互換で、再利用にはクラウド世代の破棄／新規設定が前提。レコードを黙って読み飛ばしたり移行したりしない。実際のクラウド削除・世代リセットは行っていない。
- rich編集・添付削除・QR管理者復元・設定経由の管理者権限・quick編集のテストをnative保存／実際の二端末同期へ移行。ZIP専用テストは撤去し、分割添付の履歴走査回数・逆順中断配信・破損参照の検証は `sync_v2_attachment_delivery_test.dart` へ保持。
- ローカルsmokeもZIPの往復を外し、暗号化保存→鍵の破棄→SYNC/ADMINでの再登録→添付復元→プライベートプロファイルの解除を引き続き検証する。通常の「ノートをアーカイブする」機能は維持。
- Opusレビューで通常の暗号化・CAS・競合解決に重大な退行なし。指摘された旧鍵形式の非互換方針、一括保存のCAS、legacyImport残存参照を確認した。
- v1互換側のZIP処理は旧DB／旧同期と同じ依存に属するため残る。次は旧DB・Google Drive・旧iCloud・v1互換テスト／分岐を整理・削除する。
- 最終検証: v2共有502件＋旧互換244件成功、静的解析指摘なし、変更Dartのformat確認成功、ローカルプレビューWebビルド成功。実ブラウザの `v2LocalSmoke=1` で鍵をメモリから破棄した後のメモ・添付復元とプロファイル解除までpassed、errorログなし。iOS実機・実CloudKitは未検証。
