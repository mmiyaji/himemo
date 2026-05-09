import 'dart:async';
import 'dart:convert';

import 'package:extension_google_sign_in_as_googleapis_auth/extension_google_sign_in_as_googleapis_auth.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/drive/v3.dart' as drive;

import 'google_sign_in_initializer.dart';
import 'sync_bundle_key_service.dart';

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

  Future<List<RemoteSyncBundleStatus>> listBundleHistory({int limit = 10});

  Future<RemoteSyncBundleStatus> uploadBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  });

  Future<DownloadedRemoteSyncBundle?> downloadLatestBundle();

  Future<DownloadedRemoteSyncBundle?> downloadBundleByFileId(String fileId);

  Future<String?> fetchSyncKeyBackupCode();

  Future<void> uploadSyncKeyBackupCode(String backupCode);
}

class GoogleDriveCloudSyncBundleKeyStore implements CloudSyncBundleKeyStore {
  GoogleDriveCloudSyncBundleKeyStore(this.transport);

  final GoogleDriveSyncTransport transport;

  @override
  Future<String?> readBackupCode() => transport.fetchSyncKeyBackupCode();

  @override
  Future<void> writeBackupCode(String backupCode) {
    return transport.uploadSyncKeyBackupCode(backupCode);
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

class GoogleApisGoogleDriveSyncTransport implements GoogleDriveSyncTransport {
  GoogleApisGoogleDriveSyncTransport({
    this.authConfig = const GoogleDriveAuthConfig(),
  });

  static const scope = 'https://www.googleapis.com/auth/drive.appdata';
  static const _bundleFileName = 'himemo_sync_bundle.enc';
  static const _bundleFilePrefix = 'himemo_sync_bundle_';
  static const _syncKeyFileName = 'himemo_sync_key_v1.json';
  static const _spaces = 'appDataFolder';
  static const _retryDelays = <Duration>[
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
  ];

  final GoogleDriveAuthConfig authConfig;

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
  }) async {
    final api = await _openDriveApi(interactive: false);
    final bytes = utf8.encode(encodedPayload);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(':', '-');
    final metadata = drive.File()
      ..name = '$_bundleFilePrefix$stamp.enc'
      ..parents = ['appDataFolder']
      ..appProperties = {
        'deviceId': deviceId,
        'noteCount': '$noteCount',
        'attachmentCount': '$attachmentCount',
      };

    final result = await _withDriveRetry(
      () => api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,size,appProperties',
      ),
    );

    return _toStatus(result);
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
    final response =
        await _withDriveRetry(
              () => api.files.get(
                fileId,
                $fields: 'id,name,modifiedTime,size,appProperties',
              ),
            )
            as drive.File;
    if (response.id == null || response.id!.isEmpty) {
      return null;
    }
    return _downloadFile(api, response);
  }

  @override
  Future<String?> fetchSyncKeyBackupCode() async {
    final api = await _openDriveApi(interactive: false);
    final file = await _findSyncKeyFile(api);
    if (file == null || file.id == null || file.id!.isEmpty) {
      return null;
    }
    final downloaded = await _downloadFile(api, file);
    final decoded = jsonDecode(downloaded.encodedPayload);
    if (decoded is! Map) {
      return null;
    }
    final version = decoded['version'];
    final backupCode = decoded['backupCode'];
    if (version != 1 || backupCode is! String || backupCode.isEmpty) {
      return null;
    }
    return backupCode;
  }

  @override
  Future<void> uploadSyncKeyBackupCode(String backupCode) async {
    final api = await _openDriveApi(interactive: false);
    final existing = await _findSyncKeyFile(api);
    final payload = jsonEncode({
      'version': 1,
      'backupCode': backupCode,
      'updatedAt': DateTime.now().toUtc().toIso8601String(),
    });
    final bytes = utf8.encode(payload);
    final media = drive.Media(Stream<List<int>>.value(bytes), bytes.length);
    final metadata = drive.File()
      ..name = _syncKeyFileName
      ..parents = ['appDataFolder'];

    if (existing?.id != null && existing!.id!.isNotEmpty) {
      await _withDriveRetry(
        () => api.files.update(
          metadata,
          existing.id!,
          uploadMedia: media,
          $fields: 'id,name,modifiedTime,size',
        ),
      );
      return;
    }

    await _withDriveRetry(
      () => api.files.create(
        metadata,
        uploadMedia: media,
        $fields: 'id,name,modifiedTime,size',
      ),
    );
  }

  Future<DownloadedRemoteSyncBundle> _downloadFile(
    drive.DriveApi api,
    drive.File file,
  ) async {
    final response = await _withDriveRetry(
      () => api.files.get(
        file.id!,
        downloadOptions: drive.DownloadOptions.fullMedia,
      ),
    );
    final media = response as drive.Media;
    final chunks = await _withDriveRetry(media.stream.toList);
    final bytes = chunks.expand((chunk) => chunk).toList(growable: false);
    return DownloadedRemoteSyncBundle(
      status: _toStatus(file),
      encodedPayload: utf8.decode(bytes),
    );
  }

  Future<drive.DriveApi> _openDriveApi({required bool interactive}) async {
    try {
      await GoogleSignInInitializer.ensureInitialized(authConfig);
      final cachedAuthorization = await GoogleSignIn
          .instance
          .authorizationClient
          .authorizationForScopes(const [scope]);
      if (cachedAuthorization != null) {
        return drive.DriveApi(
          cachedAuthorization.authClient(scopes: const [scope]),
        );
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
      GoogleSignInExceptionCode
          .providerConfigurationError => GoogleDriveAuthConfigurationException(
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

  Future<drive.File?> _findSyncKeyFile(drive.DriveApi api) async {
    final response = await _withDriveRetry(
      () => api.files.list(
        spaces: _spaces,
        q: "name = '$_syncKeyFileName' and trashed = false",
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

  Future<List<drive.File>> _findBundleHistory(
    drive.DriveApi api, {
    int limit = 10,
  }) async {
    final response = await _withDriveRetry(
      () => api.files.list(
        spaces: _spaces,
        q: "name = '$_bundleFileName' or name contains '$_bundleFilePrefix'",
        orderBy: 'modifiedTime desc',
        pageSize: limit,
        $fields: 'files(id,name,modifiedTime,size,appProperties)',
      ),
    );
    final files = response.files;
    if (files == null || files.isEmpty) {
      return const <drive.File>[];
    }
    return files;
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
    );
  }

  Future<T> _withDriveRetry<T>(Future<T> Function() operation) async {
    for (var attempt = 0; attempt <= _retryDelays.length; attempt += 1) {
      try {
        return await operation();
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
        if (attempt >= _retryDelays.length) {
          throw mapped;
        }
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
