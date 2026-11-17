import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import '../../security/data/encryption_service.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_enrollment_store.dart';
import 'sync_v2_icloud_transport.dart';

class SyncV2CloudDataDeleted implements Exception {
  const SyncV2CloudDataDeleted();
  @override
  String toString() =>
      'Cloud sync data was deleted; explicit recovery is required';
}

class SyncV2RegistrationConflict implements Exception {
  const SyncV2RegistrationConflict();
  @override
  String toString() =>
      'An iCloud generation is already registered; recover the existing generation.';
}

enum SyncV2RegistrationStage {
  account,
  localCheck,
  persistPending,
  readRegistration,
  prepareGeneration,
  publishRegistration,
  readback,
  verifyEnrollment,
}

/// Safe registration diagnostics. This deliberately retains no original
/// exception, message, account/generation identifier, or registration proof.
class SyncV2RegistrationFailure implements Exception {
  const SyncV2RegistrationFailure._(this.stage, this.safeCode);

  final SyncV2RegistrationStage stage;
  final String safeCode;

  @override
  String toString() => 'SyncV2RegistrationFailure(${stage.name}, $safeCode)';
}

abstract interface class SyncV2GenerationRegistrationTransport {
  Future<String> readCurrentAccountId();
  Future<String?> readRegistration();
  Future<void> prepareGeneration(String generationId);

  /// Create-only: identical retries succeed; different proofs must fail.
  Future<void> publishRegistration(String encryptedProof);
}

class SyncV2ICloudGenerationRegistrationTransport
    implements SyncV2GenerationRegistrationTransport {
  SyncV2ICloudGenerationRegistrationTransport(
    this.transport, {
    this.metadataGenerationId = metadataGeneration,
  }) {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,80}$').hasMatch(metadataGenerationId)) {
      throw ArgumentError('Invalid metadata generation');
    }
  }
  final String metadataGenerationId;
  final SyncV2ICloudTransport transport;
  static const metadataGeneration = 'metadata-v1';
  static const registrationId = 'active-generation-v1';

  @override
  Future<String> readCurrentAccountId() => transport.readCurrentAccountId();
  @override
  Future<String?> readRegistration() async {
    try {
      return (await transport.fetchHeader(
        generationId: metadataGenerationId,
        recordId: registrationId,
      )).encryptedHeader;
    } on PlatformException catch (error) {
      if (error.code == '28') throw const SyncV2CloudDataDeleted();
      if (error.code == '11' || error.code == '26') return null;
      rethrow;
    }
  }

  @override
  Future<void> prepareGeneration(String generationId) async {
    if (generationId == metadataGenerationId) {
      throw ArgumentError('Generation collides with metadata');
    }
    await transport.prepareGeneration(generationId);
    await transport.prepareGeneration(metadataGenerationId);
  }

  @override
  Future<void> publishRegistration(String encryptedProof) => transport.publish(
    generationId: metadataGenerationId,
    publication: (
      id: registrationId,
      encryptedHeader: encryptedProof,
      encryptedPayload: null,
    ),
  );
}

class SyncV2PreparedRegistration {
  SyncV2PreparedRegistration._(
    this.accountId,
    this.generationId,
    this.recoveryCode,
    this.encryptedProof,
    this._syncKey,
    this._normalKey,
  );
  final String accountId;
  final String generationId;

  /// Contains the sync key. Back up the administrator key separately.
  final String recoveryCode;
  final String encryptedProof;
  final SecretKey _syncKey;
  final SecretKey _normalKey;
  void destroy() {
    _syncKey.destroy();
    _normalKey.destroy();
  }
}

class SyncV2RegisteredNormalProfile {
  SyncV2RegisteredNormalProfile(this.access);
  final SyncV2UnlockedProfileKey access;
  String get profileId => access.profileId;

  /// Owned by the caller; destroy when the unlock session ends.
  SecretKey get normalKey => access.key;
  void destroy() => access.destroy();
}

class SyncV2GenerationRegistration {
  SyncV2GenerationRegistration(
    this.transport,
    this.enrollments, {
    EncryptionService? encryption,
    this.generationPrefix = 'g',
  }) : _encryption = encryption ?? EncryptionService() {
    if (!RegExp(r'^[a-zA-Z0-9_-]{1,47}$').hasMatch(generationPrefix)) {
      throw ArgumentError('Invalid generation prefix');
    }
  }
  final String generationPrefix;
  final SyncV2GenerationRegistrationTransport transport;
  final SyncV2EnrollmentStore enrollments;
  final EncryptionService _encryption;
  static final _id = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');
  static const _format = 'himemo-sync-v2-registration';

  List<int> _context(
    String account,
    String generation,
    String purpose, [
    String? profile,
    String? keyId,
  ]) => utf8.encode(
    jsonEncode([_format, 1, account, generation, purpose, profile, keyId]),
  );
  String _randomId(String prefix) =>
      '${prefix}_${_encryption.generateKeyBytes(length: 16).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}';

  Future<SyncV2PreparedRegistration> prepare({
    required String accountId,
    required SecretKey adminKey,
  }) async {
    if (accountId.isEmpty || (await adminKey.extractBytes()).length != 32) {
      throw const FormatException('Invalid registration identity or key');
    }
    final generation = _randomId(generationPrefix);
    final profile = _randomId('normal');
    final keyId = _randomId('key');
    final sync = SecretKey(_encryption.generateKeyBytes());
    final normal = SecretKey(_encryption.generateKeyBytes());
    try {
      final clear = await normal.extractBytes();
      Future<String> wrap(SecretKey key, String purpose) =>
          _encryption.encryptBytes(
            clearBytes: clear,
            secretKey: key,
            additionalData: _context(
              accountId,
              generation,
              purpose,
              profile,
              keyId,
            ),
          );
      final manifest = {
        'format': _format,
        'version': 1,
        'account': accountId,
        'generation': generation,
        'normalProfileId': profile,
        'keyId': keyId,
        'normalSyncWrap': await wrap(sync, 'normal-sync-wrap'),
        'normalAdminWrap': await wrap(adminKey, 'normal-admin-wrap'),
      };
      final proof = await _encryption.encryptBytes(
        clearBytes: utf8.encode(jsonEncode(manifest)),
        secretKey: sync,
        additionalData: _context(accountId, generation, 'committed-manifest'),
      );
      final code = base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'account': accountId,
            'generation': generation,
            'key': base64UrlEncode(await sync.extractBytes()),
            'format': 'himemo.sync.v2.recovery',
          }),
        ),
      );
      if (utf8.encode(code).length > 4096) {
        throw const FormatException('Recovery code too large');
      }
      return SyncV2PreparedRegistration._(
        accountId,
        generation,
        code,
        proof,
        sync,
        normal,
      );
    } catch (_) {
      sync.destroy();
      normal.destroy();
      rethrow;
    }
  }

  Future<void> _checkLocal(
    String account,
    String generation,
    SecretKey key,
  ) async {
    final existing = await enrollments.readForAccount(account);
    if (existing == null) return;
    try {
      if (existing.generationId != generation ||
          !_equal(
            await existing.syncKey.extractBytes(),
            await key.extractBytes(),
          )) {
        throw StateError('This device already has a different enrollment');
      }
    } finally {
      existing.syncKey.destroy();
    }
  }

  bool _equal(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var different = 0;
    for (var i = 0; i < a.length; i++) {
      different |= a[i] ^ b[i];
    }
    return different == 0;
  }

  Future<void> _checkAccount(String expected) async {
    if (await transport.readCurrentAccountId() != expected) {
      throw StateError('The iCloud account changed');
    }
  }

  Future<SyncV2RegisteredNormalProfile> publishPrepared(
    SyncV2PreparedRegistration prepared,
  ) async {
    await _registrationStep(
      SyncV2RegistrationStage.account,
      () => _checkAccount(prepared.accountId),
    );
    await _registrationStep(
      SyncV2RegistrationStage.localCheck,
      () => _checkLocal(
        prepared.accountId,
        prepared.generationId,
        prepared._syncKey,
      ),
    );
    final pending = (
      accountId: prepared.accountId,
      generationId: prepared.generationId,
      syncKey: prepared._syncKey,
      encryptedProof: prepared.encryptedProof,
    );
    await _registrationStep(
      SyncV2RegistrationStage.persistPending,
      () => enrollments.savePendingRegistration(pending),
    );
    return _publishPending(pending);
  }

  Future<SyncV2RegisteredNormalProfile> resumePending() async {
    final pending = await _registrationStep(
      SyncV2RegistrationStage.persistPending,
      enrollments.readPendingRegistration,
    );
    if (pending == null) {
      throw const SyncV2RegistrationFailure._(
        SyncV2RegistrationStage.persistPending,
        'state_error',
      );
    }
    try {
      return await _publishPending(pending);
    } finally {
      pending.syncKey.destroy();
    }
  }

  Future<SyncV2RegisteredNormalProfile> _publishPending(
    SyncV2PendingRegistration pending,
  ) async {
    await _registrationStep(
      SyncV2RegistrationStage.account,
      () => _checkAccount(pending.accountId),
    );
    await _registrationStep(
      SyncV2RegistrationStage.localCheck,
      () =>
          _checkLocal(pending.accountId, pending.generationId, pending.syncKey),
    );
    final existing = await _registrationStep(
      SyncV2RegistrationStage.readRegistration,
      transport.readRegistration,
    );
    if (existing != null && existing != pending.encryptedProof) {
      throw const SyncV2RegistrationConflict();
    }
    await _registrationStep(
      SyncV2RegistrationStage.prepareGeneration,
      () => transport.prepareGeneration(pending.generationId),
    );
    await _registrationStep(
      SyncV2RegistrationStage.publishRegistration,
      () async {
        try {
          await transport.publishRegistration(pending.encryptedProof);
        } catch (error) {
          if (error is SyncV2CloudDataDeleted ||
              error is SyncV2RegistrationConflict ||
              error is SyncV2RegistrationFailure) {
            rethrow;
          }
          final competing = await _registrationStep(
            SyncV2RegistrationStage.readRegistration,
            transport.readRegistration,
          );
          if (competing != null && competing != pending.encryptedProof) {
            throw const SyncV2RegistrationConflict();
          }
          rethrow;
        }
      },
    );
    final proof = await _registrationStep(
      SyncV2RegistrationStage.readback,
      () async {
        final proof = await transport.readRegistration();
        if (proof != pending.encryptedProof) {
          throw StateError('Registration readback failed');
        }
        return proof!;
      },
    );
    final result = await _registrationStep(
      SyncV2RegistrationStage.verifyEnrollment,
      () => _verifyAndSave(
        pending.accountId,
        pending.generationId,
        pending.syncKey,
        proof,
      ),
    );
    try {
      await _registrationStep(
        SyncV2RegistrationStage.verifyEnrollment,
        () => enrollments.clearPendingRegistration(pending),
      );
      return result;
    } catch (_) {
      result.destroy();
      rethrow;
    }
  }

  Future<T> _registrationStep<T>(
    SyncV2RegistrationStage stage,
    Future<T> Function() action,
  ) async {
    try {
      return await action();
    } on SyncV2CloudDataDeleted {
      rethrow;
    } on SyncV2RegistrationConflict {
      rethrow;
    } on SyncV2RegistrationFailure {
      rethrow;
    } catch (error) {
      throw SyncV2RegistrationFailure._(stage, _safeRegistrationCode(error));
    }
  }

  String _safeRegistrationCode(Object error) {
    if (error is PlatformException) {
      final code = error.code;
      final numeric = int.tryParse(code);
      if (numeric != null &&
          numeric >= 0 &&
          numeric <= 40 &&
          RegExp(r'^(0|[1-9][0-9]?)$').hasMatch(code)) {
        return code;
      }
      const knownPlatformCodes = {
        'cloudkit_v2_invalidRequest',
        'cloudkit_v2_invalidRecord',
        'cloudkit_v2_accountChanged',
        'cloudkit_v2_recordCollision',
        'cloudkit_v2_cursor_expired',
        'cloudkit_v2_unsupported',
      };
      return knownPlatformCodes.contains(code) ? code : 'platform_error';
    }
    if (error is StateError) return 'state_error';
    if (error is FormatException) return 'format_error';
    if (error is HimemoDecryptionException) return 'decryption_error';
    return error is Exception ? 'operation_error' : 'unknown_error';
  }

  Future<SyncV2RegisteredNormalProfile> recover(
    String code, {
    SecretKey? adminKey,
  }) async {
    if (utf8.encode(code).length > 4096 ||
        !RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(code)) {
      throw const FormatException('Invalid recovery code');
    }
    final value = jsonDecode(
      utf8.decode(base64Url.decode(base64Url.normalize(code))),
    );
    if (value is! Map<String, dynamic> ||
        value.length != 5 ||
        value['format'] != 'himemo.sync.v2.recovery' ||
        value['version'] is! int ||
        value['version'] != 1 ||
        value['account'] is! String ||
        (value['account'] as String).isEmpty ||
        value['generation'] is! String ||
        !_id.hasMatch(value['generation'] as String) ||
        value['key'] is! String) {
      throw const FormatException('Invalid recovery code');
    }
    final bytes = base64Url.decode(base64Url.normalize(value['key'] as String));
    if (bytes.length != 32) throw const FormatException('Invalid recovery key');
    final key = SecretKey(bytes);
    try {
      final account = value['account'] as String;
      final generation = value['generation'] as String;
      await _checkAccount(account);
      await _checkLocal(account, generation, key);
      final proof = await transport.readRegistration();
      if (proof == null) throw StateError('No committed registration');
      final result = await _verifyAndSave(
        account,
        generation,
        key,
        proof,
        adminKey: adminKey,
      );
      try {
        await enrollments.cleanupPendingAfterVerifiedRecovery((
          accountId: account,
          generationId: generation,
          syncKey: key,
        ));
        return result;
      } catch (_) {
        result.destroy();
        rethrow;
      }
    } finally {
      key.destroy();
    }
  }

  Future<SyncV2RegisteredNormalProfile> _verifyAndSave(
    String account,
    String generation,
    SecretKey sync,
    String proof, {
    SecretKey? adminKey,
  }) async {
    final manifest = await _openManifest(account, generation, sync, proof);
    final normal = await _unlockNormal((
      accountId: account,
      generationId: generation,
      syncKey: sync,
    ), manifest);
    try {
      if (adminKey != null) {
        await _verifyAdminWrap(account, generation, manifest, normal, adminKey);
      }
      await _checkAccount(account);
      await enrollments.saveVerified((
        accountId: account,
        generationId: generation,
        syncKey: sync,
      ));
      await enrollments.cacheVerifiedProof((
        accountId: account,
        generationId: generation,
        syncKey: sync,
      ), proof);
      return SyncV2RegisteredNormalProfile(normal);
    } catch (_) {
      normal.destroy();
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _openManifest(
    String account,
    String generation,
    SecretKey sync,
    String proof,
  ) async {
    if (utf8.encode(proof).length > 65536) {
      throw const FormatException('Registration proof too large');
    }
    final manifest = jsonDecode(
      utf8.decode(
        await _encryption.decryptBytes(
          encodedPayload: proof,
          secretKey: sync,
          additionalData: _context(account, generation, 'committed-manifest'),
        ),
      ),
    );
    if (manifest is! Map<String, dynamic> ||
        manifest.length != 8 ||
        manifest['format'] != _format ||
        manifest['version'] is! int ||
        manifest['version'] != 1 ||
        manifest['account'] != account ||
        manifest['generation'] != generation ||
        manifest['normalProfileId'] is! String ||
        !_id.hasMatch(manifest['normalProfileId'] as String) ||
        manifest['keyId'] is! String ||
        !_id.hasMatch(manifest['keyId'] as String) ||
        manifest['normalSyncWrap'] is! String ||
        manifest['normalAdminWrap'] is! String) {
      throw const FormatException('Invalid registration manifest');
    }
    _validateWrap(manifest['normalSyncWrap'] as String);
    _validateWrap(manifest['normalAdminWrap'] as String);
    return manifest;
  }

  Future<String> exportRecoveryCode({required String accountId}) async {
    final enrolled = await enrollments.readForAccount(accountId);
    if (enrolled == null) throw StateError('No verified enrollment');
    try {
      return base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'account': enrolled.accountId,
            'generation': enrolled.generationId,
            'key': base64UrlEncode(await enrolled.syncKey.extractBytes()),
            'format': 'himemo.sync.v2.recovery',
          }),
        ),
      );
    } finally {
      enrolled.syncKey.destroy();
    }
  }

  Future<SyncV2RegisteredNormalProfile> restoreEnrolled({
    required String accountId,
    bool refreshFromCloud = false,
  }) async {
    final enrolled = await enrollments.readForAccount(accountId);
    if (enrolled == null) throw StateError('No verified enrollment');
    try {
      final proof = refreshFromCloud
          ? null
          : await enrollments.readCachedProof(accountId);
      if (proof == null) {
        return await recover(await exportRecoveryCode(accountId: accountId));
      }
      final manifest = await _openManifest(
        accountId,
        enrolled.generationId,
        enrolled.syncKey,
        proof,
      );
      return SyncV2RegisteredNormalProfile(
        await _unlockNormal(enrolled, manifest),
      );
    } finally {
      enrolled.syncKey.destroy();
    }
  }

  Future<SyncV2UnlockedProfileKey> _unlockNormal(
    SyncV2Enrollment enrolled,
    Map<String, dynamic> manifest,
  ) => SyncV2UnlockedProfileKey.unlockNormal(
    encryption: _encryption,
    accountId: enrolled.accountId,
    generationId: enrolled.generationId,
    profileId: manifest['normalProfileId'] as String,
    keyId: manifest['keyId'] as String,
    syncWrap: manifest['normalSyncWrap'] as String,
    syncKey: enrolled.syncKey,
  );

  Future<void> verifyAdminKey({
    required String accountId,
    required SecretKey adminKey,
  }) async {
    final enrolled = await enrollments.readForAccount(accountId);
    if (enrolled == null) throw StateError('No verified enrollment');
    SyncV2UnlockedProfileKey? normal;
    try {
      final proof = await enrollments.readCachedProof(accountId);
      if (proof == null) throw StateError('No verified registration proof');
      final manifest = await _openManifest(
        accountId,
        enrolled.generationId,
        enrolled.syncKey,
        proof,
      );
      normal = await _unlockNormal(enrolled, manifest);
      await _verifyAdminWrap(
        accountId,
        enrolled.generationId,
        manifest,
        normal,
        adminKey,
      );
    } finally {
      normal?.destroy();
      enrolled.syncKey.destroy();
    }
  }

  Future<void> _verifyAdminWrap(
    String account,
    String generation,
    Map<String, dynamic> manifest,
    SyncV2UnlockedProfileKey normal,
    SecretKey adminKey,
  ) async {
    final bytes = await _encryption.decryptBytes(
      encodedPayload: manifest['normalAdminWrap'] as String,
      secretKey: adminKey,
      additionalData: _context(
        account,
        generation,
        'normal-admin-wrap',
        normal.profileId,
        normal.keyId,
      ),
    );
    try {
      if (bytes.length != 32 ||
          !_equal(bytes, await normal.key.extractBytes())) {
        throw const HimemoDecryptionException();
      }
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
  }

  void _validateWrap(String wrap) {
    if (utf8.encode(wrap).length > 4096) {
      throw const FormatException('Key wrap too large');
    }
    final envelope = jsonDecode(wrap);
    if (envelope is! Map<String, dynamic> ||
        envelope.length != 4 ||
        envelope['version'] is! int ||
        envelope['version'] != 1 ||
        envelope['nonce'] is! String ||
        envelope['cipherText'] is! String ||
        envelope['mac'] is! String ||
        base64Decode(envelope['nonce'] as String).length != 12 ||
        base64Decode(envelope['cipherText'] as String).length != 32 ||
        base64Decode(envelope['mac'] as String).length != 16) {
      throw const FormatException('Invalid key wrap');
    }
  }
}
