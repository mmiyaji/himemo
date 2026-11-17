import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_insights_view.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() {
  testWidgets(
    'only aggregates ready non-archived notes from the selected profile',
    (tester) async {
      final otherProfileNote = NoteEntry(
        id: 'note_private',
        vaultId: 'profile_other',
        title: 'Private note',
        body: 'must not contribute',
        createdAt: DateTime(2026, 11, 16, 12),
      );
      final entry = SyncV2WorkspaceNote(
        otherProfileNote,
        SyncV2NoteSnapshot(
          versions: [
            SyncV2NoteVersion(
              change: SyncV2Change(
                id: 'change_private',
                profileId: 'profile_other',
                noteId: otherProfileNote.id,
                operation: SyncV2Operation.upsert,
                parentIds: {},
                payloadDigest: 'digest',
              ),
              payloadAvailable: true,
              body: {'type': 'note', 'note': otherProfileNote.toJson()},
            ),
          ],
          pendingIds: {},
        ),
        const [],
      );
      final archivedNote = NoteEntry(
        id: 'note_archived',
        vaultId: 'profile_selected',
        title: 'Archived note',
        body: 'must not contribute',
        createdAt: DateTime(2026, 11, 16, 12),
        archivedAt: DateTime(2026, 11, 16, 13),
      );
      final archivedEntry = SyncV2WorkspaceNote(
        archivedNote,
        SyncV2NoteSnapshot(
          versions: [
            SyncV2NoteVersion(
              change: SyncV2Change(
                id: 'change_archived',
                profileId: 'profile_selected',
                noteId: archivedNote.id,
                operation: SyncV2Operation.upsert,
                parentIds: {},
                payloadDigest: 'digest',
              ),
              payloadAvailable: true,
              body: {'type': 'note', 'note': archivedNote.toJson()},
            ),
          ],
          pendingIds: {},
        ),
        const [],
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppStrings.supportedLocales,
          home: Scaffold(
            body: SyncV2InsightsView(
              profileId: 'profile_selected',
              notes: [entry, archivedEntry],
              now: DateTime(2026, 11, 16),
            ),
          ),
        ),
      );

      expect(
        find.text('Writing activity appears here when this profile has notes.'),
        findsOneWidget,
      );
      expect(find.text('This month'), findsNothing);
      expect(find.text('Private note'), findsNothing);
    },
  );
}
