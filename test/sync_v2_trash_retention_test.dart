import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_note_store.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sync_v2_workspace_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('expired deleted conflict survives reload without hiding or blocking normal notes', () async {
    final h = await _harness();
    final session = h.workspace.noteStoreSession!;
    final profile = session.normalProfileId;
    final noteId = SyncV2NoteStore.v2NoteId(h.candidate.id);
    final access = session.profiles[profile]!;
    final base = await h.workspace.repository.readNote(
      generationId: session.generationId,
      profileId: profile,
      noteId: noteId,
      syncKey: session.syncKey,
      profileKey: access,
    );
    final expired = DateTime.now().subtract(const Duration(days: 8));
    final payloads = SyncV2PayloadCodec(EncryptionService());
    // Both real encrypted heads consume the same parent, just as concurrent
    // edits on two devices would. Lexical header order selects the old deleted
    // body in SyncV2NoteStore.load, while the second live head must survive.
    for (final branch in [
      (
        id: 'a_expired_deleted_head',
        note: h.candidate.copyWith(
          deletedAt: expired,
          updatedAt: expired,
          syncState: NoteSyncState.pendingDelete,
        ),
      ),
      (
        id: 'z_concurrent_live_head',
        note: h.candidate.copyWith(title: 'Concurrent live version'),
      ),
    ]) {
      final prepared = await payloads.seal(
        generationId: session.generationId,
        changeId: branch.id,
        profileId: profile,
        noteId: noteId,
        parentIds: base.headIds,
        body: {
          'type': 'note',
          'note': branch.note.copyWith(id: noteId, vaultId: profile).toJson(),
          'attachments': [],
        },
        profileKey: access.key,
      );
      await h.workspace.inbox.queuePublication(
        generationId: session.generationId,
        change: prepared.change,
        encryptedPayload: prepared.encryptedPayload,
        syncKey: session.syncKey,
      );
    }
    final before = await h.snapshot();
    expect(before.hasConflict, isTrue);
    expect(before.headIds, {
      'a_expired_deleted_head',
      'z_concurrent_live_head',
    });

    await h.controller.reloadFromStorage();
    expect(h.notes.map((note) => note.id).toSet(), {
      h.normal.id,
      h.candidate.id,
    });
    final conflict = h.candidateInState;
    expect(conflict.deletedAt, expired);
    expect(conflict.syncState, NoteSyncState.conflict);
    expect(conflict.isPermanentlyDeleted, isFalse);
    expect(
      h.store.purgeAttempts,
      0,
      reason: 'Automatic retention must skip unresolved heads',
    );
    expect((await h.snapshot()).headIds, before.headIds);

    await expectLater(
      h.controller.upsert(conflict.copyWith(title: 'Unacknowledged overwrite')),
      throwsA(isA<SyncV2StaleNote>()),
    );
    await h.controller.upsert(
      h.normal.copyWith(title: 'Normal edit still saves'),
    );
    await h.controller.reloadFromStorage();
    expect(
      h.notes.singleWhere((note) => note.id == h.normal.id).title,
      'Normal edit still saves',
    );
    expect(h.candidateInState.syncState, NoteSyncState.conflict);
    expect(h.candidateInState.deletedAt, expired);
    expect((await h.snapshot()).headIds, before.headIds);
    expect(h.store.purgeAttempts, 0);
  });

  test('failed automatic purge keeps loaded notes usable and retries on a later reload', () async {
    final h = await _harness();
    final expired = DateTime.now().subtract(const Duration(days: 8));
    await h.store.saveOne(
      h.candidate.copyWith(
        deletedAt: expired,
        updatedAt: expired,
        syncState: NoteSyncState.pendingDelete,
      ),
    );
    h.store.failPurge = true;
    final before = await h.snapshot();

    await h.controller.reloadFromStorage();
    expect(h.store.purgeAttempts, 1);
    expect(h.notes.map((note) => note.id).toSet(), {
      h.normal.id,
      h.candidate.id,
    });
    expect(h.candidateInState.deletedAt, expired);
    expect(h.candidateInState.isPermanentlyDeleted, isFalse);
    expect(
      (await h.snapshot()).headIds,
      before.headIds,
      reason: 'A failed purge must not publish a tombstone',
    );

    await h.controller.upsert(
      h.normal.copyWith(title: 'Edit after maintenance failure'),
    );
    await h.controller.reloadFromStorage();
    expect(
      h.store.purgeAttempts,
      2,
      reason: 'Maintenance failure must leave the note available for retry',
    );
    expect(
      h.notes.singleWhere((note) => note.id == h.normal.id).title,
      'Edit after maintenance failure',
    );
    expect(h.candidateInState.isPermanentlyDeleted, isFalse);
    expect((await h.snapshot()).headIds, before.headIds);
  });
}

class _PurgeObservedStore extends SyncV2NoteStore {
  _PurgeObservedStore({required super.repository, required super.session});

  bool failPurge = false;
  int purgeAttempts = 0;

  @override
  Future<NoteEntry> saveOne(NoteEntry note) {
    if (note.isPermanentlyDeleted) {
      purgeAttempts++;
      if (failPurge) throw StateError('Synthetic retention write failure');
    }
    return super.saveOne(note);
  }
}

class _Harness {
  _Harness(
    this.workspace,
    this.store,
    this.container,
    this.normal,
    this.candidate,
  );

  final SyncV2WorkspaceController workspace;
  final _PurgeObservedStore store;
  final ProviderContainer container;
  final NoteEntry normal;
  final NoteEntry candidate;

  NotesController get controller =>
      container.read(notesControllerProvider.notifier);
  List<NoteEntry> get notes => container.read(notesControllerProvider);
  NoteEntry get candidateInState =>
      notes.singleWhere((note) => note.id == candidate.id);

  Future<SyncV2NoteSnapshot> snapshot() {
    final session = workspace.noteStoreSession!;
    return workspace.repository.readNote(
      generationId: session.generationId,
      profileId: session.normalProfileId,
      noteId: SyncV2NoteStore.v2NoteId(candidate.id),
      syncKey: session.syncKey,
      profileKey: session.profiles[session.normalProfileId]!,
    );
  }
}

Future<_Harness> _harness() async {
  SharedPreferences.setMockInitialValues({});
  configureFlavor(AppFlavor.development);
  final workspace = await createSyncV2TestWorkspace();
  addTearDown(workspace.dispose);
  final store = _PurgeObservedStore(
    repository: workspace.repository,
    session: () => workspace.noteStoreSession,
  );
  NoteEntry note(String id) => NoteEntry(
    id: id,
    vaultId: 'everyday',
    title: id,
    body: 'Original body for $id',
    createdAt: DateTime.now(),
    deviceId: 'retention-fixture',
  );
  final normal = await store.saveOne(note('normal'));
  final candidate = await store.saveOne(note('trash-candidate'));
  final container = ProviderContainer(
    overrides: [
      syncV2WorkspaceProvider.overrideWithValue(workspace),
      noteStoreProvider.overrideWithValue(store),
      secureKeyValueStoreProvider.overrideWithValue(
        MemorySecureKeyValueStore(),
      ),
    ],
  );
  addTearDown(container.dispose);
  final h = _Harness(workspace, store, container, normal, candidate);
  await h.controller.restoreCompleted;
  expect(h.notes, hasLength(2));
  return h;
}
