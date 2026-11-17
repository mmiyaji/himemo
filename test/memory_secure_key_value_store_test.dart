import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';

void main() {
  test(
    'clearing a memory store drops all session values and permits reuse',
    () async {
      final store = MemorySecureKeyValueStore();
      await store.write('sync', 'sync-only-secret');
      await store.write('admin', 'separate-admin-secret');
      store.clear();
      expect(await store.read('sync'), isNull);
      expect(await store.read('admin'), isNull);
      await store.write('sync', 'next-session');
      expect(await store.read('sync'), 'next-session');
      expect(await store.read('admin'), isNull);
    },
  );
}
