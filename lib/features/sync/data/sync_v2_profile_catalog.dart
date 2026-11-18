import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../security/data/authentication_throttle.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_note_repository.dart';

class SyncV2ProfileCatalogRecord {
  SyncV2ProfileCatalogRecord(
    this.noteId,
    this.wrapped,
    this.encryptedName,
    Set<String> headIds,
  ) : headIds = Set.unmodifiable(headIds);
  final String noteId;
  final SyncV2WrappedProfileKey wrapped;
  final String encryptedName;
  final Set<String> headIds;
}

class SyncV2ProfileCatalogConflict {
  SyncV2ProfileCatalogConflict({
    required this.profileId,
    required this.noteId,
    required Set<String> headIds,
    required List<SyncV2ProfileCatalogRecord> versions,
  }) : headIds = Set.unmodifiable(headIds),
       versions = List.unmodifiable(versions);
  final String profileId, noteId;
  final Set<String> headIds;
  final List<SyncV2ProfileCatalogRecord> versions;
}

class SyncV2UnlockedProfile {
  SyncV2UnlockedProfile({required this.name, required this.access});
  final String name;
  final SyncV2UnlockedProfileKey access;
  String get id => access.profileId;
  void destroy() => access.destroy();
}

/// The catalog is itself ordinary encrypted normal-profile note history.
/// Names have a second encryption layer requiring each private profile key.
class SyncV2ProfileCatalog {
  SyncV2ProfileCatalog(
    SyncV2Inbox inbox,
    this._repository,
    this._encryption,
    this._store, {
    required this.generationId,
    required this.syncKey,
    required this.normalAccess,
  });
  final SyncV2NoteRepository _repository;
  final EncryptionService _encryption;
  final SecureKeyValueStore _store;
  final String generationId;
  final SecretKey syncKey;
  final SyncV2UnlockedProfileKey normalAccess;
  SyncV2ProfileKeys get _keys => SyncV2ProfileKeys(_encryption);
  String _random() => _encryption
      .generateKeyBytes(length: 16)
      .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
      .join();

  SyncV2ProfileCatalogRecord _parse(
    String noteId,
    Map<String, Object?> body,
    Set<String> heads,
  ) {
    if (body.length != 3 ||
        body['type'] != 'profile-key' ||
        body['wrapped'] is! Map ||
        body['name'] is! String) {
      throw const FormatException('Invalid private profile catalog record');
    }
    final wrapped = SyncV2WrappedProfileKey.fromJson(
      Map<String, dynamic>.from(body['wrapped'] as Map),
    );
    if (!RegExp(r'^private_profile:[a-f0-9]{32}$')
        .hasMatch(wrapped.profileId)) {
      throw const FormatException('Invalid private profile identity');
    }
    return SyncV2ProfileCatalogRecord(
      noteId,
      wrapped,
      body['name'] as String,
      heads,
    );
  }

  Future<
    ({
      List<SyncV2ProfileCatalogRecord> records,
      List<SyncV2ProfileCatalogConflict> conflicts,
      bool incomplete,
    })
  >
  _read() async {
    final notes = await _repository.readProfile(
      generationId: generationId,
      profileId: normalAccess.profileId,
      syncKey: syncKey,
      profileKey: normalAccess,
      noteIdPrefix: 'profile_',
    );
    final records = <SyncV2ProfileCatalogRecord>[];
    final conflicts = <SyncV2ProfileCatalogConflict>[];
    final seen = <String>{};
    var incomplete = false;
    for (final entry in notes.entries) {
      final snapshot = entry.value;
      final versions = [
        for (final version in snapshot.versions)
          if (!version.isDeleted && version.body != null)
            _parse(entry.key, version.body!, snapshot.headIds),
      ];
      final identities = versions
          .map((version) => version.wrapped.profileId)
          .toSet();
      if (identities.length > 1 || identities.any((id) => !seen.add(id))) {
        throw const FormatException('Conflicting private profile identity');
      }
      // An incomplete catalog note cannot be authenticated or repaired yet.
      if (!snapshot.canCompareVersions) {
        incomplete = true;
        continue;
      }
      if (versions.isEmpty) continue;
      if (snapshot.hasConflict) {
        // Administrator recovery can also revive a catalog entry whose known
        // heads include a tombstone, using its surviving authenticated key.
        conflicts.add(
          SyncV2ProfileCatalogConflict(
            profileId: identities.single,
            noteId: entry.key,
            headIds: snapshot.headIds,
            versions: versions,
          ),
        );
      } else {
        records.add(versions.single);
      }
    }
    return (records: records, conflicts: conflicts, incomplete: incomplete);
  }

  Future<List<SyncV2ProfileCatalogRecord>> load() async =>
      (await _read()).records;
  Future<List<SyncV2ProfileCatalogConflict>> loadConflicts() async =>
      (await _read()).conflicts;

  bool _sameKey(List<int> left, List<int> right) {
    if (left.length != right.length) return false;
    var difference = 0;
    for (var i = 0; i < left.length; i++) {
      difference |= left[i] ^ right[i];
    }
    return difference == 0;
  }

  Future<T> _authenticateConflict<T>(
    SyncV2ProfileCatalogConflict conflict,
    SecretKey adminKey,
    Future<T> Function(SyncV2UnlockedProfileKey access, String name) operation,
  ) async {
    final accesses = <SyncV2UnlockedProfileKey>[];
    try {
      String? name;
      List<int>? keyBytes;
      String? keyId;
      final versions = [...conflict.versions];
      for (final version in versions) {
        final access = await _keys.unlockForAdminSession(
          generationId: generationId,
          record: version.wrapped,
          adminKey: adminKey,
        );
        accesses.add(access);
        final bytes = await access.key.extractBytes();
        final opened = await _open(version, access);
        if (keyBytes != null &&
            (!_sameKey(keyBytes, bytes) ||
                keyId != access.keyId ||
                name != opened.name)) {
          throw const HimemoDecryptionException();
        }
        keyBytes = bytes;
        keyId = access.keyId;
        name ??= opened.name;
      }
      return await operation(accesses.first, name!);
    } finally {
      for (final access in accesses) {
        access.destroy();
      }
    }
  }

  Future<Map<String, String>> conflictNames(SecretKey adminKey) async {
    final result = <String, String>{};
    for (final conflict in await loadConflicts()) {
      result[conflict.profileId] = await _authenticateConflict(
        conflict,
        adminKey,
        (_, name) async => name,
      );
    }
    return result;
  }

  Future<void> resolvePasswordConflict({
    required String profileId,
    required String password,
    required SecretKey adminKey,
  }) async {
    if (password.length < SyncV2ProfileKeys.minimumPasscodeLength) {
      throw ArgumentError('Use at least 12 characters.');
    }
    final conflict = (await loadConflicts()).singleWhere(
      (conflict) => conflict.profileId == profileId,
    );
    await _authenticateConflict(conflict, adminKey, (access, _) async {
      final wrapped = await _keys.wrap(
        generationId: generationId,
        profileId: profileId,
        keyId: access.keyId,
        profileKey: access.key,
        passphrase: password,
        adminKey: adminKey,
      );
      await _save(
        conflict.noteId,
        wrapped,
        conflict.versions.first.encryptedName,
        conflict.headIds,
      );
    });
  }

  List<int> _nameContext(SyncV2UnlockedProfileKey access) => utf8.encode(
    jsonEncode([
      'himemo.sync.v2.profile-name',
      generationId,
      normalAccess.profileId,
      access.profileId,
      access.keyId,
    ]),
  );
  Future<SyncV2UnlockedProfile> _open(
    SyncV2ProfileCatalogRecord record,
    SyncV2UnlockedProfileKey access,
  ) async {
    final clear = await _encryption.decryptBytes(
      encodedPayload: record.encryptedName,
      secretKey: access.key,
      additionalData: _nameContext(access),
    );
    return SyncV2UnlockedProfile(name: utf8.decode(clear), access: access);
  }

  Future<SyncV2UnlockedProfile> create({
    required String name,
    required String password,
    required SecretKey adminKey,
  }) async {
    if (name.trim().isEmpty ||
        name.length > 1024 ||
        password.length < SyncV2ProfileKeys.minimumPasscodeLength) {
      throw ArgumentError(
        'Provide a name and a passcode of at least ${SyncV2ProfileKeys.minimumPasscodeLength} characters.',
      );
    }
    final raw = SecretKey(_encryption.generateKeyBytes());
    SyncV2UnlockedProfileKey? access;
    try {
      final wrapped = await _keys.wrap(
        generationId: generationId,
        profileId: 'private_profile:${_random()}',
        keyId: _random(),
        profileKey: raw,
        passphrase: password,
        adminKey: adminKey,
      );
      access = await _keys.unlockForAdminSession(
        generationId: generationId,
        record: wrapped,
        adminKey: adminKey,
      );
      final encryptedName = await _encryption.encryptBytes(
        clearBytes: utf8.encode(name),
        secretKey: access.key,
        additionalData: _nameContext(access),
      );
      await _save('profile_${_random()}', wrapped, encryptedName, {});
      return SyncV2UnlockedProfile(name: name, access: access);
    } catch (_) {
      access?.destroy();
      rethrow;
    } finally {
      raw.destroy();
    }
  }

  Future<List<SyncV2UnlockedProfile>> unlock(String password) async {
    final records = await load();
    var sessions = <String, SyncV2UnlockedProfileKey>{};
    try {
      await AuthenticationThrottle(
        store: _store,
        storageKey: syncV2UnlockAttemptsKey(generationId),
        delayFor: syncV2UnlockDelay,
      ).verify(() async {
        if (password.isEmpty) return false;
        sessions = await _keys.unlockMatchingSessions(
          generationId: generationId,
          records: records.map((record) => record.wrapped),
          passphrase: password,
        );
        return sessions.isNotEmpty;
      });
      return [
        for (final record in records)
          if (sessions.containsKey(record.wrapped.profileId))
            await _open(record, sessions[record.wrapped.profileId]!),
      ];
    } catch (_) {
      for (final access in sessions.values) {
        access.destroy();
      }
      rethrow;
    }
  }

  Future<List<SyncV2UnlockedProfile>> unlockAdmin(SecretKey adminKey) async {
    final sessions = <SyncV2UnlockedProfileKey>[];
    try {
      final result = <SyncV2UnlockedProfile>[];
      for (final record in await load()) {
        final access = await _keys.unlockForAdminSession(
          generationId: generationId,
          record: record.wrapped,
          adminKey: adminKey,
        );
        sessions.add(access);
        result.add(await _open(record, access));
      }
      return result;
    } catch (_) {
      for (final access in sessions) {
        access.destroy();
      }
      rethrow;
    }
  }

  Future<void> changePassword({
    required SyncV2UnlockedProfile profile,
    required String password,
    required SecretKey adminKey,
  }) async {
    if (password.length < SyncV2ProfileKeys.minimumPasscodeLength) {
      throw ArgumentError('Use at least 12 characters.');
    }
    final record = (await load()).singleWhere(
      (record) => record.wrapped.profileId == profile.id,
    );
    final authenticated = await _keys.unlockForAdminSession(
      generationId: generationId,
      record: record.wrapped,
      adminKey: adminKey,
    );
    try {
      // Verify the supplied old session against the encrypted name before using it.
      await _open(record, profile.access);
      if (profile.access.generationId != generationId ||
          profile.access.keyId != record.wrapped.keyId) {
        throw const HimemoDecryptionException();
      }
      final wrapped = await _keys.wrap(
        generationId: generationId,
        profileId: profile.id,
        keyId: profile.access.keyId,
        profileKey: authenticated.key,
        passphrase: password,
        adminKey: adminKey,
      );
      await _save(record.noteId, wrapped, record.encryptedName, record.headIds);
    } finally {
      authenticated.destroy();
    }
  }

  /// Include conflict versions and fail closed when catalog data is pending.
  Future<bool> matchesPassword(String password) async {
    final catalog = await _read();
    if (catalog.incomplete) throw const SyncV2StaleNote();
    for (final record in [
      ...catalog.records,
      for (final conflict in catalog.conflicts) ...conflict.versions,
    ]) {
      final matches = await _keys.unlockMatchingSessions(
        generationId: generationId,
        records: [record.wrapped],
        passphrase: password,
      );
      try {
        if (matches.isNotEmpty) return true;
      } finally {
        for (final access in matches.values) {
          access.destroy();
        }
      }
    }
    return false;
  }

  Future<Map<String, String>> unlockedNames(
    Iterable<SyncV2UnlockedProfile> profiles,
  ) async {
    final catalog = await _read();
    if (catalog.incomplete) throw const SyncV2StaleNote();
    final records = {
      for (final record in catalog.records) record.wrapped.profileId: record,
    };
    return {
      for (final profile in profiles)
        if (records.containsKey(profile.id))
          profile.id: (await _open(records[profile.id]!, profile.access)).name,
    };
  }

  Future<void> rename({
    required SyncV2UnlockedProfile profile,
    required String name,
  }) async {
    if (name.trim().isEmpty || name.length > 1024) {
      throw ArgumentError('Provide a profile name.');
    }
    final record = (await load()).singleWhere(
      (r) => r.wrapped.profileId == profile.id,
    );
    await _open(record, profile.access);
    final encryptedName = await _encryption.encryptBytes(
      clearBytes: utf8.encode(name.trim()),
      secretKey: profile.access.key,
      additionalData: _nameContext(profile.access),
    );
    await _save(record.noteId, record.wrapped, encryptedName, record.headIds);
  }

  Future<void> delete(SyncV2UnlockedProfile profile) async {
    final record = (await load()).singleWhere(
      (r) => r.wrapped.profileId == profile.id,
    );
    await _open(record, profile.access);
    await _repository.delete(
      generationId: generationId,
      profileId: normalAccess.profileId,
      noteId: record.noteId,
      changeId: _random(),
      expectedHeadIds: record.headIds,
      syncKey: syncKey,
      profileKey: normalAccess,
    );
  }

  Future<void> _save(
    String noteId,
    SyncV2WrappedProfileKey wrapped,
    String name,
    Set<String> heads,
  ) async {
    await _repository.save(
      generationId: generationId,
      profileId: normalAccess.profileId,
      noteId: noteId,
      changeId: _random(),
      expectedHeadIds: heads,
      body: {'type': 'profile-key', 'wrapped': wrapped.toJson(), 'name': name},
      syncKey: syncKey,
      profileKey: normalAccess,
    );
  }
}
