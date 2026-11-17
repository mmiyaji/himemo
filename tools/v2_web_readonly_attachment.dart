// Synthetic-only Web entry for the readonly attachment Playwright smoke.
// It seeds the regular encrypted V2 protocol in memory and never uses CloudKit.
import 'dart:convert';

import 'package:drift/wasm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_readonly.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_web_screen.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_cloudkit_sandbox.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:web/web.dart' as web;
// ignore: depend_on_referenced_packages
import 'package:sqlite3/wasm.dart' show InMemoryFileSystem, WasmSqlite3;

const _namespace = 'readonly_web_fixture_20261116';
const _account = 'synthetic-readonly-web-account';
const _png =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGP4z8DwHwAFAAH/iZk9HQAAAABJRU5ErkJggg==';

Future<void> _savePhoto(
  SyncV2WorkspaceController workspace, {
  required String title,
  required String draftId,
}) async {
  final bytes = base64Decode(_png);
  await workspace.saveNote(
    title: title,
    body: '',
    blocks: [
      NoteBlock(
        type: NoteBlockType.photo,
        attachment: NoteAttachment(
          type: AttachmentType.photo,
          label: 'synthetic-attachment.png',
          filePath: 'v2pending:$draftId',
        ),
      ),
    ],
    addedFiles: [
      SyncV2PendingAttachment(
        label: 'synthetic-attachment.png',
        type: AttachmentType.photo,
        bytes: bytes,
        draftId: draftId,
      ),
    ],
  );
}

class _MockCloud {
  final calls = <String>[];
  final _zones = <String, Map<String, Map<String, Object?>>>{};

  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    calls.add(method);
    if (method == 'cloudKitV2AccountId') return _account;
    final generation = args['generationId'] as String?;
    if (generation == null ||
        !RegExp(r'^[A-Za-z0-9_-]{1,80}$').hasMatch(generation)) {
      throw PlatformException(code: 'cloudkit_v2_invalidRequest');
    }
    final zone = 'HiMemoSyncV2WebTest-$_namespace-$generation';
    final records = _zones.putIfAbsent(
      zone,
      () => <String, Map<String, Object?>>{},
    );
    switch (method) {
      case 'cloudKitV2Prepare':
        return null;
      case 'cloudKitV2Publish':
        final id = args['id'] as String;
        final previous = records[id];
        if (previous != null &&
            (previous['header'] != args['header'] ||
                previous['payload'] != args['payload'])) {
          throw PlatformException(code: 'cloudkit_v2_recordCollision');
        }
        records[id] = {
          'id': id,
          'header': args['header'],
          'payload': args['payload'],
        };
        return null;
      case 'cloudKitV2FetchHeader':
        final record = records[args['id']];
        if (record == null) throw PlatformException(code: '11');
        return record['header'];
      case 'cloudKitV2FetchPayload':
        final record = records[args['id']];
        final payload = record?['payload'];
        if (payload is! String || payload.isEmpty) {
          throw PlatformException(code: 'cloudkit_v2_invalidRecord');
        }
        return payload;
      case 'cloudKitV2FetchHeaders':
        final cursor = int.tryParse(args['cursor'] as String? ?? '0');
        final limit = args['limit'];
        if (cursor == null || limit is! int || limit < 1 || limit > 200) {
          throw PlatformException(code: 'cloudkit_v2_invalidRequest');
        }
        final all = records.values.toList();
        final page = all.skip(cursor).take(limit).toList();
        return {
          'cursor': '${cursor + page.length}',
          'hasMore': cursor + page.length < all.length,
          'headers': [
            for (final record in page)
              {'id': record['id'], 'header': record['header']},
          ],
          'issues': <Object>[],
        };
      default:
        throw PlatformException(code: 'cloudkit_v2_invalidRequest');
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  var stage = 'starting';
  SyncV2WorkspaceController? activeWorkspace;
  _MockCloud? activeCloud;
  void markStage(String value) {
    stage = value;
    web.document.documentElement?.setAttribute('data-fixture-stage', value);
  }

  try {
    final cloud = activeCloud = _MockCloud();
    markStage('loading writer database');
    final writerSqlite = await WasmSqlite3.loadFromUrl(
      Uri.base.resolve('vendor/drift/sqlite3.wasm'),
    );
    writerSqlite.registerVirtualFileSystem(
      InMemoryFileSystem(),
      makeDefault: true,
    );
    final writer = SyncV2CloudKitSandboxSession.create(
      executor: WasmDatabase.inMemory(writerSqlite),
      invoke: cloud.invoke,
      disconnect: () async {},
    );
    activeWorkspace = writer.workspace;
    markStage('initializing writer');
    await writer.workspace.initialize();
    markStage('registering synthetic generation');
    final codes = await writer.workspace.prepareNew(
      'synthetic-fixture-password',
    );
    markStage('confirming synthetic generation');
    await writer.workspace.confirmSetup();
    markStage('saving normal attachment');
    await _savePhoto(
      writer.workspace,
      title: 'Synthetic readonly attachment',
      draftId: 'fixture-normal-photo',
    );
    markStage('creating synthetic private profile');
    await writer.workspace.createProfile(
      'Private synthetic',
      'private-password',
    );
    markStage('saving private attachment');
    await _savePhoto(
      writer.workspace,
      title: 'Private stale attachment',
      draftId: 'fixture-private-photo',
    );
    markStage('syncing synthetic fixture');
    await writer.workspace.syncNow();
    markStage('closing writer');
    await writer.close();

    markStage('loading reader database');
    final readerSqlite = await WasmSqlite3.loadFromUrl(
      Uri.base.resolve('vendor/drift/sqlite3.wasm'),
    );
    readerSqlite.registerVirtualFileSystem(
      InMemoryFileSystem(),
      makeDefault: true,
    );
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    final inbox = SyncV2Inbox(WasmDatabase.inMemory(readerSqlite), headers);
    final controller = SyncV2CloudKitReadOnlyController(
      inbox: inbox,
      repository: SyncV2NoteRepository(
        inbox,
        headers,
        SyncV2PayloadCodec(encryption),
      ),
      encryption: encryption,
      store: SyncV2EphemeralKeyStore(),
      accountReader: () async => _account,
      registrationTransport: (account) =>
          SyncV2CloudKitWebTransport(accountId: account, invoke: cloud.invoke),
      readerFactory: (account) =>
          SyncV2CloudKitWebTransport(accountId: account, invoke: cloud.invoke),
    );
    markStage('recovering readonly profile');
    await controller.recover(codes.syncCode);
    markStage('unlocking synthetic ADMIN');
    await controller.unlockAdmin(codes.adminCode);
    final normalProfileId = controller.notes.first.note.vaultId;
    final privateProfile = controller.profiles.singleWhere(
      (profile) => profile.id != normalProfileId,
    );
    markStage('selecting synthetic private profile');
    await controller.selectProfile(privateProfile.id);
    web.document.documentElement?.setAttribute('data-fixture-ready', 'true');
    runApp(
      MaterialApp(
        locale: const Locale('ja'),
        supportedLocales: AppStrings.supportedLocales,
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Scaffold(
          body: Column(
            children: [
              Expanded(
                child: SyncV2CloudKitReadOnlyScreen(initialSession: controller),
              ),
              TextButton(
                key: const Key('reverify-synthetic-admin'),
                onPressed: () => controller.unlockAdmin(codes.adminCode),
                child: const Text('Reverify synthetic ADMIN'),
              ),
            ],
          ),
        ),
      ),
    );
  } catch (error, stack) {
    web.document.documentElement?.setAttribute(
      'data-fixture-error',
      '$stage: $error; diagnostic=${activeWorkspace?.diagnosticCode}; '
          'calls=${activeCloud?.calls.join(',')}',
    );
    debugPrint(
      'Readonly attachment fixture failed at $stage: $error; '
      'diagnostic=${activeWorkspace?.diagnosticCode}; '
      'calls=${activeCloud?.calls.join(',')}\n$stack',
    );
    runApp(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: SelectableText(
              '$stage: $error; diagnostic=${activeWorkspace?.diagnosticCode}; '
              'calls=${activeCloud?.calls.join(',')}\n$stack',
            ),
          ),
        ),
      ),
    );
  }
}
