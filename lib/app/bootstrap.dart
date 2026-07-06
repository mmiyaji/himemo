import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';

import 'ad_mob_initializer.dart';
import 'app.dart';
import 'app_flavor.dart';
import 'firebase_initializer.dart';
import 'firebase_observability.dart';
import 'record_web_plugin_registrar_stub.dart'
    if (dart.library.html) 'record_web_plugin_registrar_web.dart';

Future<void> bootstrap(AppFlavor flavor) async {
  await runZonedGuarded(
    () async {
      final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
      registerRecordWebPlugin();
      if (!kIsWeb) {
        FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
      }
      if (kIsWeb && flavor == AppFlavor.development) {
        SemanticsBinding.instance.ensureSemantics();
      }
      configureFlavor(flavor);
      await initializeFirebaseForFlavor(flavor);
      await configureFirebaseObservability(enableCollection: kReleaseMode);
      await initializeAdMob();
      runApp(ProviderScope(child: HiMemoApp(flavor: flavor)));
    },
    (error, stackTrace) {
      unawaited(recordNonFatalError(error, stackTrace, reason: 'bootstrap'));
    },
  );
}
