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

/// Only the transient inactive state of an app-owned system picker is exempt
/// from relocking. Hidden/paused still revoke every protected session.
final syncV2SystemPickerProvider = NotifierProvider<SyncV2SystemPicker, bool>(
  SyncV2SystemPicker.new,
);

class SyncV2SystemPicker extends Notifier<bool> {
  @override
  bool build() => false;
  void begin() {
    if (ref.mounted) state = true;
  }

  void end() {
    if (ref.mounted) state = false;
  }
}
