import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('a build with no backend flag uses v2', () {
    expect(noteBackend, 'v2');
  }, skip: const bool.hasEnvironment('HIMEMO_NOTE_BACKEND'));

  test('production rejects unsupported startup backends', () {
    configureFlavor(AppFlavor.production);
    expect(isDevelopmentFlavor, isFalse);
    if (noteBackend == 'v2-local') {
      expect(noteBackendOverrides, throwsStateError);
      configureFlavor(AppFlavor.development);
      expect(noteBackendOverrides(), hasLength(1));
    } else if (noteBackend == 'v2') {
      expect(noteBackendOverrides(), isEmpty);
    } else {
      expect(noteBackendOverrides, throwsStateError);
    }
  });
}
