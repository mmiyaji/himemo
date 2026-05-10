import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum NetworkConnectionKind { unknown, none, wifi, mobile, ethernet, other }

class NetworkConnectionService {
  const NetworkConnectionService();

  static const _channel = MethodChannel('org.ruhenheim.himemo/network');

  Future<NetworkConnectionKind> currentKind() async {
    if (kIsWeb) {
      return NetworkConnectionKind.unknown;
    }
    try {
      final raw = await _channel.invokeMethod<String>('currentConnectionKind');
      return NetworkConnectionKind.values.firstWhere(
        (kind) => kind.name == raw,
        orElse: () => NetworkConnectionKind.unknown,
      );
    } catch (_) {
      return NetworkConnectionKind.unknown;
    }
  }
}
