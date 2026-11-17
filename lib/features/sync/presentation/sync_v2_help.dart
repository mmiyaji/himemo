import 'package:flutter/material.dart';

/// Short onboarding guidance; no recovery codes or account data are displayed.
class SyncV2HelpDialog extends StatelessWidget {
  const SyncV2HelpDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ja = Localizations.localeOf(context).languageCode == 'ja';
    final steps = ja
        ? const [
            ('1. 初めての端末', '暗号化ワークスペースを登録し、表示された同期復元コードと管理者コードを安全な別々の場所に保管します。'),
            (
              '2. 以前のメモ',
              '必要に応じて旧画面からZIPを書き出し、管理者としてV2にインポートします。移行を確認するまで元データとZIPは残してください。',
            ),
            (
              '3. 別の端末',
              '同じiCloudアカウントで、最初の端末の同期用QRまたは同期復元コードを使って参加します。管理者コードは別の用途です。',
            ),
            (
              '4. メモとロック',
              'プロファイルの鍵から私用メモを解除・ロックできます。変更後は同期を実行し、別の端末でも内容を確認してください。',
            ),
          ]
        : const [
            (
              '1. First device',
              'Register an encrypted workspace and keep the sync recovery and administrator codes separately in safe places.',
            ),
            (
              '2. Existing notes',
              'If needed, export a ZIP from the old screen and import it as an administrator. Keep the original data and ZIP until migration is verified.',
            ),
            (
              '3. Another device',
              'Use the same iCloud account and join using the first device’s sync QR or recovery code. The administrator code serves a different purpose.',
            ),
            (
              '4. Notes and locking',
              'Unlock or lock private notes from the profile controls. Sync changes and verify them on the other device.',
            ),
          ];
    return AlertDialog(
      title: Text(ja ? '暗号化同期の使い方' : 'Encrypted sync guide'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (title, body) in steps) ...[
                Text(title, style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(body),
                const SizedBox(height: 16),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(ja ? '閉じる' : 'Close'),
        ),
      ],
    );
  }
}
