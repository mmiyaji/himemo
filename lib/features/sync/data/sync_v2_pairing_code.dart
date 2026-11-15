import 'dart:convert';

/// Adds a role-specific QR envelope around existing, cloud-verified v2
/// recovery codes. This codec does not create or verify cryptographic keys.
class SyncV2PairingCode {
  static const syncPrefix = 'himemo-v2-qr:sync:';
  static const administratorPrefix = 'himemo-v2-qr:admin:';
  static const _syncCodeFormat = 'himemo.sync.v2.recovery';
  static const _adminCodePrefix = 'himemo-admin-v2:';
  static final _generationPattern = RegExp(r'^[a-zA-Z0-9_-]{1,80}$');
  static final _base64UrlPattern = RegExp(r'^[A-Za-z0-9_-]+={0,2}$');

  static String encodeQr(String code, {required bool administrator}) {
    _validateCode(code, administrator: administrator);
    return '${administrator ? administratorPrefix : syncPrefix}$code';
  }

  /// Decodes only a recognized pairing QR envelope for the requested role.
  /// Leading/trailing whitespace from scanners is ignored; the code itself is
  /// returned unchanged and still requires the normal cloud/account checks.
  static String decodeQr(String value, {required bool administrator}) {
    try {
      final trimmed = value.trim();
      final prefix = administrator ? administratorPrefix : syncPrefix;
      if (!trimmed.startsWith(prefix)) throw const FormatException();
      final code = trimmed.substring(prefix.length);
      if (code.length > 4096) throw const FormatException();
      _validateCode(code, administrator: administrator);
      return code;
    } catch (_) {
      throw FormatException(
        'Invalid ${administrator ? 'administrator' : 'sync'} v2 pairing QR code',
      );
    }
  }

  static void _validateCode(String code, {required bool administrator}) {
    if (code.isEmpty || code.length > 4096) {
      throw const FormatException('Invalid v2 pairing code');
    }
    if (administrator) {
      _validateAdministratorCode(code);
    } else {
      _validateSyncCode(code);
    }
  }

  static void _validateSyncCode(String code) {
    try {
      if (!_base64UrlPattern.hasMatch(code)) throw const FormatException();
      final bytes = base64Url.decode(code);
      if (base64Url.encode(bytes) != code) throw const FormatException();
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          value.length != 5 ||
          !value.keys.toSet().containsAll({
            'format',
            'version',
            'account',
            'generation',
            'key',
          }) ||
          value['format'] != _syncCodeFormat ||
          value['version'] is! int ||
          value['version'] != 1 ||
          value['account'] is! String ||
          (value['account'] as String).isEmpty ||
          (value['account'] as String).length > 1024 ||
          value['generation'] is! String ||
          !_generationPattern.hasMatch(value['generation'] as String) ||
          value['key'] is! String) {
        throw const FormatException();
      }
      final encodedKey = value['key'] as String;
      if (!_base64UrlPattern.hasMatch(encodedKey)) {
        throw const FormatException();
      }
      final key = base64Url.decode(encodedKey);
      if (key.length != 32 || base64Url.encode(key) != encodedKey) {
        throw const FormatException();
      }
    } catch (_) {
      throw const FormatException('Invalid v2 sync pairing code');
    }
  }

  static void _validateAdministratorCode(String code) {
    try {
      if (!code.startsWith(_adminCodePrefix)) throw const FormatException();
      final encoded = code.substring(_adminCodePrefix.length);
      if (encoded.isEmpty ||
          encoded.length > 4096 ||
          !_base64UrlPattern.hasMatch(encoded)) {
        throw const FormatException();
      }
      final bytes = base64Url.decode(encoded);
      if (base64Url.encode(bytes) != encoded) throw const FormatException();
      final value = jsonDecode(utf8.decode(bytes));
      if (value is! Map<String, dynamic> ||
          value.length != 2 ||
          !value.keys.toSet().containsAll({'generation', 'key'}) ||
          value['generation'] is! String ||
          !_generationPattern.hasMatch(value['generation'] as String) ||
          value['key'] is! String) {
        throw const FormatException();
      }
      final encodedKey = value['key'] as String;
      final key = base64Decode(encodedKey);
      if (key.length != 32 || base64Encode(key) != encodedKey) {
        throw const FormatException();
      }
    } catch (_) {
      throw const FormatException('Invalid administrator v2 pairing code');
    }
  }
}
