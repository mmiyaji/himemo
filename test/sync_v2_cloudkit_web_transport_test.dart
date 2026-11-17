import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/data/sync_v2_receiver.dart';

void main() {
  test(
    'registration is bound to the enrolled account and metadata zone',
    () async {
      final calls = <(String, Map<String, Object?>)>[];
      final transport = SyncV2CloudKitWebTransport(
        accountId: 'account-a',
        invoke: (method, args) async {
          calls.add((method, args));
          if (method == 'cloudKitV2AccountId') return 'account-a';
          if (method == 'cloudKitV2FetchHeader') {
            throw PlatformException(code: '11');
          }
          return null;
        },
      );
      expect(await transport.readCurrentAccountId(), 'account-a');
      expect(await transport.readRegistration(), isNull);
      await transport.prepareGeneration('generation-a');
      expect(calls[1].$2['generationId'], 'metadata-v1');
      expect(calls[2].$2, {
        'accountId': 'account-a',
        'generationId': 'generation-a',
      });
      expect(calls[3].$2['generationId'], 'metadata-v1');
      await transport.publishRegistration('encrypted-proof');
      expect(calls.last.$2, {
        'accountId': 'account-a',
        'generationId': 'metadata-v1',
        'id': 'active-generation-v1',
        'header': 'encrypted-proof',
      });
    },
  );

  test(
    'pages preserve deletes, reject excess, and map expired cursors',
    () async {
      var excess = false;
      var expired = false;
      final transport = SyncV2CloudKitWebTransport(
        accountId: 'account-a',
        invoke: (method, args) async {
          if (expired) {
            throw PlatformException(code: 'cloudkit_v2_cursor_expired');
          }
          return {
            'cursor': 'next',
            'hasMore': false,
            'headers': [
              {'id': 'one', 'header': 'cipher'},
            ],
            'issues': excess
                ? [
                    {'id': 'two', 'reason': 'remote_deleted'},
                  ]
                : <Object>[],
          };
        },
      );
      final page = await transport.fetchHeaders(
        generationId: 'generation',
        cursor: null,
        limit: 1,
      );
      expect(page.nextCursor, 'next');
      expect(page.headers.single, (id: 'one', encryptedHeader: 'cipher'));
      excess = true;
      await expectLater(
        transport.fetchHeaders(
          generationId: 'generation',
          cursor: null,
          limit: 1,
        ),
        throwsFormatException,
      );
      expired = true;
      await expectLater(
        transport.fetchHeaders(
          generationId: 'generation',
          cursor: 'old',
          limit: 1,
        ),
        throwsA(isA<SyncV2CursorExpired>()),
      );
    },
  );

  test(
    'publishes and retrieves ciphertext bytes without plaintext conversion',
    () async {
      Map<String, Object?>? sent;
      final transport = SyncV2CloudKitWebTransport(
        accountId: 'account-a',
        invoke: (method, args) async {
          sent = args;
          if (method == 'cloudKitV2FetchPayload') {
            return base64Encode([0, 1, 255]);
          }
          return null;
        },
      );
      await transport.publish(
        generationId: 'generation',
        publication: (
          id: 'record',
          encryptedHeader: 'encrypted-header',
          encryptedPayload: Uint8List.fromList([0, 1, 255]),
        ),
      );
      expect(sent!['payload'], 'AAH/');
      expect(
        await transport.fetchPayload(
          generationId: 'generation',
          recordId: 'record',
        ),
        [0, 1, 255],
      );
    },
  );
}
