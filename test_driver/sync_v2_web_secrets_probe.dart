// Browser-only test fixture; never imported by production.
import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:flutter/widgets.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/security/data/sync_v2_admin_store.dart';
import 'package:himemo/features/security/data/sync_v2_device_admin_store.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:web/web.dart' as web;

const account = 'web-probe-account';
const generation = 'web-secrets-probe';
const profile = 'web-secrets-profile';
const note = 'web-secrets-note';
const body = 'confidential-v2-browser-fixture';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = MemorySecureKeyValueStore();
  final syncKey = SecretKey(List<int>.filled(32, 17));
  final adminKey = SecretKey(List<int>.filled(32, 73));
  final encryption = EncryptionService();
  final headers = SyncV2HeaderCodec(encryption);
  final inbox = SyncV2Inbox.open(headers);
  final repository = SyncV2NoteRepository(
    inbox,
    headers,
    SyncV2PayloadCodec(encryption),
  );
  final enrollment = SyncV2EnrollmentStore(store);
  final adminStore = SyncV2DeviceAdminStore(store);
  SyncV2UnlockedProfileKey? access;
  try {
    if (await store.read('probe.sync-code') != null ||
        await store.read('probe.admin-code') != null) {
      throw StateError('fresh memory store was not empty');
    }
    final wrap = await encryption.encryptBytes(
      clearBytes: List<int>.filled(32, 29),
      secretKey: syncKey,
      additionalData: utf8.encode(
        jsonEncode([
          'himemo-sync-v2-registration',
          1,
          account,
          generation,
          'normal-sync-wrap',
          profile,
          'key',
        ]),
      ),
    );
    access = await SyncV2UnlockedProfileKey.unlockNormal(
      encryption: encryption,
      accountId: account,
      generationId: generation,
      profileId: profile,
      keyId: 'key',
      syncWrap: wrap,
      syncKey: syncKey,
    );
    if (Uri.base.queryParameters['phase'] == 'verify') {
      final snapshot = await repository.readNote(
        generationId: generation,
        profileId: profile,
        noteId: note,
        syncKey: syncKey,
        profileKey: access,
      );
      if (!snapshot.canCompareVersions ||
          snapshot.versions.single.body?['text'] != body) {
        throw StateError('encrypted note was not retained');
      }
      access.destroy();
      syncKey.destroy();
      adminKey.destroy();
      store.clear();
      await inbox.close();
      web.document.title = 'V2_SECRETS_RELOADED';
    } else {
      await enrollment.saveVerified((
        accountId: account,
        generationId: generation,
        syncKey: syncKey,
      ));
      await adminStore.save(
        accountId: account,
        generationId: generation,
        adminKey: adminKey,
      );
      final syncCode = base64UrlEncode(
        utf8.encode(
          jsonEncode({
            'version': 1,
            'account': account,
            'generation': generation,
            'key': base64UrlEncode(await syncKey.extractBytes()),
            'format': 'himemo.sync.v2.recovery',
          }),
        ),
      );
      final adminCode = await SyncV2AdminStore(
        store,
        encryption,
        generationId: generation,
      ).encodeRecoveryCode(adminKey);
      await store.write('probe.sync-code', syncCode);
      await store.write('probe.admin-code', adminCode);
      final restoredSync = await enrollment.readForAccount(account);
      final restoredAdmin = await adminStore.read(
        accountId: account,
        generationId: generation,
      );
      if (restoredSync == null ||
          restoredAdmin == null ||
          base64Encode(await restoredSync.syncKey.extractBytes()) ==
              base64Encode(await restoredAdmin.extractBytes())) {
        throw StateError('session key isolation failed');
      }
      restoredSync.syncKey.destroy();
      restoredAdmin.destroy();
      await repository.save(
        generationId: generation,
        profileId: profile,
        noteId: note,
        changeId: 'web-secrets-change',
        expectedHeadIds: {},
        body: {'text': body},
        syncKey: syncKey,
        profileKey: access,
      );
      web.document.documentElement!.setAttribute(
        'data-sync-code-hash',
        crypto.sha256.convert(utf8.encode(syncCode)).toString(),
      );
      web.document.documentElement!.setAttribute(
        'data-admin-code-hash',
        crypto.sha256.convert(utf8.encode(adminCode)).toString(),
      );
      web.document.title = 'V2_SECRETS_ACTIVE';
      Timer.periodic(const Duration(milliseconds: 50), (timer) async {
        if (web.document.documentElement?.getAttribute(
              'data-v2-secret-command',
            ) !=
            'clear') {
          return;
        }
        timer.cancel();
        try {
          store.clear();
          access!.destroy();
          syncKey.destroy();
          adminKey.destroy();
          if (await store.read('probe.sync-code') != null ||
              await store.read('probe.admin-code') != null ||
              await enrollment.readForAccount(account) != null ||
              await adminStore.read(
                    accountId: account,
                    generationId: generation,
                  ) !=
                  null ||
              !syncKey.isDestroyed ||
              !adminKey.isDestroyed) {
            throw StateError('session credentials remained after clear');
          }
          await inbox.close();
          web.document.title = 'V2_SECRETS_CLEARED';
        } catch (error, stack) {
          debugPrint('V2 secrets clear failed: $error\n$stack');
          web.document.title = 'V2_SECRETS_FAILED';
        }
      });
    }
  } catch (error, stack) {
    debugPrint('V2 secrets probe failed: $error\n$stack');
    access?.destroy();
    syncKey.destroy();
    adminKey.destroy();
    store.clear();
    try {
      await inbox.close();
    } catch (_) {}
    web.document.title = 'V2_SECRETS_FAILED';
  }
  runApp(const SizedBox());
}
