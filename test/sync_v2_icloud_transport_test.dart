import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_icloud_transport.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('org.ruhenheim.himemo/cloudkit');
  const accountId = 'iCloud-account-1';
  const generationId = 'generation-1';

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test(
    'preserves record deletion and fetch errors alongside valid headers',
    () async {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'cloudKitV2FetchHeader') {
              return 'recovered-header';
            }
            return {
              'cursor': 'next',
              'hasMore': false,
              'headers': [
                {'id': 'valid', 'header': 'encrypted-header'},
              ],
              'issues': [
                {'id': 'deleted', 'reason': 'remote_deleted'},
                {'id': 'retry', 'reason': 'record_unavailable'},
              ],
            };
          });
      final transport = SyncV2ICloudTransport(accountId: accountId);
      final page = await transport.fetchHeaders(
        generationId: generationId,
        cursor: null,
        limit: 3,
      );
      expect(page.headers.single.id, 'valid');
      expect(page.issues, [
        (id: 'deleted', reason: 'remote_deleted'),
        (id: 'retry', reason: 'record_unavailable'),
      ]);
      expect(
        await transport.fetchHeader(
          generationId: generationId,
          recordId: 'retry',
        ),
        (id: 'retry', encryptedHeader: 'recovered-header'),
      );
    },
  );

  test(
    'scopes header and typed payload requests to the enrolled account',
    () async {
      final calls = <MethodCall>[];
      final payload = Uint8List.fromList([0, 1, 2, 255]);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            calls.add(call);
            switch (call.method) {
              case 'cloudKitV2AccountId':
                return accountId;
              case 'cloudKitV2FetchHeaders':
                expect(call.arguments, {
                  'accountId': accountId,
                  'generationId': generationId,
                  'cursor': 'cursor-before',
                  'limit': 17,
                });
                return {
                  'cursor': 'cursor-after',
                  'hasMore': true,
                  'headers': [
                    {'id': 'record-1', 'header': 'encrypted-header'},
                  ],
                };
              case 'cloudKitV2FetchPayload':
                expect(call.arguments, {
                  'accountId': accountId,
                  'generationId': generationId,
                  'id': 'record-1',
                });
                return payload;
              default:
                throw StateError('Unexpected method ${call.method}');
            }
          });

      final transport = SyncV2ICloudTransport(accountId: accountId);
      expect(await transport.readCurrentAccountId(), accountId);
      final page = await transport.fetchHeaders(
        generationId: generationId,
        cursor: 'cursor-before',
        limit: 17,
      );
      expect(page.nextCursor, 'cursor-after');
      expect(page.hasMore, isTrue);
      expect(page.headers, [
        (id: 'record-1', encryptedHeader: 'encrypted-header'),
      ]);

      final receivedPayload = await transport.fetchPayload(
        generationId: generationId,
        recordId: 'record-1',
      );
      expect(receivedPayload, isA<Uint8List>());
      expect(receivedPayload, payload);
      expect(calls.map((call) => call.method), [
        'cloudKitV2AccountId',
        'cloudKitV2FetchHeaders',
        'cloudKitV2FetchPayload',
      ]);
    },
  );

  test('maps iCloud expired cursor errors to SyncV2CursorExpired', () async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          expect(call.method, 'cloudKitV2FetchHeaders');
          expect(call.arguments, {
            'accountId': accountId,
            'generationId': generationId,
            'cursor': 'expired-cursor',
            'limit': 4,
          });
          throw PlatformException(code: 'cloudkit_v2_cursor_expired');
        });

    final transport = SyncV2ICloudTransport(accountId: accountId);
    await expectLater(
      transport.fetchHeaders(
        generationId: generationId,
        cursor: 'expired-cursor',
        limit: 4,
      ),
      throwsA(isA<SyncV2CursorExpired>()),
    );
  });
}
