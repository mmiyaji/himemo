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
        AppFlavor.development =>
          development.DefaultFirebaseOptions.currentPlatform,
        AppFlavor.production =>
          production.DefaultFirebaseOptions.currentPlatform,
      };
      await Firebase.initializeApp(options: options);
      await FirebaseAppCheck.instance.activate(
        providerAndroid: flavor == AppFlavor.development
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
      );
      return;
    case TargetPlatform.iOS:
      try {
        await Firebase.initializeApp();
      } on FirebaseException catch (error) {
        if (error.code == 'duplicate-app') {
          return;
        }
        debugPrint(
          'Firebase initialization skipped on iOS: ${error.code} ${error.message ?? ''}',
        );
      }
      return;
    default:
      return;
  }
}
