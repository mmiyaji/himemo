import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_capture_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

void main() {
  test('normal share retry preserves edits and never rereads acknowledged files; failed files roll back', () async {
    final encryption = EncryptionService();
    final sync = SecretKey(List.filled(32, 21));
    final rawNormal = SecretKey(List.filled(32, 22));
    addTearDown(sync.destroy);
    addTearDown(rawNormal.destroy);
    final wrap = await encryption.encryptBytes(
      clearBytes: await rawNormal.extractBytes(),
      secretKey: sync,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          'account',
          'g',
          'normal-sync-wrap',
          'normal_fixture',
          'key',
        ]),
      ),
    );
    final normal = await SyncV2UnlockedProfileKey.unlockNormal(
      encryption: encryption,
      accountId: 'account',
      generationId: 'g',
      profileId: 'normal_fixture',
      keyId: 'key',
      syncWrap: wrap,
      syncKey: sync,
    );
    addTearDown(normal.destroy);
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    addTearDown(inbox.close);
    final repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    final service = SyncV2CaptureService(inbox, repository);
    const privateId = 'private_profile:0123456789abcdef0123456789abcdef';
    final privateWrap = await encryption.encryptBytes(
      clearBytes: await rawNormal.extractBytes(),
      secretKey: sync,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          'account',
          'g',
          'normal-sync-wrap',
          privateId,
          'key',
        ]),
      ),
    );
    final privateAccess = await SyncV2UnlockedProfileKey.unlockNormal(
      encryption: encryption,
      accountId: 'account',
      generationId: 'g',
      profileId: privateId,
      keyId: 'key',
      syncWrap: privateWrap,
      syncKey: sync,
    );
    addTearDown(privateAccess.destroy);
    await expectLater(
      service.capture(
        generationId: 'g',
        syncKey: sync,
        normalAccess: privateAccess,
        rawText: 'Must stay normal',
        requestId: 'private-refused',
        readFiles: () async {
          fail('Private access must fail before file reads');
        },
      ),
      throwsFormatException,
    );
    var reads = 0;
    await service.capture(
      generationId: 'g',
      syncKey: sync,
      normalAccess: normal,
      rawText: 'Share title\nShare body',
      requestId: 'native-share-id',
      readFiles: () async {
        reads++;
        return [
          (label: 'photo', type: 'photo', bytes: Uint8List.fromList([1, 2, 3])),
        ];
      },
    );
    final notes = await repository.readProfile(
      generationId: 'g',
      profileId: normal.profileId,
      syncKey: sync,
      profileKey: normal,
      noteIdPrefix: 'note_capture_',
    );
    final entry = notes.entries.single;
    final body = entry.value.versions.single.body!;
    final note = NoteEntry.fromJson(
      Map<String, dynamic>.from(body['note'] as Map),
    );
    expect(note.title, 'Share title');
    expect(note.body, 'Share body');
    expect(note.vaultId, normal.profileId);
    final ref = SyncV2AttachmentReference.fromJson(
      Map<String, dynamic>.from((body['attachments'] as List).single as Map),
    );
    expect(
      await SyncV2AttachmentService(inbox, repository).read(
        reference: ref,
        generationId: 'g',
        syncKey: sync,
        profileAccess: normal,
      ),
      [1, 2, 3],
    );
    expect(jsonEncode(body), isNot(contains('/native/import/path')));
    await repository.save(
      generationId: 'g',
      profileId: normal.profileId,
      noteId: entry.key,
      changeId: 'edited_capture',
      expectedHeadIds: entry.value.headIds,
      body: {
        ...body,
        'note': note.copyWith(title: 'User edited', body: 'Keep this').toJson(),
      },
      syncKey: sync,
      profileKey: normal,
    );
    await service.capture(
      generationId: 'g',
      syncKey: sync,
      normalAccess: normal,
      rawText: 'Stale native title',
      requestId: 'native-share-id',
      readFiles: () async {
        reads++;
        throw StateError('Native files already removed');
      },
    );
    expect(reads, 1);
    final edited = await repository.readNote(
      generationId: 'g',
      profileId: normal.profileId,
      noteId: entry.key,
      syncKey: sync,
      profileKey: normal,
    );
    expect(
      (edited.versions.single.body!['note'] as Map)['title'],
      'User edited',
    );
    await repository.delete(
      generationId: 'g',
      profileId: normal.profileId,
      noteId: entry.key,
      changeId: 'deleted_capture',
      expectedHeadIds: edited.headIds,
      syncKey: sync,
      profileKey: normal,
    );
    await service.capture(
      generationId: 'g',
      syncKey: sync,
      normalAccess: normal,
      rawText: 'Must not resurrect',
      requestId: 'native-share-id',
      readFiles: () async {
        throw StateError('No files after deletion');
      },
    );
    expect(
      (await repository.readNote(
        generationId: 'g',
        profileId: normal.profileId,
        noteId: entry.key,
        syncKey: sync,
        profileKey: normal,
      )).versions.single.isDeleted,
      isTrue,
    );
    final before = await inbox.readPage(generationId: 'g', limit: 100);
    await expectLater(
      service.capture(
        generationId: 'g',
        syncKey: sync,
        normalAccess: normal,
        rawText: 'Failed capture',
        requestId: 'failed-native-share',
        readFiles: () async => [
          (
            label: 'valid first',
            type: 'file',
            bytes: Uint8List.fromList([4, 5, 6]),
          ),
          (label: 'invalid second', type: 'file', bytes: Uint8List(0)),
        ],
      ),
      throwsFormatException,
    );
    final after = await inbox.readPage(generationId: 'g', limit: 100);
    expect(
      after.map((record) => record.id).toSet(),
      before.map((record) => record.id).toSet(),
    );
    // The failed operation can be retried with the native files still available.
    await service.capture(
      generationId: 'g',
      syncKey: sync,
      normalAccess: normal,
      rawText: 'Successful retry',
      requestId: 'failed-native-share',
      readFiles: () async => [],
    );
    expect(
      (await repository.readProfile(
        generationId: 'g',
        profileId: normal.profileId,
        syncKey: sync,
        profileKey: normal,
        noteIdPrefix: 'note_capture_',
      )).length,
      2,
    );
  });
}
