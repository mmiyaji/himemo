// Development-only local V2 workspace: flutter run -d chrome -t tools/v2_web_local_preview.dart
// Uses an isolated browser database. No iCloud/remote transport or persistent key store.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace_screen.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_smoke.dart';
import 'package:himemo/l10n/app_strings.dart';
import 'package:web/web.dart' as web;

void main() {
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
  final controller = createLocalPreviewController();
  final router = GoRouter(
    initialLocation: '/preview',
    routes: [
      GoRoute(
        path: '/notes',
        builder: (context, state) => Scaffold(
          body: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('この開発用プレビューには旧メモはありません。'),
                TextButton(
                  onPressed: () => context.go('/preview'),
                  child: const Text('プレビューに戻る'),
                ),
              ],
            ),
          ),
        ),
      ),
      GoRoute(
        path: '/preview',
        builder: (context, state) => const Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                Material(
                  color: Color(0xFFFFE082),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '開発用：サンプル専用。iCloudには同期されません。突然終了時にデータが消える場合があります。再読み込み後はSYNC復元コード、管理者機能にはADMIN復元コードが必要です。',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                Expanded(child: SyncV2WorkspaceScreen(localOnly: true)),
              ],
            ),
          ),
        ),
      ),
    ],
  );
  runApp(
    ProviderScope(
      overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
      child: MaterialApp.router(
        routerConfig: router,
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC64759)),
          useMaterial3: true,
        ),
      ),
    ),
  );
}
