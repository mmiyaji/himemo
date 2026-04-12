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
          description: '普段使いのメモと短い日記を置く通常領域。',
        ),
        VaultBucket(
          id: 'decoy',
          name: 'Travel Scrap',
          description: '見られても不自然でないダミーのテキストと添付。',
        ),
        VaultBucket(
          id: 'private',
          name: 'Quiet Archive',
          description: '本当に隠したいメモを想定した保護領域。',
        ),
      ];

  @override
  List<UnlockIdentity> get identities => const [
        UnlockIdentity(
          id: 'daily',
          name: 'Daily View',
          tagline: '日常メモだけを開く通常のロック解除。',
          lockLabel: 'Face ID / Standard PIN',
          visibleVaultIds: ['everyday'],
          accentHex: 0xFF6B8798,
          warning: '通常導線では private vault を一切表示しません。',
        ),
        UnlockIdentity(
          id: 'cover',
          name: 'Cover View',
          tagline: '日常メモとダミーの添付を見せるカバー表示。',
          lockLabel: 'Decoy PIN',
          visibleVaultIds: ['everyday', 'decoy'],
          accentHex: 0xFF8A7B6D,
          warning: '公開配布時は hidden behavior と誤解されない説明が必要です。',
        ),
        UnlockIdentity(
          id: 'private',
          name: 'Private View',
          tagline: '機密メモを含む本来の管理者表示。',
          lockLabel: 'Private PIN + Biometrics',
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
          body: '卵、豆乳、洗剤。帰りにドラッグストアへ寄る。',
          createdAt: DateTime(2026, 4, 11, 8, 10),
          updatedAt: DateTime(2026, 4, 11, 8, 10),
          isPinned: true,
        ),
        NoteEntry(
          id: 'n2',
          vaultId: 'everyday',
          title: '日記',
          body: '今日は作業時間が長かったので、夜は静かな画面だけ見て終える。',
          createdAt: DateTime(2026, 4, 10, 22, 40),
          updatedAt: DateTime(2026, 4, 10, 22, 40),
        ),
        NoteEntry(
          id: 'n3',
          vaultId: 'decoy',
          title: '大阪メモ',
          body: '駅前の写真を整理。週末候補の動画を2本だけ残す。',
          createdAt: DateTime(2026, 4, 9, 19, 5),
          updatedAt: DateTime(2026, 4, 9, 19, 5),
          attachments: const [
            NoteAttachment(type: AttachmentType.photo, label: 'platform.jpg'),
            NoteAttachment(
                type: AttachmentType.video, label: 'walkthrough.mp4'),
          ],
        ),
        NoteEntry(
          id: 'n4',
          vaultId: 'private',
          title: 'Hidden draft',
          body: '本番ではここに暗号化後のデータだけを保存し、検索索引も分離する。',
          createdAt: DateTime(2026, 4, 8, 23, 15),
          updatedAt: DateTime(2026, 4, 8, 23, 15),
          isPinned: true,
        ),
        NoteEntry(
          id: 'n5',
          vaultId: 'private',
          title: 'Sync policy',
          body: '同期は秘密領域のみ再暗号化した blob を送る設計にする。',
          createdAt: DateTime(2026, 4, 7, 21, 0),
          updatedAt: DateTime(2026, 4, 7, 21, 0),
        ),
      ];
}
