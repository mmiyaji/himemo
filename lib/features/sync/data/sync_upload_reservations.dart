import 'dart:convert';

import '../../security/data/secure_key_value_store.dart';
import '../../security/data/storage_serial_executor.dart';

/// Keeps uncertain publications reserved across process restarts. Unknown
/// outcomes are never expired just because a device was offline for a long time.
class SyncUploadReservations {
  SyncUploadReservations(this.storageKey, {SecureKeyValueStore? store})
    : _store = store ?? PreferencesKeyValueStore();
  final String storageKey;
  final SecureKeyValueStore _store;

  Future<Map<String, String?>> read() async {
    final raw = await _store.read(storageKey);
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map ||
          decoded.entries.any(
            (e) =>
                e.key is! String ||
                e.key.toString().isEmpty ||
                (e.value != null && e.value is! String),
          )) {
        return {};
      }
      return Map<String, String?>.from(decoded);
    } on FormatException {
      // Holds live in server object metadata. Forgetting a damaged local hint
      // cannot release them; publication receipts still recover proven commits.
      return {};
    }
  }

  Future<void> start(String uploadId) =>
      _update((items) => items[uploadId] = null);
  Future<void> published(String uploadId, String bundleId) =>
      _update((items) => items[uploadId] = bundleId);
  Future<void> finish(String uploadId) =>
      _update((items) => items.remove(uploadId));

  Future<void> _update(void Function(Map<String, String?>) change) =>
      StorageSerialExecutor.run(_store, storageKey, () async {
        final items = await read();
        change(items);
        final encoded = jsonEncode(items);
        await _store.write(storageKey, encoded);
        if (await _store.read(storageKey) != encoded) {
          throw StateError('Upload reservation persistence failed.');
        }
      });
}
