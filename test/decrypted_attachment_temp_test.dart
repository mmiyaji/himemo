import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('decrypted attachment temporary files', () {
    late Directory testRoot;
    late Directory supportDirectory;
    late Directory osTemporaryDirectory;
    late EncryptedAttachmentStore store;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      testRoot = await Directory.systemTemp.createTemp(
        'himemo-decrypted-attachment-',
      );
      supportDirectory = Directory(path.join(testRoot.path, 'support'));
      osTemporaryDirectory = Directory(path.join(testRoot.path, 'os-temp'));
      await supportDirectory.create(recursive: true);
      await osTemporaryDirectory.create(recursive: true);

      final encryptionService = EncryptionService(random: Random(71));
      store = EncryptedAttachmentStore(
        encryptionService: encryptionService,
        masterKeyService: MasterKeyService(
          secureStore: MemorySecureKeyValueStore(),
          keyFactory: encryptionService.generateKeyBytes,
        ),
        directoryProvider: () async => supportDirectory,
        temporaryDirectoryProvider: () async => osTemporaryDirectory,
        sharedPreferencesProvider: SharedPreferences.getInstance,
      );
    });

    tearDown(() async {
      if (await testRoot.exists()) {
        await testRoot.delete(recursive: true);
      }
    });

    test('materializes decrypted bytes under the OS temporary path', () async {
      final materializedPath = await store.materializeDecryptedBytes(
        const <int>[1, 2, 3, 4],
        type: AttachmentType.file,
        preferredFileName: 'report.txt',
      );

      expect(materializedPath, isNotNull);
      expect(
        path.isWithin(osTemporaryDirectory.path, materializedPath!),
        isTrue,
      );
      expect(path.isWithin(supportDirectory.path, materializedPath), isFalse);
      expect(
        path.dirname(materializedPath),
        path.join(osTemporaryDirectory.path, 'himemo', 'attachments', 'tmp'),
      );
      expect(await File(materializedPath).readAsBytes(), const <int>[
        1,
        2,
        3,
        4,
      ]);
    });

    test('immediate cleanup removes the file and its cleanup marker', () async {
      final materializedPath = (await store.materializeDecryptedBytes(
        const <int>[5, 6, 7],
        type: AttachmentType.audio,
        preferredFileName: 'voice.m4a',
      ))!;
      await store.markMaterializedFileForCleanup(
        materializedPath,
        deleteAfter: DateTime.utc(2099),
      );
      final marker = File('$materializedPath.himemo-delete-after');
      expect(await marker.exists(), isTrue);

      await store.deleteMaterializedFile(materializedPath);

      expect(await File(materializedPath).exists(), isFalse);
      expect(await marker.exists(), isFalse);
    });

    test(
      'orphan sweep deletes stale unmarked files but keeps fresh ones',
      () async {
        final now = DateTime.utc(2026, 7, 10, 12);
        final stalePath = (await store.materializeDecryptedBytes(
          const <int>[8, 9],
          type: AttachmentType.video,
          preferredFileName: 'stale.mp4',
        ))!;
        final freshPath = (await store.materializeDecryptedBytes(
          const <int>[10, 11],
          type: AttachmentType.photo,
          preferredFileName: 'fresh.jpg',
        ))!;
        await File(
          stalePath,
        ).setLastModified(now.subtract(const Duration(hours: 2)));
        await File(
          freshPath,
        ).setLastModified(now.subtract(const Duration(minutes: 30)));

        expect(await store.cleanupExpiredMaterializedFiles(now: now), 1);
        expect(await File(stalePath).exists(), isFalse);
        expect(await File(freshPath).exists(), isTrue);
      },
    );
  });
}
