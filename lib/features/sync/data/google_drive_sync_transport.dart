import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:http/http.dart' show ClientException;

import 'google_sign_in_initializer.dart';
import 'sync_bundle_key_service.dart';
import 'remote_attachment_maintenance.dart';

/// Identifies whether a remote bundle contains every syncable note (full
/// snapshot) or only the changes queued since the previous upload (delta).
abstract final class SyncBundleKind {
  static const full = 'full';

  // Older readers must treat dependency-bearing checkpoints as deltas, rather
  // than assuming the standalone note list is a complete restore baseline.
  static const fullWithRetainedNotes = 'full-retained';
  static const delta = 'delta';
}

class RemoteSyncBundleStatus {
  const RemoteSyncBundleStatus({
    required this.fileId,
    required this.fileName,
    this.modifiedAt,
    this.sizeBytes,
    this.noteCount,
    this.attachmentCount,
    this.deviceId,
    this.bundleKind,
    this.replayBaseFileId,
  });

  final String fileId;
  final String fileName;
  final DateTime? modifiedAt;
  final int? sizeBytes;
  final int? noteCount;
  final int? attachmentCount;
  final String? deviceId;

  /// [SyncBundleKind.full], [SyncBundleKind.delta], or null for bundles
  /// uploaded before the kind was recorded (legacy bundles were always full
  /// snapshots).
  final String? bundleKind;
  final String? replayBaseFileId;

  bool get isFullBundle =>
      bundleKind == null ||
      bundleKind!.isEmpty ||
      bundleKind == SyncBundleKind.full ||
      bundleKind == SyncBundleKind.fullWithRetainedNotes ||
      bundleKind == 'full-ids-v1';
}

class DownloadedRemoteSyncBundle {
  const DownloadedRemoteSyncBundle({
    required this.status,
    required this.encodedPayload,
  });

  final RemoteSyncBundleStatus status;
  final String encodedPayload;
}

abstract class GoogleDriveSyncTransport {
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

  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(String fileId);
}

abstract interface class RemoteBundleMaintenanceTransport {
  Future<void> deleteBundleFilesByIds(Set<String> ids);
}

/// Read-and-delete access for recovery keys written by older app versions.
///
/// The current app never uploads a raw sync key to Google Drive because that
/// would place the decryption key beside the encrypted payload.
abstract class LegacyGoogleDriveSyncKeyTransport {
  Future<List<String>> fetchSyncKeyBackupCodes();

  Future<void> deleteSyncKeyBackupCode();
}

class InMemoryGoogleDriveSyncTransport
    implements
        GoogleDriveSyncTransport,
        LegacyGoogleDriveSyncKeyTransport,
        RemoteBundleMaintenanceTransport,
        RemoteAttachmentMaintenanceTransport {
  InMemoryGoogleDriveSyncTransport({
    this.uploadDelay = const Duration(milliseconds: 120),
  });

  final Duration uploadDelay;

  final Map<String, String> _attachmentObjects = {};
  final Map<String, _MemoryManagedAttachment> _managedAttachments = {};
  var _nextAttachmentId = 1;
  final List<_InMemoryGoogleDriveBundle> _bundles = [];
  final List<String> _syncKeyBackupCodes = [];
  var _nextBundleId = 1;

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    if (_bundles.isEmpty) {
      return null;
    }
    return _bundles.last.status;
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({
    int limit = 10,
  }) async {
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
    if (uploadDelay > Duration.zero) {
      await Future<void>.delayed(uploadDelay);
    }
    final now = DateTime.now().toUtc();
    final uploadNumber = _nextBundleId++;
    final status = RemoteSyncBundleStatus(
      fileId: 'fake-google-drive-bundle-$uploadNumber',
      fileName:
          'himemo_fake_google_drive_${now.toIso8601String().replaceAll(RegExp(r'[^0-9]'), '').padRight(14, '0').substring(0, 14)}.enc',
      modifiedAt: now,
      sizeBytes: encodedPayload.length,
      noteCount: noteCount,
      attachmentCount: attachmentCount,
      deviceId: deviceId,
      bundleKind: bundleKind,
      replayBaseFileId: replayBaseFileId,
    );
    _bundles.add(
      _InMemoryGoogleDriveBundle(
        status: status,
        encodedPayload: encodedPayload,
      ),
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
    if (skipExistingCheck && _attachmentObjects.containsKey(contentHash)) {
      return;
    }
    _attachmentObjects[contentHash] = encodedPayload;
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    return {
      ..._attachmentObjects.keys,
      ..._managedAttachments.values
          .where((o) => !o.deleting)
          .map((o) => o.contentHash),
    };
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    final managed = _managedAttachments.values
        .where((o) => o.contentHash == contentHash && !o.deleting)
        .toList();
    if (managed.isNotEmpty) return managed.first.payload;
    return _attachmentObjects[contentHash];
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    if (_bundles.isEmpty) return null;
    final bundle = _bundles.last;
    return DownloadedRemoteSyncBundle(
      status: bundle.status,
      encodedPayload: bundle.encodedPayload,
    );
  }

  @override
  Future<String> pinAttachmentObject({
    required String contentHash,
    required String uploadId,
    String? encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
  }) async {
    // Legacy objects are permanently outside managed GC. Reuse them without
    // copying bytes or creating a reservation that older clients cannot honor.
    if (_attachmentObjects.containsKey(contentHash)) {
      return 'legacy:$contentHash';
    }
    for (final o in _managedAttachments.values) {
      if (o.contentHash == contentHash &&
          !o.deleting &&
          o.uploadIds.length < 3) {
        o.uploadIds.add(uploadId);
        o.revision++;
        return o.id;
      }
    }
    final payload =
        encodedPayload ?? await downloadAttachmentObject(contentHash);
    if (payload == null) throw StateError('Attachment payload is unavailable.');
    final id = 'fake-managed-attachment-${_nextAttachmentId++}';
    _managedAttachments[id] = _MemoryManagedAttachment(
      id,
      contentHash,
      payload,
      sizeBytes,
      {uploadId},
    );
    return id;
  }

  @override
  Future<void> releaseAttachmentObject({
    required String recordId,
    required String uploadId,
    required String publishedBundleId,
  }) async {
    final o = _managedAttachments[recordId];
    if (o == null || o.deleting) return;
    o.uploadIds.remove(uploadId);
    o.lastPublishedBundleId = publishedBundleId;
    o.revision++;
  }

  @override
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects() async =>
      _managedAttachments.values
          .map((o) => o.snapshot())
          .toList(growable: false);

  @override
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  ) async {
    final o = _managedAttachments[candidate.id];
    if (o == null ||
        o.revision.toString() != candidate.revision ||
        o.uploadIds.isNotEmpty) {
      return false;
    }
    o.deleting = true;
    o.revision++;
    _managedAttachments.remove(candidate.id);
    return true;
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(
    String fileId,
  ) async {
    for (final bundle in _bundles.reversed) {
      if (bundle.status.fileId == fileId) {
        return DownloadedRemoteSyncBundle(
          status: bundle.status,
          encodedPayload: bundle.encodedPayload,
        );
      }
    }
    return null;
  }

  @override
  Future<void> deleteBundleFilesByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    _bundles.removeWhere((bundle) => ids.contains(bundle.status.fileId));
  }

  @override
  Future<List<String>> fetchSyncKeyBackupCodes() async =>
      List<String>.unmodifiable(_syncKeyBackupCodes);

  /// Seeds the legacy escrow record for migration tests only.
  void seedLegacySyncKeyBackupCodeForTest(String? backupCode) {
    _syncKeyBackupCodes
      ..clear()
      ..addAll(backupCode == null ? const <String>[] : [backupCode]);
  }

  /// Seeds duplicate legacy records for conflict migration tests only.
  void seedLegacySyncKeyBackupCodesForTest(List<String> backupCodes) {
    _syncKeyBackupCodes
      ..clear()
      ..addAll(backupCodes);
  }

  @override
  Future<void> deleteSyncKeyBackupCode() async {
    _syncKeyBackupCodes.clear();
  }
}

class _InMemoryGoogleDriveBundle {
  const _InMemoryGoogleDriveBundle({
    required this.status,
    required this.encodedPayload,
  });

  final RemoteSyncBundleStatus status;
  final String encodedPayload;
}

class _MemoryManagedAttachment {
  _MemoryManagedAttachment(
    this.id,
    this.contentHash,
    this.payload,
    this.sizeBytes,
    this.uploadIds,
  );
  final String id, contentHash, payload;
  final int sizeBytes;
  final Set<String> uploadIds;
  int revision = 1;
  bool deleting = false;
  String? lastPublishedBundleId;
  ManagedAttachmentObject snapshot() => ManagedAttachmentObject(
    id: id,
    contentHash: contentHash,
    revision: revision.toString(),
    modifiedAt: DateTime.now().toUtc(),
    uploadIds: Set.unmodifiable(uploadIds),
    lastPublishedBundleId: lastPublishedBundleId,
    deleting: deleting,
    sizeBytes: sizeBytes,
  );
}

class GoogleDriveCloudSyncBundleKeyStore
    implements CloudSyncBundleKeyStore, DeletableCloudSyncBundleKeyStore {
  GoogleDriveCloudSyncBundleKeyStore(this.transport);

  final GoogleDriveSyncTransport transport;

  @override
  Future<String?> readBackupCode() {
    return readBackupCodes().then(
      (codes) => codes.isEmpty ? null : codes.first,
    );
  }

  Future<List<String>> readBackupCodes() {
    final legacyTransport = transport;
    if (legacyTransport is! LegacyGoogleDriveSyncKeyTransport) {
      return Future<List<String>>.value(const <String>[]);
    }
    return (legacyTransport as LegacyGoogleDriveSyncKeyTransport)
        .fetchSyncKeyBackupCodes();
  }

  @override
  Future<void> deleteBackupCode() {
    final legacyTransport = transport;
    if (legacyTransport is! LegacyGoogleDriveSyncKeyTransport) {
      return Future<void>.value();
    }
    return (legacyTransport as LegacyGoogleDriveSyncKeyTransport)
        .deleteSyncKeyBackupCode();
  }
}

class GoogleDriveAuthConfig {
  const GoogleDriveAuthConfig({
    this.clientId = const String.fromEnvironment(
      'HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID',
    ),
    this.serverClientId = const String.fromEnvironment(
      'HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID',
    ),
  });

  final String clientId;
  final String serverClientId;

  String? get normalizedClientId => _blankToNull(clientId);

  String? get normalizedServerClientId => _blankToNull(serverClientId);

  static String? _blankToNull(String value) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

class GoogleDriveAuthConfigurationException implements Exception {
  const GoogleDriveAuthConfigurationException(this.message, [this.details]);

  final String message;
  final Object? details;

  @override
  String toString() => details == null ? message : '$message ($details)';
}

class GoogleDriveSyncException implements Exception {
  const GoogleDriveSyncException(
    this.message, {
    this.statusCode,
    this.retryAfter,
    this.isRateLimited = false,
    this.details,
  });

  final String message;
  final int? statusCode;
  final Duration? retryAfter;
  final bool isRateLimited;
  final Object? details;

  @override
  String toString() => message;
}

class _DriveMediaStreamFailure implements Exception {
  const _DriveMediaStreamFailure(this.error, this.stackTrace);

  final Object error;
  final StackTrace stackTrace;
}

class _InvalidManagedAttachmentMetadata implements Exception {
  const _InvalidManagedAttachmentMetadata();
}

class GoogleApisGoogleDriveSyncTransport
    implements
        GoogleDriveSyncTransport,
        LegacyGoogleDriveSyncKeyTransport,
        RemoteBundleMaintenanceTransport,
        RemoteAttachmentMaintenanceTransport {
  GoogleApisGoogleDriveSyncTransport({
    this.authConfig = const GoogleDriveAuthConfig(),
    this._driveApiProvider,
    http.Client? maintenanceClient,
  }) : _maintenanceClientOverride = maintenanceClient,
       _maintenanceClient = maintenanceClient;

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _bundleFileName = 'himemo_sync_bundle.enc';
  static const _bundleFilePrefix = 'himemo_sync_bundle_';
  static const _syncKeyFileName = 'himemo_sync_key_v1.json';
  static const _attachmentFilePrefix = 'himemo_sync_attachment_';
  static const _attachmentFileSuffix = '.encjson';
  static const _managedAttachmentPrefix = 'himemo_managed_attachment_';
  static const _managedKind = 'attachment-managed-v1';
  static final _secureRandom = Random.secure();
  static const _spaces = 'appDataFolder';
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final GoogleDriveAuthConfig authConfig;
  final Future<drive.DriveApi> Function()? _driveApiProvider;
  final http.Client? _maintenanceClientOverride;
  http.Client? _maintenanceClient;
  final Set<String> _legacyAttachmentIds = {};
  Map<String, List<drive.File>>? _managedAttachmentInventory;

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    final api = await _openDriveApi(interactive: false);
    final existing = await _findLatestBundle(api);
    if (existing == null) {
      return null;
    }
    return _toStatus(existing);
  }

  @override
  Future<List<RemoteSyncBundleStatus>> listBundleHistory({
    int limit = 10,
  }) async {
    final api = await _openDriveApi(interactive: false);
    final files = await _findBundleHistory(api, limit: limit);
    return files.map(_toStatus).toList(growable: false);
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
    final api = await _openDriveApi(interactive: false);
    final bytes = utf8.encode(encodedPayload);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final metadata = drive.File()
      ..name = '$_bundleFilePrefix$stamp.enc'
      ..parents = ['appDataFolder']
      ..appProperties = {
        'kind': 'bundle',
        'deviceId': deviceId,
        'noteCount': '$noteCount',
        'attachmentCount': '$attachmentCount',
        'bundleKind': bundleKind,
        'replayBaseFileId': ?replayBaseFileId,
      };

    final result = await _withDriveRetry(
      () => api.files.create(
        metadata,
        // Each attempt needs a fresh, single-subscription body stream.
        uploadMedia: drive.Media(Stream<List<int>>.value(bytes), bytes.length),
        $fields: 'id,name,modifiedTime,size,appProperties',
      ),
    );

    return _toStatus(result);
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
    final api = await _openDriveApi(interactive: false);
    if (!skipExistingCheck) {
      final existing = await _findAttachmentObject(api, contentHash);
      if (existing != null && existing.id != null && existing.id!.isNotEmpty) {
        return;
      }
    }
    final bytes = utf8.encode(encodedPayload);
    final metadata = drive.File()
      ..name = '$_attachmentFilePrefix$contentHash$_attachmentFileSuffix'
      ..parents = ['appDataFolder']
      ..appProperties = {
        'kind': 'attachment',
        'contentHash': contentHash,
        'type': type,
        'label': label,
        'sizeBytes': '$sizeBytes',
      };

    await _withDriveRetry(
      () => api.files.create(
        metadata,
        uploadMedia: drive.Media(Stream<List<int>>.value(bytes), bytes.length),
        $fields: 'id,name,modifiedTime,size,appProperties',
      ),
    );
  }

  @override
  Future<Set<String>> listAttachmentObjectContentHashes() async {
    final api = await _openDriveApi(interactive: false);
    return _listAttachmentObjectContentHashes(api);
  }

  @override
  Future<String?> downloadAttachmentObject(String contentHash) async {
    final api = await _openDriveApi(interactive: false);
    final managed = await _findManagedAttachments(api, contentHash);
    for (final file in managed) {
      if (file.id == null) continue;
      try {
        final snap = await _getManagedSnapshot(file.id!);
        if (snap != null && !snap.deleting) {
          return (await _downloadFile(api, file)).encodedPayload;
        }
      } on _InvalidManagedAttachmentMetadata {
        continue;
      }
    }
    final existing = await _findAttachmentObject(api, contentHash);
    if (existing == null || existing.id == null || existing.id!.isEmpty) {
      return null;
    }
    final downloaded = await _downloadFile(api, existing);
    return downloaded.encodedPayload;
  }

  @override
  Future<String> pinAttachmentObject({
    required String contentHash,
    required String uploadId,
    String? encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
  }) async {
    final api = await _openDriveApi(interactive: false);
    // Never turn an ordinary sync into an implicit byte-for-byte migration.
    // Legacy files remain unmanaged and are excluded from attachment GC.
    final legacy = await _findAttachmentObject(api, contentHash);
    if (legacy?.id case final id? when id.isNotEmpty) {
      _legacyAttachmentIds.add(id);
      return id;
    }
    for (var attempt = 0; attempt < 5; attempt++) {
      final inventory = _managedAttachmentInventory;
      final candidates = inventory == null
          ? await _findManagedAttachments(api, contentHash)
          : inventory[contentHash] ?? const <drive.File>[];
      var full = false;
      var conflict = false;
      var needsNewObject = candidates.isEmpty;
      for (final f in candidates) {
        final id = f.id;
        if (id == null || id.isEmpty) continue;
        ManagedAttachmentObject? snap;
        try {
          snap = await _getManagedSnapshot(id);
        } on _InvalidManagedAttachmentMetadata {
          needsNewObject = true;
          continue;
        }
        if (snap == null) {
          needsNewObject = true;
          continue;
        }
        if (snap.deleting) {
          needsNewObject = true;
          continue;
        }
        if (snap.uploadIds.contains(uploadId)) return id;
        if (snap.uploadIds.length >= 3) {
          full = true;
          continue;
        }
        final holds = {...snap.uploadIds, uploadId};
        final response = await _patchManaged(id, snap.revision, {
          'holds': jsonEncode(holds.toList()),
        });
        if (response == 412) {
          conflict = true;
          break;
        }
        if (response >= 200 && response < 300) return id;
        throw GoogleDriveSyncException(
          'Could not reserve the attachment.',
          statusCode: response,
        );
      }
      if (conflict) {
        _managedAttachmentInventory = null;
        continue;
      }
      final payload =
          encodedPayload ??
          await _downloadManagedCopy(api, candidates, contentHash) ??
          await downloadAttachmentObject(contentHash);
      if (payload == null) {
        throw StateError('Attachment payload is unavailable.');
      }
      // A full holder set means a new immutable object is required. A conflict
      // also restarts discovery before deciding whether another object fits.
      if (attempt == 4) break;
      if (full || needsNewObject) {
        final bytes = utf8.encode(payload);
        final nonce = List<int>.generate(16, (_) => _secureRandom.nextInt(256));
        final name =
            '$_managedAttachmentPrefix${base64Url.encode(nonce).replaceAll('=', '')}$_attachmentFileSuffix';
        final metadata = drive.File()
          ..name = name
          ..parents = ['appDataFolder']
          ..appProperties = {
            'kind': _managedKind,
            'contentHash': contentHash,
            'type': type,
            'label': label,
            'sizeBytes': '$sizeBytes',
            'holds': jsonEncode([uploadId]),
            'deleting': 'false',
            'protocol': '1',
          };
        final created = await _withDriveRetry(
          () => api.files.create(
            metadata,
            // A retry must get a fresh single-subscription upload stream.
            uploadMedia: drive.Media(
              Stream<List<int>>.value(bytes),
              bytes.length,
            ),
            $fields: 'id,name,modifiedTime,size,appProperties',
          ),
        );
        if (created.id == null || created.id!.isEmpty) {
          throw StateError('Drive returned no attachment ID.');
        }
        return created.id!;
      }
    }
    throw const GoogleDriveSyncException(
      'Attachment reservation changed repeatedly; retry sync.',
    );
  }

  @override
  Future<void> releaseAttachmentObject({
    required String recordId,
    required String uploadId,
    required String publishedBundleId,
  }) async {
    if (_legacyAttachmentIds.contains(recordId)) return;
    for (var attempt = 0; attempt < 5; attempt++) {
      final s = await _getManagedSnapshot(recordId);
      if (s == null || s.deleting) return;
      final holds = {...s.uploadIds}..remove(uploadId);
      final code = await _patchManaged(recordId, s.revision, {
        'holds': jsonEncode(holds.toList()),
        'lastBundle': publishedBundleId,
      });
      if (code == 412) continue;
      if (code >= 200 && code < 300) return;
      throw GoogleDriveSyncException(
        'Could not release the attachment reservation.',
        statusCode: code,
      );
    }
    throw const GoogleDriveSyncException(
      'Attachment reservation changed repeatedly; retry sync.',
    );
  }

  @override
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects() async {
    await _openDriveApi(interactive: false);
    final client = _maintenanceClient;
    if (client == null) {
      throw const GoogleDriveAuthConfigurationException(
        'Google Drive attachment maintenance is not authorized.',
      );
    }
    final out = <ManagedAttachmentObject>[];
    String? token;
    do {
      // v2 exposes etags in list results; capture them before the controller
      // scans bundle references, without issuing a GET per attachment.
      final uri = Uri.https('www.googleapis.com', '/drive/v2/files', {
        'spaces': _spaces,
        'q':
            "properties has { key='kind' and value='$_managedKind' and visibility='PRIVATE' } and trashed = false",
        'maxResults': '1000',
        'pageToken': ?token,
        'fields':
            'nextPageToken,items(id,etag,properties,modifiedDate,fileSize)',
      });
      final streamed = await client.send(http.Request('GET', uri));
      final response = await http.Response.fromStream(streamed);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw GoogleDriveSyncException(
          'Could not list managed attachments.',
          statusCode: response.statusCode,
        );
      }
      final body = _decodeResponseObject(response.body);
      final items = body['items'] ?? const <dynamic>[];
      if (items is! List) {
        throw const GoogleDriveSyncException('Invalid attachment inventory.');
      }
      for (final raw in items) {
        if (raw is! Map<String, dynamic>) continue;
        try {
          out.add(_managedSnapshotFromV2(raw));
        } on _InvalidManagedAttachmentMetadata {
          // Malformed objects are never eligible for deletion.
          continue;
        }
      }
      token = body['nextPageToken'] as String?;
    } while (token != null && token.isNotEmpty);
    // Discovery hints only: every mutation still obtains a fresh snapshot and
    // performs a conditional write. A concurrent 412 invalidates these hints.
    _managedAttachmentInventory = {};
    for (final item in out) {
      (_managedAttachmentInventory![item.contentHash] ??= []).add(
        drive.File()
          ..id = item.id
          ..size = item.sizeBytes.toString(),
      );
    }
    return out;
  }

  @override
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  ) async {
    ManagedAttachmentObject? s;
    try {
      s = await _getManagedSnapshot(candidate.id);
    } on _InvalidManagedAttachmentMetadata {
      return false;
    }
    if (s == null ||
        s.revision != candidate.revision ||
        s.uploadIds.isNotEmpty) {
      return false;
    }
    if (!s.deleting) {
      final code = await _patchManaged(candidate.id, s.revision, {
        'deleting': 'true',
      });
      if (code == 412) return false;
      if (code < 200 || code >= 300) {
        throw GoogleDriveSyncException(
          'Could not claim attachment for deletion.',
          statusCode: code,
        );
      }
    }
    ManagedAttachmentObject? again;
    try {
      again = await _getManagedSnapshot(candidate.id);
    } on _InvalidManagedAttachmentMetadata {
      return false;
    }
    if (again == null) return true;
    if (!again.deleting || again.uploadIds.isNotEmpty) return false;
    final del = await _maintenanceRequest(
      'DELETE',
      candidate.id,
      etag: again.revision,
    );
    if (del.statusCode == 404 ||
        (del.statusCode >= 200 && del.statusCode < 300)) {
      return true;
    }
    if (del.statusCode == 412) return false;
    throw GoogleDriveSyncException(
      'Could not delete managed attachment.',
      statusCode: del.statusCode,
    );
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    final api = await _openDriveApi(interactive: false);
    final existing = await _findLatestBundle(api);
    if (existing == null || existing.id == null || existing.id!.isEmpty) {
      return null;
    }
    return _downloadFile(api, existing);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(
    String fileId,
  ) async {
    final api = await _openDriveApi(interactive: false);
    if (fileId.isEmpty) {
      return null;
    }
    final response = await _withDriveRetry(
      () => api.files.get(
        fileId,
        $fields: 'id,name,modifiedTime,size,appProperties',
      ),
    ) as drive.File;
    if (response.id == null || response.id!.isEmpty) {
      return null;
    }
    return _downloadFile(api, response);
  }

  @override
  Future<List<String>> fetchSyncKeyBackupCodes() async {
    final api = await _openDriveApi(interactive: false);
    final files = await _findSyncKeyFiles(api);
    final backupCodes = <String>[];
    for (final file in files) {
      if (file.id == null || file.id!.isEmpty) {
        throw const FormatException('Legacy sync-key file has no ID.');
      }
      final downloaded = await _downloadFile(api, file);
      final decoded = jsonDecode(downloaded.encodedPayload);
      if (decoded is! Map) {
        throw const FormatException('Legacy sync-key file is malformed.');
      }
      final version = decoded['version'];
      final backupCode = decoded['backupCode'];
      if (version != 1 || backupCode is! String || backupCode.isEmpty) {
        throw const FormatException('Legacy sync-key file is malformed.');
      }
      backupCodes.add(backupCode);
    }
    return backupCodes;
  }

  @override
  Future<void> deleteSyncKeyBackupCode() async {
    final api = await _openDriveApi(interactive: false);
    final legacyFiles = await _findSyncKeyFiles(api);
    for (final file in legacyFiles) {
      final fileId = file.id;
      if (fileId == null || fileId.isEmpty) {
        continue;
      }
      await _withDriveRetry(() => api.files.delete(fileId));
    }
  }

  @override
  Future<void> deleteBundleFilesByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final api = await _openDriveApi(interactive: false);
    for (final id in ids) {
      if (id.isNotEmpty) await _withDriveRetry(() => api.files.delete(id));
    }
  }

  Future<DownloadedRemoteSyncBundle> _downloadFile(
    drive.DriveApi api,
    drive.File file,
  ) async {
    final bytes = await _withDriveRetry(() async {
      final response = await api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      );
      final media = response as drive.Media;
      final builder = BytesBuilder(copy: false);
      try {
        await for (final chunk in media.stream) {
          builder.add(chunk);
        }
      } on drive.ApiRequestError catch (error, stackTrace) {
        // googleapis wraps transport errors encountered after the response
        // headers arrive as ApiRequestError. While consuming a media stream,
        // these represent an incomplete transfer and are safe to retry.
        throw _DriveMediaStreamFailure(error, stackTrace);
      }
      return builder.takeBytes();
    });
    return DownloadedRemoteSyncBundle(
      status: _toStatus(file),
      encodedPayload: utf8.decode(bytes),
    );
  }

  Future<drive.DriveApi> _openDriveApi({required bool interactive}) async {
    final override = _driveApiProvider;
    if (override != null) return override();
    try {
      await GoogleSignInInitializer.ensureInitialized(authConfig);
      final cachedAuthorization = await GoogleSignIn
          .instance
          .authorizationClient
          .authorizationForScopes(const [scope]);
      if (cachedAuthorization != null) {
        final client = cachedAuthorization.authClient(scopes: const [scope]);
        _maintenanceClient = _maintenanceClientOverride ?? client;
        return drive.DriveApi(client);
      }
      if (!interactive) {
        return _authorizationUnavailable();
      }

      GoogleSignInAccount? account;
      final lightweight = GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (lightweight != null) {
        account = await lightweight;
      }
      if (account == null && interactive) {
        if (!GoogleSignIn.instance.supportsAuthenticate()) {
          throw const GoogleDriveAuthConfigurationException(
            'Google Drive authorization is not supported in this runtime. Configure the Google Sign-In SDK UI for web or use a supported native build.',
          );
        }
        account = await GoogleSignIn.instance.authenticate(
          scopeHint: const [scope],
        );
      }
      if (account == null) {
        return _authorizationUnavailable();
      }

      final authorizationClient = account.authorizationClient;
      final existingAuthorization = await authorizationClient
          .authorizationForScopes(const [scope]);
      final authorization =
          existingAuthorization ??
          (interactive
              ? await authorizationClient.authorizeScopes(const [scope])
              : null);
      if (authorization == null) {
        return _authorizationUnavailable();
      }

      final client = authorization.authClient(scopes: const [scope]);
      _maintenanceClient = _maintenanceClientOverride ?? client;
      return drive.DriveApi(client);
    } on PlatformException catch (error) {
      throw _mapPlatformException(error);
    } on GoogleSignInException catch (error) {
      throw _mapGoogleSignInException(error);
    }
  }

  Never _authorizationUnavailable() {
    throw const GoogleDriveAuthConfigurationException(
      'Google Drive authorization is not available. Connect Google Drive from Settings and confirm that Google Sign-In client IDs are configured for this build.',
    );
  }

  GoogleDriveAuthConfigurationException _mapPlatformException(
    PlatformException error,
  ) {
    final code = error.code;
    final message = error.message ?? error.details?.toString() ?? '$error';
    final needsClientId =
        message.contains('serverClientId') ||
        message.contains('clientID') ||
        message.contains('client ID') ||
        message.contains('configuration') ||
        code.toLowerCase().contains('configuration');
    if (needsClientId) {
      return GoogleDriveAuthConfigurationException(
        'Google Drive sign-in is not configured for this build. Add a Web OAuth client to google-services.json or pass --dart-define=HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID=... on Android. On iOS, set GIDClientID/URL scheme or pass --dart-define=HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID=...',
        error,
      );
    }
    return GoogleDriveAuthConfigurationException(
      'Google Drive sign-in failed before Drive access could be authorized.',
      error,
    );
  }

  GoogleDriveAuthConfigurationException _mapGoogleSignInException(
    GoogleSignInException error,
  ) {
    return switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        GoogleDriveAuthConfigurationException(
          'Google Drive sign-in is not configured for this build. Add OAuth clients for this app package/bundle and pass the Google Sign-In client IDs to the build.',
          error,
        ),
      GoogleSignInExceptionCode.canceled =>
        GoogleDriveAuthConfigurationException(
          'Google Drive sign-in was canceled.',
          error,
        ),
      GoogleSignInExceptionCode.uiUnavailable =>
        GoogleDriveAuthConfigurationException(
          'Google Drive sign-in UI is unavailable. Start authorization from the Settings screen while the app is in the foreground.',
          error,
        ),
      _ => GoogleDriveAuthConfigurationException(
        'Google Drive sign-in failed before Drive access could be authorized.',
        error,
      ),
    };
  }

  Future<drive.File?> _findLatestBundle(drive.DriveApi api) async {
    final files = await _findBundleHistory(api, limit: 1);
    if (files.isEmpty) {
      return null;
    }
    return files.first;
  }

  Future<List<drive.File>> _findSyncKeyFiles(drive.DriveApi api) async {
    final files = <drive.File>[];
    String? pageToken;
    do {
      final response = await _withDriveRetry(
        () => api.files.list(
          spaces: _spaces,
          q: "name = '$_syncKeyFileName' and trashed = false",
          orderBy: 'modifiedTime desc',
          pageSize: 1000,
          pageToken: pageToken,
          $fields:
              'nextPageToken,files(id,name,modifiedTime,size,appProperties)',
        ),
      );
      files.addAll(response.files ?? const <drive.File>[]);
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return files;
  }

  Future<drive.File?> _findAttachmentObject(
    drive.DriveApi api,
    String contentHash,
  ) async {
    final response = await _withDriveRetry(
      () => api.files.list(
        spaces: _spaces,
        q: "name = '$_attachmentFilePrefix$contentHash$_attachmentFileSuffix' and trashed = false",
        orderBy: 'modifiedTime desc',
        pageSize: 1,
        $fields: 'files(id,name,modifiedTime,size,appProperties)',
      ),
    );
    final files = response.files;
    if (files == null || files.isEmpty) {
      return null;
    }
    return files.first;
  }

  Future<Set<String>> _listAttachmentObjectContentHashes(
    drive.DriveApi api,
  ) async {
    final hashes = <String>{};
    String? pageToken;
    do {
      final response = await _withDriveRetry(
        () => api.files.list(
          spaces: _spaces,
          q: "name contains '$_attachmentFilePrefix' and trashed = false",
          pageSize: 1000,
          pageToken: pageToken,
          $fields: 'nextPageToken,files(name,appProperties)',
        ),
      );
      for (final file in response.files ?? const <drive.File>[]) {
        final hash =
            file.appProperties?['contentHash'] ??
            _contentHashFromAttachmentFileName(file.name);
        if (hash != null && hash.isNotEmpty) {
          hashes.add(hash);
        }
      }
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    final managed = await _findManagedAttachments(api, null);
    for (final file in managed) {
      if (file.id == null) continue;
      try {
        final snapshot = await _getManagedSnapshot(file.id!);
        if (snapshot != null && !snapshot.deleting) {
          hashes.add(snapshot.contentHash);
        }
      } on _InvalidManagedAttachmentMetadata {
        continue;
      }
    }
    return hashes;
  }

  Future<List<drive.File>> _findManagedAttachments(
    drive.DriveApi api,
    String? hash,
  ) async {
    final files = <drive.File>[];
    String? token;
    final hashFilter = hash == null
        ? ''
        : " and appProperties has { key='contentHash' and value='$hash' }";
    do {
      final r = await _withDriveRetry(
        () => api.files.list(
          spaces: _spaces,
          q: "appProperties has { key='kind' and value='$_managedKind' }$hashFilter and trashed = false",
          orderBy: 'modifiedTime desc',
          pageSize: 1000,
          pageToken: token,
          $fields:
              'nextPageToken,files(id,name,modifiedTime,size,appProperties)',
        ),
      );
      files.addAll(r.files ?? const <drive.File>[]);
      token = r.nextPageToken;
    } while (token != null && token.isNotEmpty);
    return files;
  }

  Future<ManagedAttachmentObject?> _getManagedSnapshot(String id) async {
    final r = await _maintenanceRequest('GET', id);
    if (r.statusCode == 404) return null;
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw GoogleDriveSyncException(
        'Could not inspect managed attachment.',
        statusCode: r.statusCode,
      );
    }
    return _managedSnapshotFromV2(_decodeResponseObject(r.body));
  }

  ManagedAttachmentObject _managedSnapshotFromV2(Map<String, dynamic> body) {
    final id = body['id'];
    final etag = body['etag'];
    if (id is! String || id.isEmpty || etag is! String || etag.isEmpty) {
      throw const _InvalidManagedAttachmentMetadata();
    }
    final props = _validatedManagedProperties(
      body['appProperties'] ?? _privatePropertiesFromV2(body['properties']),
    );
    final holds = jsonDecode(props['holds']!);
    return ManagedAttachmentObject(
      id: id,
      contentHash: props['contentHash']!,
      revision: etag,
      modifiedAt: DateTime.tryParse(body['modifiedDate']?.toString() ?? '')
          ?.toUtc(),
      uploadIds: holds is List ? holds.whereType<String>().toSet() : <String>{},
      lastPublishedBundleId: props['lastBundle'],
      deleting: props['deleting'] == 'true',
      sizeBytes: int.tryParse(body['fileSize']?.toString() ?? '') ?? 0,
    );
  }

  Map<String, String> _privatePropertiesFromV2(Object? raw) {
    final properties = <String, String>{};
    if (raw is List) {
      for (final property in raw) {
        if (property is Map &&
            property['visibility'] == 'PRIVATE' &&
            property['key'] is String &&
            property['value'] is String) {
          properties[property['key'] as String] = property['value'] as String;
        }
      }
    }
    return properties;
  }

  Future<int> _patchManaged(
    String id,
    String etag,
    Map<String, String> changes,
  ) async {
    final current = await _maintenanceRequest('GET', id);
    if (current.statusCode == 404) return 404;
    if (current.statusCode < 200 || current.statusCode >= 300) {
      throw GoogleDriveSyncException(
        'Could not inspect managed attachment.',
        statusCode: current.statusCode,
      );
    }
    final body = _decodeResponseObject(current.body);
    if ((body['etag']?.toString() ?? '') != etag) return 412;
    final existing = _validatedManagedProperties(body['appProperties']);
    existing.addAll(changes);
    final r = await _maintenanceRequest(
      'PATCH',
      id,
      etag: etag,
      body: {'appProperties': existing},
    );
    return r.statusCode;
  }

  Map<String, String> _validatedManagedProperties(Object? raw) {
    if (raw is! Map) throw const _InvalidManagedAttachmentMetadata();
    final props = <String, String>{};
    for (final entry in raw.entries) {
      if (entry.key is! String || entry.value is! String) {
        throw const _InvalidManagedAttachmentMetadata();
      }
      props[entry.key as String] = entry.value as String;
    }
    if (props['kind'] != _managedKind ||
        props['protocol'] != '1' ||
        (props['contentHash']?.isNotEmpty ?? false) == false ||
        (props['deleting'] != 'true' && props['deleting'] != 'false')) {
      throw const _InvalidManagedAttachmentMetadata();
    }
    final encodedHolds = props['holds'];
    if (encodedHolds == null) throw const _InvalidManagedAttachmentMetadata();
    Object? decoded;
    try {
      decoded = jsonDecode(encodedHolds);
    } on FormatException {
      throw const _InvalidManagedAttachmentMetadata();
    }
    if (decoded is! List || decoded.any((e) => e is! String)) {
      throw const _InvalidManagedAttachmentMetadata();
    }
    final holders = decoded.cast<String>();
    if (holders.length > 3 || holders.toSet().length != holders.length) {
      throw const _InvalidManagedAttachmentMetadata();
    }
    return props;
  }

  Future<String?> _downloadManagedCopy(
    drive.DriveApi api,
    List<drive.File> candidates,
    String contentHash,
  ) async {
    for (final file in candidates) {
      final id = file.id;
      if (id == null || id.isEmpty) continue;
      try {
        final snap = await _getManagedSnapshot(id);
        if (snap == null || snap.contentHash != contentHash) continue;
        // Deleting is a reuse barrier, but its immutable content remains a
        // valid source for cloning into a new reserved object.
        return (await _downloadFile(api, file)).encodedPayload;
      } on _InvalidManagedAttachmentMetadata {
        continue;
      } on GoogleDriveSyncException catch (error) {
        if (error.statusCode == 404) continue;
        rethrow;
      }
    }
    return null;
  }

  Future<http.Response> _maintenanceRequest(
    String method,
    String id, {
    String? etag,
    Object? body,
  }) async {
    final client = _maintenanceClient;
    if (client == null) {
      throw const GoogleDriveAuthConfigurationException(
        'Google Drive attachment maintenance is not authorized.',
      );
    }
    final uri = Uri.https(
      'www.googleapis.com',
      '/drive/v2/files/$id',
      method == 'GET'
          ? {'fields': 'id,etag,properties,modifiedDate,fileSize'}
          : null,
    );
    final req = http.Request(method, uri);
    if (etag != null) req.headers['If-Match'] = etag;
    if (body != null) {
      req.headers['Content-Type'] = 'application/json';
      final appProperties = (body as Map<String, Object?>)['appProperties'];
      if (appProperties is Map<String, String>) {
        req.body = jsonEncode({
          'properties': appProperties.entries
              .map(
                (e) => {
                  'key': e.key,
                  'value': e.value,
                  'visibility': 'PRIVATE',
                },
              )
              .toList(growable: false),
        });
      } else {
        req.body = jsonEncode(body);
      }
    }
    final streamed = await client.send(req);
    final response = await http.Response.fromStream(streamed);
    if (method != 'GET' ||
        response.statusCode < 200 ||
        response.statusCode >= 300) {
      return response;
    }
    final decoded = _decodeResponseObject(response.body);
    final privateProperties = <String, String>{};
    final properties = decoded['properties'];
    if (properties is List) {
      for (final property in properties) {
        if (property is Map &&
            property['visibility'] == 'PRIVATE' &&
            property['key'] is String &&
            property['value'] is String) {
          privateProperties[property['key'] as String] =
              property['value'] as String;
        }
      }
    }
    decoded['appProperties'] = privateProperties;
    return http.Response(
      jsonEncode(decoded),
      response.statusCode,
      headers: response.headers,
    );
  }

  Map<String, dynamic> _decodeResponseObject(String source) {
    try {
      final decoded = jsonDecode(source);
      if (decoded is Map<String, dynamic>) return decoded;
    } on FormatException {
      throw const _InvalidManagedAttachmentMetadata();
    }
    throw const _InvalidManagedAttachmentMetadata();
  }

  String? _contentHashFromAttachmentFileName(String? name) {
    if (name == null ||
        !name.startsWith(_attachmentFilePrefix) ||
        !name.endsWith(_attachmentFileSuffix)) {
      return null;
    }
    return name.substring(
      _attachmentFilePrefix.length,
      name.length - _attachmentFileSuffix.length,
    );
  }

  Future<List<drive.File>> _findBundleHistory(
    drive.DriveApi api, {
    int limit = 10,
  }) async {
    if (limit <= 0) return const <drive.File>[];
    final files = <drive.File>[];
    String? pageToken;
    do {
      final remaining = limit - files.length;
      final response = await _withDriveRetry(
        () => api.files.list(
          spaces: _spaces,
          q: "trashed = false and (appProperties has { key='kind' and value='bundle' } or name = '$_bundleFileName' or name contains '$_bundleFilePrefix')",
          orderBy: 'modifiedTime desc',
          pageSize: remaining.clamp(1, 1000).toInt(),
          pageToken: pageToken,
          $fields:
              'nextPageToken,files(id,name,modifiedTime,size,appProperties)',
        ),
      );
      files.addAll(response.files ?? const <drive.File>[]);
      if (files.length >= limit) break;
      pageToken = response.nextPageToken;
    } while (pageToken != null && pageToken.isNotEmpty);
    return files.take(limit).toList(growable: false);
  }

  RemoteSyncBundleStatus _toStatus(drive.File file) {
    final appProperties = file.appProperties ?? const <String, String>{};
    return RemoteSyncBundleStatus(
      fileId: file.id ?? '',
      fileName: file.name ?? _bundleFileName,
      modifiedAt: file.modifiedTime?.toUtc(),
      sizeBytes: file.size == null ? null : int.tryParse(file.size!),
      noteCount: int.tryParse(appProperties['noteCount'] ?? ''),
      attachmentCount: int.tryParse(appProperties['attachmentCount'] ?? ''),
      deviceId: appProperties['deviceId'],
      bundleKind: appProperties['bundleKind'],
      replayBaseFileId: appProperties['replayBaseFileId'],
    );
  }

  Future<T> _withDriveRetry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        return await operation();
      } on _DriveMediaStreamFailure catch (failure) {
        if (attempt >= _retryDelays.length) {
          Error.throwWithStackTrace(failure.error, failure.stackTrace);
        }
        await Future<void>.delayed(_retryDelays[attempt]);
      } on drive.DetailedApiRequestError catch (error) {
        final mapped = _mapDriveApiError(error);
        if (attempt >= _retryDelays.length || !_isRetryable(mapped, error)) {
          throw mapped;
        }
        await Future<void>.delayed(_retryDelays[attempt]);
      } on drive.ApiRequestError catch (error) {
        final mapped = GoogleDriveSyncException(
          'Google Drive request failed. Check your connection and try again.',
          details: error,
        );
        throw mapped;
      } on SocketException {
        if (attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt]);
      } on HttpException {
        if (attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt]);
      } on TimeoutException {
        if (attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt]);
      } on ClientException {
        if (attempt >= _retryDelays.length) rethrow;
        await Future<void>.delayed(_retryDelays[attempt]);
      }
    }
    throw const GoogleDriveSyncException('Google Drive request failed.');
  }

  bool _isRetryable(
    GoogleDriveSyncException mapped,
    drive.DetailedApiRequestError error,
  ) {
    final status = error.status;
    final message = (error.message ?? '').toLowerCase();
    if (status == 429 || status == 500 || status == 503 || status == 504) {
      return true;
    }
    if (status == 403 &&
        (message.contains('userratelimit') || message.contains('ratelimit')) &&
        !message.contains('dailylimit') &&
        !message.contains('quotaexceeded')) {
      return true;
    }
    return mapped.isRateLimited && status != 403;
  }

  GoogleDriveSyncException _mapDriveApiError(
    drive.DetailedApiRequestError error,
  ) {
    final status = error.status;
    final rawMessage = error.message ?? '';
    final normalized = rawMessage.toLowerCase();
    final isRateLimited =
        status == 429 ||
        normalized.contains('ratelimit') ||
        normalized.contains('quota') ||
        normalized.contains('limitexceeded');
    if (isRateLimited) {
      return GoogleDriveSyncException(
        'Google Drive is temporarily limiting sync requests. Please wait a few minutes and try again.',
        statusCode: status,
        retryAfter: const Duration(minutes: 2),
        isRateLimited: true,
        details: error,
      );
    }
    if (status == 401 || status == 403) {
      return GoogleDriveSyncException(
        'Google Drive access was denied. Reconnect Google Drive from Settings and try again.',
        statusCode: status,
        details: error,
      );
    }
    if (status == 500 || status == 503 || status == 504) {
      return GoogleDriveSyncException(
        'Google Drive is temporarily unavailable. Please try again shortly.',
        statusCode: status,
        retryAfter: const Duration(minutes: 1),
        details: error,
      );
    }
    return GoogleDriveSyncException(
      'Google Drive request failed. Please try again.',
      statusCode: status,
      details: error,
    );
  }
}
