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
    test('stores bundle history, attachments, and backup codes', () async {
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

      expect((await transport.fetchLatestBundleStatus())?.fileId, delta.fileId);
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
      expect(await keyStore.readBackupCode(), 'backup-code');
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
    });
  });
}
