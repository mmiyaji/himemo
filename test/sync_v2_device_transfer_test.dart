import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_device_transfer.dart';

String syncCode() => base64Url.encode(
  utf8.encode(
    jsonEncode({
      'format': 'himemo.sync.v2.recovery',
      'version': 1,
      'account': 'account',
      'generation': 'generation_1',
      'key': base64Url.encode(List.filled(32, 1)),
    }),
  ),
);
String adminCode({String generation = 'generation_1'}) =>
    'himemo-admin-v2:${base64Url.encode(utf8.encode(jsonEncode({'generation': generation, 'key': base64Encode(List.filled(32, 2))})))}';

void main() {
  test('one QR and recovery file carry SYNC and ADMIN bound to the same generation', () {
    final transfer = SyncV2DeviceTransfer(
      syncCode: syncCode(),
      adminCode: adminCode(),
    );
    for (final decoded in [
      SyncV2DeviceTransfer.fromQr('  ${transfer.toQr()}\n'),
      SyncV2DeviceTransfer.fromRecoveryFile(transfer.toRecoveryFile()),
    ]) {
      expect(decoded.syncCode, transfer.syncCode);
      expect(decoded.adminCode, transfer.adminCode);
      expect(decoded.includesAdministrator, isTrue);
    }
  });
  test(
    'SYNC-only is explicit and a mismatched ADMIN generation is rejected',
    () {
      final transfer = SyncV2DeviceTransfer(syncCode: syncCode());
      expect(SyncV2DeviceTransfer.fromQr(transfer.toQr()).adminCode, isNull);
      expect(
        () => SyncV2DeviceTransfer(
          syncCode: syncCode(),
          adminCode: adminCode(generation: 'other'),
        ),
        throwsFormatException,
      );
    },
  );
  test('malformed or oversized transfers reject without echoing keys', () {
    final file = jsonDecode(
      SyncV2DeviceTransfer(
        syncCode: syncCode(),
        adminCode: adminCode(),
      ).toRecoveryFile(),
    ) as Map<String, dynamic>;
    for (final malformed in [
      {...file, 'version': 2},
      {...file, 'version': true},
      {...file, 'extra': 'secret'},
      {...file}..remove('admin'),
      {...file, 'admin': ''},
      {...file, 'sync': 'secret'},
    ]) {
      expect(
        () => SyncV2DeviceTransfer.fromRecoveryFile(jsonEncode(malformed)),
        throwsFormatException,
      );
    }
    expect(
      () => SyncV2DeviceTransfer.fromRecoveryFile('secret' * 3000),
      throwsA(
        isA<FormatException>().having(
          (e) => e.message,
          'message',
          isNot(contains('secret')),
        ),
      ),
    );
    expect(
      () => SyncV2DeviceTransfer.fromQr(syncCode()),
      throwsFormatException,
    );
    expect(
      () => SyncV2DeviceTransfer.fromQr('${SyncV2DeviceTransfer.qrPrefix}!!!!'),
      throwsFormatException,
    );
  });
}
