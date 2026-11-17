// Standalone browser-only regression probe. Never included in production builds.
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
// The probe creates snapshots using the former Web database implementation.
// ignore: deprecated_member_use
import 'package:drift/web.dart';
import 'package:flutter/widgets.dart';
import 'package:himemo/features/security/data/encrypted_note_database_executor.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:web/web.dart' as web;

const _account = 'web-probe-account';
const _generation = 'web-persistence-probe';
const _profile = 'web-probe-profile';
const _record = 'web-probe-note';
const _keyId = 'web-probe-key';
const _message = 'v2-browser-persistence-fixture';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final encryption = EncryptionService();
  final syncKey = SecretKey(List<int>.filled(32, 17));
  final headers = SyncV2HeaderCodec(encryption);
  final phase = Uri.base.queryParameters['phase'];
  final inbox = switch (phase) {
    'legacy-write' => SyncV2Inbox(WebDatabase('himemo_sync_v2_web'), headers),
    'legacy-indexed-write' => SyncV2Inbox(
      WebDatabase.withStorage(
        // Reproduce the legacy IndexedDB format for migration tests.
        // ignore: experimental_member_use
        DriftWebStorage.indexedDb(
          'himemo_sync_v2_web',
          migrateFromLocalStorage: false,
        ),
      ),
      headers,
    ),
    'preview-write' => SyncV2Inbox(
      createSyncV2LocalPreviewDatabaseExecutor(),
      headers,
    ),
    _ => SyncV2Inbox.open(headers),
  };
  final repository = SyncV2NoteRepository(
    inbox,
    headers,
    SyncV2PayloadCodec(encryption),
  );
  var result = 'V2_STORAGE_FAILED';
  SyncV2UnlockedProfileKey? profileKey;
  try {
    final wrap = await encryption.encryptBytes(
      clearBytes: List<int>.filled(32, 29),
      secretKey: syncKey,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          _account,
          _generation,
          'normal-sync-wrap',
          _profile,
          _keyId,
        ]),
      ),
    );
    profileKey = await SyncV2UnlockedProfileKey.unlockNormal(
      encryption: encryption,
      accountId: _account,
      generationId: _generation,
      profileId: _profile,
      keyId: _keyId,
      syncWrap: wrap,
      syncKey: syncKey,
    );
    if (phase == 'legacy-write' ||
        phase == 'legacy-indexed-write' ||
        phase == 'write' ||
        phase == 'hold' ||
        phase == 'same-tab-reopen' ||
        phase == 'same-tab-slow-close' ||
        phase == 'preview-write') {
      await repository.save(
        generationId: _generation,
        profileId: _profile,
        noteId: _record,
        changeId: 'web-probe-change',
        expectedHeadIds: {},
        body: {'message': _message},
        syncKey: syncKey,
        profileKey: profileKey,
      );
      final outbox = await inbox.readOutbox(
        generationId: _generation,
        limit: 10,
      );
      if (outbox.length != 1 ||
          outbox.single.encryptedHeader.contains(_message) ||
          utf8
              .decode(outbox.single.encryptedPayload!, allowMalformed: true)
              .contains(_message)) {
        throw StateError('plaintext in encrypted v2 outbox');
      }
      if (phase == 'same-tab-reopen' || phase == 'same-tab-slow-close') {
        final closing = phase == 'same-tab-slow-close'
            ? Future<void>.delayed(const Duration(seconds: 6), inbox.close)
            : inbox.close();
        final next = SyncV2Inbox.open(headers);
        try {
          await next.customSelect('SELECT 1').get();
          await closing;
        } finally {
          await next.close();
        }
      }
      result = switch (phase) {
        'legacy-write' => 'V2_STORAGE_LEGACY_OK',
        'legacy-indexed-write' => 'V2_STORAGE_LEGACY_INDEXED_OK',
        'hold' => 'V2_STORAGE_LOCK_HELD',
        'preview-write' => 'V2_STORAGE_PREVIEW_OK',
        'same-tab-reopen' => 'V2_STORAGE_SAME_TAB_OK',
        'same-tab-slow-close' => 'V2_STORAGE_SAME_TAB_OK',
        _ => 'V2_STORAGE_WRITE_OK',
      };
    } else if (phase == 'other-db') {
      // Create Drift's shared object store before V2 migration. Built-in Drift
      // migration only runs when this shared store is first created.
      final other = SyncV2Inbox(
        WebDatabase.withStorage(
          // Seed the legacy shared object store before the migration.
          // ignore: experimental_member_use
          DriftWebStorage.indexedDb('unrelated-probe'),
        ),
        headers,
      );
      try {
        await other.customSelect('SELECT 1').get();
      } finally {
        await other.close();
      }
      result = 'V2_STORAGE_OTHER_OK';
    } else {
      final snapshot = await repository.readNote(
        generationId: _generation,
        profileId: _profile,
        noteId: _record,
        syncKey: syncKey,
        profileKey: profileKey,
      );
      if (!snapshot.canCompareVersions ||
          snapshot.versions.single.body?['message'] != _message) {
        throw StateError('missing or invalid persisted v2 note');
      }
      final outbox = await inbox.readOutbox(
        generationId: _generation,
        limit: 10,
      );
      if (outbox.length != 1) throw StateError('missing persisted v2 outbox');
      if (phase == 'read') {
        await inbox.customStatement(
          'DELETE FROM sync_v2_inbox WHERE generation_id = ?',
          [_generation],
        );
        await inbox.customStatement(
          'DELETE FROM sync_v2_outbox WHERE generation_id = ?',
          [_generation],
        );
      }
      result = phase == 'migrate'
          ? 'V2_STORAGE_MIGRATE_OK'
          : 'V2_STORAGE_READ_OK';
    }
  } catch (error, stack) {
    debugPrint('Web storage probe failed: $error\n$stack');
    final details = error.toString();
    result = switch (details) {
      final s
          when s.contains('open in another tab') ||
              s.contains('open in this tab') =>
        'V2_STORAGE_LOCKED',
      final s when s.contains('Web Locks are required') =>
        'V2_STORAGE_NO_LOCKS',
      final s when s.contains('durable, concurrency-safe') =>
        'V2_STORAGE_UNSUPPORTED',
      final s when s.contains('existing v2 database storage is unavailable') =>
        'V2_STORAGE_BACKEND_UNAVAILABLE',
      final s when s.contains('simulated migration read failure') =>
        'V2_STORAGE_MIGRATION_ERROR',
      final s when s.contains('simulated marker quota') =>
        'V2_STORAGE_MARKER_ERROR',
      final s when s.contains('Invalid legacy v2 SQLite database') =>
        'V2_STORAGE_CORRUPT_LEGACY',
      final s when s.contains('worker state is uncertain') =>
        'V2_STORAGE_WORKER_UNCERTAIN',
      final s
          when s.contains('require recovery') ||
              s.contains('requires recovery') =>
        'V2_STORAGE_RECOVERY_REQUIRED',
      _ => 'V2_STORAGE_FAILED',
    };
  } finally {
    profileKey?.destroy();
    syncKey.destroy();
    if (phase != 'other-db' &&
        phase != 'hold' &&
        phase != 'same-tab-reopen' &&
        phase != 'same-tab-slow-close') {
      try {
        await inbox.close();
      } catch (error) {
        debugPrint('Web storage probe close failed: $error');
        if (result.endsWith('_OK')) result = 'V2_STORAGE_FAILED';
      }
    }
  }
  web.document.title = result;
  runApp(const SizedBox());
}
