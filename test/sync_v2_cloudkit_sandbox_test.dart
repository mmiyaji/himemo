import 'dart:async';
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/testing/sync_v2_cloudkit_sandbox.dart';

class _Bridge extends SyncV2CloudKitWebBridge {
  int calls = 0;
  String? environment;
  String? namespace;
  bool? enableWrites;
  @override
  Future<bool> configure({
    required String containerIdentifier,
    required String apiToken,
    String environment = 'production',
    bool enableWrites = false,
    String? sandboxNamespace,
  }) async {
    calls++;
    this.environment = environment;
    namespace = sandboxNamespace;
    this.enableWrites = enableWrites;
    expect(containerIdentifier, 'iCloud.org.ruhenheim.himemo');
    return true;
  }
}

class _MockCloud {
  final zones = <String, Map<String, Map<String, Object?>>>{};
  final writtenZones = <String>[];

  Future<Object?> call(
    String namespace,
    String method,
    Map<String, Object?> args,
  ) async {
    if (method == 'cloudKitV2AccountId') return 'sandbox-account';
    final zone = 'HiMemoSyncV2WebTest-$namespace-${args['generationId']}';
    final records = zones.putIfAbsent(zone, () => {});
    switch (method) {
      case 'cloudKitV2Prepare':
        writtenZones.add(zone);
        return null;
      case 'cloudKitV2Publish':
        writtenZones.add(zone);
        final id = args['id']! as String;
        final existing = records[id];
        if (existing != null && existing['header'] != args['header']) {
          throw PlatformException(code: 'cloudkit_v2_recordCollision');
        }
        records[id] = Map<String, Object?>.of(args);
        return null;
      case 'cloudKitV2FetchHeader':
        final record = records[args['id']];
        if (record == null) throw PlatformException(code: '11');
        return record['header'];
      case 'cloudKitV2FetchPayload':
        final record = records[args['id']];
        if (record == null) throw PlatformException(code: '11');
        return record['payload'];
      case 'cloudKitV2FetchHeaders':
        final start = int.parse(args['cursor'] as String? ?? '0');
        final limit = args['limit']! as int;
        final page = records.values.skip(start).take(limit).toList();
        return {
          'cursor': '${start + page.length}',
          'hasMore': start + page.length < records.length,
          'headers': [
            for (final row in page) {'id': row['id'], 'header': row['header']},
          ],
          'issues': <Object>[],
        };
      default:
        throw StateError('Unexpected mock request');
    }
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'sandbox notes sync and recover only inside the selected namespace',
    () async {
      final cloud = _MockCloud();
      const namespace = 'sandbox_test_1234';
      SyncV2CloudKitSandboxSession session(String scope) =>
          SyncV2CloudKitSandboxSession.create(
            executor: NativeDatabase.memory(),
            invoke: (method, args) => cloud.call(scope, method, args),
            disconnect: () async {},
          );
      final first = session(namespace);
      final second = session(namespace);
      final isolated = session('different_test_12');
      addTearDown(() async {
        await first.close();
        await second.close();
        await isolated.close();
      });
      await first.workspace.initialize();
      final codes = await first.workspace.prepareNew('sample-password');
      await first.workspace.confirmSetup();
      const title = 'Sandbox synthetic note 1981';
      const body = 'Synthetic private body 3517';
      await first.workspace.saveNote(title: title, body: body);
      await first.workspace.syncNow();
      expect(cloud.writtenZones, isNotEmpty);
      expect(
        cloud.writtenZones.every(
          (zone) => zone.startsWith('HiMemoSyncV2WebTest-$namespace-'),
        ),
        isTrue,
      );
      final remote = jsonEncode(cloud.zones);
      expect(remote, isNot(contains(title)));
      expect(remote, isNot(contains(body)));

      await second.workspace.initialize();
      await second.workspace.recover(codes.syncCode);
      expect(second.workspace.notes.single.note.title, title);
      expect(second.workspace.notes.single.note.body, body);

      await isolated.workspace.initialize();
      await expectLater(
        isolated.workspace.recover(codes.syncCode),
        throwsA(anything),
      );
      expect(isolated.workspace.registered, isFalse);
      expect(
        cloud.writtenZones.every(
          (zone) => zone.startsWith('HiMemoSyncV2WebTest-'),
        ),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'sandbox configuration fails closed and never selects production',
    () async {
      final bridge = _Bridge();
      for (final namespace in ['', 'short', 'invalid/path/12345', 'a' * 33]) {
        expect(
          () => configureCloudKitSandbox(
            bridge: bridge,
            apiToken: 'token',
            namespace: namespace,
          ),
          throwsArgumentError,
        );
      }
      expect(
        () => configureCloudKitSandbox(
          bridge: bridge,
          apiToken: '',
          namespace: 'sandbox_12345678',
        ),
        throwsArgumentError,
      );
      expect(bridge.calls, 0);
      expect(
        await configureCloudKitSandbox(
          bridge: bridge,
          apiToken: 'token',
          namespace: 'sandbox_12345678',
        ),
        isTrue,
      );
      expect(bridge.environment, 'development');
      expect(bridge.enableWrites, isTrue);
      expect(bridge.namespace, 'sandbox_12345678');
    },
  );

  test(
    'gate rejects new requests and discards late responses on disconnect',
    () async {
      final reply = Completer<Object?>();
      final disconnected = Completer<void>();
      var calls = 0;
      var closes = 0;
      final gate = SandboxTransportGate(
        (method, arguments) {
          calls++;
          return reply.future;
        },
        () {
          closes++;
          return disconnected.future;
        },
      );
      final pending = gate.invoke('cloudKitV2Publish', {});
      final pendingCheck = expectLater(pending, throwsStateError);
      final closing = gate.close();
      await expectLater(gate.invoke('cloudKitV2Publish', {}), throwsStateError);
      expect(calls, 1);
      expect(closes, 1);
      reply.complete(null);
      await pendingCheck;
      disconnected.complete();
      await closing;
      await gate.close();
      expect(closes, 1);
    },
  );

  test('gate discards a late remote error after disconnect', () async {
    final reply = Completer<Object?>();
    final gate = SandboxTransportGate((_, _) => reply.future, () async {});
    final pending = gate.invoke('cloudKitV2Publish', {});
    final check = expectLater(
      pending,
      throwsA(
        isA<StateError>().having(
          (error) => error.message,
          'message',
          'Sandbox session is closed',
        ),
      ),
    );
    await gate.close();
    reply.completeError(PlatformException(code: 'late_remote_error'));
    await check;
  });

  test(
    'closing a session revokes keys and rejects a delayed operation',
    () async {
      final waiting = Completer<void>();
      final reply = Completer<Object?>();
      var accountCalls = 0;
      var totalCalls = 0;
      var closes = 0;
      final session = SyncV2CloudKitSandboxSession.create(
        executor: NativeDatabase.memory(),
        invoke: (method, args) async {
          totalCalls++;
          if (method != 'cloudKitV2AccountId') {
            throw StateError('Unexpected remote call');
          }
          accountCalls++;
          if (accountCalls == 2) {
            waiting.complete();
            return reply.future;
          }
          return 'sandbox-account';
        },
        disconnect: () async {
          closes++;
        },
      );
      await session.workspace.initialize();
      final pending = session.workspace.prepareNew('preview-password');
      final pendingCheck = expectLater(pending, throwsA(anything));
      await waiting.future;
      final closing = session.close();
      expect(session.workspace.registered, isFalse);
      expect(session.workspace.notes, isEmpty);
      expect(await session.workspace.store.read('sample'), isNull);
      await expectLater(
        session.workspace.store.write('sample', 'secret'),
        throwsStateError,
      );
      reply.complete('sandbox-account');
      await pendingCheck;
      await closing;
      await session.close();
      expect(accountCalls, 2);
      expect(totalCalls, 2);
      expect(closes, 1);
    },
  );
}
