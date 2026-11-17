import 'dart:typed_data';
import 'dart:io';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
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
  late SyncV2Inbox inbox;
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
    inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    addTearDown(inbox.close);
    repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    privateUnlocked = false;
    registered = true;
  });

  Future<
    ({SyncV2NoteStore notes, SyncV2AttachmentStore files, Directory directory})
  >
  attachmentStores() async {
    SharedPreferences.setMockInitialValues({});
    final directory = await Directory.systemTemp.createTemp(
      'himemo-v2-attachments-',
    );
    addTearDown(() => directory.delete(recursive: true));
    final encryption = EncryptionService();
    late SyncV2NoteStore notes;
    final files = SyncV2AttachmentStore(
      encryptionService: encryption,
      masterKeyService: MasterKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: encryption.generateKeyBytes,
      ),
      session: session,
      noteStore: () => notes,
      directoryProvider: () async => directory,
      temporaryDirectoryProvider: () async => directory,
    );
    notes = SyncV2NoteStore(
      repository: repository,
      session: session,
      attachmentService: SyncV2AttachmentService(inbox, repository),
      attachmentStore: files,
    );
    return (notes: notes, files: files, directory: directory);
  }

  test('photo video and audio drafts commit to private chunks and survive reload and edits', () async {
    privateUnlocked = true;
    final stores = await attachmentStores();
    final attachments = <NoteAttachment>[];
    for (final type in [
      AttachmentType.photo,
      AttachmentType.video,
      AttachmentType.audio,
    ]) {
      final path = await stores.files.storeAttachment(
        XFile.fromData(
          Uint8List.fromList([1, 2, 3, type.index]),
          name: '${type.name}.bin',
        ),
        type: type,
      );
      await stores.files.protectAttachmentForVault(
        path!,
        type: type,
        vaultId: _privateId,
      );
      attachments.add(
        NoteAttachment(
          type: type,
          label: '${type.name}.bin',
          filePath: path,
          durationMs: 1234,
        ),
      );
    }
    final saved = await stores.notes.saveOne(
      _note('media', vaultId: _privateId).copyWith(
        attachments: attachments,
        blocks: [
          for (final attachment in attachments)
            NoteBlock(
              type: NoteBlockType.values.byName(attachment.type.name),
              attachment: attachment,
            ),
        ],
      ),
    );
    expect(
      saved.attachments.every((a) => a.filePath!.startsWith('v2attachment:')),
      isTrue,
    );
    final normalHistory = await repository.readProfile(
      generationId: 'g',
      profileId: _normalId,
      syncKey: sync,
      profileKey: normal,
    );
    expect(normalHistory, isEmpty);
    final loaded = (await stores.notes.load(fallbackNotes: const [])).single;
    final edited = await stores.notes.saveOne(loaded.copyWith(title: 'edited'));
    expect(edited.attachments, saved.attachments);
    for (final attachment in edited.attachments) {
      expect(
        await stores.files.readAttachment(
          attachment.filePath!,
          type: attachment.type,
        ),
        [1, 2, 3, attachment.type.index],
      );
      final temp = await stores.files.materializeDecryptedFile(
        attachment.filePath!,
        type: attachment.type,
        preferredFileName: attachment.label,
      );
      expect(await File(temp!).readAsBytes(), [1, 2, 3, attachment.type.index]);
      expect(attachment.durationMs, 1234);
    }
    privateUnlocked = false;
    await expectLater(
      stores.files.readAttachment(
        saved.attachments.first.filePath!,
        type: AttachmentType.photo,
      ),
      throwsA(isA<SyncV2NoteStoreLocked>()),
    );
    await expectLater(
      stores.files.readAttachment(
        attachments.first.filePath!,
        type: AttachmentType.photo,
      ),
      throwsA(isA<SyncV2NoteStoreLocked>()),
    );
  });

  test('a stale note rolls back its new chunks and retries use stable draft identities', () async {
    final stores = await attachmentStores();
    await stores.notes.saveOne(_note('stale'));
    final other = newStore();
    await other.load(fallbackNotes: const []);
    await other.saveOne(_note('stale', title: 'other writer'));
    final path = await stores.files.storeAttachment(
      XFile.fromData(Uint8List.fromList([5, 6]), name: 'image.png'),
      type: AttachmentType.photo,
    );
    final draft = _note('stale').copyWith(
      attachments: [
        NoteAttachment(
          type: AttachmentType.photo,
          label: 'image.png',
          filePath: path,
        ),
      ],
    );
    await expectLater(
      stores.notes.saveOne(draft),
      throwsA(isA<SyncV2StaleNote>()),
    );
    final history = await repository.readProfile(
      generationId: 'g',
      profileId: _normalId,
      syncKey: sync,
      profileKey: normal,
    );
    expect(history.keys.where((id) => id.startsWith('blob_')), isEmpty);
    await stores.notes.load(fallbackNotes: const []);
    final saved = await stores.notes.saveOne(draft);
    final first = await repository.readProfile(
      generationId: 'g',
      profileId: _normalId,
      syncKey: sync,
      profileKey: normal,
    );
    await stores.notes.saveOne(draft.copyWith(title: 'retry'));
    final second = await repository.readProfile(
      generationId: 'g',
      profileId: _normalId,
      syncKey: sync,
      profileKey: normal,
    );
    expect(
      second.keys.where((id) => id.startsWith('blob_')),
      first.keys.where((id) => id.startsWith('blob_')),
    );
    expect(
      await stores.files.readAttachment(
        saved.attachments.single.filePath!,
        type: AttachmentType.photo,
      ),
      [5, 6],
    );
  });

  test(
    'moving a note reencrypts its attachment in the destination profile',
    () async {
      privateUnlocked = true;
      final stores = await attachmentStores();
      final path = await stores.files.storeAttachment(
        XFile.fromData(Uint8List.fromList([7, 8]), name: 'audio.wav'),
        type: AttachmentType.audio,
      );
      final saved = await stores.notes.saveOne(
        _note('move').copyWith(
          attachments: [
            NoteAttachment(
              type: AttachmentType.audio,
              label: 'audio.wav',
              filePath: path,
            ),
          ],
        ),
      );
      final moved = await stores.notes.saveOne(
        saved.copyWith(vaultId: _privateId),
      );
      expect(
        moved.attachments.single.filePath,
        isNot(saved.attachments.single.filePath),
      );
      final loaded = await stores.notes.load(fallbackNotes: const []);
      expect(loaded.single.vaultId, _privateId);
      expect(
        await stores.files.readAttachment(
          moved.attachments.single.filePath!,
          type: AttachmentType.audio,
        ),
        [7, 8],
      );
    },
  );

  test('v2 draft cleanup is isolated from v1 attachment storage', () async {
    final stores = await attachmentStores();
    final encryption = EncryptionService();
    final legacy = EncryptedAttachmentStore(
      encryptionService: encryption,
      masterKeyService: MasterKeyService(
        secureStore: MemorySecureKeyValueStore(),
        keyFactory: encryption.generateKeyBytes,
      ),
      directoryProvider: () async => stores.directory,
    );
    final source = XFile.fromData(
      Uint8List.fromList([4, 5]),
      name: 'photo.jpg',
    );
    final oldPath = await legacy.storeAttachment(
      source,
      type: AttachmentType.photo,
    );
    final draftPath = await stores.files.storeAttachment(
      source,
      type: AttachmentType.photo,
    );
    expect(await stores.files.deleteUnreferencedAttachments({}), 1);
    expect(await File(draftPath!).exists(), isFalse);
    expect(await legacy.readAttachment(oldPath!, type: AttachmentType.photo), [
      4,
      5,
    ]);
  });

  test(
    'an editor can resave its committed draft path after local cleanup',
    () async {
      final stores = await attachmentStores();
      final path = await stores.files.storeAttachment(
        XFile.fromData(Uint8List.fromList([4, 5]), name: 'photo.jpg'),
        type: AttachmentType.photo,
      );
      final draft = _note('cleanup').copyWith(
        attachments: [
          NoteAttachment(
            type: AttachmentType.photo,
            label: 'photo.jpg',
            filePath: path,
          ),
        ],
      );
      final saved = await stores.notes.saveOne(draft);
      await stores.files.deleteAttachment(path!);
      await stores.notes.load(fallbackNotes: const []);
      final resaved = await stores.notes.saveOne(
        draft.copyWith(title: 'editor retry'),
      );
      expect(
        resaved.attachments.single.filePath,
        saved.attachments.single.filePath,
      );
      expect(
        await stores.files.readAttachment(
          resaved.attachments.single.filePath!,
          type: AttachmentType.photo,
        ),
        [4, 5],
      );
    },
  );

  test(
    'locked placeholders never overwrite the original private note',
    () async {
      privateUnlocked = true;
      final store = newStore();
      final original = _note(
        'secret',
        vaultId: _privateId,
      ).copyWith(body: 'keep this');
      await store.saveOne(original);
      final placeholder = original.copyWith(
        body: '',
        deviceId: 'locked-private-note',
      );
      await store.saveOne(placeholder);
      privateUnlocked = false;
      await store.save([
        _note('public'),
        placeholder,
      ], preserveOmittedPrivateNotes: true);
      privateUnlocked = true;
      final loaded = await store.load(fallbackNotes: const []);
      expect(loaded.singleWhere((n) => n.id == 'secret').body, 'keep this');
    },
  );

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

  test('conflicted notes load but refuse edits and deletes', () async {
    SyncV2NoteVersion version(String id) => SyncV2NoteVersion(
      change: SyncV2Change(
        id: id,
        profileId: _normalId,
        noteId: 'note_c',
        operation: SyncV2Operation.upsert,
        parentIds: const {},
        payloadDigest: 'digest',
      ),
      payloadAvailable: true,
      body: {
        'type': 'note',
        'note': _note('note_c', vaultId: _normalId, title: id).toJson(),
      },
    );
    final store = SyncV2NoteStore(
      repository: _FixedRepository({
        'note_c': SyncV2NoteSnapshot(
          versions: [version('a'), version('b')],
          pendingIds: const {},
        ),
      }),
      session: session,
    );
    expect((await store.load(fallbackNotes: const [])).single.id, 'c');
    await expectLater(
      store.saveOne(_note('c', title: 'overwrite')),
      throwsA(isA<SyncV2StaleNote>()),
    );
    await expectLater(store.deleteById('c'), throwsA(isA<SyncV2StaleNote>()));
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

class _FixedRepository extends SyncV2NoteRepository {
  _FixedRepository(this.snapshots)
    : super(
        SyncV2Inbox(
          NativeDatabase.memory(),
          SyncV2HeaderCodec(EncryptionService()),
        ),
        SyncV2HeaderCodec(EncryptionService()),
        SyncV2PayloadCodec(EncryptionService()),
      );
  final Map<String, SyncV2NoteSnapshot> snapshots;

  @override
  Future<Map<String, SyncV2NoteSnapshot>> readProfile({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    SyncV2UnlockedProfileKey? profileKey,
    String? noteIdPrefix,
  }) async => profileId == _normalId ? snapshots : const {};
}
