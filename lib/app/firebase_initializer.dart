import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart' as production;
import '../firebase_options_development.dart' as development;
import 'app_flavor.dart';

Future<void> initializeFirebaseForFlavor(AppFlavor flavor) async {
  if (kIsWeb) {
    return;
  }

  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      final options = switch (flavor) {
        AppFlavor.development => development.DefaultFirebaseOptions.currentPlatform,
        AppFlavor.production => production.DefaultFirebaseOptions.currentPlatform,
      };
      await Firebase.initializeApp(options: options);
      await FirebaseAppCheck.instance.activate(
        providerAndroid: flavor == AppFlavor.development
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
      return;
    default:
      return;
  }
}
