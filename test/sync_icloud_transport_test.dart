import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/icloud_sync_transport.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('InMemoryICloudSyncTransport', () {
    test('reports availability and rejects writes while unavailable', () async {
      final transport = InMemoryICloudSyncTransport(
        availability: ICloudAccountAvailability.temporarilyUnavailable,
      );

      final status = await transport.checkAccountStatus();
      expect(status.isAvailable, isFalse);
      expect(
        status.availability,
        ICloudAccountAvailability.temporarilyUnavailable,
      );
      expect(status.message, contains('not available'));

      await expectLater(
        transport.uploadBundle(
          encodedPayload: 'payload',
          deviceId: 'device-a',
          noteCount: 1,
          attachmentCount: 0,
        ),
        throwsA(
          isA<ICloudSyncException>().having(
            (error) => error.isTemporary,
            'isTemporary',
            isTrue,
          ),
        ),
      );
    });

    test(
      'stores bundle history and downloads by latest or record name',
      () async {
        final transport = InMemoryICloudSyncTransport();

        expect(await transport.fetchLatestBundleStatus(), isNull);
        expect(await transport.downloadLatestBundle(), isNull);
        expect(await transport.downloadBundleByRecordName('missing'), isNull);

        final first = await transport.uploadBundle(
          encodedPayload: 'payload-1',
          deviceId: 'device-a',
          noteCount: 1,
          attachmentCount: 0,
          bundleKind: SyncBundleKind.full,
        );
        final second = await transport.uploadBundle(
          encodedPayload: 'payload-2',
          deviceId: 'device-b',
          noteCount: 2,
          attachmentCount: 3,
          bundleKind: SyncBundleKind.delta,
        );

        expect(
          (await transport.fetchLatestBundleStatus())?.fileId,
          second.fileId,
        );
        expect(
          (await transport.listBundleHistory(limit: 1)).map((s) => s.fileId),
          [second.fileId],
        );
        expect(
          (await transport.downloadLatestBundle())?.encodedPayload,
          'payload-2',
        );
        expect(
          (await transport.downloadBundleByRecordName(
            first.fileId,
          ))?.encodedPayload,
          'payload-1',
        );
      },
    );

    test(
      'handles attachment objects, storage breakdown, and pruning',
      () async {
        final transport = InMemoryICloudSyncTransport();
        await transport.uploadBundle(
          encodedPayload: 'aaa',
          deviceId: 'device-a',
          noteCount: 1,
          attachmentCount: 0,
        );
        await transport.uploadBundle(
          encodedPayload: 'bbbb',
          deviceId: 'device-a',
          noteCount: 1,
          attachmentCount: 0,
        );
        await transport.uploadAttachmentObject(
          contentHash: 'keep',
          encodedPayload: 'old-keep',
          type: 'photo',
          label: 'keep.jpg',
          sizeBytes: 10,
        );
        await transport.uploadAttachmentObject(
          contentHash: 'keep',
          encodedPayload: 'new-keep',
          type: 'photo',
          label: 'keep.jpg',
          sizeBytes: 20,
          skipExistingCheck: true,
        );
        await transport.uploadAttachmentObject(
          contentHash: 'drop',
          encodedPayload: 'drop-payload',
          type: 'file',
          label: 'drop.bin',
          sizeBytes: 30,
        );

        expect(await transport.listAttachmentObjectContentHashes(), {
          'keep',
          'drop',
        });
        expect(await transport.downloadAttachmentObject('keep'), 'old-keep');
        expect(await transport.downloadAttachmentObject('missing'), isNull);

        final before = await transport.fetchStorageBreakdown();
        expect(before.bundleCount, 2);
        expect(before.bundleBytes, 7);
        expect(before.attachmentCount, 2);
        expect(before.attachmentBytes, 40);
        expect(before.totalBytes, 47);

        final pruned = await transport.pruneObsoleteData(
          keepLatest: -1,
          referencedAttachmentHashes: {'keep'},
        );
        expect(pruned.deletedBundleCount, 2);
        expect(pruned.deletedBundleBytes, 7);
        expect(pruned.deletedAttachmentCount, 1);
        expect(pruned.deletedAttachmentBytes, 30);
        expect(pruned.deletedBytes, 37);
        expect(await transport.fetchLatestBundleStatus(), isNull);
        expect(await transport.listAttachmentObjectContentHashes(), {'keep'});
      },
    );
  });

  group('MethodChannelICloudSyncTransport', () {
    const channel = MethodChannel('org.ruhenheim.himemo/cloudkit');

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('maps account status success and missing plugin fallback', () async {
      final transport = MethodChannelICloudSyncTransport();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            expect(call.method, 'cloudKitAccountStatus');
            return {'status': 'restricted', 'message': 'restricted by policy'};
          });

      final restricted = await transport.checkAccountStatus();
      expect(restricted.availability, ICloudAccountAvailability.restricted);
      expect(restricted.message, 'restricted by policy');

      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async {
            throw MissingPluginException();
          });
      final unsupported = await transport.checkAccountStatus();
      expect(unsupported.availability, ICloudAccountAvailability.unsupported);
      expect(unsupported.isAvailable, isFalse);
    });

    test(
      'maps bundle, attachment, storage, and prune method responses',
      () async {
        final calls = <MethodCall>[];
        final transport = MethodChannelICloudSyncTransport();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              switch (call.method) {
                case 'cloudKitFetchLatestBundleStatus':
                  return _statusMap(recordName: 'latest', modifiedAt: '');
                case 'cloudKitListBundleHistory':
                  expect(call.arguments, {'limit': 2});
                  return [
                    _statusMap(
                      recordName: 'newer',
                      modifiedAt: '2026-06-12T00:00:00Z',
                    ),
                    _statusMap(recordName: 'older', modifiedAt: null),
                  ];
                case 'cloudKitUploadBundle':
                  expect(
                    call.arguments,
                    containsPair('bundleKind', SyncBundleKind.delta),
                  );
                  return _statusMap(recordName: 'uploaded');
                case 'cloudKitUploadAttachmentObject':
                  expect(
                    call.arguments,
                    containsPair('skipExistingCheck', true),
                  );
                  return {'ok': true};
                case 'cloudKitListAttachmentHashes':
                  return ['hash-a', '', 12, 'hash-b'];
                case 'cloudKitDownloadAttachmentObject':
                  expect(call.arguments, {'contentHash': 'hash-a'});
                  return {'encodedPayload': 'attachment-payload'};
                case 'cloudKitDownloadLatestBundle':
                  return {
                    'status': _statusMap(recordName: 'download-latest'),
                    'encodedPayload': 'latest-payload',
                  };
                case 'cloudKitDownloadBundle':
                  expect(call.arguments, {'recordName': 'download-one'});
                  return {
                    'status': _statusMap(recordName: 'download-one'),
                    'encodedPayload': null,
                  };
                case 'cloudKitStorageBreakdown':
                  return {
                    'bundleCount': '2',
                    'bundleBytes': 12.8,
                    'attachmentCount': null,
                    'attachmentBytes': '34',
                  };
                case 'cloudKitPruneObsoleteData':
                  expect(call.arguments, {
                    'keepLatest': 3,
                    'referencedAttachmentHashes': ['a', 'z'],
                  });
                  return {
                    'deletedBundleCount': '1',
                    'deletedBundleBytes': 20.2,
                    'deletedAttachmentCount': 3,
                    'deletedAttachmentBytes': '40',
                  };
              }
              fail('Unexpected method ${call.method}');
            });

        expect((await transport.fetchLatestBundleStatus())?.fileId, 'latest');
        expect(
          (await transport.listBundleHistory(limit: 2)).map((s) => s.fileId),
          ['newer', 'older'],
        );
        expect(
          (await transport.uploadBundle(
            encodedPayload: 'payload',
            deviceId: 'device-a',
            noteCount: 1,
            attachmentCount: 2,
            bundleKind: SyncBundleKind.delta,
          )).fileId,
          'uploaded',
        );
        await transport.uploadAttachmentObject(
          contentHash: 'hash-a',
          encodedPayload: 'payload',
          type: 'photo',
          label: 'photo.jpg',
          sizeBytes: 42,
          skipExistingCheck: true,
        );
        expect(await transport.listAttachmentObjectContentHashes(), {
          'hash-a',
          'hash-b',
        });
        expect(
          await transport.downloadAttachmentObject('hash-a'),
          'attachment-payload',
        );
        expect(
          (await transport.downloadLatestBundle())?.encodedPayload,
          'latest-payload',
        );
        final downloaded = await transport.downloadBundleByRecordName(
          'download-one',
        );
        expect(downloaded?.status.fileId, 'download-one');
        expect(downloaded?.encodedPayload, '');

        final storage = await transport.fetchStorageBreakdown();
        expect(storage.bundleCount, 2);
        expect(storage.bundleBytes, 12);
        expect(storage.attachmentCount, 0);
        expect(storage.attachmentBytes, 34);

        final pruned = await transport.pruneObsoleteData(
          keepLatest: 3,
          referencedAttachmentHashes: {'z', 'a'},
        );
        expect(pruned.deletedBundleCount, 1);
        expect(pruned.deletedBundleBytes, 20);
        expect(pruned.deletedAttachmentCount, 3);
        expect(pruned.deletedAttachmentBytes, 40);
        expect(
          calls.map((call) => call.method),
          contains('cloudKitPruneObsoleteData'),
        );
      },
    );

    test('maps null responses and non-temporary platform errors', () async {
      final transport = MethodChannelICloudSyncTransport();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            switch (call.method) {
              case 'cloudKitFetchLatestBundleStatus':
              case 'cloudKitDownloadAttachmentObject':
              case 'cloudKitDownloadLatestBundle':
              case 'cloudKitDownloadBundle':
                return null;
              case 'cloudKitUploadBundle':
                return null;
              case 'cloudKitStorageBreakdown':
                return null;
              case 'cloudKitPruneObsoleteData':
                throw PlatformException(
                  code: 'failed',
                  message: 'Permanent failure',
                  details: {'message': 'Permanent CloudKit failure'},
                );
            }
            return const <dynamic>[];
          });

      expect(await transport.fetchLatestBundleStatus(), isNull);
      expect(await transport.downloadAttachmentObject('missing'), isNull);
      expect(await transport.downloadLatestBundle(), isNull);
      expect(await transport.downloadBundleByRecordName('missing'), isNull);
      await expectLater(
        transport.uploadBundle(
          encodedPayload: 'payload',
          deviceId: 'device',
          noteCount: 0,
          attachmentCount: 0,
        ),
        throwsFormatException,
      );
      await expectLater(
        transport.fetchStorageBreakdown(),
        throwsFormatException,
      );
      await expectLater(
        transport.pruneObsoleteData(
          referencedAttachmentHashes: const <String>{},
        ),
        throwsA(
          isA<ICloudSyncException>()
              .having(
                (error) => error.message,
                'message',
                contains('Permanent'),
              )
              .having((error) => error.isTemporary, 'isTemporary', isFalse),
        ),
      );
    });
  });
}

Map<String, dynamic> _statusMap({
  required String recordName,
  String? modifiedAt = '2026-06-12T01:02:03+09:00',
}) {
  return {
    'recordName': recordName,
    'fileName': '$recordName.enc',
    'modifiedAt': modifiedAt,
    'sizeBytes': 123,
    'noteCount': 4,
    'attachmentCount': 5,
    'deviceId': 'device-a',
    'bundleKind': SyncBundleKind.full,
  };
}
