import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/foundation.dart';

import '../firebase_options.dart' as production;
import '../firebase_options_development.dart' as development;
import 'app_flavor.dart';

const _useDebugAppCheckForLocalProduction = bool.fromEnvironment(
  'HIMEMO_USE_DEBUG_APP_CHECK_FOR_LOCAL_PRODUCTION',
);

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
      final useDebugProvider =
          flavor == AppFlavor.development ||
          (!kReleaseMode &&
              flavor == AppFlavor.production &&
              _useDebugAppCheckForLocalProduction);
      await FirebaseAppCheck.instance.activate(
        providerAndroid: useDebugProvider
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
