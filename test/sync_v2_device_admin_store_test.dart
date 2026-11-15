import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/sync_v2_device_admin_store.dart';

void main() {
  test('saves and restores a device administrator key by identity', () async {
    final backing = MemorySecureKeyValueStore();
    final store = SyncV2DeviceAdminStore(backing);
    final key = SecretKey(List<int>.generate(32, (index) => index));
    await store.save(
      accountId: 'account-a',
      generationId: 'generation-1',
      adminKey: key,
    );

    final restored = await store.read(
      accountId: 'account-a',
      generationId: 'generation-1',
    );
    expect(restored, isNotNull);
    expect(await restored!.extractBytes(), await key.extractBytes());
    restored.destroy();

    expect(
      await store.read(accountId: 'account-b', generationId: 'generation-1'),
      isNull,
    );
    expect(
      await store.read(accountId: 'account-a', generationId: 'generation-2'),
      isNull,
    );
    key.destroy();
  });

  test('rejects malformed schema, identity binding, and key lengths', () async {
    final backing = MemorySecureKeyValueStore();
    final store = SyncV2DeviceAdminStore(backing);
    final storageKey = store.storageKey(
      installationId: 'test-installation',
      accountId: 'account',
      generationId: 'generation',
    );
    final valid = {
      'version': 1,
      'installation': 'test-installation',
      'account': 'account',
      'generation': 'generation',
      'key': base64Encode(List<int>.filled(32, 4)),
    };
    for (final invalid in [
      {...valid, 'extra': true},
      {...valid, 'version': 2},
      {...valid, 'installation': 'other-installation'},
      {...valid, 'account': 'other'},
      {...valid, 'key': base64Encode(List<int>.filled(31, 4))},
      {...valid, 'key': 'not-base64'},
    ]) {
      await backing.write(storageKey, jsonEncode(invalid));
      await expectLater(
        store.read(accountId: 'account', generationId: 'generation'),
        throwsFormatException,
      );
    }
    await backing.write(storageKey, jsonEncode({...valid}..remove('key')));
    await expectLater(
      store.read(accountId: 'account', generationId: 'generation'),
      throwsFormatException,
    );
    await expectLater(
      store.save(
        accountId: 'account',
        generationId: 'generation',
        adminKey: SecretKey(List<int>.filled(31, 0)),
      ),
      throwsFormatException,
    );
  });

  test(
    'installation changes isolate old keys and deletion is install scoped',
    () async {
      final backing = MemorySecureKeyValueStore();
      var installation = 'installation-a';
      final calls = <bool>[];
      final store = SyncV2DeviceAdminStore(
        backing,
        installationId: (create) async {
          calls.add(create);
          return installation;
        },
      );
      final key = SecretKey(List<int>.filled(32, 9));
      await store.save(
        accountId: 'account',
        generationId: 'generation',
        adminKey: key,
      );
      installation = 'installation-b';
      expect(
        await store.read(accountId: 'account', generationId: 'generation'),
        isNull,
      );
      await store.delete(accountId: 'account', generationId: 'generation');
      installation = 'installation-a';
      final restored = await store.read(
        accountId: 'account',
        generationId: 'generation',
      );
      expect(await restored!.extractBytes(), await key.extractBytes());
      restored.destroy();
      await store.delete(accountId: 'account', generationId: 'generation');
      expect(
        await store.read(accountId: 'account', generationId: 'generation'),
        isNull,
      );
      expect(calls.first, isTrue);
      expect(calls.skip(1).every((create) => !create), isTrue);
      key.destroy();
    },
  );

  test('read without an installation id does not create one', () async {
    var createCalls = 0;
    final store = SyncV2DeviceAdminStore(
      MemorySecureKeyValueStore(),
      installationId: (create) async {
        if (create) createCalls++;
        return null;
      },
    );
    expect(
      await store.read(accountId: 'account', generationId: 'generation'),
      isNull,
    );
    await store.delete(accountId: 'account', generationId: 'generation');
    expect(createCalls, 0);
    await expectLater(
      store.save(
        accountId: 'account',
        generationId: 'generation',
        adminKey: SecretKey(List<int>.filled(32, 1)),
      ),
      throwsA(isA<StateError>()),
    );
    expect(createCalls, 1);
  });

  test('propagates secure-store write failures', () async {
    final store = SyncV2DeviceAdminStore(_FailingWriteStore());
    await expectLater(
      store.save(
        accountId: 'account',
        generationId: 'generation',
        adminKey: SecretKey(List<int>.filled(32, 5)),
      ),
      throwsA(isA<StateError>()),
    );
  });

  test('propagates secure-store readback failures', () async {
    final store = SyncV2DeviceAdminStore(_FailingReadStore());
    await expectLater(
      store.save(
        accountId: 'account',
        generationId: 'generation',
        adminKey: SecretKey(List<int>.filled(32, 5)),
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _FailingWriteStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => null;

  @override
  Future<void> write(String key, String value) async {
    throw StateError('write failed');
  }

  @override
  Future<void> delete(String key) async {}
}

class _FailingReadStore implements SecureKeyValueStore {
  @override
  Future<String?> read(String key) async => throw StateError('read failed');

  @override
  Future<void> write(String key, String value) async {}

  @override
  Future<void> delete(String key) async {}
}
