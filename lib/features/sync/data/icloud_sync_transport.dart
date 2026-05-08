import 'dart:async';

import 'package:flutter/services.dart';

import '../../../app/firebase_observability.dart';
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
    await logFirebaseBreadcrumb('icloud cloudKitAccountStatus start');
    try {
      final result = _stringMapFrom(
        await _channel.invokeMethod<dynamic>('cloudKitAccountStatus') ??
            const <String, dynamic>{},
      );
      final status = ICloudAccountStatusResult(
        availability: _availabilityFromString(result['status'] as String?),
        message:
            result['message'] as String? ??
            'Unable to determine this device\'s iCloud availability.',
      );
      await logFirebaseBreadcrumb(
        'icloud cloudKitAccountStatus ${status.availability.name}',
      );
      return status;
    } on MissingPluginException {
      unawaited(
        recordNonFatalError(
          const ICloudSyncException(
            'CloudKit is not available in this runtime.',
          ),
          StackTrace.current,
          reason: 'CloudKit account status missing',
        ),
      );
      return const ICloudAccountStatusResult(
        availability: ICloudAccountAvailability.unsupported,
        message: 'CloudKit is not available in this runtime.',
      );
    } on PlatformException catch (error) {
      unawaited(
        recordNonFatalError(
          error,
          StackTrace.current,
          reason: 'CloudKit account status failed',
          information: [
            'code=${error.code}',
            'message=${_messageForPlatformException(error)}',
          ],
        ),
      );
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
        .map((entry) => _statusFromMap(_stringMapFrom(entry)))
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
      method,
      () => _channel.invokeMethod<dynamic>(method, arguments),
    );
    if (result == null) {
      return null;
    }
    return _stringMapFrom(result);
  }

  Future<List<dynamic>> _invokeList(
    String method, [
    Map<String, dynamic>? arguments,
  ]) async {
    final result = await _withCloudKitRetry(
      method,
      () => _channel.invokeListMethod<dynamic>(method, arguments),
    );
    return result ?? const <dynamic>[];
  }

  Future<T> _withCloudKitRetry<T>(
    String method,
    Future<T> Function() operation,
  ) async {
    await logFirebaseBreadcrumb('icloud $method start');
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        final result = await operation();
        await logFirebaseBreadcrumb('icloud $method success');
        return result;
      } on PlatformException catch (error) {
        final mapped = _mapPlatformException(error);
        if (attempt >= _retryDelays.length || !mapped.isTemporary) {
          unawaited(
            recordNonFatalError(
              mapped,
              StackTrace.current,
              reason: 'CloudKit method failed: $method',
              information: [
                'method=$method',
                'attempt=$attempt',
                'code=${error.code}',
                'message=${mapped.message}',
              ],
            ),
          );
          throw mapped;
        }
        await logFirebaseBreadcrumb('icloud $method retry ${attempt + 1}');
        await Future<void>.delayed(_retryDelays[attempt]);
      } on MissingPluginException {
        const mapped = ICloudSyncException(
          'CloudKit is not available in this runtime.',
        );
        unawaited(
          recordNonFatalError(
            mapped,
            StackTrace.current,
            reason: 'CloudKit method missing: $method',
          ),
        );
        throw mapped;
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
      status: _statusFromMap(_stringMapFrom(map['status'])),
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

  Map<String, dynamic> _stringMapFrom(Object? value) {
    if (value is! Map) {
      throw FormatException('Expected a CloudKit map response, got $value.');
    }
    return value.map((key, value) => MapEntry(key.toString(), value));
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
