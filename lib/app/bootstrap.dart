import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/semantics.dart';

import 'app.dart';
import 'app_flavor.dart';

void bootstrap(AppFlavor flavor) {
  final widgetsBinding = WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb) {
    FlutterNativeSplash.preserve(widgetsBinding: widgetsBinding);
  }
  if (kIsWeb && flavor == AppFlavor.development) {
    SemanticsBinding.instance.ensureSemantics();
  }
  configureFlavor(flavor);
  runApp(ProviderScope(child: HiMemoApp(flavor: flavor)));
}
