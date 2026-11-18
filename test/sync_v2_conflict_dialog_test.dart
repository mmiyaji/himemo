import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_conflict_dialog.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/presentation/sync_v2_privacy.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

import 'support/sync_v2_conflict_fixture.dart';
import 'support/sync_v2_workspace_fixture.dart';

void main() {
  for (final mode in [
    'resolve',
    'lock',
    'background',
    'locked_before_open',
    'lock_before_build',
  ]) {
    final lock = mode != 'resolve';
    testWidgets(
      lock ? 'private conflict disappears on $mode' : 'conflict dialog reviews real branches and commits the selected version',
      (tester) async {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        addTearDown(
          () => tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          ),
        );
        final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
        addTearDown(workspace.dispose);
        if (lock) {
          await tester.runAsync(
            () => workspace.createProfile('private', '5678'),
          );
        }
        final fixture = (await tester.runAsync(
          () => createSyncV2TestConflict(workspace),
        ))!;
        expect(fixture.note.syncState, NoteSyncState.conflict);
        final container = ProviderContainer(
          overrides: [
            syncV2WorkspaceProvider.overrideWithValue(workspace),
            noteStoreProvider.overrideWithValue(fixture.store),
          ],
        );
        addTearDown(container.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MaterialApp(
              home: Scaffold(
                body: Consumer(
                  builder: (context, ref, _) => TextButton(
                    onPressed: () =>
                        showSyncV2ConflictDialog(context, ref, fixture.note),
                    child: const Text('Review conflict'),
                  ),
                ),
              ),
            ),
          ),
        );
        if (mode == 'locked_before_open' || mode == 'lock_before_build') {
          if (mode == 'locked_before_open') workspace.lockPrivate();
          await tester.tap(find.text('Review conflict'));
          if (mode == 'lock_before_build') workspace.lockPrivate();
          await tester.pumpAndSettle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.text('Choose the version to keep'), findsNothing);
          expect(container.read(syncV2PrivacyActiveProvider), isFalse);
          if (mode == 'locked_before_open') {
            expect(
              find.text('Unlock this profile before reviewing its conflict.'),
              findsOneWidget,
            );
          }
          expect(tester.takeException(), isNull);
          return;
        }
        await tester.runAsync(() async {
          await tester.tap(find.text('Review conflict'));
          await tester.pump();
          await fixture.store.readConflict(fixture.note);
        });
        await tester.pumpAndSettle();
        expect(find.textContaining('Local version'), findsOneWidget);
        expect(find.textContaining('Remote version'), findsOneWidget);
        expect(container.read(syncV2PrivacyActiveProvider), isTrue);
        if (lock) {
          if (mode == 'background') {
            for (final state in [
              AppLifecycleState.inactive,
              AppLifecycleState.hidden,
              AppLifecycleState.paused,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
            expect(workspace.noteStoreSession, isNull);
            for (final state in [
              AppLifecycleState.hidden,
              AppLifecycleState.inactive,
              AppLifecycleState.resumed,
            ]) {
              tester.binding.handleAppLifecycleStateChanged(state);
            }
          } else {
            workspace.lockPrivate();
          }
          await tester.pumpAndSettle();
          await tester.runAsync(() => Future<void>.delayed(Duration.zero));
          await tester.pumpAndSettle();
          expect(find.text('Choose the version to keep'), findsNothing);
          expect(container.read(syncV2PrivacyActiveProvider), isFalse);
        } else {
          expect(
            tester
                .widget<FilledButton>(
                  find.widgetWithText(FilledButton, 'Keep this version'),
                )
                .onPressed,
            isNull,
          );
          await tester.tap(find.textContaining('Remote version'));
          await tester.pump();
          await tester.runAsync(() async {
            await tester.tap(find.text('Keep this version'));
            await fixture.store.readConflict(fixture.note);
          });
          await tester.pumpAndSettle();
          expect(find.text('Choose the version to keep'), findsNothing);
          final resolved = (await tester.runAsync(
            () => fixture.store.load(fallbackNotes: []),
          ))!.single;
          expect(resolved.title, 'Remote version');
          expect(resolved.syncState, isNot(NoteSyncState.conflict));
          expect(container.read(syncV2PrivacyActiveProvider), isFalse);
        }

        expect(tester.takeException(), isNull);
      },
    );
  }
}
