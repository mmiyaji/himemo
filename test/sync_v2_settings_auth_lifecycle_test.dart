import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/sync/presentation/sync_v2_device_security_settings.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/sync_v2_workspace_fixture.dart';

void main() {
  for (final background in [false, true]) {
    testWidgets(
      background
          ? 'real background still revokes admin during device authentication'
          : 'device authentication inactive does not revoke administrator keys',
      (tester) async {
        SharedPreferences.setMockInitialValues({});
        final workspace = (await tester.runAsync(createSyncV2TestWorkspace))!;
        final gateway = _PendingAuth();
        final container = ProviderContainer(
          overrides: [
            syncV2WorkspaceProvider.overrideWithValue(workspace),
            deviceAuthGatewayProvider.overrideWithValue(gateway),
          ],
        );
        addTearDown(container.dispose);
        addTearDown(workspace.dispose);
        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: const MaterialApp(
              home: Scaffold(
                body: SingleChildScrollView(
                  child: SyncV2DeviceSecuritySettings(),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(workspace.adminUnlocked, isTrue);
        final revision = workspace.privateSessionRevision;
        final authentication = container
            .read(deviceAuthControllerProvider.notifier)
            .authenticate(reason: 'Enter administrator mode');
        expect(
          container.read(deviceAuthControllerProvider).isAuthenticating,
          isTrue,
        );
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        expect(workspace.privateSessionRevision, revision);
        expect(workspace.adminUnlocked, isTrue);

        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.paused,
          );
          expect(workspace.adminUnlocked, isFalse);
          expect(workspace.privateSessionRevision, greaterThan(revision));
        }
        gateway.result.complete(true);
        await authentication;
        if (background) {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.hidden,
          );
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
        }
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        expect(workspace.adminUnlocked, !background);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );
  }
}

class _PendingAuth implements DeviceAuthGateway {
  final result = Completer<bool>();

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) => result.future;

  @override
  Future<DeviceAuthState> checkAvailability() async => const DeviceAuthState(
    availability: DeviceAuthAvailability.available,
    methods: ['Biometrics'],
  );
}
