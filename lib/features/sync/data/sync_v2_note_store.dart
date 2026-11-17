import 'dart:convert';

import 'package:cryptography/cryptography.dart';

import '../../home/data/note_store.dart';
import '../../home/domain/note_entry.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_note_repository.dart';

/// The v1 vault id used for the v2 normal profile.
const syncV2NormalVaultId = 'everyday';

/// v2 note ids carry this namespace; v1 note ids do not.
const syncV2NoteIdPrefix = 'note_';

/// Keys and identities needed to read and write v2 notes.
///
/// [profiles] is keyed by v2 profile id and contains every unlocked profile,
/// including the normal profile identified by [normalProfileId].
class SyncV2NoteStoreSession {
  SyncV2NoteStoreSession({
    required this.generationId,
    required this.syncKey,
    required this.normalProfileId,
    required Map<String, SyncV2UnlockedProfileKey> profiles,
  }) : profiles = Map.unmodifiable(profiles);

  final String generationId;
  final SecretKey syncKey;
  final String normalProfileId;
  final Map<String, SyncV2UnlockedProfileKey> profiles;
}

class SyncV2NoteStoreLocked implements Exception {
  const SyncV2NoteStoreLocked(this.vaultId);
  final String vaultId;
  @override
  String toString() => 'SyncV2NoteStoreLocked($vaultId)';
}

/// [NoteStore] backed by Sync v2 note history.
///
/// v1 identities are translated at this boundary:
/// - note id `X` is stored as `note_X`
/// - vault `everyday` is the v2 normal profile; private vault ids are the v2
///   profile ids unchanged (`private_profile:...`).
///
/// Attachments are not migrated yet: attachment references are written empty.
class SyncV2NoteStore implements NoteStore {
  SyncV2NoteStore({
    required this.repository,
    required this._session,
    String Function()? changeIdFactory,
  }) : _changeId = changeIdFactory ?? _defaultChangeId;

  final SyncV2NoteRepository repository;
  final SyncV2NoteStoreSession? Function() _session;
  final String Function() _changeId;

  /// Last known heads per v2 note id, used for compare-and-swap writes.
  final _heads = <String, Set<String>>{};

  /// Last written or loaded note JSON per v2 note id.
  final _known = <String, ({String vaultId, String json})>{};

  /// v2 note ids with concurrent heads or bodies not yet downloaded. Writing
  /// them would silently discard versions the user has not seen.
  final _unresolved = <String>{};

  Future<void> _queue = Future.value();

  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _queue.then((_) => action());
    _queue = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  static int _counter = 0;
  static String _defaultChangeId() =>
      'change_${DateTime.now().microsecondsSinceEpoch}_${_counter++}';

  SyncV2NoteStoreSession _requireSession() {
    final session = _session();
    if (session == null) throw const SyncV2NoteStoreLocked('session');
    return session;
  }

  static String v2NoteId(String v1Id) => '$syncV2NoteIdPrefix$v1Id';

  static String v1NoteId(String v2Id) => v2Id.startsWith(syncV2NoteIdPrefix)
      ? v2Id.substring(syncV2NoteIdPrefix.length)
      : v2Id;

  static String profileIdFor(SyncV2NoteStoreSession session, String vaultId) =>
      vaultId == syncV2NormalVaultId ? session.normalProfileId : vaultId;

  static String vaultIdFor(SyncV2NoteStoreSession session, String profileId) =>
      profileId == session.normalProfileId ? syncV2NormalVaultId : profileId;

  @override
  Future<List<NoteEntry>> load({
    required List<NoteEntry> fallbackNotes,
  }) => _serial(() async {
    final session = _session();
    if (session == null) return fallbackNotes;
    _heads.clear();
    _unresolved.clear();
    _known.clear();
    final loaded = <NoteEntry>[];
    for (final entry in session.profiles.entries) {
      final snapshots = await repository.readProfile(
        generationId: session.generationId,
        profileId: entry.key,
        syncKey: session.syncKey,
        profileKey: entry.value,
        noteIdPrefix: syncV2NoteIdPrefix,
      );
      final vaultId = vaultIdFor(session, entry.key);
      for (final snapshot in snapshots.entries) {
        final versions = snapshot.value.versions;
        if (versions.isEmpty || versions.every((v) => v.isDeleted)) {
          continue;
        }
        Map<String, dynamic>? noteJson;
        for (final version in versions) {
          final body = version.body;
          if (body != null && body['type'] == 'note' && body['note'] is Map) {
            noteJson = Map<String, dynamic>.from(body['note'] as Map);
            break;
          }
        }
        if (noteJson == null) continue;
        final NoteEntry parsed;
        try {
          parsed = NoteEntry.fromJson(noteJson);
        } on Object {
          continue;
        }
        if (parsed.id != snapshot.key || parsed.vaultId != entry.key) {
          continue;
        }
        final note = parsed.copyWith(id: v1NoteId(parsed.id), vaultId: vaultId);
        if (snapshot.value.hasConflict || !snapshot.value.canCompareVersions) {
          _unresolved.add(snapshot.key);
        }
        _heads[snapshot.key] = snapshot.value.headIds;
        _known[snapshot.key] = (
          vaultId: vaultId,
          json: jsonEncode(note.toJson()),
        );
        loaded.add(note);
      }
    }
    return loaded;
  });

  Future<void> _write(SyncV2NoteStoreSession session, NoteEntry note) async {
    final profileId = profileIdFor(session, note.vaultId);
    final profileKey = session.profiles[profileId];
    if (profileKey == null) throw SyncV2NoteStoreLocked(note.vaultId);
    final id = v2NoteId(note.id);
    if (_unresolved.contains(id)) throw const SyncV2StaleNote();
    final stored = note.copyWith(id: id, vaultId: profileId);
    final change = await repository.save(
      generationId: session.generationId,
      profileId: profileId,
      noteId: id,
      changeId: _changeId(),
      expectedHeadIds: _heads[id] ?? const {},
      body: {
        'type': 'note',
        'note': stored.toJson(),
        'attachments': const <Object>[],
      },
      syncKey: session.syncKey,
      profileKey: profileKey,
    );
    _heads[id] = {change.id};
    _known[id] = (vaultId: note.vaultId, json: jsonEncode(note.toJson()));
  }

  Future<void> _delete(SyncV2NoteStoreSession session, String v2Id) async {
    final known = _known[v2Id];
    if (known == null) return;
    if (_unresolved.contains(v2Id)) throw const SyncV2StaleNote();
    final profileId = profileIdFor(session, known.vaultId);
    final profileKey = session.profiles[profileId];
    if (profileKey == null) throw SyncV2NoteStoreLocked(known.vaultId);
    await repository.delete(
      generationId: session.generationId,
      profileId: profileId,
      noteId: v2Id,
      changeId: _changeId(),
      expectedHeadIds: _heads[v2Id] ?? const {},
      syncKey: session.syncKey,
      profileKey: profileKey,
    );
    _heads.remove(v2Id);
    _known.remove(v2Id);
  }

  @override
  Future<void> saveOne(NoteEntry note) =>
      _serial(() => _write(_requireSession(), note));

  @override
  Future<void> save(
    List<NoteEntry> notes, {
    bool preserveOmittedPrivateNotes = false,
  }) => _serial(() async {
    final session = _requireSession();
    final present = <String>{};
    for (final note in notes) {
      final id = v2NoteId(note.id);
      present.add(id);
      if (_known[id]?.json == jsonEncode(note.toJson())) continue;
      await _write(session, note);
    }
    for (final entry in _known.entries.toList()) {
      if (present.contains(entry.key)) continue;
      if (preserveOmittedPrivateNotes &&
          entry.value.vaultId != syncV2NormalVaultId) {
        continue;
      }
      await _delete(session, entry.key);
    }
  });

  @override
  Future<void> deleteById(String noteId) =>
      _serial(() => _delete(_requireSession(), v2NoteId(noteId)));

  /// v2 data is shared through sync, so this only forgets the local cache.
  @override
  Future<void> deleteByVaultId(String vaultId) => _serial(() async {
    _known.removeWhere((id, value) {
      final match = value.vaultId == vaultId;
      if (match) _heads.remove(id);
      return match;
    });
  });

  @override
  Future<int> storagePayloadSizeBytes() async => _known.values.fold<int>(
    0,
    (sum, value) => sum + utf8.encode(value.json).length,
  );
}
