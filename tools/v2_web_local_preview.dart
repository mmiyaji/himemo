// Unified local preview: flutter run -d chrome -t tools/v2_web_local_preview.dart
// --dart-define=HIMEMO_NOTE_BACKEND=v2-local
// Uses an isolated browser database. No iCloud/remote transport or persistent key store.
import 'package:flutter/material.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/app/bootstrap.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_smoke.dart';
import 'package:web/web.dart' as web;

Future<void> main() async {
  if (Uri.base.queryParameters['v2LocalSmoke'] == '1') {
    web.document.documentElement?.setAttribute(
      'data-v2-local-smoke',
      'running',
    );
    runApp(const MaterialApp(home: Scaffold(body: Text('ローカル検証を実行中'))));
    runLocalV2Smoke().then(
      (_) {
        web.document.documentElement?.setAttribute(
          'data-v2-local-smoke',
          'passed',
        );
      },
      onError: (Object error, StackTrace stackTrace) {
        debugPrint('Local V2 smoke failed: $error\n$stackTrace');
        web.document.documentElement?.setAttribute(
          'data-v2-local-smoke',
          'failed',
        );
      },
    );
    return;
  }
  if (noteBackend != 'v2-local') {
    throw StateError(
      'Run this preview with --dart-define=HIMEMO_NOTE_BACKEND=v2-local.',
    );
  }
  await bootstrap(AppFlavor.development);
}
