import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:cryptography/cryptography.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
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
import '../../security/data/encrypted_attachment_store.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/master_key_service.dart';
import '../../security/data/app_pin_lock_store.dart';
export '../../security/data/app_pin_lock_store.dart';
export '../../security/data/secret_verifier_store.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../sync/data/sync_v2_attachment_store.dart';
import '../../sync/data/sync_v2_note_store.dart';
import '../../sync/presentation/sync_v2_note_store_provider.dart';
import '../../sync/presentation/sync_v2_workspace.dart';
import 'media_duration_stub.dart' if (dart.library.io) 'media_duration_io.dart';

part 'home_providers.g.dart';
part '../../security/presentation/security_providers.dart';

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

enum AppLaunchSurface { onboarding, ready }

enum AppTutorialCourse {
  basics,
  mainScreen,
  writing,
  find,
  attachments,
  privateMemo,
  review,
  privacy,
  sync,
  syncTroubleshooting,
  trashRecovery,
  organize,
  maintenance,
}

enum AppTutorialCourseLevel { beginner, intermediate, advanced }

enum AppTutorialStep {
  privateProfile,
  addNote,
  search,
  filters,
  notesList,
  attachments,
  privateMemo,
  syncTroubleshooting,
  trashRecovery,
  syncStatus,
  navigation,
  settings,
  tags,
  trash,
  calendarInsights,
}

class AppTutorialState {
  const AppTutorialState({
    required this.course,
    required this.steps,
    required this.index,
  });

  final AppTutorialCourse course;
  final List<AppTutorialStep> steps;
  final int index;

  AppTutorialStep get step => steps[index];
  int get stepNumber => index + 1;
  int get stepCount => steps.length;
}

enum AppLockRelockDelay { immediate, seconds30, minutes2, minutes10 }

enum DeviceAuthAvailability { unknown, available, unavailable }

const customPrivateVaultPrefix = 'private_profile:';

bool isPrivateVaultId(String vaultId) {
  return vaultId.startsWith(customPrivateVaultPrefix);
}

bool isGeneratedSampleNote(NoteEntry note) {
  return note.deviceId == 'seeded-device' ||
      note.id.startsWith('seed-') ||
      note.deviceId == 'performance-seed' ||
      note.id.startsWith('perf-') ||
      (note.contentHash?.startsWith('performance-seed-') ?? false);
}

class PrivateMemoProfile {
  const PrivateMemoProfile({required this.id, required this.name});
  final String id;
  final String name;
  String get vaultId => '$customPrivateVaultPrefix$id';
}

class UnlockProfileResult {
  const UnlockProfileResult({
    required this.vaultId,
    required this.label,
    this.additionalVaultIds = const [],
  });

  final String vaultId;
  final String label;
  final List<String> additionalVaultIds;
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

  String get releaseKey => '$version+$buildNumber';
}

enum ReleaseNoteItemType { feature, improvement, fix, security }

class ReleaseNoteItem {
  const ReleaseNoteItem({
    required this.type,
    required this.title,
    required this.body,
  });

  final ReleaseNoteItemType type;
  final Map<String, String> title;
  final Map<String, String> body;

  String localizedTitle(Locale locale) => _localizedReleaseText(title, locale);

  String localizedBody(Locale locale) => _localizedReleaseText(body, locale);
}

class ReleaseNote {
  const ReleaseNote({
    required this.version,
    required this.date,
    required this.importance,
    required this.title,
    required this.summary,
    required this.items,
  });

  final String version;
  final DateTime? date;
  final String importance;
  final Map<String, String> title;
  final Map<String, String> summary;
  final List<ReleaseNoteItem> items;

  String localizedTitle(Locale locale) => _localizedReleaseText(title, locale);

  String localizedSummary(Locale locale) =>
      _localizedReleaseText(summary, locale);
}

String _localizedReleaseText(Map<String, String> values, Locale locale) {
  return values[locale.languageCode] ??
      values['en'] ??
      (values.values.isEmpty ? null : values.values.first) ??
      '';
}

ReleaseNote? releaseNoteFromJson(Map<String, dynamic> json) {
  final items = <ReleaseNoteItem>[];
  for (final rawItem in json['items'] as List<dynamic>? ?? const <dynamic>[]) {
    final item = Map<String, dynamic>.from(rawItem as Map);
    final typeName = '${item['type'] ?? 'improvement'}';
    items.add(
      ReleaseNoteItem(
        type: ReleaseNoteItemType.values.firstWhere(
          (type) => type.name == typeName,
          orElse: () => ReleaseNoteItemType.improvement,
        ),
        title: _localizedMapFromJson(item['title']),
        body: _localizedMapFromJson(item['body']),
      ),
    );
  }
  final version = '${json['version'] ?? ''}'.trim();
  if (version.isEmpty || items.isEmpty) {
    return null;
  }
  return ReleaseNote(
    version: version,
    date: DateTime.tryParse('${json['date'] ?? ''}'),
    importance: '${json['importance'] ?? 'normal'}',
    title: _localizedMapFromJson(json['title']),
    summary: _localizedMapFromJson(json['summary']),
    items: List.unmodifiable(items),
  );
}

Map<String, String> _localizedMapFromJson(Object? value) {
  if (value is! Map) {
    return const <String, String>{};
  }
  return {
    for (final entry in value.entries) '${entry.key}': '${entry.value}'.trim(),
  }..removeWhere((_, text) => text.isEmpty);
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
    this.shareId,
    this.initialText = '',
    this.files = const <QuickCaptureFile>[],
    this.rejectedFiles = const <QuickCaptureRejectedFile>[],
  });

  final String nonce;
  final QuickCaptureSource source;
  final String? shareId;
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
    unawaited(openNextPending());
  }

  Future<void> acknowledgeSharedCapture(String id) =>
      _channel.invokeMethod<void>('acknowledgeSharedCapture', id);

  Future<void> openNextPending() async {
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
    } catch (_) {
      // The native widget channel may be unavailable on unsupported launches.
    }
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
    } catch (_) {
      logDiagnostic('quick_capture', 'imported file cleanup failed');
    }
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
      shareId: arguments['shareId'] as String?,
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

abstract class MediaImportService {
  Future<MediaImportResult> importAttachment(
    MediaImportAction action, {
    VoidCallback? onProcessingStarted,
  });
}

class DefaultMediaImportService implements MediaImportService {
  DefaultMediaImportService({required this._attachmentStore});

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
    List<PlatformFile> result;
    try {
      result = await FilePicker.pickFiles(type: pickerType);
    } on MissingPluginException {
      return MediaImportResult.failure(importNotConfiguredMessage);
    } on PlatformException catch (error) {
      return MediaImportResult.failure(error.message ?? importFailedPrefix);
    } catch (error) {
      return MediaImportResult.failure('$importFailedPrefix ($error)');
    }
    if (result.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final attachments = <NoteAttachment>[];
    final deferredPreviews = <String, Future<String?>>{};
    for (final file in result) {
      final sourceFile = file.xFile;
      final bytes = kIsWeb ? await file.readAsBytes() : null;
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
        await _deleteTransientPickedMediaSource(
          sourceFile,
          reason: 'too_large',
        );
        return tooLarge;
      }
      final built = await _buildAttachment(
        type: type,
        sourceFile: sourceFile,
        deleteSourceAfterImport: true,
      );
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
    PlatformFile? file;
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
      file = await FilePicker.pickFile(
        type: defaultTargetPlatform == TargetPlatform.iOS
            ? FileType.custom
            : FileType.audio,
        allowedExtensions: defaultTargetPlatform == TargetPlatform.iOS
            ? audioExtensions
            : null,
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
    if (file == null) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final bytes = kIsWeb ? await file.readAsBytes() : null;
    if (bytes != null && bytes.length > 50 * 1024 * 1024) {
      return const MediaImportResult.failure(
        'Audio files over 50 MB are not supported yet.',
      );
    }
    final sourceFile = file.xFile;
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
    List<PlatformFile> result;
    try {
      result = await FilePicker.pickFile(type: FileType.any)
          .then((file) => file == null ? <PlatformFile>[] : [file]);
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
    if (result.isEmpty) {
      return const MediaImportResult.cancelled();
    }

    onProcessingStarted?.call();
    final file = result.single;
    final bytes = kIsWeb ? await file.readAsBytes() : null;
    if (bytes != null && bytes.length > 100 * 1024 * 1024) {
      return const MediaImportResult.failure(
        'Files over 100 MB are not supported yet.',
      );
    }
    final sourceFile = file.xFile;
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
    bool deleteSourceAfterImport = false,
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
        final preview = _videoPreviewBytesBase64ForSourceFile(sourceFile);
        deferredPreview = deleteSourceAfterImport
            ? preview.whenComplete(() async {
                await _deleteTransientPickedMediaSource(
                  sourceFile,
                  reason: 'deferred_preview_completed',
                );
              })
            : preview;
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
    if (deleteSourceAfterImport && deferredPreview == null) {
      await _deleteTransientPickedMediaSource(
        sourceFile,
        reason: 'import_completed',
      );
    }
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

final mediaImportServiceProvider = Provider<MediaImportService>(
  (ref) => DefaultMediaImportService(
    attachmentStore: ref.watch(encryptedAttachmentStoreProvider),
  ),
);

class StorageUsageSummary {
  const StorageUsageSummary({
    required this.notePayloadBytes,
    required this.attachmentPayloadBytes,
    required this.attachmentCacheBytes,
  });

  final int notePayloadBytes;
  final int attachmentPayloadBytes;
  final int attachmentCacheBytes;

  int get persistentBytes => notePayloadBytes + attachmentPayloadBytes;
  int get totalBytes => persistentBytes;
  int get onDeviceBytes => persistentBytes + attachmentCacheBytes;
  bool get hasCache => attachmentCacheBytes > 0;
}

class StorageDiagnosticsSummary {
  const StorageDiagnosticsSummary({
    required this.sqliteBytes,
    required this.syncExportBytes,
    required this.appContainerBytes,
    required this.documentsBytes,
    required this.documentsInboxBytes,
    required this.documentsRootFileBytes,
    required this.documentsTopEntries,
    required this.libraryBytes,
    required this.appSupportBytes,
    required this.temporaryDirectoryBytes,
    required this.cacheDirectoryBytes,
    required this.libraryOtherBytes,
    required this.appContainerOtherBytes,
    required this.appGroupBytes,
    required this.appGroupSharedImportsBytes,
    required this.appGroupPendingQuickCaptureBytes,
    required this.sharedPreferencesApproxBytes,
  });

  final int sqliteBytes;
  final int syncExportBytes;
  final int appContainerBytes;
  final int documentsBytes;
  final int documentsInboxBytes;
  final int documentsRootFileBytes;
  final List<Map<String, Object?>> documentsTopEntries;
  final int libraryBytes;
  final int appSupportBytes;
  final int temporaryDirectoryBytes;
  final int cacheDirectoryBytes;
  final int libraryOtherBytes;
  final int appContainerOtherBytes;
  final int appGroupBytes;
  final int appGroupSharedImportsBytes;
  final int appGroupPendingQuickCaptureBytes;
  final int sharedPreferencesApproxBytes;

  static const empty = StorageDiagnosticsSummary(
    sqliteBytes: 0,
    syncExportBytes: 0,
    appContainerBytes: 0,
    documentsBytes: 0,
    documentsInboxBytes: 0,
    documentsRootFileBytes: 0,
    documentsTopEntries: <Map<String, Object?>>[],
    libraryBytes: 0,
    appSupportBytes: 0,
    temporaryDirectoryBytes: 0,
    cacheDirectoryBytes: 0,
    libraryOtherBytes: 0,
    appContainerOtherBytes: 0,
    appGroupBytes: 0,
    appGroupSharedImportsBytes: 0,
    appGroupPendingQuickCaptureBytes: 0,
    sharedPreferencesApproxBytes: 0,
  );

  int get measuredBytes {
    final visibleContainerBytes =
        documentsBytes + libraryBytes + temporaryDirectoryBytes;
    final containerBytes = math.max(appContainerBytes, visibleContainerBytes);
    return containerBytes + appGroupBytes;
  }

  Map<String, Object?> toDiagnosticData() {
    return {
      'measuredBytes': measuredBytes,
      'appContainerBytes': appContainerBytes,
      'documentsBytes': documentsBytes,
      'documentsInboxBytes': documentsInboxBytes,
      'documentsRootFileBytes': documentsRootFileBytes,
      'documentsTopEntries': documentsTopEntries,
      'libraryBytes': libraryBytes,
      'appSupportBytes': appSupportBytes,
      'sqliteBytes': sqliteBytes,
      'syncExportBytes': syncExportBytes,
      'temporaryDirectoryBytes': temporaryDirectoryBytes,
      'cacheDirectoryBytes': cacheDirectoryBytes,
      'libraryOtherBytes': libraryOtherBytes,
      'appContainerOtherBytes': appContainerOtherBytes,
      'appGroupBytes': appGroupBytes,
      'appGroupSharedImportsBytes': appGroupSharedImportsBytes,
      'appGroupPendingQuickCaptureBytes': appGroupPendingQuickCaptureBytes,
      'sharedPreferencesApproxBytes': sharedPreferencesApproxBytes,
    };
  }
}

class _NativeStorageDiagnostics {
  const _NativeStorageDiagnostics({
    required this.appGroupBytes,
    required this.appGroupSharedImportsBytes,
    required this.appGroupPendingQuickCaptureBytes,
  });

  final int appGroupBytes;
  final int appGroupSharedImportsBytes;
  final int appGroupPendingQuickCaptureBytes;

  static const empty = _NativeStorageDiagnostics(
    appGroupBytes: 0,
    appGroupSharedImportsBytes: 0,
    appGroupPendingQuickCaptureBytes: 0,
  );
}

class _DirectoryEntryDiagnostics {
  const _DirectoryEntryDiagnostics({
    required this.name,
    required this.path,
    required this.isDirectory,
    required this.bytes,
  });

  final String name;
  final String path;
  final bool isDirectory;
  final int bytes;

  Map<String, Object?> toData() {
    return {
      'name': name,
      'path': path,
      'isDirectory': isDirectory,
      'bytes': bytes,
    };
  }
}

const _storageDiagnosticsChannel = MethodChannel('org.ruhenheim.himemo/widget');
const _iosPickedImagesDirectoryName = 'picked_images';

final storageUsageSummaryProvider = FutureProvider<StorageUsageSummary>((
  ref,
) async {
  final noteStore = ref.watch(noteStoreProvider);
  final attachmentStore = ref.watch(encryptedAttachmentStoreProvider);
  final notePayloadBytes = await noteStore.storagePayloadSizeBytes();
  final attachmentPayloadBytes = await attachmentStore
      .storagePayloadSizeBytes();
  final attachmentCacheBytes = await attachmentStore
      .materializedCacheSizeBytes();
  final pickedImagePickerCopyBytes = await _pickedImagePickerCopiesSizeBytes();
  return StorageUsageSummary(
    notePayloadBytes: notePayloadBytes,
    attachmentPayloadBytes: attachmentPayloadBytes,
    attachmentCacheBytes: attachmentCacheBytes + pickedImagePickerCopyBytes,
  );
});

final storageDiagnosticsSummaryProvider =
    FutureProvider<StorageDiagnosticsSummary>((ref) async {
      if (kIsWeb) {
        return StorageDiagnosticsSummary.empty;
      }
      try {
        final appSupportDirectory = await getApplicationSupportDirectory();
        final documentsDirectory = await getApplicationDocumentsDirectory();
        final temporaryDirectory = await getTemporaryDirectory();
        final cacheDirectory = await _applicationCacheDirectoryOrFallback(
          appSupportDirectory,
        );
        final libraryDirectory = appSupportDirectory.parent;
        final appContainerDirectory =
            defaultTargetPlatform == TargetPlatform.iOS
            ? libraryDirectory.parent
            : appSupportDirectory.parent;
        final sqliteBytes = await _sumFilesMatching(
          appSupportDirectory,
          (entity) =>
              path.basename(entity.path).startsWith('himemo_notes.sqlite'),
          label: 'sqlite',
        );
        final syncExportBytes = await _directorySizeBytes(
          Directory(path.join(appSupportDirectory.path, 'sync_exports')),
          label: 'sync_exports',
        );
        final appSupportBytes = await _directorySizeBytes(
          appSupportDirectory,
          label: 'app_support',
        );
        final temporaryDirectoryBytes = await _directorySizeBytes(
          temporaryDirectory,
          label: 'temporary',
        );
        final cacheDirectoryBytes = await _directorySizeBytes(
          cacheDirectory,
          label: 'cache',
        );
        final documentsBytes = await _directorySizeBytes(
          documentsDirectory,
          label: 'documents',
        );
        final documentsEntries = await _directoryEntryDiagnostics(
          documentsDirectory,
          label: 'documents',
        );
        final documentsInboxBytes = documentsEntries
            .where((entry) => entry.name == 'Inbox')
            .fold<int>(0, (sum, entry) => sum + entry.bytes);
        final documentsRootFileBytes = documentsEntries
            .where((entry) => !entry.isDirectory)
            .fold<int>(0, (sum, entry) => sum + entry.bytes);
        final libraryBytes = defaultTargetPlatform == TargetPlatform.iOS
            ? await _directorySizeBytes(libraryDirectory, label: 'library')
            : 0;
        final appContainerBytes = await _directorySizeBytes(
          appContainerDirectory,
          label: 'app_container',
        );
        final nativeDiagnostics = await _nativeStorageDiagnostics();
        final sharedPreferencesApproxBytes =
            await _sharedPreferencesApproxBytes();
        final libraryOtherBytes =
            libraryBytes - appSupportBytes - cacheDirectoryBytes;
        final appContainerOtherBytes =
            appContainerBytes -
            documentsBytes -
            libraryBytes -
            temporaryDirectoryBytes;
        final summary = StorageDiagnosticsSummary(
          sqliteBytes: sqliteBytes,
          syncExportBytes: syncExportBytes,
          appContainerBytes: appContainerBytes,
          documentsBytes: documentsBytes,
          documentsInboxBytes: documentsInboxBytes,
          documentsRootFileBytes: documentsRootFileBytes,
          documentsTopEntries: [
            for (final entry in documentsEntries.take(8)) entry.toData(),
          ],
          libraryBytes: libraryBytes,
          appSupportBytes: appSupportBytes,
          temporaryDirectoryBytes: temporaryDirectoryBytes,
          cacheDirectoryBytes: cacheDirectoryBytes,
          libraryOtherBytes: math.max(0, libraryOtherBytes),
          appContainerOtherBytes: math.max(0, appContainerOtherBytes),
          appGroupBytes: nativeDiagnostics.appGroupBytes,
          appGroupSharedImportsBytes:
              nativeDiagnostics.appGroupSharedImportsBytes,
          appGroupPendingQuickCaptureBytes:
              nativeDiagnostics.appGroupPendingQuickCaptureBytes,
          sharedPreferencesApproxBytes: sharedPreferencesApproxBytes,
        );
        unawaited(
          DiagnosticLogService.instance.record(
            'storage',
            'storage diagnostics calculated',
            data: summary.toDiagnosticData(),
            force: true,
          ),
        );
        return summary;
      } catch (error) {
        unawaited(
          DiagnosticLogService.instance.record(
            'storage',
            'storage diagnostics failed',
            data: {'error': '$error'},
            force: true,
          ),
        );
        return StorageDiagnosticsSummary.empty;
      }
    });

final storageCacheClearInProgressProvider =
    NotifierProvider<StorageCacheClearInProgressController, bool>(
      StorageCacheClearInProgressController.new,
    );

class StorageCacheClearInProgressController extends Notifier<bool> {
  @override
  bool build() => false;

  void setClearing(bool value) {
    state = value;
  }
}

Future<Directory> _applicationCacheDirectoryOrFallback(
  Directory appSupportDirectory,
) async {
  try {
    return await getApplicationCacheDirectory();
  } catch (error) {
    logDiagnostic(
      'storage',
      'application cache directory unavailable',
      data: {'error': '$error'},
    );
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      return Directory(path.join(appSupportDirectory.parent.path, 'Caches'));
    }
    return Directory(path.join(appSupportDirectory.parent.path, 'cache'));
  }
}

Future<Directory?> _pickedImagePickerCopiesDirectory() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return null;
  }
  final documentsDirectory = await getApplicationDocumentsDirectory();
  return Directory(
    path.join(documentsDirectory.path, _iosPickedImagesDirectoryName),
  );
}

Future<int> _pickedImagePickerCopiesSizeBytes() async {
  final directory = await _pickedImagePickerCopiesDirectory();
  if (directory == null || !await directory.exists()) {
    return 0;
  }
  return _directorySizeBytes(directory, label: 'picked_images');
}

Future<int> _clearPickedImagePickerCopies() async {
  final directory = await _pickedImagePickerCopiesDirectory();
  if (directory == null || !await directory.exists()) {
    return 0;
  }
  final deletedBytes = await _directorySizeBytes(
    directory,
    label: 'picked_images_clear',
  );
  try {
    await directory.delete(recursive: true);
    logDiagnostic(
      'storage',
      'picked image picker copies cleared',
      data: {'bytes': deletedBytes, 'path': directory.path},
    );
    return deletedBytes;
  } catch (error) {
    logDiagnostic(
      'storage',
      'picked image picker copies clear failed',
      data: {'bytes': deletedBytes, 'path': directory.path, 'error': '$error'},
    );
    return 0;
  }
}

Future<int> _deleteTransientPickedMediaSource(
  XFile sourceFile, {
  required String reason,
}) async {
  if (sourceFile.path.isEmpty) {
    return 0;
  }
  final directory = await _pickedImagePickerCopiesDirectory();
  if (directory == null) {
    return 0;
  }
  final directoryPath = path.normalize(directory.path);
  final sourcePath = path.normalize(sourceFile.path);
  final relativePath = path.relative(sourcePath, from: directoryPath);
  if (relativePath == '.' ||
      relativePath.startsWith('..${path.separator}') ||
      path.isAbsolute(relativePath)) {
    return 0;
  }
  final file = File(sourcePath);
  try {
    if (!await file.exists()) {
      return 0;
    }
    final bytes = await file.length();
    await file.delete();
    logDiagnostic(
      'attachment',
      'transient picked media source deleted',
      data: {'reason': reason, 'bytes': bytes, 'path': sourcePath},
    );
    return bytes;
  } catch (error) {
    logDiagnostic(
      'attachment',
      'transient picked media source delete failed',
      data: {'reason': reason, 'path': sourcePath, 'error': '$error'},
    );
    return 0;
  }
}

Future<int> _directorySizeBytes(Directory directory, {String? label}) async {
  try {
    if (!await directory.exists()) {
      return 0;
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'directory existence check failed',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
    return 0;
  }
  return _directoryTreeSizeBytes(directory, label: label);
}

Future<List<_DirectoryEntryDiagnostics>> _directoryEntryDiagnostics(
  Directory directory, {
  String? label,
}) async {
  try {
    if (!await directory.exists()) {
      return const <_DirectoryEntryDiagnostics>[];
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'directory entry diagnostics existence check failed',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
    return const <_DirectoryEntryDiagnostics>[];
  }
  final entries = <_DirectoryEntryDiagnostics>[];
  try {
    await for (final entity in directory.list(followLinks: false)) {
      try {
        final isDirectory = entity is Directory;
        final bytes = entity is Directory
            ? await _directoryTreeSizeBytes(entity, label: label)
            : entity is File
            ? await entity.length()
            : 0;
        entries.add(
          _DirectoryEntryDiagnostics(
            name: path.basename(entity.path),
            path: entity.path,
            isDirectory: isDirectory,
            bytes: bytes,
          ),
        );
      } catch (error) {
        logDiagnostic(
          'storage',
          'directory entry diagnostics skipped',
          data: {'label': label, 'path': entity.path, 'error': '$error'},
        );
      }
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'directory entry diagnostics listing skipped',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
  }
  entries.sort((a, b) => b.bytes.compareTo(a.bytes));
  return entries;
}

Future<int> _sumFilesMatching(
  Directory directory,
  bool Function(File file) matches, {
  String? label,
}) async {
  try {
    if (!await directory.exists()) {
      return 0;
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'directory existence check failed',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
    return 0;
  }
  return _matchingFileTreeSizeBytes(directory, matches, label: label);
}

Future<int> _directoryTreeSizeBytes(
  Directory directory, {
  String? label,
}) async {
  var total = 0;
  try {
    await for (final entity in directory.list(followLinks: false)) {
      try {
        if (entity is File) {
          total += await entity.length();
        } else if (entity is Directory) {
          total += await _directoryTreeSizeBytes(entity, label: label);
        }
      } catch (error) {
        logDiagnostic(
          'storage',
          'directory entry size read failed',
          data: {'label': label, 'path': entity.path, 'error': '$error'},
        );
      }
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'directory listing skipped',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
  }
  return total;
}

Future<int> _matchingFileTreeSizeBytes(
  Directory directory,
  bool Function(File file) matches, {
  String? label,
}) async {
  var total = 0;
  try {
    await for (final entity in directory.list(followLinks: false)) {
      try {
        if (entity is File && matches(entity)) {
          total += await entity.length();
        } else if (entity is Directory) {
          total += await _matchingFileTreeSizeBytes(
            entity,
            matches,
            label: label,
          );
        }
      } catch (error) {
        logDiagnostic(
          'storage',
          'matching directory entry size read failed',
          data: {'label': label, 'path': entity.path, 'error': '$error'},
        );
      }
    }
  } catch (error) {
    logDiagnostic(
      'storage',
      'matching directory listing skipped',
      data: {'label': label, 'path': directory.path, 'error': '$error'},
    );
  }
  return total;
}

Future<int> _sharedPreferencesApproxBytes() async {
  final prefs = await SharedPreferences.getInstance();
  var total = 0;
  for (final key in prefs.getKeys()) {
    total += utf8.encode(key).length;
    final value = prefs.get(key);
    switch (value) {
      case String text:
        total += utf8.encode(text).length;
      case List<String> list:
        for (final text in list) {
          total += utf8.encode(text).length;
        }
      default:
        total += utf8.encode('$value').length;
    }
  }
  return total;
}

Future<_NativeStorageDiagnostics> _nativeStorageDiagnostics() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.iOS) {
    return _NativeStorageDiagnostics.empty;
  }
  try {
    final result = await _storageDiagnosticsChannel
        .invokeMapMethod<String, Object?>('appGroupStorageDiagnostics');
    if (result == null) {
      return _NativeStorageDiagnostics.empty;
    }
    return _NativeStorageDiagnostics(
      appGroupBytes: _intFromPlatform(result['appGroupBytes']),
      appGroupSharedImportsBytes: _intFromPlatform(
        result['appGroupSharedImportsBytes'],
      ),
      appGroupPendingQuickCaptureBytes: _intFromPlatform(
        result['appGroupPendingQuickCaptureBytes'],
      ),
    );
  } catch (error) {
    logDiagnostic(
      'storage',
      'native storage diagnostics unavailable',
      data: {'error': error},
    );
    return _NativeStorageDiagnostics.empty;
  }
}

int _intFromPlatform(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.round();
  }
  return int.tryParse('$value') ?? 0;
}

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

final releaseNotesProvider = FutureProvider<List<ReleaseNote>>((ref) async {
  final raw = await rootBundle.loadString(
    'assets/release_notes/release_notes.json',
  );
  final decoded = jsonDecode(raw) as Map<String, dynamic>;
  final releases = <ReleaseNote>[];
  for (final rawRelease
      in decoded['releases'] as List<dynamic>? ?? const <dynamic>[]) {
    final release = releaseNoteFromJson(
      Map<String, dynamic>.from(rawRelease as Map),
    );
    if (release != null) {
      releases.add(release);
    }
  }
  return List.unmodifiable(releases);
});

final currentReleaseNoteProvider = FutureProvider<ReleaseNote?>((ref) async {
  final packageInfo = await ref.watch(packageInfoProvider.future);
  final releases = await ref.watch(releaseNotesProvider.future);
  for (final release in releases) {
    if (release.version == packageInfo.version) {
      return release;
    }
  }
  return null;
});

final unseenReleaseNoteProvider = FutureProvider<ReleaseNote?>((ref) async {
  final releaseNote = await ref.watch(currentReleaseNoteProvider.future);
  if (releaseNote == null || releaseNote.items.isEmpty) {
    return null;
  }
  final packageInfo = await ref.watch(packageInfoProvider.future);
  final prefs = await SharedPreferences.getInstance();
  final seenKey = prefs.getString('release_notes.last_seen');
  return seenKey == packageInfo.releaseKey ? null : releaseNote;
});

final releaseNotesSeenControllerProvider = Provider<ReleaseNotesSeenController>(
  (ref) {
    return ReleaseNotesSeenController(ref);
  },
);

class ReleaseNotesSeenController {
  const ReleaseNotesSeenController(this._ref);

  final Ref _ref;

  Future<void> markCurrentSeen() async {
    final packageInfo = await _ref.read(packageInfoProvider.future);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('release_notes.last_seen', packageInfo.releaseKey);
    _ref.invalidate(unseenReleaseNoteProvider);
  }
}

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

final appLaunchControllerProvider =
    NotifierProvider<AppLaunchController, AppLaunchSurface>(
      AppLaunchController.new,
    );

final appTutorialControllerProvider =
    NotifierProvider<AppTutorialController, AppTutorialState?>(
      AppTutorialController.new,
    );

class AppTutorialController extends Notifier<AppTutorialState?> {
  static const _courseSteps = <AppTutorialCourse, List<AppTutorialStep>>{
    AppTutorialCourse.basics: [
      AppTutorialStep.addNote,
      AppTutorialStep.navigation,
      AppTutorialStep.privateProfile,
    ],
    AppTutorialCourse.mainScreen: [
      AppTutorialStep.search,
      AppTutorialStep.filters,
      AppTutorialStep.notesList,
      AppTutorialStep.privateProfile,
      AppTutorialStep.syncStatus,
      AppTutorialStep.navigation,
    ],
    AppTutorialCourse.writing: [
      AppTutorialStep.addNote,
      AppTutorialStep.tags,
      AppTutorialStep.calendarInsights,
    ],
    AppTutorialCourse.find: [
      AppTutorialStep.search,
      AppTutorialStep.filters,
      AppTutorialStep.tags,
    ],
    AppTutorialCourse.attachments: [
      AppTutorialStep.attachments,
      AppTutorialStep.filters,
      AppTutorialStep.syncStatus,
    ],
    AppTutorialCourse.privateMemo: [
      AppTutorialStep.privateMemo,
      AppTutorialStep.addNote,
      AppTutorialStep.settings,
    ],
    AppTutorialCourse.review: [
      AppTutorialStep.calendarInsights,
      AppTutorialStep.tags,
      AppTutorialStep.navigation,
    ],
    AppTutorialCourse.privacy: [
      AppTutorialStep.privateProfile,
      AppTutorialStep.settings,
    ],
    AppTutorialCourse.sync: [
      AppTutorialStep.syncStatus,
      AppTutorialStep.syncTroubleshooting,
    ],
    AppTutorialCourse.syncTroubleshooting: [
      AppTutorialStep.syncTroubleshooting,
      AppTutorialStep.syncStatus,
    ],
    AppTutorialCourse.trashRecovery: [
      AppTutorialStep.trashRecovery,
      AppTutorialStep.trash,
      AppTutorialStep.navigation,
    ],
    AppTutorialCourse.organize: [
      AppTutorialStep.tags,
      AppTutorialStep.trash,
      AppTutorialStep.calendarInsights,
    ],
    AppTutorialCourse.maintenance: [
      AppTutorialStep.settings,
      AppTutorialStep.syncStatus,
      AppTutorialStep.trash,
    ],
  };

  @override
  AppTutorialState? build() => null;

  void start([AppTutorialCourse course = AppTutorialCourse.basics]) {
    final isSyncCourse =
        course == AppTutorialCourse.sync ||
        course == AppTutorialCourse.syncTroubleshooting;
    final syncIsOff = isSyncCourse && (!ref.read(syncV2RegisteredProvider));
    final steps = syncIsOff
        ? const [AppTutorialStep.syncTroubleshooting]
        : _courseSteps[course] ?? _courseSteps[AppTutorialCourse.basics]!;
    state = AppTutorialState(course: course, steps: steps, index: 0);
  }

  void next() {
    final current = state;
    if (current == null) {
      return;
    }
    state = current.index >= current.steps.length - 1
        ? null
        : AppTutorialState(
            course: current.course,
            steps: current.steps,
            index: current.index + 1,
          );
  }

  void previous() {
    final current = state;
    if (current == null) {
      return;
    }
    if (current.index <= 0) {
      return;
    }
    state = AppTutorialState(
      course: current.course,
      steps: current.steps,
      index: current.index - 1,
    );
  }

  void close() {
    state = null;
  }
}

final appTutorialCompletionControllerProvider =
    NotifierProvider<AppTutorialCompletionController, Set<AppTutorialCourse>>(
      AppTutorialCompletionController.new,
    );

class AppTutorialCompletionController extends Notifier<Set<AppTutorialCourse>> {
  static const _storageKey = 'tutorials.completed_courses.v1';

  @override
  Set<AppTutorialCourse> build() {
    unawaited(_load());
    return <AppTutorialCourse>{};
  }

  Future<void> markComplete(AppTutorialCourse course) async {
    final next = {...state, course};
    state = next;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
      _storageKey,
      next.map((course) => course.name).toList(growable: false)..sort(),
    );
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_storageKey) ?? const <String>[];
    final completed = <AppTutorialCourse>{};
    for (final name in stored) {
      for (final course in AppTutorialCourse.values) {
        if (course.name == name) {
          completed.add(course);
          break;
        }
      }
    }
    state = {...completed, ...state};
  }
}

class AppLaunchController extends Notifier<AppLaunchSurface> {
  bool _restored = false;

  static const _storageKey = 'app.onboarding_completed';
  static const _versionStorageKey = 'app.onboarding_completed_version';
  static const _currentOnboardingVersion = 2;

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
      final packageInfo = await ref.read(packageInfoProvider.future);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_storageKey, true);
      await prefs.setInt(_versionStorageKey, _currentOnboardingVersion);
      await prefs.setString('release_notes.last_seen', packageInfo.releaseKey);
    } catch (_) {
      logDiagnostic('settings', 'onboarding completion persistence failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.theme_mode';

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
    } catch (_) {
      logDiagnostic('settings', 'theme mode persistence failed');
    }
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
    } catch (_) {
      logDiagnostic('settings', 'theme mode restore failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.profile_theme_modes';

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
    } catch (_) {
      // Invalid persisted theme override data falls back to the default map.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {
      logDiagnostic('settings', 'theme overrides persistence failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.font_family';

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
    } catch (_) {
      logDiagnostic('settings', 'font family persistence failed');
    }
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
    } catch (_) {
      logDiagnostic('settings', 'font family restore failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.profile_font_families';

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
    } catch (_) {
      // Invalid persisted font override data falls back to the default map.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {
      logDiagnostic('settings', 'font overrides persistence failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.color_theme';

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
    } catch (_) {
      logDiagnostic('settings', 'color theme persistence failed');
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stored = prefs.getString(_storageKey);
      if (stored == null) {
        return;
      }

      state = _appColorThemeFromName(stored) ?? AppColorTheme.sakura;
    } catch (_) {
      logDiagnostic('settings', 'color theme restore failed');
    }
  }
}

final profileColorThemeControllerProvider =
    NotifierProvider<ProfileColorThemeController, Map<String, AppColorTheme>>(
      ProfileColorThemeController.new,
    );

class ProfileColorThemeController extends Notifier<Map<String, AppColorTheme>> {
  bool _restored = false;

  static const _storageKey = 'settings.profile_color_themes';

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
    } catch (_) {
      // Invalid persisted color theme override data uses the default map.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {
      logDiagnostic('settings', 'color theme overrides persistence failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.locale';

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
    } catch (_) {
      logDiagnostic('settings', 'locale preference persistence failed');
    }
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
    } catch (_) {
      logDiagnostic('settings', 'locale preference restore failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.profile_locales';

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
    } catch (_) {
      // Invalid persisted locale override data falls back to system defaults.
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode({
        for (final entry in state.entries) entry.key: entry.value.name,
      });
      await prefs.setString(_storageKey, encoded);
    } catch (_) {
      logDiagnostic('settings', 'locale overrides persistence failed');
    }
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

final appLockSettingsReadyProvider =
    NotifierProvider<AppLockSettingsReadyController, bool>(
      AppLockSettingsReadyController.new,
    );

class AppLockSettingsReadyController extends Notifier<bool> {
  @override
  bool build() => false;

  void markReady() => state = true;
}

class AppLockSettingsController extends Notifier<bool> {
  bool _restored = false;

  static const _storageKey = 'settings.app_lock_enabled';

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
    } catch (_) {
      logDiagnostic('app_lock', 'app lock preference persistence failed');
    }
    ref.read(appLockSettingsReadyProvider.notifier).markReady();
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? false;
    } catch (_) {
      // Fail closed in the gate until this restore attempt has completed.
    } finally {
      ref.read(appLockSettingsReadyProvider.notifier).markReady();
    }
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
    } catch (_) {
      // Spotlight may not expose this optional native channel on every platform.
    }
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
      if (block.text != null && block.text!.trim().isNotEmpty)
        block.text!.trim(),
    for (final attachment in note.attachments)
      if (attachment.label.trim().isNotEmpty) attachment.label.trim(),
    for (final block in note.blocks)
      if (block.attachment?.label.trim().isNotEmpty ?? false)
        block.attachment!.label.trim(),
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
  const maximumTerms = 512;
  const maximumTermLength = 64;
  final terms = <String>{};

  void addTerm(String raw) {
    if (terms.length >= maximumTerms) {
      return;
    }
    final term = raw.trim().toLowerCase();
    if (term.length < 2 || term.length > maximumTermLength) {
      return;
    }
    terms.add(term);
  }

  List<String> segments(String text) {
    return text
        .replaceAll(RegExp(r'[\s,.;:!?，。、・：；！？「」『』（）()\[\]［］【】#]+'), ' ')
        .split(' ')
        .map((value) => value.trim().toLowerCase())
        .where((value) => value.length >= 2)
        .toList(growable: false);
  }

  List<String> uniqueCandidates(Iterable<String> values) {
    return <String>{
      for (final value in values)
        if (value.length >= 2 && value.length <= maximumTermLength) value,
    }.toList(growable: false);
  }

  void addBalanced(List<String> candidates, int allowance) {
    if (allowance <= 0 || candidates.isEmpty || terms.length >= maximumTerms) {
      return;
    }
    final available = math.min(allowance, maximumTerms - terms.length);
    if (candidates.length <= available) {
      for (final candidate in candidates) {
        addTerm(candidate);
      }
      return;
    }
    if (available == 1) {
      addTerm(candidates.last);
      return;
    }
    for (var i = 0; i < available; i++) {
      final index = (i * (candidates.length - 1) / (available - 1)).round();
      addTerm(candidates[index]);
    }
  }

  List<String> nGrams(Iterable<String> values, int length) {
    final codePointSegments = values
        .map((value) => value.runes.toList(growable: false))
        .where((value) => value.length >= length)
        .toList(growable: false);
    final candidateCounts = codePointSegments
        .map((value) => value.length - length + 1)
        .toList(growable: false);
    final totalCandidates = candidateCounts.fold<int>(0, (a, b) => a + b);
    if (totalCandidates == 0) {
      return const <String>[];
    }

    // Bound temporary allocations for unusually large notes while sampling
    // evenly across the complete text, including its final characters.
    final sampleCount = math.min(totalCandidates, maximumTerms * 4);
    final candidates = <String>[];
    var segmentIndex = 0;
    var segmentStart = 0;
    for (var i = 0; i < sampleCount; i++) {
      final globalIndex = sampleCount == 1
          ? totalCandidates - 1
          : (i * (totalCandidates - 1) / (sampleCount - 1)).round();
      while (segmentIndex < candidateCounts.length - 1 &&
          globalIndex >= segmentStart + candidateCounts[segmentIndex]) {
        segmentStart += candidateCounts[segmentIndex];
        segmentIndex++;
      }
      final localIndex = globalIndex - segmentStart;
      final codePoints = codePointSegments[segmentIndex];
      candidates.add(
        String.fromCharCodes(
          codePoints.sublist(localIndex, localIndex + length),
        ),
      );
    }
    return uniqueCandidates(candidates);
  }

  final titleSegments = segments(title);
  final tagSegments = tags.expand(segments).toList(growable: false);
  final bodySegments = segments(body);

  // Titles and tags are concise, high-signal metadata and should never be
  // displaced by a long body.
  for (final value in [...titleSegments, ...tagSegments]) {
    addTerm(value);
  }

  // Preserve ordinary word search throughout long Latin-script bodies. The
  // balanced sampler includes the beginning and end instead of only a prefix.
  addBalanced(uniqueCandidates(bodySegments), 128);

  final allSegments = [...titleSegments, ...tagSegments, ...bodySegments];
  final nGramCandidates = <int, List<String>>{
    for (final length in const [2, 3, 4]) length: nGrams(allSegments, length),
  };
  final remaining = maximumTerms - terms.length;
  addBalanced(nGramCandidates[2]!, (remaining * 0.5).round());
  addBalanced(nGramCandidates[3]!, (remaining * 0.3).round());
  addBalanced(nGramCandidates[4]!, maximumTerms - terms.length);

  // Reuse capacity left by short or duplicate candidate sets.
  for (final length in const [2, 3, 4]) {
    addBalanced(nGramCandidates[length]!, maximumTerms - terms.length);
  }

  for (final tag in tags) {
    addTerm(tag);
  }
  return terms.take(maximumTerms).toList(growable: false);
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
  bool _restored = false;

  static const _storageKey = 'settings.ios_spotlight_standard_notes_enabled';

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
    } catch (_) {
      logDiagnostic('spotlight', 'index preference persistence failed');
    }
    await _applyIndexState(enabled);
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_storageKey) ?? false;
      state = enabled;
      await _applyIndexState(enabled);
    } catch (_) {
      logDiagnostic('spotlight', 'index preference restore failed');
    }
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
  bool _restored = false;

  static const _storageKey = 'settings.widget_quick_capture_enabled';

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
    } catch (_) {
      logDiagnostic('privacy', 'privacy screen preference persistence failed');
    }
  }

  Future<void> _restore() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = prefs.getBool(_storageKey) ?? true;
    } catch (_) {
      logDiagnostic('privacy', 'privacy screen preference restore failed');
    }
  }
}

@Riverpod(keepAlive: true)
class WidgetQuickCaptureRequestController
    extends _$WidgetQuickCaptureRequestController {
  final Set<String> _seenNonces = <String>{};

  @override
  QuickCaptureRequest? build() => null;

  void open(QuickCaptureRequest request) {
    if (state?.shareId != null) return;
    if (request.nonce.isNotEmpty && !_seenNonces.add(request.nonce)) {
      return;
    }
    if (_seenNonces.length > 32) {
      _seenNonces.remove(_seenNonces.first);
    }
    state = request;
  }

  void clear() {
    final current = state;
    if (current?.shareId != null) _seenNonces.remove(current!.nonce);
    state = null;
  }
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
  bool _restored = false;

  static const _storageKey = 'settings.app_lock_relock_delay';

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
    } catch (_) {
      logDiagnostic('app_lock', 'relock delay preference persistence failed');
    }
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
    } catch (_) {
      logDiagnostic('app_lock', 'relock delay preference restore failed');
    }
  }
}

@Riverpod(keepAlive: true)
class ActiveIdentity extends _$ActiveIdentity {
  @override
  String build() => 'daily';
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
  NoteEditorDraftStore({
    required this._encryptionService,
    required Future<SecretKey?> Function(String vaultId) keyForVault,
    this._protectAttachments,
    this._storageKey = 'notes.editor_draft.v2',
  }) : _keyResolver = keyForVault;

  final Future<void> Function(NoteEditorDraftSnapshot snapshot)?
  _protectAttachments;
  final String _storageKey;
  final Future<SecretKey?> Function(String vaultId) _keyResolver;
  Future<SecretKey?> _keyForVault(String vaultId) => _keyResolver(vaultId);
  static const _envelopeVersion = 2;

  final EncryptionService _encryptionService;

  Future<bool> hasSavedDraft() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.containsKey(_storageKey);
  }

  Future<NoteEditorDraftSnapshot?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final payload = prefs.getString(_storageKey);
    if (payload == null || payload.isEmpty) {
      return null;
    }
    try {
      final decoded = Map<String, dynamic>.from(jsonDecode(payload) as Map);
      if (decoded['version'] == _envelopeVersion &&
          decoded['encryptedPayload'] is String) {
        final vaultId = decoded['vaultId'] as String? ?? 'everyday';
        final profileKey = await _keyForVault(vaultId);
        if (decoded['keyScope'] != 'profile') return null;
        if (profileKey == null) {
          return null;
        }
        final key = profileKey;
        final clear = await _encryptionService.decryptJson(
          encodedPayload: decoded['encryptedPayload'] as String,
          secretKey: key,
        );
        final snapshot = NoteEditorDraftSnapshot.fromJson(clear);
        if (snapshot.vaultId != vaultId) {
          throw const FormatException('Draft vault does not match envelope.');
        }
        if (!identical(await _keyForVault(vaultId), key)) {
          return null;
        }
        return snapshot;
      }

      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> save(NoteEditorDraftSnapshot snapshot) async {
    final key = await _keyForVault(snapshot.vaultId);
    if (key == null) {
      return;
    }
    await _protectAttachments?.call(snapshot);
    await _writeEncryptedEnvelope(snapshot, secretKey: key);
  }

  Future<void> _writeEncryptedEnvelope(
    NoteEditorDraftSnapshot snapshot, {
    required SecretKey secretKey,
    String keyScope = 'profile',
  }) async {
    final encryptedPayload = await _encryptionService.encryptJson(
      payload: snapshot.toJson(),
      secretKey: secretKey,
    );
    if (!identical(await _keyForVault(snapshot.vaultId), secretKey)) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'version': _envelopeVersion,
        'vaultId': snapshot.vaultId,
        'keyScope': keyScope,
        'encryptedPayload': encryptedPayload,
      }),
    );
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}

bool _sameTagList(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (canonicalizeNoteTag(left[i]) != canonicalizeNoteTag(right[i])) {
      return false;
    }
  }
  return true;
}

class AutoTagRule {
  const AutoTagRule({
    required this.id,
    required this.tag,
    required this.keywords,
    this.enabled = true,
    this.matchTitle = true,
    this.matchBody = true,
    this.matchAttachments = true,
  });

  final String id;
  final String tag;
  final List<String> keywords;
  final bool enabled;
  final bool matchTitle;
  final bool matchBody;
  final bool matchAttachments;

  AutoTagRule copyWith({
    String? id,
    String? tag,
    List<String>? keywords,
    bool? enabled,
    bool? matchTitle,
    bool? matchBody,
    bool? matchAttachments,
  }) {
    return AutoTagRule(
      id: id ?? this.id,
      tag: tag ?? this.tag,
      keywords: keywords ?? this.keywords,
      enabled: enabled ?? this.enabled,
      matchTitle: matchTitle ?? this.matchTitle,
      matchBody: matchBody ?? this.matchBody,
      matchAttachments: matchAttachments ?? this.matchAttachments,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'id': id,
      'tag': tag,
      'keywords': keywords,
      'enabled': enabled,
      'matchTitle': matchTitle,
      'matchBody': matchBody,
      'matchAttachments': matchAttachments,
    };
  }

  static AutoTagRule? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final tag = normalizeNoteTag('${value['tag'] ?? ''}');
    final id = '${value['id'] ?? ''}'.trim();
    final keywords = _normalizeAutoTagKeywords(
      value['keywords'] is List
          ? (value['keywords'] as List).map((entry) => '$entry')
          : const <String>[],
    );
    if (id.isEmpty || tag.isEmpty || keywords.isEmpty) {
      return null;
    }
    return AutoTagRule(
      id: id,
      tag: tag,
      keywords: keywords,
      enabled: value['enabled'] != false,
      matchTitle: value['matchTitle'] != false,
      matchBody: value['matchBody'] != false,
      matchAttachments: value['matchAttachments'] != false,
    );
  }
}

final autoTagRulesControllerProvider =
    NotifierProvider<AutoTagRulesController, List<AutoTagRule>>(
      AutoTagRulesController.new,
    );

class AutoTagRulesController extends Notifier<List<AutoTagRule>> {
  bool _restored = false;

  static const _storageKey = 'settings.auto_tag_rules.v1';

  Future<void>? _restoreTask;

  @override
  List<AutoTagRule> build() {
    if (!_restored) {
      _restored = true;
      _restoreTask = _restore();
      unawaited(_restoreTask);
    }
    return const <AutoTagRule>[];
  }

  Future<void> get restoreCompleted => _restoreTask ?? Future<void>.value();

  Future<void> addRule({
    required String tag,
    required Iterable<String> keywords,
    bool matchTitle = true,
    bool matchBody = true,
    bool matchAttachments = true,
  }) async {
    await _restoreTask;
    final normalizedTag = normalizeNoteTag(tag);
    final normalizedKeywords = _normalizeAutoTagKeywords(keywords);
    if (normalizedTag.isEmpty || normalizedKeywords.isEmpty) {
      return;
    }
    final rule = AutoTagRule(
      id: 'rule-${DateTime.now().microsecondsSinceEpoch}',
      tag: normalizedTag,
      keywords: normalizedKeywords,
      matchTitle: matchTitle,
      matchBody: matchBody,
      matchAttachments: matchAttachments,
    );
    state = [...state, rule];
    await _persist();
  }

  Future<void> setEnabled(String id, bool enabled) async {
    await _restoreTask;
    var changed = false;
    final next = [
      for (final rule in state)
        if (rule.id == id)
          (() {
            changed = changed || rule.enabled != enabled;
            return rule.copyWith(enabled: enabled);
          })()
        else
          rule,
    ];
    if (!changed) {
      return;
    }
    state = List.unmodifiable(next);
    await _persist();
  }

  Future<void> updateRule({
    required String id,
    required String tag,
    required Iterable<String> keywords,
    required bool matchTitle,
    required bool matchBody,
    required bool matchAttachments,
  }) async {
    await _restoreTask;
    final normalizedTag = normalizeNoteTag(tag);
    final normalizedKeywords = _normalizeAutoTagKeywords(keywords);
    if (normalizedTag.isEmpty ||
        normalizedKeywords.isEmpty ||
        (!matchTitle && !matchBody && !matchAttachments)) {
      return;
    }
    var changed = false;
    final next = [
      for (final rule in state)
        if (rule.id == id)
          (() {
            final updated = rule.copyWith(
              tag: normalizedTag,
              keywords: normalizedKeywords,
              matchTitle: matchTitle,
              matchBody: matchBody,
              matchAttachments: matchAttachments,
            );
            changed =
                changed ||
                rule.tag != updated.tag ||
                !_sameStringList(rule.keywords, updated.keywords) ||
                rule.matchTitle != updated.matchTitle ||
                rule.matchBody != updated.matchBody ||
                rule.matchAttachments != updated.matchAttachments;
            return updated;
          })()
        else
          rule,
    ];
    if (!changed) {
      return;
    }
    state = List.unmodifiable(next);
    await _persist();
  }

  Future<void> removeRule(String id) async {
    await _restoreTask;
    final next = state.where((rule) => rule.id != id).toList(growable: false);
    if (next.length == state.length) {
      return;
    }
    state = List.unmodifiable(next);
    await _persist();
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    final rules = <AutoTagRule>[];
    for (final encoded
        in prefs.getStringList(_storageKey) ?? const <String>[]) {
      try {
        final rule = AutoTagRule.fromJson(jsonDecode(encoded));
        if (rule != null) {
          rules.add(rule);
        }
      } on FormatException {
        // Ignore malformed legacy/local entries.
      }
    }
    state = List.unmodifiable(rules);
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_storageKey, [
      for (final rule in state) jsonEncode(rule.toJson()),
    ]);
  }
}

bool _sameStringList(List<String> left, List<String> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var i = 0; i < left.length; i++) {
    if (left[i] != right[i]) {
      return false;
    }
  }
  return true;
}

List<String> _normalizeAutoTagKeywords(Iterable<String> keywords) {
  final seen = <String>{};
  final values = <String>[];
  for (final raw in keywords) {
    final normalized = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (normalized.isEmpty) {
      continue;
    }
    final key = normalized.toLowerCase();
    if (!seen.add(key)) {
      continue;
    }
    values.add(normalized);
  }
  return List.unmodifiable(values);
}

List<String> splitAutoTagKeywords(String value) {
  return _normalizeAutoTagKeywords(value.split(RegExp(r'[,、\n\r]+')));
}

bool autoTagRuleMatchesNote(AutoTagRule rule, NoteEntry note) {
  if (!rule.enabled) {
    return false;
  }
  final fields = <String>[
    if (rule.matchTitle) note.title,
    if (rule.matchBody) note.body,
    if (rule.matchAttachments)
      for (final attachment in note.attachments) attachment.label,
  ].where((value) => value.trim().isNotEmpty).join('\n').toLowerCase();
  if (fields.isEmpty) {
    return false;
  }
  return rule.keywords.any((keyword) {
    final needle = keyword.trim().toLowerCase();
    return needle.isNotEmpty && fields.contains(needle);
  });
}

NoteEntry applyAutoTagRules(NoteEntry note, Iterable<AutoTagRule> rules) {
  if (note.deletedAt != null || note.archivedAt != null) {
    return note;
  }
  final tags = [...note.tags];
  var changed = false;
  final existing = {for (final tag in tags) canonicalizeNoteTag(tag)};
  for (final rule in rules) {
    final tag = normalizeNoteTag(rule.tag);
    final key = canonicalizeNoteTag(tag);
    if (tag.isEmpty ||
        key.isEmpty ||
        existing.contains(key) ||
        !autoTagRuleMatchesNote(rule, note)) {
      continue;
    }
    tags.add(tag);
    existing.add(key);
    changed = true;
  }
  if (!changed) {
    return note;
  }
  return note.copyWith(tags: dedupeNoteTags(tags));
}

@Riverpod(keepAlive: true)
class NotesListDensityController extends _$NotesListDensityController {
  bool _restored = false;

  static const _storageKey = 'notes.list_density';

  bool _changedBeforeRestoreCompleted = false;

  @override
  NotesListDensity build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return NotesListDensity.standard;
  }

  Future<void> setDensity(NotesListDensity density) async {
    _changedBeforeRestoreCompleted = true;
    state = density;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, density.name);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_changedBeforeRestoreCompleted) {
      return;
    }
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
  bool _restored = false;

  static const _storageKey = 'notes.attachment_preview_fit';

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
  bool _restored = false;

  static const _storageKey = 'settings.video_playback_muted_by_default';

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
  bool _restored = false;

  static const _storageKey = 'notes.list_sort_field';
  static const _defaultSortField = NotesListSortField.createdAt;

  bool _changedBeforeRestoreCompleted = false;

  @override
  NotesListSortField build() {
    if (!_restored) {
      _restored = true;
      unawaited(_restore());
    }
    return _defaultSortField;
  }

  Future<void> setSortField(NotesListSortField field) async {
    _changedBeforeRestoreCompleted = true;
    state = field;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, field.name);
  }

  Future<void> _restore() async {
    final prefs = await SharedPreferences.getInstance();
    if (_changedBeforeRestoreCompleted) {
      return;
    }
    final stored = prefs.getString(_storageKey);
    if (stored == null || stored.isEmpty) {
      return;
    }
    state = NotesListSortField.values.firstWhere(
      (field) => field.name == stored,
      orElse: () => _defaultSortField,
    );
  }
}

@Riverpod(keepAlive: true)
class LastNoteEditorSettingsController
    extends _$LastNoteEditorSettingsController {
  bool _restored = false;

  static const _modeKey = 'notes.last_editor_mode';
  static const _vaultKey = 'notes.last_vault_id';
  static const _captureLocationKey = 'notes.last_capture_location';

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
        vaultId:
            vaultId == 'everyday' ||
                (vaultId?.startsWith(customPrivateVaultPrefix) ?? false)
            ? vaultId!
            : 'everyday',
        captureLocation: captureLocation,
      );
    }
    _restored = true;
  }
}

@Riverpod(keepAlive: true)
class NotesController extends _$NotesController {
  bool _restored = false;

  static const _deletedSeedNoteIdsKey = 'notes.deleted_seed_note_ids.v1';
  static const _storeAssetsSeedDemoNotesKey = 'store_assets.seed_demo_notes.v1';
  static const trashRetention = Duration(days: 7);

  bool _restoreFailed = false;
  Future<void>? _restoreTask;
  Future<void> _upsertQueue = Future<void>.value();
  int _privateConcealVersion = 0;

  @override
  List<NoteEntry> build() {
    if (!_restored) {
      _restored = true;
      _restoreTask = _restore();
      unawaited(_restoreTask);
    }
    return const <NoteEntry>[];
  }

  // All note mutations and reloads share one queue. A full save must never
  // use state captured before a concurrent load discovered remote notes.
  Future<T> _exclusive<T>(Future<T> Function() action) {
    final operation = _upsertQueue.then((_) => action());
    _upsertQueue = operation
        .then<void>((_) {})
        .catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<int> applyAutoTagRulesToExisting({Iterable<String>? vaultIds}) =>
      _exclusive(() => _performApplyAutoTagRulesToExisting(vaultIds: vaultIds));

  Future<void> delete(String noteId) =>
      _exclusive(() => _performDelete(noteId));

  Future<void> restoreFromTrash(String noteId) =>
      _exclusive(() => _performRestoreFromTrash(noteId));

  Future<int> purgeTrashOlderThan([Duration retention = trashRetention]) =>
      _exclusive(() => _performPurgeTrashOlderThan(retention));

  Future<void> archive(String noteId) =>
      _exclusive(() => _performArchive(noteId));

  Future<void> unarchive(String noteId) =>
      _exclusive(() => _performUnarchive(noteId));

  Future<void> togglePinned(String noteId) =>
      _exclusive(() => _performTogglePinned(noteId));

  Future<int> renameTag({
    required String from,
    required String to,
    Iterable<String>? vaultIds,
  }) => _exclusive(
    () => _performRenameTag(from: from, to: to, vaultIds: vaultIds),
  );

  Future<int> deleteTag(String tag, {Iterable<String>? vaultIds}) =>
      _exclusive(() => _performDeleteTag(tag, vaultIds: vaultIds));

  Future<int> archiveNotesOlderThan(Duration age) =>
      _exclusive(() => _performArchiveNotesOlderThan(age));

  Future<int> unarchiveAll() => _exclusive(() => _performUnarchiveAll());

  Future<void> seedIfEmpty() => _exclusive(() => _performSeedIfEmpty());

  Future<int> createDemoNotes() => _exclusive(() => _performCreateDemoNotes());

  Future<int> createPerformanceTestNotes({
    required int count,
    int attachmentsPerNote = 0,
  }) => _exclusive(
    () => _performCreatePerformanceTestNotes(
      count: count,
      attachmentsPerNote: attachmentsPerNote,
    ),
  );

  Future<int> deleteDemoNotes() => _exclusive(() => _performDeleteDemoNotes());

  Future<void> upsert(NoteEntry note) {
    final operation = _upsertQueue.then((_) => _performUpsert(note));
    _upsertQueue = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _performUpsert(NoteEntry note) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? savedNote;
    var created = false;
    await runFirebaseTrace(
      'notes_upsert',
      () async {
        final existing = state.cast<NoteEntry?>().firstWhere(
          (entry) => entry?.id == note.id,
          orElse: () => null,
        );
        if (existing?.isPermanentlyDeleted == true) return;
        if (existing != null && _isLockedPrivatePlaceholder(existing)) {
          throw const SyncV2NoteStoreLocked('note');
        }
        created = existing == null;
        final concealVersion = _privateConcealVersion;
        final prepared = await _prepareForSave(note, previous: existing);
        if (!ref.mounted) return;
        if ((isPrivateVaultId(note.vaultId) ||
                (existing != null && isPrivateVaultId(existing.vaultId))) &&
            concealVersion != _privateConcealVersion) {
          throw const SyncV2NoteStoreLocked('note');
        }
        final next = [...state];
        final index = next.indexWhere((entry) => entry.id == note.id);
        if (index == -1) {
          next.add(prepared);
        } else {
          next[index] = prepared;
        }
        _sort(next);
        state = next;
        try {
          await _persistOne(prepared);
        } catch (_) {
          final rollback = [...state];
          final rollbackIndex = rollback.indexWhere(
            (entry) => entry.id == prepared.id,
          );
          if (rollbackIndex != -1 && rollback[rollbackIndex] == prepared) {
            if (existing == null) {
              rollback.removeAt(rollbackIndex);
            } else {
              rollback[rollbackIndex] =
                  isPrivateVaultId(existing.vaultId) &&
                      concealVersion != _privateConcealVersion
                  ? _concealedPrivateNote(existing)
                  : existing;
            }
            _sort(rollback);
            state = rollback;
          }
          rethrow;
        }
        await _cleanupRemovedAttachments(existing, prepared);
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

  Future<int> _performApplyAutoTagRulesToExisting({
    Iterable<String>? vaultIds,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    await ref.read(autoTagRulesControllerProvider.notifier).restoreCompleted;
    final rules = ref.read(autoTagRulesControllerProvider);
    if (rules.where((rule) => rule.enabled).isEmpty) {
      return 0;
    }
    final targetVaultIds = vaultIds?.toSet();
    final now = DateTime.now();
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) ||
          note.deletedAt != null ||
          note.archivedAt != null ||
          (targetVaultIds != null && !targetVaultIds.contains(note.vaultId))) {
        next.add(note);
        continue;
      }
      final tagged = applyAutoTagRules(note, rules);
      if (_sameTagList(note.tags, tagged.tags)) {
        next.add(note);
        continue;
      }
      final changedBase = tagged.copyWith(
        updatedAt: now,
        revision: note.revision + 1,
      );
      final changedNote = changedBase.copyWith(
        syncState: _syncStateForLocalChange(changedBase, deleted: false),
      );
      next.add(
        changedNote.copyWith(contentHash: _computeContentHash(changedNote)),
      );
      changed++;
    }
    if (changed == 0) {
      return 0;
    }
    _sort(next);
    state = next;
    await _persist();
    logAudit('auto_tag_rules_apply', data: {'count': changed});
    return changed;
  }

  Future<void> _performDelete(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? deletedNote;
    await runFirebaseTrace('notes_delete', () async {
      final next = [...state];
      for (var i = 0; i < next.length; i++) {
        final note = next[i];
        if (note.id != noteId || note.isPermanentlyDeleted) {
          continue;
        }
        if (_isLockedPrivatePlaceholder(note)) {
          return;
        }
        final now = DateTime.now();
        final tombstone = note.copyWith(
          deletedAt: now,
          updatedAt: now,
          revision: note.revision + 1,
          syncState: _syncStateForLocalChange(note, deleted: true),
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
      logAudit('note_delete', data: {..._auditNoteData(auditedNote)});
    }
  }

  Future<void> _performRestoreFromTrash(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? restoredNote;
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (_isLockedPrivatePlaceholder(note) ||
          note.id != noteId ||
          note.deletedAt == null ||
          note.isPermanentlyDeleted) {
        continue;
      }
      final now = DateTime.now();
      final restored = note.copyWith(
        deletedAt: null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: _syncStateForLocalChange(note, deleted: false),
      );
      final concealVersion = _privateConcealVersion;
      final prepared = await _protectAttachmentsForVault(restored);
      if (!ref.mounted) return;
      if (isPrivateVaultId(note.vaultId) &&
          concealVersion != _privateConcealVersion) {
        throw const SyncV2NoteStoreLocked('note');
      }
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
    final current = [
      for (final entry in state)
        entry.id == restoredNote.id ? restoredNote : entry,
    ];
    _sort(current);
    state = current;
    await _persistOne(restoredNote);
    logAudit('note_restore', data: _auditNoteData(restoredNote));
  }

  Future<void> deletePermanently(String noteId) {
    final operation = _upsertQueue.then((_) => _deletePermanently(noteId));
    _upsertQueue = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _deletePermanently(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    NoteEntry? note;
    for (final entry in state) {
      if (entry.id == noteId) {
        note = entry;
        break;
      }
    }
    if (note == null || note.deletedAt == null || note.isPermanentlyDeleted) {
      return;
    }
    await _purgeDeletedNote(note);
    if (ref.read(selectedNoteIdProvider) == noteId) {
      ref.read(selectedNoteIdProvider.notifier).select(null);
    }
    ref.invalidate(storageUsageSummaryProvider);
    logAudit('note_permanent_delete', data: _auditNoteData(note));
  }

  Future<int> _performPurgeTrashOlderThan([
    Duration retention = trashRetention,
  ]) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    return _purgeTrashOlderThan(retention);
  }

  Future<void> _performArchive(String noteId) async {
    await _setArchiveState(noteId, archived: true);
  }

  Future<void> _performUnarchive(String noteId) async {
    await _setArchiveState(noteId, archived: false);
  }

  Future<void> _performTogglePinned(String noteId) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final next = [...state];
    for (var i = 0; i < next.length; i++) {
      final note = next[i];
      if (_isLockedPrivatePlaceholder(note) ||
          note.id != noteId ||
          note.deletedAt != null) {
        continue;
      }
      final now = DateTime.now();
      final changed = note.copyWith(
        isPinned: !note.isPinned,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: _syncStateForLocalChange(note, deleted: false),
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

  Future<int> _performRenameTag({
    required String from,
    required String to,
    Iterable<String>? vaultIds,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final fromKey = canonicalizeNoteTag(from);
    final normalizedTo = normalizeNoteTag(to);
    final toKey = canonicalizeNoteTag(normalizedTo);
    if (fromKey.isEmpty || toKey.isEmpty || fromKey == toKey) {
      return 0;
    }
    final targetVaultIds = vaultIds?.toSet();
    final now = DateTime.now();
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) ||
          note.deletedAt != null ||
          note.archivedAt != null ||
          (targetVaultIds != null && !targetVaultIds.contains(note.vaultId)) ||
          !note.tags.any((tag) => canonicalizeNoteTag(tag) == fromKey)) {
        next.add(note);
        continue;
      }
      final renamedTags = <String>[
        for (final tag in note.tags)
          canonicalizeNoteTag(tag) == fromKey ? normalizedTo : tag,
      ];
      final changedBase = note.copyWith(
        tags: dedupeNoteTags(renamedTags),
        updatedAt: now,
        revision: note.revision + 1,
      );
      final changedNote = changedBase.copyWith(
        syncState: _syncStateForLocalChange(changedBase, deleted: false),
      );
      next.add(
        changedNote.copyWith(contentHash: _computeContentHash(changedNote)),
      );
      changed++;
    }
    if (changed == 0) {
      return 0;
    }
    _sort(next);
    state = next;
    await _persist();
    logAudit(
      'tag_rename',
      data: {'fromTag': from, 'toTag': normalizedTo, 'count': changed},
    );
    return changed;
  }

  Future<int> _performDeleteTag(
    String tag, {
    Iterable<String>? vaultIds,
  }) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final key = canonicalizeNoteTag(tag);
    if (key.isEmpty) {
      return 0;
    }
    final targetVaultIds = vaultIds?.toSet();
    final now = DateTime.now();
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) ||
          note.deletedAt != null ||
          note.archivedAt != null ||
          (targetVaultIds != null && !targetVaultIds.contains(note.vaultId)) ||
          !note.tags.any((entry) => canonicalizeNoteTag(entry) == key)) {
        next.add(note);
        continue;
      }
      final changedBase = note.copyWith(
        tags: [
          for (final entry in note.tags)
            if (canonicalizeNoteTag(entry) != key) entry,
        ],
        updatedAt: now,
        revision: note.revision + 1,
      );
      final changedNote = changedBase.copyWith(
        syncState: _syncStateForLocalChange(changedBase, deleted: false),
      );
      next.add(
        changedNote.copyWith(contentHash: _computeContentHash(changedNote)),
      );
      changed++;
    }
    if (changed == 0) {
      return 0;
    }
    _sort(next);
    state = next;
    await _persist();
    logAudit('tag_delete', data: {'tag': tag, 'count': changed});
    return changed;
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

  Future<int> _performArchiveNotesOlderThan(Duration age) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    final cutoff = DateTime.now().subtract(age);
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) ||
          note.deletedAt != null ||
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
        syncState: _syncStateForLocalChange(note, deleted: false),
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

  Future<int> _performUnarchiveAll() async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    var changed = 0;
    final next = <NoteEntry>[];
    for (final note in state) {
      if (_isLockedPrivatePlaceholder(note) ||
          note.deletedAt != null ||
          note.archivedAt == null) {
        next.add(note);
        continue;
      }
      final now = DateTime.now();
      final restored = note.copyWith(
        archivedAt: null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: _syncStateForLocalChange(note, deleted: false),
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
      if (_isLockedPrivatePlaceholder(note) ||
          note.id != noteId ||
          note.deletedAt != null) {
        continue;
      }
      final now = DateTime.now();
      final changed = note.copyWith(
        archivedAt: archived ? now : null,
        updatedAt: now,
        revision: note.revision + 1,
        syncState: _syncStateForLocalChange(note, deleted: false),
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

  Future<void> _performSeedIfEmpty() async {
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

  Future<int> _performCreateDemoNotes() async {
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

  Future<int> _performCreatePerformanceTestNotes({
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

  Future<void> reloadFromStorage() {
    final operation = _upsertQueue.then((_) async {
      await _waitForInitialRestore();
      if (!ref.mounted) return;
      _restoreFailed = false;
      await _restore();
    });
    _upsertQueue = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  /// Drop decrypted content immediately when private access changes. The
  /// encrypted records remain in storage and are restored on the next unlock.
  void concealPrivateNotes({
    String? exceptVaultId,
    Iterable<String> additionalVaultIds = const [],
  }) {
    _privateConcealVersion++;
    state = [
      for (final note in state)
        if (!isPrivateVaultId(note.vaultId) ||
            note.vaultId == exceptVaultId ||
            additionalVaultIds.contains(note.vaultId))
          note
        else
          _concealedPrivateNote(note),
    ];
  }

  NoteEntry _concealedPrivateNote(NoteEntry note) => NoteEntry(
    id: note.id,
    vaultId: note.vaultId,
    title: 'Locked private note',
    body: '',
    createdAt: note.createdAt,
    updatedAt: note.updatedAt,
    deletedAt: note.deletedAt,
    deviceId: 'locked-private-note',
    contentHash: note.contentHash,
    isPinned: note.isPinned,
    revision: note.revision,
    syncState: note.syncState,
  );

  Future<int> _performDeleteDemoNotes() async {
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

  Future<void> cleanupCommittedAttachmentDrafts(NoteEntry draft) async {
    if (await ref.read(noteEditorDraftStoreProvider).hasSavedDraft()) {
      return;
    }
    await _deleteAttachments(_attachmentsIn(draft).toList());
  }

  Future<int> clearStorageCaches() async {
    final materializedCacheBytes = await ref
        .read(encryptedAttachmentStoreProvider)
        .clearMaterializedCache();
    final pickedImagePickerCopyBytes = await _clearPickedImagePickerCopies();
    final deletedBytes = materializedCacheBytes + pickedImagePickerCopyBytes;
    ref.invalidate(storageUsageSummaryProvider);
    ref.invalidate(storageDiagnosticsSummaryProvider);
    return deletedBytes;
  }

  Future<void> createWidgetQuickCapture(String rawText) async {
    await _waitForInitialRestore();
    _ensureRestoreSucceeded();
    await _createExternalCapture(rawText: rawText);
  }

  Future<void> _sharedCaptureQueue = Future.value();

  Future<void> createSharedFileCapture({
    required String rawText,
    required List<QuickCaptureFile> files,
    String? shareId,
  }) {
    final operation = _sharedCaptureQueue.then((_) async {
      await _waitForInitialRestore();
      _ensureRestoreSucceeded();
      final noteId = shareId == null ? null : 'ios-share-$shareId';
      if (noteId != null && state.any((note) => note.id == noteId)) return;
      await _createExternalCapture(rawText: rawText, files: files, id: noteId);
    });
    _sharedCaptureQueue = operation.catchError((Object _, StackTrace _) {});
    return operation;
  }

  Future<void> _createExternalCapture({
    required String rawText,
    List<QuickCaptureFile> files = const <QuickCaptureFile>[],
    String? id,
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
      if (id != null && storedPath == null) {
        throw StateError('Shared attachment could not be stored');
      }
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
        } catch (_) {
          // File size is optional metadata; preview generation can continue.
        }
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
    final noteId = id ?? now.microsecondsSinceEpoch.toString();
    final captured = NoteEntry(
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
    );
    await upsert(captured);
    await cleanupCommittedAttachmentDrafts(captured);
    if (deferredPreviews.isNotEmpty) {
      unawaited(
        _applyDeferredPreviewsToNote(noteId, deferredPreviews).catchError((
          Object _,
          StackTrace _,
        ) {
          logDiagnostic(
            'media_import',
            'optional shared preview update failed',
          );
        }),
      );
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
      } catch (_) {
        // A failed optional preview should not prevent note attachment sync.
      }
    }
    if (resolved.isEmpty) {
      return;
    }
    await _exclusive(() async {
      if (!ref.mounted) return;
      final note = state.cast<NoteEntry?>().firstWhere(
        (n) => n?.id == noteId,
        orElse: () => null,
      );
      if (note == null ||
          note.deletedAt != null ||
          note.isPermanentlyDeleted ||
          _isLockedPrivatePlaceholder(note)) {
        return;
      }
      final store = ref.read(noteStoreProvider) as SyncV2NoteStore;
      for (final source in deferredPreviews.keys) {
        for (final type in AttachmentType.values) {
          final committed = store.committedDraftReference(
            note.vaultId,
            type,
            source,
          );
          if (committed != null && resolved[source] != null) {
            resolved[committed] = resolved[source]!;
          }
        }
      }
      NoteAttachment applyPreview(NoteAttachment a) {
        final preview = a.filePath != null ? resolved[a.filePath] : null;
        return preview != null ? a.copyWith(previewBytesBase64: preview) : a;
      }

      await _performUpsert(
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
    });
  }

  Future<void> _restore() async {
    final stopwatch = kDebugMode ? (Stopwatch()..start()) : null;
    final concealVersion = _privateConcealVersion;
    try {
      final workspace = ref.read(syncV2WorkspaceProvider);
      final sessionRevision = workspace.privateSessionRevision;
      final deletedSeedNoteIds = await _deletedSeedNoteIds();
      final restored = [
        ...await ref
            .read(noteStoreProvider)
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
      if (concealVersion != _privateConcealVersion ||
          sessionRevision != workspace.privateSessionRevision) {
        final session = ref.read(syncV2WorkspaceProvider).noteStoreSession;
        next = [
          for (final note in next)
            if (isPrivateVaultId(note.vaultId) &&
                (session == null ||
                    !session.profiles.containsKey(
                      SyncV2NoteStore.profileIdFor(session, note.vaultId),
                    )))
              _concealedPrivateNote(note)
            else
              note,
        ];
      }
      _sort(next);
      state = next;
      final purgedTrash = await _purgeTrashOlderThan(
        trashRetention,
        bestEffort: true,
      );
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

  Future<int> _purgeTrashOlderThan(
    Duration retention, {
    bool bestEffort = false,
  }) async {
    final cutoff = DateTime.now().subtract(retention);
    final expired = [
      for (final note in state)
        if (note.deletedAt != null &&
            note.syncState != NoteSyncState.conflict &&
            !note.isPermanentlyDeleted &&
            !_isLockedPrivatePlaceholder(note) &&
            note.deletedAt!.isBefore(cutoff))
          note,
    ];
    if (expired.isEmpty) {
      return 0;
    }
    var purged = 0;
    for (final note in expired) {
      try {
        await _purgeDeletedNote(note);
        purged++;
      } catch (_) {
        if (!bestEffort) rethrow;
        logDiagnostic('notes', 'Automatic trash cleanup deferred.');
      }
    }
    ref.invalidate(storageUsageSummaryProvider);
    if (purged > 0) logAudit('note_trash_purge', data: {'count': purged});
    return purged;
  }

  Future<void> _purgeDeletedNote(NoteEntry note) async {
    final store = ref.read(noteStoreProvider);
    final deletedAt = note.deletedAt!;
    final tombstone = NoteEntry(
      id: note.id,
      vaultId: note.vaultId,
      title: '',
      body: '',
      createdAt: deletedAt,
      updatedAt: deletedAt,
      deletedAt: deletedAt,
      revision: note.revision + 1,
      contentHash: permanentNoteDeletionHash,
      syncState: NoteSyncState.pendingDelete,
    );
    await store.saveOne(tombstone);
    if (!ref.mounted) return;
    state = [
      for (final entry in state) entry.id == note.id ? tombstone : entry,
    ];
    await _deleteAttachments([..._attachmentsIn(note)]);
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
      final saving = state
          .where((note) => !_isLockedPrivatePlaceholder(note))
          .toList();
      final saved = await ref
          .read(noteStoreProvider)
          .save(saving, preserveOmittedPrivateNotes: true);
      if (ref.mounted) {
        final replacements = {
          for (var i = 0; i < saving.length; i++)
            saving[i].id: (before: saving[i], after: saved[i]),
        };
        state = [
          for (final current in state)
            if (replacements[current.id] case final replacement?
                when identical(current, replacement.before))
              replacement.after
            else
              current,
        ];
      }

      ref.invalidate(storageUsageSummaryProvider);
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
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  // Above this count (or half the library), per-note transactions cost more
  // than one full save.

  // Persists only the given notes. Incremental saves never delete rows, so
  // this must only be used by callers that modify or add notes (sync merge,
  // queue/synced state flips, conflict resolution) — removals still need the
  // full _persist().

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
      final saved = await ref.read(noteStoreProvider).saveOne(note);
      if (ref.mounted) {
        state = [
          for (final current in state)
            identical(current, note) ? saved : current,
        ];
      }

      ref.invalidate(storageUsageSummaryProvider);
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
      Error.throwWithStackTrace(error, stackTrace);
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

  Future<void> _deleteAttachments(
    List<NoteAttachment> attachments, {
    Set<String>? additionalRetainedFilePaths,
    bool ignoreCurrentStateReferences = false,
  }) async {
    if (attachments.isEmpty) return;
    final attachmentStore = ref.read(encryptedAttachmentStoreProvider);
    // Attachment payloads are shared by imported notes.  A removal callback
    // often receives the previous note's attachments, so consult the whole
    // current state before deleting any path.  This also protects callers
    // that delete several notes in one operation.
    final retainedFilePaths = <String>{
      if (!ignoreCurrentStateReferences)
        for (final note in state) ..._attachmentFilePathsIn(note),
      ...?additionalRetainedFilePaths,
    };
    final deleted = <String>{};
    for (final attachment in attachments) {
      final filePath = attachment.filePath;
      if (filePath == null || filePath.isEmpty) {
        continue;
      }
      if (retainedFilePaths.contains(filePath)) {
        continue;
      }
      if (!deleted.add(filePath)) {
        continue;
      }
      await attachmentStore.deleteAttachment(filePath);
    }
  }

  NoteBlockType _blockTypeForAttachment(AttachmentType type) => switch (type) {
    AttachmentType.photo => NoteBlockType.photo,
    AttachmentType.video => NoteBlockType.video,
    AttachmentType.audio => NoteBlockType.audio,
    AttachmentType.file => NoteBlockType.file,
  };

  Future<NoteEntry> _prepareForSave(
    NoteEntry note, {
    NoteEntry? previous,
  }) async {
    await ref.read(autoTagRulesControllerProvider.notifier).restoreCompleted;
    final autoTagged = applyAutoTagRules(
      note,
      ref.read(autoTagRulesControllerProvider),
    );
    final deviceId =
        autoTagged.deviceId ??
        previous?.deviceId ??
        await ref.read(deviceIdentityStoreProvider).obtain();
    final createdAt = autoTagged.createdAt;
    final updatedAt = autoTagged.updatedAt ?? DateTime.now();
    final normalized = autoTagged.copyWith(
      createdAt: createdAt,
      updatedAt: updatedAt,
      deletedAt: null,
      deviceId: deviceId,
      revision: previous == null ? autoTagged.revision : previous.revision + 1,
      syncState: _syncStateForLocalChange(autoTagged, deleted: false),
    );
    final protected = await _protectAttachmentsForVault(normalized);
    return protected.copyWith(contentHash: _computeContentHash(protected));
  }

  NoteSyncState _syncStateForLocalChange(
    NoteEntry note, {
    required bool deleted,
  }) {
    return deleted ? NoteSyncState.pendingDelete : NoteSyncState.pendingUpload;
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
      'blocks': note.blocks.map(_blockContentHashPayload).toList(),
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

  Map<String, Object?> _blockContentHashPayload(NoteBlock block) {
    final attachment = block.attachment;
    return {
      'type': block.type.name,
      'text': block.text,
      'attachment': attachment == null
          ? null
          : {
              'type': attachment.type.name,
              'label': attachment.label,
              'filePath': attachment.filePath,
            },
    };
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

final _additionalUnlockedPrivateVaultIdsProvider =
    NotifierProvider<_AdditionalUnlockedPrivateVaultIds, List<String>>(
      _AdditionalUnlockedPrivateVaultIds.new,
    );

class _AdditionalUnlockedPrivateVaultIds extends Notifier<List<String>> {
  @override
  List<String> build() => const [];

  void replace(List<String> vaultIds) {
    state = List.unmodifiable(vaultIds);
  }
}

class UnlockedPrivateProfileVaultIdController extends Notifier<String?> {
  @override
  String? build() => null;

  void unlock(String vaultId, {List<String> additionalVaultIds = const []}) {
    final previousVaultId = state;
    ref
        .read(_additionalUnlockedPrivateVaultIdsProvider.notifier)
        .replace(additionalVaultIds);
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
    ref.read(syncV2WorkspaceProvider).lockPrivate();
    if (vaultId != null) {
      final filters = ref.read(searchFiltersControllerProvider);
      if (filters.vaultId == vaultId) {
        ref.read(searchFiltersControllerProvider.notifier).setVault(null);
      }
    }
    state = null;
    ref
        .read(_additionalUnlockedPrivateVaultIdsProvider.notifier)
        .replace(const []);
    if (vaultId != null) {
      ref.read(notesControllerProvider.notifier).concealPrivateNotes();
      logAudit('private_profile_lock', data: {'vaultId': vaultId});
    }
  }
}

final adminModeSessionControllerProvider =
    NotifierProvider<AdminModeSessionController, bool>(
      AdminModeSessionController.new,
    );

class AdminModeSessionController extends Notifier<bool> {
  int _operation = 0;

  @override
  bool build() => false;

  void syncWorkspaceSession() {
    {
      state = ref.read(syncV2WorkspaceProvider).adminUnlocked;
    }
  }

  /// The caller must complete device authentication before entering admin mode.
  Future<List<String>> unlock() async {
    return _unlockSyncV2();
  }

  /// v2: the device-remembered ADMIN key opens every profile. Without it, the
  /// workspace's own biometric unlock is used. Returns no missing profiles.
  Future<List<String>> _unlockSyncV2() async {
    final operation = ++_operation;
    final workspace = ref.read(syncV2WorkspaceProvider);
    workspace.diagnosticCode = null;
    ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    final revision = workspace.privateSessionRevision;
    bool active() =>
        ref.mounted &&
        operation == _operation &&
        revision == workspace.privateSessionRevision;

    // `unlockAdminFromSettings` requires this session to be active.
    state = true;
    try {
      var unlocked = await workspace.unlockAdminFromSettings();
      if (!active()) throw const SyncV2WorkspaceException('locked');
      if (!unlocked && workspace.biometricEnabled) {
        await workspace.unlockAdminBiometric();
        unlocked = workspace.adminUnlocked;
      }
      if (!active()) throw const SyncV2WorkspaceException('locked');
      if (!unlocked) {
        throw const SyncV2WorkspaceException('admin_required');
      }
      ref.read(searchFiltersControllerProvider.notifier).setVault(null);
      logAudit(
        'admin_mode_login',
        data: {'allProfilesReadable': true, 'profilesNeedingPassword': 0},
      );
      return const [];
    } catch (_) {
      if (ref.mounted && operation == _operation) {
        if (active()) {
          lock();
        } else {
          // A lifecycle observer may revoke workspace keys before the home
          // provider has an active session to observe. Reconcile the pending
          // UI grant without revoking a newer workspace session.
          syncWorkspaceSession();
        }
      }
      rethrow;
    }
  }

  Future<void> unlockWithAdminPassword(String password) async {
    final operation = ++_operation;
    final workspace = ref.read(syncV2WorkspaceProvider);
    final revision = workspace.privateSessionRevision;
    await workspace.unlockAdmin(password);
    if (!ref.mounted ||
        operation != _operation ||
        revision != workspace.privateSessionRevision) {
      return;
    }
    state = true;
    ref.read(searchFiltersControllerProvider.notifier).setVault(null);
    logAudit('admin_mode_login', data: {'backend': 'sync_v2'});
  }

  void lock({
    String? exceptVaultId,
    List<String> additionalVaultIds = const [],
  }) {
    _operation++;
    final changed = state;
    state = false;
    final workspace = ref.read(syncV2WorkspaceProvider);
    workspace.lockSettingsAdmin();
    workspace.lockPrivate();
    ref
        .read(notesControllerProvider.notifier)
        .concealPrivateNotes(
          exceptVaultId: exceptVaultId,
          additionalVaultIds: additionalVaultIds,
        );
    if (changed) {
      ref.read(searchFiltersControllerProvider.notifier).setVault(null);
      ref.read(selectedNoteIdProvider.notifier).select(null);
      logAudit('admin_mode_logout');
    }
  }
}

final privateProfileUnlockControllerProvider =
    NotifierProvider<PrivateProfileUnlockController, AsyncValue<void>>(
      PrivateProfileUnlockController.new,
    );

class PrivateProfileUnlockController extends Notifier<AsyncValue<void>> {
  int _operation = 0;

  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<UnlockProfileResult?> unlockWithPassword(String password) async {
    return _unlockSyncV2(password);
  }

  /// v2: every profile whose passcode matches opens together. A mismatch
  /// returns null without revealing whether any profile exists.
  Future<UnlockProfileResult?> _unlockSyncV2(String password) async {
    final operation = ++_operation;
    state = const AsyncLoading();
    final workspace = ref.read(syncV2WorkspaceProvider);
    int? revision;
    bool current() => ref.mounted && operation == _operation;
    try {
      ref.read(adminModeSessionControllerProvider.notifier).lock();
      ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
      workspace.lockPrivate();
      revision = workspace.privateSessionRevision;
      try {
        await workspace.unlockPrivate(password);
      } on SyncV2WorkspaceException catch (error) {
        if (!current()) return null;
        if (revision != workspace.privateSessionRevision) {
          state = const AsyncData(null);
          return null;
        }
        if (error.code == 'wrong_password') {
          state = const AsyncData(null);
          return null;
        }
        rethrow;
      }
      if (!current()) return null;
      if (revision != workspace.privateSessionRevision) {
        state = const AsyncData(null);
        return null;
      }
      final opened = [
        for (final profile in workspace.profiles)
          if (!profile.isNormal) profile,
      ];
      if (opened.isEmpty) {
        state = const AsyncData(null);
        return null;
      }
      final result = UnlockProfileResult(
        vaultId: opened.first.id,
        label: opened.first.name,
        additionalVaultIds: [for (final p in opened.skip(1)) p.id],
      );
      ref
          .read(unlockedPrivateProfileVaultIdProvider.notifier)
          .unlock(
            result.vaultId,
            additionalVaultIds: result.additionalVaultIds,
          );
      await ref.read(notesControllerProvider.notifier).reloadFromStorage();
      if (!current()) return null;
      if (revision != workspace.privateSessionRevision) {
        state = const AsyncData(null);
        return null;
      }
      state = const AsyncData(null);
      return result;
    } catch (error, stackTrace) {
      if (!current()) return null;
      if (revision != workspace.privateSessionRevision) {
        state = const AsyncData(null);
        return null;
      }
      ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
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
  @override
  List<PrivateMemoProfile> build() {
    // v2 profile names are only readable while unlocked, so the list
    // follows the workspace's unlocked profiles.
    final workspace = ref.watch(syncV2WorkspaceProvider);
    void onChange() => state = _syncV2Profiles(workspace);
    workspace.addListener(onChange);
    ref.onDispose(() => workspace.removeListener(onChange));
    return _syncV2Profiles(workspace);
  }

  static List<PrivateMemoProfile> _syncV2Profiles(
    SyncV2WorkspaceController workspace,
  ) => [
    for (final profile in workspace.profiles)
      if (!profile.isNormal && profile.id.startsWith(customPrivateVaultPrefix))
        PrivateMemoProfile(
          id: profile.id.substring(customPrivateVaultPrefix.length),
          name: profile.name,
        ),
  ];

  Future<void> refresh() async {
    state = _syncV2Profiles(ref.read(syncV2WorkspaceProvider));
    return;
  }

  static const syncV2AdminRequiredMessage =
      'Unlock administrator mode to add a private profile.';

  /// v2: wrapping a new profile key needs the ADMIN key, so creation enters
  /// administrator mode first (device-remembered key or biometrics).
  Future<String?> _addSyncV2Profile(String name, String password) async {
    final workspace = ref.read(syncV2WorkspaceProvider);
    if (!workspace.adminUnlocked) {
      if (!workspace.biometricEnabled) return syncV2AdminRequiredMessage;
      // Same gate as the settings screen: device authentication first. The
      // in-process stub (development only) runs on web without device auth.
      final authenticated =
          (isDevelopmentFlavor && noteBackend == 'v2-local') ||
          await ref
              .read(deviceAuthControllerProvider.notifier)
              .authenticate(
                reason: 'Enter admin mode to add a private profile',
              );
      if (!authenticated) return syncV2AdminRequiredMessage;
      try {
        await ref.read(adminModeSessionControllerProvider.notifier).unlock();
      } on Object {
        return syncV2AdminRequiredMessage;
      }
    }
    if (!workspace.adminUnlocked) return syncV2AdminRequiredMessage;
    try {
      await workspace.createProfile(name.trim(), password);
    } on ArgumentError catch (error) {
      return '${error.message}';
    } on SyncV2WorkspaceException catch (error) {
      if (error.code == 'duplicate_passcode') {
        return 'Use a passcode different from the administrator passcode.';
      }
      return error.code == 'admin_required'
          ? syncV2AdminRequiredMessage
          : 'Could not create the profile (${error.code}).';
    }
    logAudit('private_profile_create', data: {'backend': 'sync_v2'});
    await refresh();
    return null;
  }

  Future<String?> addProfile({
    required String name,
    required String password,
  }) async {
    return _addSyncV2Profile(name, password);
  }

  Future<bool> deleteProfile(String id) async {
    if (!ref.read(adminModeSessionControllerProvider)) {
      return false;
    }
    final vaultId = '$customPrivateVaultPrefix$id';

    try {
      await ref.read(syncV2WorkspaceProvider).deleteProfile(vaultId);
    } on SyncV2WorkspaceException {
      return false;
    }
    await ref
        .read(profileColorThemeControllerProvider.notifier)
        .clearTheme(vaultId);
    if (ref.read(searchFiltersControllerProvider).vaultId == vaultId) {
      ref.read(searchFiltersControllerProvider.notifier).setVault(null);
    }
    await refresh();
    logAudit(
      'private_profile_delete',
      data: {'vaultId': vaultId, 'backend': 'sync_v2'},
    );
    return true;
  }

  Future<bool> renameProfile({required String id, required String name}) async {
    {
      if (!ref.read(adminModeSessionControllerProvider)) return false;
      try {
        await ref
            .read(syncV2WorkspaceProvider)
            .renameProfile('$customPrivateVaultPrefix$id', name);
        await refresh();
        return true;
      } on SyncV2WorkspaceException {
        return false;
      }
    }
  }

  Future<String?> updateProfilePassword({
    required String id,
    required String password,
  }) async {
    try {
      await ref
          .read(syncV2WorkspaceProvider)
          .changeProfilePassword('$customPrivateVaultPrefix$id', password);
    } on ArgumentError catch (error) {
      return '${error.message}';
    } on SyncV2WorkspaceException catch (error) {
      return error.code == 'duplicate_passcode'
          ? 'Use a passcode different from the administrator passcode.'
          : 'Could not change the passcode (${error.code}).';
    }
    return null;
  }
}

final accessiblePrivateVaultIdsProvider = Provider<List<String>>((ref) {
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  final profiles = ref.watch(privateMemoProfilesControllerProvider);

  if (adminMode) {
    return [for (final profile in profiles) profile.vaultId];
  }
  return [
    ?unlockedVaultId,
    ...ref.watch(_additionalUnlockedPrivateVaultIdsProvider),
  ];
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
  final profiles = ref.watch(privateMemoProfilesControllerProvider);
  final match = profiles.where((profile) => profile.vaultId == unlockedVaultId);
  if (match.isEmpty) {
    return null;
  }
  return match.first.name;
});

final privacyScreenActiveProvider = Provider<bool>((ref) {
  final adminMode = ref.watch(adminModeSessionControllerProvider);
  final unlockedVaultId = ref.watch(unlockedPrivateProfileVaultIdProvider);
  return adminMode || unlockedVaultId != null;
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
      if (note.deletedAt != null &&
          !note.isPermanentlyDeleted &&
          visibleIds.contains(note.vaultId))
        note,
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
    this.preferredLanguageCode,
  });

  final String title;
  final String body;
  final List<String> existingTags;
  final List<String> knownTags;
  final List<String> attachmentLabels;
  final String? preferredLanguageCode;

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
    this._channel = const MethodChannel('org.ruhenheim.himemo/intelligence'),
  });

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
      final response = await _channel.invokeMapMethod<String, Object?>(
        'suggestTags',
        {
          'title': request.title,
          'body': request.body,
          'existingTags': request.existingTags,
          'knownTags': request.knownTags,
          'knownTagCounts': request.knownTagCounts,
          'attachmentLabels': request.attachmentLabels,
          'preferredLanguageCode': request.preferredLanguageCode,
        },
      );
      final nativeTags = sanitizeSuggestedTags([
        for (final tag in response?['tags'] as List? ?? const []) '$tag',
      ], existingTags: request.existingTags);
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

@visibleForTesting
List<String> sanitizeSuggestedTags(
  Iterable<String> values, {
  Iterable<String> existingTags = const <String>[],
  int maxTags = 5,
}) {
  final existingKeys = {
    for (final tag in existingTags) canonicalizeNoteTag(tag),
  };
  const rejectedKeys = {
    'json',
    '```',
    '```json',
    'tags',
    'tag',
    'null',
    'none',
  };
  final expanded = <String>[];
  for (final raw in values) {
    var value = raw
        .replaceAll(RegExp(r'```\s*json', caseSensitive: false), '')
        .replaceAll(RegExp(r'```+'), '')
        .replaceAll('[', '')
        .replaceAll(']', '')
        .replaceAll('"', '')
        .replaceAll("'", '')
        .replaceAll(RegExp(r'[\n\r，、]'), ',')
        .trim();
    if (value.contains(':')) {
      final parts = value.split(':');
      if (parts.first.trim().toLowerCase() == 'tags') {
        value = parts.skip(1).join(':').trim();
      }
    }
    expanded.addAll(
      value
          .split(RegExp(r'[,，、\n\r]'))
          .map((entry) => entry.trim())
          .where((entry) => entry.isNotEmpty),
    );
  }

  final seen = <String>{};
  final tags = <String>[];
  for (final raw in expanded) {
    final normalized = normalizeNoteTag(
      raw.replaceAll(RegExp(r'^[\-\*\d\.\)\s]+'), ''),
    );
    final key = canonicalizeNoteTag(normalized);
    if (normalized.isEmpty ||
        key.isEmpty ||
        existingKeys.contains(key) ||
        rejectedKeys.contains(key) ||
        normalized.contains('```') ||
        key.contains('```') ||
        normalized.startsWith('{') ||
        normalized.endsWith('}') ||
        !seen.add(key)) {
      continue;
    }
    tags.add(normalized.length > 24 ? normalized.substring(0, 24) : normalized);
    if (tags.length >= maxTags) {
      break;
    }
  }
  return List.unmodifiable(tags);
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
  (ref) => NoteEditorDraftStore(
    encryptionService: ref.watch(encryptionServiceProvider),
    protectAttachments: (snapshot) async {
      final store = ref.read(encryptedAttachmentStoreProvider);
      final seen = <String>{};
      for (final attachment in [
        ...snapshot.quickAttachments,
        for (final block in snapshot.richBlocks)
          if (block.attachment != null) block.attachment!,
      ]) {
        final source = attachment.filePath;
        if (source != null && seen.add(source)) {
          await store.protectAttachmentForVault(
            source,
            type: attachment.type,
            vaultId: snapshot.vaultId,
          );
        }
      }
    },
    storageKey: 'notes.editor_draft.v2',
    keyForVault: (vaultId) async {
      final session = ref.read(syncV2WorkspaceProvider).noteStoreSession;
      if (session == null) return null;
      return session
          .profiles[SyncV2NoteStore.profileIdFor(session, vaultId)]
          ?.key;
    },
  ),
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
