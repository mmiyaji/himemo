import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../security/data/encryption_service.dart';
import '../../security/data/master_key_service.dart';
import 'sync_engine.dart';

class StoredSyncBundle {
  const StoredSyncBundle({
    required this.reference,
    required this.noteCount,
    required this.attachmentCount,
  });

  final String reference;
  final int noteCount;
  final int attachmentCount;
}

class SecureSyncBundleStore {
  SecureSyncBundleStore({
    required EncryptionService encryptionService,
    required MasterKeyService masterKeyService,
    Future<Directory> Function()? directoryProvider,
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    this.webStorageKey = 'sync.bundle.latest',
    this.fileName = 'latest_sync_bundle.enc',
  }) : _encryptionService = encryptionService,
       _masterKeyService = masterKeyService,
       _directoryProvider = directoryProvider ?? getApplicationSupportDirectory,
       _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  final EncryptionService _encryptionService;
  final MasterKeyService _masterKeyService;
  final Future<Directory> Function() _directoryProvider;
  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final String webStorageKey;
  final String fileName;

  Future<StoredSyncBundle> writeBundle(PreparedSyncSnapshot snapshot) async {
    final key = await _masterKeyService.obtainOrCreate();
    final payload = await _encryptionService.encryptJson(
      payload: {
        'deviceId': snapshot.deviceId,
        'exportedAt': snapshot.exportedAt.toIso8601String(),
        'summary': {
          'totalChanges': snapshot.summary.totalChanges,
          'upserts': snapshot.summary.upserts,
          'deletes': snapshot.summary.deletes,
          'lastQueuedAt': snapshot.summary.lastQueuedAt?.toIso8601String(),
        },
        'notes': [
          for (final entry in snapshot.notes)
            {
              'action': entry.action.name,
              'note': entry.note.toJson(),
            },
        ],
        'attachments': [
          for (final attachment in snapshot.attachments)
            {
              'id': attachment.id,
              'type': attachment.type.name,
              'label': attachment.label,
              'encryptedPayload': attachment.encryptedPayload,
            },
        ],
      },
      secretKey: key,
    );

    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      await prefs.setString(webStorageKey, payload);
      return StoredSyncBundle(
        reference: webStorageKey,
        noteCount: snapshot.notes.length,
        attachmentCount: snapshot.attachments.length,
      );
    }

    final directory = await _directoryProvider();
    final file = File(path.join(directory.path, 'sync_exports', fileName));
    await file.create(recursive: true);
    await file.writeAsString(payload, flush: true);
    return StoredSyncBundle(
      reference: file.path,
      noteCount: snapshot.notes.length,
      attachmentCount: snapshot.attachments.length,
    );
  }

  Future<Map<String, dynamic>?> readBundleJson(String reference) async {
    String? payload;
    if (kIsWeb) {
      final prefs = await _sharedPreferencesProvider();
      payload = prefs.getString(reference);
    } else {
      final file = File(reference);
      if (await file.exists()) {
        payload = await file.readAsString();
      }
    }
    if (payload == null || payload.isEmpty) {
      return null;
    }
    final key = await _masterKeyService.obtainOrCreate();
    return _encryptionService.decryptJson(
      encodedPayload: payload,
      secretKey: key,
    );
  }
}
