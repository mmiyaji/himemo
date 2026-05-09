import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'google_drive_sync_transport.dart';

class SyncBundleState {
  const SyncBundleState({
    this.lastRemoteFileId,
    this.lastRemoteModifiedAt,
    this.lastRemoteDeviceId,
    this.lastUploadedAt,
    this.lastAppliedAt,
  });

  final String? lastRemoteFileId;
  final DateTime? lastRemoteModifiedAt;
  final String? lastRemoteDeviceId;
  final DateTime? lastUploadedAt;
  final DateTime? lastAppliedAt;

  SyncBundleState copyWith({
    String? lastRemoteFileId,
    DateTime? lastRemoteModifiedAt,
    String? lastRemoteDeviceId,
    DateTime? lastUploadedAt,
    DateTime? lastAppliedAt,
  }) {
    return SyncBundleState(
      lastRemoteFileId: lastRemoteFileId ?? this.lastRemoteFileId,
      lastRemoteModifiedAt: lastRemoteModifiedAt ?? this.lastRemoteModifiedAt,
      lastRemoteDeviceId: lastRemoteDeviceId ?? this.lastRemoteDeviceId,
      lastUploadedAt: lastUploadedAt ?? this.lastUploadedAt,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastRemoteFileId': lastRemoteFileId,
      'lastRemoteModifiedAt': _toUtcIso8601String(lastRemoteModifiedAt),
      'lastRemoteDeviceId': lastRemoteDeviceId,
      'lastUploadedAt': _toUtcIso8601String(lastUploadedAt),
      'lastAppliedAt': _toUtcIso8601String(lastAppliedAt),
    };
  }

  static SyncBundleState fromJson(Map<String, dynamic> json) {
    return SyncBundleState(
      lastRemoteFileId: json['lastRemoteFileId'] as String?,
      lastRemoteModifiedAt: _parseUtc(json['lastRemoteModifiedAt'] as String?),
      lastRemoteDeviceId: json['lastRemoteDeviceId'] as String?,
      lastUploadedAt: _parseUtc(json['lastUploadedAt'] as String?),
      lastAppliedAt: _parseUtc(json['lastAppliedAt'] as String?),
    );
  }
}

class SyncBundleStateStore {
  SyncBundleStateStore({
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.storageKey = 'sync.bundle_state.v1',
  }) : _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String storageKey;

  Future<SyncBundleState> read() async {
    final prefs = await _sharedPreferencesProvider();
    final stored = prefs.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return const SyncBundleState();
    }
    return SyncBundleState.fromJson(
      Map<String, dynamic>.from(jsonDecode(stored) as Map),
    );
  }

  Future<void> write(SyncBundleState state) async {
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString(storageKey, jsonEncode(state.toJson()));
  }

  Future<void> recordRemoteStatus(RemoteSyncBundleStatus remoteStatus) async {
    final current = await read();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus.fileId,
        lastRemoteModifiedAt: remoteStatus.modifiedAt?.toUtc(),
        lastRemoteDeviceId: remoteStatus.deviceId,
      ),
    );
  }

  Future<void> recordUpload(RemoteSyncBundleStatus remoteStatus) async {
    final current = await read();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus.fileId,
        lastRemoteModifiedAt: remoteStatus.modifiedAt?.toUtc(),
        lastRemoteDeviceId: remoteStatus.deviceId,
        lastUploadedAt: DateTime.now().toUtc(),
      ),
    );
  }

  Future<void> recordApply(RemoteSyncBundleStatus? remoteStatus) async {
    final current = await read();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus?.fileId ?? current.lastRemoteFileId,
        lastRemoteModifiedAt:
            remoteStatus?.modifiedAt?.toUtc() ?? current.lastRemoteModifiedAt,
        lastRemoteDeviceId:
            remoteStatus?.deviceId ?? current.lastRemoteDeviceId,
        lastAppliedAt: DateTime.now().toUtc(),
      ),
    );
  }
}

String? _toUtcIso8601String(DateTime? value) =>
    value?.toUtc().toIso8601String();

DateTime? _parseUtc(String? value) {
  if (value == null || value.isEmpty) {
    return null;
  }
  return DateTime.parse(value).toUtc();
}
