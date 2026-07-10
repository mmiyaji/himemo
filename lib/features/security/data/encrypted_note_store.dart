import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import 'encrypted_note_database.dart';
import 'encryption_service.dart';
import 'master_key_service.dart';
import 'profile_data_key_service.dart';

class EncryptedNoteStore {
  EncryptedNoteStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    ProfileDataKeyService? profileDataKeyService,
    EncryptedNoteDatabase? database,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    bool? isWeb,
    this.storageFileName = 'notes.entries.enc.v1',
    this.legacyStorageKey = 'notes.entries.v1',
    this.webStorageKey = 'notes.entries.encrypted.v1',
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _profileDataKeyService = profileDataKeyService,
       _database = database,
       _isWeb = isWeb ?? kIsWeb,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final ProfileDataKeyService? _profileDataKeyService;
  final EncryptedNoteDatabase? _database;
  final bool _isWeb;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String storageFileName;
  final String legacyStorageKey;
  final String webStorageKey;

  Future<List<NoteEntry>> load({required List<NoteEntry> fallbackNotes}) async {
    if (_isWeb) {
      return _loadWeb(fallbackNotes: fallbackNotes);
    }

    final database = _database ?? EncryptedNoteDatabase();
    final encoded = await _readEncryptedPayload();
    if (encoded != null && encoded.isNotEmpty) {
      final migrated = await _decodeEntries(encoded);
      return _migrateNativeEntries(
        migrated,
        database: database,
        deleteSource: _deleteEncryptedPayload,
      );
    }

    final prefs = await _sharedPreferencesProvider();
    final legacy = prefs.getString(legacyStorageKey);
    if (legacy == null || legacy.isEmpty) {
      final snapshots = await database.loadAll();
      if (snapshots.isNotEmpty) {
        return _decryptSnapshots(snapshots);
      }
      return fallbackNotes;
    }

    late final List<NoteEntry> migrated;
    try {
      migrated = _decodePlaintextEntries(legacy);
    } catch (_) {
      await prefs.setString('$legacyStorageKey.corrupt', legacy);
      await prefs.remove(legacyStorageKey);
      final snapshots = await database.loadAll();
      if (snapshots.isNotEmpty) {
        return _decryptSnapshots(snapshots);
      }
      return fallbackNotes;
    }
    return _migrateNativeEntries(
      migrated,
      database: database,
      deleteSource: () async {
        await prefs.remove(legacyStorageKey);
      },
    );
  }

  Future<void> save(
    List<NoteEntry> notes, {
    bool preserveOmittedPrivateNotes = false,
  }) async {
    if (_isWeb) {
      await _saveWeb(
        notes,
        preserveOmittedPrivateNotes: preserveOmittedPrivateNotes,
      );
      return;
    }

    final database = _database ?? EncryptedNoteDatabase();
    final existingSnapshots = await database.loadAll();
    final existingById = {
      for (final snapshot in existingSnapshots) snapshot.note.id: snapshot,
    };
    final savedIds = notes.map((note) => note.id).toSet();
    final records = <EncryptedNoteRecord>[];
    final attachments = <EncryptedAttachmentRecord>[];
    final pendingChanges = <PendingNoteChangeRecord>[];
    for (final note in notes) {
      if (_isLockedPlaceholder(note)) {
        final existing = existingById[note.id];
        if (existing != null) {
          records.add(existing.note);
          attachments.addAll(existing.attachments);
        }
        continue;
      }
      final key = await _keyForVault(note.vaultId);
      if (key == null) {
        final existing = existingById[note.id];
        if (preserveOmittedPrivateNotes &&
            isProfileDataKeyPrivateVaultId(note.vaultId) &&
            existing != null) {
          records.add(existing.note);
          attachments.addAll(existing.attachments);
          final pendingChange = _pendingChangeForRecord(existing.note);
          if (pendingChange != null) {
            pendingChanges.add(pendingChange);
          }
          continue;
        }
        throw StateError('The key for vault ${note.vaultId} is unavailable.');
      }
      final payload = await _encryptionService.encryptJson(
        payload: _databasePayloadFor(note),
        secretKey: key,
      );
      records.add(
        EncryptedNoteRecord.fromNote(note: note, encryptedPayload: payload),
      );
      attachments.addAll(await _encryptAttachmentRecords(note, secretKey: key));
      final pendingChange = _pendingChangeFor(note);
      if (pendingChange != null) {
        pendingChanges.add(pendingChange);
      }
    }
    if (preserveOmittedPrivateNotes) {
      for (final snapshot in existingSnapshots) {
        if (savedIds.contains(snapshot.note.id) ||
            !isProfileDataKeyPrivateVaultId(snapshot.note.vaultId)) {
          continue;
        }
        records.add(snapshot.note);
        attachments.addAll(snapshot.attachments);
        final pendingChange = _pendingChangeForRecord(snapshot.note);
        if (pendingChange != null) {
          pendingChanges.add(pendingChange);
        }
      }
    }
    await database.replaceAll(
      notes: records,
      attachments: attachments,
      pendingChanges: pendingChanges,
    );
  }

  Future<void> saveOne(NoteEntry note) async {
    if (_isWeb) {
      throw UnsupportedError('Incremental note save is not supported on web.');
    }
    if (_isLockedPlaceholder(note)) {
      return;
    }
    final key = await _keyForVault(note.vaultId);
    if (key == null) {
      throw StateError('The key for vault ${note.vaultId} is unavailable.');
    }
    final database = _database ?? EncryptedNoteDatabase();
    await _saveOneWithKey(note, secretKey: key, database: database);
  }

  Future<void> _saveOneWithKey(
    NoteEntry note, {
    required SecretKey secretKey,
    required EncryptedNoteDatabase database,
  }) async {
    final payload = await _encryptionService.encryptJson(
      payload: _databasePayloadFor(note),
      secretKey: secretKey,
    );
    final attachments = await _encryptAttachmentRecords(
      note,
      secretKey: secretKey,
    );
    await database.upsertOne(
      note: EncryptedNoteRecord.fromNote(note: note, encryptedPayload: payload),
      attachments: attachments,
      pendingChange: _pendingChangeFor(note),
    );
  }

  Future<List<NoteEntry>> _migrateNativeEntries(
    List<NoteEntry> sourceEntries, {
    required EncryptedNoteDatabase database,
    required Future<void> Function() deleteSource,
  }) async {
    final sourceById = <String, NoteEntry>{
      for (final note in sourceEntries) note.id: note,
    };
    final expectedIds = sourceById.keys.toSet();
    final existingById = {
      for (final snapshot in await database.loadAll())
        snapshot.note.id: snapshot.note,
    };

    for (final note in sourceById.values) {
      final existing = existingById[note.id];
      if (existing != null) {
        if (existing.vaultId != note.vaultId) {
          throw StateError(
            'Migration note ${note.id} conflicts with an existing vault.',
          );
        }
        continue;
      }
      final key = await _keyForVault(note.vaultId);
      if (key == null) {
        if (isProfileDataKeyPrivateVaultId(note.vaultId)) {
          continue;
        }
        throw StateError('The key for vault ${note.vaultId} is unavailable.');
      }
      await _saveOneWithKey(note, secretKey: key, database: database);
    }

    // A fresh read is the migration commit check. The source is intentionally
    // retained when even one note could not be persisted (for example, while a
    // private profile is locked) so a later unlock/startup can retry it.
    final snapshots = await database.loadAll();
    final persistedById = {
      for (final snapshot in snapshots) snapshot.note.id: snapshot.note,
    };
    final missingIds = {
      for (final id in expectedIds)
        if (persistedById[id]?.vaultId != sourceById[id]!.vaultId) id,
    };
    if (missingIds.isEmpty) {
      await deleteSource();
    }

    final restored = await _decryptSnapshots(snapshots);
    for (final id in missingIds) {
      final note = sourceById[id]!;
      if (!isProfileDataKeyPrivateVaultId(note.vaultId)) {
        throw StateError('Migration did not persist note $id.');
      }
      restored.add(_lockedPlaceholderFromNote(note));
    }
    return restored;
  }

  Future<List<NoteEntry>> _loadWeb({
    required List<NoteEntry> fallbackNotes,
  }) async {
    final encoded = await _readEncryptedPayload();
    if (encoded == null || encoded.isEmpty) {
      return fallbackNotes;
    }

    final envelope = _WebNoteEnvelope.tryDecode(encoded);
    if (envelope == null) {
      final legacyNotes = await _decodeEntries(encoded);
      final decoded = await _maskLockedLegacyWebNotes(legacyNotes);
      if (!decoded.hasLockedPrivateNotes) {
        await _saveWeb(decoded.notes, preserveOmittedPrivateNotes: true);
      }
      return decoded.notes;
    }

    final restored = await _decryptSnapshots([
      for (final record in envelope.records)
        EncryptedNoteSnapshot(
          note: record,
          attachments: const <EncryptedAttachmentRecord>[],
        ),
    ]);
    final recordIds = envelope.records.map((record) => record.id).toSet();
    var hasLockedLegacyNotes = false;
    final legacyPayload = envelope.legacyEncryptedPayload;
    if (legacyPayload != null && legacyPayload.isNotEmpty) {
      final legacyNotes = await _decodeEntries(legacyPayload);
      final retainedIds = envelope.legacyRetainedNoteIds;
      final remainingLegacy = [
        for (final note in legacyNotes)
          if (!recordIds.contains(note.id) &&
              (retainedIds == null || retainedIds.contains(note.id)))
            note,
      ];
      final decoded = await _maskLockedLegacyWebNotes(remainingLegacy);
      restored.addAll(decoded.notes);
      hasLockedLegacyNotes = decoded.hasLockedPrivateNotes;
    }

    if (legacyPayload != null && !hasLockedLegacyNotes) {
      await _saveWeb(restored, preserveOmittedPrivateNotes: true);
    }
    return restored;
  }

  Future<_DecodedLegacyWebNotes> _maskLockedLegacyWebNotes(
    List<NoteEntry> notes,
  ) async {
    var hasLockedPrivateNotes = false;
    final decoded = <NoteEntry>[];
    for (final note in notes) {
      if (!isProfileDataKeyPrivateVaultId(note.vaultId)) {
        decoded.add(note);
        continue;
      }
      final key = await _keyForVault(note.vaultId);
      if (key == null) {
        hasLockedPrivateNotes = true;
        decoded.add(_lockedPlaceholderFromNote(note));
      } else {
        decoded.add(note);
      }
    }
    return _DecodedLegacyWebNotes(
      notes: decoded,
      hasLockedPrivateNotes: hasLockedPrivateNotes,
    );
  }

  Future<void> _saveWeb(
    List<NoteEntry> notes, {
    required bool preserveOmittedPrivateNotes,
  }) async {
    final currentPayload = await _readEncryptedPayload();
    final envelope = currentPayload == null || currentPayload.isEmpty
        ? const _WebNoteEnvelope(records: <EncryptedNoteRecord>[])
        : _WebNoteEnvelope.tryDecode(currentPayload);
    final existingRecords = <String, EncryptedNoteRecord>{
      for (final record in envelope?.records ?? const <EncryptedNoteRecord>[])
        record.id: record,
    };
    final legacyPayload = envelope == null
        ? currentPayload
        : envelope.legacyEncryptedPayload;
    final decodedLegacyNotes = legacyPayload == null || legacyPayload.isEmpty
        ? const <NoteEntry>[]
        : await _decodeEntries(legacyPayload);
    final retainedLegacyIds = envelope?.legacyRetainedNoteIds;
    final legacyNotes = retainedLegacyIds == null
        ? decodedLegacyNotes
        : decodedLegacyNotes
              .where((note) => retainedLegacyIds.contains(note.id))
              .toList(growable: false);
    final legacyById = <String, NoteEntry>{
      for (final note in legacyNotes) note.id: note,
    };
    final suppliedIds = notes.map((note) => note.id).toSet();
    final nextRecords = <String, EncryptedNoteRecord>{};
    final retainedLegacyNotes = <String, NoteEntry>{};

    for (final note in notes) {
      if (_isLockedPlaceholder(note)) {
        final existing = existingRecords[note.id];
        if (existing != null) {
          nextRecords[note.id] = existing;
          continue;
        }
        final legacy = legacyById[note.id];
        if (legacy == null) {
          continue;
        }
        final key = await _keyForVault(legacy.vaultId);
        if (key == null) {
          retainedLegacyNotes[legacy.id] = legacy;
        } else {
          nextRecords[legacy.id] = await _encryptWebRecord(
            legacy,
            secretKey: key,
          );
        }
        continue;
      }

      final key = await _keyForVault(note.vaultId);
      if (key == null) {
        throw StateError('The key for vault ${note.vaultId} is unavailable.');
      }
      nextRecords[note.id] = await _encryptWebRecord(note, secretKey: key);
    }

    if (preserveOmittedPrivateNotes) {
      for (final record in existingRecords.values) {
        if (suppliedIds.contains(record.id) ||
            !isProfileDataKeyPrivateVaultId(record.vaultId)) {
          continue;
        }
        nextRecords[record.id] = record;
      }
      for (final legacy in legacyById.values) {
        if (suppliedIds.contains(legacy.id) ||
            nextRecords.containsKey(legacy.id) ||
            !isProfileDataKeyPrivateVaultId(legacy.vaultId)) {
          continue;
        }
        final key = await _keyForVault(legacy.vaultId);
        if (key == null) {
          retainedLegacyNotes[legacy.id] = legacy;
        } else {
          nextRecords[legacy.id] = await _encryptWebRecord(
            legacy,
            secretKey: key,
          );
        }
      }
    }

    // A locked v1 private note cannot be moved to its profile key yet. Keep
    // the original opaque payload byte-for-byte with an allowlist of the IDs
    // still needed. Never create fresh private ciphertext with the everyday
    // key; the legacy payload is removed as soon as every profile is unlocked.
    final nextLegacyPayload = retainedLegacyNotes.isEmpty
        ? null
        : legacyPayload;

    await _writeEncryptedPayload(
      jsonEncode(
        _WebNoteEnvelope(
          records: nextRecords.values.toList(growable: false),
          legacyEncryptedPayload: nextLegacyPayload,
          legacyRetainedNoteIds: retainedLegacyNotes.keys.toSet(),
        ).toJson(),
      ),
    );
  }

  Future<EncryptedNoteRecord> _encryptWebRecord(
    NoteEntry note, {
    required SecretKey secretKey,
  }) async {
    final payload = await _encryptionService.encryptJson(
      payload: note.toJson(),
      secretKey: secretKey,
    );
    return EncryptedNoteRecord.fromNote(note: note, encryptedPayload: payload);
  }

  Future<List<NoteEntry>> _decodeEntries(String encodedPayload) async {
    final key = await _keyForVault('everyday');
    if (key == null) {
      throw StateError('Normal note key is unavailable.');
    }
    final payload = await _encryptionService.decryptJson(
      encodedPayload: encodedPayload,
      secretKey: key,
    );
    final notes = (payload['notes'] as List<dynamic>? ?? const <dynamic>[])
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(NoteEntry.fromJson)
        .toList(growable: false);
    return notes;
  }

  List<NoteEntry> _decodePlaintextEntries(String legacyPayload) {
    return (jsonDecode(legacyPayload) as List<dynamic>)
        .map((entry) => Map<String, dynamic>.from(entry as Map))
        .map(NoteEntry.fromJson)
        .toList(growable: false);
  }

  Future<List<NoteEntry>> _decryptSnapshots(
    List<EncryptedNoteSnapshot> snapshots,
  ) async {
    final notes = <NoteEntry>[];
    for (final snapshot in snapshots) {
      final record = snapshot.note;
      final key = await _keyForVault(record.vaultId);
      if (key == null) {
        notes.add(_lockedPlaceholder(record));
        continue;
      }
      Map<String, dynamic> payload;
      List<NoteAttachment> attachmentList;
      try {
        payload = await _encryptionService.decryptJson(
          encodedPayload: record.encryptedPayload,
          secretKey: key,
        );
        attachmentList = await _decryptAttachmentPayloads(
          snapshot.attachments,
          secretKey: key,
        );
      } catch (_) {
        if (isProfileDataKeyPrivateVaultId(record.vaultId)) {
          notes.add(_lockedPlaceholder(record));
          continue;
        }
        rethrow;
      }
      final legacyAttachments =
          (payload['attachments'] as List<dynamic>? ?? const <dynamic>[])
              .map((entry) => Map<String, dynamic>.from(entry as Map))
              .map(NoteAttachment.fromJson)
              .toList(growable: false);
      final mergedAttachments = attachmentList.isNotEmpty
          ? attachmentList
          : legacyAttachments;
      notes.add(
        NoteEntry.fromJson({
          ...payload,
          'attachments': mergedAttachments
              .map((attachment) => attachment.toJson())
              .toList(),
        }).copyWith(
          createdAt: record.createdAt,
          updatedAt: record.updatedAt,
          deletedAt: record.deletedAt,
          isPinned: record.isPinned,
          revision: record.revision,
          syncState: record.syncState,
          deviceId: record.deviceId,
          contentHash: record.contentHash,
        ),
      );
    }
    return notes;
  }

  Future<List<NoteAttachment>> _decryptAttachmentPayloads(
    List<EncryptedAttachmentRecord> attachments, {
    required SecretKey secretKey,
  }) async {
    final decoded = <NoteAttachment>[];
    for (final attachment in attachments) {
      final payload = await _encryptionService.decryptJson(
        encodedPayload: attachment.encryptedPayload,
        secretKey: secretKey,
      );
      decoded.add(NoteAttachment.fromJson(payload));
    }
    return decoded;
  }

  Future<List<EncryptedAttachmentRecord>> _encryptAttachmentRecords(
    NoteEntry note, {
    required SecretKey secretKey,
  }) async {
    if (note.attachments.isEmpty) {
      return const <EncryptedAttachmentRecord>[];
    }
    return Future.wait([
      for (var i = 0; i < note.attachments.length; i++)
        _encryptionService
            .encryptJson(
              payload: note.attachments[i].toJson(),
              secretKey: secretKey,
            )
            .then(
              (payload) => EncryptedAttachmentRecord(
                noteId: note.id,
                position: i,
                encryptedPayload: payload,
              ),
            ),
    ]);
  }

  Map<String, dynamic> _databasePayloadFor(NoteEntry note) {
    final payload = Map<String, dynamic>.from(note.toJson());
    payload['attachments'] = const <Map<String, dynamic>>[];
    return payload;
  }

  PendingNoteChangeRecord? _pendingChangeFor(NoteEntry note) {
    if (note.syncState != NoteSyncState.pendingUpload &&
        note.syncState != NoteSyncState.conflict &&
        note.syncState != NoteSyncState.pendingDelete) {
      return null;
    }
    return PendingNoteChangeRecord(
      noteId: note.id,
      vaultId: note.vaultId,
      revision: note.revision,
      action: note.deletedAt == null
          ? PendingNoteChangeAction.upsert
          : PendingNoteChangeAction.delete,
      queuedAt: note.updatedAt ?? note.createdAt,
      contentHash: note.contentHash,
      deletedAt: note.deletedAt,
    );
  }

  PendingNoteChangeRecord? _pendingChangeForRecord(EncryptedNoteRecord note) {
    if (note.syncState != NoteSyncState.pendingUpload &&
        note.syncState != NoteSyncState.conflict &&
        note.syncState != NoteSyncState.pendingDelete) {
      return null;
    }
    return PendingNoteChangeRecord(
      noteId: note.id,
      vaultId: note.vaultId,
      revision: note.revision,
      action: note.deletedAt == null
          ? PendingNoteChangeAction.upsert
          : PendingNoteChangeAction.delete,
      queuedAt: note.updatedAt ?? note.createdAt,
      contentHash: note.contentHash,
      deletedAt: note.deletedAt,
    );
  }

  Future<void> deleteById(String noteId) async {
    if (!_isWeb) {
      final database = _database ?? EncryptedNoteDatabase();
      await database.deleteNoteById(noteId);
      return;
    }
    final notes = await load(fallbackNotes: const <NoteEntry>[]);
    await save(notes.where((note) => note.id != noteId).toList());
  }

  Future<void> deleteByVaultId(String vaultId) async {
    if (!_isWeb) {
      final database = _database ?? EncryptedNoteDatabase();
      await database.deleteNotesByVaultId(vaultId);
      return;
    }
    final notes = await load(fallbackNotes: const <NoteEntry>[]);
    await save(notes.where((note) => note.vaultId != vaultId).toList());
  }

  Future<int> storagePayloadSizeBytes() async {
    if (!_isWeb) {
      final database = _database;
      if (database != null) {
        return database.storagePayloadSizeBytes();
      }
      final file = await _resolveStorageFile();
      if (!await file.exists()) {
        return 0;
      }
      return file.length();
    }

    final prefs = await _sharedPreferencesProvider();
    final encrypted = prefs.getString(webStorageKey);
    final legacy = prefs.getString(legacyStorageKey);
    return (encrypted?.length ?? 0) + (legacy?.length ?? 0);
  }

  Future<SecretKey?> _keyForVault(String vaultId) {
    final profileKeyService = _profileDataKeyService;
    if (profileKeyService != null) {
      return profileKeyService.keyForVault(vaultId);
    }
    if (_isWeb && isProfileDataKeyPrivateVaultId(vaultId)) {
      return Future<SecretKey?>.value();
    }
    return _masterKeyService.obtainOrCreate();
  }

  NoteEntry _lockedPlaceholder(EncryptedNoteRecord record) {
    return NoteEntry(
      id: record.id,
      vaultId: record.vaultId,
      title: 'Locked private note',
      body: '',
      createdAt: record.createdAt,
      updatedAt: record.updatedAt,
      deletedAt: record.deletedAt,
      deviceId: 'locked-private-note',
      contentHash: record.contentHash,
      isPinned: record.isPinned,
      revision: record.revision,
      syncState: record.syncState,
    );
  }

  NoteEntry _lockedPlaceholderFromNote(NoteEntry note) {
    return NoteEntry(
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
  }

  bool _isLockedPlaceholder(NoteEntry note) {
    return note.deviceId == 'locked-private-note' &&
        isProfileDataKeyPrivateVaultId(note.vaultId);
  }

  Future<String?> _readEncryptedPayload() async {
    if (_isWeb) {
      final prefs = await _sharedPreferencesProvider();
      return prefs.getString(webStorageKey);
    }

    final file = await _resolveStorageFile();
    if (!await file.exists()) {
      return null;
    }
    return file.readAsString();
  }

  Future<void> _writeEncryptedPayload(String payload) async {
    if (_isWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.setString(webStorageKey, payload);
      return;
    }

    final file = await _resolveStorageFile();
    await file.create(recursive: true);
    await file.writeAsString(payload, flush: true);
  }

  Future<void> _deleteEncryptedPayload() async {
    if (_isWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.remove(webStorageKey);
      return;
    }

    final file = await _resolveStorageFile();
    if (await file.exists()) {
      await file.delete();
    }
  }

  Future<File> _resolveStorageFile() async {
    final directory = await _directoryProvider();
    return File(path.join(directory.path, storageFileName));
  }
}

class _DecodedLegacyWebNotes {
  const _DecodedLegacyWebNotes({
    required this.notes,
    required this.hasLockedPrivateNotes,
  });

  final List<NoteEntry> notes;
  final bool hasLockedPrivateNotes;
}

class _WebNoteEnvelope {
  const _WebNoteEnvelope({
    required this.records,
    this.legacyEncryptedPayload,
    this.legacyRetainedNoteIds,
  });

  static const version = 2;

  final List<EncryptedNoteRecord> records;
  final String? legacyEncryptedPayload;
  final Set<String>? legacyRetainedNoteIds;

  Map<String, dynamic> toJson() {
    return {
      'version': version,
      'format': 'vault-separated-records',
      'records': [
        for (final record in records)
          {
            ...record.toPayloadJson(),
            'encryptedPayload': record.encryptedPayload,
          },
      ],
      if (legacyEncryptedPayload != null)
        'legacyEncryptedPayload': legacyEncryptedPayload,
      if (legacyEncryptedPayload != null)
        'legacyRetainedNoteIds': legacyRetainedNoteIds == null
            ? null
            : (legacyRetainedNoteIds!.toList()..sort()),
    };
  }

  static _WebNoteEnvelope? tryDecode(String encoded) {
    dynamic decoded;
    try {
      decoded = jsonDecode(encoded);
    } catch (_) {
      return null;
    }
    if (decoded is! Map || decoded['version'] != version) {
      return null;
    }
    if (decoded['format'] != 'vault-separated-records' ||
        decoded['records'] is! List) {
      throw const FormatException('Invalid encrypted Web note envelope.');
    }
    final payload = Map<String, dynamic>.from(decoded);
    final records = <EncryptedNoteRecord>[];
    for (final rawRecord in payload['records'] as List<dynamic>) {
      if (rawRecord is! Map) {
        throw const FormatException('Invalid encrypted Web note record.');
      }
      final record = Map<String, dynamic>.from(rawRecord);
      final encryptedPayload = record['encryptedPayload'];
      if (encryptedPayload is! String || encryptedPayload.isEmpty) {
        throw const FormatException('Invalid encrypted Web note payload.');
      }
      records.add(
        EncryptedNoteRecord.fromLegacyPayload(
          encryptedPayload: encryptedPayload,
          payload: record,
        ),
      );
    }
    final legacy = payload['legacyEncryptedPayload'];
    if (legacy != null && legacy is! String) {
      throw const FormatException('Invalid legacy Web note payload.');
    }
    final rawRetainedIds = payload['legacyRetainedNoteIds'];
    if (rawRetainedIds != null && rawRetainedIds is! List) {
      throw const FormatException('Invalid retained legacy Web note IDs.');
    }
    final retainedIds = rawRetainedIds == null
        ? null
        : (rawRetainedIds as List<dynamic>).map((id) {
            if (id is! String || id.isEmpty) {
              throw const FormatException(
                'Invalid retained legacy Web note ID.',
              );
            }
            return id;
          }).toSet();
    return _WebNoteEnvelope(
      records: records,
      legacyEncryptedPayload: legacy as String?,
      legacyRetainedNoteIds: retainedIds,
    );
  }
}
