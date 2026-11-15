import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'renders grouped notes in caller order and keeps previews metadata-only',
    (tester) async {
      var attachmentStoreReads = 0;
      NoteEntry note({
        required String id,
        required String title,
        required DateTime createdAt,
        List<NoteAttachment> attachments = const [],
      }) => NoteEntry(
        id: id,
        vaultId: 'everyday',
        title: title,
        body: 'Preview for $title',
        createdAt: createdAt,
        attachments: attachments,
      );

      final later = note(
        id: 'later',
        title: 'Caller first',
        createdAt: DateTime(2025, 6, 12, 10),
        attachments: const [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'legacy photo',
            filePath: 'legacy/encrypted/path',
          ),
        ],
      );
      final earlier = note(
        id: 'earlier',
        title: 'Caller second',
        createdAt: DateTime(2025, 6, 11, 10),
      );
      NoteEntry? selected;

      Widget app(NotesListDensity density) => ProviderScope(
        overrides: [
          encryptedAttachmentStoreProvider.overrideWith((ref) {
            attachmentStoreReads++;
            throw StateError('legacy attachment store must not be read');
          }),
        ],
        child: MaterialApp(
          locale: const Locale('en'),
          localizationsDelegates: [AppStrings.delegate],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: HomeNotePreviewList(
              notes: [later, earlier],
              profileName: 'Everyday profile',
              selectedNoteId: 'earlier',
              density: density,
              statusBuilder: (note) => Text('status-${note.id}'),
              onNoteSelected: (note) => selected = note,
            ),
          ),
        ),
      );

      await tester.pumpWidget(app(NotesListDensity.standard));
      await tester.pumpAndSettle();
      expect(find.text('Caller first'), findsOneWidget);
      expect(find.text('Caller second'), findsOneWidget);
      expect(find.text('Everyday profile'), findsNWidgets(2));
      expect(find.text('legacy photo'), findsOneWidget);
      expect(find.text('status-later'), findsOneWidget);
      expect(find.text('status-earlier'), findsOneWidget);
      expect(find.textContaining('June 12, 2025'), findsOneWidget);
      expect(find.textContaining('June 11, 2025'), findsOneWidget);
      final selectedTile = find.byKey(const Key('note-tile-earlier'));
      expect(selectedTile, findsOneWidget);
      final selectedFill = Theme.of(tester.element(selectedTile))
          .colorScheme
          .surfaceContainerHighest;
      expect(
        find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == selectedFill,
        ),
        findsOneWidget,
      );
      expect(
        tester.getTopLeft(find.byKey(const Key('note-tile-later'))).dy,
        lessThan(
          tester.getTopLeft(find.byKey(const Key('note-tile-earlier'))).dy,
        ),
      );
      expect(attachmentStoreReads, 0);

      await tester.tap(find.byKey(const Key('note-tile-later')));
      await tester.pump();
      expect(selected, same(later));

      await tester.pumpWidget(app(NotesListDensity.compact));
      await tester.pumpAndSettle();
      expect(find.textContaining('June 12, 2025'), findsNothing);
      expect(find.textContaining('June 11, 2025'), findsNothing);
      expect(attachmentStoreReads, 0);
    },
  );

  testWidgets('shows localized empty state and shared home wrappers', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: Scaffold(
          appBar: AppBar(title: const HomeBrandTitle()),
          body: Column(
            children: [
              HomeNoteSection(child: const Text('Section content')),
              const Expanded(
                child: HomeNotePreviewList(
                  notes: [],
                  profileName: 'Profile',
                  onNoteSelected: _ignoreNote,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('HiMemo'), findsOneWidget);
    expect(find.text('Section content'), findsOneWidget);
    expect(find.text('メモはありません'), findsOneWidget);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        home: const Scaffold(
          body: HomeNotePreviewList(
            notes: [],
            profileName: 'Profile',
            onNoteSelected: _ignoreNote,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('No notes yet'), findsOneWidget);
  });
}

void _ignoreNote(NoteEntry _) {}
