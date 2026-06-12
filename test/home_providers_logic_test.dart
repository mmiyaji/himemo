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
      String vaultId = 'everyday',
      required DateTime createdAt,
      DateTime? updatedAt,
      bool isPinned = false,
      DateTime? archivedAt,
      DateTime? deletedAt,
      List<String> tags = const <String>[],
      List<NoteAttachment> attachments = const <NoteAttachment>[],
      NoteLocation? location,
    }) {
      return NoteEntry(
        id: id,
        vaultId: vaultId,
        title: id,
        body: 'body',
        createdAt: createdAt,
        updatedAt: updatedAt,
        isPinned: isPinned,
        archivedAt: archivedAt,
        deletedAt: deletedAt,
        tags: tags,
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

    test('filter controller normalizes toggles and clear operations', () {
      SharedPreferences.setMockInitialValues({});
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final controller = container.read(
        searchFiltersControllerProvider.notifier,
      );

      controller.setAttachmentFilters(const [
        SearchAttachmentFilter.all,
        SearchAttachmentFilter.photo,
        SearchAttachmentFilter.photo,
        SearchAttachmentFilter.video,
      ]);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        [SearchAttachmentFilter.photo, SearchAttachmentFilter.video],
      );

      controller.toggleAttachmentFilter(SearchAttachmentFilter.photo);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        [SearchAttachmentFilter.video],
      );
      controller.toggleAttachmentFilter(SearchAttachmentFilter.video);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        [SearchAttachmentFilter.any],
      );
      controller.toggleAttachmentFilter(SearchAttachmentFilter.audio);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        [SearchAttachmentFilter.audio],
      );
      controller.toggleAttachmentFilter(SearchAttachmentFilter.any);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        [SearchAttachmentFilter.any],
      );
      controller.toggleAttachmentFilter(SearchAttachmentFilter.all);
      expect(
        container.read(searchFiltersControllerProvider).attachmentFilters,
        isEmpty,
      );

      controller.setArchivedOnly(true);
      controller.setIncludeArchived(true);
      expect(
        container.read(searchFiltersControllerProvider).archivedOnly,
        isFalse,
      );
      expect(
        container.read(searchFiltersControllerProvider).includeArchived,
        isTrue,
      );

      controller.setYear(2026);
      controller.setYear(null);
      expect(container.read(searchFiltersControllerProvider).year, isNull);

      controller.setVault('everyday');
      controller.setVault('');
      expect(container.read(searchFiltersControllerProvider).vaultId, isNull);

      controller.setTags(const ['Alpha', 'Beta']);
      controller.setRequireAllTags(true);
      controller.removeTag(' beta ');
      final filters = container.read(searchFiltersControllerProvider);
      expect(filters.tags, ['Alpha']);
      expect(filters.requireAllTags, isFalse);
    });

    test('matches query text from attachment labels and locations', () {
      final container = containerFor([
        note(
          id: 'attachment-label',
          createdAt: DateTime(2026, 6, 12, 10),
          attachments: const [
            NoteAttachment(
              type: AttachmentType.file,
              label: 'boarding-pass.pdf',
            ),
          ],
        ),
        note(
          id: 'location-address',
          createdAt: DateTime(2026, 6, 12, 9),
          location: NoteLocation(
            latitude: 35,
            longitude: 139,
            address: 'Shibuya Station',
          ),
        ),
        note(
          id: 'deleted-match',
          createdAt: DateTime(2026, 6, 12, 8),
          deletedAt: DateTime(2026, 6, 13),
          attachments: const [
            NoteAttachment(
              type: AttachmentType.file,
              label: 'boarding-pass.pdf',
            ),
          ],
        ),
      ]);

      container.read(searchQueryProvider.notifier).setQuery('boarding');
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'attachment-label',
      ]);

      container.read(searchQueryProvider.notifier).setQuery('shibuya');
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'location-address',
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

    test('narrows recent ranges and switches created-at sorting', () {
      final now = DateTime.now();
      final container = containerFor([
        note(
          id: 'updated-recent-created-old',
          createdAt: now.subtract(const Duration(days: 90)),
          updatedAt: now.subtract(const Duration(days: 1)),
        ),
        note(
          id: 'created-recent',
          createdAt: now.subtract(const Duration(days: 2)),
          updatedAt: now.subtract(const Duration(days: 60)),
        ),
        note(
          id: 'eight-days-old',
          createdAt: now.subtract(const Duration(days: 8)),
          updatedAt: now.subtract(const Duration(days: 8)),
        ),
        note(
          id: 'previous-month',
          createdAt: DateTime(
            now.year,
            now.month,
            1,
          ).subtract(const Duration(days: 1)),
          updatedAt: DateTime(
            now.year,
            now.month,
            1,
          ).subtract(const Duration(days: 1)),
        ),
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setDateRange(SearchDateRange.last7Days);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'created-recent',
      ]);

      container
          .read(searchFiltersControllerProvider.notifier)
          .setDateField(SearchDateField.updatedAt);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'updated-recent-created-old',
      ]);

      container.read(searchFiltersControllerProvider.notifier).reset();
      container
          .read(searchFiltersControllerProvider.notifier)
          .setDateRange(SearchDateRange.thisMonth);
      container
          .read(notesListSortControllerProvider.notifier)
          .setSortField(NotesListSortField.createdAt);
      expect(container.read(visibleNotesProvider).map((entry) => entry.id), [
        'created-recent',
        'eight-days-old',
      ]);
    });

    test('visible tag summaries dedupe and ignore hidden notes', () {
      final latest = DateTime(2026, 6, 12, 12);
      final container = containerFor([
        note(id: 'work-new', createdAt: latest, tags: const ['Work', '']),
        note(
          id: 'work-old',
          createdAt: latest.subtract(const Duration(days: 1)),
          updatedAt: latest.subtract(const Duration(hours: 2)),
          tags: const [' work ', '#Personal'],
        ),
        note(
          id: 'archived-work',
          createdAt: latest,
          archivedAt: latest,
          tags: const ['Work'],
        ),
        note(
          id: 'deleted-work',
          createdAt: latest,
          deletedAt: latest,
          tags: const ['Work'],
        ),
        note(
          id: 'hidden-work',
          vaultId: 'private_profile:hidden',
          createdAt: latest,
          tags: const ['Work'],
        ),
      ]);

      final summaries = container.read(visibleTagSummariesProvider);

      expect(summaries.map((summary) => summary.name), ['Work', 'Personal']);
      expect(summaries.first.count, 2);
      expect(summaries.first.latestAt, latest);
      expect(summaries.last.count, 1);
    });

    test(
      'list display controllers restore, persist, and fallback safely',
      () async {
        SharedPreferences.setMockInitialValues({
          'notes.list_density': NotesListDensity.compact.name,
          'notes.attachment_preview_fit': AttachmentPreviewFit.icon.name,
          'notes.list_sort_field': NotesListSortField.createdAt.name,
        });
        final container = ProviderContainer();
        addTearDown(container.dispose);

        expect(
          container.read(notesListDensityControllerProvider),
          NotesListDensity.standard,
        );
        expect(
          container.read(attachmentPreviewFitControllerProvider),
          AttachmentPreviewFit.preview,
        );
        expect(
          container.read(notesListSortControllerProvider),
          NotesListSortField.updatedAt,
        );
        await pumpEventQueue();
        expect(
          container.read(notesListDensityControllerProvider),
          NotesListDensity.compact,
        );
        expect(
          container.read(attachmentPreviewFitControllerProvider),
          AttachmentPreviewFit.icon,
        );
        expect(
          container.read(notesListSortControllerProvider),
          NotesListSortField.createdAt,
        );

        await container
            .read(notesListDensityControllerProvider.notifier)
            .setDensity(NotesListDensity.standard);
        await container
            .read(attachmentPreviewFitControllerProvider.notifier)
            .setFit(AttachmentPreviewFit.preview);
        await container
            .read(notesListSortControllerProvider.notifier)
            .setSortField(NotesListSortField.updatedAt);
        final prefs = await SharedPreferences.getInstance();
        expect(
          prefs.getString('notes.list_density'),
          NotesListDensity.standard.name,
        );
        expect(
          prefs.getString('notes.attachment_preview_fit'),
          AttachmentPreviewFit.preview.name,
        );
        expect(
          prefs.getString('notes.list_sort_field'),
          NotesListSortField.updatedAt.name,
        );
      },
    );

    test('list display controllers ignore invalid restored values', () async {
      SharedPreferences.setMockInitialValues({
        'notes.list_density': 'tiny',
        'notes.attachment_preview_fit': 'cover',
        'notes.list_sort_field': 'title',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      container.read(notesListDensityControllerProvider);
      container.read(attachmentPreviewFitControllerProvider);
      container.read(notesListSortControllerProvider);
      await pumpEventQueue();

      expect(
        container.read(notesListDensityControllerProvider),
        NotesListDensity.standard,
      );
      expect(
        container.read(attachmentPreviewFitControllerProvider),
        AttachmentPreviewFit.preview,
      );
      expect(
        container.read(notesListSortControllerProvider),
        NotesListSortField.updatedAt,
      );
    });
  });
}
