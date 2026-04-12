import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

class RemoteSyncBundleStatus {
  const RemoteSyncBundleStatus({
    required this.fileId,
    required this.fileName,
    this.modifiedAt,
    this.sizeBytes,
    this.noteCount,
    this.attachmentCount,
    this.deviceId,
  });

  final String fileId;
  final String fileName;
  final DateTime? modifiedAt;
  final int? sizeBytes;
  final int? noteCount;
  final int? attachmentCount;
  final String? deviceId;
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

  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  });

  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle();
}

class GoogleApisGoogleDriveSyncTransport implements GoogleDriveSyncTransport {
  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _bundleFileName = 'himemo_sync_bundle.enc';
  static const _spaces = 'appDataFolder';

  @override
  Future<RemoteSyncBundleStatus?> fetchLatestBundleStatus() async {
    final api = await _openDriveApi(interactive: false);
    final existing = await _findExistingBundle(api);
    if (existing == null) {
      return null;
    }
    return _toStatus(existing);
  }

  @override
  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) async {
    final api = await _openDriveApi(interactive: true);
    final existing = await _findExistingBundle(api);
    final bytes = utf8.encode(encodedPayload);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final metadata = drive.File()
      ..name = _bundleFileName
      ..parents = ['appDataFolder']
      ..appProperties = {
        'deviceId': deviceId,
        'noteCount': '$noteCount',
        'attachmentCount': '$attachmentCount',
      };

    final result = existing == null
        ? await api.files.create(
            metadata,
            uploadMedia: media,
            $fields: 'id,name,modifiedTime,size,appProperties',
          )
        : await api.files.update(
            metadata,
            existing.id!,
            uploadMedia: media,
            $fields: 'id,name,modifiedTime,size,appProperties',
          );

    return _toStatus(result);
  }

  @override
  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle() async {
    final api = await _openDriveApi(interactive: true);
    final existing = await _findExistingBundle(api);
    if (existing == null || existing.id == null || existing.id!.isEmpty) {
      return null;
    }
    final response = await api.files.get(
      existing.id!,
      downloadOptions: drive.DownloadOptions.fullMedia,
    );
    final media = response as drive.Media;
    final chunks = await media.stream.toList();
    final bytes = chunks.expand((chunk) => chunk).toList(growable: false);
    return DownloadedRemoteSyncBundle(
      status: _toStatus(existing),
      encodedPayload: utf8.decode(bytes),
    );
  }

  Future<drive.DriveApi> _openDriveApi({required bool interactive}) async {
    await GoogleSignIn.instance.initialize();
    final authorizationClient = GoogleSignIn.instance.authorizationClient;
    final authorization = interactive
        ? await authorizationClient.authorizeScopes([scope])
        : await authorizationClient.authorizationForScopes([scope]);
    if (authorization == null) {
      throw StateError('Google Drive authorization is not available.');
    }

    final client = authorization.authClient(scopes: const [scope]);
    return drive.DriveApi(client);
  }

  Future<drive.File?> _findExistingBundle(drive.DriveApi api) async {
    final response = await api.files.list(
      spaces: _spaces,
      q: "name = '$_bundleFileName'",
      orderBy: 'modifiedTime desc',
      pageSize: 1,
      $fields: 'files(id,name,modifiedTime,size,appProperties)',
    );
    final files = response.files;
    if (files == null || files.isEmpty) {
      return null;
    }
    return files.first;
  }

  RemoteSyncBundleStatus _toStatus(drive.File file) {
    final appProperties = file.appProperties ?? const <String, String>{};
    return RemoteSyncBundleStatus(
      fileId: file.id ?? '',
      fileName: file.name ?? _bundleFileName,
      modifiedAt: file.modifiedTime,
      sizeBytes: file.size == null ? null : int.tryParse(file.size!),
      noteCount: int.tryParse(appProperties['noteCount'] ?? ''),
      attachmentCount: int.tryParse(appProperties['attachmentCount'] ?? ''),
      deviceId: appProperties['deviceId'],
    );
  }
}
