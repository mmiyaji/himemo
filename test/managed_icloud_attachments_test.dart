import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/icloud_sync_transport.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('InMemory managed attachments', () {
    test(
      'legacy objects are reused in place without managed copies or holds',
      () async {
        final transport = InMemoryICloudSyncTransport();
        await transport.uploadAttachmentObject(
          contentHash: 'legacy-hash',
          encodedPayload: 'original-cipher',
          type: 'file',
          label: 'original',
          sizeBytes: 15,
        );
        for (final payload in [null, 'replacement-cipher']) {
          final id = await transport.pinAttachmentObject(
            contentHash: 'legacy-hash',
            uploadId: 'new-upload',
            encodedPayload: payload,
            type: 'file',
            label: 'new',
            sizeBytes: 18,
          );
          expect(id, 'attachment-legacy-hash');
          expect(await transport.listManagedAttachmentObjects(), isEmpty);
          expect(
            await transport.downloadAttachmentObject('legacy-hash'),
            'original-cipher',
          );
          await transport.releaseAttachmentObject(
            recordId: id,
            uploadId: 'new-upload',
            publishedBundleId: 'new-bundle',
          );
        }
        expect((await transport.fetchStorageBreakdown()).attachmentCount, 1);
      },
    );

    test('pins durably, CAS invalidates a racing delete, then releases and deletes', () async {
      final transport = InMemoryICloudSyncTransport();
      final id = await transport.pinAttachmentObject(
        contentHash: 'h',
        uploadId: 'u1',
        encodedPayload: 'cipher',
        type: 'image',
        label: 'x',
        sizeBytes: 7,
      );
      final first = (await transport.listManagedAttachmentObjects()).single;
      expect(first.id, id);
      expect(first.uploadIds, {'u1'});
      expect(first.contentHash, 'h');
      await transport.pinAttachmentObject(
        contentHash: 'h',
        uploadId: 'u2',
        type: 'image',
        label: 'x',
        sizeBytes: 7,
      );
      expect(await transport.claimAndDeleteAttachmentObject(first), isFalse);
      await transport.releaseAttachmentObject(
        recordId: id,
        uploadId: 'u1',
        publishedBundleId: 'b1',
      );
      await transport.releaseAttachmentObject(
        recordId: id,
        uploadId: 'u2',
        publishedBundleId: 'b2',
      );
      final candidate = (await transport.listManagedAttachmentObjects()).single;
      expect(candidate.uploadIds, isEmpty);
      expect(candidate.lastPublishedBundleId, 'b2');
      expect(await transport.claimAndDeleteAttachmentObject(candidate), isTrue);
      expect(await transport.listManagedAttachmentObjects(), isEmpty);
    });

    test('managed copy is reused only up to three holders; deleting hash is still available only while active', () async {
      final transport = InMemoryICloudSyncTransport();
      final ids = <String>[];
      for (var i = 0; i < 4; i++) {
        ids.add(
          await transport.pinAttachmentObject(
            contentHash: 'h',
            uploadId: 'u$i',
            encodedPayload: 'cipher',
            type: 'file',
            label: 'f',
            sizeBytes: 1,
          ),
        );
      }
      expect(ids.take(3).toSet(), hasLength(1));
      expect(ids[3], isNot(ids[0]));
      expect(await transport.downloadAttachmentObject('h'), 'cipher');
      expect(await transport.listAttachmentObjectContentHashes(), {'h'});
    });
  });

  group('MethodChannel managed attachments', () {
    const channel = MethodChannel('org.ruhenheim.himemo/cloudkit');
    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null),
    );

    test('uses managed actions and maps CAS revision metadata', () async {
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            return switch (call.method) {
              'managedPinAttachment' => {'recordId': 'managed-attachment-a'},
              'managedListAttachments' => [
                {
                  'recordId': 'managed-attachment-a',
                  'contentHash': 'hash',
                  'revision': 'tag',
                  'modifiedAt': '2026-01-01T00:00:00Z',
                  'uploadIds': ['up'],
                  'sizeBytes': 4,
                },
              ],
              'managedClaimDeleteAttachment' => {'deleted': true},
              _ => true,
            };
          });
      final transport = MethodChannelICloudSyncTransport();
      final id = await transport.pinAttachmentObject(
        contentHash: 'hash',
        uploadId: 'up',
        encodedPayload: 'cipher',
        type: 'file',
        label: 'name',
        sizeBytes: 4,
      );
      final object = (await transport.listManagedAttachmentObjects()).single;
      expect(id, object.id);
      expect(object.contentHash, 'hash');
      expect(object.revision, 'tag');
      expect(object.uploadIds, {'up'});
      expect(await transport.claimAndDeleteAttachmentObject(object), isTrue);
      expect(calls.map((call) => call.method), [
        'managedPinAttachment',
        'managedListAttachments',
        'managedClaimDeleteAttachment',
      ]);
      expect((calls.first.arguments as Map)['contentHash'], 'hash');
    });
  });
}
