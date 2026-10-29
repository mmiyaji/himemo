import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';

void main() {
  test(
    'readExisting does not generate or persist a missing master key',
    () async {
      final store = MemorySecureKeyValueStore();
      var factoryCalls = 0;
      final service = MasterKeyService(
        secureStore: store,
        keyFactory: () {
          factoryCalls++;
          return List<int>.filled(32, 7);
        },
      );

      expect(await service.readExisting(), isNull);
      expect(factoryCalls, 0);
      expect(await store.read('security.master_key.v1'), isNull);
    },
  );

  test('readExisting reads a valid existing AES-256 key', () async {
    final store = MemorySecureKeyValueStore();
    final keyBytes = List<int>.generate(32, (index) => index);
    await store.write('security.master_key.v1', base64Encode(keyBytes));
    final service = MasterKeyService(
      secureStore: store,
      keyFactory: () => List<int>.filled(32, 8),
    );

    expect(await (await service.readExisting())!.extractBytes(), keyBytes);
    expect(await store.read('security.master_key.v1'), base64Encode(keyBytes));
  });
}
