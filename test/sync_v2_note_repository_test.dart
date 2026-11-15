import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';

final _syncKey = SecretKey(List.filled(32, 17));
final _rawProfileKey = SecretKey(List.filled(32, 29));
late SyncV2UnlockedProfileKey _profileKey;
late SyncV2UnlockedProfileKey _otherProfileKey;
late SyncV2UnlockedProfileKey _otherGenerationKey;

class _Cloud implements SyncV2WriteTransport, SyncV2ReadTransport {
  final records = <SyncV2Publication>[];

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    records.add(publication);
  }

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async {
    final record = records.singleWhere((record) => record.id == recordId);
    return (id: record.id, encryptedHeader: record.encryptedHeader);
  }

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    final start = int.parse(cursor ?? '0');
    final page = records.skip(start).take(limit).toList();
    return SyncV2RemotePage(
      nextCursor: '${start + page.length}',
      hasMore: start + page.length < records.length,
      headers: [
        for (final record in page)
          (id: record.id, encryptedHeader: record.encryptedHeader),
      ],
    );
  }

  @override
  Future<Uint8List> fetchPayload({
    required String generationId,
    required String recordId,
  }) async => Uint8List.fromList(
    records.singleWhere((record) => record.id == recordId).encryptedPayload!,
  );
}

class _Device {
  _Device({File? file}) {
    final encryption = EncryptionService();
    headers = SyncV2HeaderCodec(encryption);
    payloads = SyncV2PayloadCodec(encryption);
    inbox = SyncV2Inbox(
      file == null ? NativeDatabase.memory() : NativeDatabase(file),
      headers,
    );
    notes = SyncV2NoteRepository(inbox, headers, payloads);
  }
  late final SyncV2HeaderCodec headers;
  late final SyncV2PayloadCodec payloads;
  late final SyncV2Inbox inbox;
  late final SyncV2NoteRepository notes;

  Future<SyncV2Change> save(
    String id,
    Set<String> parents, {
    Map<String, Object?>? body,
  }) => notes.save(
    generationId: 'generation',
    profileId: 'profile',
    noteId: 'note',
    changeId: id,
    expectedHeadIds: parents,
    body: body ?? {'text': id},
    syncKey: _syncKey,
    profileKey: _profileKey,
  );

  Future<SyncV2NoteSnapshot> read({SyncV2UnlockedProfileKey? key}) =>
      notes.readNote(
        generationId: 'generation',
        profileId: 'profile',
        noteId: 'note',
        syncKey: _syncKey,
        profileKey: key,
      );

  Future<void> publish(_Cloud cloud) async {
    await SyncV2Publisher(
      cloud,
      inbox,
    ).publishPage(generationId: 'generation', limit: 100);
  }

  Future<void> receive(_Cloud cloud, {bool bodies = true}) async {
    final receiver = SyncV2Receiver(cloud, inbox);
    await receiver.pullPage(
      generationId: 'generation',
      syncKey: _syncKey,
      limit: 100,
    );
    if (bodies) {
      await receiver.pullPendingPayloads(
        generationId: 'generation',
        syncKey: _syncKey,
        limit: 100,
      );
    }
  }
}

void main() {
  setUpAll(() async {
    final keys = SyncV2ProfileKeys(EncryptionService());
    Future<SyncV2UnlockedProfileKey> unlock(
      String generation,
      String profile,
    ) async {
      final record = await keys.wrap(
        generationId: generation,
        profileId: profile,
        keyId: 'key',
        profileKey: _rawProfileKey,
        passphrase: 'fixture profile passphrase',
        adminKey: _syncKey,
      );
      return keys.unlockForAdminSession(
        generationId: generation,
        record: record,
        adminKey: _syncKey,
      );
    }

    _profileKey = await unlock('generation', 'profile');
    _otherProfileKey = await unlock('generation', 'other-profile');
    _otherGenerationKey = await unlock('other-generation', 'profile');
  });
  tearDownAll(() {
    _profileKey.destroy();
    _otherProfileKey.destroy();
    _otherGenerationKey.destroy();
  });
  late _Device a;
  late _Device b;
  late _Cloud cloud;
  setUp(() {
    a = _Device();
    b = _Device();
    cloud = _Cloud();
  });
  tearDown(() async {
    await a.inbox.close();
    await b.inbox.close();
  });

  test(
    'profile binding rejects a wrong identity before new notes are queued',
    () async {
      for (final access in [_otherProfileKey, _otherGenerationKey]) {
        await expectLater(
          a.notes.save(
            generationId: 'generation',
            profileId: 'profile',
            noteId: 'new-note',
            changeId: 'new-change',
            expectedHeadIds: {},
            body: {'text': 'must stay unqueued'},
            syncKey: _syncKey,
            profileKey: access,
          ),
          throwsA(isA<HimemoDecryptionException>()),
        );
      }
      expect(
        await a.inbox.readOutbox(generationId: 'generation', limit: 10),
        isEmpty,
      );
    },
  );

  test(
    'a tombstone cannot be restored using another profile identity',
    () async {
      await a.save('original', {});
      await a.notes.delete(
        generationId: 'generation',
        profileId: 'profile',
        noteId: 'note',
        changeId: 'deleted',
        expectedHeadIds: {'original'},
        syncKey: _syncKey,
        profileKey: _profileKey,
      );
      await expectLater(
        a.notes.save(
          generationId: 'generation',
          profileId: 'profile',
          noteId: 'note',
          changeId: 'wrong-restore',
          expectedHeadIds: {'deleted'},
          body: {'text': 'wrong profile'},
          syncKey: _syncKey,
          profileKey: _otherProfileKey,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
      expect((await a.read()).headIds, {'deleted'});
    },
  );

  test(
    'another profile key cannot overwrite or delete existing heads',
    () async {
      await a.save('original', {});
      final wrongKey = _otherProfileKey;

      await expectLater(
        a.notes.save(
          generationId: 'generation',
          profileId: 'profile',
          noteId: 'note',
          changeId: 'wrong-key-edit',
          expectedHeadIds: {'original'},
          body: {'text': 'must not replace the original'},
          syncKey: _syncKey,
          profileKey: wrongKey,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
      await expectLater(
        a.notes.delete(
          generationId: 'generation',
          profileId: 'profile',
          noteId: 'note',
          changeId: 'wrong-key-delete',
          expectedHeadIds: {'original'},
          syncKey: _syncKey,
          profileKey: wrongKey,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
      expect((await a.read(key: _profileKey)).headIds, {'original'});
      expect(
        (await a.inbox.readOutbox(
          generationId: 'generation',
          limit: 10,
        )).map((entry) => entry.id),
        ['original'],
      );
    },
  );

  test(
    'published edits arrive locked and unlock only with the profile key',
    () async {
      await a.save('first', {}, body: {'text': 'private body'});
      await a.publish(cloud);
      await b.receive(cloud);
      final locked = await b.read();
      expect(locked.headIds, {'first'});
      expect(locked.versions.single.payloadAvailable, isTrue);
      expect(locked.versions.single.body, isNull);
      expect(locked.canCompareVersions, isFalse);
      expect((await b.read(key: _profileKey)).versions.single.body, {
        'text': 'private body',
      });
      expect((await b.read(key: _profileKey)).canCompareVersions, isTrue);
      await expectLater(
        b.read(key: _otherProfileKey),
        throwsA(isA<HimemoDecryptionException>()),
      );
      expect((await b.read()).versions.single.body, isNull);
    },
  );

  test(
    'concurrent descendants survive and resolution acknowledges every head',
    () async {
      await a.save('parent', {});
      await a.publish(cloud);
      await b.receive(cloud);
      await a.save('left', {'parent'});
      await b.save('right', {'parent'});
      await a.publish(cloud);
      await b.publish(cloud);
      await a.receive(cloud);
      await b.receive(cloud);
      expect((await a.read()).headIds, {'left', 'right'});
      expect((await b.read()).hasConflict, isTrue);
      await expectLater(
        a.save('stale', {'left'}),
        throwsA(isA<SyncV2StaleNote>()),
      );
      await a.save('resolved', {'left', 'right'}, body: {'text': 'merged'});
      await a.publish(cloud);
      await b.receive(cloud);
      final result = await b.read(key: _profileKey);
      expect(result.headIds, {'resolved'});
      expect(result.versions.single.change.parentIds, {'left', 'right'});
      expect(result.versions.single.body, {'text': 'merged'});
    },
  );

  test('a concurrent deletion and edit both remain visible', () async {
    await a.save('parent', {});
    await a.publish(cloud);
    await b.receive(cloud);
    await a.notes.delete(
      generationId: 'generation',
      profileId: 'profile',
      noteId: 'note',
      changeId: 'deleted',
      expectedHeadIds: {'parent'},
      syncKey: _syncKey,
      profileKey: _profileKey,
    );
    await b.save('edited', {'parent'});
    await a.publish(cloud);
    await b.publish(cloud);
    await a.receive(cloud);
    final snapshot = await a.read(key: _profileKey);
    expect(snapshot.headIds, {'deleted', 'edited'});
    expect(
      snapshot.versions.where((version) => version.isDeleted).single.body,
      isNull,
    );
    expect(
      snapshot.versions.where((version) => !version.isDeleted).single.body,
      {'text': 'edited'},
    );
  });

  test('missing payload prevents consuming a head', () async {
    await a.save('first', {});
    await a.publish(cloud);
    await b.receive(cloud, bodies: false);
    expect((await b.read()).versions.single.payloadAvailable, isFalse);
    await expectLater(
      b.save('next', {'first'}),
      throwsA(isA<SyncV2StaleNote>()),
    );
    expect(
      await b.inbox.readOutbox(generationId: 'generation', limit: 100),
      isEmpty,
    );
    await b.receive(cloud);
    await b.save('next', {'first'});
  });

  test('missing parent keeps a change pending and prevents writes', () async {
    final prepared = await a.payloads.seal(
      generationId: 'generation',
      changeId: 'orphan',
      profileId: 'profile',
      noteId: 'note',
      parentIds: {'absent'},
      body: {'text': 'pending'},
      profileKey: _profileKey.key,
    );
    await a.inbox.queuePublication(
      generationId: 'generation',
      change: prepared.change,
      encryptedPayload: prepared.encryptedPayload,
      syncKey: _syncKey,
    );
    await a.publish(cloud);
    await b.receive(cloud);
    expect((await b.read()).pendingIds, {'orphan'});
    await expectLater(b.save('next', {}), throwsA(isA<SyncV2StaleNote>()));
    expect(
      await b.inbox.readOutbox(generationId: 'generation', limit: 100),
      isEmpty,
    );
  });

  test(
    'semantic retry preserves ciphertext and rejects changed body',
    () async {
      await a.save(
        'first',
        {},
        body: {
          'nested': {'a': 1, 'b': 2},
          'list': [1, 2],
        },
      );
      final original = (await a.inbox.readOutbox(
        generationId: 'generation',
        limit: 100,
      )).single;
      await a.save(
        'first',
        {},
        body: {
          'list': [1, 2],
          'nested': {'b': 2, 'a': 1},
        },
      );
      final retry = (await a.inbox.readOutbox(
        generationId: 'generation',
        limit: 100,
      )).single;
      expect(retry.encryptedHeader, original.encryptedHeader);
      expect(retry.encryptedPayload, original.encryptedPayload);
      await expectLater(
        a.save('first', {}, body: {'text': 'different'}),
        throwsFormatException,
      );
      expect((await a.read()).headIds, {'first'});
      await a.publish(cloud);
      await a.save(
        'first',
        {},
        body: {
          'nested': {'a': 1, 'b': 2},
          'list': [1, 2],
        },
      );
      expect(
        await a.inbox.readOutbox(generationId: 'generation', limit: 100),
        isEmpty,
      );
    },
  );

  test('outbox insert failure rolls back the note and permits retry', () async {
    await a.inbox.readPage(generationId: 'generation', limit: 1);
    await a.inbox.customStatement(
      "CREATE TRIGGER fail_outbox BEFORE INSERT ON sync_v2_outbox BEGIN SELECT RAISE(ABORT, 'injected failure'); END",
    );
    await expectLater(a.save('first', {}), throwsA(anything));
    expect((await a.read()).headIds, isEmpty);
    expect(
      await a.inbox.readOutbox(generationId: 'generation', limit: 100),
      isEmpty,
    );
    await a.inbox.customStatement('DROP TRIGGER fail_outbox');
    await a.save('first', {});
    expect((await a.read()).headIds, {'first'});
  });

  test(
    'reopening retains ciphertext and unpublished edits without plaintext',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'himemo-note-v2-',
      );
      final file = File('${directory.path}/inbox.sqlite');
      var device = _Device(file: file);
      var closed = false;
      const plaintext = 'sample-secret-body-should-never-appear-on-disk';
      try {
        await device.save('durable', {}, body: {'text': plaintext});
        final original = (await device.inbox.readOutbox(
          generationId: 'generation',
          limit: 100,
        )).single;
        await device.inbox.close();
        closed = true;
        expect(
          latin1.decode(await file.readAsBytes()),
          isNot(contains(plaintext)),
        );
        device = _Device(file: file);
        closed = false;
        expect((await device.read(key: _profileKey)).versions.single.body, {
          'text': plaintext,
        });
        final reopened = (await device.inbox.readOutbox(
          generationId: 'generation',
          limit: 100,
        )).single;
        expect(reopened.encryptedHeader, original.encryptedHeader);
        expect(reopened.encryptedPayload, original.encryptedPayload);
        await device.publish(cloud);
        await b.receive(cloud);
        expect((await b.read(key: _profileKey)).versions.single.body, {
          'text': plaintext,
        });
      } finally {
        if (!closed) await device.inbox.close();
        await directory.delete(recursive: true);
      }
    },
  );
  test(
    'concurrent local saves compare and swap the complete head set',
    () async {
      await a.save('parent', {});
      final outcomes = await Future.wait([
        for (final id in ['left', 'right'])
          a
              .save(id, {'parent'})
              .then<Object>(
                (change) => change,
                onError: (Object error) => error,
              ),
      ]);
      expect(outcomes.whereType<SyncV2Change>(), hasLength(1));
      expect(outcomes.whereType<SyncV2StaleNote>(), hasLength(1));
      final winner = outcomes.whereType<SyncV2Change>().single.id;
      expect((await a.read()).headIds, {winner});
      expect(
        (await a.inbox.readOutbox(
          generationId: 'generation',
          limit: 100,
        )).map((record) => record.id),
        ['parent', winner],
      );
    },
  );

  test(
    'an unrelated cyclic note does not prevent reading or saving this note',
    () async {
      for (final entry in [('cycle-a', 'cycle-b'), ('cycle-b', 'cycle-a')]) {
        await a.inbox.queuePublication(
          generationId: 'generation',
          change: SyncV2Change(
            id: entry.$1,
            profileId: 'profile',
            noteId: 'other',
            operation: SyncV2Operation.delete,
            parentIds: {entry.$2},
          ),
          encryptedPayload: null,
          syncKey: _syncKey,
        );
      }
      expect((await a.read()).headIds, isEmpty);
      await a.save('valid', {});
      expect((await a.read(key: _profileKey)).versions.single.body, {
        'text': 'valid',
      });
    },
  );

  test('a known parent belonging to another note is rejected', () async {
    for (final change in [
      SyncV2Change(
        id: 'foreign',
        profileId: 'profile',
        noteId: 'other',
        operation: SyncV2Operation.delete,
        parentIds: {},
      ),
      SyncV2Change(
        id: 'invalid',
        profileId: 'profile',
        noteId: 'note',
        operation: SyncV2Operation.delete,
        parentIds: {'foreign'},
      ),
    ]) {
      await a.inbox.queuePublication(
        generationId: 'generation',
        change: change,
        encryptedPayload: null,
        syncKey: _syncKey,
      );
    }
    await expectLater(a.read(), throwsFormatException);
    await expectLater(a.save('next', {}), throwsFormatException);
    expect(
      (await a.inbox.readOutbox(
        generationId: 'generation',
        limit: 100,
      )).map((record) => record.id),
      ['foreign', 'invalid'],
    );
  });
}
