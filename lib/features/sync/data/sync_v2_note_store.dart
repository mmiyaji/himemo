import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:path/path.dart' as path;

import '../../home/data/note_store.dart';
import '../../home/domain/note_entry.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_note_repository.dart';
import 'sync_v2_attachment_service.dart';
import '../../security/data/encrypted_attachment_store.dart';

import 'dart:typed_data';

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
/// Local encrypted attachment drafts are committed as v2 chunks with the note.
class SyncV2NoteStore implements NoteStore {
  SyncV2NoteStore({
    required this.repository,
    required this._session,
    String Function()? changeIdFactory,
    this.attachmentService,
    this.attachmentStore,
  }) : _changeId = changeIdFactory ?? _defaultChangeId;

  final SyncV2AttachmentService? attachmentService;
  final EncryptedAttachmentStore? attachmentStore;
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
  final _references = <String, List<SyncV2AttachmentReference>>{};
  // Editors may retain a local draft path after a successful save. Only publish
  // aliases after the transaction commits; generation/profile scopes forbid reuse across locks.
  final _draftReferences = <String, String>{};
  String _draftKey(
    SyncV2NoteStoreSession session,
    String profileId,
    AttachmentType type,
    String source,
  ) =>
      '${session.generationId}:$profileId:${type.name}:${path.basename(source)}';

  ({
    SyncV2NoteStoreSession session,
    SyncV2UnlockedProfileKey access,
    SyncV2AttachmentReference reference,
  })
  attachmentContext(String id) {
    final session = _requireSession();
    for (final entry in _references.entries) {
      final known = _known[entry.key];
      if (known == null) continue;
      final access = session.profiles[profileIdFor(session, known.vaultId)];
      if (access == null) continue;
      for (final reference in entry.value) {
        if (reference.id == id) {
          return (session: session, access: access, reference: reference);
        }
      }
    }
    throw const SyncV2NoteStoreLocked('attachment');
  }

  void _checkActive(
    SyncV2NoteStoreSession session,
    SyncV2UnlockedProfileKey access,
  ) {
    final current = _session();
    if (current == null ||
        current.generationId != session.generationId ||
        !identical(current.profiles[access.profileId], access)) {
      throw const SyncV2NoteStoreLocked('attachment');
    }
  }

  String? committedDraftReference(
    String vaultId,
    AttachmentType type,
    String source,
  ) {
    final session = _session();
    if (session == null) return null;
    final id =
        _draftReferences[_draftKey(
          session,
          profileIdFor(session, vaultId),
          type,
          source,
        )];
    return id == null ? null : 'v2attachment:$id';
  }

  Future<Uint8List> readAttachment(String id, AttachmentType type) async {
    final context = attachmentContext(id);
    if (context.reference.type != type.name || attachmentService == null) {
      throw const FormatException('Invalid v2 attachment');
    }
    return attachmentService!.read(
      reference: context.reference,
      generationId: context.session.generationId,
      syncKey: context.session.syncKey,
      profileAccess: context.access,
      checkActive: () => _checkActive(context.session, context.access),
    );
  }

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
    _references.clear();
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
        Map<String, Object?>? selectedBody;
        for (final version in versions) {
          final body = version.body;
          if (body != null && body['type'] == 'note' && body['note'] is Map) {
            selectedBody = body;
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
        _references[snapshot.key] = [
          for (final raw in (selectedBody?['attachments'] as List? ?? const []))
            SyncV2AttachmentReference.fromJson(
              Map<String, dynamic>.from(raw as Map),
            ),
        ];
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

  Future<NoteEntry> _write(
    SyncV2NoteStoreSession session,
    NoteEntry note,
  ) async {
    if (note.deviceId == 'locked-private-note') return note;
    final profileId = profileIdFor(session, note.vaultId);
    final profileKey = session.profiles[profileId];
    if (profileKey == null) {
      throw SyncV2NoteStoreLocked(note.vaultId);
    }
    final id = v2NoteId(note.id);
    if (_unresolved.contains(id)) throw const SyncV2StaleNote();
    final refs = <String, SyncV2AttachmentReference>{};
    final translated = <String, NoteAttachment>{};
    final pendingAliases = <String, String>{};
    Future<NoteAttachment> prepare(NoteAttachment attachment) async {
      final rawSource = attachment.filePath;
      if (rawSource == null || rawSource.isEmpty) return attachment;
      var source = rawSource;
      final cached = translated['${attachment.type.name}:$source'];
      if (cached != null) {
        return attachment.copyWith(
          filePath: cached.filePath,
          syncAttachmentContentHash: cached.syncAttachmentContentHash,
          localPayloadSizeBytes: null,
          localPayloadModifiedAtMillis: null,
        );
      }
      final originalSource = source;
      final aliasKey = _draftKey(session, profileId, attachment.type, source);
      final alias = _draftReferences[aliasKey];
      if (!source.startsWith('v2attachment:') && alias != null) {
        try {
          attachmentContext(alias);
          source = 'v2attachment:$alias';
        } on SyncV2NoteStoreLocked {
          /* The original draft may still exist. */
        }
      }
      _checkActive(session, profileKey);
      SyncV2AttachmentReference reference;
      if (source.startsWith('v2attachment:')) {
        final context = attachmentContext(
          source.substring('v2attachment:'.length),
        );
        if (context.reference.type != attachment.type.name) {
          throw const FormatException('Attachment type mismatch');
        }
        if (context.access.profileId == profileId) {
          reference = context.reference;
        } else {
          final bytes = await readAttachment(
            context.reference.id,
            attachment.type,
          );
          try {
            reference = await attachmentService!.store(
              generationId: session.generationId,
              syncKey: session.syncKey,
              profileAccess: profileKey,
              bytes: bytes,
              label: attachment.label,
              type: attachment.type.name,
              stableId: 'copy:$source',
              checkActive: () => _checkActive(session, profileKey),
            );
          } finally {
            bytes.fillRange(0, bytes.length, 0);
          }
        }
      } else {
        if (attachmentService == null || attachmentStore == null) {
          throw StateError('Attachment storage is unavailable');
        }
        final clear = await attachmentStore!.readAttachment(
          source,
          type: attachment.type,
        );
        if (clear == null || clear.isEmpty) {
          throw const FormatException('Missing attachment draft');
        }
        final bytes = clear is Uint8List ? clear : Uint8List.fromList(clear);
        try {
          reference = await attachmentService!.store(
            generationId: session.generationId,
            syncKey: session.syncKey,
            profileAccess: profileKey,
            bytes: bytes,
            label: attachment.label,
            type: attachment.type.name,
            stableId: path.basename(source),
            checkActive: () => _checkActive(session, profileKey),
          );
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      if (!originalSource.startsWith('v2attachment:')) {
        pendingAliases[aliasKey] = reference.id;
      }
      refs[reference.id] = reference;
      final result = attachment.copyWith(
        filePath: 'v2attachment:${reference.id}',
        syncAttachmentContentHash: reference.sha256,
        localPayloadSizeBytes: null,
        localPayloadModifiedAtMillis: null,
      );
      translated['${attachment.type.name}:$originalSource'] = result;
      return result;
    }

    Future<({NoteEntry note, String head})> commit() async {
      final normalized = note.copyWith(
        attachments: [
          for (final attachment in note.attachments) await prepare(attachment),
        ],
        blocks: [
          for (final block in note.blocks)
            block.attachment == null
                ? block
                : block.copyWith(attachment: await prepare(block.attachment!)),
        ],
      );
      _checkActive(session, profileKey);
      final previous = _known[id];
      final moving = previous != null && previous.vaultId != note.vaultId;
      var heads = _heads[id] ?? const <String>{};
      if (moving) {
        final destination = await repository.readNote(
          generationId: session.generationId,
          profileId: profileId,
          noteId: id,
          syncKey: session.syncKey,
          profileKey: profileKey,
        );
        if (!destination.canCompareVersions ||
            destination.versions.any((v) => !v.isDeleted)) {
          throw const SyncV2StaleNote();
        }
        heads = destination.headIds;
      }
      final change = await repository.save(
        generationId: session.generationId,
        profileId: profileId,
        noteId: id,
        changeId: _changeId(),
        expectedHeadIds: heads,
        body: {
          'type': 'note',
          'note': normalized.copyWith(id: id, vaultId: profileId).toJson(),
          'attachments': [
            for (final reference in refs.values) reference.toJson(),
          ],
        },
        syncKey: session.syncKey,
        profileKey: profileKey,
      );
      if (moving) {
        final oldId = profileIdFor(session, previous.vaultId);
        final oldKey = session.profiles[oldId];
        if (oldKey == null) throw SyncV2NoteStoreLocked(previous.vaultId);
        await repository.delete(
          generationId: session.generationId,
          profileId: oldId,
          noteId: id,
          changeId: _changeId(),
          expectedHeadIds: _heads[id]!,
          syncKey: session.syncKey,
          profileKey: oldKey,
        );
      }
      _checkActive(session, profileKey);
      return (note: normalized, head: change.id);
    }

    final saved = attachmentService == null
        ? await commit()
        : await attachmentService!.inbox.transaction(commit);
    _draftReferences.addAll(pendingAliases);
    _heads[id] = {saved.head};
    _known[id] = (vaultId: note.vaultId, json: jsonEncode(saved.note.toJson()));
    _references[id] = refs.values.toList();
    return saved.note;
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
    _references.remove(v2Id);
  }

  @override
  Future<NoteEntry> saveOne(NoteEntry note) =>
      _serial(() => _write(_requireSession(), note));

  @override
  Future<List<NoteEntry>> save(
    List<NoteEntry> notes, {
    bool preserveOmittedPrivateNotes = false,
  }) => _serial(() async {
    final session = _requireSession();
    final present = <String>{};
    final saved = <NoteEntry>[];
    for (final note in notes) {
      final id = v2NoteId(note.id);
      present.add(id);
      if (note.deviceId == 'locked-private-note') {
        saved.add(note);
        continue;
      }
      if (_known[id]?.json == jsonEncode(note.toJson())) {
        saved.add(note);
      } else {
        saved.add(await _write(session, note));
      }
    }
    for (final entry in _known.entries.toList()) {
      if (present.contains(entry.key)) continue;
      if (preserveOmittedPrivateNotes &&
          entry.value.vaultId != syncV2NormalVaultId) {
        continue;
      }
      await _delete(session, entry.key);
    }
    return saved;
  });

  @override
  Future<void> deleteById(String noteId) =>
      _serial(() => _delete(_requireSession(), v2NoteId(noteId)));

  /// v2 data is shared through sync, so this only forgets the local cache.
  @override
  Future<void> deleteByVaultId(String vaultId) => _serial(() async {
    _known.removeWhere((id, value) {
      final match = value.vaultId == vaultId;
      if (match) {
        _heads.remove(id);
        _references.remove(id);
      }
      return match;
    });
  });

  @override
  Future<int> storagePayloadSizeBytes() async => _known.values.fold<int>(
    0,
    (sum, value) => sum + utf8.encode(value.json).length,
  );
}
