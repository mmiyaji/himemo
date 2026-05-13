import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'diagnostic_log.dart';

enum NetworkConnectionKind { unknown, none, wifi, mobile, ethernet, other }

class NetworkConnectionService {
  const NetworkConnectionService();

  static const _channel = MethodChannel('org.ruhenheim.himemo/network');

  Future<NetworkConnectionKind> currentKind() async {
    if (kIsWeb) {
      logDiagnostic(
        'network',
        'connection kind unavailable',
        data: {'platform': 'web'},
      );
      return NetworkConnectionKind.unknown;
    }
    try {
      final raw = await _channel.invokeMethod<String>('currentConnectionKind');
      final kind = NetworkConnectionKind.values.firstWhere(
        (kind) => kind.name == raw,
        orElse: () => NetworkConnectionKind.unknown,
      );
      logDiagnostic(
        'network',
        'connection kind read',
        data: {'kind': kind.name},
      );
      return kind;
    } catch (error) {
      logDiagnostic(
        'network',
        'connection kind read failed',
        data: {'error': error},
      );
      return NetworkConnectionKind.unknown;
    }
  }
}
