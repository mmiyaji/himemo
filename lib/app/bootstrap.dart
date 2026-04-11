import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app.dart';
import 'app_flavor.dart';

void bootstrap(AppFlavor flavor) {
  WidgetsFlutterBinding.ensureInitialized();
  configureFlavor(flavor);
  runApp(ProviderScope(child: HiMemoApp(flavor: flavor)));
}
