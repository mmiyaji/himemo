import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_upload_receipt_cache.dart';

void main() {
  test(
    'batch receipt cache preserves negative entries and independent copies',
    () async {
      final store = MemorySecureKeyValueStore();
      final cache = SyncUploadReceiptCache('receipts', store: store);
      await cache.writeBundle('previous', {'old-token': 'old-publication'});
      final updates = <String, Map<String, String>>{
        'empty': {},
        'published': {'token': 'publication'},
      };
      final writing = cache.writeBundles(updates);
      updates['published']!['token'] = 'mutated-after-call';
      await writing;
      final result = await cache.readBundles();
      expect(result, {
        'previous': {'old-token': 'old-publication'},
        'empty': <String, String>{},
        'published': {'token': 'publication'},
      });
      result['published']!['token'] = 'mutated-read';
      expect(await cache.readBundle('published'), {'token': 'publication'});
    },
  );

  test(
    'receipt cache distinguishes missing and known empty after restart',
    () async {
      final store = MemorySecureKeyValueStore();
      final cache = SyncUploadReceiptCache('receipts', store: store);
      expect(await cache.readBundle('unknown'), isNull);
      await cache.writeBundle('empty', {});
      await cache.writeBundle('publication', {
        'upload-1': 'published-bundle-1',
      });
      final restarted = SyncUploadReceiptCache('receipts', store: store);
      expect(await restarted.readBundle('empty'), isEmpty);
      expect(await restarted.readBundle('publication'), {
        'upload-1': 'published-bundle-1',
      });
    },
  );

  test('concurrent receipt writers preserve other bundles and trim complete history', () async {
    final store = MemorySecureKeyValueStore();
    await Future.wait([
      SyncUploadReceiptCache(
        'receipts',
        store: store,
      ).writeBundle('first', {'token-1': 'first'}),
      SyncUploadReceiptCache(
        'receipts',
        store: store,
      ).writeBundle('second', {'token-2': 'second'}),
    ]);
    final cache = SyncUploadReceiptCache('receipts', store: store);
    expect(await cache.readBundle('first'), {'token-1': 'first'});
    expect(await cache.readBundle('second'), {'token-2': 'second'});
    await cache.retainBundles({'second'});
    expect(await cache.readBundle('first'), isNull);
    expect(await cache.readBundle('second'), {'token-2': 'second'});
  });

  test(
    'corrupt entries are cache misses rather than publication proof',
    () async {
      final store = MemorySecureKeyValueStore();
      final cache = SyncUploadReceiptCache('receipts', store: store);
      for (final raw in [
        '{broken',
        '[]',
        '{"version":2,"bundles":{"bad":{"token":"bundle"}}}',
        '{"version":1,"bundles":{"bad":{"token":42}}}',
        '{"version":1,"bundles":{"bad":{"":"bundle"}}}',
      ]) {
        await store.write('receipts', raw);
        expect(await cache.readBundle('bad'), isNull);
        await cache.writeBundle('valid', {});
        expect(await cache.readBundle('valid'), isEmpty);
      }
      await store.write(
        'receipts',
        '{"version":1,"bundles":{"bad":{"token":null},"good":{}}}',
      );
      expect(await cache.readBundle('bad'), isNull);
      expect(await cache.readBundle('good'), isEmpty);
    },
  );

  test(
    'receipt cache confirms persistence and surfaces storage errors',
    () async {
      final cache = SyncUploadReceiptCache('receipts', store: _NoWriteStore());
      await expectLater(cache.writeBundle('bundle', {}), throwsStateError);
    },
  );
}

class _NoWriteStore extends MemorySecureKeyValueStore {
  @override
  Future<void> write(String key, String value) async {}
}
