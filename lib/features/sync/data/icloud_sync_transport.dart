import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../../../app/diagnostic_log.dart';
import '../../../app/firebase_observability.dart';
import 'google_drive_sync_transport.dart';
import 'remote_attachment_maintenance.dart';

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

class ICloudStorageBreakdown {
  const ICloudStorageBreakdown({
    required this.bundleCount,
    required this.bundleBytes,
    required this.attachmentCount,
    required this.attachmentBytes,
  });

  final int bundleCount;
  final int bundleBytes;
  final int attachmentCount;
  final int attachmentBytes;

  int get totalBytes => bundleBytes + attachmentBytes;
}

class ICloudMaintenanceResult {
  const ICloudMaintenanceResult({
    required this.deletedBundleCount,
    required this.deletedBundleBytes,
    required this.deletedAttachmentCount,
    required this.deletedAttachmentBytes,
  });

  final int deletedBundleCount;
  final int deletedBundleBytes;
  final int deletedAttachmentCount;
  final int deletedAttachmentBytes;

  int get deletedBytes => deletedBundleBytes + deletedAttachmentBytes;
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
    String bundleKind = SyncBundleKind.full,
    String? replayBaseFileId,
  });

  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  });

  Future<Set<String>> listAttachmentObjectContentHashes();

  Future<String?> downloadAttachmentObject(String contentHash);

  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle();

  Future<DownloadedRemoteSyncBundle?> downloadBundleByRecordName(
    String recordName,
  );

  Future<ICloudStorageBreakdown> fetchStorageBreakdown();

  Future<ICloudMaintenanceResult> pruneObsoleteData({
    int keepLatest = 1,
    required Set<String> referencedAttachmentHashes,
    Set<String>? bundleFileIdsToDelete,
    String? expectedLatestFileId,
  });
}

class InMemoryICloudSyncTransport
    implements ICloudSyncTransport, RemoteAttachmentMaintenanceTransport {
  InMemoryICloudSyncTransport({
    this.operationDelay = Duration.zero,
    this.availability = ICloudAccountAvailability.available,
  });

  final Duration operationDelay;
  ICloudAccountAvailability availability;

  final Map<String, _InMemoryICloudAttachment> _attachmentObjects = {};
  final Map<String, _MemoryManagedAttachment> _managedAttachments = {};
  final List<_InMemoryICloudBundle> _bundles = [];
  int _nextBundleId = 1;
  int _nextManagedId = 1;

  @override
  Future<String> pinAttachmentObject({
    required String contentHash,
    required String uploadId,
    String? encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
  }) async {
    await _delay();
    _throwIfUnavailable();
    // Legacy objects are deliberately retained by GC. Reuse them in place;
    // ordinary synchronization must not download and duplicate their payload.
    if (_attachmentObjects.containsKey(contentHash)) {
      return 'attachment-$contentHash';
    }
    final token = uploadId.length <= 64 ? uploadId : uploadId.substring(0, 64);
    final candidates = _managedAttachments.values
        .where(
          (item) =>
              item.contentHash == contentHash &&
              !item.deleting &&
              item.holders.length < 3,
        )
        .toList();
    if (candidates.isNotEmpty) {
      candidates.first.holders.add(token);
      candidates.first.revision++;
      return candidates.first.id;
    }
    final payload =
        encodedPayload ?? await downloadAttachmentObject(contentHash);
    if (payload == null) {
      throw const ICloudSyncException(
        'No attachment payload is available for managed upload.',
      );
    }
    final id = 'managed-attachment-${_nextManagedId++}';
    _managedAttachments[id] = _MemoryManagedAttachment(
      id,
      contentHash,
      payload,
      sizeBytes,
      {token},
    );
    return id;
  }

  @override
  Future<void> releaseAttachmentObject({
    required String recordId,
    required String uploadId,
    required String publishedBundleId,
  }) async {
    await _delay();
    _throwIfUnavailable();
    final item = _managedAttachments[recordId];
    if (item == null) return;
    item.holders.remove(
      uploadId.length <= 64 ? uploadId : uploadId.substring(0, 64),
    );
    item.lastPublishedBundleId = publishedBundleId;
    item.revision++;
  }

  @override
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects() async {
    await _delay();
    _throwIfUnavailable();
    return _managedAttachments.values
        .map((item) => item.snapshot())
        .toList(growable: false);
  }

  @override
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  ) async {
    await _delay();
    _throwIfUnavailable();
    final item = _managedAttachments[candidate.id];
    if (item == null ||
        item.revision.toString() != candidate.revision ||
        item.holders.isNotEmpty) {
      return false;
    }
    item.deleting = true;
    item.revision++;
    _managedAttachments.remove(candidate.id);
    return true;
  }

  @override
  Future<ICloudAccountStatusResult> checkAccountStatus() async {
    await _delay();
    return ICloudAccountStatusResult(
      availability: availability,
      message: availability == ICloudAccountAvailability.available
          ? 'iCloud simulator is available.'
          : 'iCloud simulator is not available.',
    );
  }

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    await _delay();
    if (_bundles.isEmpty) {
      return null;
    }
    return _bundles.last.status;
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({
    int limit = 10,
  }) async {
    await _delay();
    return _bundles.reversed
        .take(limit)
        .map((bundle) => bundle.status)
        .toList(growable: false);
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
    String bundleKind = SyncBundleKind.full,
    String? replayBaseFileId,
  }) async {
    await _delay();
    _throwIfUnavailable();
    final now = DateTime.now().toUtc();
    final uploadNumber = _nextBundleId++;
    final status = RemoteSyncBundleStatus(
      fileId: 'fake-icloud-bundle-$uploadNumber',
      fileName:
          'himemo_fake_icloud_${now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').padRight(14, '0').substring(0, 14)}.enc',
      modifiedAt: now,
      sizeBytes: encodedPayload.length,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
      deviceId: deviceId,
      bundleKind: bundleKind,
      replayBaseFileId: replayBaseFileId,
    );
    _bundles.add(
      _InMemoryICloudBundle(status: status, encodedPayload: encodedPayload),
    );
    return status;
  }

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    await _delay();
    _throwIfUnavailable();
    if (skipExistingCheck && _attachmentObjects.containsKey(contentHash)) {
      return;
    }
    _attachmentObjects[contentHash] = _InMemoryICloudAttachment(
      encodedPayload: encodedPayload,
      sizeBytes: sizeBytes,
    );
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    await _delay();
    _throwIfUnavailable();
    return {
      ..._attachmentObjects.keys,
      ..._managedAttachments.values
          .where((item) => !item.deleting)
          .map((item) => item.contentHash),
    };
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    await _delay();
    _throwIfUnavailable();
    final managed = _managedAttachments.values
        .where((item) => item.contentHash == contentHash && !item.deleting)
        .firstOrNull;
    return managed?.payload ?? _attachmentObjects[contentHash]?.encodedPayload;
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    await _delay();
    _throwIfUnavailable();
    if (_bundles.isEmpty) {
      return null;
    }
    final bundle = _bundles.last;
    return DownloadedRemoteSyncBundle(
      status: bundle.status,
      encodedPayload: bundle.encodedPayload,
    );
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByRecordName(
    String recordName,
  ) async {
    await _delay();
    _throwIfUnavailable();
    for (final bundle in _bundles.reversed) {
      if (bundle.status.fileId == recordName) {
        return DownloadedRemoteSyncBundle(
          status: bundle.status,
          encodedPayload: bundle.encodedPayload,
        );
      }
    }
    return null;
  }

  @override
  Future<ICloudStorageBreakdown> fetchStorageBreakdown() async {
    await _delay();
    return ICloudStorageBreakdown(
      bundleCount: _bundles.length,
      bundleBytes: _bundles.fold<int>(
        0,
        (total, bundle) => total + (bundle.status.sizeBytes ?? 0),
      ),
      attachmentCount: _attachmentObjects.length + _managedAttachments.length,
      attachmentBytes:
          _attachmentObjects.values.fold<int>(
            0,
            (total, attachment) => total + attachment.sizeBytes,
          ) +
          _managedAttachments.values.fold<int>(
            0,
            (total, attachment) => total + attachment.sizeBytes,
          ),
    );
  }

  @override
  Future<ICloudMaintenanceResult> pruneObsoleteData({
    int keepLatest = 1,
    required Set<String> referencedAttachmentHashes,
    Set<String>? bundleFileIdsToDelete,
    String? expectedLatestFileId,
  }) async {
    await _delay();
    // Fail closed for legacy callers that request an unbounded sweep.
    if (bundleFileIdsToDelete == null ||
        expectedLatestFileId == null ||
        _bundles.isEmpty ||
        _bundles.last.status.fileId != expectedLatestFileId) {
      return const ICloudMaintenanceResult(
        deletedBundleCount: 0,
        deletedBundleBytes: 0,
        deletedAttachmentCount: 0,
        deletedAttachmentBytes: 0,
      );
    }
    final removed = _bundles
        .where(
          (bundle) =>
              bundleFileIdsToDelete.contains(bundle.status.fileId) &&
              bundle.status.fileId != expectedLatestFileId,
        )
        .toList();
    _bundles.removeWhere((bundle) => removed.contains(bundle));
    return ICloudMaintenanceResult(
      deletedBundleCount: removed.length,
      deletedBundleBytes: removed.fold<int>(
        0,
        (sum, item) => sum + (item.status.sizeBytes ?? 0),
      ),
      deletedAttachmentCount: 0,
      deletedAttachmentBytes: 0,
    );
  }

  Future<void> _delay() async {
    if (operationDelay > Duration.zero) {
      await Future<void>.delayed(operationDelay);
    }
  }

  void _throwIfUnavailable() {
    if (availability == ICloudAccountAvailability.available) {
      return;
    }
    throw ICloudSyncException(
      'iCloud simulator is not available.',
      isTemporary:
          availability == ICloudAccountAvailability.temporarilyUnavailable,
    );
  }
}

class _MemoryManagedAttachment {
  _MemoryManagedAttachment(
    this.id,
    this.contentHash,
    this.payload,
    this.sizeBytes,
    this.holders,
  );
  final String id, contentHash, payload;
  final int sizeBytes;
  final Set<String> holders;
  int revision = 1;
  bool deleting = false;
  String? lastPublishedBundleId;
  ManagedAttachmentObject snapshot() => ManagedAttachmentObject(
    id: id,
    contentHash: contentHash,
    revision: '$revision',
    modifiedAt: DateTime.now().toUtc(),
    uploadIds: Set.unmodifiable(holders),
    lastPublishedBundleId: lastPublishedBundleId,
    deleting: deleting,
    sizeBytes: sizeBytes,
  );
}

class _InMemoryICloudBundle {
  const _InMemoryICloudBundle({
    required this.status,
    required this.encodedPayload,
  });

  final RemoteSyncBundleStatus status;
  final String encodedPayload;
}

class _InMemoryICloudAttachment {
  const _InMemoryICloudAttachment({
    required this.encodedPayload,
    required this.sizeBytes,
  });

  final String encodedPayload;
  final int sizeBytes;
}

class MethodChannelICloudSyncTransport
    implements ICloudSyncTransport, RemoteAttachmentMaintenanceTransport {
  static const MethodChannel _channel = MethodChannel(
    'org.ruhenheim.himemo/cloudkit',
  );
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  @override
  Future<String> pinAttachmentObject({
    required String contentHash,
    required String uploadId,
    String? encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
  }) async {
    final result = await _invokeMap('managedPinAttachment', {
      'contentHash': contentHash,
      'uploadId': uploadId,
      'encodedPayload': encodedPayload,
      'type': type,
      'label': label,
      'sizeBytes': sizeBytes,
    });
    final id = result?['recordId'];
    if (id is! String || id.isEmpty) {
      throw const FormatException(
        'CloudKit did not return a managed attachment ID.',
      );
    }
    return id;
  }

  @override
  Future<void> releaseAttachmentObject({
    required String recordId,
    required String uploadId,
    required String publishedBundleId,
  }) async {
    await _invokeMap('managedReleaseAttachment', {
      'recordId': recordId,
      'uploadId': uploadId,
      'publishedBundleId': publishedBundleId,
    });
  }

  @override
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects() async =>
      (await _invokeList('managedListAttachments'))
          .map((entry) => _managedAttachmentFromMap(_stringMapFrom(entry)))
          .toList(growable: false);
  @override
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  ) async =>
      (await _invokeMap('managedClaimDeleteAttachment', {
        'recordId': candidate.id,
        'revision': candidate.revision,
      }))?['deleted'] ==
      true;
  ManagedAttachmentObject _managedAttachmentFromMap(Map<String, dynamic> map) =>
      ManagedAttachmentObject(
        id: map['recordId'] as String? ?? '',
        contentHash: map['contentHash'] as String? ?? '',
        revision: map['revision'] as String? ?? '',
        modifiedAt: _parseDate(map['modifiedAt'] as String?),
        uploadIds: ((map['uploadIds'] as List?) ?? const [])
            .whereType<String>()
            .toSet(),
        lastPublishedBundleId: map['lastPublishedBundleId'] as String?,
        deleting: map['deleting'] == true,
        sizeBytes: _intFrom(map['sizeBytes']),
      );

  @override
  Future<ICloudAccountStatusResult> checkAccountStatus() async {
    final stopwatch = Stopwatch()..start();
    await logFirebaseBreadcrumb('icloud cloudKitAccountStatus start');
    logDiagnostic('icloud', 'account status start');
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
      stopwatch.stop();
      logDiagnostic(
        'icloud',
        'account status success',
        data: {
          'availability': status.availability.name,
          'elapsedMs': stopwatch.elapsedMilliseconds,
        },
      );
      return status;
    } on MissingPluginException {
      stopwatch.stop();
      logDiagnostic(
        'icloud',
        'account status missing',
        data: {'elapsedMs': stopwatch.elapsedMilliseconds},
      );
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
      stopwatch.stop();
      logDiagnostic(
        'icloud',
        'account status failed',
        data: {
          'elapsedMs': stopwatch.elapsedMilliseconds,
          'code': error.code,
          'message': error.message,
        },
      );
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
    String bundleKind = SyncBundleKind.full,
    String? replayBaseFileId,
  }) async {
    final result = await _invokeMap('cloudKitUploadBundle', {
      'encodedPayload': encodedPayload,
      'deviceId': deviceId,
      'noteCount': noteCount,
      'attachmentCount': attachmentCount,
      // Encode the base in the existing String field: no production CloudKit
      // schema migration is required for this protocol extension.
      'bundleKind': replayBaseFileId == null
          ? bundleKind
          : '$bundleKind:${base64Url.encode(utf8.encode(replayBaseFileId))}',
    });
    if (result == null) {
      throw const FormatException('CloudKit did not return uploaded metadata.');
    }
    return _statusFromMap(result);
  }

  @override
  Future<void> uploadAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) async {
    await _invokeMap('cloudKitUploadAttachmentObject', {
      'contentHash': contentHash,
      'encodedPayload': encodedPayload,
      'type': type,
      'label': label,
      'sizeBytes': sizeBytes,
      'skipExistingCheck': skipExistingCheck,
    });
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    final result = await _invokeList('cloudKitListAttachmentHashes');
    return {
      for (final entry in result)
        if (entry is String && entry.isNotEmpty) entry,
    };
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    final result = await _invokeMap('cloudKitDownloadAttachmentObject', {
      'contentHash': contentHash,
    });
    return result?['encodedPayload'] as String?;
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

  @override
  Future<ICloudStorageBreakdown> fetchStorageBreakdown() async {
    final result = await _invokeMap('cloudKitStorageBreakdown');
    if (result == null) {
      throw const FormatException('CloudKit did not return storage metadata.');
    }
    return ICloudStorageBreakdown(
      bundleCount: _intFrom(result['bundleCount']),
      bundleBytes: _intFrom(result['bundleBytes']),
      attachmentCount: _intFrom(result['attachmentCount']),
      attachmentBytes: _intFrom(result['attachmentBytes']),
    );
  }

  @override
  Future<ICloudMaintenanceResult> pruneObsoleteData({
    int keepLatest = 1,
    required Set<String> referencedAttachmentHashes,
    Set<String>? bundleFileIdsToDelete,
    String? expectedLatestFileId,
  }) async {
    final result = await _invokeMap('cloudKitPruneObsoleteData', {
      'keepLatest': keepLatest,
      'bundleFileIdsToDelete': bundleFileIdsToDelete?.toList(),
      'expectedLatestFileId': expectedLatestFileId,
      'referencedAttachmentHashes': referencedAttachmentHashes.toList()..sort(),
    });
    if (result == null) {
      throw const FormatException('CloudKit did not return cleanup metadata.');
    }
    return ICloudMaintenanceResult(
      deletedBundleCount: _intFrom(result['deletedBundleCount']),
      deletedBundleBytes: _intFrom(result['deletedBundleBytes']),
      deletedAttachmentCount: _intFrom(result['deletedAttachmentCount']),
      deletedAttachmentBytes: _intFrom(result['deletedAttachmentBytes']),
    );
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
    final stopwatch = Stopwatch()..start();
    await logFirebaseBreadcrumb('icloud $method start');
    logDiagnostic('icloud', 'method start', data: {'method': method});
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        final result = await operation();
        await logFirebaseBreadcrumb('icloud $method success');
        stopwatch.stop();
        logDiagnostic(
          'icloud',
          'method success',
          data: {
            'method': method,
            'attempt': attempt,
            'elapsedMs': stopwatch.elapsedMilliseconds,
          },
        );
        return result;
      } on PlatformException catch (error) {
        final mapped = _mapPlatformException(error);
        if (attempt >= _retryDelays.length || !mapped.isTemporary) {
          stopwatch.stop();
          logDiagnostic(
            'icloud',
            'method failed',
            data: {
              'method': method,
              'attempt': attempt,
              'elapsedMs': stopwatch.elapsedMilliseconds,
              'code': error.code,
              'message': mapped.message,
              'temporary': mapped.isTemporary,
            },
          );
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
        logDiagnostic(
          'icloud',
          'method retry',
          data: {
            'method': method,
            'attempt': attempt + 1,
            'delayMs': _retryDelays[attempt].inMilliseconds,
            'message': mapped.message,
          },
        );
        await Future<void>.delayed(_retryDelays[attempt]);
      } on MissingPluginException {
        const mapped = ICloudSyncException(
          'CloudKit is not available in this runtime.',
        );
        stopwatch.stop();
        logDiagnostic(
          'icloud',
          'method missing',
          data: {'method': method, 'elapsedMs': stopwatch.elapsedMilliseconds},
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
    final rawKind = map['bundleKind'] as String?;
    final parts = rawKind?.split(':');
    final hasBase = parts != null && parts.length == 2;
    final base = hasBase ? utf8.decode(base64Url.decode(parts[1])) : null;
    return RemoteSyncBundleStatus(
      fileId: map['recordName'] as String? ?? '',
      fileName: map['fileName'] as String? ?? '',
      modifiedAt: _parseDate(map['modifiedAt'] as String?),
      sizeBytes: map['sizeBytes'] as int?,
      noteCount: map['noteCount'] as int?,
      attachmentCount: map['attachmentCount'] as int?,
      deviceId: map['deviceId'] as String?,
      bundleKind: hasBase ? parts[0] : rawKind,
      replayBaseFileId: base,
    );
  }

  DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    return DateTime.tryParse(value)?.toUtc();
  }

  int _intFrom(Object? value) {
    return switch (value) {
      int value => value,
      double value => value.toInt(),
      String value => int.tryParse(value) ?? 0,
      _ => 0,
    };
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
