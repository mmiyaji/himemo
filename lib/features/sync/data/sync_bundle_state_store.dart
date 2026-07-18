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
    this.lastAppliedRemoteFileId,
    this.lastAppliedRemoteModifiedAt,
    this.lastFullUploadedAt,
    this.deltaUploadsSinceFull = 0,
  });

  final String? lastRemoteFileId;
  final DateTime? lastRemoteModifiedAt;
  final String? lastRemoteDeviceId;
  final DateTime? lastUploadedAt;
  final DateTime? lastAppliedAt;

  /// The most recent remote bundle this device has actually applied locally
  /// (or produced itself via upload). Unlike [lastRemoteFileId], which is
  /// refreshed on every status check, this anchor only moves when the local
  /// notes are known to contain that bundle's changes — it is what the delta
  /// sync walk uses to decide which remote bundles still need to be applied.
  final String? lastAppliedRemoteFileId;
  final DateTime? lastAppliedRemoteModifiedAt;

  /// When this device last uploaded a full snapshot bundle, and the number of
  /// delta bundles uploaded since. Used to schedule periodic full snapshots
  /// so remote history can converge and be pruned.
  final DateTime? lastFullUploadedAt;
  final int deltaUploadsSinceFull;

  SyncBundleState copyWith({
    String? lastRemoteFileId,
    DateTime? lastRemoteModifiedAt,
    String? lastRemoteDeviceId,
    DateTime? lastUploadedAt,
    DateTime? lastAppliedAt,
    String? lastAppliedRemoteFileId,
    DateTime? lastAppliedRemoteModifiedAt,
    DateTime? lastFullUploadedAt,
    int? deltaUploadsSinceFull,
  }) {
    return SyncBundleState(
      lastRemoteFileId: lastRemoteFileId ?? this.lastRemoteFileId,
      lastRemoteModifiedAt: lastRemoteModifiedAt ?? this.lastRemoteModifiedAt,
      lastRemoteDeviceId: lastRemoteDeviceId ?? this.lastRemoteDeviceId,
      lastUploadedAt: lastUploadedAt ?? this.lastUploadedAt,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
      lastAppliedRemoteFileId:
          lastAppliedRemoteFileId ?? this.lastAppliedRemoteFileId,
      lastAppliedRemoteModifiedAt:
          lastAppliedRemoteModifiedAt ?? this.lastAppliedRemoteModifiedAt,
      lastFullUploadedAt: lastFullUploadedAt ?? this.lastFullUploadedAt,
      deltaUploadsSinceFull:
          deltaUploadsSinceFull ?? this.deltaUploadsSinceFull,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastRemoteFileId': lastRemoteFileId,
      'lastRemoteModifiedAt': _toUtcIso8601String(lastRemoteModifiedAt),
      'lastRemoteDeviceId': lastRemoteDeviceId,
      'lastUploadedAt': _toUtcIso8601String(lastUploadedAt),
      'lastAppliedAt': _toUtcIso8601String(lastAppliedAt),
      'lastAppliedRemoteFileId': lastAppliedRemoteFileId,
      'lastAppliedRemoteModifiedAt': _toUtcIso8601String(
        lastAppliedRemoteModifiedAt,
      ),
      'lastFullUploadedAt': _toUtcIso8601String(lastFullUploadedAt),
      'deltaUploadsSinceFull': deltaUploadsSinceFull,
    };
  }

  static SyncBundleState fromJson(Map<String, dynamic> json) {
    return SyncBundleState(
      lastRemoteFileId: json['lastRemoteFileId'] as String?,
      lastRemoteModifiedAt: _parseUtc(json['lastRemoteModifiedAt'] as String?),
      lastRemoteDeviceId: json['lastRemoteDeviceId'] as String?,
      lastUploadedAt: _parseUtc(json['lastUploadedAt'] as String?),
      lastAppliedAt: _parseUtc(json['lastAppliedAt'] as String?),
      lastAppliedRemoteFileId: json['lastAppliedRemoteFileId'] as String?,
      lastAppliedRemoteModifiedAt: _parseUtc(
        json['lastAppliedRemoteModifiedAt'] as String?,
      ),
      lastFullUploadedAt: _parseUtc(json['lastFullUploadedAt'] as String?),
      deltaUploadsSinceFull:
          (json['deltaUploadsSinceFull'] as num?)?.toInt() ?? 0,
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

  Future<void> recordUpload(
    RemoteSyncBundleStatus remoteStatus, {
    bool fullSnapshot = true,
    bool advanceAppliedAnchor = true,
  }) async {
    final current = await read();
    final now = DateTime.now().toUtc();
    await write(
      current.copyWith(
        lastRemoteFileId: remoteStatus.fileId,
        lastRemoteModifiedAt: remoteStatus.modifiedAt?.toUtc(),
        lastRemoteDeviceId: remoteStatus.deviceId,
        lastUploadedAt: now,
        // Regular uploads are based on an already-applied remote anchor. A
        // conflict-resolution delta can intentionally be appended without
        // applying unrelated remote changes first, so it must preserve the
        // previous apply anchor for the next history walk.
        lastAppliedRemoteFileId: advanceAppliedAnchor
            ? remoteStatus.fileId
            : current.lastAppliedRemoteFileId,
        lastAppliedRemoteModifiedAt: advanceAppliedAnchor
            ? remoteStatus.modifiedAt?.toUtc()
            : current.lastAppliedRemoteModifiedAt,
        lastFullUploadedAt: fullSnapshot ? now : current.lastFullUploadedAt,
        deltaUploadsSinceFull: fullSnapshot
            ? 0
            : current.deltaUploadsSinceFull + 1,
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
        lastAppliedRemoteFileId:
            remoteStatus?.fileId ?? current.lastAppliedRemoteFileId,
        lastAppliedRemoteModifiedAt:
            remoteStatus?.modifiedAt?.toUtc() ??
            current.lastAppliedRemoteModifiedAt,
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
