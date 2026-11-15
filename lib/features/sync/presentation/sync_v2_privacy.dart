import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Route lifetime protection is independent of the legacy private session.
final syncV2PrivacyRouteProvider = NotifierProvider<SyncV2PrivacyRoute, int>(
  SyncV2PrivacyRoute.new,
);
final syncV2PrivacyActiveProvider = Provider<bool>(
  (ref) => ref.watch(syncV2PrivacyRouteProvider) > 0,
);

class SyncV2PrivacyRoute extends Notifier<int> {
  @override
  int build() => 0;
  void acquire() {
    if (ref.mounted) state++;
  }

  void release() {
    if (ref.mounted && state > 0) state--;
  }
}
