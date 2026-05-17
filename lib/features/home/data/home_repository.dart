import 'dart:math' as math;

import '../domain/note_entry.dart';
import '../domain/vault_models.dart';

const _seedPhotoWarm =
    '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';
const _seedPhotoCool =
    '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';
const _seedPhotoLeaf =
    'iVBORw0KGgoAAAANSUhEUgAAAKAAAABuCAYAAACgLRjpAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAPDSURBVHhe7dzNS1RRGMdx/7qWEbhxI71sDGrjpkVUFNQiF7Vp4SKCCKOwRRQRhRBZib2glUgqlWllqGWW0fbGM4MR54Qz584z93dGv4vPRvSec7lfzp25c5yu3xurBaDSFf4AqBIBQooAIUWAkCJASBEgpAgQUgQIKQKEFAFCigAhRYCQIkBIESCkCBBSBAgpAoQUAUKKACFFgJAiQEgRIKQIEFKVB7j+falYXVncduy8wnNFY5UHaBfrw+LstmPnFZ4rGiNAJwRYDgE6IcByCNAJAZZDgE4IsJxsAhx5NFoMDg1nz+YZzp0Ay8smQLu4ew4ez57NM5w7AZZHgIkI0BcBJiJAXwSYiAB9EWAiAvRFgIkI0BcBJiJAXwSYiAB9EWAiAvRFgIkI0BcBJiJAXwSYKIcA1+ZeFyvPH//1bXoi+p1OQYCJVAFuLC8U7y4NFi/69hdj3bsjzw70FrPnzxY/P72N/jZnBJhIEeDykwe1wMLo/udpb0/x8e7N6Bi5IsBEVQZoq56tamFkzZg6dbQjVkMCTFRlgGXj2/TqSH90zNwQYKKqArTbbhhUGfPXLkfHzgkBJqoiQLv1Nvuar5Hxnu7au+ZwjFwQYKIqApy7cC4KqRXTZ05GY+SCABNVEaDX6rfJVkFbVcNxckCAidodoD1UDgPy8OXhvWisHBBgonYHaKGE8XhYuHE1GisHBJio3QEu3hqO4vHw/srFaKwcEGCidgf4eeROFI+HXB/HEGCidgdomwvCeDxY2OFYOcgmQL4Zoe7X2lLtXWsYUKvW52eisXKQTYCdzitAY8/twoBaMdl/KBojFwToxDNAexTjuQrmevs1BOjEM0Bj71rDkMp4M3A6OnZOCNCJd4D2WtBunWFQKewTldy3ZBGgE+8AjW0imDjcF4XVDNuYajtqwmPmpvIA+Zb8NLYS2lb8MLCtdMpmVFN5gChn9eV4bYNpGNu/7P9FOmk7viHADmPP8+zjOnuTssk+5815z99WCBBSBCiysTJe/FgYyobNJ5xjFQhQxC7618l92bD5hHOsAgGKEGAdAYoQYB0BihBgHQGKEGBdywHOTIwW968PItHY7YFiauRYNmw+4RybYdc/bCJFywHaJE7s3YUdyq5/2EQKAkRLCBBSBAgpAoQUAUKKACFFgJAiQEgRIKQIEFIECCkChBQBQooAIUWAkCJASMkDZEf0zibfEQ20ggAhRYCQIkBIESCkCBBSBAgpAoQUAUKKACFFgJAiQEgRIKQIEFIECCkChBQBQooAIUWAkPoDK9pcTB0OfI4AAAAASUVORK5CYII=';
const _seedPhotoStation =
    'iVBORw0KGgoAAAANSUhEUgAAAKAAAABuCAYAAACgLRjpAAAAAXNSR0IArs4c6QAAAARnQU1BAACxjwv8YQUAAAAJcEhZcwAADsMAAA7DAcdvqGQAAAR4SURBVHhe7d2xThtBEIBhHi3PgXgASro0KKFKGrooDUoVyUlBF4kSKV0oUCjCKyAhUkVKf9HZwezOzu7OLQtjzv9KX2G8vvPd/j6f02Tn95+/A+BlR/4BeE4ECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFcECFfdAvx++Wv4+OUbtsS43rKBFt0CHN/Uq70DbIlxvWUDLQgQTQgQrggQrggQrggQrggQrggQrggQrggQrggQrggQrggQrggQrggQrggQrrYjwMPz4WZIx83ZcTp372A4vpIzS+NuOD1Mt5FuJz8vnVsbD9vaP7tb//XiJN3uyvFwehtt4P/Iv6dwu8NwPRxX5uTOZc3sA6wvbHpy668JR2YRteivFum8R+6zFqBpu7fnw754XRygHhgB1pxcRycxO8QCmBZtPfQA5QKuRhr7Y/dZClB/D5khzkH62vQ4CbAiWlR59YniTE9uJLyaKVeLVPiVdzdcXOUjyTLuMxugvAIr25CRhRHJ55ZDnEMCrAgD1Ba+9vyaMYbsfPlYztcYX5MLsPjhC0UfxIcrtBqg2AcBVsiTWIysxBjDvXRh4iti8Wo7cZ96gFP2p8+NjuE2PI96pASoWgwXwamLR/5+LGGMYcWwoJbFMu5TDzA87vpxat8E8ftdRL+i79//5GNSzDzAUSnC1aheGY0xLIVfadFX37QorPusBlh4bWkbSVzRPeXqg5XMUbZdswUBPij90ixGaIxB7kNus/RcwrhPLZ6psWvvS4sruqW5WqhzptqqAGPiH2cLi2yNwXK1XY/SD4MJ+9QD1G8DdPpcPa74+MJ7QwKUTAtovFKYtiV/UdZGJQzjPvUAxdXe+HrTD4zMMRJgQlyNlEWwLpI1htJXvDaKi2bcZy7A+J5tHOkHTL7f8P1kA5TfHOocuxkHKD/d5VE8gZYYogVPF3stvILktiW3V5iXDXDi8ct95AOUx5qZYzTrAEfyU66OwgIvGWKQN+jy+QfxlVlGM2Wfcr/atkwRKtsvBqhsV5tjMfsAl5RP7GpU7sO01yuLJb+WtBBCplir+0y3ld+v/rVZOv5agPKDpM+p244AsbEIEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK4IEK42LsBt+x/T33/4NLw+erc2PpZz5mzj/sf0bfN58XXY3d1dGx/LOagjwEYE2AcBNiLAPgiwEQH2QYCNCLAPAmxEgH0QYCMC7IMAGxFgHwTYiAD7IMBGBNgHATYiwD4IsBEB9kGAjQiwDwJsRIB9EGAjAuyDABsRYB8E2IgA+yDARgTYBwE2IsA+CLARAfZBgI0IsA8CbESAfRBgIwLsgwAbEWAfBNiIAPt49gB/XP5cLtZL9+btURTg+FjOeYnG9ZFr9pSePcDxIMOFw2YZ10eu2VMiQEQIEK5mH+Bc7gHnavb3gECIAOGKAOGKAOGKAOGKAOGKAOHqH/hFbjVY4i/uAAAAAElFTkSuQmCC';

abstract class HomeRepository {
  List<VaultBucket> get vaults;
  List<UnlockIdentity> get identities;
  List<NoteEntry> get seededNotes;
}

class SeededHomeRepository implements HomeRepository {
  SeededHomeRepository({
    DateTime? seedBaseDate,
    bool useEnglishSeedData = false,
  }) : _seedBaseDate = seedBaseDate ?? DateTime.now(),
       _useEnglishSeedData = useEnglishSeedData;

  final DateTime _seedBaseDate;
  final bool _useEnglishSeedData;

  String _seedText({required String ja, required String en}) =>
      _useEnglishSeedData ? en : ja;

  @override
  List<VaultBucket> get vaults => const [
    VaultBucket(id: 'everyday', name: 'Notes', description: ''),
    VaultBucket(
      id: 'decoy',
      name: 'Travel Scrap',
      description: '見せても自然な旅行記や写真メモを置くための領域です。',
    ),
    VaultBucket(
      id: 'private',
      name: 'Locked profile',
      description: 'プロファイルを解除したときだけ表示されるメモです。',
    ),
  ];

  @override
  List<UnlockIdentity> get identities => const [
    UnlockIdentity(
      id: 'daily',
      name: 'Notes',
      tagline: '標準のノート領域です。',
      lockLabel: 'Standard access',
      visibleVaultIds: ['everyday'],
      accentHex: 0xFF6B8798,
      warning: '通常表示ではロック中のプロファイルは見えません。',
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
  List<NoteEntry> get seededNotes {
    final seedToday = DateTime(
      _seedBaseDate.year,
      _seedBaseDate.month,
      _seedBaseDate.day,
    );
    DateTime seededAt(int daysAgo, int hour, int minute) {
      final candidate = seedToday
          .subtract(Duration(days: daysAgo))
          .add(Duration(hours: hour, minutes: minute));
      if (daysAgo != 0 || !candidate.isAfter(_seedBaseDate)) {
        return candidate;
      }

      final currentMinuteOfDay =
          (_seedBaseDate.hour * Duration.minutesPerHour) + _seedBaseDate.minute;
      if (currentMinuteOfDay == 0) {
        return seedToday;
      }

      final targetMinuteOfDay = (hour * Duration.minutesPerHour) + minute;
      final minutesBeforeNow = (Duration.minutesPerDay - targetMinuteOfDay)
          .clamp(1, 180);
      final adjustedMinuteOfDay = math.max(
        0,
        currentMinuteOfDay - minutesBeforeNow,
      );
      return seedToday.add(Duration(minutes: adjustedMinuteOfDay));
    }

    return [
      NoteEntry(
        id: 'seed-2026-04-12-groceries',
        vaultId: 'everyday',
        title: _seedText(ja: '買い物メモ', en: 'Shopping list'),
        body: _seedText(
          ja: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
          en: 'Milk, eggs, and fruit. Stop by the drugstore on the way home.',
        ),
        createdAt: seededAt(0, 23, 7),
        updatedAt: seededAt(0, 23, 7),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-12-groceries',
        tags: _useEnglishSeedData
            ? const ['shopping', 'daily']
            : const ['買い物', '日常'],
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
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '牛乳、卵、果物。帰りにドラッグストアにも寄る。',
              en: 'Milk, eggs, and fruit. Stop by the drugstore on the way home.',
            ),
          ),
          const NoteBlock(
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
        title: _seedText(ja: '共有会の準備', en: 'Sharing meeting prep'),
        body: _seedText(
          ja: '資料の見せ方を先に整理すると、共有会が短く終わりそう。',
          en: 'If we organize the document flow first, the sharing meeting should be shorter.',
        ),
        createdAt: seededAt(0, 22, 2),
        updatedAt: seededAt(0, 22, 2),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-12-idea',
        syncState: NoteSyncState.synced,
      ),
      NoteEntry(
        id: 'seed-2026-04-11-diary',
        vaultId: 'everyday',
        title: _seedText(ja: '日記', en: 'Journal'),
        body: _seedText(
          ja: '今日は集中して書けた。夜は静かで、考え事がまとまった。',
          en: 'I wrote with focus today. The quiet evening helped my thoughts settle.',
        ),
        createdAt: seededAt(1, 21, 39),
        updatedAt: seededAt(1, 21, 39),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-11-diary',
        tags: _useEnglishSeedData ? const ['journal'] : const ['日記'],
        syncState: NoteSyncState.synced,
      ),
      NoteEntry(
        id: 'seed-2026-04-11-walk',
        vaultId: 'everyday',
        title: _seedText(ja: '川沿いを歩いた', en: 'Walk by the river'),
        body: _seedText(
          ja: '風が強かったけれど、夕方の色がきれいだった。',
          en: 'The wind was strong, but the evening colors were clear.',
        ),
        createdAt: seededAt(1, 18, 15),
        updatedAt: seededAt(1, 18, 15),
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
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '風が強かったけれど、夕方の色がきれいだった。',
              en: 'The wind was strong, but the evening colors were clear.',
            ),
          ),
          const NoteBlock(
            type: NoteBlockType.photo,
            attachment: NoteAttachment(
              type: AttachmentType.photo,
              label: 'evening-walk.png',
              previewBytesBase64: _seedPhotoCool,
            ),
          ),
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '橋の下でメモを取り直した。次は動画でも残したい。',
              en: 'I rewrote the note under the bridge. Next time I want to save a video too.',
            ),
          ),
        ],
      ),
      NoteEntry(
        id: 'seed-2026-04-10-plan',
        vaultId: 'everyday',
        title: _seedText(ja: '週末の予定', en: 'Weekend plan'),
        body: _seedText(
          ja: '午前に掃除、午後に本屋、夜は家で映画。',
          en: 'Clean in the morning, visit the bookstore in the afternoon, movie at home at night.',
        ),
        createdAt: seededAt(2, 8, 20),
        updatedAt: seededAt(2, 8, 20),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-10-plan',
        tags: _useEnglishSeedData ? const ['plan', 'work'] : const ['予定', '仕事'],
        syncState: NoteSyncState.synced,
      ),
      NoteEntry(
        id: 'seed-2026-04-09-trip',
        vaultId: 'decoy',
        title: _seedText(ja: '大阪駅のメモ', en: 'Station transfer note'),
        body: _seedText(
          ja: '案内板が見やすくなっていた。乗り換え動画も残しておく。',
          en: 'The signs were easier to read. Save a transfer video for later.',
        ),
        createdAt: seededAt(3, 19, 5),
        updatedAt: seededAt(3, 19, 5),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-09-trip',
        tags: _useEnglishSeedData
            ? const ['travel', 'station']
            : const ['旅行', '駅'],
        syncState: NoteSyncState.synced,
        editorMode: NoteEditorMode.rich,
        attachments: const [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'station-sign.png',
            previewBytesBase64: _seedPhotoStation,
          ),
          NoteAttachment(
            type: AttachmentType.video,
            label: 'platform-walkthrough.mp4',
          ),
        ],
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '案内板が見やすくなっていた。乗り換え動画も残しておく。',
              en: 'The signs were easier to read. Save a transfer video for later.',
            ),
          ),
          const NoteBlock(
            type: NoteBlockType.photo,
            attachment: NoteAttachment(
              type: AttachmentType.photo,
              label: 'station-sign.png',
              previewBytesBase64: _seedPhotoStation,
            ),
          ),
          const NoteBlock(
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
        title: _seedText(ja: 'カフェのBGM', en: 'Cafe background music'),
        body: _seedText(
          ja: '落ち着いた音が流れていた。音量感をメモしておく。',
          en: 'Calm music was playing. Note the volume and mood.',
        ),
        createdAt: seededAt(4, 14, 10),
        updatedAt: seededAt(4, 14, 10),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-08-cafe',
        tags: _useEnglishSeedData
            ? const ['audio', 'cafe']
            : const ['音声', 'カフェ'],
        syncState: NoteSyncState.synced,
        editorMode: NoteEditorMode.rich,
        attachments: const [
          NoteAttachment(type: AttachmentType.audio, label: 'cafe-bgm.m4a'),
        ],
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '落ち着いた音が流れていた。音量感をメモしておく。',
              en: 'Calm music was playing. Note the volume and mood.',
            ),
          ),
          const NoteBlock(
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
        title: _seedText(ja: '会議メモ', en: 'Meeting note'),
        body: _seedText(
          ja: '開始は10分遅れ。共有資料の見出しを先に整える。',
          en: 'Started ten minutes late. Clean up the shared deck headings first.',
        ),
        createdAt: seededAt(5, 9, 40),
        updatedAt: seededAt(5, 9, 40),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-07-board',
        syncState: NoteSyncState.synced,
      ),
      NoteEntry(
        id: 'seed-2026-04-06-private-draft',
        vaultId: 'private',
        title: _seedText(ja: '静かな下書き', en: 'Private draft'),
        body: _seedText(
          ja: 'ここは本当に見せたくない考えをまとめるためのメモ。',
          en: 'A note for thoughts that should stay in the private profile.',
        ),
        createdAt: seededAt(6, 23, 15),
        updatedAt: seededAt(6, 23, 15),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-06-private-draft',
        tags: _useEnglishSeedData
            ? const ['personal', 'draft']
            : const ['個人', '下書き'],
        isPinned: true,
        syncState: NoteSyncState.synced,
      ),
      NoteEntry(
        id: 'seed-2026-04-05-private-photo',
        vaultId: 'private',
        title: _seedText(ja: '机のレイアウト案', en: 'Desk layout idea'),
        body: _seedText(
          ja: '紙の配置だけ残して、本文はあとで追記する。',
          en: 'Save the paper layout first and add the details later.',
        ),
        createdAt: seededAt(7, 22, 30),
        updatedAt: seededAt(7, 22, 30),
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
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '紙の配置だけ残して、本文はあとで追記する。',
              en: 'Save the paper layout first and add the details later.',
            ),
          ),
          const NoteBlock(
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
        title: _seedText(ja: '音声メモ', en: 'Audio memo'),
        body: _seedText(
          ja: '歩きながら録った短いメモ。あとでテキスト化する。',
          en: 'A short note recorded while walking. Transcribe it later.',
        ),
        createdAt: seededAt(7, 7, 55),
        updatedAt: seededAt(7, 7, 55),
        deviceId: 'seeded-device',
        contentHash: 'seed-2026-04-03-private-audio',
        syncState: NoteSyncState.synced,
        editorMode: NoteEditorMode.rich,
        attachments: const [
          NoteAttachment(type: AttachmentType.audio, label: 'walking-note.m4a'),
        ],
        blocks: [
          NoteBlock(
            type: NoteBlockType.paragraph,
            text: _seedText(
              ja: '歩きながら録った短いメモ。あとでテキスト化する。',
              en: 'A short note recorded while walking. Transcribe it later.',
            ),
          ),
          const NoteBlock(
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
}
