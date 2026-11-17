import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/home/presentation/home_page.dart';
import '../features/home/presentation/widget_quick_capture_screen.dart';
import '../features/sync/presentation/sync_v2_note_store_provider.dart';
import '../features/sync/presentation/sync_v2_workspace_screen.dart';
import '../features/sync/presentation/sync_v2_cloudkit_web_screen_stub.dart'
    if (dart.library.js_interop) '../features/sync/presentation/sync_v2_cloudkit_web_screen.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/notes',
    redirect: (context, state) async {
      // With the v2 note backend the v1 screens are the v2 UI; do not redirect.
      if (!usesSyncV2NoteBackend &&
          !kIsWeb &&
          defaultTargetPlatform == TargetPlatform.iOS &&
          const [
            '/notes',
            '/calendar',
            '/insights',
            '/trash',
            '/tags',
          ].contains(state.uri.path) &&
          (await SharedPreferences.getInstance()).getBool(
                'settings.sync_v2.enabled',
              ) ==
              true) {
        return '/sync-v2';
      }
      return null;
    },
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/notes'),
      GoRoute(
        path: '/sync-v2',
        redirect: (_, _) => usesSyncV2NoteBackend ? '/settings' : null,
        builder: (context, state) => const SyncV2WorkspaceScreen(),
      ),
      GoRoute(
        path: '/sync-v2-web-readonly',
        redirect: (_, _) => usesSyncV2NoteBackend ? '/settings' : null,
        builder: (context, state) =>
            SyncV2CloudKitReadOnlyScreen(onExit: () => context.go('/settings')),
      ),
      GoRoute(
        path: '/widget-capture',
        pageBuilder: (context, state) => NoTransitionPage(
          key: state.pageKey,
          child: const WidgetQuickCaptureScreen(),
        ),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/notes',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const NotesScreen(),
            ),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const CalendarScreen(),
            ),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const InsightsScreen(),
            ),
          ),
          GoRoute(
            path: '/trash',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const TrashScreen(),
            ),
          ),
          GoRoute(
            path: '/tags',
            pageBuilder: (context, state) =>
                NoTransitionPage(key: state.pageKey, child: const TagsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const SettingsScreen(),
            ),
          ),
          GoRoute(
            path: '/tutorials',
            pageBuilder: (context, state) => NoTransitionPage(
              key: state.pageKey,
              child: const TutorialsScreen(),
            ),
          ),
        ],
      ),
    ],
  );
}
