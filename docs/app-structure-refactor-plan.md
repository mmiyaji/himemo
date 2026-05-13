# app.dart 構造改善案

## 目的

`lib/app/app.dart` はルーティング、起動ゲート、アプリロック、プライバシースクリーン、ライフサイクル同期、プラットフォームチャネル調整をまとめて持っています。安全に進めるには、既存の provider 発火タイミングを変えずに責務だけを分けます。

## 切り出し単位

1. `lib/app/app_lock_gate.dart`
   - `_AppLockGate`、プライバシースクリーンのチャネル状態、ライフサイクルカバー状態、Quick Capture のバイパス判定を移します。
   - 公開インターフェースは child widget と既存 Riverpod provider だけにします。
   - Quick Capture は `/widget-capture` が有効、または Quick Capture request が残っている間だけアプリロックをバイパスする現在のルールを維持します。

2. `lib/app/cloud_sync_scheduler.dart`
   - クラウド同期のライフサイクルスケジューリング、自動同期間隔チェック、foreground/background トリガーを移します。
   - provider の read と `ref.listen` の挙動を維持するため、router を包む小さな `ConsumerStatefulWidget` として始めます。
   - transport 固有の処理は既存の sync provider 側に残します。

3. `lib/app/app_shell_host.dart`
   - launch gate、sync scheduler、app-lock gate、router を合成します。
   - アプリ全体の高レベルな順序関係はここだけに集約します。

## 移行手順

1. 現在の Quick Capture ロックバイパスとライフサイクル privacy 挙動を guardrail test で固定します。
2. app-lock gate を挙動変更なしで移し、UI guardrail test を実行します。
3. cloud sync scheduler を挙動変更なしで移し、sync と UI の guardrail test を実行します。
4. private class のリネームは、挙動維持の移動をコミットした後に行います。

## 今回やらないこと

- 切り出し中にロックタイミング、プライバシースクリーン表示、同期間隔、Quick Capture ルーティングは変えません。
- 既存のライフサイクル挙動がテストで固定されるまでは、新しい scheduler 抽象は導入しません。
