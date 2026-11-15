import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_profile_catalog.dart';

void main() {
  setUp(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = true);
  tearDown(() => driftRuntimeOptions.dontWarnAboutMultipleDatabases = false);
  test('portable encrypted catalog unlocks all matching profiles and rewraps passwords', () async {
    final encryption = EncryptionService();
    final sync = SecretKey(List.filled(32, 11));
    final admin = SecretKey(List.filled(32, 12));
    final rawNormal = SecretKey(List.filled(32, 13));
    final normalWrap = await encryption.encryptBytes(
      clearBytes: await rawNormal.extractBytes(),
      secretKey: sync,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          'account',
          'generation',
          'normal-sync-wrap',
          'normal',
          'normal-key',
        ]),
      ),
    );
    final normal = await SyncV2UnlockedProfileKey.unlockNormal(
      encryption: encryption,
      accountId: 'account',
      generationId: 'generation',
      profileId: 'normal',
      keyId: 'normal-key',
      syncWrap: normalWrap,
      syncKey: sync,
    );
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final repository = SyncV2NoteRepository(
      inbox,
      headers,
      SyncV2PayloadCodec(encryption),
    );
    SyncV2ProfileCatalog device() => SyncV2ProfileCatalog(
      inbox,
      repository,
      encryption,
      MemorySecureKeyValueStore(),
      generationId: 'generation',
      syncKey: sync,
      normalAccess: normal,
    );
    final first = await device().create(
      name: 'Secret journal alpha',
      password: 'shared private password',
      adminKey: admin,
    );
    final second = await device().create(
      name: 'Secret journal beta',
      password: 'shared private password',
      adminKey: admin,
    );
    expect(first.id, startsWith('private_profile:'));
    final records = await device().load();
    expect(
      jsonEncode(records.map((r) => r.wrapped.toJson()).toList()),
      isNot(contains('Secret journal')),
    );
    for (final record in records) {
      expect(record.encryptedName, isNot(contains('Secret journal')));
      await expectLater(
        encryption.decryptBytes(
          encodedPayload: record.encryptedName,
          secretKey: sync,
        ),
        throwsA(isA<HimemoDecryptionException>()),
      );
    }
    // A fresh service has no retained private keys or names.
    final unlocked = await device().unlock('shared private password');
    expect(unlocked.map((p) => p.name).toSet(), {
      'Secret journal alpha',
      'Secret journal beta',
    });
    final recovered = await device().unlockAdmin(admin);
    expect(recovered.length, 2);
    final remoteInbox = SyncV2Inbox(NativeDatabase.memory(), headers);
    final page = await inbox.readPage(generationId: 'generation', limit: 100);
    await remoteInbox.stagePage(
      generationId: 'generation',
      expectedCursor: null,
      nextCursor: 'first-page',
      records: page,
      syncKey: sync,
    );
    for (final header in page) {
      await remoteInbox.storePayload(
        generationId: 'generation',
        recordId: header.id,
        encryptedPayload: (await inbox.readPayload(
          generationId: 'generation',
          recordId: header.id,
        ))!,
        syncKey: sync,
      );
    }
    final remoteCatalog = SyncV2ProfileCatalog(
      remoteInbox,
      SyncV2NoteRepository(
        remoteInbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
      encryption,
      MemorySecureKeyValueStore(),
      generationId: 'generation',
      syncKey: sync,
      normalAccess: normal,
    );
    final remoteProfiles = await remoteCatalog.unlock(
      'shared private password',
    );
    expect(remoteProfiles.map((profile) => profile.name).toSet(), {
      'Secret journal alpha',
      'Secret journal beta',
    });
    await remoteCatalog.changePassword(
      profile: remoteProfiles.firstWhere((p) => p.id == first.id),
      password: 'remote independent password',
      adminKey: admin,
    );

    await device().changePassword(
      profile: first,
      password: 'new independent password',
      adminKey: admin,
    );
    final old = await device().unlock('shared private password');
    expect(old.map((p) => p.id), [second.id]);
    final changed = await device().unlock('new independent password');
    expect(changed.single.id, first.id);
    expect(
      await changed.single.access.key.extractBytes(),
      await first.access.key.extractBytes(),
    );
    // Retrying rewrap preserves the key and active profile identity.
    await device().changePassword(
      profile: changed.single,
      password: 'new independent password',
      adminKey: admin,
    );
    final badAdmin = SecretKey(List.filled(32, 99));
    await expectLater(
      device().changePassword(
        profile: first,
        password: 'third independent password',
        adminKey: badAdmin,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
    badAdmin.destroy();
    final remotePage = await remoteInbox.readPage(
      generationId: 'generation',
      limit: 100,
    );
    await inbox.stagePage(
      generationId: 'generation',
      expectedCursor: null,
      nextCursor: 'remote-page',
      records: remotePage,
      syncKey: sync,
    );
    for (final header in remotePage) {
      await inbox.storePayload(
        generationId: 'generation',
        recordId: header.id,
        encryptedPayload: (await remoteInbox.readPayload(
          generationId: 'generation',
          recordId: header.id,
        ))!,
        syncKey: sync,
      );
    }
    final conflicts = await device().loadConflicts();
    expect(conflicts.single.profileId, first.id);
    expect(conflicts.single.headIds.length, 2);
    final unaffected = await device().unlock('shared private password');
    expect(unaffected.single.id, second.id);
    final adminUnaffected = await device().unlockAdmin(admin);
    expect(adminUnaffected.single.id, second.id);
    expect(await device().conflictNames(admin), {first.id: first.name});
    final importAccess = await device().ensureImportProfile(
      sourceProfileId: first.id,
      name: 'Imported',
      adminKey: admin,
    );
    expect(importAccess.id, first.id);
    importAccess.destroy();
    expect(
      (await device().loadConflicts()).single.headIds,
      conflicts.single.headIds,
      reason: 'Import must not silently resolve a real password conflict',
    );
    await device().resolvePasswordConflict(
      profileId: first.id,
      password: 'repaired independent password',
      adminKey: admin,
    );
    expect(await device().loadConflicts(), isEmpty);
    final repaired = await device().unlock('repaired independent password');
    expect(
      await repaired.single.access.key.extractBytes(),
      await first.access.key.extractBytes(),
    );
    final repairedRecord = (await device().load()).singleWhere(
      (r) => r.wrapped.profileId == first.id,
    );
    expect(repairedRecord.headIds.length, 1);
    final repairNote = await repository.readNote(
      generationId: 'generation',
      profileId: normal.profileId,
      noteId: repairedRecord.noteId,
      syncKey: sync,
      profileKey: normal,
    );
    expect(
      repairNote.versions.single.change.parentIds,
      conflicts.single.headIds,
    );
    final repairedPage = await inbox.readPage(
      generationId: 'generation',
      limit: 100,
    );
    await remoteInbox.stagePage(
      generationId: 'generation',
      expectedCursor: 'first-page',
      nextCursor: 'repaired-page',
      records: repairedPage,
      syncKey: sync,
    );
    for (final header in repairedPage) {
      await remoteInbox.storePayload(
        generationId: 'generation',
        recordId: header.id,
        encryptedPayload: (await inbox.readPayload(
          generationId: 'generation',
          recordId: header.id,
        ))!,
        syncKey: sync,
      );
    }
    expect(await remoteCatalog.loadConflicts(), isEmpty);
    final remoteRepaired = await remoteCatalog.unlock(
      'repaired independent password',
    );
    expect(remoteRepaired.single.id, first.id);
    // A conflicting admin-wrapped DIFFERENT key must never overwrite history.
    final wrongProfileKey = SecretKey(List.filled(32, 123));
    final wrongWrapped = await SyncV2ProfileKeys(encryption).wrap(
      generationId: 'generation',
      profileId: first.id,
      keyId: first.access.keyId,
      profileKey: wrongProfileKey,
      passphrase: 'other wrapping password',
      adminKey: admin,
    );
    final wrongName = await encryption.encryptBytes(
      clearBytes: utf8.encode(first.name),
      secretKey: wrongProfileKey,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo.sync.v2.profile-name',
          'generation',
          normal.profileId,
          first.id,
          first.access.keyId,
        ]),
      ),
    );
    final injected = <SyncV2RemoteHeader>[];
    final payloads = SyncV2PayloadCodec(encryption);
    final bodies = [
      {
        'type': 'profile-key',
        'wrapped': repairedRecord.wrapped.toJson(),
        'name': repairedRecord.encryptedName,
      },
      {
        'type': 'profile-key',
        'wrapped': wrongWrapped.toJson(),
        'name': wrongName,
      },
    ];
    for (var i = 0; i < bodies.length; i++) {
      final sealed = await payloads.seal(
        generationId: 'generation',
        changeId: 'forged_sibling_$i',
        profileId: normal.profileId,
        noteId: repairedRecord.noteId,
        parentIds: repairedRecord.headIds,
        body: bodies[i],
        profileKey: normal.key,
      );
      injected.add((
        id: sealed.change.id,
        encryptedHeader: await headers.seal(
          sealed.change,
          generationId: 'generation',
          syncKey: sync,
        ),
      ));
      await inbox.stagePage(
        generationId: 'generation',
        expectedCursor: i == 0 ? 'remote-page' : 'forged-0',
        nextCursor: 'forged-$i',
        records: [injected.last],
        syncKey: sync,
      );
      await inbox.storePayload(
        generationId: 'generation',
        recordId: sealed.change.id,
        encryptedPayload: sealed.encryptedPayload,
        syncKey: sync,
      );
    }
    final mismatched = (await device().loadConflicts()).single;
    await expectLater(
      device().resolvePasswordConflict(
        profileId: first.id,
        password: 'must never be installed',
        adminKey: admin,
      ),
      throwsA(isA<HimemoDecryptionException>()),
    );
    expect((await device().loadConflicts()).single.headIds, mismatched.headIds);
    wrongProfileKey.destroy();
    for (final profile in [
      ...remoteProfiles,
      ...unaffected,
      ...adminUnaffected,
      ...repaired,
      ...remoteRepaired,
    ]) {
      profile.destroy();
    }
    await remoteInbox.close();
    final latest = (await device().load()).first;
    await repository.save(
      generationId: 'generation',
      profileId: normal.profileId,
      noteId: 'profile_duplicate',
      changeId: 'duplicate_catalog',
      expectedHeadIds: {},
      body: {
        'type': 'profile-key',
        'wrapped': latest.wrapped.toJson(),
        'name': latest.encryptedName,
      },
      syncKey: sync,
      profileKey: normal,
    );
    await expectLater(device().load(), throwsFormatException);
    for (final profile in [
      first,
      second,
      ...unlocked,
      ...recovered,
      ...old,
      ...changed,
    ]) {
      profile.destroy();
    }
    normal.destroy();
    rawNormal.destroy();
    sync.destroy();
    admin.destroy();
    await inbox.close();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
