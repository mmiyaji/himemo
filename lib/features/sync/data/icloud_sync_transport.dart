import 'dart:async';

import 'package:flutter/services.dart';

import 'google_drive_sync_transport.dart';

enum ICloudAccountAvailability {
  available,
  noAccount,
  restricted,
  temporarilyUnavailable,
  couldNotDetermine,
  unsupported,
  unknown,
}

class ICloudAccountStatusResult {
  const ICloudAccountStatusResult({
    required this.availability,
    required this.message,
  });

  final ICloudAccountAvailability availability;
  final String message;

  bool get isAvailable => availability == ICloudAccountAvailability.available;
}

class ICloudSyncException implements Exception {
  const ICloudSyncException(
    this.message, {
    this.retryAfter,
    this.isTemporary = false,
    this.details,
  });

  final String message;
  final Duration? retryAfter;
  final bool isTemporary;
  final Object? details;

  @override
  String toString() => message;
}

abstract class ICloudSyncTransport {
  Future<ICloudAccountStatusResult> checkAccountStatus();

  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus();

  Future<List<RemoteSyncBundleStatus>> listBundleHistory({int limit = 10});

  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  });

  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle();

  Future<DownloadedRemoteSyncBundle?> downloadBundleByRecordName(
    String recordName,
  );
}

class MethodChannelICloudSyncTransport implements ICloudSyncTransport {
  static const MethodChannel _channel = MethodChannel(
    'org.ruhenheim.himemo/cloudkit',
  );
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  @override
  Future<ICloudAccountStatusResult> checkAccountStatus() async {
    try {
      final result = Map<String, dynamic>.from(
        await _channel.invokeMapMethod<String, dynamic>(
              'cloudKitAccountStatus',
            ) ??
            const <String, dynamic>{},
      );
      return ICloudAccountStatusResult(
        availability: _availabilityFromString(result['status'] as String?),
        message:
            result['message'] as String? ??
            'Unable to determine this device\'s iCloud availability.',
      );
    } on MissingPluginException {
      return const ICloudAccountStatusResult(
        availability: ICloudAccountAvailability.unsupported,
        message: 'CloudKit is not available in this runtime.',
      );
    } on PlatformException catch (error) {
      return ICloudAccountStatusResult(
        availability: ICloudAccountAvailability.unknown,
        message: _messageForPlatformException(error),
      );
    }
  }

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    final result = await _invokeMap('cloudKitFetchLatestBundleStatus');
    if (result == null) {
      return null;
    }
    return _statusFromMap(result);
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({
    int limit = 10,
  }) async {
    final result = await _invokeList('cloudKitListBundleHistory', {
      'limit': limit,
    });
    return result
        .map((entry) => _statusFromMap(Map<String, dynamic>.from(entry as Map)))
        .toList(growable: false);
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) async {
    final result = await _invokeMap('cloudKitUploadBundle', {
      'encodedPayload': encodedPayload,
      'deviceId': deviceId,
      'noteCount': noteCount,
      'attachmentCount': attachmentCount,
    });
    if (result == null) {
      throw const FormatException('CloudKit did not return uploaded metadata.');
    }
    return _statusFromMap(result);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    final result = await _invokeMap('cloudKitDownloadLatestBundle');
    if (result == null) {
      return null;
    }
    return _downloadedBundleFromMap(result);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByRecordName(
    String recordName,
  ) async {
    final result = await _invokeMap('cloudKitDownloadBundle', {
      'recordName': recordName,
    });
    if (result == null) {
      return null;
    }
    return _downloadedBundleFromMap(result);
  }

  Future<Map<String, dynamic>?> _invokeMap(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _withCloudKitRetry(
      () => _channel.invokeMapMethod<String, dynamic>(method, arguments),
    );
    if (result == null) {
      return null;
    }
    return Map<String, dynamic>.from(result);
  }

  Future<List<dynamic>> _invokeList(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _withCloudKitRetry(
      () => _channel.invokeListMethod<dynamic>(method, arguments),
    );
    return result ?? const <dynamic>[];
  }

  Future<T> _withCloudKitRetry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        return await operation();
      } on PlatformException catch (error) {
        final mapped = _mapPlatformException(error);
        if (attempt >= _retryDelays.length || !mapped.isTemporary) {
          throw mapped;
        }
        await Future<void>.delayed(_retryDelays[attempt]);
      } on MissingPluginException {
        throw const ICloudSyncException(
          'CloudKit is not available in this runtime.',
        );
      }
    }
    throw const ICloudSyncException('CloudKit request failed.');
  }

  ICloudSyncException _mapPlatformException(PlatformException error) {
    final details = error.details;
    final retryAfter = details is Map
        ? _durationFromSeconds(details['retryAfterSeconds'])
        : null;
    final message = _messageForPlatformException(error);
    final isTemporary =
        retryAfter != null ||
        message.contains('temporarily') ||
        message.contains('Retry') ||
        message.contains('network is unavailable') ||
        message.contains('CloudKit is temporarily unavailable');
    return ICloudSyncException(
      message,
      retryAfter:
          retryAfter ?? (isTemporary ? const Duration(minutes: 1) : null),
      isTemporary: isTemporary,
      details: error,
    );
  }

  Duration? _durationFromSeconds(Object? value) {
    final seconds = switch (value) {
      int seconds => seconds,
      double seconds => seconds.ceil(),
      String seconds => double.tryParse(seconds)?.ceil(),
      _ => null,
    };
    if (seconds == null || seconds <= 0) {
      return null;
    }
    return Duration(seconds: seconds);
  }

  String _messageForPlatformException(PlatformException error) {
    final details = error.details;
    if (details is Map && details['message'] is String) {
      return details['message'] as String;
    }
    return error.message ?? error.code;
  }

  DownloadedRemoteSyncBundle _downloadedBundleFromMap(
    Map<String, dynamic> map,
  ) {
    return DownloadedRemoteSyncBundle(
      status: _statusFromMap(
        Map<String, dynamic>.from(map['status'] as Map<String, dynamic>),
      ),
      encodedPayload: map['encodedPayload'] as String? ?? '',
    );
  }

  RemoteSyncBundleStatus _statusFromMap(Map<String, dynamic> map) {
    return RemoteSyncBundleStatus(
      fileId: map['recordName'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      modifiedAt: _parseDate(map['modifiedAt'] as String?),
      sizeBytes: map['sizeBytes'] as int?,
      noteCount: map['noteCount'] as int?,
      attachmentCount: map['attachmentCount'] as int?,
      deviceId: map['deviceId'] as String?,
    );
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value);
  }

  ICloudAccountAvailability _availabilityFromString(String? value) {
    return switch (value) {
      'available' => ICloudAccountAvailability.available,
      'noAccount' => ICloudAccountAvailability.noAccount,
      'restricted' => ICloudAccountAvailability.restricted,
      'temporarilyUnavailable' =>
        ICloudAccountAvailability.temporarilyUnavailable,
      'couldNotDetermine' => ICloudAccountAvailability.couldNotDetermine,
      'unsupported' => ICloudAccountAvailability.unsupported,
      _ => ICloudAccountAvailability.unknown,
    };
  }
}
