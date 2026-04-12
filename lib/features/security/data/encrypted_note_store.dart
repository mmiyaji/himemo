import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import 'encryption_service.dart';
import 'master_key_service.dart';

class EncryptedNoteStore {
  EncryptedNoteStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.storageFileName = 'notes.entries.enc.v1',
    this.legacyStorageKey = 'notes.entries.v1',
    this.webStorageKey = 'notes.entries.encrypted.v1',
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String storageFileName;
  final String legacyStorageKey;
  final String webStorageKey;

  Future<List<NoteEntry>> load({
    required List<NoteEntry> fallbackNotes,
  }) async {
    try {
      final encoded = await _readEncryptedPayload();
      if (encoded != null && encoded.isNotEmpty) {
        return _decodeEntries(encoded);
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
    final payload = {
      'notes': notes.map((entry) => entry.toJson()).toList(),
    };
    final key = await _masterKeyService.obtainOrCreate();
    final encoded = await _encryptionService.encryptJson(
      payload: payload,
      secretKey: key,
    );
    await _writeEncryptedPayload(encoded);
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

  Future<File> _resolveStorageFile() async {
    final directory = await _directoryProvider();
    return File(path.join(directory.path, storageFileName));
  }
}
