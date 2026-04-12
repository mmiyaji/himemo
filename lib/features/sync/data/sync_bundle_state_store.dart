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
      'lastRemoteModifiedAt': lastRemoteModifiedAt?.toIso8601String(),
      'lastRemoteDeviceId': lastRemoteDeviceId,
      'lastUploadedAt': lastUploadedAt?.toIso8601String(),
      'lastAppliedAt': lastAppliedAt?.toIso8601String(),
    };
  }

  static SyncBundleState fromJson(Map<String, dynamic> json) {
    return SyncBundleState(
      lastRemoteFileId: json['lastRemoteFileId'] as String?,
      lastRemoteModifiedAt: json['lastRemoteModifiedAt'] == null
          ? null
          : DateTime.parse(json['lastRemoteModifiedAt'] as String),
      lastRemoteDeviceId: json['lastRemoteDeviceId'] as String?,
      lastUploadedAt: json['lastUploadedAt'] == null
          ? null
          : DateTime.parse(json['lastUploadedAt'] as String),
      lastAppliedAt: json['lastAppliedAt'] == null
          ? null
          : DateTime.parse(json['lastAppliedAt'] as String),
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
        lastRemoteModifiedAt: remoteStatus.modifiedAt,
        lastRemoteDeviceId: remoteStatus.deviceId,
      ),
    );
  }

  Future<void> recordUpload(RemoteSyncBundleStatus remoteStatus) async {
    final current = await read();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus.fileId,
        lastRemoteModifiedAt: remoteStatus.modifiedAt,
        lastRemoteDeviceId: remoteStatus.deviceId,
        lastUploadedAt: DateTime.now(),
      ),
    );
  }

  Future<void> recordApply(RemoteSyncBundleStatus? remoteStatus) async {
    final current = await read();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus?.fileId ?? current.lastRemoteFileId,
        lastRemoteModifiedAt:
            remoteStatus?.modifiedAt ?? current.lastRemoteModifiedAt,
        lastRemoteDeviceId:
            remoteStatus?.deviceId ?? current.lastRemoteDeviceId,
        lastAppliedAt: DateTime.now(),
      ),
    );
  }
}
