import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../security/data/secure_key_value_store.dart';
import '../../security/data/storage_serial_executor.dart';

import 'google_drive_sync_transport.dart';

class SyncBundleState {
  const SyncBundleState({
    this.lastRemoteFileId,
    this.lastRemoteModifiedAt,
    this.lastRemoteDeviceId,
    this.lastUploadedAt,
    this.lastUploadedRemoteFileId,
    this.lastAppliedAt,
    this.lastAppliedRemoteFileId,
    this.lastAppliedRemoteModifiedAt,
    this.lastFullUploadedAt,
    this.deltaUploadsSinceFull = 0,
    this.appliedRemoteFileIds,
  });

  final String? lastRemoteFileId;
  final DateTime? lastRemoteModifiedAt;
  final String? lastRemoteDeviceId;
  final DateTime? lastUploadedAt;
  final String? lastUploadedRemoteFileId;
  final DateTime? lastAppliedAt;

  /// The most recent remote bundle this device has actually applied locally
  /// in an ordered history walk. Own uploads are acknowledged during that
  /// walk too, rather than advancing past unseen records at publication time.
  /// Unlike [lastRemoteFileId], which is
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

  /// Exact bundle IDs already represented locally. Null means legacy state
  /// with unknown coverage; an empty set means known to have applied none.
  final Set<String>? appliedRemoteFileIds;

  SyncBundleState copyWith({
    String? lastRemoteFileId,
    DateTime? lastRemoteModifiedAt,
    String? lastRemoteDeviceId,
    DateTime? lastUploadedAt,
    String? lastUploadedRemoteFileId,
    DateTime? lastAppliedAt,
    String? lastAppliedRemoteFileId,
    DateTime? lastAppliedRemoteModifiedAt,
    DateTime? lastFullUploadedAt,
    int? deltaUploadsSinceFull,
    Set<String>? appliedRemoteFileIds,
  }) {
    return SyncBundleState(
      lastRemoteFileId: lastRemoteFileId ?? this.lastRemoteFileId,
      lastRemoteModifiedAt: lastRemoteModifiedAt ?? this.lastRemoteModifiedAt,
      lastRemoteDeviceId: lastRemoteDeviceId ?? this.lastRemoteDeviceId,
      lastUploadedAt: lastUploadedAt ?? this.lastUploadedAt,
      lastUploadedRemoteFileId:
          lastUploadedRemoteFileId ?? this.lastUploadedRemoteFileId,
      lastAppliedAt: lastAppliedAt ?? this.lastAppliedAt,
      lastAppliedRemoteFileId:
          lastAppliedRemoteFileId ?? this.lastAppliedRemoteFileId,
      lastAppliedRemoteModifiedAt:
          lastAppliedRemoteModifiedAt ?? this.lastAppliedRemoteModifiedAt,
      lastFullUploadedAt: lastFullUploadedAt ?? this.lastFullUploadedAt,
      deltaUploadsSinceFull:
          deltaUploadsSinceFull ?? this.deltaUploadsSinceFull,
      appliedRemoteFileIds: appliedRemoteFileIds ?? this.appliedRemoteFileIds,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'lastRemoteFileId': lastRemoteFileId,
      'lastRemoteModifiedAt': _toUtcIso8601String(lastRemoteModifiedAt),
      'lastRemoteDeviceId': lastRemoteDeviceId,
      'lastUploadedAt': _toUtcIso8601String(lastUploadedAt),
      'lastUploadedRemoteFileId': lastUploadedRemoteFileId,
      'lastAppliedAt': _toUtcIso8601String(lastAppliedAt),
      'lastAppliedRemoteFileId': lastAppliedRemoteFileId,
      'lastAppliedRemoteModifiedAt': _toUtcIso8601String(
        lastAppliedRemoteModifiedAt,
      ),
      'lastFullUploadedAt': _toUtcIso8601String(lastFullUploadedAt),
      'deltaUploadsSinceFull': deltaUploadsSinceFull,
      if (appliedRemoteFileIds != null)
        'appliedRemoteFileIds': appliedRemoteFileIds!.toList()..sort(),
    };
  }

  static SyncBundleState fromJson(Map<String, dynamic> json) {
    final rawIds = json['appliedRemoteFileIds'];
    Set<String>? knownIds;
    if (rawIds != null) {
      if (rawIds is! List || rawIds.any((id) => id is! String || id.isEmpty)) {
        throw const FormatException('Invalid applied remote file IDs.');
      }
      knownIds = rawIds.cast<String>().toSet();
      if (knownIds.length != rawIds.length) {
        throw const FormatException('Duplicate applied remote file IDs.');
      }
    }
    return SyncBundleState(
      lastRemoteFileId: json['lastRemoteFileId'] as String?,
      lastRemoteModifiedAt: _parseUtc(json['lastRemoteModifiedAt'] as String?),
      lastRemoteDeviceId: json['lastRemoteDeviceId'] as String?,
      lastUploadedAt: _parseUtc(json['lastUploadedAt'] as String?),
      lastUploadedRemoteFileId: json['lastUploadedRemoteFileId'] as String?,
      lastAppliedAt: _parseUtc(json['lastAppliedAt'] as String?),
      lastAppliedRemoteFileId: json['lastAppliedRemoteFileId'] as String?,
      lastAppliedRemoteModifiedAt: _parseUtc(
        json['lastAppliedRemoteModifiedAt'] as String?,
      ),
      lastFullUploadedAt: _parseUtc(json['lastFullUploadedAt'] as String?),
      deltaUploadsSinceFull:
          (json['deltaUploadsSinceFull'] as num?)?.toInt() ?? 0,
      appliedRemoteFileIds: knownIds == null
          ? null
          : Set.unmodifiable(knownIds),
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
    await _serialized(() async {
      final current = await read();
      await write(
        current.copyWith(
          lastRemoteFileId: remoteStatus.fileId,
          lastRemoteModifiedAt: remoteStatus.modifiedAt?.toUtc(),
          lastRemoteDeviceId: remoteStatus.deviceId,
        ),
      );
    });
  }

  Future<void> recordUpload(
    RemoteSyncBundleStatus remoteStatus, {
    bool fullSnapshot = true,
    bool advanceAppliedAnchor = false,
  }) async {
    await _serialized(() async {
      final current = await read();
      final now = DateTime.now().toUtc();
      final known = current.appliedRemoteFileIds;
      await write(
        current.copyWith(
          lastRemoteFileId: remoteStatus.fileId,
          lastRemoteModifiedAt: remoteStatus.modifiedAt?.toUtc(),
          lastRemoteDeviceId: remoteStatus.deviceId,
          lastUploadedAt: now,
          lastUploadedRemoteFileId: remoteStatus.fileId,
          // Publishing is not an application of remote history. Preserve the
          // anchor by default so concurrent records are replayed next time.
          lastAppliedRemoteFileId: current.lastAppliedRemoteFileId,
          lastAppliedRemoteModifiedAt: current.lastAppliedRemoteModifiedAt,
          appliedRemoteFileIds: known == null
              ? null
              : {...known, remoteStatus.fileId},
          lastFullUploadedAt: fullSnapshot ? now : current.lastFullUploadedAt,
          deltaUploadsSinceFull: fullSnapshot
              ? 0
              : current.deltaUploadsSinceFull + 1,
        ),
      );
    });
  }

  Future<void> recordApply(
    RemoteSyncBundleStatus? remoteStatus, {
    Set<String> coveredRemoteFileIds = const <String>{},
    bool advanceAnchor = true,
  }) async {
    await _serialized(() async {
      final current = await read();
      final known = <String>{
        ...?current.appliedRemoteFileIds,
        ...coveredRemoteFileIds,
      };
      if (remoteStatus != null) known.add(remoteStatus.fileId);
      await write(
        current.copyWith(
          lastRemoteFileId: remoteStatus?.fileId ?? current.lastRemoteFileId,
          lastRemoteModifiedAt:
              remoteStatus?.modifiedAt?.toUtc() ?? current.lastRemoteModifiedAt,
          lastRemoteDeviceId:
              remoteStatus?.deviceId ?? current.lastRemoteDeviceId,
          lastAppliedAt: DateTime.now().toUtc(),
          lastAppliedRemoteFileId: advanceAnchor
              ? remoteStatus?.fileId ?? current.lastAppliedRemoteFileId
              : current.lastAppliedRemoteFileId,
          lastAppliedRemoteModifiedAt: advanceAnchor
              ? remoteStatus?.modifiedAt?.toUtc() ??
                    current.lastAppliedRemoteModifiedAt
              : current.lastAppliedRemoteModifiedAt,
          appliedRemoteFileIds: known,
        ),
      );
    });
  }

  Future<void> _serialized(Future<void> Function() operation) =>
      StorageSerialExecutor.run(
        PreferencesKeyValueStore(),
        storageKey,
        operation,
      );

  /// Bounds the local exact-ID set to IDs still present in fetched remote
  /// history. Call only after a complete history listing.
  Future<void> retainAppliedIds(Set<String> liveRemoteFileIds) async {
    await _serialized(() async {
      final current = await read();
      final known = current.appliedRemoteFileIds;
      if (known == null) return;
      await write(
        current.copyWith(
          appliedRemoteFileIds: known.intersection(liveRemoteFileIds),
        ),
      );
    });
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
