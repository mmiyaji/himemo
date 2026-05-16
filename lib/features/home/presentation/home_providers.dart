import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as path;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/firebase_observability.dart';
import '../../../app/app_flavor.dart';
import '../../../app/audit_log.dart';
import '../../../app/diagnostic_log.dart';
import '../../../app/in_app_update_service.dart';
import '../../../app/network_connection.dart';
import '../../../app/play_integrity_service.dart';
import '../../../app/play_integrity_verifier.dart';
import '../data/home_repository.dart';
import '../domain/note_entry.dart';
import '../domain/note_tags.dart';
import '../domain/vault_models.dart';
import 'video_thumbnail_generator_stub.dart'
    if (dart.library.io) 'video_thumbnail_generator_io.dart'
    if (dart.library.html) 'video_thumbnail_generator_web.dart';
import '../../security/data/device_identity_store.dart';
import '../../security/data/encrypted_note_store.dart';
import '../../security/data/encrypted_note_database.dart';
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/master_key_service.dart';
import '../../security/data/profile_data_key_service.dart';
import '../../security/data/private_vault_secret_store.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../sync/data/google_drive_sync_transport.dart';
import '../../sync/data/google_sign_in_initializer.dart';
import '../../sync/data/icloud_sync_transport.dart';
import '../../sync/data/sync_conflict_policy.dart';
import '../../sync/data/sync_bundle_preview.dart';
import '../../sync/data/secure_sync_bundle_store.dart';
import '../../sync/data/sync_bundle_key_service.dart';
import '../../sync/data/sync_bundle_state_store.dart';
import '../../sync/data/sync_engine.dart';
import 'media_duration_stub.dart' if (dart.library.io) 'media_duration_io.dart';

part 'home_providers.g.dart';

void _debugHomePerf(String message) {
  if (!kDebugMode) {
    return;
  }
  debugPrint('[home-perf] ${DateTime.now().toIso8601String()} $message');
}

enum AppColorTheme {
  konjyo,
  moegi,
  yamabuki,
  ginnezumi,
  seiheki,
  kurenai,
  sakura,
  fuji,
  ai,
  kurumi,
  chigusa,
  sumire,
  sumi,
  shironeri,
  gofun,
  enji,
  hanada,
  sora,
  ruri,
  asagi,
  wakatake,
  tokiwa,
  byakuroku,
  nanohana,
  haizakura,
  akane,
  kikyo,
  edomurasaki,
  shion,
  rikyucha,
}

AppColorTheme? _appColorThemeFromName(String? value) {
  if (value == null) {
    return null;
  }
  const legacyNames = {
    'blue': AppColorTheme.konjyo,
    'green': AppColorTheme.moegi,
    'orange': AppColorTheme.yamabuki,
    'slate': AppColorTheme.ginnezumi,
    'teal': AppColorTheme.seiheki,
    'rose': AppColorTheme.kurenai,
  };
  final legacy = legacyNames[value];
  if (legacy != null) {
    return legacy;
  }
  for (final theme in AppColorTheme.values) {
    if (theme.name == value) {
      return theme;
    }
  }
  return null;
}

({String title, String body}) _splitExternalCaptureText(
  String rawText,
  List<QuickCaptureFile> validFiles,
) {
  final text = rawText.trim();
  final lines = const LineSplitter()
      .convert(text)
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList(growable: false);
  final title = lines.isEmpty
      ? (validFiles.length == 1 ? validFiles.single.name : 'Shared attachments')
      : lines.first;
  return (title: title, body: lines.skip(1).join('\n'));
}

enum AppLocaleSetting {
  system,
  japanese,
  english,
  chinese,
  korean,
  spanish,
  german,
}

enum AppFontFamily {
  system,
  gothic,
  uiGothic,
  kakuGothic,
  mincho,
  uiMincho,
  rounded,
  zenRounded,
  casual,
  monospace,
}

const iOSFriendlyAppFontFamilies = <AppFontFamily>{
  AppFontFamily.system,
  AppFontFamily.gothic,
  AppFontFamily.mincho,
  AppFontFamily.rounded,
  AppFontFamily.monospace,
};

enum NotesListDensity { standard, compact }

enum AttachmentPreviewFit { preview, icon }

enum NotesListSortField { updatedAt, createdAt }

enum SyncProvider { off, iCloud, googleDrive }

bool get isICloudSyncSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum AppLaunchSurface { onboarding, ready }

enum AppLockRelockDelay { immediate, seconds30, minutes2, minutes10 }

enum DeviceAuthAvailability { unknown, available, unavailable }

enum SyncAuthStage { idle, busy, authenticated, unsupported, error }

enum SyncTransferStage { idle, busy, success, error }

enum SyncTransferProgress {
  none,
  checkingRemote,
  preparingBundle,
  uploadingBundle,
  downloadingBundle,
  applyingBundle,
  finalizing,
}

const legacyPrivateVaultId = 'private';
const customPrivateVaultPrefix = 'private_profile:';

bool isPrivateVaultId(String vaultId) {
  return vaultId == legacyPrivateVaultId ||
      vaultId.startsWith(customPrivateVaultPrefix);
}

bool isGeneratedSampleNote(NoteEntry note) {
  return note.deviceId == 'seeded-device' ||
      note.id.startsWith('seed-') ||
      note.deviceId == 'performance-seed' ||
      note.id.startsWith('perf-') ||
      (note.contentHash?.startsWith('performance-seed-') ?? false);
}

@visibleForTesting
bool remoteBundleNeedsApplyForSync(
  RemoteSyncBundleStatus remoteStatus,
  SyncBundleState bundleState,
) {
  final lastAppliedAt = bundleState.lastAppliedAt;
  final lastUploadedAt = bundleState.lastUploadedAt;
  final knownActionAt = _latestDateTime(lastAppliedAt, lastUploadedAt);
  if (knownActionAt == null) {
    return true;
  }
  final remoteModifiedAt = remoteStatus.modifiedAt?.toUtc();
  if (remoteModifiedAt == null) {
    return bundleState.lastRemoteFileId != remoteStatus.fileId &&
        lastAppliedAt == null;
  }
  if (remoteModifiedAt.isAfter(knownActionAt)) {
    return true;
  }
  return remoteStatus.fileId.isNotEmpty &&
      bundleState.lastRemoteFileId != remoteStatus.fileId;
}

DateTime? _latestDateTime(DateTime? left, DateTime? right) {
  if (left == null) {
    return right?.toUtc();
  }
  if (right == null) {
    return left.toUtc();
  }
  final leftUtc = left.toUtc();
  final rightUtc = right.toUtc();
  return leftUtc.isAfter(rightUtc) ? leftUtc : rightUtc;
}

class PrivateMemoProfile {
  const PrivateMemoProfile({
    required this.id,
    required this.name,
    required this.createdAt,
  });

  final String id;
  final String name;
  final DateTime createdAt;

  String get vaultId => '$customPrivateVaultPrefix$id';

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'createdAt': createdAt.toIso8601String(),
  };

  factory PrivateMemoProfile.fromJson(Map<String, dynamic> json) {
    return PrivateMemoProfile(
      id: json['id'] as String,
      name: json['name'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class UnlockProfileResult {
  const UnlockProfileResult({
    required this.vaultId,
    required this.label,
    required this.isLegacy,
  });

  final String vaultId;
  final String label;
  final bool isLegacy;
}

class AppPackageDetails {
  const AppPackageDetails({
    required this.appName,
    required this.version,
    required this.buildNumber,
  });

  final String appName;
  final String version;
  final String buildNumber;

  String get displayVersion => '$version ($buildNumber)';
}

enum SearchDateRange { all, last7Days, last30Days, thisMonth }

enum SearchDateField { createdAt, updatedAt }

enum SearchAttachmentFilter { all, any, photo, video, audio, location }

class SearchFilters {
  const SearchFilters({
    this.pinnedOnly = false,
    this.withMediaOnly = false,
    this.attachmentFilters = const <SearchAttachmentFilter>[],
    this.archivedOnly = false,
    this.includeArchived = false,
    this.requireAllTags = false,
    this.dateRange = SearchDateRange.all,
    this.dateField = SearchDateField.createdAt,
    this.vaultId,
    this.year,
    this.tags = const <String>[],
  });

  final bool pinnedOnly;
  final bool withMediaOnly;
  final List<SearchAttachmentFilter> attachmentFilters;
  SearchAttachmentFilter get attachmentFilter => attachmentFilters.isEmpty
      ? SearchAttachmentFilter.all
      : attachmentFilters.first;
  final bool archivedOnly;
  final bool includeArchived;
  final bool requireAllTags;
  final SearchDateRange dateRange;
  final SearchDateField dateField;
  final String? vaultId;
  final int? year;
  final List<String> tags;

  bool get isDefault =>
      !pinnedOnly &&
      !withMediaOnly &&
      attachmentFilters.isEmpty &&
      !archivedOnly &&
      !includeArchived &&
      !requireAllTags &&
      dateRange == SearchDateRange.all &&
      dateField == SearchDateField.createdAt &&
      (vaultId == null || vaultId!.isEmpty) &&
      year == null &&
      tags.isEmpty;

  SearchFilters copyWith({
    bool? pinnedOnly,
    bool? withMediaOnly,
    List<SearchAttachmentFilter>? attachmentFilters,
    bool? archivedOnly,
    bool? includeArchived,
    bool? requireAllTags,
    SearchDateRange? dateRange,
    SearchDateField? dateField,
    String? vaultId,
    int? year,
    List<String>? tags,
    bool clearVault = false,
    bool clearYear = false,
  }) {
    return SearchFilters(
      pinnedOnly: pinnedOnly ?? this.pinnedOnly,
      withMediaOnly: withMediaOnly ?? this.withMediaOnly,
      attachmentFilters: attachmentFilters ?? this.attachmentFilters,
      archivedOnly: archivedOnly ?? this.archivedOnly,
      includeArchived: includeArchived ?? this.includeArchived,
      requireAllTags: requireAllTags ?? this.requireAllTags,
      dateRange: dateRange ?? this.dateRange,
      dateField: dateField ?? this.dateField,
      vaultId: clearVault ? null : (vaultId ?? this.vaultId),
      year: clearYear ? null : (year ?? this.year),
      tags: tags ?? this.tags,
    );
  }
}

class LastNoteEditorSettings {
  const LastNoteEditorSettings({
    this.mode = NoteEditorMode.rich,
    this.vaultId = 'everyday',
    this.captureLocation = false,
  });

  final NoteEditorMode mode;
  final String vaultId;
  final bool captureLocation;
}

enum QuickCaptureSource { widget, share }

class QuickCaptureFile {
  const QuickCaptureFile({
    required this.path,
    required this.name,
    required this.mimeType,
  });

  final String path;
  final String name;
  final String mimeType;

  AttachmentType? get attachmentType {
    final normalized = mimeType.toLowerCase();
    if (normalized.startsWith('image/')) {
      return AttachmentType.photo;
    }
    if (normalized.startsWith('video/')) {
      return AttachmentType.video;
    }
    if (normalized.startsWith('audio/')) {
      return AttachmentType.audio;
    }
    return AttachmentType.file;
  }

  static QuickCaptureFile fromJson(Map<String, dynamic> json) {
    return QuickCaptureFile(
      path: '${json['path'] ?? ''}',
      name: '${json['name'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
    );
  }
}

class QuickCaptureRejectedFile {
  const QuickCaptureRejectedFile({
    required this.name,
    required this.mimeType,
    required this.reason,
  });

  final String name;
  final String mimeType;
  final String reason;

  static QuickCaptureRejectedFile fromJson(Map<String, dynamic> json) {
    return QuickCaptureRejectedFile(
      name: '${json['name'] ?? ''}',
      mimeType: '${json['mimeType'] ?? ''}',
      reason: '${json['reason'] ?? ''}',
    );
  }
}

class QuickCaptureRequest {
  const QuickCaptureRequest({
    required this.nonce,
    required this.source,
    this.initialText = '',
    this.files = const <QuickCaptureFile>[],
    this.rejectedFiles = const <QuickCaptureRejectedFile>[],
  });

  final String nonce;
  final QuickCaptureSource source;
  final String initialText;
  final List<QuickCaptureFile> files;
  final List<QuickCaptureRejectedFile> rejectedFiles;
}

class WidgetQuickCaptureBridge {
  WidgetQuickCaptureBridge(this._onOpenRequested);

  static const MethodChannel _channel = MethodChannel(
    'org.ruhenheim.himemo/widget',
  );

  final void Function(QuickCaptureRequest request) _onOpenRequested;
  bool _attached = false;

  void attach() {
    if (_attached ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openQuickCapture') {
        final arguments = Map<String, dynamic>.from(
          (call.arguments as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        );
        _onOpenRequested(_requestFromArguments(arguments));
      }
    });
    unawaited(_consumePendingRequest());
  }

  Future<void> _consumePendingRequest() async {
    try {
      final pending = await _channel.invokeMethod<dynamic>(
        'consumePendingQuickCapture',
      );
      if (pending is bool) {
        if (pending) {
          _onOpenRequested(
            QuickCaptureRequest(
              nonce: DateTime.now().microsecondsSinceEpoch.toString(),
              source: QuickCaptureSource.widget,
            ),
          );
        }
        return;
      }
      if (pending is Map) {
        _onOpenRequested(
          _requestFromArguments(Map<String, dynamic>.from(pending.cast())),
        );
      }
    } catch (_) {}
  }

  Future<void> deleteImportedFiles(List<QuickCaptureFile> files) async {
    if (files.isEmpty ||
        kIsWeb ||
        (defaultTargetPlatform != TargetPlatform.android &&
            defaultTargetPlatform != TargetPlatform.iOS)) {
      return;
    }
    try {
      await _channel.invokeMethod<void>(
        'deleteSharedImportFiles',
        <String, Object?>{
          'paths': [for (final file in files) file.path],
        },
      );
    } catch (_) {}
  }

  QuickCaptureRequest _requestFromArguments(Map<String, dynamic> arguments) {
    final sourceValue = '${arguments['source'] ?? 'widget'}';
    final source = sourceValue == 'share'
        ? QuickCaptureSource.share
        : QuickCaptureSource.widget;
    final initialText = '${arguments['text'] ?? ''}'.trim();
    final files = (arguments['files'] as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map>()
        .map(
          (entry) =>
              QuickCaptureFile.fromJson(Map<String, dynamic>.from(entry)),
        )
        .where((file) => file.path.isNotEmpty && file.attachmentType != null)
        .toList(growable: false);
    final rejectedFiles =
        (arguments['rejectedFiles'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map>()
            .map(
              (entry) => QuickCaptureRejectedFile.fromJson(
                Map<String, dynamic>.from(entry),
              ),
            )
            .where((file) => file.name.isNotEmpty || file.reason.isNotEmpty)
            .toList(growable: false);
    return QuickCaptureRequest(
      nonce: '${arguments['nonce'] ?? DateTime.now().microsecondsSinceEpoch}'
          .trim(),
      source: source,
      initialText: initialText,
      files: files,
      rejectedFiles: rejectedFiles,
    );
  }
}

class NoteEditorDraftSnapshot {
  const NoteEditorDraftSnapshot({
    required this.createdAt,
    required this.isPinned,
    required this.editorMode,
    required this.vaultId,
    required this.tags,
    required this.quickContent,
    required this.quickAttachments,
    required this.richBlocks,
    this.location,
  });

  final DateTime createdAt;
  final bool isPinned;
  final NoteEditorMode editorMode;
  final String vaultId;
  final List<String> tags;
  final String quickContent;
  final List<NoteAttachment> quickAttachments;
  final List<NoteBlock> richBlocks;
  final NoteLocation? location;

  Map<String, dynamic> toJson() => {
    'createdAt': createdAt.toIso8601String(),
    'isPinned': isPinned,
    'editorMode': editorMode.name,
    'vaultId': vaultId,
    'tags': tags,
    'quickContent': quickContent,
    'quickAttachments': quickAttachments.map((e) => e.toJson()).toList(),
    'richBlocks': richBlocks.map((e) => e.toJson()).toList(),
    'location': location?.toJson(),
  };

  static NoteEditorDraftSnapshot fromJson(Map<String, dynamic> json) {
    return NoteEditorDraftSnapshot(
      createdAt: DateTime.parse(json['createdAt'] as String),
      isPinned: json['isPinned'] as bool? ?? false,
      editorMode: NoteEditorMode.values.byName(
        json['editorMode'] as String? ?? NoteEditorMode.rich.name,
      ),
      vaultId: json['vaultId'] as String? ?? 'everyday',
      tags: dedupeNoteTags(
        (json['tags'] as List<dynamic>? ?? const []).whereType<String>(),
      ),
      quickContent: json['quickContent'] as String? ?? '',
      quickAttachments: (json['quickAttachments'] as List<dynamic>? ?? const [])
          .map(
            (entry) => NoteAttachment.fromJson(
              Map<String, dynamic>.from(entry as Map),
            ),
          )
          .toList(growable: false),
      richBlocks: (json['richBlocks'] as List<dynamic>? ?? const [])
          .map(
            (entry) =>
                NoteBlock.fromJson(Map<String, dynamic>.from(entry as Map)),
          )
          .toList(growable: false),
      location: json['location'] == null
          ? null
          : NoteLocation.fromJson(
              Map<String, dynamic>.from(json['location'] as Map),
            ),
    );
  }
}

enum MediaImportAction {
  takePhoto,
  pickPhoto,
  recordVideo,
  pickVideo,
  recordAudio,
  pickAudio,
  pickFile,
  addLocation,
}

class MediaImportResult {
  const MediaImportResult._({
    this.attachment,
    this.attachments = const <NoteAttachment>[],
    this.errorMessage,
    required this.wasCancelled,
    this.deferredPreviews = const <String, Future<String?>>{},
  });

  const MediaImportResult.success(NoteAttachment attachment)
    : this._(
        attachment: attachment,
        attachments: const <NoteAttachment>[],
        wasCancelled: false,
      );

  MediaImportResult.successWithDeferredPreview(
    NoteAttachment attachment, {
    required Map<String, Future<String?>> deferredPreviews,
  }) : this._(
         attachment: attachment,
         attachments: const <NoteAttachment>[],
         wasCancelled: false,
         deferredPreviews: deferredPreviews,
       );

  MediaImportResult.successManyWithDeferredPreviews(
    List<NoteAttachment> attachments, {
    required Map<String, Future<String?>> deferredPreviews,
  }) : this._(
         attachments: attachments,
         wasCancelled: false,
         deferredPreviews: deferredPreviews,
       );

  const MediaImportResult.successMany(List<NoteAttachment> attachments)
    : this._(attachments: attachments, wasCancelled: false);

  const MediaImportResult.cancelled()
    : this._(wasCancelled: true, attachment: null, errorMessage: null);

  const MediaImportResult.failure(String errorMessage)
    : this._(attachment: null, errorMessage: errorMessage, wasCancelled: false);

  final NoteAttachment? attachment;
  final List<NoteAttachment> attachments;
  final String? errorMessage;
  final bool wasCancelled;

  /// Keyed by attachment filePath; value resolves to preview base64.
  final Map<String, Future<String?>> deferredPreviews;

  List<NoteAttachment> get allAttachments {
    if (attachments.isNotEmpty) {
      return attachments;
    }
    final single = attachment;
    return single == null ? const <NoteAttachment>[] : <NoteAttachment>[single];
  }
}

const _deferredVideoPreviewThresholdBytes = 32 * 1024 * 1024;

Future<int?> _mediaDurationMs({
  required AttachmentType type,
  required XFile sourceFile,
}) async {
  if (kIsWeb || sourceFile.path.isEmpty) {
    return null;
  }
  return switch (type) {
    AttachmentType.audio => probeAudioDurationMs(sourceFile.path),
    AttachmentType.video => probeVideoDurationMs(sourceFile.path),
    _ => null,
  };
}

Future<int?> _sourceFileLength(XFile sourceFile) async {
  try {
    return await sourceFile.length();
  } catch (_) {
    return null;
  }
}

Future<String?> _videoPreviewBytesBase64ForSourceFile(XFile sourceFile) async {
  try {
    final bytes = await generateVideoThumbnailBytes(sourceFile);
    if (bytes == null || bytes.isEmpty) {
      return null;
    }
    return base64Encode(bytes);
  } catch (error) {
    debugPrint('Video thumbnail generation failed: $error');
    return null;
  }
}

Future<String?> _videoPreviewBytesBase64ForBytes(
  List<int> bytes, {
  required String label,
  String? mimeType,
}) {
  if (bytes.isEmpty) {
    return Future.value(null);
  }
  return _videoPreviewBytesBase64ForSourceFile(
    XFile.fromData(Uint8List.fromList(bytes), name: label, mimeType: mimeType),
  );
}

class DeviceAuthState {
  const DeviceAuthState({
    required this.availability,
    required this.methods,
    this.lastError,
    this.isAuthenticating = false,
  });

  const DeviceAuthState.unknown()
    : availability = DeviceAuthAvailability.unknown,
      methods = const [],
      lastError = null,
      isAuthenticating = false;

  final DeviceAuthAvailability availability;
  final List<String> methods;
  final String? lastError;
  final bool isAuthenticating;

  bool get isAvailable => availability == DeviceAuthAvailability.available;

  String get summary {
    if (isAuthenticating) {
      return 'Waiting for device authentication...';
    }
    if (isAvailable && methods.isNotEmpty) {
      return methods.join(', ');
    }
    if (isAvailable) {
      return 'Device credential available';
    }
    if (lastError != null && lastError!.isNotEmpty) {
      return lastError!;
    }
    return 'Biometric or device credential is not available on this device.';
  }

  DeviceAuthState copyWith({
    DeviceAuthAvailability? availability,
    List<String>? methods,
    String? lastError,
    bool clearLastError = false,
    bool? isAuthenticating,
  }) {
    return DeviceAuthState(
      availability: availability ?? this.availability,
      methods: methods ?? this.methods,
      lastError: clearLastError ? null : (lastError ?? this.lastError),
      isAuthenticating: isAuthenticating ?? this.isAuthenticating,
    );
  }
}

class AppPinLockState {
  const AppPinLockState({required this.isConfigured, this.lastError});

  const AppPinLockState.unconfigured() : isConfigured = false, lastError = null;

  final bool isConfigured;
  final String? lastError;

  String get summary {
    if (isConfigured) {
      return 'An unlock PIN is configured for this app.';
    }
    return lastError ?? 'No unlock PIN is configured yet.';
  }

  AppPinLockState copyWith({
    bool? isConfigured,
    String? lastError,
    bool clearError = false,
  }) {
    return AppPinLockState(
      isConfigured: isConfigured ?? this.isConfigured,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class AppPinLockStore {
  AppPinLockStore({required EncryptionService encryptionService})
    : _encryptionService = encryptionService;

  static const _storageKey = 'settings.web_app_pin.v1';

  final EncryptionService _encryptionService;

  Future<bool> hasPin() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey);
    return payload != null && payload.isNotEmpty;
  }

  Future<void> configure(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: pin,
      salt: salt,
    );
    await prefs.setString(
      _storageKey,
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
  }

  Future<bool> verify(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey);
    if (payload == null || payload.isEmpty) {
      return false;
    }
    final decoded = Map<String, dynamic>.from(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    final salt = base64Decode(decoded['salt'] as String);
    final storedVerifier = decoded['verifier'] as String;
    final incomingVerifier = await _encryptionService.deriveSecretVerifier(
      secret: pin,
      salt: salt,
    );
    return _constantTimeEquals(storedVerifier, incomingVerifier);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }

  bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var diff = leftBytes.length ^ rightBytes.length;
    final limit = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var i = 0; i < limit; i++) {
      final a = i < leftBytes.length ? leftBytes[i] : 0;
      final b = i < rightBytes.length ? rightBytes[i] : 0;
      diff |= a ^ b;
    }
    return diff == 0;
  }
}

class SecretVerifierStore {
  SecretVerifierStore({
    required SecureKeyValueStore secureStore,
    required EncryptionService encryptionService,
    required this.storageKey,
  }) : _secureStore = secureStore,
       _encryptionService = encryptionService;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final String storageKey;

  Future<bool> hasSecret() async {
    final payload = await _secureStore.read(storageKey);
    return payload != null && payload.isNotEmpty;
  }

  Future<void> configure(String secret) async {
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: salt,
    );
    await _secureStore.write(
      storageKey,
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
  }

  Future<bool> verify(String secret) async {
    final payload = await _secureStore.read(storageKey);
    if (payload == null || payload.isEmpty) {
      return false;
    }
    final decoded = Map<String, dynamic>.from(
      jsonDecode(payload) as Map<String, dynamic>,
    );
    final salt = base64Decode(decoded['salt'] as String);
    final verifier = decoded['verifier'] as String;
    final incomingVerifier = await _encryptionService.deriveSecretVerifier(
      secret: secret,
      salt: salt,
    );
    return _constantTimeEquals(verifier, incomingVerifier);
  }

  Future<void> clear() => _secureStore.delete(storageKey);

  bool _constantTimeEquals(String left, String right) {
    final leftBytes = utf8.encode(left);
    final rightBytes = utf8.encode(right);
    var diff = leftBytes.length ^ rightBytes.length;
    final limit = leftBytes.length > rightBytes.length
        ? leftBytes.length
        : rightBytes.length;
    for (var i = 0; i < limit; i++) {
      final a = i < leftBytes.length ? leftBytes[i] : 0;
      final b = i < rightBytes.length ? rightBytes[i] : 0;
      diff |= a ^ b;
    }
    return diff == 0;
  }
}

class SyncAuthState {
  const SyncAuthState({
    required this.provider,
    required this.stage,
    this.userId,
    this.displayName,
    this.email,
    this.message,
  });

  const SyncAuthState.idle(this.provider)
    : stage = SyncAuthStage.idle,
      userId = null,
      displayName = null,
      email = null,
      message = null;

  final SyncProvider provider;
  final SyncAuthStage stage;
  final String? userId;
  final String? displayName;
  final String? email;
  final String? message;

  bool get isAuthenticated => stage == SyncAuthStage.authenticated;

  SyncAuthState copyWith({
    SyncProvider? provider,
    SyncAuthStage? stage,
    String? userId,
    String? displayName,
    String? email,
    String? message,
    bool clearMessage = false,
  }) {
    return SyncAuthState(
      provider: provider ?? this.provider,
      stage: stage ?? this.stage,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      message: clearMessage ? null : (message ?? this.message),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'provider': provider.name,
      'stage': stage.name,
      'userId': userId,
      'displayName': displayName,
      'email': email,
      'message': message,
    };
  }

  static SyncAuthState fromJson(Map<String, dynamic> json) {
    final provider = SyncProvider.values.firstWhere(
      (value) => value.name == json['provider'],
      orElse: () => SyncProvider.off,
    );
    final stage = SyncAuthStage.values.firstWhere(
      (value) => value.name == json['stage'],
      orElse: () => SyncAuthStage.idle,
    );
    return SyncAuthState(
      provider: provider,
      stage: stage,
      userId: json['userId'] as String?,
      displayName: json['displayName'] as String?,
      email: json['email'] as String?,
      message: json['message'] as String?,
    );
  }
}

class SyncTransferState {
  const SyncTransferState({
    required this.stage,
    this.progress = SyncTransferProgress.none,
    this.message,
    this.detail,
    this.completedItems,
    this.totalItems,
    this.remoteStatus,
    this.localBundle,
    this.cooldownUntil,
  });

  const SyncTransferState.idle()
    : stage = SyncTransferStage.idle,
      progress = SyncTransferProgress.none,
      message = null,
      detail = null,
      completedItems = null,
      totalItems = null,
      remoteStatus = null,
      localBundle = null,
      cooldownUntil = null;

  final SyncTransferStage stage;
  final SyncTransferProgress progress;
  final String? message;
  final String? detail;
  final int? completedItems;
  final int? totalItems;
  final RemoteSyncBundleStatus? remoteStatus;
  final StoredSyncBundle? localBundle;
  final DateTime? cooldownUntil;

  bool get isBusy => stage == SyncTransferStage.busy || isCoolingDown;

  bool get isCoolingDown {
    final until = cooldownUntil;
    return until != null && DateTime.now().isBefore(until);
  }

  SyncTransferState copyWith({
    SyncTransferStage? stage,
    SyncTransferProgress? progress,
    String? message,
    String? detail,
    int? completedItems,
    int? totalItems,
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
    DateTime? cooldownUntil,
    bool clearMessage = false,
    bool clearDetail = false,
    bool clearCooldown = false,
    bool clearLocalBundle = false,
  }) {
    return SyncTransferState(
      stage: stage ?? this.stage,
      progress:
          progress ??
          (stage != null && stage != SyncTransferStage.busy
              ? SyncTransferProgress.none
              : this.progress),
      message: clearMessage ? null : (message ?? this.message),
      detail: clearDetail || (stage != null && stage != SyncTransferStage.busy)
          ? null
          : (detail ?? this.detail),
      completedItems:
          clearDetail || (stage != null && stage != SyncTransferStage.busy)
          ? null
          : (completedItems ?? this.completedItems),
      totalItems:
          clearDetail || (stage != null && stage != SyncTransferStage.busy)
          ? null
          : (totalItems ?? this.totalItems),
      remoteStatus: remoteStatus ?? this.remoteStatus,
      localBundle: clearLocalBundle ? null : (localBundle ?? this.localBundle),
      cooldownUntil: clearCooldown
          ? null
          : (cooldownUntil ?? this.cooldownUntil),
    );
  }
}

enum LargeSyncTransferDirection { upload, download }

class LargeSyncTransferWarning {
  const LargeSyncTransferWarning({
    required this.direction,
    required this.bytes,
    required this.thresholdBytes,
  });

  final LargeSyncTransferDirection direction;
  final int bytes;
  final int thresholdBytes;
}

class DiagnosticLogSnapshot {
  const DiagnosticLogSnapshot({required this.enabled, required this.entries});

  final bool enabled;
  final List<String> entries;

  String get text => entries.join('\n');
}

class AuditLogSnapshot {
  const AuditLogSnapshot({required this.entries});

  final List<String> entries;

  String get text => entries.join('\n');
}

class LocalNoteArchive {
  const LocalNoteArchive({
    required this.bytes,
    required this.fileName,
    required this.noteCount,
    required this.attachmentCount,
    required this.isPasswordProtected,
  });

  final Uint8List bytes;
  final String fileName;
  final int noteCount;
  final int attachmentCount;
  final bool isPasswordProtected;
}

class _DecodedLocalZipArchive {
  const _DecodedLocalZipArchive({
    required this.manifest,
    required this.notes,
    required this.attachmentFiles,
  });

  final Map<String, dynamic> manifest;
  final List<Map<String, dynamic>> notes;
  final Map<String, Uint8List> attachmentFiles;
}

class _LocalArchiveFilePayload {
  const _LocalArchiveFilePayload({required this.name, required this.bytes});

  final String name;
  final TransferableTypedData bytes;
}

class _LocalZipEncodeRequest {
  const _LocalZipEncodeRequest({
    required this.manifest,
    required this.notes,
    required this.files,
    this.password,
  });

  final Map<String, dynamic> manifest;
  final List<Map<String, dynamic>> notes;
  final List<_LocalArchiveFilePayload> files;
  final String? password;
}

class _LocalZipDecodeRequest {
  const _LocalZipDecodeRequest({required this.bytes, this.password});

  final TransferableTypedData bytes;
  final String? password;
}

enum InAppUpdateStage {
  idle,
  checking,
  ready,
  updating,
  completed,
  unsupported,
  error,
}

class InAppUpdateState {
  const InAppUpdateState({required this.stage, this.status, this.message});

  const InAppUpdateState.idle()
    : stage = InAppUpdateStage.idle,
      status = null,
      message = null;

  final InAppUpdateStage stage;
  final InAppUpdateStatus? status;
  final String? message;

  bool get isBusy =>
      stage == InAppUpdateStage.checking || stage == InAppUpdateStage.updating;

  InAppUpdateState copyWith({
    InAppUpdateStage? stage,
    InAppUpdateStatus? status,
    String? message,
    bool clearMessage = false,
  }) {
    return InAppUpdateState(
      stage: stage ?? this.stage,
      status: status ?? this.status,
      message: clearMessage ? null : (message ?? this.message),
    );
  }
}

abstract class DeviceAuthGateway {
  Future<DeviceAuthState> checkAvailability();

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  });
}

class LocalDeviceAuthGateway implements DeviceAuthGateway {
  LocalDeviceAuthGateway({LocalAuthentication? localAuth})
    : _localAuth = localAuth ?? LocalAuthentication();

  final LocalAuthentication _localAuth;

  @override
  Future<DeviceAuthState> checkAvailability() async {
    if (kIsWeb) {
      return const DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: [],
        lastError: 'Device authentication is not available on web.',
      );
    }

    try {
      final supported = await _localAuth.isDeviceSupported();
      final biometrics = await _localAuth.getAvailableBiometrics();
      final methods = biometrics.map(_labelForBiometric).toSet().toList()
        ..sort();
      return DeviceAuthState(
        availability: supported
            ? DeviceAuthAvailability.available
            : DeviceAuthAvailability.unavailable,
        methods: methods,
      );
    } on MissingPluginException {
      return const DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: [],
        lastError:
            'Device authentication plugin is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: const [],
        lastError: error.message ?? error.code,
      );
    } catch (error) {
      return DeviceAuthState(
        availability: DeviceAuthAvailability.unavailable,
        methods: const [],
        lastError: '$error',
      );
    }
  }

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    if (kIsWeb) {
      return false;
    }

    try {
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: biometricOnly,
        persistAcrossBackgrounding: true,
      );
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    } catch (_) {
      return false;
    }
  }

  String _labelForBiometric(BiometricType type) {
    switch (type) {
      case BiometricType.face:
        return 'Face ID';
      case BiometricType.fingerprint:
        return 'Fingerprint';
      case BiometricType.iris:
        return 'Iris';
      case BiometricType.strong:
        return 'Strong biometrics';
      case BiometricType.weak:
        return 'Weak biometrics';
    }
  }
}

abstract class SyncAuthGateway {
  Future<SyncAuthState> connect(SyncProvider provider);

  Future<void> disconnect(SyncProvider provider);
}

const _useFakeGoogleDriveSync = bool.fromEnvironment(
  'HIMEMO_FAKE_GOOGLE_DRIVE_SYNC',
);

bool get useFakeGoogleDriveSync => _useFakeGoogleDriveSync;

class FakeGoogleDriveSyncAuthGateway implements SyncAuthGateway {
  FakeGoogleDriveSyncAuthGateway({required SyncAuthGateway fallback})
    : _fallback = fallback;

  final SyncAuthGateway _fallback;

  @override
  Future<SyncAuthState> connect(SyncProvider provider) {
    if (provider != SyncProvider.googleDrive) {
      return _fallback.connect(provider);
    }
    return Future.value(
      const SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.authenticated,
        userId: 'fake-google-drive-user',
        displayName: 'Fake Google Drive',
        email: 'fake-google-drive@example.test',
        message: 'Fake Google Drive sync is connected for local testing.',
      ),
    );
  }

  @override
  Future<void> disconnect(SyncProvider provider) {
    if (provider != SyncProvider.googleDrive) {
      return _fallback.disconnect(provider);
    }
    return Future<void>.value();
  }
}

class DefaultSyncAuthGateway implements SyncAuthGateway {
  DefaultSyncAuthGateway({
    this.googleDriveAuthConfig = const GoogleDriveAuthConfig(),
  });

  static const _googleScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];

  final GoogleDriveAuthConfig googleDriveAuthConfig;

  @override
  Future<SyncAuthState> connect(SyncProvider provider) {
    return switch (provider) {
      SyncProvider.off => Future.value(SyncAuthState.idle(provider)),
      SyncProvider.googleDrive => _connectGoogle(),
      SyncProvider.iCloud => _connectICloud(),
    };
  }

  @override
  Future<void> disconnect(SyncProvider provider) async {
    try {
      if (provider == SyncProvider.googleDrive) {
        await _ensureGoogleInitialized();
        await GoogleSignIn.instance.disconnect();
      }
    } catch (_) {}
  }

  Future<void> _ensureGoogleInitialized() async {
    await GoogleSignInInitializer.ensureInitialized(googleDriveAuthConfig);
  }

  Future<SyncAuthState> _connectGoogle() async {
    try {
      await _ensureGoogleInitialized();
      GoogleSignInAccount? account;
      final lightweight = GoogleSignIn.instance
          .attemptLightweightAuthentication();
      if (lightweight != null) {
        account = await lightweight;
      }
      if (account == null) {
        if (!GoogleSignIn.instance.supportsAuthenticate()) {
          return const SyncAuthState(
            provider: SyncProvider.googleDrive,
            stage: SyncAuthStage.unsupported,
            message:
                'Google sign-in on this platform needs explicit client ID setup and a user-triggered SDK button.',
          );
        }
        account = await GoogleSignIn.instance.authenticate(
          scopeHint: _googleScopes,
        );
      }

      final existingAuthorization = await account.authorizationClient
          .authorizationForScopes(_googleScopes);
      if (existingAuthorization == null) {
        await account.authorizationClient.authorizeScopes(_googleScopes);
      }

      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.authenticated,
        userId: account.id,
        displayName: account.displayName,
        email: account.email,
        message: 'Google Drive app-data access is authorized.',
      );
    } on MissingPluginException {
      return const SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.unsupported,
        message: 'Google sign-in plugin is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.error,
        message: _googleDrivePlatformExceptionMessage(error),
      );
    } on GoogleSignInException catch (error) {
      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.error,
        message: _googleDriveSignInExceptionMessage(error),
      );
    } on GoogleDriveAuthConfigurationException catch (error) {
      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.error,
        message: error.message,
      );
    } catch (error) {
      return SyncAuthState(
        provider: SyncProvider.googleDrive,
        stage: SyncAuthStage.error,
        message: '$error',
      );
    }
  }

  Future<SyncAuthState> _connectICloud() async {
    if (!isICloudSyncSupported) {
      return const SyncAuthState(
        provider: SyncProvider.iCloud,
        stage: SyncAuthStage.unsupported,
        message: 'iCloud sync is currently available on iPhone and iPad only.',
      );
    }

    return const SyncAuthState(
      provider: SyncProvider.iCloud,
      stage: SyncAuthStage.authenticated,
      displayName: 'iCloud',
      message: 'iCloud is selected as this device sync target.',
    );
  }

  String _googleDrivePlatformExceptionMessage(PlatformException error) {
    final code = error.code;
    final message = error.message ?? error.details?.toString() ?? '$error';
    final needsClientId =
        message.contains('serverClientId') ||
        message.contains('clientID') ||
        message.contains('client ID') ||
        message.contains('configuration') ||
        code.toLowerCase().contains('configuration');
    if (needsClientId) {
      return 'Google Drive sign-in is not configured for this build. Add a Web OAuth client to google-services.json or pass --dart-define=HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID=... on Android. On iOS, set GIDClientID/URL scheme or pass --dart-define=HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID=...';
    }
    return 'Google Drive sign-in failed: $message';
  }

  String _googleDriveSignInExceptionMessage(GoogleSignInException error) {
    return switch (error.code) {
      GoogleSignInExceptionCode.clientConfigurationError ||
      GoogleSignInExceptionCode.providerConfigurationError =>
        'Google Drive sign-in is not configured for this build. Add OAuth clients for this app package/bundle and pass the Google Sign-In client IDs to the build.',
      GoogleSignInExceptionCode.canceled =>
        'Google Drive sign-in was canceled.',
      GoogleSignInExceptionCode.uiUnavailable =>
        'Google Drive sign-in UI is unavailable. Start authorization from the Settings screen while the app is in the foreground.',
      _ =>
        'Google Drive sign-in failed: ${error.description ?? error.toString()}',
    };
  }
}

abstract class MediaImportService {
  Future<MediaImportResult> importAttachment(
    MediaImportAction action, {
    VoidCallback? onProcessingStarted,
  });
}

class DefaultMediaImportService implements MediaImportService {
  DefaultMediaImportService({required EncryptedAttachmentStore attachmentStore})
    : _attachmentStore = attachmentStore;

  final EncryptedAttachmentStore _attachmentStore;

  @override
  Future<MediaImportResult> importAttachment(
    MediaImportAction action, {
    VoidCallback? onProcessingStarted,
  }) async {
    switch (action) {
      case MediaImportAction.takePhoto:
        return _pickPhoto(
          ImageSource.camera,
          onProcessingStarted: onProcessingStarted,
        );
      case MediaImportAction.pickPhoto:
        return _pickPhoto(
          ImageSource.gallery,
          onProcessingStarted: onProcessingStarted,
        );
      case MediaImportAction.recordVideo:
        return _pickVideo(
          ImageSource.camera,
          onProcessingStarted: onProcessingStarted,
        );
      case MediaImportAction.pickVideo:
        return _pickVideo(
          ImageSource.gallery,
          onProcessingStarted: onProcessingStarted,
        );
      case MediaImportAction.recordAudio:
        return const MediaImportResult.failure(
          'Audio recording is handled by the note editor.',
        );
      case MediaImportAction.pickAudio:
        return _pickAudio(onProcessingStarted: onProcessingStarted);
      case MediaImportAction.pickFile:
        return _pickFile(onProcessingStarted: onProcessingStarted);
      case MediaImportAction.addLocation:
        return const MediaImportResult.failure(
          'Location capture is handled by the note editor.',
        );
    }
  }

  Future<MediaImportResult> _pickPhoto(
    ImageSource source, {
    VoidCallback? onProcessingStarted,
  }) async {
    if (source == ImageSource.gallery) {
      return _pickMediaFiles(
        type: AttachmentType.photo,
        pickerType: FileType.image,
        maxBytes: 25 * 1024 * 1024,
        tooLargeMessage: 'Photos over 25 MB are not supported yet.',
        openFailureMessage:
            'The selected photo could not be opened on this device.',
        importNotConfiguredMessage:
            'Photo import is not configured in this runtime.',
        importFailedPrefix: 'Photo import failed on this device.',
        onProcessingStarted: onProcessingStarted,
      );
    }
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = await picker.pickImage(
        source: source,
        imageQuality: 88,
        maxWidth: 1800,
      );
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Photo import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Photo import failed on this device.',
      );
    }
    if (picked == null) {
      return const MediaImportResult.cancelled();
    }
    onProcessingStarted?.call();
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 25 * 1024 * 1024,
      tooLargeMessage: 'Photos over 25 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    final result = await _buildAttachment(
      type: AttachmentType.photo,
      sourceFile: picked,
    );
    return MediaImportResult.success(result.attachment);
  }

  Future<MediaImportResult> _pickVideo(
    ImageSource source, {
    VoidCallback? onProcessingStarted,
  }) async {
    if (source == ImageSource.gallery) {
      return _pickMediaFiles(
        type: AttachmentType.video,
        pickerType: FileType.video,
        maxBytes: 200 * 1024 * 1024,
        tooLargeMessage: 'Videos over 200 MB are not supported yet.',
        openFailureMessage:
            'The selected video could not be opened on this device.',
        importNotConfiguredMessage:
            'Video import is not configured in this runtime.',
        importFailedPrefix: 'Video import failed on this device.',
        onProcessingStarted: onProcessingStarted,
      );
    }
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = await picker.pickVideo(source: source);
      picked ??= await _recoverLostVideoCapture(picker);
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Video import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Video import failed on this device.',
      );
    }
    if (picked == null) {
      return const MediaImportResult.cancelled();
    }
    onProcessingStarted?.call();
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 200 * 1024 * 1024,
      tooLargeMessage: 'Videos over 200 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    try {
      final result = await _buildAttachment(
        type: AttachmentType.video,
        sourceFile: picked,
      );
      if (result.deferredPreview != null) {
        return MediaImportResult.successWithDeferredPreview(
          result.attachment,
          deferredPreviews: {
            result.attachment.filePath!: result.deferredPreview!,
          },
        );
      }
      return MediaImportResult.success(result.attachment);
    } catch (error) {
      return MediaImportResult.failure(
        'The recorded video could not be attached on this device. ($error)',
      );
    }
  }

  Future<XFile?> _recoverLostVideoCapture(ImagePicker picker) async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return null;
    }
    try {
      final response = await picker.retrieveLostData();
      if (response.isEmpty) {
        return null;
      }
      final exception = response.exception;
      if (exception != null) {
        throw exception;
      }
      final files = response.files;
      if (files != null && files.isNotEmpty) {
        return files.last;
      }
      return response.file;
    } on PlatformException {
      rethrow;
    } catch (error) {
      debugPrint('Video capture lost data recovery failed: $error');
      return null;
    }
  }

  Future<MediaImportResult> _pickMediaFiles({
    required AttachmentType type,
    required FileType pickerType,
    required int maxBytes,
    required String tooLargeMessage,
    required String openFailureMessage,
    required String importNotConfiguredMessage,
    required String importFailedPrefix,
    VoidCallback? onProcessingStarted,
  }) async {
    if (!kIsWeb &&
        defaultTargetPlatform == TargetPlatform.iOS &&
        (type == AttachmentType.photo || type == AttachmentType.video)) {
      return _pickIOSPhotoLibraryMedia(
        type: type,
        maxBytes: maxBytes,
        tooLargeMessage: tooLargeMessage,
        openFailureMessage: openFailureMessage,
        importNotConfiguredMessage: importNotConfiguredMessage,
        importFailedPrefix: importFailedPrefix,
        onProcessingStarted: onProcessingStarted,
      );
    }
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(
        type: pickerType,
        allowMultiple: true,
        withData: kIsWeb,
      );
    } on MissingPluginException {
      return MediaImportResult.failure(importNotConfiguredMessage);
    } on PlatformException catch (error) {
      return MediaImportResult.failure(error.message ?? importFailedPrefix);
    } catch (error) {
      return MediaImportResult.failure('$importFailedPrefix ($error)');
    }
    if (result == null || result.files.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final attachments = <NoteAttachment>[];
    final deferredPreviews = <String, Future<String?>>{};
    for (final file in result.files) {
      final sourceFile = _xFileFromPlatformFile(file);
      if (sourceFile == null) {
        return MediaImportResult.failure(openFailureMessage);
      }
      final bytes = file.bytes;
      if (bytes != null && bytes.length > maxBytes) {
        return MediaImportResult.failure(tooLargeMessage);
      }
      final tooLarge = await _validateFileSize(
        sourceFile,
        maxBytes: maxBytes,
        tooLargeMessage: tooLargeMessage,
      );
      if (tooLarge != null) {
        return tooLarge;
      }
      final built = await _buildAttachment(type: type, sourceFile: sourceFile);
      attachments.add(built.attachment);
      if (built.deferredPreview != null && built.attachment.filePath != null) {
        deferredPreviews[built.attachment.filePath!] = built.deferredPreview!;
      }
    }
    if (deferredPreviews.isNotEmpty) {
      if (attachments.length == 1) {
        return MediaImportResult.successWithDeferredPreview(
          attachments.single,
          deferredPreviews: deferredPreviews,
        );
      }
      return MediaImportResult.successManyWithDeferredPreviews(
        attachments,
        deferredPreviews: deferredPreviews,
      );
    }
    if (attachments.length == 1) {
      return MediaImportResult.success(attachments.single);
    }
    return MediaImportResult.successMany(attachments);
  }

  Future<MediaImportResult> _pickIOSPhotoLibraryMedia({
    required AttachmentType type,
    required int maxBytes,
    required String tooLargeMessage,
    required String openFailureMessage,
    required String importNotConfiguredMessage,
    required String importFailedPrefix,
    VoidCallback? onProcessingStarted,
  }) async {
    List<XFile> files;
    try {
      final picker = ImagePicker();
      files = type == AttachmentType.photo
          ? await picker.pickMultiImage(imageQuality: 88, maxWidth: 1800)
          : await picker.pickMultiVideo();
    } on MissingPluginException {
      return MediaImportResult.failure(importNotConfiguredMessage);
    } on PlatformException catch (error) {
      return MediaImportResult.failure(error.message ?? importFailedPrefix);
    } catch (error) {
      return MediaImportResult.failure('$importFailedPrefix ($error)');
    }
    if (files.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final attachments = <NoteAttachment>[];
    final deferredPreviews = <String, Future<String?>>{};
    for (final sourceFile in files) {
      if (sourceFile.path.isEmpty) {
        return MediaImportResult.failure(openFailureMessage);
      }
      final tooLarge = await _validateFileSize(
        sourceFile,
        maxBytes: maxBytes,
        tooLargeMessage: tooLargeMessage,
      );
      if (tooLarge != null) {
        return tooLarge;
      }
      final built = await _buildAttachment(type: type, sourceFile: sourceFile);
      attachments.add(built.attachment);
      if (built.deferredPreview != null && built.attachment.filePath != null) {
        deferredPreviews[built.attachment.filePath!] = built.deferredPreview!;
      }
    }
    if (deferredPreviews.isNotEmpty) {
      if (attachments.length == 1) {
        return MediaImportResult.successWithDeferredPreview(
          attachments.single,
          deferredPreviews: deferredPreviews,
        );
      }
      return MediaImportResult.successManyWithDeferredPreviews(
        attachments,
        deferredPreviews: deferredPreviews,
      );
    }
    if (attachments.length == 1) {
      return MediaImportResult.success(attachments.single);
    }
    return MediaImportResult.successMany(attachments);
  }

  Future<MediaImportResult> _pickAudio({
    VoidCallback? onProcessingStarted,
  }) async {
    FilePickerResult? result;
    try {
      final audioExtensions = <String>[
        'm4a',
        'aac',
        'mp3',
        'wav',
        'aiff',
        'aif',
        'caf',
        'flac',
        'ogg',
      ];
      result = await FilePicker.pickFiles(
        type: defaultTargetPlatform == TargetPlatform.iOS
            ? FileType.custom
            : FileType.audio,
        allowedExtensions: defaultTargetPlatform == TargetPlatform.iOS
            ? audioExtensions
            : null,
        withData: kIsWeb,
      );
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'Audio import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'Audio import failed on this device.',
      );
    } catch (error) {
      return MediaImportResult.failure(
        'Audio import failed on this device. ($error)',
      );
    }
    if (result == null || result.files.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final file = result.files.single;
    final bytes = file.bytes;
    if (file.path == null && bytes == null) {
      return const MediaImportResult.failure(
        'The selected audio file could not be opened on this device.',
      );
    }
    if (bytes != null && bytes.length > 50 * 1024 * 1024) {
      return const MediaImportResult.failure(
        'Audio files over 50 MB are not supported yet.',
      );
    }
    final sourceFile = file.path == null
        ? XFile.fromData(file.bytes!, name: file.name)
        : XFile(file.path!, name: file.name);
    final tooLarge = await _validateFileSize(
      sourceFile,
      maxBytes: 50 * 1024 * 1024,
      tooLargeMessage: 'Audio files over 50 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    final built = await _buildAttachment(
      type: AttachmentType.audio,
      sourceFile: sourceFile,
    );
    return MediaImportResult.success(built.attachment);
  }

  Future<MediaImportResult> _pickFile({
    VoidCallback? onProcessingStarted,
  }) async {
    FilePickerResult? result;
    try {
      result = await FilePicker.pickFiles(type: FileType.any, withData: kIsWeb);
    } on MissingPluginException {
      return const MediaImportResult.failure(
        'File import is not configured in this runtime.',
      );
    } on PlatformException catch (error) {
      return MediaImportResult.failure(
        error.message ?? 'File import failed on this device.',
      );
    } catch (error) {
      return MediaImportResult.failure(
        'File import failed on this device. ($error)',
      );
    }
    if (result == null || result.files.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final file = result.files.single;
    final bytes = file.bytes;
    if (file.path == null && bytes == null) {
      return const MediaImportResult.failure(
        'The selected file could not be opened on this device.',
      );
    }
    if (bytes != null && bytes.length > 100 * 1024 * 1024) {
      return const MediaImportResult.failure(
        'Files over 100 MB are not supported yet.',
      );
    }
    final sourceFile = file.path == null
        ? XFile.fromData(file.bytes!, name: file.name)
        : XFile(file.path!, name: file.name);
    final tooLarge = await _validateFileSize(
      sourceFile,
      maxBytes: 100 * 1024 * 1024,
      tooLargeMessage: 'Files over 100 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    final built = await _buildAttachment(
      type: AttachmentType.file,
      sourceFile: sourceFile,
    );
    return MediaImportResult.success(built.attachment);
  }

  Future<({NoteAttachment attachment, Future<String?>? deferredPreview})>
  _buildAttachment({
    required AttachmentType type,
    required XFile sourceFile,
  }) async {
    final label = sourceFile.name.isEmpty
        ? path.basename(sourceFile.path)
        : sourceFile.name;
    final sourceBytes = await _sourceFileLength(sourceFile);
    logDiagnostic(
      'attachment',
      'attachment import build start',
      data: {'type': type.name, 'label': label, 'bytes': sourceBytes},
    );
    final stopwatch = Stopwatch()..start();
    final durationMs = await _mediaDurationMs(
      type: type,
      sourceFile: sourceFile,
    );
    String? previewBytesBase64;
    Future<String?>? deferredPreview;
    if (type == AttachmentType.video) {
      if (sourceBytes != null &&
          sourceBytes > _deferredVideoPreviewThresholdBytes) {
        logDiagnostic(
          'attachment',
          'video preview deferred for large file',
          data: {
            'label': label,
            'bytes': sourceBytes,
            'thresholdBytes': _deferredVideoPreviewThresholdBytes,
          },
        );
        deferredPreview = _videoPreviewBytesBase64ForSourceFile(sourceFile);
      } else {
        previewBytesBase64 = await _videoPreviewBytesBase64ForSourceFile(
          sourceFile,
        );
      }
    }
    final storedPath = await _attachmentStore.storeAttachment(
      sourceFile,
      type: type,
    );
    stopwatch.stop();
    logDiagnostic(
      'attachment',
      'attachment import build completed',
      data: {
        'type': type.name,
        'label': label,
        'bytes': sourceBytes,
        'elapsedMs': stopwatch.elapsedMilliseconds,
        'hasPreview': previewBytesBase64 != null,
        'hasDeferredPreview': deferredPreview != null,
      },
    );
    return (
      attachment: NoteAttachment(
        type: type,
        label: label,
        filePath: storedPath,
        previewBytesBase64: previewBytesBase64,
        durationMs: durationMs,
      ),
      deferredPreview: deferredPreview,
    );
  }

  XFile? _xFileFromPlatformFile(PlatformFile file) {
    final bytes = file.bytes;
    final path = file.path;
    if (path == null && bytes == null) {
      return null;
    }
    if (path == null) {
      return XFile.fromData(bytes!, name: file.name);
    }
    return XFile(path, name: file.name);
  }

  Future<MediaImportResult?> _validateFileSize(
    XFile file, {
    required int maxBytes,
    required String tooLargeMessage,
  }) async {
    if (kIsWeb) {
      return null;
    }
    final length = await file.length();
    if (length > maxBytes) {
      return MediaImportResult.failure(tooLargeMessage);
    }
    return null;
  }
}

final deviceAuthGatewayProvider = Provider<DeviceAuthGateway>(
  (ref) => LocalDeviceAuthGateway(),
);

final googleDriveAuthConfigProvider = Provider<GoogleDriveAuthConfig>(
  (ref) => const GoogleDriveAuthConfig(),
);

final syncAuthGatewayProvider = Provider<SyncAuthGateway>((ref) {
  final gateway = DefaultSyncAuthGateway(
    googleDriveAuthConfig: ref.watch(googleDriveAuthConfigProvider),
  );
  if (_useFakeGoogleDriveSync) {
    return FakeGoogleDriveSyncAuthGateway(fallback: gateway);
  }
  return gateway;
});

final mediaImportServiceProvider = Provider<MediaImportService>(
  (ref) => DefaultMediaImportService(
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
  ),
);

final secureKeyValueStoreProvider = Provider<SecureKeyValueStore>((ref) {
  return FlutterSecureKeyValueStore();
});

final iCloudSynchronizableKeyValueStoreProvider = Provider<SecureKeyValueStore>(
  (ref) {
    return FlutterSecureKeyValueStore(
      iOptions: const IOSOptions(
        accountName: 'org.ruhenheim.himemo.cloud_recovery_key',
        synchronizable: true,
        accessibility: KeychainAccessibility.first_unlock,
      ),
      mOptions: const MacOsOptions(
        accountName: 'org.ruhenheim.himemo.cloud_recovery_key',
        synchronizable: true,
      ),
    );
  },
);

final encryptionServiceProvider = Provider<EncryptionService>((ref) {
  return EncryptionService();
});

final appPinLockStoreProvider = Provider<AppPinLockStore>((ref) {
  return AppPinLockStore(
    encryptionService: ref.watch(encryptionServiceProvider),
  );
});

final coverModeSecretStoreProvider = Provider<SecretVerifierStore>((ref) {
  return SecretVerifierStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
    storageKey: 'security.cover_mode_secret.v1',
  );
});

final masterKeyServiceProvider = Provider<MasterKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  return MasterKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    keyFactory: encryption.generateKeyBytes,
  );
});

final encryptedNoteStoreProvider = Provider<EncryptedNoteStore>((ref) {
  return EncryptedNoteStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
    profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
    database: ref.watch(encryptedNoteDatabaseProvider),
  );
});

final profileDataKeyServiceProvider = Provider<ProfileDataKeyService>((ref) {
  return ProfileDataKeyService(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
    normalMasterKeyService: ref.watch(masterKeyServiceProvider),
  );
});

final encryptedNoteDatabaseProvider = Provider<EncryptedNoteDatabase>((ref) {
  final database = EncryptedNoteDatabase();
  ref.onDispose(database.close);
  return database;
});

final deviceIdentityStoreProvider = Provider<DeviceIdentityStore>((ref) {
  return DeviceIdentityStore();
});

final encryptedAttachmentStoreProvider = Provider<EncryptedAttachmentStore>((
  ref,
) {
  return EncryptedAttachmentStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    masterKeyService: ref.watch(masterKeyServiceProvider),
    profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
  );
});

class StorageUsageSummary {
  const StorageUsageSummary({
    required this.notePayloadBytes,
    required this.attachmentPayloadBytes,
  });

  final int notePayloadBytes;
  final int attachmentPayloadBytes;

  int get totalBytes => notePayloadBytes + attachmentPayloadBytes;
}

final storageUsageSummaryProvider = FutureProvider<StorageUsageSummary>((
  ref,
) async {
  ref.watch(notesControllerProvider);
  await ref
      .read(notesControllerProvider.notifier)
      .cleanupUnreferencedAttachments();
  final notePayloadBytes = await ref
      .watch(encryptedNoteStoreProvider)
      .storagePayloadSizeBytes();
  final attachmentPayloadBytes = await ref
      .watch(encryptedAttachmentStoreProvider)
      .storagePayloadSizeBytes();
  return StorageUsageSummary(
    notePayloadBytes: notePayloadBytes,
    attachmentPayloadBytes: attachmentPayloadBytes,
  );
});

final syncEngineProvider = Provider<SyncEngine>((ref) {
  return SyncEngine(
    database: ref.watch(encryptedNoteDatabaseProvider),
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
    deviceIdentityStore: ref.watch(deviceIdentityStoreProvider),
  );
});

final diagnosticLogServiceProvider = Provider<DiagnosticLogService>((ref) {
  return DiagnosticLogService.instance;
});

final auditLogServiceProvider = Provider<AuditLogService>((ref) {
  return AuditLogService.instance;
});

final networkConnectionServiceProvider = Provider<NetworkConnectionService>((
  ref,
) {
  return const NetworkConnectionService();
});

@Riverpod(keepAlive: true)
class DiagnosticLogController extends _$DiagnosticLogController {
  @override
  Future<DiagnosticLogSnapshot> build() async {
    final service = ref.watch(diagnosticLogServiceProvider);
    return DiagnosticLogSnapshot(
      enabled: await service.isEnabled(),
      entries: await service.entries(),
    );
  }

  Future<void> setEnabled(bool enabled) async {
    final service = ref.read(diagnosticLogServiceProvider);
    await service.setEnabled(enabled);
    ref.invalidateSelf();
  }

  Future<bool> toggleEnabled() async {
    final service = ref.read(diagnosticLogServiceProvider);
    final enabled = await service.toggleEnabled();
    ref.invalidateSelf();
    return enabled;
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<String> exportText() {
    return ref.read(diagnosticLogServiceProvider).exportText();
  }

  Future<void> clear() async {
    await ref.read(diagnosticLogServiceProvider).clear();
    ref.invalidateSelf();
  }
}

final auditLogControllerProvider =
    AsyncNotifierProvider<AuditLogController, AuditLogSnapshot>(
      AuditLogController.new,
    );

class AuditLogController extends AsyncNotifier<AuditLogSnapshot> {
  @override
  Future<AuditLogSnapshot> build() async {
    final service = ref.watch(auditLogServiceProvider);
    void onRevisionChanged() => ref.invalidateSelf();
    service.revision.addListener(onRevisionChanged);
    ref.onDispose(() => service.revision.removeListener(onRevisionChanged));
    return AuditLogSnapshot(entries: await service.entries());
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
  }

  Future<String> exportText() {
    return ref.read(auditLogServiceProvider).exportText();
  }
}

final secureSyncBundleStoreProvider = Provider<SecureSyncBundleStore>((ref) {
  return SecureSyncBundleStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    syncBundleKeyService: ref.watch(syncBundleKeyServiceProvider),
    legacyMasterKeyService: ref.watch(masterKeyServiceProvider),
  );
});

final syncBundleKeyServiceProvider = Provider<SyncBundleKeyService>((ref) {
  final encryption = ref.watch(encryptionServiceProvider);
  final provider = ref.watch(syncProviderControllerProvider);
  final usesICloudSharedKey =
      provider == SyncProvider.iCloud &&
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);
  return SyncBundleKeyService(
    secureStore: usesICloudSharedKey
        ? ref.watch(iCloudSynchronizableKeyValueStoreProvider)
        : ref.watch(secureKeyValueStoreProvider),
    fallbackStore: usesICloudSharedKey
        ? ref.watch(secureKeyValueStoreProvider)
        : null,
    cloudStore: provider == SyncProvider.googleDrive
        ? ref.watch(googleDriveCloudSyncBundleKeyStoreProvider)
        : null,
    keyFactory: encryption.generateKeyBytes,
  );
});

final syncBundleFingerprintProvider = FutureProvider<String>((ref) async {
  return ref.watch(syncBundleKeyServiceProvider).fingerprint();
});

final packageInfoProvider = FutureProvider<AppPackageDetails>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return AppPackageDetails(
      appName: info.appName.isEmpty ? 'HiMemo' : info.appName,
      version: info.version.isEmpty ? '1.0.0' : info.version,
      buildNumber: info.buildNumber.isEmpty ? '1' : info.buildNumber,
    );
  } catch (_) {
    return const AppPackageDetails(
      appName: 'HiMemo',
      version: '1.0.0',
      buildNumber: '1',
    );
  }
});

final googleDriveSyncTransportProvider = Provider<GoogleDriveSyncTransport>((
  ref,
) {
  if (_useFakeGoogleDriveSync) {
    return InMemoryGoogleDriveSyncTransport();
  }
  return GoogleApisGoogleDriveSyncTransport(
    authConfig: ref.watch(googleDriveAuthConfigProvider),
  );
});

final googleDriveCloudSyncBundleKeyStoreProvider =
    Provider<CloudSyncBundleKeyStore>((ref) {
      return GoogleDriveCloudSyncBundleKeyStore(
        ref.watch(googleDriveSyncTransportProvider),
      );
    });

final iCloudSyncTransportProvider = Provider<ICloudSyncTransport>((ref) {
  return MethodChannelICloudSyncTransport();
});

final syncBundleStateStoreProvider = Provider<SyncBundleStateStore>((ref) {
  return SyncBundleStateStore();
});

final syncBundleStateProvider = FutureProvider<SyncBundleState>((ref) async {
  return ref.watch(syncBundleStateStoreProvider).read();
});

final syncConflictWarningProvider = Provider<String?>((ref) {
  final provider = ref.watch(syncProviderControllerProvider);
  final assessment = assessSyncConflict(
    googleDriveSelected: provider != SyncProvider.off,
    queue: ref.watch(syncQueueSummaryProvider).asData?.value,
    remoteStatus: ref.watch(syncTransferControllerProvider).remoteStatus,
    bundleState: ref.watch(syncBundleStateProvider).asData?.value,
  );
  return assessment.message;
});

final syncQueueSummaryProvider = FutureProvider<SyncQueueSummary>((ref) async {
  return ref.watch(syncEngineProvider).summarizeQueue();
});

final playIntegrityServiceProvider = Provider<PlayIntegrityService>(
  (ref) => const PlayIntegrityService(),
);

final playIntegrityStatusProvider = FutureProvider<PlayIntegrityStatus>((ref) {
  return ref.watch(playIntegrityServiceProvider).checkAvailability();
});

final playIntegrityVerifierProvider = Provider<PlayIntegrityVerifier>(
  (ref) => PlayIntegrityVerifier(
    playIntegrityService: ref.watch(playIntegrityServiceProvider),
  ),
);

final currentAppFlavorProvider = Provider<AppFlavor>((ref) {
  final flavorName = FlavorConfig.instance.variables['flavor'] as String?;
  return flavorName == AppFlavor.production.name
      ? AppFlavor.production
      : AppFlavor.development;
});

final inAppUpdateServiceProvider = Provider<InAppUpdateService>(
  (ref) => const InAppUpdateService(),
);

final inAppUpdateControllerProvider =
    NotifierProvider<InAppUpdateController, InAppUpdateState>(
      InAppUpdateController.new,
    );

class InAppUpdateController extends Notifier<InAppUpdateState> {
  bool _checkedOnce = false;

  @override
  InAppUpdateState build() => const InAppUpdateState.idle();

  Future<void> check({bool silentIfUnsupported = false}) async {
    if (_checkedOnce && state.stage != InAppUpdateStage.error) {
      return;
    }
    _checkedOnce = true;
    state = state.copyWith(
      stage: InAppUpdateStage.checking,
      clearMessage: true,
    );
    final status = await ref.read(inAppUpdateServiceProvider).checkForUpdate();
    if (!status.isSupported && silentIfUnsupported) {
      state = InAppUpdateState(
        stage: InAppUpdateStage.unsupported,
        status: status,
      );
      return;
    }
    state = InAppUpdateState(
      stage: status.updateAvailable
          ? InAppUpdateStage.ready
          : (status.isSupported
                ? InAppUpdateStage.completed
                : InAppUpdateStage.unsupported),
      status: status,
      message: status.message,
    );
  }

  Future<void> startPreferredUpdate() async {
    final status = state.status;
    if (status == null || !status.updateAvailable) {
      return;
    }
    state = state.copyWith(
      stage: InAppUpdateStage.updating,
      clearMessage: true,
    );
    try {
      await logFirebaseBreadcrumb('in-app update requested');
      if (status.immediateAllowed) {
        await ref.read(inAppUpdateServiceProvider).performImmediateUpdate();
      } else if (status.flexibleAllowed) {
        await ref.read(inAppUpdateServiceProvider).performFlexibleUpdate();
      } else {
        state = state.copyWith(
          stage: InAppUpdateStage.unsupported,
          message: 'Google Play update flow is not allowed for this build.',
        );
        return;
      }
      state = state.copyWith(
        stage: InAppUpdateStage.completed,
        message: 'Update flow started with Google Play.',
      );
    } catch (error, stackTrace) {
      await recordNonFatalError(
        error,
        stackTrace,
        reason: 'in_app_update_start_failed',
      );
      state = state.copyWith(stage: InAppUpdateStage.error, message: '$error');
    }
  }

  Future<void> completeFlexibleUpdate() async {
    try {
      await ref.read(inAppUpdateServiceProvider).completeFlexibleUpdate();
      state = state.copyWith(
        stage: InAppUpdateStage.completed,
        message: 'Flexible update installation completed.',
      );
    } catch (error, stackTrace) {
      await recordNonFatalError(
        error,
        stackTrace,
        reason: 'in_app_update_complete_failed',
      );
      state = state.copyWith(stage: InAppUpdateStage.error, message: '$error');
    }
  }
}

final syncTransferControllerProvider =
    NotifierProvider<SyncTransferController, SyncTransferState>(
      SyncTransferController.new,
    );

class SyncTransferController extends Notifier<SyncTransferState> {
  static const largeMobileSyncThresholdBytes = 50 * 1024 * 1024;
  static const _remoteStatusCacheTtl = Duration(seconds: 90);
  static const _syncBundleDecryptionMessage =
      'sync.error.bundle_decryption_failed';
  static const _syncBundleKeyMissingMessage = 'sync.error.bundle_key_missing';
  static const _iCloudSyncBundleKeyWaitingMessage =
      'sync.error.icloud_keychain_waiting';
  static const _privateProfileNotesPendingUnlockMessage =
      'sync.info.private_profile_notes_pending_unlock';

  Timer? _cooldownTimer;
  Timer? _remoteStatusWaitTimer;
  RemoteSyncBundleStatus? _cachedRemoteStatus;
  DateTime? _cachedRemoteStatusFetchedAt;
  SyncProvider? _cachedRemoteStatusProvider;

  @override
  SyncTransferState build() {
    ref.onDispose(() {
      _cooldownTimer?.cancel();
      _remoteStatusWaitTimer?.cancel();
    });
    return const SyncTransferState.idle();
  }

  void _diagnostic(
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    logDiagnostic('sync', message, data: data);
  }

  void clearLocalBundleCache() {
    state = state.copyWith(clearLocalBundle: true);
  }

  Future<SyncQueueSummary> _readLocalSyncQueueSummary() {
    return ref.read(syncEngineProvider).summarizeQueue();
  }

  Future<LargeSyncTransferWarning?> largeMobileTransferWarning({
    bool includeUpload = true,
    bool includeDownload = true,
    bool estimateAllLocalNotes = false,
  }) async {
    final kind = await ref.read(networkConnectionServiceProvider).currentKind();
    if (kind != NetworkConnectionKind.mobile) {
      return null;
    }
    if (includeDownload) {
      var remoteStatus = state.remoteStatus;
      if (remoteStatus == null &&
          _supportsRemoteTransport(ref.read(syncProviderControllerProvider))) {
        final bundleState = await ref.read(syncBundleStateProvider.future);
        if (bundleState.lastRemoteFileId != null &&
            bundleState.lastRemoteFileId!.isNotEmpty) {
          remoteStatus = RemoteSyncBundleStatus(
            fileId: bundleState.lastRemoteFileId!,
            fileName: '',
            modifiedAt: bundleState.lastRemoteModifiedAt,
            deviceId: bundleState.lastRemoteDeviceId,
          );
          state = state.copyWith(remoteStatus: remoteStatus);
        }
        unawaited(_refreshRemoteStatusInBackground());
      }
      final remoteSize = remoteStatus?.sizeBytes;
      final bundleState = await ref.read(syncBundleStateProvider.future);
      final needsDownload =
          remoteStatus != null &&
          remoteBundleNeedsApplyForSync(remoteStatus, bundleState);
      if (needsDownload &&
          remoteSize != null &&
          remoteSize >= largeMobileSyncThresholdBytes) {
        return LargeSyncTransferWarning(
          direction: LargeSyncTransferDirection.download,
          bytes: remoteSize,
          thresholdBytes: largeMobileSyncThresholdBytes,
        );
      }
    }
    if (!includeUpload) {
      return null;
    }
    final uploadBytes = estimateAllLocalNotes
        ? await estimateCurrentStateUploadBytes()
        : await estimatePendingUploadBytes();
    if (uploadBytes >= largeMobileSyncThresholdBytes) {
      return LargeSyncTransferWarning(
        direction: LargeSyncTransferDirection.upload,
        bytes: uploadBytes,
        thresholdBytes: largeMobileSyncThresholdBytes,
      );
    }
    return null;
  }

  Future<int> estimatePendingUploadBytes() async {
    final pendingChanges = await ref
        .read(syncEngineProvider)
        .loadPendingChanges();
    final pendingIds = pendingChanges.map((change) => change.noteId).toSet();
    final notes = await ref
        .read(notesControllerProvider.notifier)
        .notesForSyncSnapshot(pendingNoteIds: pendingIds);
    return ref.read(syncEngineProvider).estimateNotesPayloadBytes(notes);
  }

  Future<int> estimateCurrentStateUploadBytes() async {
    final notes = ref
        .read(notesControllerProvider)
        .where((note) => !isGeneratedSampleNote(note))
        .map((note) {
          final syncState = note.deletedAt == null
              ? NoteSyncState.pendingUpload
              : NoteSyncState.pendingDelete;
          return note.copyWith(syncState: syncState);
        })
        .toList(growable: false);
    return ref.read(syncEngineProvider).estimateNotesPayloadBytes(notes);
  }

  Future<bool> _shouldBlockLargeMobileTransfer({
    required bool allowLargeMobileTransfer,
    required bool silentLargeMobileSkip,
    bool includeUpload = true,
    bool includeDownload = true,
    bool estimateAllLocalNotes = false,
  }) async {
    if (allowLargeMobileTransfer) {
      return false;
    }
    final warning = await largeMobileTransferWarning(
      includeUpload: includeUpload,
      includeDownload: includeDownload,
      estimateAllLocalNotes: estimateAllLocalNotes,
    );
    if (warning == null) {
      return false;
    }
    _diagnostic(
      'large mobile sync blocked',
      data: {
        'direction': warning.direction.name,
        'bytes': warning.bytes,
        'thresholdBytes': warning.thresholdBytes,
        'silent': silentLargeMobileSkip,
      },
    );
    if (!silentLargeMobileSkip) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.large_mobile_transfer_requires_confirmation',
      );
    } else if (state.stage == SyncTransferStage.busy) {
      state = SyncTransferState(
        stage: SyncTransferStage.idle,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
    return true;
  }

  void _startBusy(SyncTransferProgress progress) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      clearMessage: true,
      clearDetail: true,
      clearCooldown: true,
    );
  }

  void _setProgress(SyncTransferProgress progress) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      clearMessage: true,
    );
  }

  void _setProgressDetail({
    required SyncTransferProgress progress,
    String? detail,
    int? completedItems,
    int? totalItems,
  }) {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      progress: progress,
      detail: detail,
      completedItems: completedItems,
      totalItems: totalItems,
      clearMessage: true,
      clearDetail:
          detail == null && completedItems == null && totalItems == null,
    );
  }

  Future<void> _yieldToUi() => Future<void>.delayed(Duration.zero);

  Future<T> _measureSyncStep<T>(
    String message,
    Future<T> Function() operation, {
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await operation();
    } finally {
      stopwatch.stop();
      _diagnostic(
        message,
        data: {...data, 'elapsedMs': stopwatch.elapsedMilliseconds},
      );
    }
  }

  bool _canUseCachedRemoteStatus(SyncProvider provider) {
    final fetchedAt = _cachedRemoteStatusFetchedAt;
    return fetchedAt != null &&
        _cachedRemoteStatusProvider == provider &&
        DateTime.now().difference(fetchedAt) < _remoteStatusCacheTtl;
  }

  void _cacheRemoteStatus(
    SyncProvider provider,
    RemoteSyncBundleStatus? remoteStatus,
  ) {
    _cachedRemoteStatusProvider = provider;
    _cachedRemoteStatusFetchedAt = DateTime.now();
    _cachedRemoteStatus = remoteStatus;
  }

  void _startRemoteStatusWaitProgress({
    required SyncProvider provider,
    required int totalItems,
  }) {
    _remoteStatusWaitTimer?.cancel();
    final startedAt = DateTime.now();

    void update() {
      final elapsed = DateTime.now().difference(startedAt).inSeconds;
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: elapsed <= 0
            ? 'Waiting for ${provider.name} response'
            : 'Waiting for ${provider.name} response (${elapsed}s)',
        completedItems: 0,
        totalItems: totalItems,
      );
    }

    update();
    _remoteStatusWaitTimer = Timer.periodic(
      const Duration(seconds: 1),
      (_) => update(),
    );
  }

  Future<RemoteSyncBundleStatus?> _fetchLatestRemoteStatusWithCache({
    required String traceName,
    required bool allowCached,
    required int totalItems,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (allowCached && _canUseCachedRemoteStatus(provider)) {
      _diagnostic(
        'remote status cache hit',
        data: {
          'provider': provider.name,
          'ageMs': DateTime.now()
              .difference(_cachedRemoteStatusFetchedAt!)
              .inMilliseconds,
          'hasRemote': _cachedRemoteStatus != null,
          'fileId': _cachedRemoteStatus?.fileId,
        },
      );
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Using recent cloud status',
        completedItems: 1,
        totalItems: totalItems,
      );
      await _yieldToUi();
      return _cachedRemoteStatus;
    }
    _startRemoteStatusWaitProgress(provider: provider, totalItems: totalItems);
    try {
      final remoteStatus = await runFirebaseTrace(
        traceName,
        _fetchLatestRemoteStatus,
      );
      _cacheRemoteStatus(provider, remoteStatus);
      return remoteStatus;
    } finally {
      _remoteStatusWaitTimer?.cancel();
      _remoteStatusWaitTimer = null;
    }
  }

  Future<void> refreshRemoteStatus({
    bool allowCachedRemoteStatus = false,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.idle,
        message: 'sync.info.select_target_for_remote_status',
      );
      return;
    }
    _startBusy(SyncTransferProgress.checkingRemote);
    await _yieldToUi();
    try {
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking cloud status',
        completedItems: 0,
        totalItems: 1,
      );
      await _yieldToUi();
      final remoteStatus = await _measureSyncStep(
        'remote status check completed',
        () => _fetchLatestRemoteStatusWithCache(
          traceName: 'sync_refresh_remote_status',
          allowCached: allowCachedRemoteStatus,
          totalItems: 1,
        ),
        data: {'cachedAllowed': allowCachedRemoteStatus},
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: remoteStatus == null
            ? 'sync.info.no_remote_bundle'
            : 'sync.info.remote_bundle_refreshed',
        remoteStatus: remoteStatus,
        localBundle: state.localBundle,
      );
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
      }
    } catch (error) {
      state = _failureState(error, remoteStatus: state.remoteStatus);
    }
  }

  Future<ICloudStorageBreakdown> fetchICloudStorageBreakdown() async {
    final provider = ref.read(syncProviderControllerProvider);
    if (provider != SyncProvider.iCloud) {
      throw StateError('iCloud sync is not selected.');
    }
    _diagnostic('icloud storage breakdown requested');
    final breakdown = await runFirebaseTrace(
      'sync_icloud_storage_breakdown',
      () => ref.read(iCloudSyncTransportProvider).fetchStorageBreakdown(),
    );
    _diagnostic(
      'icloud storage breakdown loaded',
      data: {
        'bundleCount': breakdown.bundleCount,
        'bundleBytes': breakdown.bundleBytes,
        'attachmentCount': breakdown.attachmentCount,
        'attachmentBytes': breakdown.attachmentBytes,
        'totalBytes': breakdown.totalBytes,
      },
    );
    return breakdown;
  }

  Future<ICloudMaintenanceResult> compactICloudStorage({
    int keepLatest = 1,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (provider != SyncProvider.iCloud) {
      throw StateError('iCloud sync is not selected.');
    }
    _diagnostic(
      'icloud storage compact requested',
      data: {'keepLatest': keepLatest},
    );
    await ref.read(notesControllerProvider.notifier).queueCurrentStateForSync();
    await uploadCurrentBundle(force: true, pruneAfterUpload: false);
    final localBundle = state.localBundle;
    if (localBundle == null) {
      throw StateError('sync.error.local_bundle_prepare_failed');
    }
    final referencedHashes = await _referencedAttachmentHashesFromBundle(
      localBundle.reference,
    );
    final result = await runFirebaseTrace(
      'sync_icloud_prune_obsolete_data',
      () => ref
          .read(iCloudSyncTransportProvider)
          .pruneObsoleteData(
            keepLatest: keepLatest,
            referencedAttachmentHashes: referencedHashes,
          ),
    );
    _diagnostic(
      'icloud storage compact completed',
      data: {
        'deletedBundleCount': result.deletedBundleCount,
        'deletedBundleBytes': result.deletedBundleBytes,
        'deletedAttachmentCount': result.deletedAttachmentCount,
        'deletedAttachmentBytes': result.deletedAttachmentBytes,
        'referencedAttachmentHashes': referencedHashes.length,
      },
    );
    await refreshRemoteStatus();
    return result;
  }

  Future<Set<String>> _referencedAttachmentHashesFromBundle(
    String reference,
  ) async {
    final decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readBundleJson(reference);
    if (decoded == null) {
      return const <String>{};
    }
    final hashes = <String>{};
    for (final rawAttachment
        in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawAttachment is! Map) {
        continue;
      }
      final contentHash = rawAttachment['contentHash'] as String?;
      if (contentHash != null && contentHash.isNotEmpty) {
        hashes.add(contentHash);
      }
    }
    for (final rawEntry
        in (decoded['notes'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawEntry is! Map) {
        continue;
      }
      final rawNote = rawEntry['note'];
      if (rawNote is! Map) {
        continue;
      }
      hashes.addAll(_remoteAttachmentHashesInNoteJson(rawNote));
    }
    return hashes;
  }

  Set<String> _remoteAttachmentHashesInNoteJson(Map rawNote) {
    final hashes = <String>{};

    void addFromAttachmentJson(Object? rawAttachment) {
      if (rawAttachment is! Map) {
        return;
      }
      final filePath = rawAttachment['filePath'] as String?;
      final contentHash = _remoteAttachmentHashFromRef(filePath);
      if (contentHash != null) {
        hashes.add(contentHash);
      }
    }

    for (final rawAttachment
        in (rawNote['attachments'] as List<dynamic>? ?? const <dynamic>[])) {
      addFromAttachmentJson(rawAttachment);
    }
    for (final rawBlock
        in (rawNote['blocks'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawBlock is! Map) {
        continue;
      }
      addFromAttachmentJson(rawBlock['attachment']);
    }
    return hashes;
  }

  String? _remoteAttachmentHashFromRef(String? filePath) {
    const prefix = 'sync-attachment-object://';
    if (filePath == null || !filePath.startsWith(prefix)) {
      return null;
    }
    final contentHash = filePath.substring(prefix.length);
    return contentHash.isEmpty ? null : contentHash;
  }

  Future<void> uploadCurrentBundle({
    bool force = false,
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
    bool pruneAfterUpload = true,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    _diagnostic(
      'upload requested',
      data: {'provider': provider.name, 'force': force},
    );
    if (!_supportsRemoteTransport(provider)) {
      _diagnostic(
        'upload skipped unsupported provider',
        data: {'provider': provider.name},
      );
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_upload',
      );
      return;
    }
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: await _readLocalSyncQueueSummary(),
      remoteStatus: state.remoteStatus,
      bundleState: await ref.read(syncBundleStateProvider.future),
    );
    if (assessment.hasConflict && !force) {
      _diagnostic(
        'upload conflict detected',
        data: {'message': assessment.message},
      );
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.conflict_download_first_or_force_upload',
      );
      return;
    }
    if (await _shouldBlockLargeMobileTransfer(
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
      includeDownload: false,
    )) {
      return;
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    await _yieldToUi();
    try {
      await logFirebaseBreadcrumb('sync upload requested');
      await ref
          .read(notesControllerProvider.notifier)
          .queueCurrentStateForSync();
      var pendingChanges = await ref
          .read(syncEngineProvider)
          .loadPendingChanges();
      final pendingIds = pendingChanges.map((change) => change.noteId).toSet();
      final notes = await ref
          .read(notesControllerProvider.notifier)
          .notesForSyncSnapshot(pendingNoteIds: pendingIds);
      final uploadableNoteIds = notes.map((note) => note.id).toSet();
      final stalePendingUpsertIds = pendingChanges
          .where(
            (change) =>
                change.action == PendingNoteChangeAction.upsert &&
                !uploadableNoteIds.contains(change.noteId),
          )
          .map((change) => change.noteId)
          .toSet();
      if (stalePendingUpsertIds.isNotEmpty) {
        _diagnostic(
          'stale pending upserts pruned before upload',
          data: {'count': stalePendingUpsertIds.length},
        );
        await ref
            .read(encryptedNoteDatabaseProvider)
            .deletePendingChangesByIds(stalePendingUpsertIds);
        pendingChanges = pendingChanges
            .where((change) => !stalePendingUpsertIds.contains(change.noteId))
            .toList(growable: false);
      }
      final pendingHashes = {
        for (final change in pendingChanges) change.noteId: change.contentHash,
      };
      final snapshot = await runFirebaseTrace(
        'sync_prepare_snapshot',
        () => ref
            .read(syncEngineProvider)
            .prepareSnapshot(
              notes,
              pendingChanges: pendingChanges,
              onProgress: (progress) async {
                _setProgressDetail(
                  progress: SyncTransferProgress.preparingBundle,
                  detail: progress.detail,
                  completedItems: progress.completedItems,
                  totalItems: progress.totalItems,
                );
                await _yieldToUi();
              },
            ),
      );
      final preparedUpserts = snapshot.notes
          .where((change) => change.action == PendingNoteChangeAction.upsert)
          .length;
      if (preparedUpserts < snapshot.summary.upserts) {
        throw StateError('sync.error.local_snapshot_incomplete');
      }
      _diagnostic(
        'snapshot prepared',
        data: {
          'changes': snapshot.summary.totalChanges,
          'upserts': snapshot.summary.upserts,
          'deletes': snapshot.summary.deletes,
          'preparedNotes': snapshot.notes.length,
          'attachments': snapshot.attachments.length,
        },
      );
      final privateProfiles = await ref
          .read(privateMemoProfileStoreProvider)
          .exportSyncPayload();
      final provider = ref.read(syncProviderControllerProvider);
      if (provider != SyncProvider.off) {
        _setProgress(SyncTransferProgress.uploadingBundle);
        await _yieldToUi();
        await runFirebaseTrace(
          'sync_upload_attachment_objects',
          () => _uploadRemoteAttachmentObjects(snapshot.attachments),
        );
      }
      final bundle = await runFirebaseTrace(
        'sync_write_local_bundle',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .writeBundle(
              snapshot,
              privateProfiles: [privateProfiles],
              inlineAttachments: provider == SyncProvider.off,
            ),
      );
      final encodedPayload = await runFirebaseTrace(
        'sync_read_local_bundle_payload',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readEncryptedBundlePayload(bundle.reference),
      );
      if (encodedPayload == null || encodedPayload.isEmpty) {
        throw StateError('sync.error.local_bundle_prepare_failed');
      }
      _diagnostic(
        'local bundle prepared',
        data: {
          'notes': bundle.noteCount,
          'attachments': bundle.attachmentCount,
          'payloadLength': encodedPayload.length,
        },
      );
      final remoteStatus = await runFirebaseTrace(
        'sync_upload_remote_bundle',
        () => _uploadRemoteBundle(
          encodedPayload: encodedPayload,
          deviceId: snapshot.deviceId,
          noteCount: bundle.noteCount,
          attachmentCount: bundle.attachmentCount,
        ),
      );
      _cacheRemoteStatus(provider, remoteStatus);
      _diagnostic(
        'remote bundle uploaded',
        data: {
          'fileId': remoteStatus.fileId,
          'modifiedAt': remoteStatus.modifiedAt?.toUtc().toIso8601String(),
          'deviceId': remoteStatus.deviceId,
          'notes': remoteStatus.noteCount,
          'attachments': remoteStatus.attachmentCount,
          'sizeBytes': remoteStatus.sizeBytes,
        },
      );
      _setProgress(SyncTransferProgress.finalizing);
      await _yieldToUi();
      await ref
          .read(notesControllerProvider.notifier)
          .markSnapshotChangesSynced(pendingHashes);
      ref.invalidate(syncQueueSummaryProvider);
      final queueAfterUpload = await _readLocalSyncQueueSummary();
      _diagnostic(
        'local queue after upload marked synced',
        data: {
          'changes': queueAfterUpload.totalChanges,
          'upserts': queueAfterUpload.upserts,
          'deletes': queueAfterUpload.deletes,
        },
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: 'sync.info.upload_success',
        remoteStatus: remoteStatus,
        localBundle: bundle,
      );
      await ref.read(syncBundleStateStoreProvider).recordUpload(remoteStatus);
      ref.invalidate(syncBundleStateProvider);
      if (provider == SyncProvider.iCloud && pruneAfterUpload) {
        try {
          final referencedHashes = await _referencedAttachmentHashesFromBundle(
            bundle.reference,
          );
          final maintenance = await ref
              .read(iCloudSyncTransportProvider)
              .pruneObsoleteData(
                keepLatest: 1,
                referencedAttachmentHashes: referencedHashes,
              );
          _diagnostic(
            'icloud post upload storage prune completed',
            data: {
              'deletedBundleCount': maintenance.deletedBundleCount,
              'deletedBundleBytes': maintenance.deletedBundleBytes,
              'deletedAttachmentCount': maintenance.deletedAttachmentCount,
              'deletedAttachmentBytes': maintenance.deletedAttachmentBytes,
              'referencedAttachmentHashes': referencedHashes.length,
            },
          );
        } catch (error, stackTrace) {
          _diagnostic(
            'icloud post upload storage prune failed',
            data: {'error': error},
          );
          await recordNonFatalError(
            error,
            stackTrace,
            reason: 'icloud_post_upload_storage_prune_failed',
          );
        }
      }
    } on SyncAttachmentMissingException catch (error) {
      _diagnostic(
        'upload blocked by missing local attachment',
        data: {
          'noteId': error.noteId,
          'attachmentLabel': error.attachmentLabel,
          'attachmentType': error.attachmentType.name,
          'fileRef': path.basename(error.filePath),
          'index': error.index,
        },
      );
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    } catch (error) {
      _diagnostic('upload failed', data: {'error': error});
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<void> reuploadAllCurrentNotes({
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_reupload',
      );
      return;
    }
    if (state.isBusy) {
      return;
    }
    if (await _shouldBlockLargeMobileTransfer(
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
      includeDownload: false,
      estimateAllLocalNotes: true,
    )) {
      return;
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    await _yieldToUi();
    await ref.read(notesControllerProvider.notifier).queueCurrentStateForSync();
    await uploadCurrentBundle(
      force: true,
      allowLargeMobileTransfer: allowLargeMobileTransfer,
      silentLargeMobileSkip: silentLargeMobileSkip,
    );
  }

  Future<void> syncNow({
    bool forceUpload = false,
    bool allowLargeMobileTransfer = false,
    bool silentLargeMobileSkip = false,
    bool allowCachedRemoteStatus = false,
  }) async {
    final provider = ref.read(syncProviderControllerProvider);
    _diagnostic(
      'sync now requested',
      data: {
        'provider': provider.name,
        'forceUpload': forceUpload,
        'busy': state.isBusy,
        'allowCachedRemoteStatus': allowCachedRemoteStatus,
      },
    );
    if (!_supportsRemoteTransport(provider)) {
      _diagnostic(
        'sync now skipped unsupported provider',
        data: {'provider': provider.name},
      );
      return;
    }
    if (state.isBusy) {
      _diagnostic('sync now skipped busy');
      return;
    }
    _startBusy(SyncTransferProgress.checkingRemote);
    await _yieldToUi();
    try {
      await logFirebaseBreadcrumb('sync now requested');
      const checkingStepCount = 4;
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking cloud status',
        completedItems: 0,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      final remoteStatus = await _measureSyncStep(
        'remote status check completed',
        () => _fetchLatestRemoteStatusWithCache(
          traceName: 'sync_refresh_remote_status',
          allowCached: allowCachedRemoteStatus,
          totalItems: checkingStepCount,
        ),
        data: {'cachedAllowed': allowCachedRemoteStatus},
      );
      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Reading sync history',
        completedItems: 1,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      final bundleState = await _measureSyncStep(
        'sync state check completed',
        () => ref.read(syncBundleStateProvider.future),
      );
      _diagnostic(
        'remote status refreshed',
        data: {
          'hasRemote': remoteStatus != null,
          'fileId': remoteStatus?.fileId,
          'modifiedAt': remoteStatus?.modifiedAt?.toUtc().toIso8601String(),
          'deviceId': remoteStatus?.deviceId,
          'notes': remoteStatus?.noteCount,
          'attachments': remoteStatus?.attachmentCount,
          'sizeBytes': remoteStatus?.sizeBytes,
          'lastRemoteFileId': bundleState.lastRemoteFileId,
          'lastAppliedAt': bundleState.lastAppliedAt?.toUtc().toIso8601String(),
          'lastUploadedAt': bundleState.lastUploadedAt
              ?.toUtc()
              .toIso8601String(),
        },
      );
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
      }
      state = state.copyWith(remoteStatus: remoteStatus);

      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking transfer size',
        completedItems: 2,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      if (await _measureSyncStep(
        'transfer size check completed',
        () => _shouldBlockLargeMobileTransfer(
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
          includeUpload: false,
          includeDownload:
              remoteStatus != null &&
              _remoteBundleNeedsApply(remoteStatus, bundleState),
        ),
      )) {
        return;
      }

      _setProgressDetail(
        progress: SyncTransferProgress.checkingRemote,
        detail: 'Checking local changes',
        completedItems: 3,
        totalItems: checkingStepCount,
      );
      await _yieldToUi();
      final queue = await _measureSyncStep(
        'local queue check completed',
        _readLocalSyncQueueSummary,
      );
      final hadPendingChangesBeforeRemoteApply = queue.hasPendingChanges;
      var appliedRemoteDuringSync = false;
      _diagnostic(
        'local queue inspected',
        data: {
          'changes': queue.totalChanges,
          'upserts': queue.upserts,
          'deletes': queue.deletes,
          'lastQueuedAt': queue.lastQueuedAt?.toUtc().toIso8601String(),
        },
      );
      if (remoteStatus != null &&
          _remoteBundleNeedsApply(remoteStatus, bundleState)) {
        _diagnostic(
          'remote bundle needs apply',
          data: {'fileId': remoteStatus.fileId},
        );
        final assessment = assessSyncConflict(
          googleDriveSelected: true,
          queue: queue,
          remoteStatus: remoteStatus,
          bundleState: bundleState,
        );
        if (assessment.hasConflict && !forceUpload) {
          _diagnostic(
            'sync conflict candidate detected',
            data: {'message': assessment.message},
          );
        }
        _setProgress(SyncTransferProgress.downloadingBundle);
        await _yieldToUi();
        final remoteBundle = await runFirebaseTrace(
          'sync_download_latest_bundle',
          _downloadLatestRemoteBundle,
        );
        _diagnostic(
          'latest remote bundle downloaded',
          data: {
            'hasBundle': remoteBundle != null,
            'fileId': remoteBundle?.status.fileId,
            'payloadLength': remoteBundle?.encodedPayload.length,
          },
        );
        await _storeDownloadedBundle(
          remoteBundle,
          emptyMessage: 'sync.info.no_bundle_to_sync',
        );
        if (remoteBundle != null) {
          _setProgress(SyncTransferProgress.applyingBundle);
          await _yieldToUi();
          await applyDownloadedBundle();
          if (state.stage == SyncTransferStage.error) {
            return;
          }
          if (state.message == _privateProfileNotesPendingUnlockMessage) {
            return;
          }
          appliedRemoteDuringSync = true;
          final hasNoteConflicts = ref
              .read(notesControllerProvider)
              .any((note) => note.syncState == NoteSyncState.conflict);
          if (hasNoteConflicts && !forceUpload) {
            _diagnostic('sync note conflict requires review');
            state = state.copyWith(
              stage: SyncTransferStage.error,
              message: 'sync.error.conflict_review_remote',
            );
            return;
          }
        }
      }

      ref.invalidate(syncQueueSummaryProvider);
      final refreshedQueue = await _readLocalSyncQueueSummary();
      _diagnostic(
        'local queue refreshed',
        data: {
          'changes': refreshedQueue.totalChanges,
          'upserts': refreshedQueue.upserts,
          'deletes': refreshedQueue.deletes,
        },
      );
      if (refreshedQueue.hasPendingChanges) {
        _setProgress(SyncTransferProgress.preparingBundle);
        await _yieldToUi();
        final forceConvergenceUpload =
            appliedRemoteDuringSync && !hadPendingChangesBeforeRemoteApply;
        await uploadCurrentBundle(
          force: forceUpload || forceConvergenceUpload,
          allowLargeMobileTransfer: allowLargeMobileTransfer,
          silentLargeMobileSkip: silentLargeMobileSkip,
        );
        return;
      }
      _setProgress(SyncTransferProgress.finalizing);
      await _yieldToUi();
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: 'sync.info.sync_success',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      _diagnostic('sync now completed');
    } catch (error) {
      _diagnostic('sync now failed', data: {'error': error});
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<LocalNoteArchive> exportLocalArchive({
    String? password,
    Set<String>? vaultIds,
    bool includeSampleNotes = false,
  }) async {
    _startBusy(SyncTransferProgress.preparingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive export requested');
      final archive = await runFirebaseTrace(
        'notes_prepare_local_zip_archive',
        () => _buildLocalZipArchive(
          password: password,
          vaultIds: vaultIds,
          includeSampleNotes: includeSampleNotes,
        ),
      );
      if (archive.bytes.isEmpty) {
        throw StateError('ローカルアーカイブを準備できませんでした。');
      }
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message:
            'ZIP アーカイブを作成しました（ノート ${archive.noteCount} 件、添付 ${archive.attachmentCount} 件）。',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return archive;
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      rethrow;
    }
  }

  Future<SyncBundlePreview> importLocalArchiveBytes(
    List<int> bytes, {
    String? password,
  }) async {
    if (bytes.isEmpty) {
      throw StateError('選択したアーカイブは空です。');
    }
    _startBusy(SyncTransferProgress.preparingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive import selected');
      final decoded = await _decodeLocalZipArchive(bytes, password: password);
      final preview = buildSyncBundlePreview(
        decodedBundle: _zipArchiveAsSyncBundle(decoded),
        currentNotes: ref.read(notesControllerProvider),
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: '確認用の ZIP アーカイブを読み込みました。',
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return preview;
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      rethrow;
    }
  }

  Future<void> applyLocalArchiveBytes(
    List<int> bytes, {
    String? password,
  }) async {
    _startBusy(SyncTransferProgress.applyingBundle);
    try {
      await logFirebaseBreadcrumb('local zip archive apply selected');
      final decoded = await _decodeLocalZipArchive(bytes, password: password);
      final attachmentFiles = decoded.attachmentFiles;
      final importedChanges = <PreparedSyncNote>[];
      for (final rawNote in decoded.notes) {
        final note = NoteEntry.fromJson(rawNote);
        final storedByArchivePath = <String, String?>{};

        Future<NoteAttachment> importAttachment(
          NoteAttachment attachment,
        ) async {
          final filePath = attachment.filePath;
          if (filePath == null || filePath.isEmpty) {
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
            );
          }
          final bytes = attachmentFiles[filePath];
          if (bytes == null || bytes.isEmpty) {
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
            );
          }
          if (!storedByArchivePath.containsKey(filePath)) {
            final encryptedPayload = await ref
                .read(encryptedAttachmentStoreProvider)
                .encryptAttachmentBytes(
                  bytes: bytes,
                  type: attachment.type,
                  vaultId: note.vaultId,
                );
            storedByArchivePath[filePath] = await ref
                .read(encryptedAttachmentStoreProvider)
                .storeEncryptedPayload(
                  encodedPayload: encryptedPayload,
                  type: attachment.type,
                  fileNameHint: attachment.label,
                  vaultId: note.vaultId,
                );
          }
          return attachment.copyWith(
            filePath: storedByArchivePath[filePath],
            previewBytesBase64: null,
          );
        }

        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          importedAttachments.add(await importAttachment(attachment));
        }
        final importedBlocks = <NoteBlock>[];
        for (final block in note.blocks) {
          final attachment = block.attachment;
          importedBlocks.add(
            attachment == null
                ? block
                : block.copyWith(
                    attachment: await importAttachment(attachment),
                  ),
          );
        }

        importedChanges.add(
          PreparedSyncNote(
            action: PendingNoteChangeAction.upsert,
            note: note.copyWith(
              attachments: importedAttachments,
              blocks: importedBlocks,
              syncState: NoteSyncState.pendingUpload,
            ),
          ),
        );
      }
      await ref
          .read(notesControllerProvider.notifier)
          .mergeFromSync(importedChanges);
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: 'ZIP アーカイブをローカルのノートに反映しました。',
      );
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      rethrow;
    }
  }

  Future<void> downloadLatestBundle() async {
    final remoteStatus = state.remoteStatus;
    if (remoteStatus != null && remoteStatus.fileId.isNotEmpty) {
      await downloadBundle(remoteStatus);
      return;
    }
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      return;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      await logFirebaseBreadcrumb('sync download latest requested');
      final remoteBundle = await runFirebaseTrace(
        'sync_download_latest_bundle',
        _downloadLatestRemoteBundle,
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.info.no_usable_remote_bundle',
      );
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<List<RemoteSyncBundleStatus>> listRemoteBundleHistory() async {
    return _listRemoteHistory();
  }

  Future<void> downloadBundle(RemoteSyncBundleStatus remoteStatus) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      return;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      await logFirebaseBreadcrumb(
        'sync download bundle ${remoteStatus.fileId}',
      );
      final remoteBundle = await runFirebaseTrace(
        'sync_download_selected_bundle',
        () => _downloadRemoteBundleById(remoteStatus.fileId),
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.error.selected_bundle_download_failed',
      );
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<SyncBundlePreview> downloadBundlePreview(
    RemoteSyncBundleStatus remoteStatus,
  ) async {
    await downloadBundle(remoteStatus);
    if (state.stage == SyncTransferStage.error) {
      throw StateError(
        state.message ?? 'sync.error.remote_bundle_download_failed',
      );
    }
    return previewDownloadedBundle();
  }

  Future<void> applyDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: 'sync.error.download_before_apply',
      );
      return;
    }
    _startBusy(SyncTransferProgress.applyingBundle);
    try {
      await logFirebaseBreadcrumb('sync apply downloaded bundle');
      final decoded = await runFirebaseTrace(
        'sync_read_downloaded_bundle',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readBundleJson(localBundle.reference),
      );
      if (decoded == null) {
        throw StateError('sync.error.downloaded_bundle_decryption_failed');
      }
      for (final rawProfiles
          in (decoded['privateProfiles'] as List<dynamic>? ??
              const <dynamic>[])) {
        await ref
            .read(privateMemoProfileStoreProvider)
            .importSyncPayload(rawProfiles);
      }
      final rawNoteEntries =
          decoded['notes'] as List<dynamic>? ?? const <dynamic>[];
      final lockedPrivateVaultIds = <String>{};
      final attachmentPayloads = <String, Map<String, dynamic>>{
        for (final entry
            in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
          (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
      };
      final importedChanges = <PreparedSyncNote>[];
      var importedEntryCount = 0;
      final totalEntries = rawNoteEntries.length;
      for (final rawEntry in rawNoteEntries) {
        if (importedEntryCount > 0 && importedEntryCount % 25 == 0) {
          await _yieldToUi();
        }
        importedEntryCount++;
        _setProgressDetail(
          progress: SyncTransferProgress.applyingBundle,
          detail: 'Applying note',
          completedItems: importedEntryCount - 1,
          totalItems: totalEntries,
        );
        final entry = Map<String, dynamic>.from(rawEntry as Map);
        final note = NoteEntry.fromJson(
          Map<String, dynamic>.from(entry['note'] as Map),
        );
        if (isPrivateVaultId(note.vaultId) &&
            !ref
                .read(profileDataKeyServiceProvider)
                .isProfileUnlocked(note.vaultId)) {
          lockedPrivateVaultIds.add(note.vaultId);
          continue;
        }
        final action = PendingNoteChangeAction.values.firstWhere(
          (value) => value.name == entry['action'],
          orElse: () => note.deletedAt == null
              ? PendingNoteChangeAction.upsert
              : PendingNoteChangeAction.delete,
        );
        final storedBySyncAttachmentId = <String, String?>{};
        final previewBySyncAttachmentId = <String, String?>{};

        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          _setProgressDetail(
            progress: SyncTransferProgress.applyingBundle,
            detail: 'Applying attachment for note',
            completedItems: importedEntryCount - 1,
            totalItems: totalEntries,
          );
          await _yieldToUi();
          importedAttachments.add(
            await _importRemoteSyncAttachment(
              attachment: attachment,
              note: note,
              inlinePayloads: attachmentPayloads,
              storedBySyncAttachmentId: storedBySyncAttachmentId,
              previewBySyncAttachmentId: previewBySyncAttachmentId,
            ),
          );
        }
        final importedBlocks = <NoteBlock>[];
        for (final block in note.blocks) {
          final attachment = block.attachment;
          if (attachment != null) {
            _setProgressDetail(
              progress: SyncTransferProgress.applyingBundle,
              detail: 'Applying block attachment for note',
              completedItems: importedEntryCount - 1,
              totalItems: totalEntries,
            );
            await _yieldToUi();
          }
          importedBlocks.add(
            attachment == null
                ? block
                : block.copyWith(
                    attachment: await _importRemoteSyncAttachment(
                      attachment: attachment,
                      note: note,
                      inlinePayloads: attachmentPayloads,
                      storedBySyncAttachmentId: storedBySyncAttachmentId,
                      previewBySyncAttachmentId: previewBySyncAttachmentId,
                    ),
                  ),
          );
        }
        importedChanges.add(
          PreparedSyncNote(
            action: action,
            note: note.copyWith(
              attachments: importedAttachments,
              blocks: importedBlocks,
            ),
          ),
        );
      }
      if (importedChanges.isNotEmpty) {
        await ref
            .read(notesControllerProvider.notifier)
            .mergeFromSync(importedChanges);
        ref.invalidate(syncQueueSummaryProvider);
      }
      if (lockedPrivateVaultIds.isEmpty) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordApply(state.remoteStatus);
        ref.invalidate(syncBundleStateProvider);
      }
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: lockedPrivateVaultIds.isEmpty
            ? 'sync.info.apply_success'
            : _privateProfileNotesPendingUnlockMessage,
      );
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
    }
  }

  Future<int> downloadDeferredAttachments() async {
    if (!_supportsRemoteTransport(ref.read(syncProviderControllerProvider))) {
      return 0;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      var count = 0;
      var scannedNoteCount = 0;
      final currentNotes = ref.read(notesControllerProvider);
      final totalNotes = currentNotes.length;
      final hydratedNotes = <NoteEntry>[];
      for (final note in currentNotes) {
        if (scannedNoteCount > 0 && scannedNoteCount % 25 == 0) {
          await _yieldToUi();
        }
        scannedNoteCount++;
        _setProgressDetail(
          progress: SyncTransferProgress.downloadingBundle,
          detail: 'Checking attachments',
          completedItems: scannedNoteCount - 1,
          totalItems: totalNotes,
        );
        final storedBySyncAttachmentId = <String, String?>{};
        final previewBySyncAttachmentId = <String, String?>{};
        Future<NoteAttachment> hydrate(NoteAttachment attachment) async {
          final remoteRef = attachment.filePath;
          if (remoteRef == null ||
              !remoteRef.startsWith('sync-attachment-object://')) {
            return attachment;
          }
          final imported = await _importRemoteSyncAttachment(
            attachment: attachment,
            note: note,
            inlinePayloads: const <String, Map<String, dynamic>>{},
            storedBySyncAttachmentId: storedBySyncAttachmentId,
            previewBySyncAttachmentId: previewBySyncAttachmentId,
            deferOnMobile: false,
          );
          final storedPath = imported.filePath;
          if (storedPath != null && storedPath != remoteRef) {
            count += 1;
          }
          return imported;
        }

        hydratedNotes.add(
          note.copyWith(
            attachments: [
              for (final attachment in note.attachments)
                await hydrate(attachment),
            ],
            blocks: [
              for (final block in note.blocks)
                block.attachment == null
                    ? block
                    : block.copyWith(
                        attachment: await hydrate(block.attachment!),
                      ),
            ],
          ),
        );
      }
      if (count > 0) {
        await ref
            .read(notesControllerProvider.notifier)
            .replaceFromSync(hydratedNotes);
      }
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: count == 0
            ? 'sync.info.no_deferred_attachments'
            : 'sync.info.deferred_attachments_downloaded',
      );
      return count;
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      return 0;
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      return 0;
    }
  }

  Future<SyncBundlePreview> previewDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      throw StateError('sync.error.download_before_review');
    }
    try {
      final decoded = await ref
          .read(secureSyncBundleStoreProvider)
          .readBundleJson(localBundle.reference);
      if (decoded == null) {
        throw StateError('sync.error.downloaded_bundle_decryption_failed');
      }
      return buildSyncBundlePreview(
        decodedBundle: decoded,
        currentNotes: ref.read(notesControllerProvider),
      );
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      rethrow;
    }
  }

  Future<NoteEntry?> downloadLatestRemoteNoteForConflict(String noteId) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'sync.error.select_target_for_download',
      );
      return null;
    }
    _startBusy(SyncTransferProgress.downloadingBundle);
    try {
      final remoteBundle = await runFirebaseTrace(
        'sync_download_latest_bundle_for_conflict',
        _downloadLatestRemoteBundle,
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: 'sync.info.no_usable_remote_bundle',
      );
      final localBundle = state.localBundle;
      if (localBundle == null) {
        return null;
      }
      final changes = await _readPreparedChangesFromBundle(
        localBundle.reference,
      );
      for (final change in changes) {
        if (change.note.id == noteId &&
            change.action != PendingNoteChangeAction.delete) {
          return change.note.copyWith(syncState: NoteSyncState.synced);
        }
      }
      return null;
    } on HimemoDecryptionException {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
      );
      return null;
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
      return null;
    }
  }

  Future<void> recordDownloadedBundleApplied() async {
    await ref
        .read(syncBundleStateStoreProvider)
        .recordApply(state.remoteStatus);
    ref.invalidate(syncBundleStateProvider);
  }

  Future<NoteAttachment> _importRemoteSyncAttachment({
    required NoteAttachment attachment,
    required NoteEntry note,
    required Map<String, Map<String, dynamic>> inlinePayloads,
    required Map<String, String?> storedBySyncAttachmentId,
    required Map<String, String?> previewBySyncAttachmentId,
    bool deferOnMobile = true,
  }) async {
    final filePath = attachment.filePath;
    if (filePath == null) {
      return attachment;
    }
    if (filePath.startsWith('sync-attachment-object://')) {
      final contentHash = filePath.substring(
        'sync-attachment-object://'.length,
      );
      if (contentHash.isEmpty) {
        return attachment.copyWith(filePath: null, previewBytesBase64: null);
      }
      final inlinePayload = inlinePayloads[contentHash];
      final hasInlinePayload =
          inlinePayload != null &&
          ((inlinePayload['bytesBase64'] as String?)?.isNotEmpty == true ||
              (inlinePayload['encryptedPayload'] as String?)?.isNotEmpty ==
                  true);
      if (inlinePayload != null && !hasInlinePayload) {
        _diagnostic(
          'remote attachment object metadata found',
          data: {
            'contentHash': contentHash,
            'type': inlinePayload['type'],
            'label': inlinePayload['label'],
          },
        );
      }
      if (inlinePayload != null && hasInlinePayload) {
        return _importInlineSyncAttachment(
          attachment: attachment,
          note: note,
          attachmentId: contentHash,
          payload: inlinePayload,
          storedBySyncAttachmentId: storedBySyncAttachmentId,
          previewBySyncAttachmentId: previewBySyncAttachmentId,
        );
      }
      final connectionKind = await ref
          .read(networkConnectionServiceProvider)
          .currentKind();
      if (deferOnMobile && connectionKind == NetworkConnectionKind.mobile) {
        _diagnostic(
          'remote attachment object deferred on mobile',
          data: {
            'contentHash': contentHash,
            'type': attachment.type.name,
            'label': attachment.label,
          },
        );
        return attachment;
      }
      if (!storedBySyncAttachmentId.containsKey(contentHash)) {
        final encodedPayload = await _downloadRemoteAttachmentObject(
          contentHash,
        );
        if (encodedPayload == null || encodedPayload.isEmpty) {
          storedBySyncAttachmentId[contentHash] = null;
          previewBySyncAttachmentId[contentHash] =
              attachment.previewBytesBase64;
        } else {
          final decoded = await ref
              .read(secureSyncBundleStoreProvider)
              .readAttachmentObjectPayload(encodedPayload);
          final payloadHash = decoded['contentHash'] as String? ?? contentHash;
          if (payloadHash != contentHash) {
            throw StateError('sync.error.attachment_object_hash_mismatch');
          }
          final payloadType = AttachmentType.values.firstWhere(
            (value) => value.name == decoded['type'],
            orElse: () => attachment.type,
          );
          final label = decoded['label'] as String? ?? attachment.label;
          final bytesBase64 = decoded['bytesBase64'] as String?;
          if (bytesBase64 == null || bytesBase64.isEmpty) {
            storedBySyncAttachmentId[contentHash] = null;
            previewBySyncAttachmentId[contentHash] =
                attachment.previewBytesBase64;
          } else {
            final decodedBytes = await _decodeSyncAttachmentBytes(bytesBase64);
            if (decodedBytes.contentHash != contentHash) {
              throw StateError('sync.error.attachment_object_hash_mismatch');
            }
            final clearBytes = decodedBytes.bytes;
            previewBySyncAttachmentId[contentHash] =
                payloadType == AttachmentType.video
                ? await _videoPreviewBytesBase64ForBytes(
                    clearBytes,
                    label: label,
                    mimeType: 'video/mp4',
                  )
                : attachment.previewBytesBase64;
            final encryptedPayload = await ref
                .read(encryptedAttachmentStoreProvider)
                .encryptAttachmentBytes(
                  bytes: clearBytes,
                  type: payloadType,
                  vaultId: note.vaultId,
                );
            storedBySyncAttachmentId[contentHash] = await ref
                .read(encryptedAttachmentStoreProvider)
                .storeEncryptedPayload(
                  encodedPayload: encryptedPayload,
                  type: payloadType,
                  fileNameHint: label,
                  vaultId: note.vaultId,
                );
          }
        }
      }
      final storedPath = storedBySyncAttachmentId[contentHash];
      return attachment.copyWith(
        filePath: storedPath ?? attachment.filePath,
        previewBytesBase64:
            previewBySyncAttachmentId[contentHash] ??
            attachment.previewBytesBase64,
      );
    }
    if (!filePath.startsWith('sync-attachment://')) {
      return attachment;
    }
    final attachmentId = filePath.substring('sync-attachment://'.length);
    final payload = inlinePayloads[attachmentId];
    if (payload == null) {
      return attachment.copyWith(filePath: null, previewBytesBase64: null);
    }
    return _importInlineSyncAttachment(
      attachment: attachment,
      note: note,
      attachmentId: attachmentId,
      payload: payload,
      storedBySyncAttachmentId: storedBySyncAttachmentId,
      previewBySyncAttachmentId: previewBySyncAttachmentId,
    );
  }

  Future<NoteAttachment> _importInlineSyncAttachment({
    required NoteAttachment attachment,
    required NoteEntry note,
    required String attachmentId,
    required Map<String, dynamic> payload,
    required Map<String, String?> storedBySyncAttachmentId,
    required Map<String, String?> previewBySyncAttachmentId,
  }) async {
    if (!storedBySyncAttachmentId.containsKey(attachmentId)) {
      final payloadType = AttachmentType.values.firstWhere(
        (value) => value.name == payload['type'],
        orElse: () => attachment.type,
      );
      final label = payload['label'] as String? ?? attachment.label;
      final bytesBase64 = payload['bytesBase64'] as String?;
      if (bytesBase64 != null && bytesBase64.isNotEmpty) {
        final decodedBytes = await _decodeSyncAttachmentBytes(bytesBase64);
        final clearBytes = decodedBytes.bytes;
        previewBySyncAttachmentId[attachmentId] =
            payloadType == AttachmentType.video
            ? await _videoPreviewBytesBase64ForBytes(
                clearBytes,
                label: label,
                mimeType: 'video/mp4',
              )
            : null;
        final encryptedPayload = await ref
            .read(encryptedAttachmentStoreProvider)
            .encryptAttachmentBytes(
              bytes: clearBytes,
              type: payloadType,
              vaultId: note.vaultId,
            );
        storedBySyncAttachmentId[attachmentId] = await ref
            .read(encryptedAttachmentStoreProvider)
            .storeEncryptedPayload(
              encodedPayload: encryptedPayload,
              type: payloadType,
              fileNameHint: label,
              vaultId: note.vaultId,
            );
      } else {
        previewBySyncAttachmentId[attachmentId] = null;
        final legacyPayload = payload['encryptedPayload'] as String?;
        storedBySyncAttachmentId[attachmentId] =
            legacyPayload == null || legacyPayload.isEmpty
            ? null
            : await ref
                  .read(encryptedAttachmentStoreProvider)
                  .storeEncryptedPayload(
                    encodedPayload: legacyPayload,
                    type: payloadType,
                    fileNameHint: label,
                    vaultId: note.vaultId,
                  );
      }
    }
    return attachment.copyWith(
      filePath: storedBySyncAttachmentId[attachmentId],
      previewBytesBase64: previewBySyncAttachmentId[attachmentId],
    );
  }

  Future<List<PreparedSyncNote>> _readPreparedChangesFromBundle(
    String reference,
  ) async {
    final decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readBundleJson(reference);
    if (decoded == null) {
      throw StateError('sync.error.downloaded_bundle_decryption_failed');
    }
    final rawNoteEntries =
        decoded['notes'] as List<dynamic>? ?? const <dynamic>[];
    final lockedPrivateVaultIds = <String>{};
    for (final rawEntry in rawNoteEntries) {
      final entry = Map<String, dynamic>.from(rawEntry as Map);
      final note = NoteEntry.fromJson(
        Map<String, dynamic>.from(entry['note'] as Map),
      );
      if (isPrivateVaultId(note.vaultId) &&
          !ref
              .read(profileDataKeyServiceProvider)
              .isProfileUnlocked(note.vaultId)) {
        lockedPrivateVaultIds.add(note.vaultId);
      }
    }
    if (lockedPrivateVaultIds.isNotEmpty) {
      throw StateError('sync.error.private_profile_locked');
    }
    final attachmentPayloads = <String, Map<String, dynamic>>{
      for (final entry
          in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
        (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
    };
    final importedChanges = <PreparedSyncNote>[];
    for (final rawEntry in rawNoteEntries) {
      final entry = Map<String, dynamic>.from(rawEntry as Map);
      final note = NoteEntry.fromJson(
        Map<String, dynamic>.from(entry['note'] as Map),
      );
      final action = PendingNoteChangeAction.values.firstWhere(
        (value) => value.name == entry['action'],
        orElse: () => note.deletedAt == null
            ? PendingNoteChangeAction.upsert
            : PendingNoteChangeAction.delete,
      );
      final storedBySyncAttachmentId = <String, String?>{};
      final previewBySyncAttachmentId = <String, String?>{};

      final importedAttachments = <NoteAttachment>[];
      for (final attachment in note.attachments) {
        importedAttachments.add(
          await _importRemoteSyncAttachment(
            attachment: attachment,
            note: note,
            inlinePayloads: attachmentPayloads,
            storedBySyncAttachmentId: storedBySyncAttachmentId,
            previewBySyncAttachmentId: previewBySyncAttachmentId,
          ),
        );
      }
      final importedBlocks = <NoteBlock>[];
      for (final block in note.blocks) {
        final attachment = block.attachment;
        importedBlocks.add(
          attachment == null
              ? block
              : block.copyWith(
                  attachment: await _importRemoteSyncAttachment(
                    attachment: attachment,
                    note: note,
                    inlinePayloads: attachmentPayloads,
                    storedBySyncAttachmentId: storedBySyncAttachmentId,
                    previewBySyncAttachmentId: previewBySyncAttachmentId,
                  ),
                ),
        );
      }
      importedChanges.add(
        PreparedSyncNote(
          action: action,
          note: note.copyWith(
            attachments: importedAttachments,
            blocks: importedBlocks,
          ),
        ),
      );
    }
    return importedChanges;
  }

  Future<void> _storeDownloadedBundle(
    DownloadedRemoteSyncBundle? remoteBundle, {
    required String emptyMessage,
  }) async {
    if (remoteBundle == null) {
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: emptyMessage,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
      return;
    }
    final localBundle = await ref
        .read(secureSyncBundleStoreProvider)
        .writeEncryptedBundlePayload(
          remoteBundle.encodedPayload,
          noteCount: remoteBundle.status.noteCount ?? 0,
          attachmentCount: remoteBundle.status.attachmentCount ?? 0,
          fileNameOverride: 'downloaded_sync_bundle.enc',
        );
    state = SyncTransferState(
      stage: SyncTransferStage.success,
      message: 'sync.info.remote_bundle_saved_locally',
      remoteStatus: remoteBundle.status,
      localBundle: localBundle,
    );
    await ref
        .read(syncBundleStateStoreProvider)
        .recordRemoteStatus(remoteBundle.status);
  }

  bool _supportsRemoteTransport(SyncProvider provider) {
    return provider == SyncProvider.googleDrive ||
        provider == SyncProvider.iCloud;
  }

  bool _remoteBundleNeedsApply(
    RemoteSyncBundleStatus remoteStatus,
    SyncBundleState bundleState,
  ) {
    return remoteBundleNeedsApplyForSync(remoteStatus, bundleState);
  }

  Future<LocalNoteArchive> _buildLocalZipArchive({
    String? password,
    Set<String>? vaultIds,
    bool includeSampleNotes = false,
  }) async {
    final exportedAt = DateTime.now();
    final notes = ref
        .read(notesControllerProvider)
        .where((entry) => entry.deletedAt == null)
        .where(
          (entry) =>
              vaultIds == null ||
              vaultIds.isEmpty ||
              vaultIds.contains(entry.vaultId),
        )
        .where((entry) => includeSampleNotes || !isGeneratedSampleNote(entry))
        .toList(growable: false);
    final archiveFiles = <_LocalArchiveFilePayload>[];
    final exportedNotes = <Map<String, dynamic>>[];
    var attachmentCount = 0;

    for (final note in notes) {
      final archivePathByAttachmentKey = <String, String>{};

      Future<NoteAttachment> exportAttachment(
        NoteAttachment attachment,
        int index,
      ) async {
        final filePath = attachment.filePath;
        if (filePath == null || filePath.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        final key = _attachmentExportKey(attachment);
        final existingPath = archivePathByAttachmentKey[key];
        if (existingPath != null) {
          return attachment.copyWith(
            filePath: existingPath,
            previewBytesBase64: null,
          );
        }
        final bytes = await ref
            .read(encryptedAttachmentStoreProvider)
            .readAttachment(filePath, type: attachment.type);
        if (bytes == null || bytes.isEmpty) {
          return attachment.copyWith(filePath: null, previewBytesBase64: null);
        }
        final archivePath = _archiveAttachmentPath(
          noteId: note.id,
          index: index,
          label: attachment.label,
        );
        archiveFiles.add(
          _LocalArchiveFilePayload(
            name: archivePath,
            bytes: TransferableTypedData.fromList([
              bytes is Uint8List ? bytes : Uint8List.fromList(bytes),
            ]),
          ),
        );
        archivePathByAttachmentKey[key] = archivePath;
        attachmentCount += 1;
        return attachment.copyWith(
          filePath: archivePath,
          previewBytesBase64: null,
        );
      }

      final exportedAttachments = <NoteAttachment>[];
      for (var i = 0; i < note.attachments.length; i++) {
        exportedAttachments.add(await exportAttachment(note.attachments[i], i));
      }
      final exportedBlocks = <NoteBlock>[];
      for (var i = 0; i < note.blocks.length; i++) {
        final block = note.blocks[i];
        final attachment = block.attachment;
        exportedBlocks.add(
          attachment == null
              ? block
              : block.copyWith(
                  attachment: await exportAttachment(
                    attachment,
                    note.attachments.length + i,
                  ),
                ),
        );
      }

      exportedNotes.add(
        note
            .copyWith(
              attachments: exportedAttachments,
              blocks: exportedBlocks,
              syncState: NoteSyncState.localOnly,
            )
            .toJson(),
      );
    }

    final manifest = {
      'format': 'org.ruhenheim.himemo.notes.zip',
      'version': 1,
      'exportedAt': exportedAt.toIso8601String(),
      'encryption': password == null || password.isEmpty
          ? 'none'
          : 'zip-aes-256',
      'noteCount': exportedNotes.length,
      'attachmentCount': attachmentCount,
      'contents': ['notes.json', 'attachments/'],
    };
    final encoded = await _encodeLocalZipArchive(
      manifest: manifest,
      notes: exportedNotes,
      files: archiveFiles,
      password: password,
    );
    if (encoded.isEmpty) {
      throw StateError('ZIP archive could not be encoded.');
    }
    return LocalNoteArchive(
      bytes: Uint8List.fromList(encoded),
      fileName: _localArchiveFileName(
        exportedAt,
        passwordProtected: password != null && password.isNotEmpty,
      ),
      noteCount: exportedNotes.length,
      attachmentCount: attachmentCount,
      isPasswordProtected: password != null && password.isNotEmpty,
    );
  }

  Future<_DecodedLocalZipArchive> _decodeLocalZipArchive(
    List<int> bytes, {
    String? password,
  }) async {
    final source = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
    if (kIsWeb || source.lengthInBytes < 512 * 1024) {
      return _decodeLocalZipArchivePayloadInBackground(
        _LocalZipDecodeRequest(
          bytes: TransferableTypedData.fromList([source]),
          password: password,
        ),
      );
    }
    return Isolate.run(
      () => _decodeLocalZipArchivePayloadInBackground(
        _LocalZipDecodeRequest(
          bytes: TransferableTypedData.fromList([source]),
          password: password,
        ),
      ),
    );
  }

  Future<Uint8List> _encodeLocalZipArchive({
    required Map<String, dynamic> manifest,
    required List<Map<String, dynamic>> notes,
    required List<_LocalArchiveFilePayload> files,
    String? password,
  }) async {
    final request = _LocalZipEncodeRequest(
      manifest: manifest,
      notes: notes,
      files: files,
      password: password == null || password.isEmpty ? null : password,
    );
    if (kIsWeb) {
      final encoded = _encodeLocalZipArchivePayloadInBackground(request);
      return encoded.materialize().asUint8List();
    }
    final encoded = await Isolate.run(
      () => _encodeLocalZipArchivePayloadInBackground(request),
    );
    return encoded.materialize().asUint8List();
  }

  Map<String, dynamic> _zipArchiveAsSyncBundle(
    _DecodedLocalZipArchive archive,
  ) {
    return {
      'deviceId': 'local-zip',
      'exportedAt': archive.manifest['exportedAt'],
      'notes': [
        for (final note in archive.notes)
          {'action': PendingNoteChangeAction.upsert.name, 'note': note},
      ],
      'attachments': [
        for (final entry in archive.attachmentFiles.entries)
          {'id': entry.key, 'encryptedPayload': '', 'type': 'file'},
      ],
    };
  }

  String _attachmentExportKey(NoteAttachment attachment) {
    return [
      attachment.type.name,
      attachment.label,
      attachment.filePath ?? '',
      attachment.durationMs?.toString() ?? '',
    ].join('\u0000');
  }

  String _archiveAttachmentPath({
    required String noteId,
    required int index,
    required String label,
  }) {
    final rawName = path.basename(label).trim();
    final safeName = _safeArchiveSegment(
      rawName.isEmpty ? 'attachment.bin' : rawName,
    );
    return 'attachments/${_safeArchiveSegment(noteId)}_${index}_$safeName';
  }

  String _safeArchiveSegment(String value) {
    final safe = value
        .replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return safe.isEmpty ? 'file' : safe;
  }

  String _localArchiveFileName(
    DateTime exportedAt, {
    required bool passwordProtected,
  }) {
    String two(int value) => value.toString().padLeft(2, '0');
    final stamp =
        '${exportedAt.year}${two(exportedAt.month)}${two(exportedAt.day)}_${two(exportedAt.hour)}${two(exportedAt.minute)}${two(exportedAt.second)}';
    final suffix = passwordProtected ? 'encrypted' : 'plain';
    return 'himemo_archive_${suffix}_$stamp.zip';
  }

  Future<RemoteSyncBundleStatus?> _fetchLatestRemoteStatus() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).fetchLatestBundleStatus(),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .fetchLatestBundleStatus(),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<void> _refreshRemoteStatusInBackground() async {
    try {
      final provider = ref.read(syncProviderControllerProvider);
      final remoteStatus = await _fetchLatestRemoteStatus();
      _cacheRemoteStatus(provider, remoteStatus);
      if (remoteStatus != null) {
        await ref
            .read(syncBundleStateStoreProvider)
            .recordRemoteStatus(remoteStatus);
        state = state.copyWith(remoteStatus: remoteStatus);
      }
    } catch (_) {}
  }

  Future<List<RemoteSyncBundleStatus>> _listRemoteHistory() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).listBundleHistory(),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref.read(googleDriveSyncTransportProvider).listBundleHistory(),
      ),
      SyncProvider.off => Future.value(const <RemoteSyncBundleStatus>[]),
    };
  }

  Future<RemoteSyncBundleStatus> _uploadRemoteBundle({
    required String encodedPayload,
    required String deviceId,
    required int noteCount,
    required int attachmentCount,
  }) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .uploadBundle(
              encodedPayload: encodedPayload,
              deviceId: deviceId,
              noteCount: noteCount,
              attachmentCount: attachmentCount,
            ),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .uploadBundle(
              encodedPayload: encodedPayload,
              deviceId: deviceId,
              noteCount: noteCount,
              attachmentCount: attachmentCount,
            ),
      ),
      SyncProvider.off => Future.error(
        StateError('Remote sync is not enabled.'),
      ),
    };
  }

  Future<void> _uploadRemoteAttachmentObjects(
    List<PreparedSyncAttachment> attachments,
  ) async {
    if (attachments.isEmpty) {
      return;
    }
    final uniqueAttachments = <String, PreparedSyncAttachment>{};
    for (final attachment in attachments) {
      uniqueAttachments.putIfAbsent(attachment.contentHash, () => attachment);
    }
    final unique = uniqueAttachments.values.toList(growable: false);
    final totalBytes = unique.fold<int>(
      0,
      (total, attachment) => total + attachment.sizeBytes,
    );
    _diagnostic(
      'attachment object upload start',
      data: {
        'requested': attachments.length,
        'unique': unique.length,
        'bytes': totalBytes,
      },
    );
    final existingHashes = await _listExistingRemoteAttachmentHashes();
    final pendingUploads = existingHashes == null
        ? unique
        : unique
              .where(
                (attachment) =>
                    !existingHashes.contains(attachment.contentHash),
              )
              .toList(growable: false);
    final skipped = unique.length - pendingUploads.length;
    _setProgressDetail(
      progress: SyncTransferProgress.uploadingBundle,
      detail: 'Checking attachment objects',
      completedItems: skipped,
      totalItems: unique.length,
    );
    await _yieldToUi();
    if (existingHashes != null) {
      _diagnostic(
        'attachment object upload existing checked',
        data: {
          'remoteKnown': existingHashes.length,
          'skipped': skipped,
          'pending': pendingUploads.length,
        },
      );
    }
    if (pendingUploads.isEmpty) {
      _setProgressDetail(
        progress: SyncTransferProgress.uploadingBundle,
        detail: 'Attachments already uploaded',
        completedItems: unique.length,
        totalItems: unique.length,
      );
      await _yieldToUi();
      _diagnostic(
        'attachment object upload progress',
        data: {
          'uploaded': unique.length,
          'total': unique.length,
          'skipped': skipped,
        },
      );
      return;
    }
    final bundleStore = ref.read(secureSyncBundleStoreProvider);
    var uploaded = 0;
    for (final attachment in pendingUploads) {
      final completedBefore = skipped + uploaded;
      _setProgressDetail(
        progress: SyncTransferProgress.uploadingBundle,
        detail: 'Uploading attachment',
        completedItems: completedBefore,
        totalItems: unique.length,
      );
      await _yieldToUi();
      final encodedPayload = await bundleStore.writeAttachmentObjectPayload(
        attachment,
      );
      await _yieldToUi();
      await _uploadRemoteAttachmentObject(
        contentHash: attachment.contentHash,
        encodedPayload: encodedPayload,
        type: attachment.type.name,
        label: attachment.label,
        sizeBytes: attachment.sizeBytes,
        skipExistingCheck: existingHashes != null,
      );
      uploaded += 1;
      final completed = skipped + uploaded;
      _setProgressDetail(
        progress: SyncTransferProgress.uploadingBundle,
        detail: 'Uploaded attachment',
        completedItems: completed,
        totalItems: unique.length,
      );
      await _yieldToUi();
      if (completed % 5 == 0 || completed == unique.length) {
        _diagnostic(
          'attachment object upload progress',
          data: {
            'uploaded': completed,
            'total': unique.length,
            'skipped': skipped,
          },
        );
      }
    }
  }

  Future<Set<String>?> _listExistingRemoteAttachmentHashes() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .listAttachmentObjectContentHashes(),
      ),
      SyncProvider.iCloud || SyncProvider.off => Future<Set<String>?>.value(),
    };
  }

  Future<void> _uploadRemoteAttachmentObject({
    required String contentHash,
    required String encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
    bool skipExistingCheck = false,
  }) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .uploadAttachmentObject(
              contentHash: contentHash,
              encodedPayload: encodedPayload,
              type: type,
              label: label,
              sizeBytes: sizeBytes,
              skipExistingCheck: skipExistingCheck,
            ),
      ),
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .uploadAttachmentObject(
              contentHash: contentHash,
              encodedPayload: encodedPayload,
              type: type,
              label: label,
              sizeBytes: sizeBytes,
              skipExistingCheck: skipExistingCheck,
            ),
      SyncProvider.off => Future<void>.value(),
    };
  }

  Future<String?> _downloadRemoteAttachmentObject(String contentHash) async {
    final provider = ref.read(syncProviderControllerProvider);
    Future<String?> download() => switch (provider) {
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .downloadAttachmentObject(contentHash),
      ),
      SyncProvider.iCloud =>
        ref
            .read(iCloudSyncTransportProvider)
            .downloadAttachmentObject(contentHash),
      SyncProvider.off => Future<String?>.value(),
    };
    var encodedPayload = await download();
    if ((encodedPayload == null || encodedPayload.isEmpty) &&
        provider == SyncProvider.iCloud) {
      for (final delay in const [
        Duration(milliseconds: 700),
        Duration(seconds: 2),
        Duration(seconds: 4),
      ]) {
        await Future<void>.delayed(delay);
        encodedPayload = await download();
        if (encodedPayload != null && encodedPayload.isNotEmpty) {
          break;
        }
      }
    }
    if (encodedPayload == null || encodedPayload.isEmpty) {
      _diagnostic(
        'remote attachment object unavailable',
        data: {'provider': provider.name, 'contentHash': contentHash},
      );
    }
    return encodedPayload;
  }

  Future<DownloadedRemoteSyncBundle?> _downloadLatestRemoteBundle() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadLatestBundle(),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref.read(googleDriveSyncTransportProvider).downloadLatestBundle(),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<DownloadedRemoteSyncBundle?> _downloadRemoteBundleById(String id) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadBundleByRecordName(id),
      SyncProvider.googleDrive => _withGoogleDriveAuthRecovery(
        () => ref
            .read(googleDriveSyncTransportProvider)
            .downloadBundleByFileId(id),
      ),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<T> _withGoogleDriveAuthRecovery<T>(
    Future<T> Function() operation,
  ) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      if (!_isRecoverableGoogleDriveAuthorizationError(error)) {
        rethrow;
      }
      final authController = ref.read(syncAuthControllerProvider.notifier);
      await authController.connect(SyncProvider.googleDrive);
      if (!authController.stateFor(SyncProvider.googleDrive).isAuthenticated) {
        Error.throwWithStackTrace(error, stackTrace);
      }
      return await operation();
    }
  }

  bool _isRecoverableGoogleDriveAuthorizationError(Object error) {
    return error is GoogleDriveAuthConfigurationException &&
        error.message.contains('Google Drive authorization is not available');
  }

  SyncTransferState _failureState(
    Object error, {
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
  }) {
    if (error is HimemoDecryptionException) {
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: _syncBundleDecryptionMessage,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
      );
    }
    if (error is StateError &&
        error.message == 'Sync bundle key is not available.') {
      final provider = ref.read(syncProviderControllerProvider);
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: provider == SyncProvider.iCloud
            ? _iCloudSyncBundleKeyWaitingMessage
            : _syncBundleKeyMissingMessage,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
      );
    }
    if (error is GoogleDriveSyncException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) {
        _scheduleCooldownRefresh(retryAfter);
      }
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: error.message,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
        cooldownUntil: retryAfter == null
            ? null
            : DateTime.now().add(retryAfter),
      );
    }
    if (error is ICloudSyncException) {
      final retryAfter = error.retryAfter;
      if (retryAfter != null) {
        _scheduleCooldownRefresh(retryAfter);
      }
      return SyncTransferState(
        stage: SyncTransferStage.error,
        message: error.message,
        remoteStatus: remoteStatus,
        localBundle: localBundle,
        cooldownUntil: retryAfter == null
            ? null
            : DateTime.now().add(retryAfter),
      );
    }
    return SyncTransferState(
      stage: SyncTransferStage.error,
      message: '$error',
      remoteStatus: remoteStatus,
      localBundle: localBundle,
    );
  }

  void _scheduleCooldownRefresh(Duration duration) {
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer(duration, () {
      state = state.copyWith(clearCooldown: true);
    });
  }
}

class _DecodedSyncAttachmentBytes {
  const _DecodedSyncAttachmentBytes({
    required this.bytes,
    required this.contentHash,
  });

  final Uint8List bytes;
  final String contentHash;
}

Future<_DecodedSyncAttachmentBytes> _decodeSyncAttachmentBytes(
  String bytesBase64,
) async {
  if (kIsWeb) {
    final bytes = Uint8List.fromList(base64Decode(bytesBase64));
    return _DecodedSyncAttachmentBytes(
      bytes: bytes,
      contentHash: sha256.convert(bytes).toString(),
    );
  }
  final result = await Isolate.run(() {
    final bytes = Uint8List.fromList(base64Decode(bytesBase64));
    return <String, Object>{
      'bytes': TransferableTypedData.fromList([bytes]),
      'contentHash': sha256.convert(bytes).toString(),
    };
  });
  final transferable = result['bytes']! as TransferableTypedData;
  return _DecodedSyncAttachmentBytes(
    bytes: transferable.materialize().asUint8List(),
    contentHash: result['contentHash']! as String,
  );
}

_DecodedLocalZipArchive _decodeLocalZipArchivePayloadInBackground(
  _LocalZipDecodeRequest request,
) {
  final archive = ZipDecoder().decodeBytes(
    request.bytes.materialize().asUint8List(),
    password: request.password,
  );
  final manifestFile = archive.findFile('manifest.json');
  final notesFile = archive.findFile('notes.json');
  if (manifestFile == null || notesFile == null) {
    throw StateError('This file is not a HiMemo ZIP archive.');
  }
  final manifest = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(manifestFile.content)) as Map,
  );
  final notesPayload = Map<String, dynamic>.from(
    jsonDecode(utf8.decode(notesFile.content)) as Map,
  );
  final notes = [
    for (final entry
        in (notesPayload['notes'] as List<dynamic>? ?? const <dynamic>[]))
      Map<String, dynamic>.from(entry as Map),
  ];
  final attachmentFiles = <String, Uint8List>{};
  for (final file in archive.files) {
    if (!file.isFile || !file.name.startsWith('attachments/')) {
      continue;
    }
    attachmentFiles[file.name] = Uint8List.fromList(file.content);
  }
  return _DecodedLocalZipArchive(
    manifest: manifest,
    notes: notes,
    attachmentFiles: attachmentFiles,
  );
}

TransferableTypedData _encodeLocalZipArchivePayloadInBackground(
  _LocalZipEncodeRequest request,
) {
  final archive = Archive();
  archive.addFile(
    ArchiveFile.string('manifest.json', jsonEncode(request.manifest)),
  );
  archive.addFile(
    ArchiveFile.string(
      'notes.json',
      jsonEncode({'schemaVersion': 1, 'notes': request.notes}),
    ),
  );
  for (final file in request.files) {
    archive.addFile(
      ArchiveFile.bytes(file.name, file.bytes.materialize().asUint8List()),
    );
  }
  final encoded = ZipEncoder(password: request.password).encode(archive);
  return TransferableTypedData.fromList([
    encoded is Uint8List ? encoded : Uint8List.fromList(encoded),
  ]);
}

class PrivateMemoProfileStore {
  PrivateMemoProfileStore({
    required SecureKeyValueStore secureStore,
    required EncryptionService encryptionService,
    required ProfileDataKeyService profileDataKeyService,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.listStorageKey = 'security.private_profiles.list.v1',
    this.verifierStoragePrefix = 'security.private_profile.verifier.',
  }) : _secureStore = secureStore,
       _encryptionService = encryptionService,
       _profileDataKeyService = profileDataKeyService,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final SecureKeyValueStore _secureStore;
  final EncryptionService _encryptionService;
  final ProfileDataKeyService _profileDataKeyService;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String listStorageKey;
  final String verifierStoragePrefix;

  Future<List<PrivateMemoProfile>> listProfiles() async {
    final prefs = await _sharedPreferencesProvider();
    final payload = prefs.getString(listStorageKey);
    if (payload == null || payload.isEmpty) {
      return const <PrivateMemoProfile>[];
    }
    try {
      final decoded = (jsonDecode(payload) as List)
          .cast<Map>()
          .map(
            (entry) => PrivateMemoProfile.fromJson(
              Map<String, dynamic>.from(entry.cast<String, dynamic>()),
            ),
          )
          .toList(growable: false);
      return decoded;
    } catch (_) {
      return const <PrivateMemoProfile>[];
    }
  }

  Future<bool> hasProfiles() async => (await listProfiles()).isNotEmpty;

  Future<Map<String, dynamic>> exportSyncPayload() async {
    final profiles = await listProfiles();
    final verifiers = <Map<String, dynamic>>[];
    for (final profile in profiles) {
      final stored = await _secureStore.read(
        '$verifierStoragePrefix${profile.id}',
      );
      if (stored == null || stored.isEmpty) {
        continue;
      }
      try {
        final decoded = Map<String, dynamic>.from(jsonDecode(stored) as Map);
        if (decoded['salt'] is String && decoded['verifier'] is String) {
          verifiers.add(<String, dynamic>{'profileId': profile.id, ...decoded});
        }
      } catch (_) {}
    }
    final dataKeys = await _profileDataKeyService.exportWrappedProfileKeys(
      profiles.map((profile) => profile.vaultId),
    );
    return <String, dynamic>{
      'version': 1,
      'profiles': [for (final profile in profiles) profile.toJson()],
      'verifiers': verifiers,
      'dataKeys': dataKeys,
    };
  }

  Future<int> importSyncPayload(Object? payload) async {
    if (payload is! Map) {
      return 0;
    }
    final decoded = Map<String, dynamic>.from(payload);
    if (decoded['version'] != 1) {
      return 0;
    }

    var imported = 0;
    final existing = await listProfiles();
    final profilesById = <String, PrivateMemoProfile>{
      for (final profile in existing) profile.id: profile,
    };
    for (final rawProfile
        in (decoded['profiles'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawProfile is! Map) {
        continue;
      }
      try {
        final profile = PrivateMemoProfile.fromJson(
          Map<String, dynamic>.from(rawProfile),
        );
        profilesById[profile.id] = profile;
        imported += 1;
      } catch (_) {}
    }
    if (imported > 0) {
      final profiles = profilesById.values.toList(growable: false)
        ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      await _saveProfiles(profiles);
    }

    for (final rawVerifier
        in (decoded['verifiers'] as List<dynamic>? ?? const <dynamic>[])) {
      if (rawVerifier is! Map) {
        continue;
      }
      final verifier = Map<String, dynamic>.from(rawVerifier);
      final profileId = verifier['profileId'] as String?;
      final salt = verifier['salt'];
      final secretVerifier = verifier['verifier'];
      if (profileId == null ||
          !profilesById.containsKey(profileId) ||
          salt is! String ||
          salt.isEmpty ||
          secretVerifier is! String ||
          secretVerifier.isEmpty) {
        continue;
      }
      await _secureStore.write(
        '$verifierStoragePrefix$profileId',
        jsonEncode({'salt': salt, 'verifier': secretVerifier}),
      );
      imported += 1;
    }

    imported += await _profileDataKeyService.importWrappedProfileKeys(
      decoded['dataKeys'] as List<dynamic>? ?? const <dynamic>[],
      overwrite: true,
    );
    return imported;
  }

  Future<String?> addProfile({
    required String name,
    required String password,
  }) async {
    final existing = await listProfiles();
    final duplicate = await verifyAny(password);
    if (duplicate != null) {
      return 'That password already unlocks another profile.';
    }
    final profile = PrivateMemoProfile(
      id: _createProfileId(),
      name: name.trim().isEmpty
          ? _nextDefaultName(existing.length + 1)
          : name.trim(),
      createdAt: DateTime.now(),
    );
    final salt = _encryptionService.generateSalt();
    final verifier = await _encryptionService.deriveSecretVerifier(
      secret: password,
      salt: salt,
    );
    await _secureStore.write(
      '$verifierStoragePrefix${profile.id}',
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
    await _profileDataKeyService.configureProfile(
      vaultId: profile.vaultId,
      password: password,
    );
    await _saveProfiles([...existing, profile]);
    return null;
  }

  Future<UnlockProfileResult?> verifyAny(String password) async {
    final profiles = await listProfiles();
    for (final profile in profiles) {
      final matched = await _verifyProfilePassword(profile.id, password);
      if (matched) {
        await _profileDataKeyService.unlockProfile(
          vaultId: profile.vaultId,
          password: password,
        );
        return UnlockProfileResult(
          vaultId: profile.vaultId,
          label: profile.name,
          isLegacy: false,
        );
      }
    }
    return null;
  }

  Future<void> deleteProfile(String id) async {
    final existing = await listProfiles();
    await _saveProfiles(
      existing.where((profile) => profile.id != id).toList(growable: false),
    );
    await _secureStore.delete('$verifierStoragePrefix$id');
    await _profileDataKeyService.deleteProfileKey(
      '$customPrivateVaultPrefix$id',
    );
  }

  Future<void> updateProfilePassword({
    required String id,
    required String password,
  }) async {
    final profiles = await listProfiles();
    if (!profiles.any((profile) => profile.id == id)) {
      return;
    }
    final vaultId = '$customPrivateVaultPrefix$id';
    if (!_profileDataKeyService.isProfileUnlocked(vaultId)) {
      return;
    }
    final encryption = EncryptionService();
    final salt = encryption.generateSalt();
    final verifier = await encryption.deriveSecretVerifier(
      secret: password,
      salt: salt,
    );
    final changed = await _profileDataKeyService.changeProfilePassword(
      vaultId: vaultId,
      newPassword: password,
    );
    if (!changed) {
      return;
    }
    await _secureStore.write(
      '$verifierStoragePrefix$id',
      jsonEncode({'salt': base64Encode(salt), 'verifier': verifier}),
    );
  }

  Future<bool> _verifyProfilePassword(String id, String password) async {
    final stored = await _secureStore.read('$verifierStoragePrefix$id');
    if (stored == null || stored.isEmpty) {
      return false;
    }
    try {
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      final verifier = await _encryptionService.deriveSecretVerifier(
        secret: password,
        salt: base64Decode(decoded['salt'] as String),
      );
      return verifier == decoded['verifier'];
    } catch (_) {
      return false;
    }
  }

  Future<void> _saveProfiles(List<PrivateMemoProfile> profiles) async {
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString(
      listStorageKey,
      jsonEncode([for (final profile in profiles) profile.toJson()]),
    );
  }

  String _createProfileId() {
    final random = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
    return 'profile_$random';
  }

  String _nextDefaultName(int index) => 'Profile $index';
}

final privateMemoProfileStoreProvider = Provider<PrivateMemoProfileStore>((
  ref,
) {
  return PrivateMemoProfileStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
    profileDataKeyService: ref.watch(profileDataKeyServiceProvider),
  );
});

final privateVaultSecretStoreProvider = Provider<PrivateVaultSecretStore>((
  ref,
) {
  return PrivateVaultSecretStore(
    secureStore: ref.watch(secureKeyValueStoreProvider),
    encryptionService: ref.watch(encryptionServiceProvider),
  );
});

@Riverpod(keepAlive: true)
HomeRepository homeRepository(Ref ref) {
  final appLocale = ref.watch(appLocaleControllerProvider);
  final deviceLanguage = ui.PlatformDispatcher.instance.locale.languageCode;
  final useEnglishSeedData = switch (appLocale) {
    AppLocaleSetting.english => true,
    AppLocaleSetting.japanese => false,
    AppLocaleSetting.chinese => true,
    AppLocaleSetting.korean => true,
    AppLocaleSetting.spanish => true,
    AppLocaleSetting.german => true,
    AppLocaleSetting.system => deviceLanguage != 'ja',
  };
  return SeededHomeRepository(useEnglishSeedData: useEnglishSeedData);
}

final appSessionUnlockControllerProvider =
    NotifierProvider<AppSessionUnlockController, bool>(
      AppSessionUnlockController.new,
    );

class AppSessionUnlockController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() {
    final changed = !state;
    state = true;
    if (changed) {
      logAudit('session_unlock');
    }
  }

  void lock() {
    final changed = state;
    state = false;
    if (changed) {
      logAudit('session_lock');
    }
  }
}

final appPinLockControllerProvider =
    NotifierProvider<AppPinLockController, AppPinLockState>(
      AppPinLockController.new,
    );

class AppPinLockController extends Notifier<AppPinLockState> {
  bool _restored = false;

  @override
  AppPinLockState build() {
    if (!_restored) {
      _restored = true;
      unawaited(refresh());
    }
    return const AppPinLockState.unconfigured();
  }

  Future<void> refresh() async {
    try {
      final configured = await ref.read(appPinLockStoreProvider).hasPin();
      state = AppPinLockState(isConfigured: configured);
    } catch (error) {
      state = AppPinLockState(isConfigured: false, lastError: '$error');
    }
  }

  Future<void> configure(String pin) async {
    await ref.read(appPinLockStoreProvider).configure(pin);
    state = const AppPinLockState(isConfigured: true);
    ref.read(appSessionUnlockControllerProvider.notifier).unlock();
  }

  Future<bool> verify(String pin) async {
    try {
      final matched = await ref.read(appPinLockStoreProvider).verify(pin);
      state = AppPinLockState(
        isConfigured: state.isConfigured,
        lastError: matched ? null : 'The PIN did not match.',
      );
      if (matched) {
        ref.read(appSessionUnlockControllerProvider.notifier).unlock();
      }
      return matched;
    } catch (error) {
      state = AppPinLockState(
        isConfigured: state.isConfigured,
        lastError: '$error',
      );
      return false;
    }
  }

  Future<void> clear() async {
    await ref.read(appPinLockStoreProvider).clear();
    state = const AppPinLockState.unconfigured();
    ref.read(appSessionUnlockControllerProvider.notifier).unlock();
  }
}

final coverModeSecretControllerProvider =
    NotifierProvider<CoverModeSecretController, bool>(
      CoverModeSecretController.new,
    );

class CoverModeSecretController extends Notifier<bool> {
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> configure(String secret) async {
    await ref.read(coverModeSecretStoreProvider).configure(secret);
    state = true;
  }

  Future<bool> verify(String secret) async {
    try {
      return await ref.read(coverModeSecretStoreProvider).verify(secret);
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    await ref.read(coverModeSecretStoreProvider).clear();
    state = false;
  }

  Future<void> _restore() async {
    try {
      state = await ref.read(coverModeSecretStoreProvider).hasSecret();
    } catch (_) {}
  }
}

final deviceAuthControllerProvider =
    NotifierProvider<DeviceAuthController, DeviceAuthState>(
      DeviceAuthController.new,
    );

class DeviceAuthController extends Notifier<DeviceAuthState> {
  Future<bool>? _pendingAuthentication;

  @override
  DeviceAuthState build() {
    unawaited(refresh());
    return const DeviceAuthState.unknown();
  }

  Future<void> refresh() async {
    final refreshed = await ref
        .read(deviceAuthGatewayProvider)
        .checkAvailability();
    state = refreshed.copyWith(
      isAuthenticating: _pendingAuthentication != null,
    );
  }

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final pendingAuthentication = _pendingAuthentication;
    if (pendingAuthentication != null) {
      return pendingAuthentication;
    }
    state = state.copyWith(isAuthenticating: true);
    final future = _runAuthentication(
      reason: reason,
      biometricOnly: biometricOnly,
    );
    _pendingAuthentication = future;
    return future;
  }

  Future<bool> _runAuthentication({
    required String reason,
    required bool biometricOnly,
  }) async {
    var authenticated = false;
    try {
      authenticated = await ref
          .read(deviceAuthGatewayProvider)
          .authenticate(reason: reason, biometricOnly: biometricOnly);
      if (authenticated) {
        ref.read(appSessionUnlockControllerProvider.notifier).unlock();
      }
      return authenticated;
    } finally {
      _pendingAuthentication = null;
      await refresh();
    }
  }
}

final syncAuthControllerProvider =
    NotifierProvider<SyncAuthController, Map<SyncProvider, SyncAuthState>>(
      SyncAuthController.new,
    );

class SyncAuthController extends Notifier<Map<SyncProvider, SyncAuthState>> {
  static const _storageKey = 'sync.auth_accounts.v1';
  static const _integrityApprovalKey = 'sync.integrity_approved.v1';
  static const _googleScopes = <String>[
    'https://www.googleapis.com/auth/drive.appdata',
  ];
  bool _restored = false;

  @override
  Map<SyncProvider, SyncAuthState> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return {
      for (final provider in SyncProvider.values)
        provider: SyncAuthState.idle(provider),
    };
  }

  SyncAuthState stateFor(SyncProvider provider) =>
      state[provider] ?? SyncAuthState.idle(provider);

  Future<void> connectSelected() async {
    await connect(ref.read(syncProviderControllerProvider));
  }

  Future<void> connect(SyncProvider provider) async {
    if (provider == SyncProvider.off) {
      _update(provider, SyncAuthState.idle(provider));
      return;
    }

    _update(
      provider,
      stateFor(
        provider,
      ).copyWith(stage: SyncAuthStage.busy, clearMessage: true),
    );

    final requiresIntegrity = provider == SyncProvider.googleDrive;
    final alreadyApproved =
        !requiresIntegrity || await _hasIntegrityApproval(provider);
    if (!alreadyApproved) {
      final verification = await ref
          .read(playIntegrityVerifierProvider)
          .verifyOperation(
            flavor: ref.read(currentAppFlavorProvider),
            operation: 'sync.enable',
            payload: {'provider': provider.name},
          );
      if (!verification.allowed) {
        _update(
          provider,
          stateFor(
            provider,
          ).copyWith(stage: SyncAuthStage.error, message: verification.message),
        );
        return;
      }
      await _markIntegrityApproved(provider);
    }

    final next = await ref.read(syncAuthGatewayProvider).connect(provider);

    _update(provider, next);
    await _persist();
  }

  Future<void> completeGoogleDriveWebAuthentication(
    GoogleSignInAccount account,
  ) async {
    const provider = SyncProvider.googleDrive;
    _update(
      provider,
      stateFor(provider).copyWith(
        stage: SyncAuthStage.busy,
        userId: account.id,
        displayName: account.displayName,
        email: account.email,
        clearMessage: true,
      ),
    );

    try {
      final alreadyApproved = await _hasIntegrityApproval(provider);
      if (!alreadyApproved) {
        final verification = await ref
            .read(playIntegrityVerifierProvider)
            .verifyOperation(
              flavor: ref.read(currentAppFlavorProvider),
              operation: 'sync.enable',
              payload: {'provider': provider.name},
            );
        if (!verification.allowed) {
          _update(
            provider,
            stateFor(provider).copyWith(
              stage: SyncAuthStage.error,
              message: verification.message,
            ),
          );
          return;
        }
        await _markIntegrityApproved(provider);
      }

      final authorizationClient = account.authorizationClient;
      final existingAuthorization = await authorizationClient
          .authorizationForScopes(_googleScopes);
      if (existingAuthorization == null) {
        await authorizationClient.authorizeScopes(_googleScopes);
      }

      _update(
        provider,
        SyncAuthState(
          provider: provider,
          stage: SyncAuthStage.authenticated,
          userId: account.id,
          displayName: account.displayName,
          email: account.email,
          message: 'Google Drive app-data access is authorized.',
        ),
      );
      await _persist();
    } on GoogleSignInException catch (error) {
      _update(
        provider,
        stateFor(provider).copyWith(
          stage: SyncAuthStage.error,
          message: DefaultSyncAuthGateway()._googleDriveSignInExceptionMessage(
            error,
          ),
        ),
      );
    } catch (error) {
      _update(
        provider,
        stateFor(
          provider,
        ).copyWith(stage: SyncAuthStage.error, message: '$error'),
      );
    }
  }

  Future<void> disconnectSelected() async {
    await disconnect(ref.read(syncProviderControllerProvider));
  }

  Future<void> disconnect(SyncProvider provider) async {
    await ref.read(syncAuthGatewayProvider).disconnect(provider);
    _update(provider, SyncAuthState.idle(provider));
    await _persist();
  }

  void _update(SyncProvider provider, SyncAuthState next) {
    state = {...state, provider: next};
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final provider in SyncProvider.values)
          provider: _normalizeRestoredState(
            provider,
            decoded[provider.name] == null
                ? SyncAuthState.idle(provider)
                : SyncAuthState.fromJson(
                    Map<String, dynamic>.from(decoded[provider.name] as Map),
                  ),
          ),
      };
    } catch (_) {}
  }

  SyncAuthState _normalizeRestoredState(
    SyncProvider provider,
    SyncAuthState restored,
  ) {
    if (provider != SyncProvider.iCloud) {
      return restored;
    }
    final message = restored.message ?? '';
    final staleAppleSignInError =
        restored.stage == SyncAuthStage.error &&
        (message.contains('SignInWithAppleAuthorizationException') ||
            message.contains(
              'com.apple.AuthenticationServices.AuthorizationError',
            ));
    if (staleAppleSignInError) {
      return SyncAuthState.idle(provider);
    }
    return restored;
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key.name: entry.value.toJson(),
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  Future<bool> _hasIntegrityApproval(SyncProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_integrityApprovalKey.${provider.name}') ?? false;
  }

  Future<void> _markIntegrityApproved(SyncProvider provider) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_integrityApprovalKey.${provider.name}', true);
  }
}

final appLaunchControllerProvider =
    NotifierProvider<AppLaunchController, AppLaunchSurface>(
      AppLaunchController.new,
    );

class AppLaunchController extends Notifier<AppLaunchSurface> {
  static const _storageKey = 'app.onboarding_completed';
  static const _versionStorageKey = 'app.onboarding_completed_version';
  static const _currentOnboardingVersion = 2;
  bool _restored = false;
  bool _completedInSession = false;

  @override
  AppLaunchSurface build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppLaunchSurface.onboarding;
  }

  Future<void> completeOnboarding() async {
    _completedInSession = true;
    state = AppLaunchSurface.ready;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
      await prefs.setInt(_versionStorageKey, _currentOnboardingVersion);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_completedInSession) {
        return;
      }
      final completed = prefs.getBool(_storageKey) ?? false;
      final completedVersion = prefs.getInt(_versionStorageKey) ?? 0;
      final hasCompletedCurrentOnboarding =
          completed && completedVersion >= _currentOnboardingVersion;
      state = hasCompletedCurrentOnboarding
          ? AppLaunchSurface.ready
          : AppLaunchSurface.onboarding;
    } catch (_) {
      if (_completedInSession) {
        return;
      }
      state = AppLaunchSurface.onboarding;
    }
  }
}

@Riverpod(keepAlive: true)
class ThemeModeController extends _$ThemeModeController {
  static const _storageKey = 'settings.theme_mode';
  bool _restored = false;

  @override
  ThemeMode build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return ThemeMode.light;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, mode.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = ThemeMode.values.firstWhere(
        (mode) => mode.name == stored,
        orElse: () => ThemeMode.light,
      );
    } catch (_) {}
  }
}

final effectiveThemeModeProvider = Provider<ThemeMode>((ref) {
  final defaultMode = ref.watch(themeModeControllerProvider);
  final activeScope = ref.watch(activeColorThemeScopeProvider);
  if (activeScope == defaultColorThemeScope) {
    return defaultMode;
  }
  return ref.watch(profileThemeModeControllerProvider)[activeScope] ??
      defaultMode;
});

final profileThemeModeControllerProvider =
    NotifierProvider<ProfileThemeModeController, Map<String, ThemeMode>>(
      ProfileThemeModeController.new,
    );

class ProfileThemeModeController extends Notifier<Map<String, ThemeMode>> {
  static const _storageKey = 'settings.profile_theme_modes';
  bool _restored = false;

  @override
  Map<String, ThemeMode> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return const <String, ThemeMode>{};
  }

  Future<void> setMode(String scope, ThemeMode mode) async {
    if (scope == defaultColorThemeScope) {
      return;
    }
    state = {...state, scope: mode};
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final entry in decoded.entries)
          if (_themeModeFromName(entry.value as String?) != null)
            entry.key: _themeModeFromName(entry.value as String?)!,
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }
}

final appColorThemeControllerProvider =
    NotifierProvider<AppColorThemeController, AppColorTheme>(
      AppColorThemeController.new,
    );

final appFontFamilyControllerProvider =
    NotifierProvider<AppFontFamilyController, AppFontFamily>(
      AppFontFamilyController.new,
    );

class AppFontFamilyController extends Notifier<AppFontFamily> {
  static const _storageKey = 'settings.font_family';
  bool _restored = false;

  @override
  AppFontFamily build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppFontFamily.system;
  }

  Future<void> setFont(AppFontFamily font) async {
    state = font;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, font.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      final restored = AppFontFamily.values.firstWhere(
        (font) => font.name == stored,
        orElse: () => AppFontFamily.system,
      );
      state = iOSFriendlyAppFontFamilies.contains(restored)
          ? restored
          : AppFontFamily.system;
    } catch (_) {}
  }
}

final effectiveAppFontFamilyProvider = Provider<AppFontFamily>((ref) {
  final defaultFont = ref.watch(appFontFamilyControllerProvider);
  final activeScope = ref.watch(activeColorThemeScopeProvider);
  if (activeScope == defaultColorThemeScope) {
    return defaultFont;
  }
  return ref.watch(profileFontFamilyControllerProvider)[activeScope] ??
      defaultFont;
});

final profileFontFamilyControllerProvider =
    NotifierProvider<ProfileFontFamilyController, Map<String, AppFontFamily>>(
      ProfileFontFamilyController.new,
    );

class ProfileFontFamilyController extends Notifier<Map<String, AppFontFamily>> {
  static const _storageKey = 'settings.profile_font_families';
  bool _restored = false;

  @override
  Map<String, AppFontFamily> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return const <String, AppFontFamily>{};
  }

  Future<void> setFont(String scope, AppFontFamily font) async {
    if (scope == defaultColorThemeScope) {
      return;
    }
    state = {...state, scope: font};
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final entry in decoded.entries)
          if (_fontFamilyFromName(entry.value as String?) != null)
            entry.key: _fontFamilyFromName(entry.value as String?)!,
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }
}

const defaultColorThemeScope = 'daily';

final activeColorThemeScopeProvider = Provider<String>((ref) {
  return ref.watch(unlockedPrivateProfileVaultIdProvider) ??
      defaultColorThemeScope;
});

final colorThemeSettingsScopeProvider =
    NotifierProvider<ColorThemeSettingsScopeController, String>(
      ColorThemeSettingsScopeController.new,
    );

class ColorThemeSettingsScopeController extends Notifier<String> {
  @override
  String build() => ref.watch(activeColorThemeScopeProvider);

  void select(String scope) {
    state = scope;
  }
}

final effectiveAppColorThemeProvider = Provider<AppColorTheme>((ref) {
  final defaultTheme = ref.watch(appColorThemeControllerProvider);
  final activeScope = ref.watch(activeColorThemeScopeProvider);
  if (activeScope == defaultColorThemeScope) {
    return defaultTheme;
  }
  return ref.watch(profileColorThemeControllerProvider)[activeScope] ??
      defaultTheme;
});

class AppColorThemeController extends Notifier<AppColorTheme> {
  static const _storageKey = 'settings.color_theme';
  bool _restored = false;

  @override
  AppColorTheme build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppColorTheme.sakura;
  }

  Future<void> setTheme(AppColorTheme theme) async {
    state = theme;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, theme.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = _appColorThemeFromName(stored) ?? AppColorTheme.sakura;
    } catch (_) {}
  }
}

final profileColorThemeControllerProvider =
    NotifierProvider<ProfileColorThemeController, Map<String, AppColorTheme>>(
      ProfileColorThemeController.new,
    );

class ProfileColorThemeController extends Notifier<Map<String, AppColorTheme>> {
  static const _storageKey = 'settings.profile_color_themes';
  bool _restored = false;

  @override
  Map<String, AppColorTheme> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return const <String, AppColorTheme>{};
  }

  Future<void> setTheme(String scope, AppColorTheme theme) async {
    if (scope == defaultColorThemeScope) {
      return;
    }
    state = {...state, scope: theme};
    await _persist();
  }

  Future<void> clearTheme(String scope) async {
    if (!state.containsKey(scope)) {
      return;
    }
    final next = {...state}..remove(scope);
    state = next;
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final entry in decoded.entries)
          if (_themeFromName(entry.value as String?) != null)
            entry.key: _themeFromName(entry.value as String?)!,
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }

  AppColorTheme? _themeFromName(String? value) {
    return _appColorThemeFromName(value);
  }
}

final appLocaleControllerProvider =
    NotifierProvider<AppLocaleController, AppLocaleSetting>(
      AppLocaleController.new,
    );

class AppLocaleController extends Notifier<AppLocaleSetting> {
  static const _storageKey = 'settings.locale';
  bool _restored = false;

  @override
  AppLocaleSetting build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return _defaultLocaleSetting();
  }

  Future<void> setLocale(AppLocaleSetting locale) async {
    state = locale;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, locale.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = AppLocaleSetting.values.firstWhere(
        (locale) => locale.name == stored,
        orElse: () => AppLocaleSetting.system,
      );
    } catch (_) {}
  }

  AppLocaleSetting _defaultLocaleSetting() {
    final languageCode = ui.PlatformDispatcher.instance.locale.languageCode;
    return languageCode == 'ja'
        ? AppLocaleSetting.japanese
        : AppLocaleSetting.english;
  }
}

final effectiveAppLocaleProvider = Provider<AppLocaleSetting>((ref) {
  final defaultLocale = ref.watch(appLocaleControllerProvider);
  final activeScope = ref.watch(activeColorThemeScopeProvider);
  if (activeScope == defaultColorThemeScope) {
    return defaultLocale;
  }
  return ref.watch(profileLocaleControllerProvider)[activeScope] ??
      defaultLocale;
});

final profileLocaleControllerProvider =
    NotifierProvider<ProfileLocaleController, Map<String, AppLocaleSetting>>(
      ProfileLocaleController.new,
    );

class ProfileLocaleController extends Notifier<Map<String, AppLocaleSetting>> {
  static const _storageKey = 'settings.profile_locales';
  bool _restored = false;

  @override
  Map<String, AppLocaleSetting> build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return const <String, AppLocaleSetting>{};
  }

  Future<void> setLocale(String scope, AppLocaleSetting locale) async {
    if (scope == defaultColorThemeScope) {
      return;
    }
    state = {...state, scope: locale};
    await _persist();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null || stored.isEmpty) {
        return;
      }
      final decoded = Map<String, dynamic>.from(
        jsonDecode(stored) as Map<String, dynamic>,
      );
      state = {
        for (final entry in decoded.entries)
          if (_localeSettingFromName(entry.value as String?) != null)
            entry.key: _localeSettingFromName(entry.value as String?)!,
      };
    } catch (_) {}
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {}
  }
}

ThemeMode? _themeModeFromName(String? value) {
  if (value == null) {
    return null;
  }
  for (final mode in ThemeMode.values) {
    if (mode.name == value) {
      return mode;
    }
  }
  return null;
}

AppFontFamily? _fontFamilyFromName(String? value) {
  if (value == null) {
    return null;
  }
  for (final font in AppFontFamily.values) {
    if (font.name == value && iOSFriendlyAppFontFamilies.contains(font)) {
      return font;
    }
  }
  return null;
}

AppLocaleSetting? _localeSettingFromName(String? value) {
  if (value == null) {
    return null;
  }
  for (final locale in AppLocaleSetting.values) {
    if (locale.name == value) {
      return locale;
    }
  }
  return null;
}

final appLockSettingsControllerProvider =
    NotifierProvider<AppLockSettingsController, bool>(
      AppLockSettingsController.new,
    );

class AppLockSettingsController extends Notifier<bool> {
  static const _storageKey = 'settings.app_lock_enabled';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? false;
    } catch (_) {}
  }
}

class SpotlightNoteIndexBridge {
  SpotlightNoteIndexBridge(this._onOpenRequested);

  static const MethodChannel _channel = MethodChannel(
    'org.ruhenheim.himemo/spotlight',
  );

  final void Function(String noteId) _onOpenRequested;
  bool _attached = false;

  bool get _isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

  void attach() {
    if (_attached || !_isSupported) {
      return;
    }
    _attached = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'openSpotlightNote') {
        final arguments = Map<String, dynamic>.from(
          (call.arguments as Map?)?.cast<String, dynamic>() ??
              const <String, dynamic>{},
        );
        final noteId = '${arguments['noteId'] ?? ''}'.trim();
        if (noteId.isNotEmpty) {
          _onOpenRequested(noteId);
          unawaited(_invoke('clearPendingSpotlightNote'));
        }
      }
    });
    unawaited(_consumePendingOpen());
  }

  Future<void> replaceAllStandardNotes(List<NoteEntry> notes) async {
    if (!_isSupported) {
      _diagnostic('replace all skipped unsupported');
      return;
    }
    final items = [
      for (final note in notes)
        if (_isSpotlightIndexableStandardNote(note))
          _spotlightItemArguments(note),
    ];
    _diagnostic('replace all requested', data: {'items': items.length});
    await _invoke('replaceAllNotes', {'items': items});
  }

  Future<void> upsert(NoteEntry note) async {
    if (!_isSupported) {
      _diagnostic('upsert skipped unsupported', data: {'noteId': note.id});
      return;
    }
    if (!_isSpotlightIndexableStandardNote(note)) {
      await delete(note.id);
      return;
    }
    _diagnostic('upsert requested', data: {'noteId': note.id});
    await _invoke('indexNotes', {
      'items': [_spotlightItemArguments(note)],
    });
  }

  Future<void> delete(String noteId) async {
    if (!_isSupported || noteId.trim().isEmpty) {
      return;
    }
    _diagnostic('delete requested', data: {'noteId': noteId});
    await _invoke('deleteNotes', {
      'ids': [noteId],
    });
  }

  Future<void> clearNotes() async {
    if (!_isSupported) {
      _diagnostic('clear skipped unsupported');
      return;
    }
    _diagnostic('clear requested');
    await _invoke('clearNotes');
  }

  Future<void> _consumePendingOpen() async {
    try {
      final pending = await _channel.invokeMethod<dynamic>(
        'consumePendingSpotlightNote',
      );
      if (pending is String && pending.trim().isNotEmpty) {
        _onOpenRequested(pending.trim());
      }
    } catch (_) {}
  }

  Future<void> _invoke(String method, [Object? arguments]) async {
    try {
      final result = await _channel.invokeMethod<Object?>(method, arguments);
      _diagnostic('$method completed', data: {'result': result});
    } catch (error) {
      _diagnostic('$method failed', data: {'error': error});
    }
  }

  void _diagnostic(
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
  }) {
    logDiagnostic('spotlight', message, data: data);
  }
}

bool _isSpotlightIndexableStandardNote(NoteEntry note) {
  return note.vaultId == 'everyday' &&
      note.deletedAt == null &&
      note.archivedAt == null &&
      !isGeneratedSampleNote(note);
}

Map<String, Object?> _spotlightItemArguments(NoteEntry note) {
  final body = _spotlightSearchableText(note);
  final title = note.title.trim().isNotEmpty
      ? note.title.trim()
      : _spotlightFallbackTitle(note, body);
  return <String, Object?>{
    'id': note.id,
    'title': title,
    'body': body,
    'createdAt': note.createdAt.toIso8601String(),
    'updatedAt': note.updatedAt?.toIso8601String(),
    'tags': note.normalizedTags,
    'searchTerms': _spotlightSearchTerms(
      title: title,
      body: body,
      tags: note.normalizedTags,
    ),
  };
}

String _spotlightSearchableText(NoteEntry note) {
  final parts = <String>[
    if (note.body.trim().isNotEmpty) note.body.trim(),
    for (final block in note.blocks)
      if (block.type == NoteBlockType.paragraph &&
          block.text != null &&
          block.text!.trim().isNotEmpty)
        block.text!.trim(),
    if (note.normalizedTags.isNotEmpty) note.normalizedTags.join(' '),
  ];
  return parts.join('\n\n').trim();
}

String _spotlightFallbackTitle(NoteEntry note, String body) {
  final firstLine = body
      .split(RegExp(r'\r?\n'))
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
  if (firstLine.isNotEmpty) {
    return firstLine.length <= 48
        ? firstLine
        : '${firstLine.substring(0, 48)}...';
  }
  return '${note.createdAt.year.toString().padLeft(4, '0')}/'
      '${note.createdAt.month.toString().padLeft(2, '0')}/'
      '${note.createdAt.day.toString().padLeft(2, '0')}';
}

List<String> _spotlightSearchTerms({
  required String title,
  required String body,
  required List<String> tags,
}) {
  final terms = <String>{};

  void addTerm(String raw) {
    final term = raw.trim().toLowerCase();
    if (term.length < 2) {
      return;
    }
    terms.add(term.length > 64 ? term.substring(0, 64) : term);
  }

  void addText(String text) {
    final normalized = text.replaceAll(
      RegExp(r'[\s,.;:!?，。、！？「」『』（）()\[\]［］【】#]+'),
      ' ',
    );
    for (final raw in normalized.split(' ')) {
      addTerm(raw);
    }
    final compact = normalized.replaceAll(' ', '');
    if (compact.length >= 4) {
      for (var i = 0; i < compact.length && terms.length < 80; i++) {
        for (final length in const [2, 3, 4]) {
          if (i + length <= compact.length) {
            addTerm(compact.substring(i, i + length));
          }
        }
      }
    }
  }

  addText(title);
  addText(body);
  for (final tag in tags) {
    addText(tag);
  }
  return terms.take(80).toList(growable: false);
}

class SpotlightNoteOpenRequestController extends Notifier<String?> {
  @override
  String? build() => null;

  void open(String noteId) => state = noteId;

  void clear() => state = null;
}

final spotlightNoteOpenRequestControllerProvider =
    NotifierProvider<SpotlightNoteOpenRequestController, String?>(
      SpotlightNoteOpenRequestController.new,
    );

final spotlightNoteIndexBridgeProvider = Provider<SpotlightNoteIndexBridge>((
  ref,
) {
  final bridge = SpotlightNoteIndexBridge(
    (noteId) => ref
        .read(spotlightNoteOpenRequestControllerProvider.notifier)
        .open(noteId),
  );
  bridge.attach();
  return bridge;
});

final spotlightNoteIndexEnabledControllerProvider =
    NotifierProvider<SpotlightNoteIndexEnabledController, bool>(
      SpotlightNoteIndexEnabledController.new,
    );

class SpotlightNoteIndexEnabledController extends Notifier<bool> {
  static const _storageKey = 'settings.ios_spotlight_standard_notes_enabled';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
    await _applyIndexState(enabled);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_storageKey) ?? false;
      state = enabled;
      await _applyIndexState(enabled);
    } catch (_) {}
  }

  Future<void> _applyIndexState(bool enabled) async {
    final bridge = ref.read(spotlightNoteIndexBridgeProvider);
    if (!enabled) {
      await bridge.clearNotes();
      return;
    }
    await ref.read(notesControllerProvider.notifier).restoreCompleted;
    await bridge.replaceAllStandardNotes(ref.read(notesControllerProvider));
  }
}

@Riverpod(keepAlive: true)
class WidgetQuickCaptureSettingsController
    extends _$WidgetQuickCaptureSettingsController {
  static const _storageKey = 'settings.widget_quick_capture_enabled';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? true;
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class WidgetQuickCaptureRequestController
    extends _$WidgetQuickCaptureRequestController {
  final Set<String> _seenNonces = <String>{};

  @override
  QuickCaptureRequest? build() => null;

  void open(QuickCaptureRequest request) {
    if (request.nonce.isNotEmpty && !_seenNonces.add(request.nonce)) {
      return;
    }
    if (_seenNonces.length > 32) {
      _seenNonces.remove(_seenNonces.first);
    }
    state = request;
  }

  void clear() => state = null;
}

@Riverpod(keepAlive: true)
WidgetQuickCaptureBridge widgetQuickCaptureBridge(Ref ref) {
  final bridge = WidgetQuickCaptureBridge(
    (request) => ref
        .read(widgetQuickCaptureRequestControllerProvider.notifier)
        .open(request),
  );
  bridge.attach();
  return bridge;
}

final appLockRelockDelayControllerProvider =
    NotifierProvider<AppLockRelockDelayController, AppLockRelockDelay>(
      AppLockRelockDelayController.new,
    );

class AppLockRelockDelayController extends Notifier<AppLockRelockDelay> {
  static const _storageKey = 'settings.app_lock_relock_delay';
  bool _restored = false;

  @override
  AppLockRelockDelay build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AppLockRelockDelay.immediate;
  }

  Future<void> setDelay(AppLockRelockDelay delay) async {
    state = delay;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, delay.name);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }
      state = AppLockRelockDelay.values.firstWhere(
        (delay) => delay.name == stored,
        orElse: () => AppLockRelockDelay.immediate,
      );
    } catch (_) {}
  }
}

final privateVaultLockOnAppLockControllerProvider =
    NotifierProvider<PrivateVaultLockOnAppLockController, bool>(
      PrivateVaultLockOnAppLockController.new,
    );

class PrivateVaultLockOnAppLockController extends Notifier<bool> {
  static const _storageKey = 'settings.private_vault_lock_on_app_lock';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return true;
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, enabled);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? true;
    } catch (_) {}
  }
}

final syncProviderControllerProvider =
    NotifierProvider<SyncProviderController, SyncProvider>(
      SyncProviderController.new,
    );

class SyncProviderController extends Notifier<SyncProvider> {
  static const _storageKey = 'settings.sync_provider';
  bool _restored = false;

  @override
  SyncProvider build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return SyncProvider.off;
  }

  Future<void> setProvider(SyncProvider provider) async {
    if (provider == SyncProvider.iCloud && !isICloudSyncSupported) {
      provider = SyncProvider.off;
    }
    final previous = state;
    String? carriedBackupCode;
    if (provider == SyncProvider.googleDrive &&
        previous != SyncProvider.googleDrive) {
      try {
        carriedBackupCode = await ref
            .read(syncBundleKeyServiceProvider)
            .exportBackupCode();
      } catch (_) {}
    }
    state = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.name);
    } catch (_) {}
    if (provider == SyncProvider.googleDrive) {
      await _prepareGoogleDriveSyncKey(carriedBackupCode);
    }
    if (provider != SyncProvider.off && provider != previous) {
      await ref
          .read(notesControllerProvider.notifier)
          .queueCurrentStateForSync();
      ref.invalidate(syncQueueSummaryProvider);
    }
  }

  Future<void> _prepareGoogleDriveSyncKey(String? carriedBackupCode) async {
    try {
      final cloudStore = ref.read(googleDriveCloudSyncBundleKeyStoreProvider);
      final remoteBackupCode = await cloudStore.readBackupCode();
      if (remoteBackupCode != null && remoteBackupCode.isNotEmpty) {
        await ref
            .read(syncBundleKeyServiceProvider)
            .importBackupCode(remoteBackupCode);
        return;
      }
    } catch (_) {}

    if (carriedBackupCode != null && carriedBackupCode.isNotEmpty) {
      try {
        await ref
            .read(syncBundleKeyServiceProvider)
            .importBackupCode(carriedBackupCode);
        return;
      } catch (_) {}
    }

    try {
      await ref.read(syncBundleKeyServiceProvider).obtainOrCreate();
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }
      final restored = SyncProvider.values.firstWhere(
        (provider) => provider.name == stored,
        orElse: () => SyncProvider.off,
      );
      state = restored == SyncProvider.iCloud && !isICloudSyncSupported
          ? SyncProvider.off
          : restored;
    } catch (_) {}
  }
}

final privateVaultSessionControllerProvider =
    NotifierProvider<PrivateVaultSessionController, bool>(
      PrivateVaultSessionController.new,
    );

class PrivateVaultSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() {
    ref.read(profileDataKeyServiceProvider).lockProfile(legacyPrivateVaultId);
    state = false;
  }
}

final privateVaultSecretControllerProvider =
    NotifierProvider<PrivateVaultSecretController, bool>(
      PrivateVaultSecretController.new,
    );

class PrivateVaultSecretController extends Notifier<bool> {
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return false;
  }

  Future<void> configure(String secret) async {
    await ref.read(privateVaultSecretStoreProvider).configure(secret);
    await ref
        .read(profileDataKeyServiceProvider)
        .configureProfile(vaultId: legacyPrivateVaultId, password: secret);
    state = true;
    ref.read(privateVaultSessionControllerProvider.notifier).unlock();
  }

  Future<bool> verify(String secret) async {
    try {
      final matched = await ref
          .read(privateVaultSecretStoreProvider)
          .verify(secret);
      if (matched) {
        await ref
            .read(profileDataKeyServiceProvider)
            .unlockProfile(vaultId: legacyPrivateVaultId, password: secret);
        ref.read(privateVaultSessionControllerProvider.notifier).unlock();
      }
      return matched;
    } catch (_) {
      return false;
    }
  }

  Future<void> clear() async {
    try {
      await ref.read(privateVaultSecretStoreProvider).clear();
      await ref
          .read(profileDataKeyServiceProvider)
          .deleteProfileKey(legacyPrivateVaultId);
    } catch (_) {}
    state = false;
    ref.read(privateVaultSessionControllerProvider.notifier).lock();
  }

  Future<void> _restore() async {
    try {
      state = await ref.read(privateVaultSecretStoreProvider).hasSecret();
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class ActiveIdentity extends _$ActiveIdentity {
  static const _storageKey = 'settings.active_identity';
  bool _restored = false;

  @override
  String build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return 'daily';
  }

  Future<void> switchTo(String identityId) async {
    final previousIdentityId = state;
    state = identityId;
    if (previousIdentityId != identityId) {
      logAudit(
        'profile_switch',
        data: {
          'from': previousIdentityId,
          'to': identityId,
          'adminMode': ref.read(adminModeSessionControllerProvider),
        },
      );
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, identityId);
    } catch (_) {}
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored != null) {
        state = stored;
      }
    } catch (_) {}
  }
}

@Riverpod(keepAlive: true)
class SearchQuery extends _$SearchQuery {
  @override
  String build() => '';

  void setQuery(String value) => state = value;
}

class SearchFiltersController extends Notifier<SearchFilters> {
  @override
  SearchFilters build() => const SearchFilters();

  void setPinnedOnly(bool value) {
    state = state.copyWith(pinnedOnly: value);
  }

  void setWithMediaOnly(bool value) {
    state = state.copyWith(
      withMediaOnly: value,
      attachmentFilters: value
          ? const <SearchAttachmentFilter>[SearchAttachmentFilter.any]
          : const <SearchAttachmentFilter>[],
    );
  }

  void setAttachmentFilter(SearchAttachmentFilter value) {
    state = state.copyWith(
      withMediaOnly: false,
      attachmentFilters: value == SearchAttachmentFilter.all
          ? const <SearchAttachmentFilter>[]
          : [value],
    );
  }

  void setAttachmentFilters(List<SearchAttachmentFilter> values) {
    final normalized = _normalizeAttachmentFilters(values);
    state = state.copyWith(withMediaOnly: false, attachmentFilters: normalized);
  }

  void toggleAttachmentFilter(SearchAttachmentFilter value) {
    if (value == SearchAttachmentFilter.all) {
      setAttachmentFilters(const <SearchAttachmentFilter>[]);
      return;
    }
    if (value == SearchAttachmentFilter.any) {
      setAttachmentFilters(const <SearchAttachmentFilter>[
        SearchAttachmentFilter.any,
      ]);
      return;
    }
    final next = state.attachmentFilters
        .where((filter) => filter != SearchAttachmentFilter.any)
        .toList(growable: true);
    if (next.contains(value)) {
      next.remove(value);
    } else {
      next.add(value);
    }
    setAttachmentFilters(
      next.isEmpty
          ? const <SearchAttachmentFilter>[SearchAttachmentFilter.any]
          : next,
    );
  }

  void setArchivedOnly(bool value) {
    state = state.copyWith(archivedOnly: value, includeArchived: false);
  }

  void setIncludeArchived(bool value) {
    state = state.copyWith(includeArchived: value, archivedOnly: false);
  }

  void setRequireAllTags(bool value) {
    state = state.copyWith(requireAllTags: value);
  }

  void setDateRange(SearchDateRange value) {
    state = state.copyWith(
      dateRange: value,
      dateField: value == SearchDateRange.all
          ? SearchDateField.createdAt
          : state.dateField,
    );
  }

  void setDateField(SearchDateField value) {
    state = state.copyWith(dateField: value);
  }

  void setVault(String? vaultId) {
    if (vaultId == null || vaultId.isEmpty) {
      state = state.copyWith(clearVault: true);
      return;
    }
    state = state.copyWith(vaultId: vaultId);
  }

  void setYear(int? year) {
    if (year == null) {
      state = state.copyWith(clearYear: true);
      return;
    }
    state = state.copyWith(year: year);
  }

  void setTags(List<String> tags) {
    final deduped = dedupeNoteTags(tags);
    state = state.copyWith(
      tags: deduped,
      requireAllTags: deduped.length > 1 ? state.requireAllTags : false,
    );
  }

  void addTag(String tag) {
    setTags([...state.tags, tag]);
  }

  void removeTag(String tag) {
    final key = canonicalizeNoteTag(tag);
    setTags(
      state.tags
          .where((entry) => canonicalizeNoteTag(entry) != key)
          .toList(growable: false),
    );
  }

  void reset() {
    state = const SearchFilters();
  }
}

List<SearchAttachmentFilter> _normalizeAttachmentFilters(
  Iterable<SearchAttachmentFilter> values,
) {
  final selected = <SearchAttachmentFilter>[];
  for (final value in values) {
    if (value == SearchAttachmentFilter.all) {
      continue;
    }
    if (value == SearchAttachmentFilter.any) {
      return const <SearchAttachmentFilter>[SearchAttachmentFilter.any];
    }
    if (!selected.contains(value)) {
      selected.add(value);
    }
  }
  return List<SearchAttachmentFilter>.unmodifiable(selected);
}

final searchFiltersControllerProvider =
    NotifierProvider<SearchFiltersController, SearchFilters>(
      SearchFiltersController.new,
    );

class SelectedNoteIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? noteId) {
    state = noteId;
  }
}

final selectedNoteIdProvider =
    NotifierProvider<SelectedNoteIdController, String?>(
      SelectedNoteIdController.new,
    );

final activeNoteCountProvider = Provider<int>((ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  var count = 0;
  for (final note in ref.watch(notesControllerProvider)) {
    if (note.deletedAt == null &&
        note.archivedAt == null &&
        visibleIds.contains(note.vaultId)) {
      count++;
    }
  }
  return count;
});

final archivedNoteCountProvider = Provider<int>((ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  var count = 0;
  for (final note in ref.watch(notesControllerProvider)) {
    if (note.deletedAt == null &&
        note.archivedAt != null &&
        visibleIds.contains(note.vaultId)) {
      count++;
    }
  }
  return count;
});

class NoteEditorDraftStore {
  static const _storageKey = 'notes.editor_draft.v1';

  Future<NoteEditorDraftSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey);
    if (payload == null || payload.isEmpty) {
      return null;
    }
    try {
      return NoteEditorDraftSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(payload) as Map),
      );
    } catch (_) {
      return null;
    }
  }

  Future<void> save(NoteEditorDraftSnapshot snapshot) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, jsonEncode(snapshot.toJson()));
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

@Riverpod(keepAlive: true)
class NotesListDensityController extends _$NotesListDensityController {
  static const _storageKey = 'notes.list_density';
  bool _restored = false;

  @override
  NotesListDensity build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return NotesListDensity.standard;
  }

  Future<void> setDensity(NotesListDensity density) async {
    state = density;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, density.name);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    state = NotesListDensity.values.firstWhere(
      (density) => density.name == stored,
      orElse: () => NotesListDensity.standard,
    );
  }
}

@Riverpod(keepAlive: true)
class AttachmentPreviewFitController extends _$AttachmentPreviewFitController {
  static const _storageKey = 'notes.attachment_preview_fit';
  bool _restored = false;

  @override
  AttachmentPreviewFit build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return AttachmentPreviewFit.preview;
  }

  Future<void> setFit(AttachmentPreviewFit fit) async {
    state = fit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, fit.name);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    state = AttachmentPreviewFit.values.firstWhere(
      (fit) => fit.name == stored,
      orElse: () => AttachmentPreviewFit.preview,
    );
  }
}

final videoPlaybackMutedByDefaultControllerProvider =
    NotifierProvider<VideoPlaybackMutedByDefaultController, bool>(
      VideoPlaybackMutedByDefaultController.new,
    );

class VideoPlaybackMutedByDefaultController extends Notifier<bool> {
  static const _storageKey = 'settings.video_playback_muted_by_default';
  bool _restored = false;

  @override
  bool build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return true;
  }

  Future<void> setMuted(bool muted) async {
    state = muted;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_storageKey, muted);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    state = prefs.getBool(_storageKey) ?? true;
  }
}

@Riverpod(keepAlive: true)
class NotesListSortController extends _$NotesListSortController {
  static const _storageKey = 'notes.list_sort_field';
  bool _restored = false;

  @override
  NotesListSortField build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return NotesListSortField.updatedAt;
  }

  Future<void> setSortField(NotesListSortField field) async {
    state = field;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, field.name);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    state = NotesListSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => NotesListSortField.updatedAt,
    );
  }
}

@Riverpod(keepAlive: true)
class LastNoteEditorSettingsController
    extends _$LastNoteEditorSettingsController {
  static const _modeKey = 'notes.last_editor_mode';
  static const _vaultKey = 'notes.last_vault_id';
  static const _captureLocationKey = 'notes.last_capture_location';
  bool _restored = false;
  bool _changedBeforeRestoreCompleted = false;
  Future<void>? _restoreTask;

  @override
  LastNoteEditorSettings build() {
    if (!_restored) {
      _restoreTask ??= _restore();
    }
    return const LastNoteEditorSettings();
  }

  Future<void> ensureRestored() {
    if (_restored) {
      return Future<void>.value();
    }
    return _restoreTask ??= _restore();
  }

  Future<void> remember({
    required NoteEditorMode mode,
    required String vaultId,
    bool? captureLocation,
  }) async {
    if (!_restored) {
      _changedBeforeRestoreCompleted = true;
    }
    state = LastNoteEditorSettings(
      mode: mode,
      vaultId: vaultId,
      captureLocation: captureLocation ?? state.captureLocation,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_modeKey, mode.name);
    await prefs.setString(_vaultKey, vaultId);
    await prefs.setBool(_captureLocationKey, state.captureLocation);
  }

  Future<void> setCaptureLocation(bool enabled) async {
    if (!_restored) {
      _changedBeforeRestoreCompleted = true;
    }
    state = LastNoteEditorSettings(
      mode: state.mode,
      vaultId: state.vaultId,
      captureLocation: enabled,
    );
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_captureLocationKey, enabled);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final modeName = prefs.getString(_modeKey);
    final vaultId = prefs.getString(_vaultKey);
    final captureLocation = prefs.getBool(_captureLocationKey) ?? false;
    if (!_changedBeforeRestoreCompleted) {
      state = LastNoteEditorSettings(
        mode: modeName == null || modeName.isEmpty
            ? NoteEditorMode.rich
            : NoteEditorMode.values.byName(modeName),
        vaultId: vaultId == null || vaultId.isEmpty ? 'everyday' : vaultId,
        captureLocation: captureLocation,
      );
    }
    _restored = true;
  }
}

@Riverpod(keepAlive: true)
class NotesController extends _$NotesController {
  static const _deletedSeedNoteIdsKey = 'notes.deleted_seed_note_ids.v1';
  static const _storeAssetsSeedDemoNotesKey = 'store_assets.seed_demo_notes.v1';
  static const trashRetention = Duration(days: 7);

  bool _restored = false;
  bool _restoreFailed = false;
  Future<void>? _restoreTask;

  @override
  List<NoteEntry> build() {
    if (!_restored) {
      _restored = true;
      _restoreTask = _restore();
      unawaited(_restoreTask);
    }
    return const <NoteEntry>[];
  }

  Future<void> upsert(NoteEntry note) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? savedNote;
    var created = false;
    await runFirebaseTrace(
      'notes_upsert',
      () async {
        final next = [...state];
        final index = next.indexWhere((entry) => entry.id == note.id);
        final existing = index == -1 ? null : next[index];
        created = existing == null;
        final prepared = await _prepareForSave(note, previous: existing);
        if (index == -1) {
          next.add(prepared);
        } else {
          next[index] = prepared;
        }
        _sort(next);
        state = next;
        await _cleanupRemovedAttachments(existing, prepared);
        await _persistOne(prepared);
        savedNote = prepared;
      },
      attributes: {
        'editor_mode': note.editorMode.name,
        'vault_id': note.vaultId,
        'has_media': note.attachments.isNotEmpty ? 'true' : 'false',
      },
    );
    final auditedNote = savedNote;
    if (auditedNote != null) {
      logAudit(
        created ? 'note_create' : 'note_update',
        data: _auditNoteData(auditedNote),
      );
    }
  }

  Future<void> delete(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? deletedNote;
    var lockedPlaceholder = false;
    await runFirebaseTrace('notes_delete', () async {
      final next = [...state];
      for (var i = 0; i < next.length; i++) {
        final note = next[i];
        if (note.id != noteId) {
          continue;
        }
        if (_isLockedPrivatePlaceholder(note)) {
          next.removeAt(i);
          state = next;
          await ref.read(encryptedNoteStoreProvider).deleteById(noteId);
          deletedNote = note;
          lockedPlaceholder = true;
          return;
        }
        final now = DateTime.now();
        final tombstone = note.copyWith(
          deletedAt: now,
          updatedAt: now,
          revision: note.revision + 1,
          syncState: NoteSyncState.pendingDelete,
        );
        final prepared = tombstone.copyWith(
          contentHash: _computeContentHash(tombstone),
        );
        next[i] = prepared;
        _sort(next);
        state = next;
        await _persistOne(prepared);
        deletedNote = prepared;
        return;
      }
    });
    final auditedNote = deletedNote;
    if (auditedNote != null) {
      logAudit(
        'note_delete',
        data: {
          ..._auditNoteData(auditedNote),
          'lockedPlaceholder': lockedPlaceholder,
        },
      );
    }
  }

  Future<void> restoreFromTrash(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? restoredNote;
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (note.id != noteId || note.deletedAt == null) {
        continue;
      }
      final now = DateTime.now();
      final restored = note.copyWith(
        deletedAt: null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      );
      final prepared = await _protectAttachmentsForVault(restored);
      final withHash = prepared.copyWith(
        contentHash: _computeContentHash(prepared),
      );
      next[i] = withHash;
      restoredNote = withHash;
      break;
    }
    if (restoredNote == null) {
      return;
    }
    _sort(next);
    state = next;
    await _persistOne(restoredNote);
    logAudit('note_restore', data: _auditNoteData(restoredNote));
  }

  Future<void> deletePermanently(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? note;
    for (final entry in state) {
      if (entry.id == noteId) {
        note = entry;
        break;
      }
    }
    if (note == null || note.deletedAt == null) {
      return;
    }
    state = state.where((entry) => entry.id != noteId).toList(growable: false);
    if (ref.read(selectedNoteIdProvider) == noteId) {
      ref.read(selectedNoteIdProvider.notifier).select(null);
    }
    await _deleteAttachments([..._attachmentsIn(note)]);
    await ref.read(encryptedNoteStoreProvider).deleteById(noteId);
    ref.invalidate(storageUsageSummaryProvider);
    logAudit('note_permanent_delete', data: _auditNoteData(note));
  }

  Future<int> purgeTrashOlderThan([Duration retention = trashRetention]) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    return _purgeTrashOlderThan(retention);
  }

  Future<void> archive(String noteId) async {
    await _setArchiveState(noteId, archived: true);
  }

  Future<void> unarchive(String noteId) async {
    await _setArchiveState(noteId, archived: false);
  }

  Future<void> togglePinned(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (note.id != noteId || note.deletedAt != null) {
        continue;
      }
      final now = DateTime.now();
      final changed = note.copyWith(
        isPinned: !note.isPinned,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      );
      final prepared = changed.copyWith(
        contentHash: _computeContentHash(changed),
      );
      next[i] = prepared;
      _sort(next);
      state = next;
      await _persistOne(prepared);
      logAudit('note_pin_toggle', data: _auditNoteData(prepared));
      return;
    }
  }

  Map<String, Object?> _auditNoteData(NoteEntry note) {
    return {
      'noteId': note.id,
      'vaultId': note.vaultId,
      'revision': note.revision,
      'editorMode': note.editorMode.name,
      'attachments': note.attachments.length,
      'tags': note.tags.length,
      'adminMode': ref.read(adminModeSessionControllerProvider),
    };
  }

  Future<int> archiveNotesOlderThan(Duration age) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final cutoff = DateTime.now().subtract(age);
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (note.deletedAt != null ||
          note.archivedAt != null ||
          note.isPinned ||
          !note.createdAt.isBefore(cutoff)) {
        next.add(note);
        continue;
      }
      final now = DateTime.now();
      final archived = note.copyWith(
        archivedAt: now,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      );
      next.add(archived.copyWith(contentHash: _computeContentHash(archived)));
      changed++;
    }
    if (changed == 0) {
      return 0;
    }
    _sort(next);
    state = next;
    await _persist();
    logAudit('note_bulk_archive', data: {'count': changed});
    return changed;
  }

  Future<int> unarchiveAll() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (note.deletedAt != null || note.archivedAt == null) {
        next.add(note);
        continue;
      }
      final now = DateTime.now();
      final restored = note.copyWith(
        archivedAt: null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      );
      next.add(restored.copyWith(contentHash: _computeContentHash(restored)));
      changed++;
    }
    if (changed == 0) {
      return 0;
    }
    _sort(next);
    state = next;
    await _persist();
    logAudit('note_bulk_unarchive', data: {'count': changed});
    return changed;
  }

  Future<void> _setArchiveState(String noteId, {required bool archived}) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (note.id != noteId || note.deletedAt != null) {
        continue;
      }
      final now = DateTime.now();
      final changed = note.copyWith(
        archivedAt: archived ? now : null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: NoteSyncState.pendingUpload,
      );
      final prepared = changed.copyWith(
        contentHash: _computeContentHash(changed),
      );
      next[i] = prepared;
      _sort(next);
      state = next;
      await _persistOne(prepared);
      logAudit(
        archived ? 'note_archive' : 'note_unarchive',
        data: _auditNoteData(prepared),
      );
      return;
    }
  }

  Future<void> seedIfEmpty() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    if (state.isNotEmpty) {
      return;
    }
    await _rememberDeletedSeedNoteIds(const <String>{});
    state = List<NoteEntry>.from(ref.read(homeRepositoryProvider).seededNotes);
    _sort(state);
    await _persist();
  }

  Future<int> createDemoNotes() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final existingIds = state.map((note) => note.id).toSet();
    final notesToAdd = ref
        .read(homeRepositoryProvider)
        .seededNotes
        .where((note) => note.vaultId == 'everyday')
        .where((note) => !existingIds.contains(note.id))
        .toList(growable: false);
    await _rememberDeletedSeedNoteIds(const <String>{});
    if (notesToAdd.isEmpty) {
      return 0;
    }
    state = [...state, ...notesToAdd];
    _sort(state);
    await _persist();
    return notesToAdd.length;
  }

  Future<int> createPerformanceTestNotes({
    required int count,
    int attachmentsPerNote = 0,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    if (count <= 0) {
      return 0;
    }
    final now = DateTime.now();
    final existingById = {for (final note in state) note.id: note};
    final notesToAdd = <NoteEntry>[];
    final notesToRequeue = <String, NoteEntry>{};
    for (var index = 0; index < count; index++) {
      final id = 'perf-${index.toString().padLeft(4, '0')}';
      final existing = existingById[id];
      if (existing != null) {
        if (existing.syncState == NoteSyncState.localOnly) {
          notesToRequeue[id] = existing.copyWith(
            updatedAt: now,
            syncState: NoteSyncState.pendingUpload,
            contentHash: 'performance-seed-$id-requeued',
          );
        }
        continue;
      }
      final createdAt = now.subtract(Duration(minutes: index * 11));
      final title = 'Performance note ${index + 1}';
      final body =
          'Performance test memo ${index + 1}\n'
          'This generated note is used to measure list, search, calendar, and detail switching performance.';
      final attachments = attachmentsPerNote <= 0
          ? const <NoteAttachment>[]
          : await _createPerformanceTestAttachments(
              noteIndex: index,
              count: attachmentsPerNote,
            );
      notesToAdd.add(
        NoteEntry(
          id: id,
          vaultId: 'everyday',
          title: title,
          body: body,
          createdAt: createdAt,
          updatedAt: createdAt,
          deviceId: 'performance-seed',
          contentHash: 'performance-seed-$id',
          syncState: NoteSyncState.pendingUpload,
          attachments: attachments,
          blocks: [
            NoteBlock(type: NoteBlockType.paragraph, text: body),
            for (final attachment in attachments)
              NoteBlock(
                type: _blockTypeForAttachment(attachment.type),
                attachment: attachment,
              ),
          ],
          tags: [
            'performance',
            if (index.isEven) 'batch-a' else 'batch-b',
            'day-${index % 30 + 1}',
          ],
          editorMode: NoteEditorMode.rich,
          location: index % 5 == 0
              ? NoteLocation(
                  latitude: 35.681236 + (index % 20) * 0.001,
                  longitude: 139.767125 + (index % 20) * 0.001,
                  address: 'Performance location ${index + 1}',
                  capturedAt: createdAt,
                )
              : null,
        ),
      );
    }
    if (notesToAdd.isEmpty && notesToRequeue.isEmpty) {
      return 0;
    }
    final next = [
      for (final note in state) notesToRequeue[note.id] ?? note,
      ...notesToAdd,
    ];
    _sort(next);
    state = next;
    await _persist();
    return notesToAdd.length + notesToRequeue.length;
  }

  Future<List<NoteAttachment>> _createPerformanceTestAttachments({
    required int noteIndex,
    required int count,
  }) async {
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    final attachments = <NoteAttachment>[];
    for (var attachmentIndex = 0; attachmentIndex < count; attachmentIndex++) {
      final type = switch (attachmentIndex % 3) {
        0 => AttachmentType.photo,
        1 => AttachmentType.video,
        _ => AttachmentType.audio,
      };
      final extension = switch (type) {
        AttachmentType.photo => 'png',
        AttachmentType.video => 'mp4',
        AttachmentType.audio => 'm4a',
        AttachmentType.file => 'bin',
      };
      final mimeType = switch (type) {
        AttachmentType.photo => 'image/png',
        AttachmentType.video => 'video/mp4',
        AttachmentType.audio => 'audio/mp4',
        AttachmentType.file => 'application/octet-stream',
      };
      final fileName =
          'perf-${noteIndex.toString().padLeft(4, '0')}-'
          '${attachmentIndex.toString().padLeft(2, '0')}.$extension';
      final sourceFile = XFile.fromData(
        _performanceAttachmentBytes(type, noteIndex, attachmentIndex),
        name: fileName,
        mimeType: mimeType,
      );
      final storedPath = await attachmentStore.storeAttachment(
        sourceFile,
        type: type,
      );
      attachments.add(
        NoteAttachment(
          type: type,
          label: fileName,
          filePath: storedPath,
          durationMs: switch (type) {
            AttachmentType.video => 15000 + (noteIndex % 9) * 1000,
            AttachmentType.audio => 30000 + (noteIndex % 11) * 1000,
            _ => null,
          },
        ),
      );
    }
    return attachments;
  }

  Uint8List _performanceAttachmentBytes(
    AttachmentType type,
    int noteIndex,
    int attachmentIndex,
  ) {
    if (type == AttachmentType.photo) {
      return base64Decode('R0lGODlhAQABAIAAAAAAAP///ywAAAAAAQABAAACAUwAOw==');
    }
    final size = switch (type) {
      AttachmentType.video => 256 * 1024,
      AttachmentType.audio => 96 * 1024,
      AttachmentType.file => 32 * 1024,
      AttachmentType.photo => 1024,
    };
    final seed = (noteIndex + 1) * 1103515245 + attachmentIndex * 12345;
    return Uint8List.fromList(
      List<int>.generate(size, (offset) => (seed + offset * 31) & 0xff),
    );
  }

  Future<void> get restoreCompleted => _waitForInitialRestore();

  Future<void> reloadFromStorage() async {
    _restoreFailed = false;
    await _restore();
  }

  Future<int> deleteDemoNotes() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final seedIds = ref
        .read(homeRepositoryProvider)
        .seededNotes
        .map((note) => note.id)
        .toSet();
    final idsToDelete = state
        .where((note) => _isSeedNote(note) || seedIds.contains(note.id))
        .map((note) => note.id)
        .toSet();
    if (idsToDelete.isEmpty) {
      await _rememberDeletedSeedNoteIds(seedIds);
      return 0;
    }

    final removedNotes = state
        .where((note) => idsToDelete.contains(note.id))
        .toList(growable: false);
    state = state
        .where((note) => !idsToDelete.contains(note.id))
        .toList(growable: false);
    final selectedNoteId = ref.read(selectedNoteIdProvider);
    if (selectedNoteId != null && idsToDelete.contains(selectedNoteId)) {
      ref.read(selectedNoteIdProvider.notifier).select(null);
    }
    await _deleteAttachments([
      for (final note in removedNotes) ..._attachmentsIn(note),
    ]);
    await _rememberDeletedSeedNoteIds({...seedIds, ...idsToDelete});
    await _persist();
    return idsToDelete.length;
  }

  Future<int> resetLocalStorage() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final removedNotes = state
        .where((note) => note.deletedAt == null)
        .toList(growable: false);
    final removedCount = removedNotes.length;
    await _deleteAttachments([
      for (final note in state) ..._attachmentsIn(note),
    ]);
    state = const <NoteEntry>[];
    ref.read(selectedNoteIdProvider.notifier).select(null);
    await ref.read(noteEditorDraftStoreProvider).clear();
    await _rememberDeletedSeedNoteIds(
      ref
          .read(homeRepositoryProvider)
          .seededNotes
          .map((note) => note.id)
          .toSet(),
    );
    await ref.read(encryptedNoteStoreProvider).save(const <NoteEntry>[]);
    await _syncSpotlightIndexForAll();
    ref.invalidate(storageUsageSummaryProvider);
    return removedCount;
  }

  Future<int> cleanupUnreferencedAttachments() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final retainedAttachmentReferences = <String>{
      for (final note in state) ..._attachmentFilePathsIn(note),
    };
    return ref
        .read(encryptedAttachmentStoreProvider)
        .deleteUnreferencedAttachments(retainedAttachmentReferences);
  }

  Future<void> replaceFromSync(List<NoteEntry> notes) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final incomingPaths = {
      for (final note in notes) ..._attachmentFilePathsIn(note),
    };
    final removedAttachments = [
      for (final existing in state)
        for (final attachment in _attachmentsIn(existing))
          if (attachment.filePath != null &&
              !incomingPaths.contains(attachment.filePath))
            attachment,
    ];
    await _deleteAttachments(removedAttachments);
    final next = [...notes];
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> mergeFromSync(List<PreparedSyncNote> changes) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    if (changes.isEmpty) {
      return;
    }
    final next = [...state];
    final removedAttachments = <NoteAttachment>[];

    for (final change in changes) {
      final incoming = change.note.copyWith(syncState: NoteSyncState.synced);
      final index = next.indexWhere((note) => note.id == incoming.id);
      final current = index == -1 ? null : next[index];
      final shouldDelete = change.action == PendingNoteChangeAction.delete;

      if (current != null && _hasUnuploadedLocalChange(current)) {
        if (!_sameSyncedContent(current, incoming)) {
          next[index] = current.copyWith(syncState: NoteSyncState.conflict);
        }
        continue;
      }

      if (current != null && !_incomingWins(current, incoming)) {
        if (!_sameSyncedContent(current, incoming) &&
            !_hasUnuploadedLocalChange(current)) {
          final queued = current.copyWith(
            syncState: current.deletedAt == null
                ? NoteSyncState.pendingUpload
                : NoteSyncState.pendingDelete,
          );
          next[index] = queued.contentHash == null
              ? queued.copyWith(contentHash: _computeContentHash(queued))
              : queued;
        }
        continue;
      }

      final applied = shouldDelete
          ? incoming.copyWith(
              deletedAt: incoming.deletedAt ?? DateTime.now(),
              syncState: NoteSyncState.synced,
            )
          : incoming.copyWith(deletedAt: null, syncState: NoteSyncState.synced);

      if (current == null) {
        next.add(applied);
      } else {
        next[index] = applied;
        removedAttachments.addAll(_attachmentsIn(current));
      }
    }

    final stillRetained = <String>{
      for (final note in next) ..._attachmentFilePathsIn(note),
    };
    await _deleteAttachments(
      removedAttachments
          .where((attachment) {
            final filePath = attachment.filePath;
            return filePath != null && !stillRetained.contains(filePath);
          })
          .toList(growable: false),
    );

    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> resolveConflictKeepingLocal(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    final index = next.indexWhere((note) => note.id == noteId);
    if (index == -1) {
      return;
    }
    final current = next[index];
    final queued = current.copyWith(syncState: NoteSyncState.pendingUpload);
    next[index] = queued.copyWith(contentHash: _computeContentHash(queued));
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> resolveConflictUsingRemote(NoteEntry remoteNote) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    final index = next.indexWhere((note) => note.id == remoteNote.id);
    final applied = remoteNote.copyWith(
      deletedAt: null,
      syncState: NoteSyncState.synced,
    );
    final removedAttachments = <NoteAttachment>[];
    if (index == -1) {
      next.add(applied);
    } else {
      removedAttachments.addAll(_attachmentsIn(next[index]));
      next[index] = applied;
    }
    final retained = <String>{
      for (final note in next) ..._attachmentFilePathsIn(note),
    };
    await _deleteAttachments(
      removedAttachments
          .where((attachment) {
            final filePath = attachment.filePath;
            return filePath != null && !retained.contains(filePath);
          })
          .toList(growable: false),
    );
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> resolveConflictByMerging(NoteEntry remoteNote) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    final index = next.indexWhere((note) => note.id == remoteNote.id);
    if (index == -1) {
      final queued = remoteNote.copyWith(
        syncState: NoteSyncState.pendingUpload,
      );
      next.add(queued.copyWith(contentHash: _computeContentHash(queued)));
      _sort(next);
      state = next;
      await _persist();
      return;
    }
    final local = next[index];
    final mergedBody = _mergedConflictBody(local, remoteNote);
    final mergedAttachments = <NoteAttachment>[
      ...local.attachments,
      for (final attachment in remoteNote.attachments)
        if (!_hasEquivalentAttachment(local.attachments, attachment))
          attachment,
    ];
    final mergedBlocks = <NoteBlock>[
      NoteBlock(type: NoteBlockType.paragraph, text: mergedBody),
      for (final attachment in mergedAttachments)
        NoteBlock(
          type: _blockTypeForAttachment(attachment.type),
          attachment: attachment,
        ),
    ];
    final merged = local.copyWith(
      title: local.title.trim().isEmpty ? remoteNote.title : local.title,
      body: mergedBody,
      updatedAt: DateTime.now(),
      revision: math.max(local.revision, remoteNote.revision) + 1,
      attachments: mergedAttachments,
      blocks: mergedBlocks,
      syncState: NoteSyncState.pendingUpload,
    );
    next[index] = merged.copyWith(contentHash: _computeContentHash(merged));
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> markCurrentStateSynced() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    var changed = false;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (note.syncState == NoteSyncState.pendingUpload ||
          note.syncState == NoteSyncState.pendingDelete ||
          note.syncState == NoteSyncState.conflict) {
        next.add(note.copyWith(syncState: NoteSyncState.synced));
        changed = true;
      } else {
        next.add(note);
      }
    }
    if (!changed) {
      return;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> markSnapshotChangesSynced(
    Map<String, String?> pendingContentHashes,
  ) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    if (pendingContentHashes.isEmpty) {
      return;
    }
    var changed = false;
    final next = <NoteEntry>[];
    for (final note in state) {
      final pendingHash = pendingContentHashes[note.id];
      if (!pendingContentHashes.containsKey(note.id) ||
          (pendingHash != null && note.contentHash != pendingHash) ||
          (pendingHash == null && note.contentHash != null)) {
        next.add(note);
        continue;
      }
      if (note.syncState == NoteSyncState.pendingUpload ||
          note.syncState == NoteSyncState.pendingDelete ||
          note.syncState == NoteSyncState.conflict) {
        next.add(note.copyWith(syncState: NoteSyncState.synced));
        changed = true;
      } else {
        next.add(note);
      }
    }
    if (!changed) {
      return;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<List<NoteEntry>> notesForSyncSnapshot({
    Set<String>? pendingNoteIds,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    bool canUpload(NoteEntry note) => !_isLockedPrivatePlaceholder(note);
    if (pendingNoteIds == null) {
      return List<NoteEntry>.unmodifiable(state.where(canUpload));
    }
    return List<NoteEntry>.unmodifiable(
      state.where(
        (note) => pendingNoteIds.contains(note.id) && canUpload(note),
      ),
    );
  }

  Future<void> queueCurrentStateForSync() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    var changed = false;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) || isGeneratedSampleNote(note)) {
        next.add(note);
        continue;
      }
      final syncState = note.deletedAt == null
          ? NoteSyncState.pendingUpload
          : NoteSyncState.pendingDelete;
      if (note.syncState == syncState && note.contentHash != null) {
        next.add(note);
        continue;
      }
      final queued = note.copyWith(syncState: syncState);
      next.add(
        queued.contentHash == null
            ? queued.copyWith(contentHash: _computeContentHash(queued))
            : queued,
      );
      changed = true;
    }
    if (!changed) {
      return;
    }
    _sort(next);
    state = next;
    await _persist();
  }

  Future<void> createWidgetQuickCapture(String rawText) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    await _createExternalCapture(rawText: rawText);
  }

  Future<void> createSharedFileCapture({
    required String rawText,
    required List<QuickCaptureFile> files,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    await _createExternalCapture(rawText: rawText, files: files);
  }

  Future<void> _createExternalCapture({
    required String rawText,
    List<QuickCaptureFile> files = const <QuickCaptureFile>[],
  }) async {
    final text = rawText.trim();
    final validFiles = files
        .where((file) => file.path.isNotEmpty && file.attachmentType != null)
        .toList(growable: false);
    if (text.isEmpty && validFiles.isEmpty) {
      return;
    }
    await logFirebaseBreadcrumb('widget quick capture saved');
    final now = DateTime.now();
    final content = _splitExternalCaptureText(text, validFiles);
    final attachments = <NoteAttachment>[];
    final deferredPreviews = <String, Future<String?>>{};
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    for (final file in validFiles) {
      final attachmentType = file.attachmentType;
      if (attachmentType == null) {
        continue;
      }
      final sourceFile = XFile(
        file.path,
        name: file.name.isEmpty ? path.basename(file.path) : file.name,
        mimeType: file.mimeType.isEmpty ? null : file.mimeType,
      );
      final storedPath = await attachmentStore.storeAttachment(
        sourceFile,
        type: attachmentType,
      );
      final durationMs = await _mediaDurationMs(
        type: attachmentType,
        sourceFile: sourceFile,
      );
      String? previewBytesBase64;
      Future<String?>? deferredPreview;
      if (attachmentType == AttachmentType.video) {
        int? sourceBytes;
        try {
          sourceBytes = await sourceFile.length();
        } catch (_) {}
        if (sourceBytes != null &&
            sourceBytes > _deferredVideoPreviewThresholdBytes) {
          deferredPreview = _videoPreviewBytesBase64ForSourceFile(sourceFile);
        } else {
          previewBytesBase64 = await _videoPreviewBytesBase64ForSourceFile(
            sourceFile,
          );
        }
      }
      final attachment = NoteAttachment(
        type: attachmentType,
        label: sourceFile.name,
        filePath: storedPath,
        previewBytesBase64: previewBytesBase64,
        durationMs: durationMs,
      );
      attachments.add(attachment);
      if (deferredPreview != null && storedPath != null) {
        deferredPreviews[storedPath] = deferredPreview;
      }
    }
    final noteId = now.microsecondsSinceEpoch.toString();
    await upsert(
      NoteEntry(
        id: noteId,
        vaultId: 'everyday',
        title: content.title,
        body: content.body,
        createdAt: now,
        updatedAt: now,
        attachments: attachments,
        blocks: [
          if (content.body.isNotEmpty)
            NoteBlock(type: NoteBlockType.paragraph, text: content.body),
          for (final attachment in attachments)
            NoteBlock(
              type: switch (attachment.type) {
                AttachmentType.photo => NoteBlockType.photo,
                AttachmentType.video => NoteBlockType.video,
                AttachmentType.audio => NoteBlockType.audio,
                AttachmentType.file => NoteBlockType.file,
              },
              attachment: attachment,
            ),
        ],
        editorMode: NoteEditorMode.quick,
      ),
    );
    if (deferredPreviews.isNotEmpty) {
      unawaited(_applyDeferredPreviewsToNote(noteId, deferredPreviews));
    }
  }

  Future<void> _applyDeferredPreviewsToNote(
    String noteId,
    Map<String, Future<String?>> deferredPreviews,
  ) async {
    final resolved = <String, String>{};
    for (final entry in deferredPreviews.entries) {
      try {
        final preview = await entry.value;
        if (preview != null) {
          resolved[entry.key] = preview;
        }
      } catch (_) {}
    }
    if (resolved.isEmpty) {
      return;
    }
    final note = state.cast<NoteEntry?>().firstWhere(
      (n) => n?.id == noteId,
      orElse: () => null,
    );
    if (note == null) {
      return;
    }
    NoteAttachment applyPreview(NoteAttachment a) {
      final preview = a.filePath != null ? resolved[a.filePath] : null;
      return preview != null ? a.copyWith(previewBytesBase64: preview) : a;
    }

    await upsert(
      note.copyWith(
        attachments: note.attachments.map(applyPreview).toList(),
        blocks: note.blocks
            .map(
              (b) => b.attachment != null
                  ? b.copyWith(attachment: applyPreview(b.attachment!))
                  : b,
            )
            .toList(),
      ),
    );
  }

  Future<void> _restore() async {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      final deletedSeedNoteIds = await _deletedSeedNoteIds();
      final restored = [
        ...await ref
            .read(encryptedNoteStoreProvider)
            .load(fallbackNotes: const <NoteEntry>[]),
      ];
      if (!ref.mounted) {
        return;
      }
      final restoredWithoutDeletedSeeds = restored
          .where((note) => !deletedSeedNoteIds.contains(note.id))
          .toList(growable: false);
      var next = restoredWithoutDeletedSeeds;
      var changed = restoredWithoutDeletedSeeds.length != restored.length;
      if (!kIsWeb &&
          next.any((note) => note.syncState == NoteSyncState.conflict)) {
        final pendingChanges = await ref
            .read(encryptedNoteDatabaseProvider)
            .loadPendingChanges();
        final pendingIds = pendingChanges
            .map((change) => change.noteId)
            .toSet();
        if (next.any(
          (note) =>
              note.syncState == NoteSyncState.conflict &&
              !pendingIds.contains(note.id),
        )) {
          changed = true;
        }
      }
      if (next.isEmpty && await _shouldSeedDemoNotesForStoreAssets()) {
        next = ref
            .read(homeRepositoryProvider)
            .seededNotes
            .where((note) => note.vaultId == 'everyday')
            .toList(growable: false);
        changed = true;
      }
      _sort(next);
      state = next;
      final purgedTrash = await _purgeTrashOlderThan(trashRetention);
      changed = changed || purgedTrash > 0;
      _restoreFailed = false;
      stopwatch?.stop();
      _debugHomePerf(
        'notes restore count=${state.length} changed=$changed elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms',
      );
      if (changed) {
        await _persist();
      }
    } catch (error, stackTrace) {
      stopwatch?.stop();
      _debugHomePerf(
        'notes restore failed elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms error=$error',
      );
      if (!ref.mounted) {
        return;
      }
      _restoreFailed = true;
      state = const <NoteEntry>[];
      await recordNonFatalError(
        error,
        stackTrace,
        reason: 'notes_restore_failed',
      );
    }
  }

  Future<Set<String>> _deletedSeedNoteIds() async {
    final prefs = await SharedPreferences.getInstance();
    return (prefs.getStringList(_deletedSeedNoteIdsKey) ?? const <String>[])
        .toSet();
  }

  Future<bool> _shouldSeedDemoNotesForStoreAssets() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_storeAssetsSeedDemoNotesKey) ?? false;
  }

  Future<void> _rememberDeletedSeedNoteIds(Set<String> ids) async {
    final prefs = await SharedPreferences.getInstance();
    if (ids.isEmpty) {
      await prefs.remove(_deletedSeedNoteIdsKey);
      return;
    }
    await prefs.setStringList(_deletedSeedNoteIdsKey, ids.toList()..sort());
  }

  Future<int> _purgeTrashOlderThan(Duration retention) async {
    final cutoff = DateTime.now().subtract(retention);
    final expired = [
      for (final note in state)
        if (note.deletedAt != null && note.deletedAt!.isBefore(cutoff)) note,
    ];
    if (expired.isEmpty) {
      return 0;
    }
    final expiredIds = {for (final note in expired) note.id};
    state = [
      for (final note in state)
        if (!expiredIds.contains(note.id)) note,
    ];
    await _deleteAttachments([
      for (final note in expired) ..._attachmentsIn(note),
    ]);
    final store = ref.read(encryptedNoteStoreProvider);
    for (final noteId in expiredIds) {
      await store.deleteById(noteId);
    }
    ref.invalidate(storageUsageSummaryProvider);
    logAudit('note_trash_purge', data: {'count': expired.length});
    return expired.length;
  }

  Future<void> _waitForInitialRestore() async {
    final task = _restoreTask;
    if (task != null) {
      await task;
    }
  }

  void _ensureRestoreSucceeded() {
    if (_restoreFailed) {
      throw StateError(
        'Stored notes could not be restored. Refusing to overwrite local data.',
      );
    }
  }

  bool _isSeedNote(NoteEntry note) =>
      note.deviceId == 'seeded-device' || note.id.startsWith('seed-');

  bool _isLockedPrivatePlaceholder(NoteEntry note) {
    return note.deviceId == 'locked-private-note' &&
        isPrivateVaultId(note.vaultId);
  }

  Future<void> _persist() async {
    if (_restoreFailed) {
      return;
    }
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      await ref.read(encryptedNoteStoreProvider).save(state);
      ref.invalidate(syncQueueSummaryProvider);
      await _syncSpotlightIndexForAll();
      stopwatch?.stop();
      _debugHomePerf(
        'notes persist full count=${state.length} elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms',
      );
    } catch (error, stackTrace) {
      stopwatch?.stop();
      _debugHomePerf(
        'notes persist full failed count=${state.length} elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms error=$error',
      );
      await recordNonFatalError(
        error,
        stackTrace,
        reason: 'notes_persist_failed',
      );
    }
  }

  Future<void> _persistOne(NoteEntry note) async {
    if (_restoreFailed) {
      return;
    }
    if (kIsWeb) {
      await _persist();
      return;
    }
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    try {
      await ref.read(encryptedNoteStoreProvider).saveOne(note);
      ref.invalidate(syncQueueSummaryProvider);
      await _syncSpotlightIndexForNote(note);
      stopwatch?.stop();
      _debugHomePerf(
        'notes persist one id=${note.id} attachments=${note.attachments.length} elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms',
      );
    } catch (error, stackTrace) {
      stopwatch?.stop();
      _debugHomePerf(
        'notes persist one failed id=${note.id} elapsed=${stopwatch?.elapsedMilliseconds ?? 0}ms error=$error',
      );
      await recordNonFatalError(
        error,
        stackTrace,
        reason: 'note_persist_one_failed',
      );
      await _persist();
    }
  }

  Future<void> _syncSpotlightIndexForAll() async {
    if (!ref.read(spotlightNoteIndexEnabledControllerProvider)) {
      return;
    }
    await ref
        .read(spotlightNoteIndexBridgeProvider)
        .replaceAllStandardNotes(state);
  }

  Future<void> _syncSpotlightIndexForNote(NoteEntry note) async {
    if (!ref.read(spotlightNoteIndexEnabledControllerProvider)) {
      return;
    }
    await ref.read(spotlightNoteIndexBridgeProvider).upsert(note);
  }

  Future<void> _cleanupRemovedAttachments(
    NoteEntry? previous,
    NoteEntry next,
  ) async {
    if (previous == null) {
      return;
    }
    final retained = _attachmentFilePathsIn(next);
    final removed = _attachmentsIn(previous)
        .where((attachment) {
          final filePath = attachment.filePath;
          return filePath != null && !retained.contains(filePath);
        })
        .toList(growable: false);
    await _deleteAttachments(removed);
  }

  Iterable<NoteAttachment> _attachmentsIn(NoteEntry note) sync* {
    yield* note.attachments;
    for (final block in note.blocks) {
      final attachment = block.attachment;
      if (attachment != null) {
        yield attachment;
      }
    }
  }

  Set<String> _attachmentFilePathsIn(NoteEntry note) {
    return {
      for (final attachment in _attachmentsIn(note))
        if (attachment.filePath != null && attachment.filePath!.isNotEmpty)
          attachment.filePath!,
    };
  }

  Future<void> _deleteAttachments(List<NoteAttachment> attachments) async {
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    final deleted = <String>{};
    for (final attachment in attachments) {
      final filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
        continue;
      }
      if (!deleted.add(filePath)) {
        continue;
      }
      await attachmentStore.deleteAttachment(filePath);
    }
  }

  Future<NoteEntry> _prepareForSave(
    NoteEntry note, {
    NoteEntry? previous,
  }) async {
    final deviceId =
        note.deviceId ??
        previous?.deviceId ??
        await ref.read(deviceIdentityStoreProvider).obtain();
    final createdAt = note.createdAt;
    final updatedAt = note.updatedAt ?? DateTime.now();
    final normalized = note.copyWith(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: null,
      deviceId: deviceId,
      revision: previous == null ? note.revision : previous.revision + 1,
      syncState: NoteSyncState.pendingUpload,
    );
    final protected = await _protectAttachmentsForVault(normalized);
    return protected.copyWith(contentHash: _computeContentHash(protected));
  }

  Future<NoteEntry> _protectAttachmentsForVault(NoteEntry note) async {
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    final protectedPaths = <String>{};

    Future<NoteAttachment> protect(NoteAttachment attachment) async {
      final filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
        return attachment;
      }
      if (protectedPaths.add(filePath)) {
        await attachmentStore.protectAttachmentForVault(
          filePath,
          type: attachment.type,
          vaultId: note.vaultId,
        );
      }
      return attachment;
    }

    final attachments = <NoteAttachment>[];
    for (final attachment in note.attachments) {
      attachments.add(await protect(attachment));
    }
    final blocks = <NoteBlock>[];
    for (final block in note.blocks) {
      final attachment = block.attachment;
      blocks.add(
        attachment == null
            ? block
            : block.copyWith(attachment: await protect(attachment)),
      );
    }
    return note.copyWith(attachments: attachments, blocks: blocks);
  }

  String _computeContentHash(NoteEntry note) {
    final payload = jsonEncode({
      'id': note.id,
      'vaultId': note.vaultId,
      'title': note.title,
      'body': note.body,
      'blocks': note.blocks.map((block) => block.toJson()).toList(),
      'tags': note.tags,
      'createdAt': note.createdAt.toIso8601String(),
      'updatedAt': note.updatedAt?.toIso8601String(),
      'deletedAt': note.deletedAt?.toIso8601String(),
      'archivedAt': note.archivedAt?.toIso8601String(),
      'isPinned': note.isPinned,
      'revision': note.revision,
      'attachments': [
        for (final attachment in note.attachments)
          {
            'type': attachment.type.name,
            'label': attachment.label,
            'filePath': attachment.filePath,
          },
      ],
      'location': note.location?.toJson(),
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool _hasUnuploadedLocalChange(NoteEntry note) {
    return note.syncState == NoteSyncState.pendingUpload ||
        note.syncState == NoteSyncState.pendingDelete ||
        note.syncState == NoteSyncState.conflict;
  }

  String _mergedConflictBody(NoteEntry local, NoteEntry remote) {
    final localBody = local.body.trim();
    final remoteBody = remote.body.trim();
    if (localBody == remoteBody) {
      return local.body;
    }
    final buffer = StringBuffer()
      ..writeln('Local version')
      ..writeln(localBody.isEmpty ? '(empty)' : localBody)
      ..writeln()
      ..writeln('Remote version')
      ..write(remoteBody.isEmpty ? '(empty)' : remoteBody);
    return buffer.toString();
  }

  bool _hasEquivalentAttachment(
    List<NoteAttachment> attachments,
    NoteAttachment candidate,
  ) {
    return attachments.any((attachment) {
      if (attachment.filePath != null &&
          candidate.filePath != null &&
          attachment.filePath == candidate.filePath) {
        return true;
      }
      return attachment.type == candidate.type &&
          attachment.label == candidate.label &&
          attachment.previewBytesBase64 == candidate.previewBytesBase64;
    });
  }

  NoteBlockType _blockTypeForAttachment(AttachmentType type) {
    return switch (type) {
      AttachmentType.photo => NoteBlockType.photo,
      AttachmentType.video => NoteBlockType.video,
      AttachmentType.audio => NoteBlockType.audio,
      AttachmentType.file => NoteBlockType.file,
    };
  }

  bool _sameSyncedContent(NoteEntry current, NoteEntry incoming) {
    return current.contentHash != null &&
        incoming.contentHash != null &&
        current.contentHash == incoming.contentHash;
  }

  bool _incomingWins(NoteEntry current, NoteEntry incoming) {
    if (incoming.revision != current.revision) {
      return incoming.revision > current.revision;
    }
    return _syncMoment(incoming).isAfter(_syncMoment(current));
  }

  DateTime _syncMoment(NoteEntry note) {
    return note.deletedAt ?? note.updatedAt ?? note.createdAt;
  }

  void _sort(List<NoteEntry> notes) {
    notes.sort((left, right) {
      final leftMoment = left.updatedAt ?? left.createdAt;
      final rightMoment = right.updatedAt ?? right.createdAt;
      final dateOrder = rightMoment.compareTo(leftMoment);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return right.createdAt.compareTo(left.createdAt);
    });
  }
}

final unlockedPrivateProfileVaultIdProvider =
    NotifierProvider<UnlockedPrivateProfileVaultIdController, String?>(
      UnlockedPrivateProfileVaultIdController.new,
    );

class UnlockedPrivateProfileVaultIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void unlock(String vaultId) {
    final previousVaultId = state;
    state = vaultId;
    if (previousVaultId != vaultId) {
      logAudit(
        'private_profile_unlock',
        data: {'vaultId': vaultId, 'adminMode': false},
      );
    }
    ref.read(searchFiltersControllerProvider.notifier).setVault(vaultId);
  }

  void lock() {
    final vaultId = state;
    if (vaultId != null) {
      ref.read(profileDataKeyServiceProvider).lockProfile(vaultId);
      final filters = ref.read(searchFiltersControllerProvider);
      if (filters.vaultId == vaultId) {
        ref.read(searchFiltersControllerProvider.notifier).setVault(null);
      }
    }
    state = null;
    if (vaultId != null) {
      logAudit('private_profile_lock', data: {'vaultId': vaultId});
    }
  }
}

final adminModeSessionControllerProvider =
    NotifierProvider<AdminModeSessionController, bool>(
      AdminModeSessionController.new,
    );

class AdminModeSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() {
    final changed = !state;
    state = true;
    if (changed) {
      logAudit('admin_mode_login', data: {'allProfilesReadable': true});
    }
  }

  void lock() {
    final changed = state;
    state = false;
    if (changed) {
      logAudit('admin_mode_logout');
    }
  }
}

final privateProfileUnlockControllerProvider =
    NotifierProvider<PrivateProfileUnlockController, AsyncValue<void>>(
      PrivateProfileUnlockController.new,
    );

class PrivateProfileUnlockController extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<UnlockProfileResult?> unlockWithPassword(String password) async {
    state = const AsyncLoading();
    try {
      final custom = await ref
          .read(privateMemoProfileStoreProvider)
          .verifyAny(password);
      if (custom != null) {
        ref
            .read(unlockedPrivateProfileVaultIdProvider.notifier)
            .unlock(custom.vaultId);
        ref.read(adminModeSessionControllerProvider.notifier).lock();
        await _applyPendingDownloadedBundle();
        await ref.read(notesControllerProvider.notifier).reloadFromStorage();
        state = const AsyncData(null);
        return custom;
      }
      final legacyMatched = await ref
          .read(privateVaultSecretControllerProvider.notifier)
          .verify(password);
      if (legacyMatched) {
        const result = UnlockProfileResult(
          vaultId: legacyPrivateVaultId,
          label: 'Private profile',
          isLegacy: true,
        );
        ref
            .read(unlockedPrivateProfileVaultIdProvider.notifier)
            .unlock(result.vaultId);
        ref.read(adminModeSessionControllerProvider.notifier).lock();
        await _applyPendingDownloadedBundle();
        await ref.read(notesControllerProvider.notifier).reloadFromStorage();
        state = const AsyncData(null);
        return result;
      }
      state = const AsyncData(null);
      return null;
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
      return null;
    }
  }

  Future<void> _applyPendingDownloadedBundle() async {
    if (ref.read(syncTransferControllerProvider).localBundle == null) {
      return;
    }
    await ref
        .read(syncTransferControllerProvider.notifier)
        .applyDownloadedBundle();
  }
}

final privateMemoProfilesProvider = Provider<List<PrivateMemoProfile>>(
  (ref) => ref.watch(privateMemoProfilesControllerProvider),
);

final privateMemoProfilesControllerProvider =
    NotifierProvider<PrivateMemoProfilesController, List<PrivateMemoProfile>>(
      PrivateMemoProfilesController.new,
    );

class PrivateMemoProfilesController extends Notifier<List<PrivateMemoProfile>> {
  bool _restored = false;

  @override
  List<PrivateMemoProfile> build() {
    if (!_restored) {
      _restored = true;
      unawaited(refresh());
    }
    return const <PrivateMemoProfile>[];
  }

  Future<void> refresh() async {
    state = await ref.read(privateMemoProfileStoreProvider).listProfiles();
  }

  Future<String?> addProfile({
    required String name,
    required String password,
  }) async {
    final error = await ref
        .read(privateMemoProfileStoreProvider)
        .addProfile(name: name, password: password);
    await refresh();
    return error;
  }

  Future<void> deleteProfile(String id) async {
    await ref.read(privateMemoProfileStoreProvider).deleteProfile(id);
    final unlockedVaultId = ref.read(unlockedPrivateProfileVaultIdProvider);
    final vaultId = '$customPrivateVaultPrefix$id';
    await ref
        .read(profileColorThemeControllerProvider.notifier)
        .clearTheme(vaultId);
    if (unlockedVaultId == vaultId) {
      ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    }
    await refresh();
  }

  Future<void> updateProfilePassword({
    required String id,
    required String password,
  }) async {
    await ref
        .read(privateMemoProfileStoreProvider)
        .updateProfilePassword(id: id, password: password);
    await refresh();
  }
}

final accessiblePrivateVaultIdsProvider = Provider<List<String>>((ref) {
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  final profiles = ref.watch(privateMemoProfilesControllerProvider);
  final legacyConfigured = ref.watch(privateVaultSecretControllerProvider);
  if (adminMode) {
    return [
      if (legacyConfigured) legacyPrivateVaultId,
      for (final profile in profiles) profile.vaultId,
    ];
  }
  return [?unlockedVaultId];
});

final activePrivateProfileLabelProvider = Provider<String?>((ref) {
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  if (adminMode) {
    return 'Admin mode';
  }
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  if (unlockedVaultId == null) {
    return null;
  }
  if (unlockedVaultId == legacyPrivateVaultId) {
    return 'Private profile';
  }
  final profiles = ref.watch(privateMemoProfilesControllerProvider);
  final match = profiles.where((profile) => profile.vaultId == unlockedVaultId);
  if (match.isEmpty) {
    return null;
  }
  return match.first.name;
});

final privacyScreenActiveProvider = Provider<bool>((ref) {
  final legacyPrivateUnlocked = ref.watch(
    privateVaultSessionControllerProvider,
  );
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  return legacyPrivateUnlocked || adminMode || unlockedVaultId != null;
});

@riverpod
List<VaultBucket> vaults(Ref ref) => ref.watch(homeRepositoryProvider).vaults;

@riverpod
List<UnlockIdentity> identities(Ref ref) =>
    ref.watch(homeRepositoryProvider).identities;

@riverpod
UnlockIdentity activeIdentityData(Ref ref) {
  final activeId = ref.watch(activeIdentityProvider);
  return ref
      .watch(identitiesProvider)
      .firstWhere((identity) => identity.id == activeId);
}

@riverpod
List<VaultBucket> visibleVaults(Ref ref) {
  final baseVault = ref
      .watch(vaultsProvider)
      .firstWhere((vault) => vault.id == 'everyday');
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  final accessiblePrivateVaultIds = ref.watch(
    accessiblePrivateVaultIdsProvider,
  );
  final profiles = ref.watch(privateMemoProfilesControllerProvider);
  VaultBucket? privateVaultFor(String vaultId) {
    if (vaultId == legacyPrivateVaultId) {
      return const VaultBucket(
        id: legacyPrivateVaultId,
        name: 'Private profile',
        description: '__unlocked_private_notes__',
      );
    }
    final match = profiles.where((profile) => profile.vaultId == vaultId);
    if (match.isEmpty) {
      return null;
    }
    final profile = match.first;
    return VaultBucket(
      id: profile.vaultId,
      name: profile.name,
      description: '__unlocked_private_notes__',
    );
  }

  final visible = <VaultBucket>[];
  if (!adminMode && unlockedVaultId != null) {
    final activePrivateVault = privateVaultFor(unlockedVaultId);
    if (activePrivateVault != null) {
      visible.add(activePrivateVault);
    }
  }
  visible.add(baseVault);
  for (final vaultId in accessiblePrivateVaultIds) {
    if (vaultId == unlockedVaultId && !adminMode) {
      continue;
    }
    final privateVault = privateVaultFor(vaultId);
    if (privateVault == null) {
      continue;
    }
    visible.add(privateVault);
  }
  return visible;
}

@riverpod
List<NoteEntry> visibleNotes(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final allNotes = ref.watch(notesControllerProvider);
  final visibleVaults = ref.watch(visibleVaultsProvider);
  final visibleIds = visibleVaults.map((vault) => vault.id).toSet();
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filters = ref.watch(searchFiltersControllerProvider);
  final sortField = ref.watch(notesListSortControllerProvider);
  final searchIndex = query.isEmpty
      ? const <String, String>{}
      : ref.watch(noteSearchIndexProvider);
  final filterVaultId = filters.vaultId;
  final filterYear = filters.year;
  final dateRangeStart = _searchDateRangeStart(filters.dateRange);
  final requiredTags = filters.tags
      .map(canonicalizeNoteTag)
      .where((tag) => tag.isNotEmpty)
      .toSet();
  final results = <NoteEntry>[];
  for (final note in allNotes) {
    if (!visibleIds.contains(note.vaultId) || note.deletedAt != null) {
      continue;
    }
    if (filters.archivedOnly) {
      if (note.archivedAt == null) {
        continue;
      }
    } else if (!filters.includeArchived && note.archivedAt != null) {
      continue;
    }
    if (filterVaultId != null && note.vaultId != filterVaultId) {
      continue;
    }
    if (filterYear != null && note.createdAt.toLocal().year != filterYear) {
      continue;
    }
    if (dateRangeStart != null) {
      final noteDate = filters.dateField == SearchDateField.updatedAt
          ? (note.updatedAt ?? note.createdAt)
          : note.createdAt;
      if (noteDate.isBefore(dateRangeStart)) {
        continue;
      }
    }
    if (filters.pinnedOnly && !note.isPinned) {
      continue;
    }
    if (!_noteMatchesAttachmentFilter(note, filters.attachmentFilters)) {
      continue;
    }
    if (requiredTags.isNotEmpty) {
      final noteTagKeys = {
        for (final tag in note.tags) canonicalizeNoteTag(tag),
      };
      final matchedTag = filters.requireAllTags
          ? requiredTags.every(noteTagKeys.contains)
          : requiredTags.any(noteTagKeys.contains);
      if (!matchedTag) {
        continue;
      }
    }
    if (query.isNotEmpty && !_noteMatchesQuery(note, query, searchIndex)) {
      continue;
    }
    results.add(note);
  }
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (allNotes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible notes source=${allNotes.length} result=${results.length} query=${query.isEmpty ? 0 : query.length} tags=${requiredTags.length} elapsed=${elapsed / 1000}ms',
    );
  }
  results.sort((left, right) => _compareVisibleNotes(left, right, sortField));
  return List.unmodifiable(results);
}

final trashedNotesProvider = Provider<List<NoteEntry>>((ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final results = [
    for (final note in ref.watch(notesControllerProvider))
      if (note.deletedAt != null && visibleIds.contains(note.vaultId)) note,
  ];
  results.sort((left, right) {
    final leftDeletedAt = left.deletedAt ?? left.updatedAt ?? left.createdAt;
    final rightDeletedAt =
        right.deletedAt ?? right.updatedAt ?? right.createdAt;
    final dateOrder = rightDeletedAt.compareTo(leftDeletedAt);
    if (dateOrder != 0) {
      return dateOrder;
    }
    return right.createdAt.compareTo(left.createdAt);
  });
  return List<NoteEntry>.unmodifiable(results);
});

int _compareVisibleNotes(
  NoteEntry left,
  NoteEntry right,
  NotesListSortField sortField,
) {
  final leftMoment = switch (sortField) {
    NotesListSortField.updatedAt => left.updatedAt ?? left.createdAt,
    NotesListSortField.createdAt => left.createdAt,
  };
  final rightMoment = switch (sortField) {
    NotesListSortField.updatedAt => right.updatedAt ?? right.createdAt,
    NotesListSortField.createdAt => right.createdAt,
  };
  final dateOrder = rightMoment.compareTo(leftMoment);
  if (dateOrder != 0) {
    return dateOrder;
  }
  return right.createdAt.compareTo(left.createdAt);
}

DateTime? _searchDateRangeStart(SearchDateRange range) {
  final now = DateTime.now();
  return switch (range) {
    SearchDateRange.all => null,
    SearchDateRange.last7Days => now.subtract(const Duration(days: 7)),
    SearchDateRange.last30Days => now.subtract(const Duration(days: 30)),
    SearchDateRange.thisMonth => DateTime(now.year, now.month),
  };
}

bool _noteMatchesAttachmentFilter(
  NoteEntry note,
  List<SearchAttachmentFilter> filters,
) {
  if (filters.isEmpty) {
    return true;
  }
  if (filters.contains(SearchAttachmentFilter.any)) {
    return note.attachments.isNotEmpty || note.location != null;
  }
  return filters.any((filter) {
    return switch (filter) {
      SearchAttachmentFilter.all => true,
      SearchAttachmentFilter.any =>
        note.attachments.isNotEmpty || note.location != null,
      SearchAttachmentFilter.photo => note.attachments.any(
        (attachment) => attachment.type == AttachmentType.photo,
      ),
      SearchAttachmentFilter.video => note.attachments.any(
        (attachment) => attachment.type == AttachmentType.video,
      ),
      SearchAttachmentFilter.audio => note.attachments.any(
        (attachment) => attachment.type == AttachmentType.audio,
      ),
      SearchAttachmentFilter.location => note.location != null,
    };
  });
}

@riverpod
List<int> visibleNoteYears(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(visibleNotesProvider);
  final years = <int>{};
  for (final note in notes) {
    years.add(note.createdAt.toLocal().year);
  }
  final sorted = years.toList(growable: false)
    ..sort((left, right) => right.compareTo(left));
  final result = List<int>.unmodifiable(sorted);
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible note years source=${notes.length} years=${result.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return result;
}

final unfilteredVisibleNotesProvider = Provider<List<NoteEntry>>((ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final notes = [
    for (final note in ref.watch(notesControllerProvider))
      if (note.deletedAt == null &&
          note.archivedAt == null &&
          visibleIds.contains(note.vaultId))
        note,
  ];
  return List<NoteEntry>.unmodifiable(notes);
});

@riverpod
Map<String, String> noteSearchIndex(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(notesControllerProvider);
  final filters = ref.watch(searchFiltersControllerProvider);
  final entries = <String, String>{};
  for (final note in notes) {
    if (note.deletedAt != null) {
      continue;
    }
    if (filters.archivedOnly) {
      if (note.archivedAt == null) {
        continue;
      }
    } else if (!filters.includeArchived && note.archivedAt != null) {
      continue;
    }
    entries[note.id] = _noteSearchText(note);
  }
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'note search index source=${notes.length} entries=${entries.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return Map.unmodifiable(entries);
}

String _noteSearchText(NoteEntry note) {
  final buffer = StringBuffer()
    ..write(note.title)
    ..write('\n')
    ..write(note.body);
  for (final tag in note.tags) {
    buffer
      ..write('\n')
      ..write(tag);
  }
  for (final attachment in note.attachments) {
    buffer
      ..write('\n')
      ..write(attachment.label);
  }
  final location = note.location;
  if (location != null) {
    buffer
      ..write('\n')
      ..write(location.address ?? '')
      ..write('\n')
      ..write(location.latitude)
      ..write('\n')
      ..write(location.longitude);
  }
  return buffer.toString().toLowerCase();
}

bool _noteMatchesQuery(
  NoteEntry note,
  String query,
  Map<String, String> searchIndex,
) {
  return searchIndex[note.id]?.contains(query) ?? false;
}

@riverpod
List<String> visibleTagSuggestions(Ref ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final seen = <String>{};
  final tags = <String>[];
  for (final note in ref.watch(notesControllerProvider)) {
    if (note.deletedAt != null ||
        note.archivedAt != null ||
        !visibleIds.contains(note.vaultId)) {
      continue;
    }
    for (final tag in note.tags) {
      final normalized = normalizeNoteTag(tag);
      if (normalized.isEmpty) {
        continue;
      }
      final key = canonicalizeNoteTag(normalized);
      if (!seen.add(key)) {
        continue;
      }
      tags.add(normalized);
    }
  }
  tags.sort((left, right) => left.toLowerCase().compareTo(right.toLowerCase()));
  return List.unmodifiable(tags);
}

class TagSuggestionRequest {
  const TagSuggestionRequest({
    required this.title,
    required this.body,
    required this.existingTags,
    required this.knownTags,
    required this.attachmentLabels,
    this.knownTagCounts = const <String, int>{},
  });

  final String title;
  final String body;
  final List<String> existingTags;
  final List<String> knownTags;
  final List<String> attachmentLabels;

  /// Canonicalized tag key -> usage count among visible notes. Used to give
  /// frequently-used tags a higher priority in suggestions.
  final Map<String, int> knownTagCounts;
}

class TagSuggestionResult {
  const TagSuggestionResult({
    required this.tags,
    required this.source,
    required this.usedAppleIntelligence,
  });

  final List<String> tags;
  final String source;
  final bool usedAppleIntelligence;
}

abstract class TagSuggestionGateway {
  Future<TagSuggestionResult> suggestTags(TagSuggestionRequest request);
}

final tagSuggestionGatewayProvider = Provider<TagSuggestionGateway>((ref) {
  return MethodChannelTagSuggestionGateway();
});

class MethodChannelTagSuggestionGateway implements TagSuggestionGateway {
  MethodChannelTagSuggestionGateway({
    MethodChannel channel = const MethodChannel(
      'org.ruhenheim.himemo/intelligence',
    ),
  }) : _channel = channel;

  final MethodChannel _channel;

  @override
  Future<TagSuggestionResult> suggestTags(TagSuggestionRequest request) async {
    final fallbackTags = suggestLocalNoteTags(request);
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
      return TagSuggestionResult(
        tags: fallbackTags,
        source: 'local',
        usedAppleIntelligence: false,
      );
    }
    try {
      final response = await _channel
          .invokeMapMethod<String, Object?>('suggestTags', {
            'title': request.title,
            'body': request.body,
            'existingTags': request.existingTags,
            'knownTags': request.knownTags,
            'knownTagCounts': request.knownTagCounts,
            'attachmentLabels': request.attachmentLabels,
          });
      final nativeTags = dedupeNoteTags([
        for (final tag in response?['tags'] as List? ?? const []) '$tag',
      ]);
      final existingKeys = {
        for (final tag in request.existingTags) canonicalizeNoteTag(tag),
      };
      final tags = [
        for (final tag in nativeTags)
          if (!existingKeys.contains(canonicalizeNoteTag(tag))) tag,
      ];
      if (tags.isNotEmpty) {
        return TagSuggestionResult(
          tags: tags,
          source: '${response?['source'] ?? 'apple_intelligence'}',
          usedAppleIntelligence: response?['usedAppleIntelligence'] == true,
        );
      }
    } on MissingPluginException {
      // Fall through to the deterministic local model.
    } on PlatformException {
      // Apple Intelligence is unavailable on many devices and OS versions.
    }
    return TagSuggestionResult(
      tags: fallbackTags,
      source: 'local',
      usedAppleIntelligence: false,
    );
  }
}

List<String> suggestLocalNoteTags(TagSuggestionRequest request) {
  final existingKeys = {
    for (final tag in request.existingTags) canonicalizeNoteTag(tag),
  };
  final text = [
    request.title,
    request.body,
    ...request.attachmentLabels,
  ].join('\n').toLowerCase();
  final scored = <String, int>{};
  final displayName = <String, String>{};

  void addCandidate(String rawTag, int baseScore) {
    final normalized = normalizeNoteTag(rawTag);
    if (normalized.isEmpty) {
      return;
    }
    final key = canonicalizeNoteTag(normalized);
    if (key.isEmpty || existingKeys.contains(key)) {
      return;
    }
    var score = baseScore;
    // Prefer single-word style tags: short, no internal separators.
    final length = key.length;
    final hasSeparator = key.contains('_') || key.contains('-');
    if (hasSeparator) {
      score -= 4;
    }
    if (length <= 4) {
      score += 3;
    } else if (length >= 9) {
      score -= 4;
    }
    scored[key] = (scored[key] ?? 0) + score;
    displayName.putIfAbsent(key, () => normalized);
  }

  for (final knownTag in request.knownTags) {
    final normalized = normalizeNoteTag(knownTag);
    final key = canonicalizeNoteTag(normalized);
    if (key.isEmpty || existingKeys.contains(key)) {
      continue;
    }
    if (text.contains(key)) {
      // Strongly prefer known/already-used tags. Tags used more often get an
      // additional boost (capped to avoid one runaway tag dominating).
      final count = request.knownTagCounts[key] ?? 0;
      final usageBoost = (count * 3).clamp(0, 30);
      addCandidate(normalized, 40 + usageBoost);
    }
  }

  final sourceText = '${request.title}\n${request.body}';
  for (final match in RegExp(
    r'[A-Za-z0-9][A-Za-z0-9_-]{2,}|[一-龠々ぁ-んァ-ヶー]{2,}',
  ).allMatches(sourceText)) {
    final token = match.group(0) ?? '';
    if (_localTagStopWords.contains(token.toLowerCase())) {
      continue;
    }
    addCandidate(token, request.title.contains(token) ? 12 : 5);
  }

  final entries = scored.entries.toList()
    ..sort((left, right) {
      final scoreOrder = right.value.compareTo(left.value);
      if (scoreOrder != 0) {
        return scoreOrder;
      }
      return displayName[left.key]!.compareTo(displayName[right.key]!);
    });
  return List.unmodifiable([
    for (final entry in entries.take(8)) displayName[entry.key]!,
  ]);
}

const _localTagStopWords = <String>{
  'the',
  'and',
  'for',
  'with',
  'from',
  'this',
  'that',
  'memo',
  'note',
  'について',
  'です',
  'ます',
  'する',
  'した',
  'ある',
  'これ',
  'それ',
};

class VisibleTagSummary {
  const VisibleTagSummary({
    required this.name,
    required this.count,
    required this.latestAt,
  });

  final String name;
  final int count;
  final DateTime latestAt;
}

final visibleTagSummariesProvider = Provider<List<VisibleTagSummary>>((ref) {
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final summaries = <String, ({String name, int count, DateTime latestAt})>{};
  for (final note in ref.watch(notesControllerProvider)) {
    if (note.deletedAt != null ||
        note.archivedAt != null ||
        !visibleIds.contains(note.vaultId)) {
      continue;
    }
    final noteAt = note.updatedAt ?? note.createdAt;
    for (final tag in note.tags) {
      final normalized = normalizeNoteTag(tag);
      if (normalized.isEmpty) {
        continue;
      }
      final key = canonicalizeNoteTag(normalized);
      final current = summaries[key];
      if (current == null) {
        summaries[key] = (name: normalized, count: 1, latestAt: noteAt);
      } else {
        summaries[key] = (
          name: current.name,
          count: current.count + 1,
          latestAt: noteAt.isAfter(current.latestAt)
              ? noteAt
              : current.latestAt,
        );
      }
    }
  }
  final result = summaries.values
      .map(
        (entry) => VisibleTagSummary(
          name: entry.name,
          count: entry.count,
          latestAt: entry.latestAt,
        ),
      )
      .toList();
  result.sort((left, right) {
    final countOrder = right.count.compareTo(left.count);
    if (countOrder != 0) {
      return countOrder;
    }
    final dateOrder = right.latestAt.compareTo(left.latestAt);
    if (dateOrder != 0) {
      return dateOrder;
    }
    return left.name.toLowerCase().compareTo(right.name.toLowerCase());
  });
  return List.unmodifiable(result);
});

final noteEditorDraftStoreProvider = Provider<NoteEditorDraftStore>(
  (ref) => NoteEditorDraftStore(),
);

Map<DateTime, List<NoteEntry>> _notesByCreatedDay(List<NoteEntry> notes) {
  final grouped = <DateTime, List<NoteEntry>>{};
  for (final note in notes) {
    final createdAt = note.createdAt.toLocal();
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    (grouped[day] ??= <NoteEntry>[]).add(note);
  }
  return Map<DateTime, List<NoteEntry>>.unmodifiable({
    for (final entry in grouped.entries)
      entry.key: List<NoteEntry>.unmodifiable(entry.value),
  });
}

@riverpod
Map<String, List<NoteEntry>> visibleNotesByVault(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(visibleNotesProvider);
  final grouped = <String, List<NoteEntry>>{};
  for (final note in notes) {
    (grouped[note.vaultId] ??= <NoteEntry>[]).add(note);
  }
  final result = Map<String, List<NoteEntry>>.unmodifiable({
    for (final entry in grouped.entries)
      entry.key: List<NoteEntry>.unmodifiable(entry.value),
  });
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible notes by vault source=${notes.length} vaults=${result.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return result;
}

@riverpod
Map<String, int> visibleNoteIndexById(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(visibleNotesProvider);
  final result = Map<String, int>.unmodifiable({
    for (var index = 0; index < notes.length; index++) notes[index].id: index,
  });
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible note index source=${notes.length} entries=${result.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return result;
}

@riverpod
Map<DateTime, List<NoteEntry>> visibleNotesByDay(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(visibleNotesProvider);
  final result = _notesByCreatedDay(notes);
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible notes by day source=${notes.length} days=${result.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return result;
}

final unfilteredVisibleNotesByDayProvider =
    Provider<Map<DateTime, List<NoteEntry>>>(
      (ref) => _notesByCreatedDay(ref.watch(unfilteredVisibleNotesProvider)),
    );

final unfilteredVisibleNoteDaysProvider = Provider<List<DateTime>>((ref) {
  final days =
      ref
          .watch(unfilteredVisibleNotesByDayProvider)
          .keys
          .toList(growable: false)
        ..sort();
  return List<DateTime>.unmodifiable(days);
});

@riverpod
List<DateTime> visibleNoteDays(Ref ref) {
  final days = ref.watch(visibleNotesByDayProvider).keys.toList(growable: false)
    ..sort();
  return List.unmodifiable(days);
}

@riverpod
List<NoteEntry> notesForVault(Ref ref, String vaultId) {
  return ref.watch(visibleNotesByVaultProvider)[vaultId] ?? const <NoteEntry>[];
}

@riverpod
SyncAuthState selectedSyncAuthState(Ref ref) {
  final provider = ref.watch(syncProviderControllerProvider);
  final states = ref.watch(syncAuthControllerProvider);
  return states[provider] ?? SyncAuthState.idle(provider);
}

@riverpod
VaultBucket vaultById(Ref ref, String vaultId) {
  for (final vault in ref.watch(visibleVaultsProvider)) {
    if (vault.id == vaultId) {
      return vault;
    }
  }
  for (final vault in ref.watch(vaultsProvider)) {
    if (vault.id == vaultId) {
      return vault;
    }
  }
  return VaultBucket(
    id: vaultId,
    name: '__notes__',
    description: '__unlocked_notes__',
  );
}

@riverpod
NoteEntry? noteById(Ref ref, String noteId) {
  final index = ref.watch(visibleNoteIndexByIdProvider)[noteId];
  if (index == null) {
    return null;
  }
  final notes = ref.watch(visibleNotesProvider);
  return index >= 0 && index < notes.length ? notes[index] : null;
}
