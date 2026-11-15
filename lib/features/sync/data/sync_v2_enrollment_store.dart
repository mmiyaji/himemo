import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:crypto/crypto.dart' show sha256;

import '../../security/data/secure_key_value_store.dart';
import '../../security/data/storage_serial_executor.dart';

/// The caller owns [syncKey] and destroys it when the session ends.
typedef SyncV2Enrollment = ({
  String accountId,
  String generationId,
  SecretKey syncKey,
});

typedef SyncV2PendingRegistration = ({
  String accountId,
  String generationId,
  SecretKey syncKey,
  String encryptedProof,
});

/// Stores one explicitly enrolled iCloud generation on this device.
class SyncV2EnrollmentStore {
  SyncV2EnrollmentStore(this._store);

  final SecureKeyValueStore _store;
  static const _pendingKey = 'security.icloud_sync_v2.pending_registration.v1';
  static const _storageKey = 'security.icloud_sync_v2.enrollment.v1';
  static const _proofKey = 'security.icloud_sync_v2.verified_proof.v1';
  static final _generationPattern = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');

  Future<String> _proofBinding(SyncV2Enrollment enrollment) async =>
      jsonEncode([
        enrollment.accountId,
        enrollment.generationId,
        sha256.convert(await enrollment.syncKey.extractBytes()).toString(),
      ]);

  Future<bool> _matches(SyncV2Enrollment left, SyncV2Enrollment right) async {
    if (left.accountId != right.accountId ||
        left.generationId != right.generationId) {
      return false;
    }
    final a = await left.syncKey.extractBytes();
    final b = await right.syncKey.extractBytes();
    if (a.length != b.length) return false;
    var different = 0;
    for (var i = 0; i < a.length; i++) {
      different |= a[i] ^ b[i];
    }
    return different == 0;
  }

  /// Cache only an authenticated encrypted manifest after durable enrollment.
  Future<void> cacheVerifiedProof(SyncV2Enrollment enrollment, String proof) =>
      StorageSerialExecutor.run(_store, _storageKey, () async {
        if (proof.isEmpty || utf8.encode(proof).length > 65536) {
          throw const FormatException('Invalid registration proof');
        }
        final finalEnrollment = await readForAccount(enrollment.accountId);
        if (finalEnrollment == null) throw StateError('No verified enrollment');
        try {
          if (!await _matches(finalEnrollment, enrollment)) {
            throw StateError('Enrollment mismatch');
          }
          final encoded = jsonEncode({
            'binding': await _proofBinding(finalEnrollment),
            'proof': proof,
          });
          await _store.write(_proofKey, encoded);
          if (await _store.read(_proofKey) != encoded) {
            throw StateError('Could not cache registration proof');
          }
        } finally {
          finalEnrollment.syncKey.destroy();
        }
      });

  Future<String?> readCachedProof(String accountId) async {
    final enrollment = await readForAccount(accountId);
    if (enrollment == null) return null;
    final binding = await _proofBinding(enrollment);
    enrollment.syncKey.destroy();
    final raw = await _store.read(_proofKey);
    if (raw == null) return null;
    final value = jsonDecode(raw);
    if (value is! Map ||
        value.length != 2 ||
        value['binding'] != binding ||
        value['proof'] is! String ||
        (value['proof'] as String).isEmpty ||
        utf8.encode(value['proof'] as String).length > 65536) {
      throw const FormatException('Invalid cached registration proof');
    }
    return value['proof'] as String;
  }

  /// Caller must first authenticate the winning cloud proof. No cloud keys are
  /// discarded: only the exact same-account pending local attempt is removed.
  Future<void> cleanupPendingAfterVerifiedRecovery(SyncV2Enrollment verified) =>
      StorageSerialExecutor.run(_store, _storageKey, () async {
        final finalEnrollment = await readForAccount(verified.accountId);
        if (finalEnrollment == null) throw StateError('No verified enrollment');
        try {
          if (!await _matches(finalEnrollment, verified)) {
            throw StateError('Enrollment mismatch');
          }
        } finally {
          finalEnrollment.syncKey.destroy();
        }
        final raw = await _store.read(_pendingKey);
        if (raw == null) return;
        final pending = await readPendingRegistration();
        if (pending == null) return;
        try {
          if (pending.accountId != verified.accountId) return;
          if (await _store.read(_pendingKey) != raw) {
            throw StateError('Pending registration changed');
          }
          await _store.delete(_pendingKey);
          if (await _store.read(_pendingKey) != null) {
            throw StateError('Could not clear pending registration');
          }
        } finally {
          pending.syncKey.destroy();
        }
      });

  Future<SyncV2Enrollment?> readForAccount(String currentAccountId) async {
    final raw = await _store.read(_storageKey);
    if (raw == null) return null;
    final enrollment = _decode(raw);
    if (enrollment.accountId != currentAccountId) {
      enrollment.syncKey.destroy();
      throw StateError('The current iCloud account is not enrolled');
    }
    return enrollment;
  }

  /// Persist only after the caller verifies enrollment against the cloud.
  /// Repeating the same enrollment is safe. Replacement requires a separate
  /// flow that deals with the previous generation and its unsent data.
  Future<void> saveVerified(SyncV2Enrollment enrollment) async {
    final key = await enrollment.syncKey.extractBytes();
    if (key.length != 32 ||
        enrollment.accountId.isEmpty ||
        !_generationPattern.hasMatch(enrollment.generationId)) {
      throw const FormatException('Invalid iCloud v2 enrollment');
    }
    final encoded = jsonEncode({
      'version': 1,
      'account': enrollment.accountId,
      'generation': enrollment.generationId,
      'key': base64Encode(key),
    });
    await StorageSerialExecutor.run(_store, _storageKey, () async {
      final existing = await _store.read(_storageKey);
      if (existing == encoded) return;
      if (existing != null) {
        throw StateError('This device already has an iCloud v2 enrollment');
      }
      await _store.write(_storageKey, encoded);
      if (await _store.read(_storageKey) != encoded) {
        throw StateError('Could not persist iCloud v2 enrollment');
      }
    });
  }

  SyncV2Enrollment _decode(String raw) {
    final value = jsonDecode(raw);
    if (value
        case {
          'version': 1,
          'account': final String account,
          'generation': final String generation,
          'key': final String encodedKey,
        }
        when account.isNotEmpty && _generationPattern.hasMatch(generation)) {
      final key = base64Decode(encodedKey);
      if (key.length == 32) {
        return (
          accountId: account,
          generationId: generation,
          syncKey: SecretKey(key),
        );
      }
    }
    throw const FormatException('Invalid stored iCloud v2 enrollment');
  }

  String _encodePending(SyncV2PendingRegistration pending, List<int> key) {
    if (key.length != 32 ||
        pending.accountId.isEmpty ||
        pending.accountId.length > 4096 ||
        !_generationPattern.hasMatch(pending.generationId) ||
        pending.encryptedProof.isEmpty ||
        utf8.encode(pending.encryptedProof).length > 65536) {
      throw const FormatException('Invalid pending registration');
    }
    return jsonEncode({
      'version': 1,
      'account': pending.accountId,
      'generation': pending.generationId,
      'key': base64Encode(key),
      'proof': pending.encryptedProof,
    });
  }

  /// The returned sync key is owned by the caller.
  Future<SyncV2PendingRegistration?> readPendingRegistration() async {
    final raw = await _store.read(_pendingKey);
    if (raw == null) return null;
    if (utf8.encode(raw).length > 100000) {
      throw const FormatException('Pending registration too large');
    }
    final value = jsonDecode(raw);
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['account'] is! String ||
        value['generation'] is! String ||
        value['key'] is! String ||
        value['proof'] is! String) {
      throw const FormatException('Invalid pending registration');
    }
    final bytes = base64Decode(value['key'] as String);
    final pending = (
      accountId: value['account'] as String,
      generationId: value['generation'] as String,
      syncKey: SecretKey(bytes),
      encryptedProof: value['proof'] as String,
    );
    try {
      _encodePending(pending, bytes);
      return pending;
    } catch (_) {
      pending.syncKey.destroy();
      rethrow;
    }
  }

  Future<void> savePendingRegistration(
    SyncV2PendingRegistration pending,
  ) async {
    final encoded = _encodePending(
      pending,
      await pending.syncKey.extractBytes(),
    );
    await StorageSerialExecutor.run(_store, _storageKey, () async {
      final previous = await _store.read(_pendingKey);
      if (previous != null && previous != encoded) {
        throw StateError('A different registration is pending');
      }
      await _store.write(_pendingKey, encoded);
      if (await _store.read(_pendingKey) != encoded) {
        throw StateError('Could not persist pending registration');
      }
    });
  }

  /// Clear only the matching pending record after durable final enrollment.
  Future<void> clearPendingRegistration(
    SyncV2PendingRegistration pending,
  ) async {
    final encoded = _encodePending(
      pending,
      await pending.syncKey.extractBytes(),
    );
    await StorageSerialExecutor.run(_store, _storageKey, () async {
      final finalRaw = await _store.read(_storageKey);
      if (finalRaw == null) throw StateError('No verified enrollment');
      final enrolled = _decode(finalRaw);
      try {
        if (enrolled.accountId != pending.accountId ||
            enrolled.generationId != pending.generationId ||
            base64Encode(await enrolled.syncKey.extractBytes()) !=
                base64Encode(await pending.syncKey.extractBytes())) {
          throw StateError('Pending registration differs from enrollment');
        }
      } finally {
        enrolled.syncKey.destroy();
      }
      final stored = await _store.read(_pendingKey);
      if (stored == null) return;
      if (stored != encoded) {
        throw StateError('A different registration is pending');
      }
      await _store.delete(_pendingKey);
      if (await _store.read(_pendingKey) != null) {
        throw StateError('Could not clear pending registration');
      }
    });
  }
}
