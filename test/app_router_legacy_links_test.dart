import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:himemo/features/home/presentation/home_page.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';

import 'support/sync_v2_workspace_fixture.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets(
    'compose on an unregistered device opens setup before accepting text',
    (tester) async {
      final workspace = (await tester.runAsync(
        () => createSyncV2TestWorkspace(register: false),
      ))!;
      addTearDown(workspace.dispose);
      final router = GoRouter(
        routes: [
          GoRoute(
            path: '/',
            builder: (context, state) => Scaffold(
              body: Consumer(
                builder: (context, ref, _) => TextButton(
                  onPressed: () => showNoteEditorSheet(context, ref),
                  child: const Text('Compose'),
                ),
              ),
            ),
          ),
          GoRoute(
            path: '/settings',
            builder: (_, _) => const Scaffold(body: Text('Setup')),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [syncV2WorkspaceProvider.overrideWithValue(workspace)],
          child: MaterialApp.router(routerConfig: router),
        ),
      );
      await tester.tap(find.text('Compose'));
      await tester.pumpAndSettle();
      expect(find.text('Setup'), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    },
    skip: !usesSyncV2NoteBackend,
  );

  testWidgets(
    'old iOS activation flag preserves unified routes and redirects old links',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'settings.sync_v2.enabled': true,
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final router = container.read(appRouterProvider);
      addTearDown(router.dispose);
      await tester.pumpWidget(const SizedBox());
      final context = tester.element(find.byType(SizedBox));
      for (final path in [
        '/notes',
        '/calendar',
        '/insights',
        '/trash',
        '/tags',
      ]) {
        final match = await router.routeInformationParser
            .parseRouteInformationWithDependencies(
              RouteInformation(uri: Uri.parse(path)),
              context,
            );
        expect(match.isError, isFalse);
        expect(match.uri.path, path);
      }
      for (final path in ['/sync-v2', '/sync-v2-web-readonly']) {
        final match = await router.routeInformationParser
            .parseRouteInformationWithDependencies(
              RouteInformation(uri: Uri.parse(path)),
              context,
            );
        expect(match.isError, isFalse);
        expect(match.uri.path, '/settings');
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
  );
}
