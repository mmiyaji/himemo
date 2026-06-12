import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('releaseNoteFromJson', () {
    test('rejects incomplete releases and normalizes localized fields', () {
      expect(releaseNoteFromJson(const {}), isNull);
      expect(
        releaseNoteFromJson(const {'version': '1.0.0', 'items': []}),
        isNull,
      );

      final release = releaseNoteFromJson({
        'version': ' 1.2.3 ',
        'date': 'not-a-date',
        'importance': null,
        'title': {'en': ' English title ', 'ja': '  ', 'es': 'Titulo'},
        'summary': {'fr': 'Fallback summary'},
        'items': [
          {
            'type': 'unknown',
            'title': {'en': ' Item ', 'de': ''},
            'body': {'ja': 'Body ja', 'en': ' Body '},
          },
        ],
      });

      expect(release, isNotNull);
      expect(release!.version, '1.2.3');
      expect(release.date, isNull);
      expect(release.importance, 'normal');
      expect(release.localizedTitle(const Locale('ja')), 'English title');
      expect(release.localizedTitle(const Locale('es')), 'Titulo');
      expect(release.localizedSummary(const Locale('ko')), 'Fallback summary');
      expect(release.items.single.type, ReleaseNoteItemType.improvement);
      expect(release.items.single.localizedTitle(const Locale('de')), 'Item');
      expect(release.items.single.localizedBody(const Locale('ja')), 'Body ja');
    });
  });

  group('quick capture DTOs', () {
    test('maps mime types and stringifies json defaults', () {
      expect(
        const QuickCaptureFile(
          path: 'p',
          name: 'a.jpg',
          mimeType: 'IMAGE/JPEG',
        ).attachmentType,
        AttachmentType.photo,
      );
      expect(
        const QuickCaptureFile(
          path: 'p',
          name: 'v.mp4',
          mimeType: 'video/mp4',
        ).attachmentType,
        AttachmentType.video,
      );
      expect(
        const QuickCaptureFile(
          path: 'p',
          name: 'a.m4a',
          mimeType: 'audio/mp4',
        ).attachmentType,
        AttachmentType.audio,
      );
      expect(
        const QuickCaptureFile(
          path: 'p',
          name: 'data.bin',
          mimeType: 'application/octet-stream',
        ).attachmentType,
        AttachmentType.file,
      );

      final file = QuickCaptureFile.fromJson({
        'path': 12,
        'name': null,
        'mimeType': true,
      });
      expect(file.path, '12');
      expect(file.name, '');
      expect(file.mimeType, 'true');

      final rejected = QuickCaptureRejectedFile.fromJson({
        'name': 'bad.exe',
        'mimeType': null,
        'reason': 404,
      });
      expect(rejected.name, 'bad.exe');
      expect(rejected.mimeType, '');
      expect(rejected.reason, '404');
    });
  });

  group('auto tag and sync exclusion logic', () {
    NoteEntry note({
      String title = 'Title',
      String body = 'Body',
      List<String> tags = const <String>[],
      List<NoteAttachment> attachments = const <NoteAttachment>[],
      DateTime? deletedAt,
      DateTime? archivedAt,
    }) {
      return NoteEntry(
        id: 'note',
        vaultId: 'everyday',
        title: title,
        body: body,
        createdAt: DateTime(2026, 6, 12),
        tags: tags,
        attachments: attachments,
        deletedAt: deletedAt,
        archivedAt: archivedAt,
      );
    }

    test('parses rules and matches selected note fields', () {
      expect(AutoTagRule.fromJson(null), isNull);
      expect(
        AutoTagRule.fromJson({
          'id': ' ',
          'tag': 'Work',
          'keywords': ['invoice'],
        }),
        isNull,
      );
      expect(
        AutoTagRule.fromJson({
          'id': 'rule',
          'tag': ' ',
          'keywords': ['invoice'],
        }),
        isNull,
      );
      expect(
        AutoTagRule.fromJson({'id': 'rule', 'tag': 'Work', 'keywords': []}),
        isNull,
      );

      final rule = AutoTagRule.fromJson({
        'id': ' rule ',
        'tag': ' Work ',
        'keywords': [' invoice ', 'INVOICE', '', 'receipt'],
        'enabled': false,
        'matchTitle': false,
        'matchBody': true,
        'matchAttachments': false,
      });
      expect(rule, isNotNull);
      expect(rule!.id, 'rule');
      expect(rule.tag, 'Work');
      expect(rule.keywords, ['invoice', 'receipt']);
      expect(rule.enabled, isFalse);
      expect(rule.toJson()['matchTitle'], isFalse);
      expect(rule.copyWith(enabled: true).enabled, isTrue);

      expect(splitAutoTagKeywords(' invoice, receipt\nmemo, TAX, invoice '), [
        'invoice',
        'receipt',
        'memo',
        'TAX',
      ]);

      final bodyOnly = rule.copyWith(enabled: true);
      expect(
        autoTagRuleMatchesNote(bodyOnly, note(body: 'paid invoice')),
        isTrue,
      );
      expect(
        autoTagRuleMatchesNote(bodyOnly, note(title: 'invoice', body: '')),
        isFalse,
      );
      expect(
        autoTagRuleMatchesNote(
          bodyOnly.copyWith(matchBody: false, matchAttachments: true),
          note(
            body: '',
            attachments: const [
              NoteAttachment(type: AttachmentType.file, label: 'receipt.pdf'),
            ],
          ),
        ),
        isTrue,
      );
      expect(
        autoTagRuleMatchesNote(
          bodyOnly.copyWith(matchBody: false, matchAttachments: false),
          note(body: ''),
        ),
        isFalse,
      );
    });

    test('applies tags once and skips archived or deleted notes', () {
      final rule = AutoTagRule(
        id: 'r1',
        tag: 'Finance',
        keywords: const ['invoice'],
      );
      final source = note(body: 'invoice attached', tags: const ['Work']);
      final tagged = applyAutoTagRules(source, [
        rule,
        rule.copyWith(id: 'r2', tag: 'finance'),
        rule.copyWith(id: 'r3', tag: ''),
        rule.copyWith(id: 'r4', enabled: false, tag: 'Skipped'),
      ]);

      expect(tagged.tags, ['Work', 'Finance']);
      expect(applyAutoTagRules(tagged, [rule]), same(tagged));

      final deleted = source.copyWith(deletedAt: DateTime(2026, 6, 13));
      expect(applyAutoTagRules(deleted, [rule]), same(deleted));

      final archived = source.copyWith(archivedAt: DateTime(2026, 6, 13));
      expect(applyAutoTagRules(archived, [rule]), same(archived));
    });

    test('detects sync exclusion tags case-insensitively', () {
      expect(noteExcludedFromSync(note(), const []), isFalse);
      expect(
        noteExcludedFromSync(note(tags: const ['Work']), const ['']),
        isFalse,
      );
      expect(
        noteExcludedFromSync(
          note(tags: const [systemSyncExcludedTag, 'Work']),
          const [' $systemSyncExcludedTag '],
        ),
        isTrue,
      );
      expect(isSystemSyncExclusionTag(systemSyncExcludedTag), isTrue);
      expect(isSystemSyncExclusionTag('Work'), isFalse);
    });
  });

  group('visibleNotesProvider filters', () {
    NoteEntry note({
      required String id,
      required DateTime createdAt,
      DateTime? updatedAt,
      bool isPinned = false,
      DateTime? archivedAt,
      DateTime? deletedAt,
      List<NoteAttachment> attachments = const <NoteAttachment>[],
      NoteLocation? location,
    }) {
      return NoteEntry(
        id: id,
        vaultId: 'everyday',
        title: id,
        body: 'body',
        createdAt: createdAt,
        updatedAt: updatedAt,
        isPinned: isPinned,
        archivedAt: archivedAt,
        deletedAt: deletedAt,
        attachments: attachments,
        location: location,
      );
    }

    ProviderContainer containerFor(List<NoteEntry> notes) {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer(
        overrides: [notesControllerProvider.overrideWithValue(notes)],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('narrows by pinned state and attachment categories', () {
      final container = containerFor([
        note(
          id: 'photo',
          createdAt: DateTime(2026, 6, 12, 10),
          isPinned: true,
          attachments: const [
            NoteAttachment(type: AttachmentType.photo, label: 'photo.jpg'),
          ],
        ),
        note(
          id: 'video',
          createdAt: DateTime(2026, 6, 12, 9),
          attachments: const [
            NoteAttachment(type: AttachmentType.video, label: 'clip.mp4'),
          ],
        ),
        note(
          id: 'audio',
          createdAt: DateTime(2026, 6, 12, 8),
          attachments: const [
            NoteAttachment(type: AttachmentType.audio, label: 'voice.m4a'),
          ],
        ),
        note(
          id: 'location',
          createdAt: DateTime(2026, 6, 12, 7),
          location: const NoteLocation(latitude: 35, longitude: 139),
        ),
        note(id: 'plain', createdAt: DateTime(2026, 6, 12, 6)),
      ]);

      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'photo',
        'video',
        'audio',
        'location',
        'plain',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setPinnedOnly(true);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'photo',
      ]);

      container.read(searchFiltersControllerProvider.notifier).reset();
      container
          .read(searchFiltersControllerProvider.notifier)
          .setAttachmentFilter(SearchAttachmentFilter.photo);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'photo',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setAttachmentFilter(SearchAttachmentFilter.audio);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'audio',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setAttachmentFilters(const [
            SearchAttachmentFilter.video,
            SearchAttachmentFilter.location,
          ]);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'video',
        'location',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setWithMediaOnly(true);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'photo',
        'video',
        'audio',
        'location',
      ]);
    });

    test('narrows by archive, year, and updated-at date ranges', () {
      final container = containerFor([
        note(
          id: 'archived',
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime.now(),
          archivedAt: DateTime(2026, 6, 1),
        ),
        note(
          id: 'recent',
          createdAt: DateTime(2025, 1, 1),
          updatedAt: DateTime.now(),
        ),
        note(
          id: 'old',
          createdAt: DateTime(2024, 1, 1),
          updatedAt: DateTime.now().subtract(const Duration(days: 40)),
        ),
        note(
          id: 'deleted',
          createdAt: DateTime(2026, 6, 12),
          deletedAt: DateTime(2026, 6, 13),
        ),
      ]);

      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'recent',
        'old',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setArchivedOnly(true);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'archived',
      ]);

      container.read(searchFiltersControllerProvider.notifier).reset();
      container.read(searchFiltersControllerProvider.notifier).setYear(2025);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'recent',
      ]);

      container.read(searchFiltersControllerProvider.notifier).reset();
      container
          .read(searchFiltersControllerProvider.notifier)
          .setDateField(SearchDateField.updatedAt);
      container
          .read(searchFiltersControllerProvider.notifier)
          .setDateRange(SearchDateRange.last30Days);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'recent',
      ]);
    });
  });
}
