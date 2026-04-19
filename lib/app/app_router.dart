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
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: WidgetQuickCaptureScreen()),
      ),
      ShellRoute(
        builder: (context, state, child) => AppShell(child: child),
        routes: [
          GoRoute(
            path: '/notes',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: NotesScreen()),
          ),
          GoRoute(
            path: '/calendar',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: CalendarScreen()),
          ),
          GoRoute(
            path: '/insights',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: InsightsScreen()),
          ),
          GoRoute(
            path: '/settings',
            pageBuilder: (context, state) =>
                const NoTransitionPage(child: SettingsScreen()),
          ),
        ],
      ),
    ],
  );
}
