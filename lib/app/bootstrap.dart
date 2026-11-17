import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';
import 'app_flavor.dart';
import 'firebase_initializer.dart';
import 'firebase_observability.dart';
import '../features/sync/presentation/sync_v2_note_store_provider.dart';
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
      if (flavor == AppFlavor.development) {
        // Visible in the browser console; confirms which note store is active.
        debugPrint('HiMemo note backend: $noteBackend');
      }
      await initializeFirebaseForFlavor(flavor);
      await configureFirebaseObservability(enableCollection: kReleaseMode);
      runApp(
        ProviderScope(
          overrides: noteBackendOverrides(),
          child: HiMemoApp(flavor: flavor),
        ),
      );
    },
    (error, stackTrace) {
      unawaited(recordNonFatalError(error, stackTrace, reason: 'bootstrap'));
    },
  );
}
