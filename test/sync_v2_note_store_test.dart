import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_note_store.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

const _normalId = 'normal_fixture';
const _privateId = 'private_profile:0123456789abcdef0123456789abcdef';

Future<SyncV2UnlockedProfileKey> _access(
  EncryptionService encryption,
  SecretKey sync,
  String profileId,
  int seed,
) async {
  final raw = SecretKey(List.filled(32, seed));
  final wrap = await encryption.encryptBytes(
    clearBytes: await raw.extractBytes(),
    secretKey: sync,
    additionalData: utf8.encode(
      jsonEncode([
        'himemo-sync-v2-registration',
        1,
        'account',
        'g',
        'normal-sync-wrap',
        profileId,
        'key',
      ]),
    ),
  );
  return SyncV2UnlockedProfileKey.unlockNormal(
    encryption: encryption,
    accountId: 'account',
    generationId: 'g',
    profileId: profileId,
    keyId: 'key',
    syncWrap: wrap,
    syncKey: sync,
  );
}

NoteEntry _note(String id, {String vaultId = 'everyday', String? title}) =>
    NoteEntry(
      id: id,
      vaultId: vaultId,
      title: title ?? 'title $id',
      body: 'body $id',
      createdAt: DateTime.utc(2026, 11, 17),
    );

void main() {
  late SyncV2NoteRepository repository;
  late SyncV2UnlockedProfileKey normal;
  late SyncV2UnlockedProfileKey private;
  late SecretKey sync;
  late bool privateUnlocked;
  late bool registered;

  SyncV2NoteStoreSession? session() => !registered
      ? null
      : SyncV2NoteStoreSession(
          generationId: 'g',
          syncKey: sync,
          normalProfileId: _normalId,
          profiles: {
            _normalId: normal,
            if (privateUnlocked) _privateId: private,
          },
        );

  SyncV2NoteStore newStore() =>
      SyncV2NoteStore(repository: repository, session: session);

  setUp(() async {
    final encryption = EncryptionService();
    sync = SecretKey(List.filled(32, 21));
    normal = await _access(encryption, sync, _normalId, 22);
    private = await _access(encryption, sync, _privateId, 23);
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    addTearDown(inbox.close);
    repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    privateUnlocked = false;
    registered = true;
  });

  test('saved notes survive a new store instance with v1 identities', () async {
    await newStore().saveOne(_note('1001'));
    await newStore().saveOne(_note('1002'));

    final loaded = await newStore().load(fallbackNotes: const []);

    expect(loaded.map((n) => n.id).toSet(), {'1001', '1002'});
    expect(loaded.every((n) => n.vaultId == 'everyday'), isTrue);
  });

  test('edits use the last known head instead of forking', () async {
    final store = newStore();
    await store.saveOne(_note('1', title: 'first'));
    await store.saveOne(_note('1', title: 'second'));

    final reloaded = newStore();
    final loaded = await reloaded.load(fallbackNotes: const []);
    expect(loaded.single.title, 'second');

    await reloaded.saveOne(_note('1', title: 'third'));
    final snapshot = await repository.readNote(
      generationId: 'g',
      profileId: _normalId,
      noteId: 'note_1',
      syncKey: sync,
      profileKey: normal,
    );
    expect(snapshot.hasConflict, isFalse);
    expect(
      (await newStore().load(fallbackNotes: const [])).single.title,
      'third',
    );
  });

  test('deleteById removes the note from later loads', () async {
    final store = newStore();
    await store.saveOne(_note('1'));
    await store.saveOne(_note('2'));
    await store.deleteById('1');

    final loaded = await newStore().load(fallbackNotes: const []);
    expect(loaded.map((n) => n.id), ['2']);
  });

  test(
    'private notes are only readable while the profile is unlocked',
    () async {
      privateUnlocked = true;
      await newStore().saveOne(_note('p1', vaultId: _privateId));

      privateUnlocked = false;
      final locked = newStore();
      expect(await locked.load(fallbackNotes: const []), isEmpty);
      await expectLater(
        locked.saveOne(_note('p2', vaultId: _privateId)),
        throwsA(isA<SyncV2NoteStoreLocked>()),
      );

      privateUnlocked = true;
      final unlocked = await newStore().load(fallbackNotes: const []);
      expect(unlocked.single.id, 'p1');
      expect(unlocked.single.vaultId, _privateId);
    },
  );

  test('full save keeps omitted private notes when asked', () async {
    privateUnlocked = true;
    final store = newStore();
    await store.save([_note('n1'), _note('p1', vaultId: _privateId)]);

    await store.save([_note('n1')], preserveOmittedPrivateNotes: true);
    expect(
      (await newStore().load(fallbackNotes: const [])).map((n) => n.id).toSet(),
      {'n1', 'p1'},
    );

    await store.save([_note('p1', vaultId: _privateId)]);
    expect((await newStore().load(fallbackNotes: const [])).map((n) => n.id), [
      'p1',
    ]);
  });

  test(
    'unregistered workspace returns the fallback and refuses writes',
    () async {
      registered = false;
      final store = newStore();
      final fallback = [_note('f')];
      expect(await store.load(fallbackNotes: fallback), fallback);
      await expectLater(
        store.saveOne(_note('x')),
        throwsA(isA<SyncV2NoteStoreLocked>()),
      );
    },
  );
}
