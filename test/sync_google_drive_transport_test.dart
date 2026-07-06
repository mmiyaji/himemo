import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';

void main() {
  group('RemoteSyncBundleStatus', () {
    test('treats legacy and explicit full bundles as full snapshots', () {
      RemoteSyncBundleStatus status(String? kind) => RemoteSyncBundleStatus(
        fileId: 'id-${kind ?? 'null'}',
        fileName: 'bundle.enc',
        bundleKind: kind,
      );

      expect(status(null).isFullBundle, isTrue);
      expect(status('').isFullBundle, isTrue);
      expect(status(SyncBundleKind.full).isFullBundle, isTrue);
      expect(status(SyncBundleKind.delta).isFullBundle, isFalse);
    });
  });

  group('InMemoryGoogleDriveSyncTransport', () {
    test(
      'stores bundle history and attachments without writing backup codes',
      () async {
        final transport = InMemoryGoogleDriveSyncTransport(
          uploadDelay: Duration.zero,
        );
        final hash = 'hash-${DateTime.now().microsecondsSinceEpoch}';

        expect(await transport.fetchLatestBundleStatus(), isNull);
        expect(await transport.listBundleHistory(), isEmpty);
        expect(await transport.downloadLatestBundle(), isNull);
        expect(await transport.downloadBundleByFileId('missing'), isNull);
        expect(await transport.fetchSyncKeyBackupCode(), isNull);

        final full = await transport.uploadBundle(
          encodedPayload: 'payload-full',
          deviceId: 'device-a',
          noteCount: 2,
          attachmentCount: 1,
        );
        final delta = await transport.uploadBundle(
          encodedPayload: 'payload-delta',
          deviceId: 'device-b',
          noteCount: 1,
          attachmentCount: 0,
          bundleKind: SyncBundleKind.delta,
        );

        expect(
          (await transport.fetchLatestBundleStatus())?.fileId,
          delta.fileId,
        );
        expect(
          (await transport.listBundleHistory(
            limit: 1,
          )).map((status) => status.fileId),
          [delta.fileId],
        );
        expect(
          (await transport.downloadLatestBundle())?.encodedPayload,
          'payload-delta',
        );
        expect(
          (await transport.downloadBundleByFileId(full.fileId))?.encodedPayload,
          'payload-full',
        );

        await transport.uploadAttachmentObject(
          contentHash: hash,
          encodedPayload: 'first',
          type: 'photo',
          label: 'photo.jpg',
          sizeBytes: 10,
        );
        await transport.uploadAttachmentObject(
          contentHash: hash,
          encodedPayload: 'kept-out',
          type: 'photo',
          label: 'photo.jpg',
          sizeBytes: 20,
          skipExistingCheck: true,
        );
        expect(await transport.downloadAttachmentObject(hash), 'first');
        await transport.uploadAttachmentObject(
          contentHash: hash,
          encodedPayload: 'overwritten',
          type: 'photo',
          label: 'photo.jpg',
          sizeBytes: 30,
        );
        expect(
          await transport.listAttachmentObjectContentHashes(),
          contains(hash),
        );
        expect(await transport.downloadAttachmentObject(hash), 'overwritten');

        final keyStore = GoogleDriveCloudSyncBundleKeyStore(transport);
        await keyStore.writeBackupCode('backup-code');
        expect(await keyStore.readBackupCode(), isNull);
      },
    );

    test('reads and deletes legacy backup codes', () async {
      final transport = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
        legacySyncKeyBackupCode: 'legacy-backup-code',
      );
      final keyStore = GoogleDriveCloudSyncBundleKeyStore(transport);

      expect(await keyStore.readBackupCode(), 'legacy-backup-code');

      await keyStore.deleteBackupCode();

      expect(await keyStore.readBackupCode(), isNull);
    });

    test(
      'delays uploads when configured and keeps empty history limits stable',
      () async {
        final transport = InMemoryGoogleDriveSyncTransport(
          uploadDelay: const Duration(milliseconds: 1),
        );

        final before = DateTime.now();
        final status = await transport.uploadBundle(
          encodedPayload: '',
          deviceId: 'device-delay',
          noteCount: 0,
          attachmentCount: 0,
        );

        expect(DateTime.now().difference(before), isNot(Duration.zero));
        expect(status.sizeBytes, 0);
        expect(status.bundleKind, SyncBundleKind.full);
        expect(await transport.listBundleHistory(limit: 0), isEmpty);
      },
    );

    test('keeps simulator state isolated per transport instance', () async {
      final first = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );
      final second = InMemoryGoogleDriveSyncTransport(
        uploadDelay: Duration.zero,
      );

      await first.uploadBundle(
        encodedPayload: 'first-payload',
        deviceId: 'device-a',
        noteCount: 1,
        attachmentCount: 0,
      );
      await first.uploadAttachmentObject(
        contentHash: 'hash-isolated',
        encodedPayload: 'attachment',
        type: 'file',
        label: 'file.bin',
        sizeBytes: 10,
      );
      expect(await second.fetchLatestBundleStatus(), isNull);
      expect(await second.listBundleHistory(), isEmpty);
      expect(await second.downloadAttachmentObject('hash-isolated'), isNull);
      expect(
        await GoogleDriveCloudSyncBundleKeyStore(second).readBackupCode(),
        isNull,
      );
    });
  });

  group('GoogleDriveAuthConfig', () {
    test('normalizes whitespace and formats configuration errors', () {
      const blank = GoogleDriveAuthConfig(
        clientId: '  ',
        serverClientId: '\n\t',
      );
      const configured = GoogleDriveAuthConfig(
        clientId: ' client ',
        serverClientId: ' server ',
      );

      expect(blank.normalizedClientId, isNull);
      expect(blank.normalizedServerClientId, isNull);
      expect(configured.normalizedClientId, 'client');
      expect(configured.normalizedServerClientId, 'server');
      expect(
        const GoogleDriveAuthConfigurationException('message').toString(),
        'message',
      );
      expect(
        const GoogleDriveAuthConfigurationException(
          'message',
          'detail',
        ).toString(),
        'message (detail)',
      );
      expect(
        const GoogleDriveSyncException('sync failed').toString(),
        'sync failed',
      );
      final rateLimited = GoogleDriveSyncException(
        'limited',
        statusCode: 429,
        retryAfter: const Duration(minutes: 2),
        isRateLimited: true,
        details: const {'reason': 'rateLimitExceeded'},
      );
      expect(rateLimited.toString(), 'limited');
      expect(rateLimited.statusCode, 429);
      expect(rateLimited.retryAfter, const Duration(minutes: 2));
      expect(rateLimited.isRateLimited, isTrue);
      expect(rateLimited.details, isA<Map>());
    });
  });
}
