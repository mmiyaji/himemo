import 'dart:async';
import 'dart:convert';
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
import '../../../app/in_app_update_service.dart';
import '../../../app/play_integrity_service.dart';
import '../../../app/play_integrity_verifier.dart';
import '../data/home_repository.dart';
import '../domain/note_entry.dart';
import '../domain/note_tags.dart';
import '../domain/vault_models.dart';
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

enum SyncProvider { off, iCloud, googleDrive }

bool get isICloudSyncSupported =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.iOS;

enum AppLaunchSurface { onboarding, ready }

enum AppLockRelockDelay { immediate, seconds30, minutes2, minutes10 }

enum DeviceAuthAvailability { unknown, available, unavailable }

enum SyncAuthStage { idle, busy, authenticated, unsupported, error }

enum SyncTransferStage { idle, busy, success, error }

const legacyPrivateVaultId = 'private';
const customPrivateVaultPrefix = 'private_profile:';

bool isPrivateVaultId(String vaultId) {
  return vaultId == legacyPrivateVaultId ||
      vaultId.startsWith(customPrivateVaultPrefix);
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
    this.attachmentFilter = SearchAttachmentFilter.all,
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
  final SearchAttachmentFilter attachmentFilter;
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
      attachmentFilter == SearchAttachmentFilter.all &&
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
    SearchAttachmentFilter? attachmentFilter,
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
      attachmentFilter: attachmentFilter ?? this.attachmentFilter,
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

  final int nonce;
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
              nonce: DateTime.now().microsecondsSinceEpoch,
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
      nonce: DateTime.now().microsecondsSinceEpoch,
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
    this.errorMessage,
    required this.wasCancelled,
  });

  const MediaImportResult.success(NoteAttachment attachment)
    : this._(attachment: attachment, wasCancelled: false);

  const MediaImportResult.cancelled()
    : this._(wasCancelled: true, attachment: null, errorMessage: null);

  const MediaImportResult.failure(String errorMessage)
    : this._(attachment: null, errorMessage: errorMessage, wasCancelled: false);

  final NoteAttachment? attachment;
  final String? errorMessage;
  final bool wasCancelled;
}

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

class DeviceAuthState {
  const DeviceAuthState({
    required this.availability,
    required this.methods,
    this.lastError,
  });

  const DeviceAuthState.unknown()
    : availability = DeviceAuthAvailability.unknown,
      methods = const [],
      lastError = null;

  final DeviceAuthAvailability availability;
  final List<String> methods;
  final String? lastError;

  bool get isAvailable => availability == DeviceAuthAvailability.available;

  String get summary {
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
}

class AppPinLockState {
  const AppPinLockState({required this.isConfigured, this.lastError});

  const AppPinLockState.unconfigured() : isConfigured = false, lastError = null;

  final bool isConfigured;
  final String? lastError;

  String get summary {
    if (isConfigured) {
      return 'A web-only unlock PIN is configured for this browser session.';
    }
    return lastError ?? 'No unlock PIN is configured for this browser yet.';
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
    this.message,
    this.remoteStatus,
    this.localBundle,
    this.cooldownUntil,
  });

  const SyncTransferState.idle()
    : stage = SyncTransferStage.idle,
      message = null,
      remoteStatus = null,
      localBundle = null,
      cooldownUntil = null;

  final SyncTransferStage stage;
  final String? message;
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
    String? message,
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
    DateTime? cooldownUntil,
    bool clearMessage = false,
    bool clearCooldown = false,
  }) {
    return SyncTransferState(
      stage: stage ?? this.stage,
      message: clearMessage ? null : (message ?? this.message),
      remoteStatus: remoteStatus ?? this.remoteStatus,
      localBundle: localBundle ?? this.localBundle,
      cooldownUntil: clearCooldown
          ? null
          : (cooldownUntil ?? this.cooldownUntil),
    );
  }
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
        options: AuthenticationOptions(
          biometricOnly: biometricOnly,
          stickyAuth: true,
        ),
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
  Future<MediaImportResult> importAttachment(MediaImportAction action);
}

class DefaultMediaImportService implements MediaImportService {
  DefaultMediaImportService({required EncryptedAttachmentStore attachmentStore})
    : _attachmentStore = attachmentStore;

  final EncryptedAttachmentStore _attachmentStore;

  @override
  Future<MediaImportResult> importAttachment(MediaImportAction action) async {
    switch (action) {
      case MediaImportAction.takePhoto:
        return _pickPhoto(ImageSource.camera);
      case MediaImportAction.pickPhoto:
        return _pickPhoto(ImageSource.gallery);
      case MediaImportAction.recordVideo:
        return _pickVideo(ImageSource.camera);
      case MediaImportAction.pickVideo:
        return _pickVideo(ImageSource.gallery);
      case MediaImportAction.recordAudio:
        return const MediaImportResult.failure(
          'Audio recording is handled by the note editor.',
        );
      case MediaImportAction.pickAudio:
        return _pickAudio();
      case MediaImportAction.pickFile:
        return _pickFile();
      case MediaImportAction.addLocation:
        return const MediaImportResult.failure(
          'Location capture is handled by the note editor.',
        );
    }
  }

  Future<MediaImportResult> _pickPhoto(ImageSource source) async {
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
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 25 * 1024 * 1024,
      tooLargeMessage: 'Photos over 25 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    return MediaImportResult.success(
      await _buildAttachment(type: AttachmentType.photo, sourceFile: picked),
    );
  }

  Future<MediaImportResult> _pickVideo(ImageSource source) async {
    XFile? picked;
    try {
      final picker = ImagePicker();
      picked = await picker.pickVideo(source: source);
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
    final tooLarge = await _validateFileSize(
      picked,
      maxBytes: 200 * 1024 * 1024,
      tooLargeMessage: 'Videos over 200 MB are not supported yet.',
    );
    if (tooLarge != null) {
      return tooLarge;
    }
    return MediaImportResult.success(
      await _buildAttachment(type: AttachmentType.video, sourceFile: picked),
    );
  }

  Future<MediaImportResult> _pickAudio() async {
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
      result = await FilePicker.platform.pickFiles(
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
    return MediaImportResult.success(
      await _buildAttachment(
        type: AttachmentType.audio,
        sourceFile: sourceFile,
      ),
    );
  }

  Future<MediaImportResult> _pickFile() async {
    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.any,
        withData: kIsWeb,
      );
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
    return MediaImportResult.success(
      await _buildAttachment(type: AttachmentType.file, sourceFile: sourceFile),
    );
  }

  Future<NoteAttachment> _buildAttachment({
    required AttachmentType type,
    required XFile sourceFile,
  }) async {
    final durationMs = await _mediaDurationMs(
      type: type,
      sourceFile: sourceFile,
    );
    final storedPath = await _attachmentStore.storeAttachment(
      sourceFile,
      type: type,
    );
    return NoteAttachment(
      type: type,
      label: sourceFile.name.isEmpty
          ? path.basename(sourceFile.path)
          : sourceFile.name,
      filePath: storedPath,
      durationMs: durationMs,
    );
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

final syncAuthGatewayProvider = Provider<SyncAuthGateway>(
  (ref) => DefaultSyncAuthGateway(
    googleDriveAuthConfig: ref.watch(googleDriveAuthConfigProvider),
  ),
);

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
  return GoogleApisGoogleDriveSyncTransport(
    authConfig: ref.watch(googleDriveAuthConfigProvider),
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
  ref.watch(notesControllerProvider);
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
  Timer? _cooldownTimer;

  @override
  SyncTransferState build() {
    ref.onDispose(() => _cooldownTimer?.cancel());
    return const SyncTransferState.idle();
  }

  Future<void> refreshRemoteStatus() async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.idle,
        message: 'リモートの状態を確認するには、先にクラウド同期先を選択してください。',
      );
      return;
    }
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
    try {
      final remoteStatus = await runFirebaseTrace(
        'sync_refresh_remote_status',
        _fetchLatestRemoteStatus,
      );
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: remoteStatus == null
            ? 'リモートにはまだバンドルが保存されていません。'
            : '${_providerLabel(provider)} のバンドル情報を更新しました。',
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

  Future<void> uploadCurrentBundle({bool force = false}) async {
    final provider = ref.read(syncProviderControllerProvider);
    if (!_supportsRemoteTransport(provider)) {
      state = const SyncTransferState(
        stage: SyncTransferStage.error,
        message: 'アップロードするには、先にクラウド同期先を選択してください。',
      );
      return;
    }
    final assessment = assessSyncConflict(
      googleDriveSelected: true,
      queue: await ref.read(syncQueueSummaryProvider.future),
      remoteStatus: state.remoteStatus,
      bundleState: await ref.read(syncBundleStateProvider.future),
    );
    if (assessment.hasConflict && !force) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message:
            '${assessment.message} 先にリモートのバンドルをダウンロードして適用するか、上書きする場合は強制アップロードを使用してください。',
      );
      return;
    }
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
    try {
      await logFirebaseBreadcrumb('sync upload requested');
      final snapshot = await runFirebaseTrace(
        'sync_prepare_snapshot',
        () => ref
            .read(syncEngineProvider)
            .prepareSnapshot(ref.read(notesControllerProvider)),
      );
      final bundle = await runFirebaseTrace(
        'sync_write_local_bundle',
        () => ref.read(secureSyncBundleStoreProvider).writeBundle(snapshot),
      );
      final encodedPayload = await runFirebaseTrace(
        'sync_read_local_bundle_payload',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readEncryptedBundlePayload(bundle.reference),
      );
      if (encodedPayload == null || encodedPayload.isEmpty) {
        throw StateError('ローカルの同期バンドルを準備できませんでした。');
      }
      final remoteStatus = await runFirebaseTrace(
        'sync_upload_remote_bundle',
        () => _uploadRemoteBundle(
          encodedPayload: encodedPayload,
          deviceId: snapshot.deviceId,
          noteCount: bundle.noteCount,
          attachmentCount: bundle.attachmentCount,
        ),
      );
      await ref.read(notesControllerProvider.notifier).markCurrentStateSynced();
      state = SyncTransferState(
        stage: SyncTransferStage.success,
        message: '暗号化したバンドルを ${_providerLabel(provider)} にアップロードしました。',
        remoteStatus: remoteStatus,
        localBundle: bundle,
      );
      await ref.read(syncBundleStateStoreProvider).recordUpload(remoteStatus);
    } catch (error) {
      state = _failureState(
        error,
        remoteStatus: state.remoteStatus,
        localBundle: state.localBundle,
      );
    }
  }

  Future<LocalNoteArchive> exportLocalArchive({String? password}) async {
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
    try {
      await logFirebaseBreadcrumb('local zip archive export requested');
      final archive = await runFirebaseTrace(
        'notes_prepare_local_zip_archive',
        () => _buildLocalZipArchive(password: password),
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
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
    try {
      await logFirebaseBreadcrumb('local zip archive import selected');
      final decoded = _decodeLocalZipArchive(bytes, password: password);
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
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      await logFirebaseBreadcrumb('local zip archive apply selected');
      final decoded = _decodeLocalZipArchive(bytes, password: password);
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
        message: 'ダウンロードするには、先にクラウド同期先を選択してください。',
      );
      return;
    }
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
    try {
      await logFirebaseBreadcrumb('sync download latest requested');
      final remoteBundle = await runFirebaseTrace(
        'sync_download_latest_bundle',
        _downloadLatestRemoteBundle,
      );
      await _storeDownloadedBundle(
        remoteBundle,
        emptyMessage: '${_providerLabel(provider)} に利用できるリモートバンドルはありません。',
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
        message: 'ダウンロードするには、先にクラウド同期先を選択してください。',
      );
      return;
    }
    state = state.copyWith(
      stage: SyncTransferStage.busy,
      clearMessage: true,
      clearCooldown: true,
    );
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
        emptyMessage: '選択した ${_providerLabel(provider)} のバンドルをダウンロードできませんでした。',
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
      throw StateError(state.message ?? 'リモートバンドルをダウンロードできませんでした。');
    }
    return previewDownloadedBundle();
  }

  Future<void> applyDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      state = state.copyWith(
        stage: SyncTransferStage.error,
        message: '適用する前にリモートバンドルをダウンロードしてください。',
      );
      return;
    }
    state = state.copyWith(stage: SyncTransferStage.busy, clearMessage: true);
    try {
      await logFirebaseBreadcrumb('sync apply downloaded bundle');
      final decoded = await runFirebaseTrace(
        'sync_read_downloaded_bundle',
        () => ref
            .read(secureSyncBundleStoreProvider)
            .readBundleJson(localBundle.reference),
      );
      if (decoded == null) {
        throw StateError('ダウンロードしたバンドルを復号できませんでした。');
      }
      final attachmentPayloads = <String, Map<String, dynamic>>{
        for (final entry
            in (decoded['attachments'] as List<dynamic>? ?? const <dynamic>[]))
          (entry as Map)['id'] as String: Map<String, dynamic>.from(entry),
      };
      final importedChanges = <PreparedSyncNote>[];
      for (final rawEntry
          in (decoded['notes'] as List<dynamic>? ?? const <dynamic>[])) {
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
        final importedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          final filePath = attachment.filePath;
          if (filePath == null || !filePath.startsWith('sync-attachment://')) {
            importedAttachments.add(attachment);
            continue;
          }
          final attachmentId = filePath.substring('sync-attachment://'.length);
          final payload = attachmentPayloads[attachmentId];
          if (payload == null) {
            importedAttachments.add(attachment.copyWith(filePath: null));
            continue;
          }
          final storedReference = await ref
              .read(encryptedAttachmentStoreProvider)
              .storeEncryptedPayload(
                encodedPayload: payload['encryptedPayload'] as String,
                type: AttachmentType.values.firstWhere(
                  (value) => value.name == payload['type'],
                  orElse: () => attachment.type,
                ),
                fileNameHint: payload['label'] as String? ?? attachment.label,
                vaultId: note.vaultId,
              );
          importedAttachments.add(
            attachment.copyWith(filePath: storedReference),
          );
        }
        importedChanges.add(
          PreparedSyncNote(
            action: action,
            note: note.copyWith(attachments: importedAttachments),
          ),
        );
      }
      await ref
          .read(notesControllerProvider.notifier)
          .mergeFromSync(importedChanges);
      await ref
          .read(syncBundleStateStoreProvider)
          .recordApply(state.remoteStatus);
      state = state.copyWith(
        stage: SyncTransferStage.success,
        message: 'ダウンロードしたバンドルをローカルのノートに反映しました。',
      );
    } catch (error) {
      state = state.copyWith(stage: SyncTransferStage.error, message: '$error');
    }
  }

  Future<SyncBundlePreview> previewDownloadedBundle() async {
    final localBundle = state.localBundle;
    if (localBundle == null) {
      throw StateError('確認する前にリモートバンドルをダウンロードしてください。');
    }
    final decoded = await ref
        .read(secureSyncBundleStoreProvider)
        .readBundleJson(localBundle.reference);
    if (decoded == null) {
      throw StateError('ダウンロードしたバンドルを復号できませんでした。');
    }
    return buildSyncBundlePreview(
      decodedBundle: decoded,
      currentNotes: ref.read(notesControllerProvider),
    );
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
      message:
          '${_providerLabel(ref.read(syncProviderControllerProvider))} のリモートバンドルをローカルの保護ストレージに保存しました。',
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

  String _providerLabel(SyncProvider provider) {
    return switch (provider) {
      SyncProvider.iCloud => 'iCloud',
      SyncProvider.googleDrive => 'Google Drive',
      SyncProvider.off => 'remote storage',
    };
  }

  Future<LocalNoteArchive> _buildLocalZipArchive({String? password}) async {
    final exportedAt = DateTime.now();
    final notes = ref
        .read(notesControllerProvider)
        .where((entry) => entry.deletedAt == null)
        .toList(growable: false);
    final archive = Archive();
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
        archive.addFile(ArchiveFile.bytes(archivePath, bytes));
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

    archive.addFile(
      ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'format': 'org.ruhenheim.himemo.notes.zip',
          'version': 1,
          'exportedAt': exportedAt.toIso8601String(),
          'encryption': password == null || password.isEmpty
              ? 'none'
              : 'zip-aes-256',
          'noteCount': exportedNotes.length,
          'attachmentCount': attachmentCount,
          'contents': ['notes.json', 'attachments/'],
        }),
      ),
    );
    archive.addFile(
      ArchiveFile.string(
        'notes.json',
        jsonEncode({'schemaVersion': 1, 'notes': exportedNotes}),
      ),
    );

    final encoded = ZipEncoder(
      password: password == null || password.isEmpty ? null : password,
    ).encode(archive);
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

  _DecodedLocalZipArchive _decodeLocalZipArchive(
    List<int> bytes, {
    String? password,
  }) {
    final archive = ZipDecoder().decodeBytes(bytes, password: password);
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
      SyncProvider.googleDrive =>
        ref.read(googleDriveSyncTransportProvider).fetchLatestBundleStatus(),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<List<RemoteSyncBundleStatus>> _listRemoteHistory() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).listBundleHistory(),
      SyncProvider.googleDrive =>
        ref.read(googleDriveSyncTransportProvider).listBundleHistory(),
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
      SyncProvider.googleDrive =>
        ref
            .read(googleDriveSyncTransportProvider)
            .uploadBundle(
              encodedPayload: encodedPayload,
              deviceId: deviceId,
              noteCount: noteCount,
              attachmentCount: attachmentCount,
            ),
      SyncProvider.off => Future.error(
        StateError('Remote sync is not enabled.'),
      ),
    };
  }

  Future<DownloadedRemoteSyncBundle?> _downloadLatestRemoteBundle() {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadLatestBundle(),
      SyncProvider.googleDrive =>
        ref.read(googleDriveSyncTransportProvider).downloadLatestBundle(),
      SyncProvider.off => Future.value(null),
    };
  }

  Future<DownloadedRemoteSyncBundle?> _downloadRemoteBundleById(String id) {
    final provider = ref.read(syncProviderControllerProvider);
    return switch (provider) {
      SyncProvider.iCloud =>
        ref.read(iCloudSyncTransportProvider).downloadBundleByRecordName(id),
      SyncProvider.googleDrive =>
        ref.read(googleDriveSyncTransportProvider).downloadBundleByFileId(id),
      SyncProvider.off => Future.value(null),
    };
  }

  SyncTransferState _failureState(
    Object error, {
    RemoteSyncBundleStatus? remoteStatus,
    StoredSyncBundle? localBundle,
  }) {
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

  void unlock() => state = true;

  void lock() => state = false;
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
  @override
  DeviceAuthState build() {
    unawaited(refresh());
    return const DeviceAuthState.unknown();
  }

  Future<void> refresh() async {
    state = await ref.read(deviceAuthGatewayProvider).checkAvailability();
  }

  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    final authenticated = await ref
        .read(deviceAuthGatewayProvider)
        .authenticate(reason: reason, biometricOnly: biometricOnly);
    await refresh();
    if (authenticated) {
      ref.read(appSessionUnlockControllerProvider.notifier).unlock();
    }
    return authenticated;
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

@Riverpod(keepAlive: true)
class WidgetQuickCaptureRequestController
    extends _$WidgetQuickCaptureRequestController {
  @override
  QuickCaptureRequest? build() => null;

  void open(QuickCaptureRequest request) => state = request;

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
    state = provider;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, provider.name);
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
    state = identityId;
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
      attachmentFilter: value
          ? SearchAttachmentFilter.any
          : SearchAttachmentFilter.all,
    );
  }

  void setAttachmentFilter(SearchAttachmentFilter value) {
    state = state.copyWith(withMediaOnly: false, attachmentFilter: value);
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
class LastNoteEditorSettingsController
    extends _$LastNoteEditorSettingsController {
  static const _modeKey = 'notes.last_editor_mode';
  static const _vaultKey = 'notes.last_vault_id';
  static const _captureLocationKey = 'notes.last_capture_location';
  bool _restored = false;

  @override
  LastNoteEditorSettings build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return const LastNoteEditorSettings();
  }

  Future<void> remember({
    required NoteEditorMode mode,
    required String vaultId,
    bool? captureLocation,
  }) async {
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
    state = LastNoteEditorSettings(
      mode: modeName == null || modeName.isEmpty
          ? NoteEditorMode.rich
          : NoteEditorMode.values.byName(modeName),
      vaultId: vaultId == null || vaultId.isEmpty ? 'everyday' : vaultId,
      captureLocation: captureLocation,
    );
  }
}

@Riverpod(keepAlive: true)
class NotesController extends _$NotesController {
  static const _deletedSeedNoteIdsKey = 'notes.deleted_seed_note_ids.v1';
  static const _storeAssetsSeedDemoNotesKey = 'store_assets.seed_demo_notes.v1';

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
    await runFirebaseTrace(
      'notes_upsert',
      () async {
        final next = [...state];
        final index = next.indexWhere((entry) => entry.id == note.id);
        final existing = index == -1 ? null : next[index];
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
      },
      attributes: {
        'editor_mode': note.editorMode.name,
        'vault_id': note.vaultId,
        'has_media': note.attachments.isNotEmpty ? 'true' : 'false',
      },
    );
  }

  Future<void> delete(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
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
        return;
      }
    });
  }

  Future<void> archive(String noteId) async {
    await _setArchiveState(noteId, archived: true);
  }

  Future<void> unarchive(String noteId) async {
    await _setArchiveState(noteId, archived: false);
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

  Future<int> createPerformanceTestNotes({required int count}) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    if (count <= 0) {
      return 0;
    }
    final now = DateTime.now();
    final existingIds = state.map((note) => note.id).toSet();
    final notesToAdd = <NoteEntry>[];
    for (var index = 0; index < count; index++) {
      final id = 'perf-${index.toString().padLeft(4, '0')}';
      if (existingIds.contains(id)) {
        continue;
      }
      final createdAt = now.subtract(Duration(minutes: index * 11));
      final title = 'Performance note ${index + 1}';
      final body =
          'Performance test memo ${index + 1}\n'
          'This generated note is used to measure list, search, calendar, and detail switching performance.';
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
          blocks: [NoteBlock(type: NoteBlockType.paragraph, text: body)],
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
    if (notesToAdd.isEmpty) {
      return 0;
    }
    final next = [...state, ...notesToAdd];
    _sort(next);
    state = next;
    await _persist();
    return notesToAdd.length;
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
      for (final note in removedNotes) ...note.attachments,
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
    await _deleteAttachments([for (final note in state) ...note.attachments]);
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
    ref.invalidate(storageUsageSummaryProvider);
    return removedCount;
  }

  Future<int> cleanupUnreferencedAttachments() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final retainedAttachmentReferences = <String>{
      for (final note in state)
        if (note.deletedAt == null) ...[
          for (final attachment in note.attachments)
            if (attachment.filePath != null && attachment.filePath!.isNotEmpty)
              attachment.filePath!,
          for (final block in note.blocks)
            if (block.attachment?.filePath != null &&
                block.attachment!.filePath!.isNotEmpty)
              block.attachment!.filePath!,
        ],
    };
    return ref
        .read(encryptedAttachmentStoreProvider)
        .deleteUnreferencedAttachments(retainedAttachmentReferences);
  }

  Future<void> replaceFromSync(List<NoteEntry> notes) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final incomingPaths = notes
        .expand((note) => note.attachments)
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    final removedAttachments = [
      for (final existing in state)
        for (final attachment in existing.attachments)
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
        removedAttachments.addAll(current.attachments);
      }
    }

    final stillRetained = <String>{
      for (final note in next)
        for (final attachment in note.attachments)
          if (attachment.filePath != null) attachment.filePath!,
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

  Future<void> markCurrentStateSynced() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    var changed = false;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (note.syncState == NoteSyncState.pendingUpload ||
          note.syncState == NoteSyncState.pendingDelete) {
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
      attachments.add(
        NoteAttachment(
          type: attachmentType,
          label: sourceFile.name,
          filePath: storedPath,
          durationMs: durationMs,
        ),
      );
    }
    await upsert(
      NoteEntry(
        id: now.microsecondsSinceEpoch.toString(),
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

  Future<void> _cleanupRemovedAttachments(
    NoteEntry? previous,
    NoteEntry next,
  ) async {
    if (previous == null) {
      return;
    }
    final retained = next.attachments
        .map((attachment) => attachment.filePath)
        .whereType<String>()
        .toSet();
    final removed = previous.attachments
        .where((attachment) {
          final filePath = attachment.filePath;
          return filePath != null && !retained.contains(filePath);
        })
        .toList(growable: false);
    await _deleteAttachments(removed);
  }

  Future<void> _deleteAttachments(List<NoteAttachment> attachments) async {
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    for (final attachment in attachments) {
      final filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
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
    });
    return sha256.convert(utf8.encode(payload)).toString();
  }

  bool _hasUnuploadedLocalChange(NoteEntry note) {
    return note.syncState == NoteSyncState.pendingUpload ||
        note.syncState == NoteSyncState.pendingDelete ||
        note.syncState == NoteSyncState.conflict;
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
      if (left.isPinned != right.isPinned) {
        return right.isPinned ? 1 : -1;
      }
      final leftPrivate = isPrivateVaultId(left.vaultId);
      final rightPrivate = isPrivateVaultId(right.vaultId);
      if (leftPrivate != rightPrivate) {
        return leftPrivate ? -1 : 1;
      }
      final dateOrder = right.createdAt.compareTo(left.createdAt);
      if (dateOrder != 0) {
        return dateOrder;
      }
      return (right.updatedAt ?? right.createdAt).compareTo(
        left.updatedAt ?? left.createdAt,
      );
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

  void unlock(String vaultId) => state = vaultId;

  void lock() {
    final vaultId = state;
    if (vaultId != null) {
      ref.read(profileDataKeyServiceProvider).lockProfile(vaultId);
    }
    state = null;
  }
}

final adminModeSessionControllerProvider =
    NotifierProvider<AdminModeSessionController, bool>(
      AdminModeSessionController.new,
    );

class AdminModeSessionController extends Notifier<bool> {
  @override
  bool build() => false;

  void unlock() => state = true;

  void lock() => state = false;
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
  return [if (unlockedVaultId != null) unlockedVaultId];
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
  final visibleIds = ref
      .watch(visibleVaultsProvider)
      .map((vault) => vault.id)
      .toSet();
  final query = ref.watch(searchQueryProvider).trim().toLowerCase();
  final filters = ref.watch(searchFiltersControllerProvider);
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
    if (filterYear != null && note.createdAt.year != filterYear) {
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
    if (!_noteMatchesAttachmentFilter(note, filters.attachmentFilter)) {
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
  return List.unmodifiable(results);
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
  SearchAttachmentFilter filter,
) {
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
}

@riverpod
List<int> visibleNoteYears(Ref ref) {
  final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
  final notes = ref.watch(visibleNotesProvider);
  final years = <int>{};
  for (final note in notes) {
    years.add(note.createdAt.year);
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
  final grouped = <DateTime, List<NoteEntry>>{};
  for (final note in notes) {
    final day = DateTime(
      note.createdAt.year,
      note.createdAt.month,
      note.createdAt.day,
    );
    (grouped[day] ??= <NoteEntry>[]).add(note);
  }
  final result = Map<DateTime, List<NoteEntry>>.unmodifiable({
    for (final entry in grouped.entries)
      entry.key: List<NoteEntry>.unmodifiable(entry.value),
  });
  final elapsed = stopwatch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugHomePerf(
      'visible notes by day source=${notes.length} days=${result.length} elapsed=${elapsed / 1000}ms',
    );
  }
  return result;
}

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
