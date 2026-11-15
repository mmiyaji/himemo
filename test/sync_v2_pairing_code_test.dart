import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_pairing_code.dart';

String _syncCode({
  Object? account = 'account@example.test',
  Object? generation = 'generation_1',
  Object? version = 1,
  Object? key,
  Map<String, Object?>? extra,
}) => base64UrlEncode(
  utf8.encode(
    jsonEncode({
      'format': 'himemo.sync.v2.recovery',
      'version': version,
      'account': account,
      'generation': generation,
      'key': key ?? base64UrlEncode(List<int>.filled(32, 17)),
      ...?extra,
    }),
  ),
);

String _adminCode({
  Object? generation = 'generation_1',
  Object? key,
  Map<String, Object?>? extra,
}) =>
    'himemo-admin-v2:${base64UrlEncode(utf8.encode(jsonEncode({'generation': generation, 'key': key ?? base64Encode(List<int>.filled(32, 23)), ...?extra})))}';

void main() {
  test(
    'round-trips both pairing roles and tolerates scanner edge whitespace',
    () {
      final sync = _syncCode();
      final admin = _adminCode();
      final syncQr = SyncV2PairingCode.encodeQr(sync, administrator: false);
      final adminQr = SyncV2PairingCode.encodeQr(admin, administrator: true);

      expect(syncQr, startsWith(SyncV2PairingCode.syncPrefix));
      expect(adminQr, startsWith(SyncV2PairingCode.administratorPrefix));
      expect(
        SyncV2PairingCode.decodeQr(' \n$syncQr\t ', administrator: false),
        sync,
      );
      expect(SyncV2PairingCode.decodeQr(adminQr, administrator: true), admin);
    },
  );

  test('QR envelopes cannot cross roles and raw backups are not QR codes', () {
    final syncQr = SyncV2PairingCode.encodeQr(
      _syncCode(),
      administrator: false,
    );
    final adminQr = SyncV2PairingCode.encodeQr(
      _adminCode(),
      administrator: true,
    );
    expect(
      () => SyncV2PairingCode.decodeQr(syncQr, administrator: true),
      throwsFormatException,
    );
    expect(
      () => SyncV2PairingCode.decodeQr(adminQr, administrator: false),
      throwsFormatException,
    );
    expect(
      () => SyncV2PairingCode.decodeQr(_syncCode(), administrator: false),
      throwsFormatException,
    );
    expect(
      () => SyncV2PairingCode.decodeQr(
        'https://example.test',
        administrator: false,
      ),
      throwsFormatException,
    );
    expect(
      () => SyncV2PairingCode.decodeQr(
        '${SyncV2PairingCode.administratorPrefix}${'sensitive-content' * 300}',
        administrator: true,
      ),
      throwsA(
        isA<FormatException>().having(
          (error) => error.message,
          'message',
          isNot(contains('sensitive-content')),
        ),
      ),
    );
  });

  test('rejects malformed sync recovery schemas and keys', () {
    final invalid = [
      _syncCode(version: '1'),
      _syncCode(version: 1.0),
      _syncCode(extra: {'extra': true}),
      _syncCode(account: ''),
      _syncCode(account: 23),
      _syncCode(account: 'a' * 1025),
      _syncCode(generation: 'contains.dot'),
      _syncCode(generation: ''),
      _syncCode(key: base64UrlEncode(List<int>.filled(31, 0))),
      _syncCode(key: 23),
      _syncCode(key: 'not-base64'),
      'not-base64',
    ];
    for (final code in invalid) {
      expect(
        () => SyncV2PairingCode.encodeQr(code, administrator: false),
        throwsFormatException,
        reason: code.length < 100 ? code : 'invalid sync recovery schema',
      );
    }
    expect(
      () => SyncV2PairingCode.decodeQr(
        '${SyncV2PairingCode.syncPrefix}${'a' * 4097}',
        administrator: false,
      ),
      throwsFormatException,
    );
  });

  test('rejects malformed administrator recovery schemas and keys', () {
    final invalid = [
      _adminCode(extra: {'extra': true}),
      _adminCode(generation: 'not safe/generation'),
      _adminCode(generation: 23),
      _adminCode(generation: 'a' * 81),
      _adminCode(key: 'non-string'),
      _adminCode(key: base64Encode(List<int>.filled(31, 0))),
      _adminCode(key: 'not-base64'),
      'himemo-admin-v2:not-base64',
    ];
    for (final code in invalid) {
      expect(
        () => SyncV2PairingCode.encodeQr(code, administrator: true),
        throwsFormatException,
        reason: code.length < 100 ? code : 'invalid admin recovery schema',
      );
    }
    expect(
      () => SyncV2PairingCode.decodeQr(
        '${SyncV2PairingCode.administratorPrefix}${_adminCode() * 50}',
        administrator: true,
      ),
      throwsFormatException,
    );
  });
}
