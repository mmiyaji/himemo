import 'dart:convert';

import '../../security/data/secure_key_value_store.dart';
import '../../security/data/storage_serial_executor.dart';

/// Caches publication metadata extracted from successfully decrypted immutable
/// bundles. An empty entry is meaningful: that bundle contains no receipts.
/// No keys, attachment bytes or note contents are stored here.
class SyncUploadReceiptCache {
  SyncUploadReceiptCache(this.storageKey, {SecureKeyValueStore? store})
    : _store = store ?? PreferencesKeyValueStore();

  final String storageKey;
  final SecureKeyValueStore _store;

  Future<Map<String, String>?> readBundle(String bundleId) async {
    final receipts = (await readBundles())[bundleId];
    return receipts == null ? null : Map<String, String>.from(receipts);
  }

  /// Read once per history scan rather than parsing the whole cache per bundle.
  Future<Map<String, Map<String, String>>> readBundles() async => {
    for (final entry in (await _read()).entries)
      entry.key: Map<String, String>.from(entry.value),
  };

  Future<void> writeBundle(String bundleId, Map<String, String> receipts) =>
      writeBundles({bundleId: receipts});

  /// Merge a scan's new entries in one persisted read/modify/write operation.
  Future<void> writeBundles(Map<String, Map<String, String>> updates) {
    final copy = <String, Map<String, String>>{};
    for (final entry in updates.entries) {
      if (entry.key.isEmpty ||
          entry.value.entries.any((e) => e.key.isEmpty || e.value.isEmpty)) {
        throw ArgumentError('Receipt cache identities must not be empty.');
      }
      copy[entry.key] = Map<String, String>.from(entry.value);
    }
    return _update((bundles) => bundles.addAll(copy));
  }

  /// Call only with a complete history listing. Removed bundles no longer need
  /// a cache entry; any surviving checkpoint retains its own publication proof.
  Future<void> retainBundles(Set<String> liveIds) => _update(
    (bundles) => bundles.removeWhere((id, _) => !liveIds.contains(id)),
  );

  Future<Map<String, Map<String, String>>> _read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return {};
    Object? decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      return {};
    }
    if (decoded is! Map || decoded['version'] != 1) return {};
    final entries = decoded['bundles'];
    if (entries is! Map) return {};
    final result = <String, Map<String, String>>{};
    for (final entry in entries.entries) {
      final id = entry.key;
      final receipts = entry.value;
      if (id is! String || id.isEmpty || receipts is! Map) continue;
      if (receipts.entries.any(
        (e) =>
            e.key is! String ||
            (e.key as String).isEmpty ||
            e.value is! String ||
            (e.value as String).isEmpty,
      )) {
        continue;
      }
      result[id] = Map<String, String>.from(receipts);
    }
    return result;
  }

  Future<void> _update(
    void Function(Map<String, Map<String, String>>) change,
  ) => StorageSerialExecutor.run(_store, storageKey, () async {
    final bundles = await _read();
    change(bundles);
    final encoded = jsonEncode({'version': 1, 'bundles': bundles});
    await _store.write(storageKey, encoded);
    if (await _store.read(storageKey) != encoded) {
      throw StateError('Upload receipt cache persistence failed.');
    }
  });
}
