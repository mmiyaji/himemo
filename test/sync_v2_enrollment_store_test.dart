import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';

void main() {
  test('cached proof binds final key and cleanup rejects mismatches and retains other accounts', () async {
    final backing = MemorySecureKeyValueStore();
    final store = SyncV2EnrollmentStore(backing);
    final key = SecretKey(List.filled(32, 1));
    final wrong = SecretKey(List.filled(32, 2));
    addTearDown(key.destroy);
    addTearDown(wrong.destroy);
    final verified = (
      accountId: 'account',
      generationId: 'winner',
      syncKey: key,
    );
    await store.saveVerified(verified);
    await store.cacheVerifiedProof(verified, 'encrypted-proof');
    expect(await store.readCachedProof('account'), 'encrypted-proof');
    final mismatch = (
      accountId: 'account',
      generationId: 'winner',
      syncKey: wrong,
    );
    await expectLater(
      store.cacheVerifiedProof(mismatch, 'other'),
      throwsStateError,
    );
    await store.savePendingRegistration((
      accountId: 'account',
      generationId: 'loser',
      syncKey: wrong,
      encryptedProof: 'loser-proof',
    ));
    await expectLater(
      store.cleanupPendingAfterVerifiedRecovery(mismatch),
      throwsStateError,
    );
    final retained = await store.readPendingRegistration();
    expect(retained, isNotNull);
    retained!.syncKey.destroy();
    await store.cleanupPendingAfterVerifiedRecovery(verified);
    expect(await store.readPendingRegistration(), isNull);
    await store.savePendingRegistration((
      accountId: 'other-account',
      generationId: 'loser',
      syncKey: wrong,
      encryptedProof: 'other-proof',
    ));
    await store.cleanupPendingAfterVerifiedRecovery(verified);
    final other = await store.readPendingRegistration();
    expect(other!.accountId, 'other-account');
    other.syncKey.destroy();
  });
  test('pending registration is immutable and clears only after matching final save', () async {
    final backing = MemorySecureKeyValueStore();
    final store = SyncV2EnrollmentStore(backing);
    final key = SecretKey(List.filled(32, 5));
    addTearDown(key.destroy);
    final pending = (
      accountId: 'account',
      generationId: 'generation',
      syncKey: key,
      encryptedProof: 'original-proof',
    );
    await store.savePendingRegistration(pending);
    await store.savePendingRegistration(pending);
    await expectLater(
      store.savePendingRegistration((
        accountId: 'account',
        generationId: 'generation',
        syncKey: key,
        encryptedProof: 'different-proof',
      )),
      throwsStateError,
    );
    await expectLater(
      store.clearPendingRegistration(pending),
      throwsStateError,
    );
    final reopened = await SyncV2EnrollmentStore(backing)
        .readPendingRegistration();
    expect(reopened!.encryptedProof, 'original-proof');
    expect(await reopened.syncKey.extractBytes(), await key.extractBytes());
    reopened.syncKey.destroy();
    await store.saveVerified((
      accountId: 'account',
      generationId: 'generation',
      syncKey: key,
    ));
    await expectLater(
      store.clearPendingRegistration((
        accountId: 'account',
        generationId: 'generation',
        syncKey: key,
        encryptedProof: 'different-proof',
      )),
      throwsStateError,
    );
    await store.clearPendingRegistration(pending);
    expect(await store.readPendingRegistration(), isNull);
    final finalEnrollment = await store.readForAccount('account');
    expect(finalEnrollment!.generationId, 'generation');
    finalEnrollment.syncKey.destroy();
  });
  test(
    'detects a store that acknowledges but drops enrollment writes',
    () async {
      final store = SyncV2EnrollmentStore(_DroppingStore());
      await expectLater(
        store.saveVerified((
          accountId: 'account',
          generationId: 'generation',
          syncKey: SecretKey(List.filled(32, 1)),
        )),
        throwsStateError,
      );
    },
  );
  test(
    'saves idempotently and reads the enrollment for the same account',
    () async {
      final backing = MemorySecureKeyValueStore();
      final store = SyncV2EnrollmentStore(backing);
      final key = SecretKey(List<int>.generate(32, (index) => index + 1));
      final enrollment = (
        accountId: 'account-1',
        generationId: 'generation_1',
        syncKey: key,
      );

      await store.saveVerified(enrollment);
      await store.saveVerified(enrollment);

      final restored = await SyncV2EnrollmentStore(backing)
          .readForAccount('account-1');
      expect(restored, isNotNull);
      expect(restored!.accountId, 'account-1');
      expect(restored.generationId, 'generation_1');
      expect(await restored.syncKey.extractBytes(), await key.extractBytes());
      restored.syncKey.destroy();
      key.destroy();
    },
  );

  test('refuses to return enrollment for a different iCloud account', () async {
    final store = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
    await store.saveVerified((
      accountId: 'account-1',
      generationId: 'generation-1',
      syncKey: SecretKey(List<int>.filled(32, 3)),
    ));

    await expectLater(store.readForAccount('account-2'), throwsStateError);
  });

  test(
    'concurrent conflicting enrollments cannot replace each other',
    () async {
      final store = SyncV2EnrollmentStore(MemorySecureKeyValueStore());
      final attempts = await Future.wait(
        [
          (
            accountId: 'account-1',
            generationId: 'generation-a',
            syncKey: SecretKey(List<int>.filled(32, 4)),
          ),
          (
            accountId: 'account-1',
            generationId: 'generation-b',
            syncKey: SecretKey(List<int>.filled(32, 5)),
          ),
        ].map((enrollment) async {
          try {
            await store.saveVerified(enrollment);
            return true;
          } on StateError {
            return false;
          }
        }),
      );

      expect(attempts.where((saved) => saved), hasLength(1));
      expect(attempts.where((saved) => !saved), hasLength(1));
      final restored = await store.readForAccount('account-1');
      expect({
        'generation-a',
        'generation-b',
      }, contains(restored!.generationId));
      restored.syncKey.destroy();
    },
  );

  test('rejects invalid sync keys and generation IDs', () async {
    final store = SyncV2EnrollmentStore(MemorySecureKeyValueStore());

    await expectLater(
      store.saveVerified((
        accountId: 'account-1',
        generationId: 'generation-1',
        syncKey: SecretKey(List<int>.filled(16, 1)),
      )),
      throwsFormatException,
    );
    await expectLater(
      store.saveVerified((
        accountId: 'account-1',
        generationId: 'generation with spaces',
        syncKey: SecretKey(List<int>.filled(32, 1)),
      )),
      throwsFormatException,
    );
    await expectLater(
      store.saveVerified((
        accountId: '',
        generationId: 'generation-1',
        syncKey: SecretKey(List<int>.filled(32, 1)),
      )),
      throwsFormatException,
    );
  });
}

class _DroppingStore extends MemorySecureKeyValueStore {
  @override
  Future<void> write(String key, String value) async {}
}
