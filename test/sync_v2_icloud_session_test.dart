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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
