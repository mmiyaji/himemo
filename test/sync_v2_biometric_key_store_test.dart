import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/sync_v2_biometric_key_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.ruhenheim.himemo/sync_v2_biometrics');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late MethodChannelSyncV2BiometricKeyStore store;

  setUp(() {
    store = MethodChannelSyncV2BiometricKeyStore(channel: channel);
  });

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test(
    'reports availability and defaults a missing response to false',
    () async {
      messenger.setMockMethodCallHandler(channel, (_) async => true);
      expect(await store.isAvailable(), isTrue);
      messenger.setMockMethodCallHandler(channel, (_) async => null);
      expect(await store.isAvailable(), isFalse);
    },
  );

  test('writes exactly 32 bytes as base64 scoped by generation', () async {
    final calls = <MethodCall>[];
    messenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      return null;
    });
    final bytes = List<int>.generate(32, (index) => index);
    await store.save('generation-a', SecretKey(bytes));

    expect(calls, hasLength(1));
    expect(calls.single.method, 'write');
    final arguments = calls.single.arguments as Map<Object?, Object?>;
    expect(arguments.keys, containsAll(['generationId', 'keyBase64']));
    expect(arguments.keys, hasLength(2));
    expect(arguments['generationId'], 'generation-a');
    expect(base64Decode(arguments['keyBase64']! as String), bytes);
  });

  test(
    'rejects non-32-byte keys before sending them over the channel',
    () async {
      var called = false;
      messenger.setMockMethodCallHandler(channel, (_) async {
        called = true;
        return null;
      });

      await expectLater(
        store.save('generation-a', SecretKey(List<int>.filled(31, 7))),
        throwsArgumentError,
      );
      expect(called, isFalse);
    },
  );

  test('reads a valid key and returns null only for an absent key', () async {
    final bytes = List<int>.generate(32, (index) => 255 - index);
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'read');
      expect(call.arguments, {'generationId': 'generation-b'});
      return base64Encode(bytes);
    });
    expect(await (await store.read('generation-b'))!.extractBytes(), bytes);

    messenger.setMockMethodCallHandler(channel, (_) async => null);
    expect(await store.read('generation-b'), isNull);
  });

  test('rejects malformed or wrong-sized native key responses', () async {
    messenger.setMockMethodCallHandler(channel, (_) async => 'not base64');
    await expectLater(
      store.read('generation-a'),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'failed')),
    );

    messenger.setMockMethodCallHandler(
      channel,
      (_) async => base64Encode(List<int>.filled(31, 4)),
    );
    await expectLater(
      store.read('generation-a'),
      throwsA(isA<PlatformException>().having((e) => e.code, 'code', 'failed')),
    );
  });

  test(
    'passes cancellation and invalidation error codes through unchanged',
    () async {
      for (final code in [
        'cancelled',
        'unavailable',
        'invalidated',
        'failed',
      ]) {
        messenger.setMockMethodCallHandler(channel, (_) async {
          throw PlatformException(code: code);
        });
        await expectLater(
          store.read('generation-a'),
          throwsA(isA<PlatformException>().having((e) => e.code, 'code', code)),
        );
      }
    },
  );

  test('deletes only the requested generation', () async {
    MethodCall? recorded;
    messenger.setMockMethodCallHandler(channel, (call) async {
      recorded = call;
      return null;
    });
    await store.delete('generation-c');
    expect(recorded?.method, 'delete');
    expect(recorded?.arguments, {'generationId': 'generation-c'});
  });
}
