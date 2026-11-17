// Compatibility entry for the unified local preview. No iCloud access.
// Run with --dart-define=HIMEMO_NOTE_BACKEND=v2-local.
import 'v2_web_local_preview.dart' as preview;

Future<void> main() => preview.main();
