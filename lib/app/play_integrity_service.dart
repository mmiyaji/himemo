import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class PlayIntegrityStatus {
  const PlayIntegrityStatus({
    required this.isAvailable,
    required this.message,
    this.installerPackage,
    this.projectNumber,
  });

  final bool isAvailable;
  final String message;
  final String? installerPackage;
  final String? projectNumber;
}

class PlayIntegrityService {
  static const MethodChannel _channel = MethodChannel(
    'org.ruhenheim.himemo/integrity',
  );

  const PlayIntegrityService();

  Future<PlayIntegrityStatus> checkAvailability() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return const PlayIntegrityStatus(
        isAvailable: false,
        message: 'Play Integrity is only available on Android.',
      );
    }
    try {
      final response = Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>('checkAvailability') ??
            const <String, dynamic>{},
      );
      return PlayIntegrityStatus(
        isAvailable: response['available'] as bool? ?? false,
        message:
            response['message'] as String? ??
            'Play Integrity status is unavailable.',
        installerPackage: response['installerPackage'] as String?,
        projectNumber: response['projectNumber'] as String?,
      );
    } catch (error) {
      return PlayIntegrityStatus(
        isAvailable: false,
        message: '$error',
      );
    }
  }

  Future<String> requestClassicToken({
    required String requestHash,
  }) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw StateError('Play Integrity is only available on Android.');
    }
    if (requestHash.trim().isEmpty) {
      throw ArgumentError.value(requestHash, 'requestHash', 'Must not be empty');
    }
    final token = await _channel.invokeMethod<String>('requestToken', {
      'requestHash': requestHash.trim(),
    });
    if (token == null || token.isEmpty) {
      throw StateError('Play Integrity token was empty.');
    }
    return token;
  }
}
