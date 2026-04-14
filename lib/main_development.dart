import 'app/app_flavor.dart';
import 'app/bootstrap.dart';

Future<void> main() async {
  await bootstrap(AppFlavor.development);
}
