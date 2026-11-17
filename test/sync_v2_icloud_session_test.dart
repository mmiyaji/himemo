import 'dart:async';

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_session.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_publisher.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';

class _WebLikeTransport implements SyncV2ReadTransport, SyncV2WriteTransport {
  int published = 0;

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async =>
      const SyncV2RemotePage(nextCursor: 'cursor', hasMore: false, headers: []);

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    published++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('session uses the injected account and transport', () async {
    final key = SecretKey(List<int>.filled(32, 9));
    final enrollments = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
    await enrollments.saveVerified((
      accountId: 'web-account',
      generationId: 'generation',
      syncKey: key,
    ));
    final inbox = SyncV2Inbox(
      NativeDatabase.memory(),
      SyncV2HeaderCodec(EncryptionService()),
    );
    addTearDown(inbox.close);
    await inbox.queuePublication(
      generationId: 'generation',
      syncKey: key,
      encryptedPayload: null,
      change: SyncV2Change(
        id: 'web-change',
        profileId: 'profile',
        noteId: 'note',
        parentIds: const {},
        operation: SyncV2Operation.delete,
      ),
    );
    final transport = _WebLikeTransport();
    final result = await SyncV2ICloudSession(
      enrollments,
      inbox,
      accountReader: () async => 'web-account',
      transportFactory: (account) {
        expect(account, 'web-account');
        return (reader: transport, writer: transport);
      },
    ).syncOnce();
    expect(result.errors, isEmpty);
    expect(result.publishedChanges, 1);
    expect(transport.published, 1);
  });

  test('publishes queued changes even when header reception fails', () async {
    const channel = MethodChannel('org.ruhenheim.himemo/cloudkit');
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <String>[];
    final releaseReceive = Completer<void>();
    final published = Completer<void>();
    addTearDown(() {
      if (!releaseReceive.isCompleted) releaseReceive.complete();
    });
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.method);
      switch (call.method) {
        case 'cloudKitV2AccountId':
          return 'account';
        case 'cloudKitV2FetchHeaders':
          await releaseReceive.future;
          throw PlatformException(code: 'network_error');
        case 'cloudKitV2Publish':
          published.complete();
          return null;
        default:
          throw StateError(call.method);
      }
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    final key = SecretKey(List<int>.filled(32, 3));
    final enrollments = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
    await enrollments.saveVerified((
      accountId: 'account',
      generationId: 'generation',
      syncKey: key,
    ));
    final inbox = SyncV2Inbox(
      NativeDatabase.memory(),
      SyncV2HeaderCodec(EncryptionService()),
    );
    addTearDown(inbox.close);
    await inbox.queuePublication(
      generationId: 'generation',
      syncKey: key,
      encryptedPayload: null,
      change: SyncV2Change(
        id: 'local-delete',
        profileId: 'profile',
        noteId: 'note',
        parentIds: const {},
        operation: SyncV2Operation.delete,
      ),
    );
    final operation = SyncV2ICloudSession(enrollments, inbox).syncOnce();
    await published.future.timeout(const Duration(seconds: 2));
    releaseReceive.complete();
    final result = await operation;
    expect(result.publishedChanges, 1);
    expect(result.headersStaged, isFalse);
    expect(result.errors, ['header_receive_failed']);
    expect(calls, contains('cloudKitV2Publish'));
    expect(
      await inbox.readOutbox(generationId: 'generation', limit: 10),
      isEmpty,
    );
  });
}
