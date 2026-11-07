import 'package:flutter/services.dart';
import 'package:flutter_driver/driver_extension.dart';
import 'package:himemo/main_production.dart' as production;

Future<void> main() async {
  enableFlutterDriverExtension(
    handler: (_) async {
      // These channels used to depend on AppDelegate.window at app launch.
      const network = MethodChannel('org.ruhenheim.himemo/network');
      const privacy = MethodChannel('org.ruhenheim.himemo/privacy');
      final kind = await network.invokeMethod<String>('currentConnectionKind');
      await privacy.invokeMethod<void>('setProtected', {'enabled': true});
      await privacy.invokeMethod<void>('setProtected', {'enabled': false});
      return 'native-channels-ready:$kind';
    },
  );
  await production.main();
}
