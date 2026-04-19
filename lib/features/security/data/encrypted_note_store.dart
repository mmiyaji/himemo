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

class EncryptedNoteStore {
  EncryptedNoteStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    EncryptedNoteDatabase? database,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.storageFileName = 'notes.entries.enc.v1',
    this.legacyStorageKey = 'notes.entries.v1',
    this.webStorageKey = 'notes.entries.encrypted.v1',
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _database = database,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final EncryptedNoteDatabase? _database;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String storageFileName;
  final String legacyStorageKey;
  final String webStorageKey;

  Future<List<NoteEntry>> load({
    required List<NoteEntry> fallbackNotes,
  }) async {
    try {
      if (!kIsWeb) {
        final database = _database ?? EncryptedNoteDatabase();
        final snapshots = await database.loadAll();
        if (snapshots.isNotEmpty) {
          return _decryptSnapshots(snapshots);
        }
      }

      final encoded = await _readEncryptedPayload();
      if (encoded != null && encoded.isNotEmpty) {
        final migrated = await _decodeEntries(encoded);
        if (!kIsWeb) {
          await save(migrated);
          await _deleteEncryptedPayload();
        }
        return migrated;
      }

      final prefs = await _sharedPreferencesProvider();
      final legacy = prefs.getString(legacyStorageKey);
      if (legacy == null || legacy.isEmpty) {
        return fallbackNotes;
      }

      final migrated = _decodePlaintextEntries(legacy);
      await save(migrated);
      await prefs.remove(legacyStorageKey);
      return migrated;
    } catch (_) {
      return fallbackNotes;
    }
  }

  Future<void> save(List<NoteEntry> notes) async {
    if (kIsWeb) {
      final payload = {
        'notes': notes.map((entry) => entry.toJson()).toList(),
      };
      final key = await _masterKeyService.obtainOrCreate();
      final encoded = await _encryptionService.encryptJson(
        payload: payload,
        secretKey: key,
      );
      await _writeEncryptedPayload(encoded);
      return;
    }

    final key = await _masterKeyService.obtainOrCreate();
    final database = _database ?? EncryptedNoteDatabase();
    final records = <EncryptedNoteRecord>[];
    final attachments = <EncryptedAttachmentRecord>[];
    final pendingChanges = <PendingNoteChangeRecord>[];
    for (final note in notes) {
      final payload = await _encryptionService.encryptJson(
        payload: _databasePayloadFor(note),
        secretKey: key,
      );
      records.add(
        EncryptedNoteRecord.fromNote(note: note, encryptedPayload: payload),
      );
      for (var i = 0; i < note.attachments.length; i++) {
        final attachmentPayload = await _encryptionService.encryptJson(
          payload: note.attachments[i].toJson(),
          secretKey: key,
        );
        attachments.add(
          EncryptedAttachmentRecord(
            noteId: note.id,
            position: i,
            encryptedPayload: attachmentPayload,
          ),
        );
      }
      if (note.syncState != NoteSyncState.synced &&
          note.syncState != NoteSyncState.localOnly) {
        pendingChanges.add(
          PendingNoteChangeRecord(
            noteId: note.id,
            vaultId: note.vaultId,
            revision: note.revision,
            action: note.deletedAt == null
                ? PendingNoteChangeAction.upsert
                : PendingNoteChangeAction.delete,
            queuedAt: note.updatedAt ?? note.createdAt,
            contentHash: note.contentHash,
            deletedAt: note.deletedAt,
          ),
        );
      }
    }
    await database.replaceAll(
      notes: records,
      attachments: attachments,
      pendingChanges: pendingChanges,
    );
  }

  Future<List<NoteEntry>> _decodeEntries(String encodedPayload) async {
    final key = await _masterKeyService.obtainOrCreate();
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
    final key = await _masterKeyService.obtainOrCreate();
    final notes = <NoteEntry>[];
    for (final snapshot in snapshots) {
      final record = snapshot.note;
      final payload = await _encryptionService.decryptJson(
        encodedPayload: record.encryptedPayload,
        secretKey: key,
      );
      final attachmentList = await _decryptAttachmentPayloads(
        snapshot.attachments,
        secretKey: key,
      );
      final legacyAttachments = (payload['attachments'] as List<dynamic>? ?? const <dynamic>[])
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

  Map<String, dynamic> _databasePayloadFor(NoteEntry note) {
    final payload = Map<String, dynamic>.from(note.toJson());
    payload['attachments'] = const <Map<String, dynamic>>[];
    return payload;
  }

  Future<String?> _readEncryptedPayload() async {
    if (kIsWeb) {
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
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.setString(webStorageKey, payload);
      return;
    }

    final file = await _resolveStorageFile();
    await file.create(recursive: true);
    await file.writeAsString(payload, flush: true);
  }

  Future<void> _deleteEncryptedPayload() async {
    if (kIsWeb) {
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
