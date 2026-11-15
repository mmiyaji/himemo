import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_archive_service.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

class _CountingHeaders extends SyncV2HeaderCodec {
  _CountingHeaders(super.encryption);
  int opens = 0;
  @override
  Future<SyncV2Change> open(
    String encryptedHeader, {
    required String generationId,
    required String recordId,
    required SecretKey syncKey,
  }) {
    opens++;
    return super.open(
      encryptedHeader,
      generationId: generationId,
      recordId: recordId,
      syncKey: syncKey,
    );
  }
}

void main() {
  final syncKey = SecretKey(List.filled(32, 17));
  late SyncV2UnlockedProfileKey access;
  setUpAll(() async {
    final keys = SyncV2ProfileKeys(EncryptionService());
    final record = await keys.wrap(
      generationId: 'g',
      profileId: 'normal_0123456789abcdef',
      keyId: 'k',
      profileKey: SecretKey(List.filled(32, 29)),
      passphrase: 'test password',
      adminKey: syncKey,
    );
    access = await keys.unlockForAdminSession(
      generationId: 'g',
      record: record,
      adminKey: syncKey,
    );
  });
  ({SyncV2Inbox inbox, SyncV2NoteRepository repo, _CountingHeaders headers})
  device() {
    final encryption = EncryptionService();
    final headers = _CountingHeaders(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    return (
      inbox: inbox,
      headers: headers,
      repo: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
    );
  }

  test(
    'multi-chunk writes and reads decrypt history once per operation',
    () async {
      final d = device();
      addTearDown(d.inbox.close);
      final service = SyncV2AttachmentService(d.inbox, d.repo);
      await service.store(
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
        bytes: Uint8List.fromList([1]),
        label: 'seed',
        type: 'file',
        stableId: 'seed',
      );
      d.headers.opens = 0;
      final bytes = Uint8List(2 * SyncV2AttachmentService.chunkBytes + 1);
      final ref = await service.store(
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
        bytes: bytes,
        label: 'three chunks',
        type: 'file',
        stableId: 'batch',
      );
      expect(ref.chunks.length, 3);
      expect(
        d.headers.opens,
        1,
        reason: 'One scan of the existing seed header',
      );
      d.headers.opens = 0;
      expect(
        await service.read(
          reference: ref,
          generationId: 'g',
          syncKey: syncKey,
          profileAccess: access,
        ),
        bytes,
      );
      expect(d.headers.opens, 4, reason: 'Each of four headers is opened once');
    },
  );

  test('private-only ZIP permits an unused normal destination and requires private mapping', () async {
    final d = device();
    addTearDown(d.inbox.close);
    final service = SyncV2ArchiveService(d.inbox, d.repo);
    final keys = SyncV2ProfileKeys(EncryptionService());
    final wrapped = await keys.wrap(
      generationId: 'g',
      profileId: 'private_profile:destination',
      keyId: 'private-key',
      profileKey: SecretKey(List.filled(32, 37)),
      passphrase: 'private password',
      adminKey: syncKey,
    );
    final privateAccess = await keys.unlockForAdminSession(
      generationId: 'g',
      record: wrapped,
      adminKey: syncKey,
    );
    addTearDown(privateAccess.destroy);
    final note = NoteEntry(
      id: 'legacy-private',
      vaultId: 'private',
      title: 'private import',
      body: '',
      createdAt: DateTime.utc(2020),
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': 'org.ruhenheim.himemo.notes.zip',
            'version': 1,
            'noteCount': 1,
            'attachmentCount': 0,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'notes.json',
          jsonEncode({
            'notes': [note.toJson()],
          }),
        ),
      );
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    await expectLater(
      service.importArchive(
        bytes: bytes,
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access},
      ),
      throwsStateError,
    );
    expect(await d.inbox.readOutbox(generationId: 'g', limit: 100), isEmpty);
    expect(
      await service.importArchive(
        bytes: bytes,
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access, 'private': privateAccess},
      ),
      1,
    );
    final exported = await service.exportArchive(
      generationId: 'g',
      syncKey: syncKey,
      profiles: [privateAccess],
    );
    expect((await service.inspect(exported)).noteCountsByProfile, {
      'private_profile:destination': 1,
    });
  });

  test('chunks survive reversed interrupted delivery and reject corrupt references', () async {
    final a = device(), b = device();
    addTearDown(a.inbox.close);
    addTearDown(b.inbox.close);
    final service = SyncV2AttachmentService(a.inbox, a.repo);
    final target = SyncV2AttachmentService(b.inbox, b.repo);
    final bytes = Uint8List.fromList(
      List.generate(1024 * 1024 + 3, (i) => i % 251),
    );
    final ref = await service.store(
      generationId: 'g',
      syncKey: syncKey,
      profileAccess: access,
      bytes: bytes,
      label: 'photo',
      type: 'photo',
      stableId: 'stable',
    );
    await service.store(
      generationId: 'g',
      syncKey: syncKey,
      profileAccess: access,
      bytes: bytes,
      label: 'photo',
      type: 'photo',
      stableId: 'stable',
    );
    final queued = await a.inbox.readOutbox(generationId: 'g', limit: 100);
    expect(queued.length, 2);
    await b.inbox.stagePage(
      generationId: 'g',
      expectedCursor: null,
      nextCursor: '1',
      records: [
        for (final p in queued.reversed)
          (id: p.id, encryptedHeader: p.encryptedHeader),
      ],
      syncKey: syncKey,
    );
    await b.inbox.storePayload(
      generationId: 'g',
      recordId: queued.last.id,
      encryptedPayload: queued.last.encryptedPayload!,
      syncKey: syncKey,
    );
    await expectLater(
      target.read(
        reference: ref,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      throwsFormatException,
    );
    await b.inbox.storePayload(
      generationId: 'g',
      recordId: queued.first.id,
      encryptedPayload: queued.first.encryptedPayload!,
      syncKey: syncKey,
    );
    expect(
      await target.read(
        reference: ref,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      bytes,
    );
    final corrupt = SyncV2AttachmentReference.fromJson({
      ...ref.toJson(),
      'sha256': '0' * 64,
    });
    await expectLater(
      target.read(
        reference: corrupt,
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
      ),
      throwsFormatException,
    );
  });
  test(
    'ZIP imports atomically, retries, remaps block photos and exports',
    () async {
      final d = device();
      addTearDown(d.inbox.close);
      final service = SyncV2ArchiveService(d.inbox, d.repo);
      final photo = NoteAttachment(
        type: AttachmentType.photo,
        label: 'picture',
        filePath: 'attachments/photo',
      );
      final note = NoteEntry(
        id: 'old',
        vaultId: 'everyday',
        title: 'hello',
        body: '',
        createdAt: DateTime.utc(2020),
        attachments: [photo],
        blocks: [NoteBlock(type: NoteBlockType.photo, attachment: photo)],
      );
      final zip = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'org.ruhenheim.himemo.notes.zip',
              'version': 1,
              'noteCount': 1,
              'attachmentCount': 1,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'notes.json',
            jsonEncode({
              'notes': [note.toJson()],
            }),
          ),
        )
        ..addFile(ArchiveFile.bytes('attachments/photo', [1, 2, 3]));
      final bytes = Uint8List.fromList(ZipEncoder().encode(zip));
      expect((await service.inspect(bytes)).noteCountsByProfile, {
        'everyday': 1,
      });
      // The second reference fails after the first chunk was queued. The outer
      // import transaction must roll back the already encrypted first chunk.
      final invalid = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'org.ruhenheim.himemo.notes.zip',
              'version': 1,
              'noteCount': 1,
              'attachmentCount': 2,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'notes.json',
            jsonEncode({
              'notes': [
                note
                    .copyWith(
                      attachments: [
                        photo,
                        photo.copyWith(
                          label: 'x' * 5000,
                          filePath: 'attachments/second',
                        ),
                      ],
                    )
                    .toJson(),
              ],
            }),
          ),
        )
        ..addFile(ArchiveFile.bytes('attachments/photo', [1, 2, 3]))
        ..addFile(ArchiveFile.bytes('attachments/second', [4, 5, 6]));
      await expectLater(
        service.importArchive(
          bytes: Uint8List.fromList(ZipEncoder().encode(invalid)),
          generationId: 'g',
          syncKey: syncKey,
          destinations: {'everyday': access},
        ),
        throwsFormatException,
      );
      expect(await d.inbox.readOutbox(generationId: 'g', limit: 100), isEmpty);
      await expectLater(
        service.importArchive(
          bytes: bytes,
          generationId: 'g',
          syncKey: syncKey,
          destinations: {},
        ),
        throwsStateError,
      );
      expect(await d.inbox.readOutbox(generationId: 'g', limit: 100), isEmpty);
      for (var i = 0; i < 2; i++) {
        expect(
          await service.importArchive(
            bytes: bytes,
            generationId: 'g',
            syncKey: syncKey,
            destinations: {'everyday': access},
          ),
          1,
        );
      }
      expect(
        (await d.inbox.readOutbox(generationId: 'g', limit: 100)).length,
        2,
      );
      final snapshots = await d.repo.readProfile(
        generationId: 'g',
        profileId: 'normal_0123456789abcdef',
        syncKey: syncKey,
        profileKey: access,
        noteIdPrefix: 'note_',
      );
      final body = snapshots.values.single.versions.single.body!;
      final mapped = NoteEntry.fromJson(
        Map<String, dynamic>.from(body['note'] as Map),
      );
      expect(mapped.attachments.single.filePath, startsWith('v2attachment:'));
      expect(
        mapped.blocks.single.attachment!.filePath,
        mapped.attachments.single.filePath,
      );
      final exported = await service.exportArchive(
        generationId: 'g',
        syncKey: syncKey,
        profiles: [access],
      );
      expect((await service.inspect(exported)).noteCountsByProfile, {
        'everyday': 1,
      });
    },
  );

  test(
    'admin ZIP overwrite restores edits and is a no-op when repeated',
    () async {
      final d = device();
      addTearDown(d.inbox.close);
      final service = SyncV2ArchiveService(d.inbox, d.repo);
      final note = NoteEntry(
        id: 'same-source-id',
        vaultId: 'everyday',
        title: 'archive title',
        body: 'archive body',
        createdAt: DateTime.utc(2020),
      );
      final archive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'org.ruhenheim.himemo.notes.zip',
              'version': 1,
              'noteCount': 1,
              'attachmentCount': 0,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'notes.json',
            jsonEncode({
              'notes': [note.toJson()],
            }),
          ),
        );
      final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
      await service.importArchive(
        bytes: bytes,
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access},
      );
      final legacySnapshot = await d.repo.readProfile(
        generationId: 'g',
        profileId: access.profileId,
        syncKey: syncKey,
        profileKey: access,
      );
      final legacyNoteId = legacySnapshot.keys.single;
      Future<Map<String, SyncV2NoteSnapshot>> importAndRead() async {
        await service.importArchive(
          bytes: bytes,
          generationId: 'g',
          syncKey: syncKey,
          destinations: {'everyday': access},
          overwriteExisting: true,
        );
        return d.repo.readProfile(
          generationId: 'g',
          profileId: access.profileId,
          syncKey: syncKey,
          profileKey: access,
        );
      }

      var snapshots = await importAndRead();
      expect(snapshots, hasLength(1));
      final noteId = snapshots.keys.single;
      expect(noteId, legacyNoteId, reason: 'prior manual import ID is reused');
      var snapshot = snapshots[noteId]!;
      await d.repo.save(
        generationId: 'g',
        profileId: access.profileId,
        noteId: noteId,
        changeId: 'local-edit',
        expectedHeadIds: snapshot.headIds,
        body: {
          'type': 'note',
          'note': note.copyWith(title: 'local edit').toJson(),
          'attachments': [],
          'legacyImport': {'profileId': 'everyday', 'noteId': note.id},
        },
        syncKey: syncKey,
        profileKey: access,
      );
      snapshots = await importAndRead();
      snapshot = snapshots[noteId]!;
      expect(
        snapshot.versions.single.body!['note'],
        note.copyWith(id: noteId, vaultId: access.profileId).toJson(),
      );
      final queuedCount = (await d.inbox.readOutbox(
        generationId: 'g',
        limit: 100,
      )).length;
      await importAndRead();
      expect(
        (await d.inbox.readOutbox(generationId: 'g', limit: 100)),
        hasLength(queuedCount),
      );
      final changedArchive = Archive()
        ..addFile(
          ArchiveFile.string(
            'manifest.json',
            jsonEncode({
              'format': 'org.ruhenheim.himemo.notes.zip',
              'version': 1,
              'noteCount': 1,
              'attachmentCount': 0,
            }),
          ),
        )
        ..addFile(
          ArchiveFile.string(
            'notes.json',
            jsonEncode({
              'notes': [note.copyWith(title: 'changed ZIP').toJson()],
            }),
          ),
        );
      await service.importArchive(
        bytes: Uint8List.fromList(ZipEncoder().encode(changedArchive)),
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access},
        overwriteExisting: true,
      );
      final changed = await d.repo.readProfile(
        generationId: 'g',
        profileId: access.profileId,
        syncKey: syncKey,
        profileKey: access,
      );
      expect(changed, hasLength(1));
      expect(
        NoteEntry.fromJson(
          Map<String, dynamic>.from(
            changed[noteId]!.versions.single.body!['note'] as Map,
          ),
        ).title,
        'changed ZIP',
      );
    },
  );

  test(
    'admin archive source IDs cannot overwrite profile or attachment entities',
    () async {
      final d = device();
      addTearDown(d.inbox.close);
      final service = SyncV2ArchiveService(d.inbox, d.repo);
      final attachment = await service.attachments.store(
        generationId: 'g',
        syncKey: syncKey,
        profileAccess: access,
        bytes: Uint8List.fromList([1, 2]),
        label: 'existing',
        type: 'file',
      );
      await d.repo.save(
        generationId: 'g',
        profileId: access.profileId,
        noteId: 'profile_reserved',
        changeId: 'profile-head',
        expectedHeadIds: {},
        body: {'type': 'profile-key', 'sentinel': true},
        syncKey: syncKey,
        profileKey: access,
      );
      final notes = [
        for (final id in [attachment.chunks.single, 'profile_reserved'])
          NoteEntry(
            id: id,
            vaultId: 'everyday',
            title: 'restored note',
            body: 'ZIP content',
            createdAt: DateTime.utc(2020),
          ),
      ];
      final bytes = Uint8List.fromList(
        ZipEncoder().encode(
          Archive()
            ..addFile(
              ArchiveFile.string(
                'manifest.json',
                jsonEncode({
                  'format': 'org.ruhenheim.himemo.notes.zip',
                  'version': 1,
                  'noteCount': 2,
                  'attachmentCount': 0,
                }),
              ),
            )
            ..addFile(
              ArchiveFile.string(
                'notes.json',
                jsonEncode({'notes': notes.map((n) => n.toJson()).toList()}),
              ),
            ),
        ),
      );
      await service.importArchive(
        bytes: bytes,
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access},
        overwriteExisting: true,
      );
      expect(
        await service.attachments.read(
          reference: attachment,
          generationId: 'g',
          syncKey: syncKey,
          profileAccess: access,
        ),
        [1, 2],
      );
      final profile = await d.repo.readNote(
        generationId: 'g',
        profileId: access.profileId,
        noteId: 'profile_reserved',
        syncKey: syncKey,
        profileKey: access,
      );
      expect(profile.versions.single.body, {
        'type': 'profile-key',
        'sentinel': true,
      });
      final restored = await d.repo.readProfile(
        generationId: 'g',
        profileId: access.profileId,
        syncKey: syncKey,
        profileKey: access,
        noteIdPrefix: 'note_',
      );
      expect(restored, hasLength(2));
    },
  );

  test('admin imports namespace change records by writer', () async {
    final first = device(), second = device(), synced = device();
    addTearDown(first.inbox.close);
    addTearDown(second.inbox.close);
    addTearDown(synced.inbox.close);
    final note = NoteEntry(
      id: 'shared-source-id',
      vaultId: 'everyday',
      title: 'shared',
      body: '',
      createdAt: DateTime.utc(2020),
      attachments: [
        NoteAttachment(
          type: AttachmentType.file,
          label: 'shared-file',
          filePath: 'attachments/shared-file',
        ),
      ],
    );
    final archive = Archive()
      ..addFile(
        ArchiveFile.string(
          'manifest.json',
          jsonEncode({
            'format': 'org.ruhenheim.himemo.notes.zip',
            'version': 1,
            'noteCount': 1,
            'attachmentCount': 1,
          }),
        ),
      )
      ..addFile(
        ArchiveFile.string(
          'notes.json',
          jsonEncode({
            'notes': [note.toJson()],
          }),
        ),
      )
      ..addFile(ArchiveFile.bytes('attachments/shared-file', [2, 3, 5, 7]));
    final bytes = Uint8List.fromList(ZipEncoder().encode(archive));
    for (final entry in [(first, 'device-a'), (second, 'device-b')]) {
      await SyncV2ArchiveService(entry.$1.inbox, entry.$1.repo).importArchive(
        bytes: bytes,
        generationId: 'g',
        syncKey: syncKey,
        destinations: {'everyday': access},
        overwriteExisting: true,
        writerId: entry.$2,
      );
    }
    final firstOutbox = await first.inbox.readOutbox(
      generationId: 'g',
      limit: 100,
    );
    final secondOutbox = await second.inbox.readOutbox(
      generationId: 'g',
      limit: 100,
    );
    expect(firstOutbox, hasLength(2));
    expect(secondOutbox, hasLength(2));
    expect(
      firstOutbox
          .map((record) => record.id)
          .toSet()
          .intersection(secondOutbox.map((record) => record.id).toSet()),
      isEmpty,
    );
    await synced.inbox.stagePage(
      generationId: 'g',
      expectedCursor: null,
      nextCursor: 'page-1',
      records: [
        for (final record in firstOutbox)
          (id: record.id, encryptedHeader: record.encryptedHeader),
      ],
      syncKey: syncKey,
    );
    for (final record in firstOutbox) {
      if (record.encryptedPayload != null) {
        await synced.inbox.storePayload(
          generationId: 'g',
          recordId: record.id,
          encryptedPayload: record.encryptedPayload!,
          syncKey: syncKey,
        );
      }
    }
    await SyncV2ArchiveService(synced.inbox, synced.repo).importArchive(
      bytes: bytes,
      generationId: 'g',
      syncKey: syncKey,
      destinations: {'everyday': access},
      overwriteExisting: true,
      writerId: 'device-c',
    );
    expect(
      await synced.inbox.readOutbox(generationId: 'g', limit: 100),
      isEmpty,
      reason: 'healthy synced attachment references are reused for a no-op',
    );
    final firstNotes = await first.repo.readProfile(
      generationId: 'g',
      profileId: access.profileId,
      syncKey: syncKey,
      profileKey: access,
      noteIdPrefix: 'note_',
    );
    final secondNotes = await second.repo.readProfile(
      generationId: 'g',
      profileId: access.profileId,
      syncKey: syncKey,
      profileKey: access,
      noteIdPrefix: 'note_',
    );
    expect(firstNotes.keys, secondNotes.keys);
  });
}
