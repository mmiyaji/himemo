import '../domain/note_entry.dart';
import '../domain/vault_models.dart';

abstract class HomeRepository {
  List<VaultBucket> get vaults;
  List<UnlockIdentity> get identities;
  List<NoteEntry> get seededNotes;
}

class SeededHomeRepository implements HomeRepository {
  @override
  List<VaultBucket> get vaults => const [
        VaultBucket(
          id: 'everyday',
          name: 'Daily Notes',
          description: '普段使いのメモや日記を保存する標準のメモ領域。',
        ),
        VaultBucket(
          id: 'decoy',
          name: 'Travel Scrap',
          description: '通常画面の延長に見える別表示用のメモ領域。',
        ),
        VaultBucket(
          id: 'private',
          name: 'Quiet Archive',
          description: '特別な解除キーでのみ開く非公開メモ領域。',
        ),
      ];

  @override
  List<UnlockIdentity> get identities => const [
        UnlockIdentity(
          id: 'daily',
          name: 'Daily View',
          tagline: '普段使いのメモだけを開く通常モード。',
          lockLabel: 'Standard access',
          visibleVaultIds: ['everyday'],
          accentHex: 0xFF6B8798,
          warning: '通常導線では private vault を表示しません。',
        ),
        UnlockIdentity(
          id: 'cover',
          name: 'Cover View',
          tagline: '通常メモに見える別表示へ切り替えるモード。',
          lockLabel: 'Cover key',
          visibleVaultIds: ['everyday', 'decoy'],
          accentHex: 0xFF8A7B6D,
          warning: '公開配布時は hidden behavior と誤解されない説明が必要です。',
        ),
        UnlockIdentity(
          id: 'private',
          name: 'Private View',
          tagline: '本当に隠したいメモだけを開く非公開モード。',
          lockLabel: 'Private key',
          visibleVaultIds: ['everyday', 'private'],
          accentHex: 0xFF5C7466,
          warning: '本番では鍵導出、暗号化、キャッシュ制御を必須にします。',
        ),
      ];

  @override
  List<NoteEntry> get seededNotes => [
        NoteEntry(
          id: 'n1',
          vaultId: 'everyday',
          title: '朝の買い物',
          body: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
          createdAt: DateTime(2026, 4, 11, 8, 10),
          updatedAt: DateTime(2026, 4, 11, 8, 10),
          deviceId: 'seeded-device',
          contentHash: 'seed-n1',
          isPinned: true,
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'n2',
          vaultId: 'everyday',
          title: '日記',
          body: '今日は集中して書けた。夜は静かで、考え事がまとまった。',
          createdAt: DateTime(2026, 4, 10, 22, 40),
          updatedAt: DateTime(2026, 4, 10, 22, 40),
          deviceId: 'seeded-device',
          contentHash: 'seed-n2',
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'n3',
          vaultId: 'decoy',
          title: '大阪メモ',
          body: '駅前の写真を整理。週末の散歩ルートも本にして見返す。',
          createdAt: DateTime(2026, 4, 9, 19, 5),
          updatedAt: DateTime(2026, 4, 9, 19, 5),
          deviceId: 'seeded-device',
          contentHash: 'seed-n3',
          attachments: const [
            NoteAttachment(type: AttachmentType.photo, label: 'platform.jpg'),
            NoteAttachment(
                type: AttachmentType.video, label: 'walkthrough.mp4'),
          ],
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'n4',
          vaultId: 'private',
          title: 'Hidden draft',
          body: '本番ではここに暗号化された下書きだけを保存し、通知や検索結果にも露出させない。',
          createdAt: DateTime(2026, 4, 8, 23, 15),
          updatedAt: DateTime(2026, 4, 8, 23, 15),
          deviceId: 'seeded-device',
          contentHash: 'seed-n4',
          isPinned: true,
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'n5',
          vaultId: 'private',
          title: 'Sync policy',
          body: '同期は暗号化済みの blob のみを扱い、復号鍵は端末側で保持する設計にする。',
          createdAt: DateTime(2026, 4, 7, 21, 0),
          updatedAt: DateTime(2026, 4, 7, 21, 0),
          deviceId: 'seeded-device',
          contentHash: 'seed-n5',
          syncState: NoteSyncState.synced,
        ),
      ];
}
