import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart';

import '../../home/data/note_store.dart';
import '../../home/presentation/home_providers.dart';
import '../data/sync_v2_note_store.dart';
import '../data/sync_v2_attachment_service.dart';
import '../testing/sync_v2_local_preview.dart';
import 'sync_v2_workspace.dart';

/// Selects where `NotesController` persists notes.
///
/// - `v1` (default): local encrypted database.
/// - `v2`: Sync v2 history through the iCloud workspace.
/// - `v2-local`: Sync v2 history with an in-process stub instead of iCloud,
///   registered automatically. Development only; keys are kept in memory.
const noteBackend = String.fromEnvironment(
  'HIMEMO_NOTE_BACKEND',
  defaultValue: 'v1',
);

bool get usesSyncV2NoteBackend =>
    noteBackend == 'v2' || noteBackend == 'v2-local';

/// Provider overrides needed for [noteBackend]; pass to the root ProviderScope.
List<Override> noteBackendOverrides() => [
  if (noteBackend == 'v2-local')
    syncV2WorkspaceProvider.overrideWith((ref) {
      final workspace = createLocalPreviewController();
      ref.onDispose(workspace.dispose);
      unawaited(_registerLocalPreview(workspace));
      return workspace;
    }),
];

Future<void> _registerLocalPreview(SyncV2WorkspaceController workspace) async {
  await workspace.initialize();
  if (workspace.registered) return;
  await workspace.prepareNew('preview-password');
  await workspace.confirmSetup();
}

// Shared lookup avoids a Riverpod dependency cycle between the note writer and
// the attachment reader used by the existing viewer widgets.
final syncV2AttachmentLookupProvider = Provider<SyncV2AttachmentLookup>(
  (ref) => SyncV2AttachmentLookup(),
);

class SyncV2AttachmentLookup {
  SyncV2NoteStore? store;
}

final Provider<NoteStore> noteStoreProvider = Provider<NoteStore>((ref) {
  if (!usesSyncV2NoteBackend) return ref.watch(encryptedNoteStoreProvider);
  final workspace = ref.watch(syncV2WorkspaceProvider);
  if (noteBackend == 'v2') unawaited(workspace.initialize());
  final store = SyncV2NoteStore(
    repository: workspace.repository,
    session: () => workspace.noteStoreSession,
    attachmentService: SyncV2AttachmentService(
      workspace.inbox,
      workspace.repository,
    ),
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
  );
  final lookup = ref.watch(syncV2AttachmentLookupProvider);
  lookup.store = store;
  ref.onDispose(() {
    if (identical(lookup.store, store)) lookup.store = null;
  });
  // Reload v1 state when readable profiles change or a sync delivers notes.
  String? lastKey;
  void onChange() {
    final session = workspace.noteStoreSession;
    final key = session == null
        ? null
        : '${session.generationId}:${workspace.privateSessionRevision}:'
              '${(session.profiles.keys.toList()..sort()).join(',')}:'
              // The workspace replaces this list after every sync download.
              '${identityHashCode(workspace.notes)}';
    if (key == lastKey) return;
    lastKey = key;
    unawaited(ref.read(notesControllerProvider.notifier).reloadFromStorage());
  }

  Future.microtask(() {
    if (ref.mounted) onChange();
  });
  workspace.addListener(onChange);
  ref.onDispose(() => workspace.removeListener(onChange));
  return store;
});
