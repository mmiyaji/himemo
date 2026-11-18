import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../../security/data/sync_v2_profile_keys.dart';
import '../../security/data/encryption_service.dart';
import 'sync_v2_header_codec.dart';
import 'sync_v2_history.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_payload_codec.dart';

class SyncV2StaleNote implements Exception {
  const SyncV2StaleNote();

  @override
  String toString() => 'The note changed. Reload all versions before saving.';
}

/// A head is retained even when its body has not arrived or is still locked.
class SyncV2NoteVersion {
  const SyncV2NoteVersion({
    required this.change,
    required this.payloadAvailable,
    required this.body,
  });

  final SyncV2Change change;
  final bool payloadAvailable;
  final Map<String, Object?>? body;
  bool get isDeleted => change.operation == SyncV2Operation.delete;
}

class SyncV2NoteSnapshot {
  SyncV2NoteSnapshot({
    required List<SyncV2NoteVersion> versions,
    required Set<String> pendingIds,
  }) : versions = List.unmodifiable(versions),
       pendingIds = Set.unmodifiable(pendingIds);

  final List<SyncV2NoteVersion> versions;
  final Set<String> pendingIds;
  Set<String> get headIds => {
    for (final version in versions) version.change.id,
  };
  bool get hasConflict => versions.length > 1;
  bool get canCompareVersions =>
      pendingIds.isEmpty &&
      versions.every(
        (version) =>
            version.payloadAvailable &&
            (version.isDeleted || version.body != null),
      );
}

/// The encrypted change log is the source of truth, not a second notes DB.
/// Edits and their outbox entries commit in the same inbox transaction.
/// Profile keys are borrowed for a single call; this object never retains them.
class SyncV2NoteRepository {
  SyncV2NoteRepository(this._inbox, this._headers, this._payloads);

  final SyncV2Inbox _inbox;
  final SyncV2HeaderCodec _headers;
  final SyncV2PayloadCodec _payloads;
  final _projectionEncryption = EncryptionService();

  /// Keep session checks in the same transaction as a caller's mutation.
  Future<T> transaction<T>(Future<T> Function() action) =>
      _inbox.transaction(action);

  Future<List<SyncV2Change>> _history(
    String generationId,
    SecretKey syncKey, {
    void Function()? checkActive,
  }) async {
    final changes = <SyncV2Change>[];
    var afterId = '';
    while (true) {
      checkActive?.call();
      final page = await _inbox.readPage(
        generationId: generationId,
        afterId: afterId,
        limit: 100,
      );
      for (final record in page) {
        checkActive?.call();
        changes.add(
          await _headers.open(
            record.encryptedHeader,
            generationId: generationId,
            recordId: record.id,
            syncKey: syncKey,
          ),
        );
      }
      checkActive?.call();
      if (page.length < 100) return changes;
      afterId = page.last.id;
    }
  }

  Future<SyncV2NoteSnapshot> readNote({
    required String generationId,
    required String profileId,
    required String noteId,
    required SecretKey syncKey,
    SyncV2UnlockedProfileKey? profileKey,
  }) => _inbox.transaction(() async {
    _validateIdentity(generationId, profileId, noteId);
    _validateProfileKey(profileKey, generationId, profileId);
    final history = await _history(generationId, syncKey);
    return _readFromHistory(
      history,
      generationId,
      profileId,
      noteId,
      profileKey,
    );
  });

  /// Authenticated per-note projections keep list reads proportional to current
  /// heads, rather than the generation's entire history. A changed note is
  /// rebuilt from its immutable log; prefixes never open attachment bodies.
  Future<Map<String, SyncV2NoteSnapshot>> readProfile({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    SyncV2UnlockedProfileKey? profileKey,
    String? noteIdPrefix,
  }) => _inbox.transaction(() async {
    _validateIdentity(generationId, profileId, 'profile');
    _validateProfileKey(profileKey, generationId, profileId);
    final states = await _inbox.readNoteStates(
      generationId: generationId,
      profileId: profileId,
      syncKey: syncKey,
    );
    final result = <String, SyncV2NoteSnapshot>{};
    for (final state in states) {
      final context = utf8.encode(
        jsonEncode([
          'himemo.sync.v2.note-state.1',
          generationId,
          profileId,
          state.noteToken,
        ]),
      );
      String? encrypted = state.encryptedState;
      if (encrypted == null) {
        var matchesPrefix = true;
        // A prefix-filtered list must not resolve an unrelated attachment's
        // invalid history as a fatal error. Validate its indexed identity too.
        if (noteIdPrefix != null) {
          final first = await _inbox.readHeader(
            generationId,
            state.firstRecordId,
          );
          if (first == null) {
            throw const FormatException('Missing v2 note history');
          }
          final identity = await _headers.open(
            first.encryptedHeader,
            generationId: generationId,
            recordId: first.id,
            syncKey: syncKey,
          );
          if (identity.profileId != profileId ||
              await _inbox.noteIndexToken(
                    generationId: generationId,
                    profileId: profileId,
                    noteId: identity.noteId,
                    syncKey: syncKey,
                  ) !=
                  state.noteToken) {
            throw const FormatException('Invalid v2 note index');
          }
          matchesPrefix = identity.noteId.startsWith(noteIdPrefix);
        }
        final history = <SyncV2Change>[];
        for (final record in await _inbox.readIndexedNoteHistory(
          generationId: generationId,
          noteToken: state.noteToken,
        )) {
          history.add(
            await _headers.open(
              record.encryptedHeader,
              generationId: generationId,
              recordId: record.id,
              syncKey: syncKey,
            ),
          );
        }
        if (history.isEmpty) {
          throw const FormatException('Missing v2 note history');
        }
        final noteId = history.first.noteId;
        if (history.any(
              (change) =>
                  change.profileId != profileId || change.noteId != noteId,
            ) ||
            await _inbox.noteIndexToken(
                  generationId: generationId,
                  profileId: profileId,
                  noteId: noteId,
                  syncKey: syncKey,
                ) !=
                state.noteToken) {
          throw const FormatException('Invalid v2 note index');
        }
        // Authenticate external parents too, including a parent which arrived
        // after this pending child and belongs to another note/profile.
        final ownIds = {for (final change in history) change.id};
        final externalIds = {for (final change in history) ...change.parentIds}
          ..removeAll(ownIds);
        for (final id in externalIds) {
          final record = await _inbox.readHeader(generationId, id);
          if (record != null) {
            history.add(
              await _headers.open(
                record.encryptedHeader,
                generationId: generationId,
                recordId: record.id,
                syncKey: syncKey,
              ),
            );
          }
        }
        final Map<String, Object?> projection;
        try {
          final resolved = _resolveNote(history, profileId, noteId);
          projection = {
            'v': 1,
            'note': noteId,
            'heads': [
              for (final c in history)
                if (resolved.headIds.contains(c.id)) c.id,
            ],
            'pending': resolved.pendingIds.toList(),
          };
        } on FormatException {
          if (matchesPrefix) rethrow;
          // Invalid histories outside the selected prefix keep their original
          // ignored behavior; never turn an error into an empty valid state.
          continue;
        }
        encrypted = await _projectionEncryption.encryptBytes(
          clearBytes: utf8.encode(jsonEncode(projection)),
          secretKey: syncKey,
          additionalData: context,
        );
        await _inbox.writeNoteState(
          generationId: generationId,
          profileId: profileId,
          noteToken: state.noteToken,
          encryptedState: encrypted,
          syncKey: syncKey,
        );
      }
      final decoded = jsonDecode(
        utf8.decode(
          await _projectionEncryption.decryptBytes(
            encodedPayload: encrypted,
            secretKey: syncKey,
            additionalData: context,
          ),
        ),
      );
      if (decoded
          case {
            'v': 1,
            'note': final String noteId,
            'heads': final List<Object?> headIds,
            'pending': final List<Object?> pendingIds,
          }
          when headIds.every((id) => id is String) &&
              pendingIds.every((id) => id is String)) {
        if (noteIdPrefix != null && !noteId.startsWith(noteIdPrefix)) continue;
        final heads = <SyncV2Change>[];
        for (final id in headIds.cast<String>()) {
          final record = await _inbox.readHeader(generationId, id);
          if (record == null) throw const FormatException('Missing v2 head');
          final change = await _headers.open(
            record.encryptedHeader,
            generationId: generationId,
            recordId: record.id,
            syncKey: syncKey,
          );
          if (change.profileId != profileId || change.noteId != noteId) {
            throw const FormatException('Invalid v2 note state');
          }
          heads.add(change);
        }
        result[noteId] = await _readVersions(
          heads,
          headIds.cast<String>().toSet(),
          pendingIds.cast<String>().toSet(),
          generationId,
          profileKey,
        );
      } else {
        throw const FormatException('Invalid v2 note state');
      }
    }
    return result;
  });

  Future<Map<String, SyncV2NoteSnapshot>> readMany({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
    required Set<String> noteIds,
    void Function()? checkActive,
  }) => _inbox.transaction(() async {
    checkActive?.call();
    _validateIdentity(generationId, profileId, 'batch');
    _validateProfileKey(profileKey, generationId, profileId);
    final history = await _history(
      generationId,
      syncKey,
      checkActive: checkActive,
    );
    final result = <String, SyncV2NoteSnapshot>{};
    for (final id in noteIds) {
      checkActive?.call();
      result[id] = await _readFromHistory(
        history,
        generationId,
        profileId,
        id,
        profileKey,
        checkActive: checkActive,
      );
      checkActive?.call();
    }
    return result;
  });

  /// Immutable records share a single authenticated header scan.
  /// New change IDs require empty heads; exact retries remain idempotent.
  Future<void> saveNewBatch({
    required String generationId,
    required String profileId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
    void Function()? checkActive,
    required List<({String noteId, String changeId, Map<String, Object?> body})>
    notes,
  }) {
    final detached =
        <({String noteId, String changeId, Map<String, dynamic> body})>[];
    for (final note in notes) {
      checkActive?.call();
      detached.add((
        noteId: note.noteId,
        changeId: note.changeId,
        body: jsonDecode(jsonEncode(note.body)) as Map<String, dynamic>,
      ));
      checkActive?.call();
    }
    return _inbox.transaction(() async {
      checkActive?.call();
      final history = await _history(
        generationId,
        syncKey,
        checkActive: checkActive,
      );
      for (final note in detached) {
        checkActive?.call();
        final change = await _commit(
          generationId: generationId,
          profileId: profileId,
          noteId: note.noteId,
          changeId: note.changeId,
          expectedHeadIds: {},
          body: note.body,
          syncKey: syncKey,
          profileKey: profileKey,
          cachedHistory: history,
        );
        checkActive?.call();
        if (!history.any((existing) => existing.id == change.id)) {
          history.add(change);
        }
      }
    });
  }

  Future<SyncV2NoteSnapshot> _readFromHistory(
    List<SyncV2Change> history,
    String generationId,
    String profileId,
    String noteId,
    SyncV2UnlockedProfileKey? profileKey, {
    void Function()? checkActive,
  }) async {
    final resolved = _resolveNote(history, profileId, noteId);
    return _readVersions(
      history.where((c) => c.profileId == profileId && c.noteId == noteId),
      resolved.headIds,
      resolved.pendingIds,
      generationId,
      profileKey,
      checkActive: checkActive,
    );
  }

  Future<SyncV2NoteSnapshot> _readVersions(
    Iterable<SyncV2Change> changes,
    Set<String> headIds,
    Set<String> pendingIds,
    String generationId,
    SyncV2UnlockedProfileKey? profileKey, {
    void Function()? checkActive,
  }) async {
    final versions = <SyncV2NoteVersion>[];
    for (final change in changes) {
      if (!headIds.contains(change.id)) continue;
      final payload = change.operation == SyncV2Operation.delete
          ? null
          : await _inbox.readPayload(
              generationId: generationId,
              recordId: change.id,
            );
      checkActive?.call();
      Map<String, Object?>? body;
      if (payload != null && profileKey != null) {
        checkActive?.call();
        body = Map.unmodifiable(
          await _payloads.open(
            generationId: generationId,
            change: change,
            encryptedPayload: payload,
            profileKey: profileKey.key,
          ),
        );
        checkActive?.call();
      }
      versions.add(
        SyncV2NoteVersion(
          change: change,
          payloadAvailable:
              change.operation == SyncV2Operation.delete || payload != null,
          body: body,
        ),
      );
    }
    return SyncV2NoteSnapshot(versions: versions, pendingIds: pendingIds);
  }

  /// Reads the sole authenticated immediate predecessor of a tombstone.
  /// Multiple parents, missing payloads and unresolved heads are not guessed.
  Future<Map<String, Object?>> readDeletedPredecessor({
    required String generationId,
    required String profileId,
    required String noteId,
    required Set<String> expectedHeadIds,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
  }) => _inbox.transaction(() async {
    _validateIdentity(generationId, profileId, noteId);
    _validateProfileKey(profileKey, generationId, profileId);
    final history = await _history(generationId, syncKey);
    final resolved = _resolveNote(history, profileId, noteId);
    if (resolved.pendingIds.isNotEmpty ||
        expectedHeadIds.length != 1 ||
        resolved.headIds.length != 1 ||
        !resolved.headIds.containsAll(expectedHeadIds)) {
      throw const SyncV2StaleNote();
    }
    final tombstone = history.singleWhere(
      (change) => change.id == expectedHeadIds.single,
    );
    if (tombstone.operation != SyncV2Operation.delete ||
        tombstone.parentIds.length != 1) {
      throw const SyncV2StaleNote();
    }
    final candidates = history
        .where(
          (change) =>
              change.id == tombstone.parentIds.single &&
              change.profileId == profileId &&
              change.noteId == noteId &&
              change.operation == SyncV2Operation.upsert,
        )
        .toList();
    if (candidates.length != 1) throw const SyncV2StaleNote();
    final parent = candidates.single;
    final encrypted = await _inbox.readPayload(
      generationId: generationId,
      recordId: parent.id,
    );
    if (encrypted == null) throw const SyncV2StaleNote();
    return Map.unmodifiable(
      await _payloads.open(
        generationId: generationId,
        change: parent,
        encryptedPayload: encrypted,
        profileKey: profileKey.key,
      ),
    );
  });

  /// Supply exactly the heads shown to the editor. Resolving a conflict must
  /// acknowledge every version; unseen or incomplete history blocks a write.
  /// Repeating a change ID with the same content reuses its original ciphertext.
  Future<SyncV2Change> save({
    required String generationId,
    required String profileId,
    required String noteId,
    required String changeId,
    required Set<String> expectedHeadIds,
    required Map<String, Object?> body,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
  }) {
    // Detach before the first await so the editor cannot mutate an in-flight edit.
    final snapshot = jsonDecode(jsonEncode(body)) as Map<String, dynamic>;
    return _commit(
      generationId: generationId,
      profileId: profileId,
      noteId: noteId,
      changeId: changeId,
      expectedHeadIds: Set.of(expectedHeadIds),
      body: snapshot,
      syncKey: syncKey,
      profileKey: profileKey,
    );
  }

  /// Deletion requires the same profile key used to compare existing versions.
  Future<SyncV2Change> delete({
    required String generationId,
    required String profileId,
    required String noteId,
    required String changeId,
    required Set<String> expectedHeadIds,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileKey,
  }) => _commit(
    generationId: generationId,
    profileId: profileId,
    noteId: noteId,
    changeId: changeId,
    expectedHeadIds: Set.of(expectedHeadIds),
    body: null,
    syncKey: syncKey,
    profileKey: profileKey,
  );

  Future<SyncV2Change> _commit({
    required String generationId,
    required String profileId,
    required String noteId,
    required String changeId,
    required Set<String> expectedHeadIds,
    required Map<String, Object?>? body,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey? profileKey,
    List<SyncV2Change>? cachedHistory,
  }) => _inbox.transaction(() async {
    _validateIdentity(generationId, profileId, noteId);
    _validateProfileKey(profileKey, generationId, profileId);
    if (changeId.isEmpty) throw const FormatException('Missing v2 change ID');
    final history = cachedHistory ?? await _history(generationId, syncKey);
    final operation = body == null
        ? SyncV2Operation.delete
        : SyncV2Operation.upsert;
    for (final existing in history) {
      if (existing.id != changeId) continue;
      if (existing.profileId != profileId ||
          existing.noteId != noteId ||
          existing.operation != operation ||
          !_sameIds(existing.parentIds, expectedHeadIds)) {
        throw const FormatException('Conflicting v2 change ID');
      }
      if (body != null) {
        final payload = await _inbox.readPayload(
          generationId: generationId,
          recordId: changeId,
        );
        if (payload == null) throw const SyncV2StaleNote();
        final previous = await _payloads.open(
          generationId: generationId,
          change: existing,
          encryptedPayload: payload,
          profileKey: profileKey!.key,
        );
        if (jsonEncode(_canonical(previous)) != jsonEncode(_canonical(body))) {
          throw const FormatException('Conflicting v2 change ID');
        }
      }
      return existing;
    }
    final resolved = _resolveNote(history, profileId, noteId);
    final noteChanges = history.where(
      (change) => change.profileId == profileId && change.noteId == noteId,
    );
    final heads = <String>{};
    for (final change in noteChanges) {
      if (resolved.pendingIds.contains(change.id)) {
        throw const SyncV2StaleNote();
      }
      if (resolved.headIds.contains(change.id)) heads.add(change.id);
    }
    if (!_sameIds(heads, expectedHeadIds)) throw const SyncV2StaleNote();
    // Reject unavailable bodies and accidental use of another profile's key.
    for (final change in noteChanges) {
      if (heads.contains(change.id) &&
          change.operation == SyncV2Operation.upsert) {
        final previousPayload = await _inbox.readPayload(
          generationId: generationId,
          recordId: change.id,
        );
        if (previousPayload == null) throw const SyncV2StaleNote();
        await _payloads.open(
          generationId: generationId,
          change: change,
          encryptedPayload: previousPayload,
          profileKey: profileKey!.key,
        );
      }
    }
    final SyncV2Change change;
    Uint8List? payload;
    if (body == null) {
      change = SyncV2Change(
        id: changeId,
        profileId: profileId,
        noteId: noteId,
        operation: operation,
        parentIds: expectedHeadIds,
      );
    } else {
      final prepared = await _payloads.seal(
        generationId: generationId,
        changeId: changeId,
        profileId: profileId,
        noteId: noteId,
        parentIds: expectedHeadIds,
        body: body,
        profileKey: profileKey!.key,
      );
      change = prepared.change;
      payload = prepared.encryptedPayload;
    }
    await _inbox.queuePublication(
      generationId: generationId,
      change: change,
      encryptedPayload: payload,
      syncKey: syncKey,
    );
    return change;
  });

  void _validateIdentity(String generation, String profile, String note) {
    if ([generation, profile, note].any((id) => id.isEmpty)) {
      throw const FormatException('Missing v2 note identity');
    }
  }

  void _validateProfileKey(
    SyncV2UnlockedProfileKey? access,
    String generation,
    String profile,
  ) {
    if (access != null &&
        (access.generationId != generation || access.profileId != profile)) {
      throw const HimemoDecryptionException();
    }
  }

  bool _sameIds(Set<String> left, Set<String> right) =>
      left.length == right.length && left.containsAll(right);

  ({Set<String> headIds, Set<String> pendingIds}) _resolveNote(
    List<SyncV2Change> history,
    String profileId,
    String noteId,
  ) {
    final byId = {for (final change in history) change.id: change};
    final noteChanges = history
        .where(
          (change) => change.profileId == profileId && change.noteId == noteId,
        )
        .toList();
    for (final change in noteChanges) {
      for (final parentId in change.parentIds) {
        final parent = byId[parentId];
        if (parent != null &&
            (parent.profileId != profileId || parent.noteId != noteId)) {
          throw const FormatException('Sync v2 parent belongs to another note');
        }
      }
    }
    return resolveSyncV2History(noteChanges);
  }

  Object? _canonical(Object? value) => switch (value) {
    Map<String, dynamic>() => {
      for (final key in value.keys.toList()..sort())
        key: _canonical(value[key]),
    },
    List<Object?>() => value.map(_canonical).toList(),
    _ => value,
  };
}
