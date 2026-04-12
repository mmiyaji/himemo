import '../domain/note_entry.dart';
import '../domain/vault_models.dart';

const _seedPhotoWarm =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAxSURBVEhL7c2hAQAACIAw/z/F9zxAu4WijbBCISqzP8UO1xwgB8gBcoAcIAfIAXofDPj6XerIJulkAAAAAElFTkSuQmCC';
const _seedPhotoCool =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAxSURBVEhL7c2hAQAACIAw/7/Dd7xJu4WijbBCIbK6P8UO1xwgB8gBcoAcIAfIAXofDEGnuiocKsKBAAAAAElFTkSuQmCC';
const _seedPhotoLeaf =
    'iVBORw0KGgoAAAANSUhEUgAAABgAAAAYCAYAAADgdz34AAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAAzSURBVEhLYzjyYNd/WmIGdAFq41ELCOJRCwjiUQsI4lELCOJRCwjiUQsI4lELCGKaWwAA39+RqkRptNYAAAAASUVORK5CYII=';

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
          description: '普段使いのメモや日記を保存する標準の領域です。',
        ),
        VaultBucket(
          id: 'decoy',
          name: 'Travel Scrap',
          description: '見せても自然な旅行記や写真メモを置くための領域です。',
        ),
        VaultBucket(
          id: 'private',
          name: 'Quiet Archive',
          description: '特別な解除キーでのみ開く個人用の保管領域です。',
        ),
      ];

  @override
  List<UnlockIdentity> get identities => const [
        UnlockIdentity(
          id: 'daily',
          name: 'Daily View',
          tagline: '普段使いのメモだけを開く標準モードです。',
          lockLabel: 'Standard access',
          visibleVaultIds: ['everyday'],
          accentHex: 0xFF6B8798,
          warning: '通常表示では private vault は見えません。',
        ),
        UnlockIdentity(
          id: 'cover',
          name: 'Cover View',
          tagline: '日常メモに加えて見せても自然な記録を開くモードです。',
          lockLabel: 'Cover key',
          visibleVaultIds: ['everyday', 'decoy'],
          accentHex: 0xFF8A7B6D,
          warning: '公開ストア配布時は hidden behavior の扱いに注意が必要です。',
        ),
        UnlockIdentity(
          id: 'private',
          name: 'Private View',
          tagline: '本当に隠したいメモだけを開く保管モードです。',
          lockLabel: 'Private key',
          visibleVaultIds: ['everyday', 'private'],
          accentHex: 0xFF5C7466,
          warning: '本番では暗号化とバックアップ導線を明確にします。',
        ),
      ];

  @override
  List<NoteEntry> get seededNotes => [
        NoteEntry(
          id: 'seed-2026-04-12-groceries',
          vaultId: 'everyday',
          title: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
          body: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
          createdAt: DateTime(2026, 4, 12, 23, 7),
          updatedAt: DateTime(2026, 4, 12, 23, 7),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-12-groceries',
          isPinned: true,
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'snack-color.png',
              previewBytesBase64: _seedPhotoWarm,
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
            ),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: 'snack-color.png',
                previewBytesBase64: _seedPhotoWarm,
              ),
            ),
          ],
        ),
        NoteEntry(
          id: 'seed-2026-04-12-idea',
          vaultId: 'everyday',
          title: 'どうですか',
          body: '資料の見せ方を先に整理すると、共有会が短く終わりそう。',
          createdAt: DateTime(2026, 4, 12, 22, 2),
          updatedAt: DateTime(2026, 4, 12, 22, 2),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-12-idea',
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'seed-2026-04-11-diary',
          vaultId: 'everyday',
          title: '日記',
          body: '今日は集中して書けた。夜は静かで、考え事がまとまった。',
          createdAt: DateTime(2026, 4, 11, 21, 39),
          updatedAt: DateTime(2026, 4, 11, 21, 39),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-11-diary',
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'seed-2026-04-11-walk',
          vaultId: 'everyday',
          title: '川沿いを歩いた',
          body: '風が強かったけれど、夕方の色がきれいだった。',
          createdAt: DateTime(2026, 4, 11, 18, 15),
          updatedAt: DateTime(2026, 4, 11, 18, 15),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-11-walk',
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'evening-walk.png',
              previewBytesBase64: _seedPhotoCool,
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '風が強かったけれど、夕方の色がきれいだった。',
            ),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: 'evening-walk.png',
                previewBytesBase64: _seedPhotoCool,
              ),
            ),
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '橋の下でメモを取り直した。次は動画でも残したい。',
            ),
          ],
        ),
        NoteEntry(
          id: 'seed-2026-04-10-plan',
          vaultId: 'everyday',
          title: '週末の予定',
          body: '午前に掃除、午後に本屋、夜は家で映画。',
          createdAt: DateTime(2026, 4, 10, 8, 20),
          updatedAt: DateTime(2026, 4, 10, 8, 20),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-10-plan',
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'seed-2026-04-09-trip',
          vaultId: 'decoy',
          title: '大阪駅のメモ',
          body: '案内板が見やすくなっていた。乗り換え動画も残しておく。',
          createdAt: DateTime(2026, 4, 9, 19, 5),
          updatedAt: DateTime(2026, 4, 9, 19, 5),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-09-trip',
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'station-sign.png',
              previewBytesBase64: _seedPhotoCool,
            ),
            NoteAttachment(
              type: AttachmentType.video,
              label: 'platform-walkthrough.mp4',
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '案内板が見やすくなっていた。乗り換え動画も残しておく。',
            ),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: 'station-sign.png',
                previewBytesBase64: _seedPhotoCool,
              ),
            ),
            NoteBlock(
              type: NoteBlockType.video,
              attachment: NoteAttachment(
                type: AttachmentType.video,
                label: 'platform-walkthrough.mp4',
              ),
            ),
          ],
        ),
        NoteEntry(
          id: 'seed-2026-04-08-cafe',
          vaultId: 'decoy',
          title: 'カフェのBGM',
          body: '落ち着いた音が流れていた。音量感をメモしておく。',
          createdAt: DateTime(2026, 4, 8, 14, 10),
          updatedAt: DateTime(2026, 4, 8, 14, 10),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-08-cafe',
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.audio,
              label: 'cafe-bgm.m4a',
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '落ち着いた音が流れていた。音量感をメモしておく。',
            ),
            NoteBlock(
              type: NoteBlockType.audio,
              attachment: NoteAttachment(
                type: AttachmentType.audio,
                label: 'cafe-bgm.m4a',
              ),
            ),
          ],
        ),
        NoteEntry(
          id: 'seed-2026-04-07-board',
          vaultId: 'everyday',
          title: '会議メモ',
          body: '開始は10分遅れ。共有資料の見出しを先に整える。',
          createdAt: DateTime(2026, 4, 7, 9, 40),
          updatedAt: DateTime(2026, 4, 7, 9, 40),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-07-board',
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'seed-2026-04-06-private-draft',
          vaultId: 'private',
          title: '静かな下書き',
          body: 'ここは本当に見せたくない考えをまとめるためのメモ。',
          createdAt: DateTime(2026, 4, 6, 23, 15),
          updatedAt: DateTime(2026, 4, 6, 23, 15),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-06-private-draft',
          isPinned: true,
          syncState: NoteSyncState.synced,
        ),
        NoteEntry(
          id: 'seed-2026-04-05-private-photo',
          vaultId: 'private',
          title: '机のレイアウト案',
          body: '紙の配置だけ残して、本文はあとで追記する。',
          createdAt: DateTime(2026, 4, 5, 22, 30),
          updatedAt: DateTime(2026, 4, 5, 22, 30),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-05-private-photo',
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.photo,
              label: 'desk-layout.png',
              previewBytesBase64: _seedPhotoLeaf,
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '紙の配置だけ残して、本文はあとで追記する。',
            ),
            NoteBlock(
              type: NoteBlockType.photo,
              attachment: NoteAttachment(
                type: AttachmentType.photo,
                label: 'desk-layout.png',
                previewBytesBase64: _seedPhotoLeaf,
              ),
            ),
          ],
        ),
        NoteEntry(
          id: 'seed-2026-04-03-private-audio',
          vaultId: 'private',
          title: '音声メモ',
          body: '歩きながら録った短いメモ。あとでテキスト化する。',
          createdAt: DateTime(2026, 4, 3, 7, 55),
          updatedAt: DateTime(2026, 4, 3, 7, 55),
          deviceId: 'seeded-device',
          contentHash: 'seed-2026-04-03-private-audio',
          syncState: NoteSyncState.synced,
          editorMode: NoteEditorMode.rich,
          attachments: const [
            NoteAttachment(
              type: AttachmentType.audio,
              label: 'walking-note.m4a',
            ),
          ],
          blocks: const [
            NoteBlock(
              type: NoteBlockType.paragraph,
              text: '歩きながら録った短いメモ。あとでテキスト化する。',
            ),
            NoteBlock(
              type: NoteBlockType.audio,
              attachment: NoteAttachment(
                type: AttachmentType.audio,
                label: 'walking-note.m4a',
              ),
            ),
          ],
        ),
      ];
}
