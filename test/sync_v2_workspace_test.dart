import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';

class _Cloud
    implements
        SyncV2GenerationRegistrationTransport,
        SyncV2WriteTransport,
        SyncV2ReadTransport {
  String? proof;
  String account = 'account';
  bool offline = false;
  int registryWrites = 0;
  final records = <SyncV2Publication>[];
  @override
  Future<String> readCurrentAccountId() async {
    if (offline) throw StateError('offline');
    return account;
  }

  @override
  Future<String?> readRegistration() async {
    if (offline) throw StateError('offline');
    return proof;
  }

  @override
  Future<void> prepareGeneration(String generationId) async {
    registryWrites++;
  }

  @override
  Future<void> publishRegistration(String encryptedProof) async {
    registryWrites++;
    if (proof != null && proof != encryptedProof) throw StateError('collision');
    proof = encryptedProof;
  }

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    if (offline) throw StateError('offline');
    if (records.any((r) => r.id == publication.id)) return;
    records.add(publication);
  }

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async {
    final record = records.singleWhere((r) => r.id == recordId);
    return (id: record.id, encryptedHeader: record.encryptedHeader);
  }

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    if (offline) throw StateError('offline');
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
    records.singleWhere((r) => r.id == recordId).encryptedPayload!,
  );
}

class _Store extends SecureKeyValueStore {
  final backing = MemorySecureKeyValueStore();
  Completer<void>? unlockEntered, unlockRelease;
  Completer<void>? restoreEntered, restoreRelease;
  @override
  Future<String?> read(String key) async {
    if (key == 'security.icloud_sync_v2.verified_proof.v1' &&
        restoreRelease != null) {
      restoreEntered!.complete();
      await restoreRelease!.future;
      restoreRelease = null;
    }
    if (key.startsWith('sync.v2.profiles.') &&
        key.endsWith('.attempts') &&
        unlockRelease != null) {
      unlockEntered!.complete();
      await unlockRelease!.future;
      unlockRelease = null;
    }
    return backing.read(key);
  }

  @override
  Future<void> write(String key, String value) => backing.write(key, value);
  @override
  Future<void> delete(String key) => backing.delete(key);
}

class _Device {
  _Device(this.cloud, {_Store? sharedStore}) : store = sharedStore ?? _Store() {
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    enrollment = SyncV2EnrollmentStore(store);
    workspace = SyncV2WorkspaceController(
      inbox: inbox,
      repository: repository,
      store: store,
      enrollments: enrollment,
      registrationTransport: cloud,
      registrationFactory: (_) =>
          SyncV2GenerationRegistration(cloud, enrollment),
      syncOperation: sync,
      activate: () async {
        activations++;
      },
      deactivate: () async {
        deactivations++;
      },
      supported: true,
      automaticSync: false,
    );
  }
  final _Cloud cloud;
  final _Store store;
  late final SyncV2Inbox inbox;
  late final SyncV2EnrollmentStore enrollment;
  late final SyncV2WorkspaceController workspace;
  int activations = 0, deactivations = 0;
  Completer<void>? syncEntered, syncRelease;
  Future<SyncV2ICloudProgress> sync() async {
    if (syncRelease != null) {
      syncEntered!.complete();
      await syncRelease!.future;
      syncRelease = null;
    }
    final local = (await enrollment.readForAccount('account'))!;
    try {
      final published = await SyncV2Publisher(cloud, inbox).publishPage(
        generationId: local.generationId,
        limit: 50,
        stopOnQuarantine: true,
      );
      final receiver = SyncV2Receiver(cloud, inbox);
      final page = await receiver.pullPage(
        generationId: local.generationId,
        syncKey: local.syncKey,
        limit: 50,
      );
      final downloaded = await receiver.pullPendingPayloads(
        generationId: local.generationId,
        syncKey: local.syncKey,
        limit: 50,
      );
      return (
        headersStaged: page.staged,
        hasMoreHeaders: page.hasMore,
        publishedChanges: published,
        downloadedPayloads: downloaded,
        errors: <String>[],
      );
    } finally {
      local.syncKey.destroy();
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('resume completes an existing registration interrupted during initial restore', () async {
    final cloud = _Cloud();
    final original = _Device(cloud);
    addTearDown(original.workspace.dispose);
    await original.workspace.initialize();
    await original.workspace.prepareNew('administrator password');
    await original.workspace.confirmSetup();
    final reopened = _Device(cloud, sharedStore: original.store);
    addTearDown(reopened.workspace.dispose);
    reopened.store.restoreEntered = Completer<void>();
    reopened.store.restoreRelease = Completer<void>();
    final initial = expectLater(
      reopened.workspace.initialize(),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await reopened.store.restoreEntered!.future;
    reopened.workspace.background();
    reopened.store.restoreRelease!.complete();
    await initial;
    expect(reopened.workspace.registered, isFalse);
    expect(reopened.workspace.notes, isEmpty);
    expect(reopened.activations, 0);
    await reopened.workspace.resume();
    expect(reopened.workspace.registered, isTrue);
    expect(reopened.workspace.profiles.length, 1);
    expect(reopened.activations, 1);
    await expectLater(
      reopened.workspace.prepareNew('another admin password'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
  });
  test('setup keeps the same codes across background and rejects switched accounts', () async {
    final cloud = _Cloud();
    final device = _Device(cloud);
    addTearDown(device.workspace.dispose);
    await device.workspace.initialize();
    final codes = await device.workspace.prepareNew('administrator password');
    expect(cloud.registryWrites, 0);
    device.workspace.background();
    await device.workspace.resume();
    final continued = await device.workspace.prepareNew(
      'administrator password',
    );
    expect(continued, codes);
    expect(cloud.registryWrites, 0);
    await device.workspace.confirmSetup();
    await device.workspace.createProfile('Private', 'private password');
    final generation = device.workspace.generationId;
    expect(device.workspace.profiles.length, 2);
    cloud.account = 'different-account';
    await expectLater(
      device.workspace.recover(codes.syncCode),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(device.workspace.accountId, 'account');
    expect(device.workspace.generationId, generation);
    expect(device.workspace.profiles.length, 1);
    expect(device.workspace.adminUnlocked, isFalse);
    expect(device.workspace.notes, isEmpty);
  });
  test('editing imported rich blocks exports updated text without removed attachment references', () async {
    final cloud = _Cloud();
    final a = _Device(cloud), b = _Device(cloud);
    addTearDown(a.workspace.dispose);
    addTearDown(b.workspace.dispose);
    await a.workspace.initialize();
    await b.workspace.initialize();
    final codes = await a.workspace.prepareNew('administrator password');
    await a.workspace.confirmSetup();
    const photo = NoteAttachment(
      type: AttachmentType.photo,
      label: 'old photo',
      filePath: 'attachments/photo',
    );
    final rich = NoteEntry(
      id: 'legacy-rich',
      vaultId: 'everyday',
      title: 'Rich note',
      body: 'Old paragraph',
      createdAt: DateTime.utc(2020),
      attachments: [photo],
      blocks: [
        const NoteBlock(type: NoteBlockType.paragraph, text: 'Old paragraph'),
        const NoteBlock(type: NoteBlockType.photo, attachment: photo),
      ],
    );
    final input = Archive()
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
            'notes': [rich.toJson()],
          }),
        ),
      )
      ..addFile(ArchiveFile.bytes('attachments/photo', [1, 2, 3]));
    await a.workspace.importArchive(
      bytes: Uint8List.fromList(ZipEncoder().encode(input)),
      destinations: {},
      acceptUnlinkedAttachments: false,
    );
    final imported = a.workspace.notes.single;
    expect(imported.note.blocks.map((block) => block.type), [
      NoteBlockType.paragraph,
      NoteBlockType.photo,
    ]);
    expect(imported.attachments, hasLength(1));
    await a.workspace.saveNote(
      original: imported,
      title: 'Edited rich note',
      body: 'Updated paragraph',
      removedAttachmentIds: [imported.attachments.single.id],
    );
    final updated = a.workspace.notes.single;
    expect(updated.note.body, 'Updated paragraph');
    expect(updated.note.blocks.map((block) => block.text), [
      'Updated paragraph',
    ]);
    expect(
      updated.note.blocks.any((block) => block.attachment != null),
      isFalse,
    );
    expect(updated.note.attachments, isEmpty);
    expect(updated.attachments, isEmpty);
    final exported = await a.workspace.exportArchive();
    final inspection = await a.workspace.inspectArchive(exported);
    expect(inspection.noteCountsByProfile, {'everyday': 1});
    expect(inspection.notesWithUnlinkedAttachments, 0);
    final decoded = ZipDecoder().decodeBytes(exported);
    expect(
      decoded.files.where((file) => file.name.startsWith('attachments/')),
      isEmpty,
    );
    final exportedJson = jsonDecode(
      utf8.decode(
        decoded.files.singleWhere((file) => file.name == 'notes.json').content,
      ),
    ) as Map;
    final exportedNote = NoteEntry.fromJson(
      Map<String, dynamic>.from((exportedJson['notes'] as List).single as Map),
    );
    expect(exportedNote.body, 'Updated paragraph');
    expect(exportedNote.blocks, [
      const NoteBlock(type: NoteBlockType.paragraph, text: 'Updated paragraph'),
    ]);
    expect(exportedNote.attachments, isEmpty);
    await b.workspace.recover(codes.syncCode);
    await b.workspace.importArchive(
      bytes: exported,
      destinations: {},
      acceptUnlinkedAttachments: false,
    );
    final roundTripped = b.workspace.notes.single;
    expect(roundTripped.note.body, 'Updated paragraph');
    expect(roundTripped.note.blocks, exportedNote.blocks);
    expect(roundTripped.attachments, isEmpty);
    expect(roundTripped.note.attachments, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 2)));
  test('two isolated workspaces enroll, transfer private files and resolve concurrent heads', () async {
    final cloud = _Cloud();
    final a = _Device(cloud), b = _Device(cloud);
    addTearDown(a.workspace.dispose);
    addTearDown(b.workspace.dispose);
    await a.workspace.initialize();
    await b.workspace.initialize();
    expect(a.workspace.registered, isFalse);
    final codes = await a.workspace.prepareNew('administrator password');
    expect(cloud.registryWrites, 0);
    expect(cloud.records, isEmpty);
    expect(a.activations, 0);
    await a.workspace.confirmSetup();
    expect(a.workspace.registered, isTrue);
    expect(a.workspace.adminUnlocked, isTrue);
    expect(a.activations, 1);
    expect(a.workspace.profiles.single.isNormal, isTrue);
    final normalId = a.workspace.selectedProfileId!;
    await a.workspace.saveNote(title: 'offline normal', body: 'cached body');
    await a.workspace.createProfile('Research', 'private password');
    final privateId = a.workspace.selectedProfileId!;
    final photo = Uint8List.fromList(
      List.generate(1024 * 1024 + 7, (i) => i % 251),
    );
    await a.workspace.saveNote(
      title: 'Secret',
      body: 'original',
      addedFiles: [
        SyncV2PendingAttachment(
          label: 'photo',
          type: AttachmentType.photo,
          bytes: photo,
        ),
      ],
    );
    await a.workspace.syncNow();
    await b.workspace.recover(codes.syncCode);
    expect(b.activations, 1);
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes.single.note.title, 'offline normal');
    await b.workspace.unlockPrivate('private password');
    expect(b.workspace.selectedProfileId, privateId);
    expect(b.workspace.notes.single.note.title, 'Secret');
    expect(
      await b.workspace.readAttachment(
        b.workspace.notes.single.attachments.single,
      ),
      photo,
    );
    final originalA = a.workspace.notes.single;
    final originalB = b.workspace.notes.single;
    await a.workspace.saveNote(
      original: originalA,
      title: 'A version',
      body: 'from a',
    );
    await b.workspace.saveNote(
      original: originalB,
      title: 'B version',
      body: 'from b',
    );
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    await a.workspace.syncNow();
    expect(a.workspace.notes.single.isConflict, isTrue);
    expect(b.workspace.notes.single.isConflict, isTrue);
    final conflict = a.workspace.notes.single;
    await expectLater(
      a.workspace.saveNote(original: conflict, title: 'merge', body: 'merged'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    final selected = conflict.versions.singleWhere(
      (v) => (v.body!['note'] as Map)['title'] == 'B version',
    );
    await a.workspace.saveNote(
      original: conflict,
      selectedVersionId: selected.change.id,
      title: 'Resolved',
      body: 'from b',
    );
    expect(a.workspace.notes.single.isConflict, isFalse);
    expect(a.workspace.notes.single.attachments.length, 1);
    await a.workspace.syncNow();
    await b.workspace.syncNow();
    expect(b.workspace.notes.single.note.title, 'Resolved');
    expect(b.workspace.notes.single.isConflict, isFalse);

    // Export authorization follows the selected profile even while another
    // private profile remains unlocked in the workspace.
    await a.workspace.selectProfile(normalId);
    expect(a.workspace.profiles.any((p) => p.id == privateId), isTrue);
    final normalArchive = await a.workspace.exportArchive();
    final exported = await a.workspace.inspectArchive(normalArchive);
    expect(exported.noteCountsByProfile, {'everyday': 1});
    await a.workspace.selectProfile(privateId);

    // Hold the operation queue, submit a brand-new private note, then lock
    // synchronously before the save starts. It must never borrow normal access.
    for (final useBackground in [false, true]) {
      if (b.workspace.selectedProfileId != privateId) {
        await b.workspace.resume();
        await b.workspace.unlockPrivate('private password');
      }
      final before = await b.inbox.readPage(
        generationId: b.workspace.generationId!,
        limit: 100,
      );
      b.syncEntered = Completer<void>();
      b.syncRelease = Completer<void>();
      final holding = b.workspace.syncNow();
      await b.syncEntered!.future;
      final save = b.workspace.saveNote(
        title: 'Queued private secret',
        body: 'must never enter normal notes',
        addedFiles: [
          SyncV2PendingAttachment(
            label: 'secret attachment',
            type: AttachmentType.file,
            bytes: Uint8List.fromList([71, 72, 73]),
          ),
        ],
      );
      final refused = expectLater(
        save,
        throwsA(isA<SyncV2WorkspaceException>()),
      );
      final queuedUnlockRefused = useBackground
          ? expectLater(
              b.workspace.unlockPrivate('private password'),
              throwsA(isA<SyncV2WorkspaceException>()),
            )
          : null;
      if (useBackground) {
        b.workspace.background();
      } else {
        b.workspace.lockPrivate();
      }
      b.syncRelease!.complete();
      await holding;
      await refused;
      if (queuedUnlockRefused != null) await queuedUnlockRefused;
      expect(b.workspace.profiles.length, 1);
      final after = await b.inbox.readPage(
        generationId: b.workspace.generationId!,
        limit: 100,
      );
      expect(after.map((r) => r.id).toSet(), before.map((r) => r.id).toSet());
      expect(
        await b.inbox.readOutbox(
          generationId: b.workspace.generationId!,
          limit: 100,
        ),
        isEmpty,
      );
      await b.workspace.resume();
      expect(b.workspace.notes.single.note.title, 'offline normal');
      expect(b.workspace.notes.single.note.body, 'cached body');
      expect(b.workspace.notes.single.attachments, isEmpty);
    }

    b.workspace.lockPrivate();
    await expectLater(
      b.workspace.recoverAdmin('invalid code', 'new administrator password'),
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    expect(b.workspace.adminUnlocked, isFalse);
    await b.workspace.recoverAdmin(
      codes.adminCode,
      'new administrator password',
    );
    expect(b.workspace.adminUnlocked, isTrue);
    expect(b.workspace.profiles.any((p) => p.id == privateId), isTrue);

    // A delayed unlock cannot recreate private plaintext after an app lock.
    b.workspace.lockPrivate();
    b.store.unlockEntered = Completer<void>();
    b.store.unlockRelease = Completer<void>();
    final unlock = b.workspace.unlockPrivate('private password');
    final rejected = expectLater(
      unlock,
      throwsA(isA<SyncV2WorkspaceException>()),
    );
    await b.store.unlockEntered!.future;
    b.workspace.background();
    b.store.unlockRelease!.complete();
    await rejected;
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes, isEmpty);
    expect(b.workspace.adminUnlocked, isFalse);

    await b.workspace.resume();
    await b.workspace.unlockPrivate('private password');
    b.syncEntered = Completer<void>();
    b.syncRelease = Completer<void>();
    final syncing = b.workspace.syncNow();
    await b.syncEntered!.future;
    b.workspace.background();
    b.syncRelease!.complete();
    await syncing;
    expect(b.workspace.profiles.length, 1);
    expect(b.workspace.notes, isEmpty);
    expect(b.workspace.adminUnlocked, isFalse);

    // Cached registration restores normal data even if account/registry reads fail.
    cloud.offline = true;
    await a.workspace.initialize();
    expect(a.workspace.selectedProfileId, normalId);
    expect(a.workspace.notes.single.note.title, 'offline normal');
    expect(a.workspace.profiles.length, 1);
    expect(a.activations, 2);
    expect(a.deactivations, 0);
    await a.workspace.leaveV2();
    expect(a.deactivations, 1);
  }, timeout: const Timeout(Duration(minutes: 2)));
}
