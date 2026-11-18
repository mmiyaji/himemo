import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_note_store.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sync_v2_workspace_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'normal save cannot restore private plaintext concealed during preparation',
    () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      final gate = harness.rules.holdPreparation();
      final saving = controller.upsert(
        harness.normal.copyWith(title: 'Saved normally'),
      );
      await gate.entered.future;
      try {
        controller.concealPrivateNotes();
        expect(harness.privateInState.deviceId, 'locked-private-note');
        expect(harness.privateInState.body, isEmpty);
      } finally {
        gate.release.complete();
      }
      await saving;

      expect(harness.privateInState.deviceId, 'locked-private-note');
      expect(harness.privateInState.title, 'Locked private note');
      expect(harness.privateInState.body, isEmpty);
      expect(harness.privateInState.tags, isEmpty);
      expect(
        harness.container
            .read(notesControllerProvider)
            .singleWhere((note) => note.id == harness.normal.id)
            .title,
        'Saved normally',
      );
      final stored = await harness.store.load(fallbackNotes: const []);
      expect(
        stored.singleWhere((note) => note.id == harness.private.id).toJson(),
        harness.private.toJson(),
        reason:
            'Concealing content must not change the encrypted private note.',
      );
    },
  );

  test(
    'tag rename waits for sync reload and preserves a newly arrived note',
    () async {
      final harness = await _createHarness();
      await harness.controller.upsert(
        harness.normal.copyWith(tags: ['before']),
      );
      // Model a sync arrival in the real repository before the UI has reloaded.
      final arrived = await harness.store.saveOne(
        NoteEntry(
          id: 'arrived-during-reload',
          vaultId: 'everyday',
          title: 'Newly synced note',
          body: 'Must survive a concurrent bulk save',
          createdAt: DateTime.now(),
          deviceId: 'other-device',
        ),
      );
      final gate = harness.store.holdNextLoad();
      final reloading = harness.controller.reloadFromStorage();
      await gate.entered.future;
      var renameCompleted = false;
      final renaming = harness.controller
          .renameTag(from: 'before', to: 'after')
          .then((count) {
            renameCompleted = true;
            return count;
          });
      try {
        await Future<void>.delayed(Duration.zero);
        expect(renameCompleted, isFalse);
      } finally {
        gate.release.complete();
      }
      await reloading;
      expect(await renaming, 1);
      final current = harness.container.read(notesControllerProvider);
      expect(
        current.singleWhere((note) => note.id == arrived.id).toJson(),
        arrived.toJson(),
      );
      expect(current.singleWhere((note) => note.id == harness.normal.id).tags, [
        'after',
      ]);
      final stored = await harness.store.load(fallbackNotes: const []);
      expect(
        stored.singleWhere((note) => note.id == arrived.id).toJson(),
        arrived.toJson(),
      );
      expect(stored.singleWhere((note) => note.id == harness.normal.id).tags, [
        'after',
      ]);
      final workspace = harness.container.read(syncV2WorkspaceProvider);
      final session = workspace.noteStoreSession!;
      final history = await workspace.repository.readNote(
        generationId: session.generationId,
        profileId: session.normalProfileId,
        noteId: SyncV2NoteStore.v2NoteId(arrived.id),
        syncKey: session.syncKey,
        profileKey: session.profiles[session.normalProfileId]!,
      );
      expect(history.versions, isNotEmpty);
      expect(history.versions.where((version) => version.isDeleted), isEmpty);
    },
  );

  test(
    'storage reload waits for a pending upsert and keeps its saved edit',
    () async {
      final harness = await _createHarness();
      final gate = harness.rules.holdPreparation();
      final saving = harness.controller.upsert(
        harness.normal.copyWith(title: 'Queued edit'),
      );
      await gate.entered.future;
      final loadsBeforeReload = harness.store.loads;
      var reloadCompleted = false;
      final reloading = harness.controller.reloadFromStorage().then((_) {
        reloadCompleted = true;
      });
      try {
        // Drain microtasks while preparation remains explicitly blocked. The
        // load counter detects an unqueued read without depending on I/O speed.
        await Future<void>.delayed(Duration.zero);
        expect(harness.store.loads, loadsBeforeReload);
        expect(reloadCompleted, isFalse);
        final readBeforeSave = await harness.store.load(
          fallbackNotes: const [],
        );
        expect(
          readBeforeSave
              .singleWhere((note) => note.id == harness.normal.id)
              .title,
          harness.normal.title,
        );
        expect(reloadCompleted, isFalse);
      } finally {
        gate.release.complete();
      }
      await saving;
      await reloading;
      expect(reloadCompleted, isTrue);
      expect(
        harness.container
            .read(notesControllerProvider)
            .singleWhere((note) => note.id == harness.normal.id)
            .title,
        'Queued edit',
      );
      final stored = await harness.store.load(fallbackNotes: const []);
      expect(
        stored.singleWhere((note) => note.id == harness.normal.id).title,
        'Queued edit',
      );
    },
  );

  test(
    'locked placeholders resist single-note and batch edits without data loss',
    () async {
      final harness = await _createHarness();
      final controller = harness.controller;
      controller.concealPrivateNotes();
      final concealed = harness.privateInState.toJson();

      await controller.archive(harness.private.id);
      await controller.unarchive(harness.private.id);
      await controller.togglePinned(harness.private.id);
      await controller.delete(harness.private.id);
      await expectLater(
        controller.upsert(
          harness.private.copyWith(title: 'Stale private editor'),
        ),
        throwsA(isA<SyncV2NoteStoreLocked>()),
      );
      expect(harness.privateInState.toJson(), concealed);

      // The private note is old enough to archive. Its placeholder title also
      // matches the first rule, so these guards exercise real eligible inputs.
      expect(
        await controller.archiveNotesOlderThan(const Duration(days: 30)),
        0,
      );
      expect(await controller.unarchiveAll(), 0);
      harness.rules.replaceRules([
        AutoTagRule(
          id: 'private-match',
          tag: 'must-not-add',
          keywords: const ['note'],
        ),
        AutoTagRule(
          id: 'normal-match',
          tag: 'invoice',
          keywords: const ['invoice'],
        ),
      ]);
      expect(await controller.applyAutoTagRulesToExisting(), 1);
      expect(harness.privateInState.toJson(), concealed);

      final stored = await harness.store.load(fallbackNotes: const []);
      expect(
        stored.singleWhere((note) => note.id == harness.private.id).toJson(),
        harness.private.toJson(),
        reason:
            'A full normal-profile save must preserve concealed private data.',
      );
      expect(stored.singleWhere((note) => note.id == harness.normal.id).tags, [
        'invoice',
      ]);
    },
  );
}

class _ControlledRules extends AutoTagRulesController {
  ({Completer<void> entered, Completer<void> release})? _gate;

  @override
  List<AutoTagRule> build() => const [];

  @override
  Future<void> get restoreCompleted {
    final gate = _gate;
    if (gate == null) return Future<void>.value();
    if (!gate.entered.isCompleted) gate.entered.complete();
    return gate.release.future;
  }

  ({Completer<void> entered, Completer<void> release}) holdPreparation() =>
      _gate = (entered: Completer<void>(), release: Completer<void>());

  void replaceRules(List<AutoTagRule> rules) => state = rules;
}

class _ObservedNoteStore extends SyncV2NoteStore {
  _ObservedNoteStore({required super.repository, required super.session});

  int loads = 0;
  ({Completer<void> entered, Completer<void> release})? _nextLoadGate;

  ({Completer<void> entered, Completer<void> release}) holdNextLoad() =>
      _nextLoadGate = (entered: Completer<void>(), release: Completer<void>());

  @override
  Future<List<NoteEntry>> load({required List<NoteEntry> fallbackNotes}) async {
    loads++;
    final gate = _nextLoadGate;
    _nextLoadGate = null;
    final loaded = await super.load(fallbackNotes: fallbackNotes);
    if (gate != null) {
      gate.entered.complete();
      await gate.release.future;
    }
    return loaded;
  }
}

class _Harness {
  _Harness(this.container, this.store, this.rules, this.normal, this.private);

  final ProviderContainer container;
  final _ObservedNoteStore store;
  final _ControlledRules rules;
  final NoteEntry normal;
  final NoteEntry private;

  NotesController get controller =>
      container.read(notesControllerProvider.notifier);
  NoteEntry get privateInState => container
      .read(notesControllerProvider)
      .singleWhere((note) => note.id == private.id);
}

Future<_Harness> _createHarness() async {
  SharedPreferences.setMockInitialValues({});
  configureFlavor(AppFlavor.development);
  final workspace = await createSyncV2TestWorkspace();
  addTearDown(workspace.dispose);
  await workspace.createProfile('Private', '5678');
  final privateVaultId = workspace.selectedProfileId!;
  final store = _ObservedNoteStore(
    repository: workspace.repository,
    session: () => workspace.noteStoreSession,
  );
  final normal = await store.saveOne(
    NoteEntry(
      id: 'normal',
      vaultId: 'everyday',
      title: 'Normal invoice',
      body: 'Visible normal content',
      createdAt: DateTime.now(),
      deviceId: 'fixture-device',
    ),
  );
  final private = await store.saveOne(
    NoteEntry(
      id: 'private',
      vaultId: privateVaultId,
      title: 'Private secret',
      body: 'Private plaintext must stay concealed',
      tags: const ['private-tag'],
      createdAt: DateTime.utc(2020),
      deviceId: 'fixture-device',
    ),
  );
  final rules = _ControlledRules();
  // Keep the real encrypted v2 store while controlling only the asynchronous
  // preparation boundary. Omitting the provider's workspace listener lets the
  // test observe concealment before any subsequent storage reload.
  final container = ProviderContainer(
    overrides: [
      syncV2WorkspaceProvider.overrideWithValue(workspace),
      noteStoreProvider.overrideWithValue(store),
      secureKeyValueStoreProvider.overrideWithValue(
        MemorySecureKeyValueStore(),
      ),
      autoTagRulesControllerProvider.overrideWith(() => rules),
    ],
  );
  addTearDown(container.dispose);
  await container.read(notesControllerProvider.notifier).restoreCompleted;
  container.read(autoTagRulesControllerProvider);
  expect(container.read(notesControllerProvider), hasLength(2));
  return _Harness(container, store, rules, normal, private);
}
