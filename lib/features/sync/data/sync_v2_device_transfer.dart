import 'dart:convert';

import 'sync_v2_pairing_code.dart';

/// One device-transfer envelope. Keys are still verified against the signed-in
/// account's registration before enrollment; this codec only validates shape.
class SyncV2DeviceTransfer {
  SyncV2DeviceTransfer._(this.syncCode, this.adminCode, this.generationId);

  factory SyncV2DeviceTransfer({required String syncCode, String? adminCode}) {
    try {
      SyncV2PairingCode.encodeQr(syncCode, administrator: false);
      final sync = jsonDecode(utf8.decode(base64Url.decode(syncCode))) as Map;
      final generation = sync['generation'] as String;
      if (adminCode != null) {
        SyncV2PairingCode.encodeQr(adminCode, administrator: true);
        final admin = jsonDecode(
          utf8.decode(
            base64Url.decode(adminCode.substring('himemo-admin-v2:'.length)),
          ),
        ) as Map;
        if (admin['generation'] != generation) throw const FormatException();
      }
      return SyncV2DeviceTransfer._(syncCode, adminCode, generation);
    } catch (_) {
      throw const FormatException('Invalid v2 device transfer');
    }
  }

  static const qrPrefix = 'himemo-v2-qr:device:';
  static const _format = 'himemo.sync.v2.device-transfer';
  static const maxFileBytes = 12288;
  final String syncCode;
  final String? adminCode;
  final String generationId;
  bool get includesAdministrator => adminCode != null;

  String toRecoveryFile() => jsonEncode({
    'format': _format,
    'version': 1,
    'sync': syncCode,
    'admin': adminCode,
  });
  String toQr() =>
      '$qrPrefix${base64Url.encode(utf8.encode(toRecoveryFile()))}';

  factory SyncV2DeviceTransfer.fromRecoveryFile(String value) {
    try {
      if (utf8.encode(value).length > maxFileBytes) {
        throw const FormatException();
      }
      final json = jsonDecode(value);
      if (json is! Map<String, dynamic> ||
          json.length != 4 ||
          json['format'] != _format ||
          json['version'] is! int ||
          json['version'] != 1 ||
          json['sync'] is! String ||
          (json['admin'] != null && json['admin'] is! String) ||
          !json.containsKey('admin')) {
        throw const FormatException();
      }
      return SyncV2DeviceTransfer(
        syncCode: json['sync'] as String,
        adminCode: json['admin'] as String?,
      );
    } catch (_) {
      throw const FormatException('Invalid v2 recovery file');
    }
  }

  factory SyncV2DeviceTransfer.fromQr(String value) {
    try {
      final text = value.trim();
      if (text.length > 18000 || !text.startsWith(qrPrefix)) {
        throw const FormatException();
      }
      final encoded = text.substring(qrPrefix.length);
      final bytes = base64Url.decode(encoded);
      if (base64Url.encode(bytes) != encoded) throw const FormatException();
      return SyncV2DeviceTransfer.fromRecoveryFile(utf8.decode(bytes));
    } catch (_) {
      throw const FormatException('Invalid v2 device pairing QR');
    }
  }
}
