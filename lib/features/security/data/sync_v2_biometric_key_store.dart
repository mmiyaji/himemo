import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

/// Storage for a Sync v2 admin key protected by the current biometric set.
///
/// [read] returns null only when that generation has no saved key. User
/// cancellation, unavailable biometrics, and invalidated keys are surfaced as
/// [PlatformException]s with codes `cancelled`, `unavailable`, `invalidated`,
/// or `failed`.
abstract interface class SyncV2BiometricKeyStore {
  Future<bool> isAvailable();

  Future<void> save(String generationId, SecretKey key);

  Future<SecretKey?> read(String generationId);

  Future<void> delete(String generationId);
}

class MethodChannelSyncV2BiometricKeyStore implements SyncV2BiometricKeyStore {
  MethodChannelSyncV2BiometricKeyStore({MethodChannel? channel})
    : _channel =
          channel ??
          const MethodChannel('org.ruhenheim.himemo/sync_v2_biometrics');

  final MethodChannel _channel;

  @override
  Future<bool> isAvailable() async =>
      await _channel.invokeMethod<bool>('availability') ?? false;

  @override
  Future<void> save(String generationId, SecretKey key) async {
    final bytes = await key.extractBytes();
    if (bytes.length != 32) {
      throw ArgumentError.value(
        bytes.length,
        'key',
        'Must be exactly 32 bytes',
      );
    }
    await _channel.invokeMethod<void>('write', <String, Object>{
      'generationId': generationId,
      'keyBase64': base64Encode(bytes),
    });
  }

  @override
  Future<SecretKey?> read(String generationId) async {
    final encoded = await _channel.invokeMethod<String>(
      'read',
      <String, Object>{'generationId': generationId},
    );
    if (encoded == null) return null;
    try {
      final bytes = base64Decode(encoded);
      if (bytes.length != 32) {
        throw const FormatException('Biometric key must be exactly 32 bytes');
      }
      return SecretKey(bytes);
    } on FormatException {
      throw PlatformException(
        code: 'failed',
        message: 'The biometric key could not be decoded.',
      );
    }
  }

  @override
  Future<void> delete(String generationId) async {
    await _channel.invokeMethod<void>('delete', <String, Object>{
      'generationId': generationId,
    });
  }
}
