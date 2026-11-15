import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_transport.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_profile_catalog.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const generation = String.fromEnvironment('HIMEMO_SYNC_V2_DEV_GENERATION');
  final enabled =
      RegExp(r'^dev_[a-zA-Z0-9_-]{1,30}$').hasMatch(generation) &&
      defaultTargetPlatform == TargetPlatform.iOS;

  testWidgets('CloudKit v2 development zone round-trips encrypted data', (
    _,
  ) async {
    final identity = SyncV2ICloudTransport(accountId: '');
    final account = await identity.readCurrentAccountId();
    final transport = SyncV2ICloudTransport(accountId: account);
    final encryption = EncryptionService();
    final headerCodec = SyncV2HeaderCodec(encryption);
    final payloadCodec = SyncV2PayloadCodec(encryption);
    final inbox = SyncV2Inbox(NativeDatabase.memory(), headerCodec);
    addTearDown(inbox.close);
    final receiver = SyncV2Receiver(transport, inbox);
    final syncKey = SecretKey(encryption.generateKeyBytes());
    final profileKey = SecretKey(encryption.generateKeyBytes());
    addTearDown(syncKey.destroy);
    addTearDown(profileKey.destroy);
    await transport.prepareGeneration(generation);
    expect(
      await receiver.pullPage(
        generationId: generation,
        syncKey: syncKey,
        limit: 10,
      ),
      (staged: true, hasMore: false),
    );
    final before = await inbox.readPage(generationId: generation, limit: 10);
    expect(before, isEmpty, reason: 'Choose a fresh development zone');

    final prepared = await payloadCodec.seal(
      generationId: generation,
      changeId: 'smoke-change',
      profileId: 'smoke-profile',
      noteId: 'smoke-note',
      parentIds: {},
      body: {'text': 'synthetic development fixture'},
      profileKey: profileKey,
    );
    final encryptedHeader = await headerCodec.seal(
      prepared.change,
      generationId: generation,
      syncKey: syncKey,
    );
    final publication = (
      id: prepared.change.id,
      encryptedHeader: encryptedHeader,
      encryptedPayload: prepared.encryptedPayload,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      await transport.publish(
        generationId: generation,
        publication: publication,
      );
    }
    // The synthetic fixture supplies a trusted enrollment for this test.
    final enrollments = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
    await enrollments.saveVerified((
      accountId: account,
      generationId: generation,
      syncKey: syncKey,
    ));
    final progress = await SyncV2ICloudSession(
      enrollments,
      inbox,
    ).syncOnce(limit: 10);
    expect(progress.headersStaged, isTrue);
    expect(progress.hasMoreHeaders, isFalse);
    expect(progress.downloadedPayloads, 1);
    expect(progress.publishedChanges, 0);
    expect(progress.errors, isEmpty);
    final after = await inbox.readPage(generationId: generation, limit: 10);
    final fetched = after.single;
    final change = await headerCodec.open(
      fetched.encryptedHeader,
      generationId: generation,
      recordId: fetched.id,
      syncKey: syncKey,
    );
    final body = (await inbox.readPayload(
      generationId: generation,
      recordId: change.id,
    ))!;
    expect(body, orderedEquals(publication.encryptedPayload));
    expect(
      await payloadCodec.open(
        generationId: generation,
        change: change,
        encryptedPayload: body,
        profileKey: profileKey,
      ),
      {'text': 'synthetic development fixture'},
    );
  }, skip: !enabled);

  testWidgets(
    'isolated CloudKit registration recovers a second device and its notes',
    (_) async {
      final account = await SyncV2ICloudTransport(accountId: '')
          .readCurrentAccountId();
      final encryption = EncryptionService();
      final adminKey = SecretKey(encryption.generateKeyBytes());
      addTearDown(adminKey.destroy);
      // Never use metadata-v1 (the real account registry) in this fixture.
      final registry = SyncV2ICloudGenerationRegistrationTransport(
        SyncV2ICloudTransport(accountId: account),
        metadataGenerationId: '${generation}_registry',
      );
      final sourceEnrollment = SyncV2EnrollmentStore(
        MemorySecureKeyValueStore(),
      );
      final targetEnrollment = SyncV2EnrollmentStore(
        MemorySecureKeyValueStore(),
      );
      final sourceRegistration = SyncV2GenerationRegistration(
        registry,
        sourceEnrollment,
        generationPrefix: '${generation}_g',
      );
      final prepared = await sourceRegistration.prepare(
        accountId: account,
        adminKey: adminKey,
      );
      addTearDown(prepared.destroy);
      final sourceProfile = await sourceRegistration.publishPrepared(prepared);
      addTearDown(sourceProfile.destroy);
      final targetProfile = await SyncV2GenerationRegistration(
        registry,
        targetEnrollment,
      ).recover(prepared.recoveryCode);
      addTearDown(targetProfile.destroy);
      expect(targetProfile.profileId, sourceProfile.profileId);
      expect(
        await targetProfile.normalKey.extractBytes(),
        await sourceProfile.normalKey.extractBytes(),
      );
      final headers = SyncV2HeaderCodec(encryption);
      final payloads = SyncV2PayloadCodec(encryption);
      final source = SyncV2Inbox(NativeDatabase.memory(), headers);
      final target = SyncV2Inbox(NativeDatabase.memory(), headers);
      addTearDown(source.close);
      addTearDown(target.close);
      final sourceKeys = (await sourceEnrollment.readForAccount(account))!;
      final targetKeys = (await targetEnrollment.readForAccount(account))!;
      addTearDown(sourceKeys.syncKey.destroy);
      addTearDown(targetKeys.syncKey.destroy);
      await SyncV2NoteRepository(source, headers, payloads).save(
        generationId: sourceKeys.generationId,
        profileId: sourceProfile.profileId,
        noteId: 'synthetic-note',
        changeId: 'synthetic-change',
        expectedHeadIds: {},
        body: {'text': 'synthetic registered-device fixture'},
        syncKey: sourceKeys.syncKey,
        profileKey: sourceProfile.access,
      );
      final published = await SyncV2ICloudSession(
        sourceEnrollment,
        source,
      ).syncOnce(limit: 10);
      expect(published.publishedChanges, 1);
      expect(published.errors, isEmpty);
      final received = await SyncV2ICloudSession(
        targetEnrollment,
        target,
      ).syncOnce(limit: 10);
      expect(received.errors, isEmpty);
      expect(received.downloadedPayloads, 1);
      final notes = SyncV2NoteRepository(target, headers, payloads);
      final locked = await notes.readNote(
        generationId: targetKeys.generationId,
        profileId: targetProfile.profileId,
        noteId: 'synthetic-note',
        syncKey: targetKeys.syncKey,
      );
      expect(locked.versions.single.body, isNull);
      final unlocked = await notes.readNote(
        generationId: targetKeys.generationId,
        profileId: targetProfile.profileId,
        noteId: 'synthetic-note',
        syncKey: targetKeys.syncKey,
        profileKey: targetProfile.access,
      );
      expect(unlocked.versions.single.body, {
        'text': 'synthetic registered-device fixture',
      });

      // Exercise the production private catalog and chunk format against the
      // same isolated development generation, never the real account registry.
      const privatePassword = 'synthetic private fixture password';
      final sourceNotes = SyncV2NoteRepository(source, headers, payloads);
      final sourceCatalog = SyncV2ProfileCatalog(
        source,
        sourceNotes,
        encryption,
        MemorySecureKeyValueStore(),
        generationId: sourceKeys.generationId,
        syncKey: sourceKeys.syncKey,
        normalAccess: sourceProfile.access,
      );
      final privateProfile = await sourceCatalog.create(
        name: 'Synthetic private fixture',
        password: privatePassword,
        adminKey: adminKey,
      );
      addTearDown(privateProfile.destroy);
      final attachmentBytes = Uint8List.fromList(
        List.generate(1024 * 1024 + 137, (index) => index % 251),
      );
      final attachment = await SyncV2AttachmentService(source, sourceNotes)
          .store(
            generationId: sourceKeys.generationId,
            syncKey: sourceKeys.syncKey,
            profileAccess: privateProfile.access,
            bytes: attachmentBytes,
            label: 'synthetic-private-photo.bin',
            type: AttachmentType.photo.name,
          );
      expect(attachment.chunks, hasLength(2));
      final privateNote = NoteEntry(
        id: 'synthetic-private-note',
        vaultId: privateProfile.id,
        title: 'Synthetic private title',
        body: 'Synthetic private body',
        createdAt: DateTime.utc(2026, 1, 1),
        attachments: [
          NoteAttachment(
            type: AttachmentType.photo,
            label: attachment.label,
            filePath: 'v2attachment:${attachment.id}',
          ),
        ],
      );
      await sourceNotes.save(
        generationId: sourceKeys.generationId,
        profileId: privateProfile.id,
        noteId: privateNote.id,
        changeId: 'synthetic-private-change',
        expectedHeadIds: {},
        syncKey: sourceKeys.syncKey,
        profileKey: privateProfile.access,
        body: {
          'type': 'note',
          'note': privateNote.toJson(),
          'attachments': [attachment.toJson()],
        },
      );
      final privatePublished = await SyncV2ICloudSession(
        sourceEnrollment,
        source,
        stopOnQuarantine: true,
      ).syncOnce(limit: 10);
      expect(privatePublished.errors, isEmpty);
      expect(
        privatePublished.publishedChanges,
        4,
        reason: 'Catalog, two attachment chunks, and private note',
      );
      final privateReceived = await SyncV2ICloudSession(
        targetEnrollment,
        target,
        stopOnQuarantine: true,
      ).syncOnce(limit: 10);
      expect(privateReceived.errors, isEmpty);
      expect(privateReceived.downloadedPayloads, 4);
      final privateLocked = await notes.readNote(
        generationId: targetKeys.generationId,
        profileId: privateProfile.id,
        noteId: privateNote.id,
        syncKey: targetKeys.syncKey,
      );
      expect(privateLocked.versions.single.body, isNull);
      final targetCatalog = SyncV2ProfileCatalog(
        target,
        notes,
        encryption,
        MemorySecureKeyValueStore(),
        generationId: targetKeys.generationId,
        syncKey: targetKeys.syncKey,
        normalAccess: targetProfile.access,
      );
      final targetPrivateProfiles = await targetCatalog.unlock(privatePassword);
      for (final profile in targetPrivateProfiles) {
        addTearDown(profile.destroy);
      }
      final targetPrivate = targetPrivateProfiles.single;
      expect(targetPrivate.id, privateProfile.id);
      expect(targetPrivate.name, 'Synthetic private fixture');
      final privateUnlocked = await notes.readNote(
        generationId: targetKeys.generationId,
        profileId: targetPrivate.id,
        noteId: privateNote.id,
        syncKey: targetKeys.syncKey,
        profileKey: targetPrivate.access,
      );
      final privateBody = privateUnlocked.versions.single.body!;
      final restoredNote = NoteEntry.fromJson(
        Map<String, dynamic>.from(privateBody['note'] as Map),
      );
      expect(restoredNote.title, privateNote.title);
      expect(restoredNote.body, privateNote.body);
      final restoredAttachment = SyncV2AttachmentReference.fromJson(
        Map<String, dynamic>.from(
          (privateBody['attachments'] as List).single as Map,
        ),
      );
      expect(
        await SyncV2AttachmentService(target, notes).read(
          reference: restoredAttachment,
          generationId: targetKeys.generationId,
          syncKey: targetKeys.syncKey,
          profileAccess: targetPrivate.access,
        ),
        orderedEquals(attachmentBytes),
      );
    },
    skip: !enabled,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
