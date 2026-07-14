import 'package:go_router/go_router.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../features/home/presentation/home_page.dart';
import '../features/home/presentation/widget_quick_capture_screen.dart';

part 'app_router.g.dart';

@Riverpod(keepAlive: true)
GoRouter appRouter(Ref ref) {
  return GoRouter(
    initialLocation: '/notes',
    routes: [
      GoRoute(path: '/', redirect: (_, _) => '/notes'),
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
