import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/sync_v2_admin_store.dart';

void main() {
  test('admin passphrase wraps key, wrong password fails, recovery binds generation', () async {
    final storage = MemorySecureKeyValueStore();
    final store = SyncV2AdminStore(
      storage,
      EncryptionService(),
      generationId: 'generation',
    );
    final key = SecretKey(List.filled(32, 53));
    await store.configure(adminKey: key, password: '123456');
    final persisted = (await storage.read(store.storageKey))!;
    expect(persisted, isNot(contains(base64Encode(List.filled(32, 53)))));
    expect(persisted, isNot(contains('123456')));
    expect(await store.unlock('incorrect long password'), isNull);
    final unlocked = (await store.unlock('123456'))!;
    expect(await unlocked.extractBytes(), await key.extractBytes());
    unlocked.destroy();
    final code = await store.encodeRecoveryCode(key);
    final recovered = store.decodeRecoveryCode(code);
    expect(await recovered.extractBytes(), await key.extractBytes());
    recovered.destroy();
    expect(
      () => SyncV2AdminStore(
        storage,
        EncryptionService(),
        generationId: 'other',
      ).decodeRecoveryCode(code),
      throwsFormatException,
    );
    expect(() => store.decodeRecoveryCode('$code='), throwsFormatException);
    await expectLater(
      store.configure(adminKey: key, password: 'short'),
      throwsArgumentError,
    );
    key.destroy();
  }, timeout: const Timeout(Duration(minutes: 2)));
}
