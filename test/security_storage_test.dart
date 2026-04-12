import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encrypted_note_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/private_vault_secret_store.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('EncryptedNoteStore', () {
    late Directory tempDirectory;
    late MemorySecureKeyValueStore secureStore;
    late EncryptionService encryptionService;
    late SharedPreferences prefs;
    late EncryptedNoteStore noteStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      tempDirectory = await Directory.systemTemp.createTemp(
        'himemo-secure-notes-',
      );
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(7));
      noteStore = EncryptedNoteStore(
        encryptionService: encryptionService,
        masterKeyService: MasterKeyService(
          secureStore: secureStore,
          keyFactory: encryptionService.generateKeyBytes,
        ),
        directoryProvider: () async => tempDirectory,
        sharedPreferencesProvider: () async => prefs,
      );
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('migrates plaintext legacy notes into encrypted storage', () async {
      final notes = [
        NoteEntry(
          id: 'n1',
          vaultId: 'everyday',
          title: 'Encrypted title',
          body: 'Encrypted body',
          createdAt: DateTime(2026, 4, 12, 10, 0),
        ),
      ];
      await prefs.setString(
        'notes.entries.v1',
        jsonEncode(notes.map((entry) => entry.toJson()).toList()),
      );

      final restored = await noteStore.load(fallbackNotes: const []);

      expect(restored, notes);
      expect(prefs.getString('notes.entries.v1'), isNull);
      final encryptedFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}notes.entries.enc.v1',
      );
      expect(await encryptedFile.exists(), isTrue);
      final rawPayload = await encryptedFile.readAsString();
      expect(rawPayload.contains('Encrypted body'), isFalse);
    });

    test('persists and restores notes without plaintext leakage', () async {
      final notes = [
        NoteEntry(
          id: 'n9',
          vaultId: 'private',
          title: 'Vault plan',
          body: 'Only encrypted payload should be stored.',
          createdAt: DateTime(2026, 4, 12, 11, 30),
          isPinned: true,
        ),
      ];

      await noteStore.save(notes);
      final restored = await noteStore.load(fallbackNotes: const []);

      expect(restored, notes);
      final encryptedFile = File(
        '${tempDirectory.path}${Platform.pathSeparator}notes.entries.enc.v1',
      );
      final rawPayload = await encryptedFile.readAsString();
      expect(rawPayload.contains('Vault plan'), isFalse);
      expect(rawPayload.contains('Only encrypted payload should be stored.'), isFalse);
    });
  });

  group('PrivateVaultSecretStore', () {
    late MemorySecureKeyValueStore secureStore;
    late EncryptionService encryptionService;
    late SharedPreferences prefs;
    late PrivateVaultSecretStore secretStore;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      prefs = await SharedPreferences.getInstance();
      secureStore = MemorySecureKeyValueStore();
      encryptionService = EncryptionService(random: Random(9));
      secretStore = PrivateVaultSecretStore(
        secureStore: secureStore,
        encryptionService: encryptionService,
        sharedPreferencesProvider: () async => prefs,
      );
    });

    test('stores and verifies private vault secret in secure storage', () async {
      expect(await secretStore.hasSecret(), isFalse);

      await secretStore.configure('top-secret');

      expect(await secretStore.hasSecret(), isTrue);
      expect(await secretStore.verify('top-secret'), isTrue);
      expect(await secretStore.verify('not-it'), isFalse);
      final stored = await secureStore.read('security.private_vault.verifier.v1');
      expect(stored, isNotNull);
      expect(stored!.contains('top-secret'), isFalse);
    });

    test('migrates legacy verifier out of shared preferences', () async {
      final salt = encryptionService.generateSalt();
      final verifier = await encryptionService.deriveSecretVerifier(
        secret: 'legacy-secret',
        salt: salt,
      );
      await prefs.setString('security.private_vault_salt', base64Encode(salt));
      await prefs.setString('security.private_vault_digest', verifier);

      expect(await secretStore.hasSecret(), isTrue);
      expect(await secretStore.verify('legacy-secret'), isTrue);
      expect(prefs.getString('security.private_vault_salt'), isNull);
      expect(prefs.getString('security.private_vault_digest'), isNull);
    });
  });
}
