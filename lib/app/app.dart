import 'package:flutter/material.dart';
import 'dart:async';

import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:pinput/pinput.dart';

import '../features/home/presentation/home_providers.dart';
import '../l10n/app_localizations.dart';
import '../l10n/app_strings.dart';
import 'app_flavor.dart';
import 'app_router.dart';

class HiMemoApp extends ConsumerWidget {
  const HiMemoApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(effectiveAppColorThemeProvider);
    final localeSetting = ref.watch(appLocaleControllerProvider);
    final launchSurface = ref.watch(appLaunchControllerProvider);
    final router = ref.watch(appRouterProvider);
    final currentLocation = router.routeInformationProvider.value.uri.path;
    final locale = switch (localeSetting) {
      AppLocaleSetting.system => null,
      AppLocaleSetting.japanese => const Locale('ja'),
      AppLocaleSetting.english => const Locale('en'),
      AppLocaleSetting.chinese => const Locale('zh'),
      AppLocaleSetting.korean => const Locale('ko'),
      AppLocaleSetting.spanish => const Locale('es'),
      AppLocaleSetting.german => const Locale('de'),
    };

    ref.watch(widgetQuickCaptureBridgeProvider);
    ref.watch(inAppUpdateControllerProvider);
    ref.listen(widgetQuickCaptureRequestControllerProvider, (previous, next) {
      if (previous == next || next == null) {
        return;
      }
      router.go('/widget-capture');
    });

    return FlavorBanner(
      child: MaterialApp.router(
        title: flavor.displayName,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localeListResolutionCallback: (locales, supportedLocales) {
          for (final deviceLocale in locales ?? const <Locale>[]) {
            for (final supportedLocale in supportedLocales) {
              if (supportedLocale.languageCode == deviceLocale.languageCode) {
                return supportedLocale;
              }
            }
          }
          return const Locale('en');
        },
        localizationsDelegates: const [
          AppLocalizations.delegate,
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        themeMode: themeMode,
        theme: _buildTheme(Brightness.light, colorTheme),
        darkTheme: _buildTheme(Brightness.dark, colorTheme),
        builder: (context, child) {
          return _LaunchSurfaceGate(
            flavor: flavor,
            launchSurface: launchSurface,
            currentLocation: currentLocation,
            child: child,
          );
        },
      ),
    );
  }
}

class _LaunchSurfaceGate extends StatefulWidget {
  const _LaunchSurfaceGate({
    required this.flavor,
    required this.launchSurface,
    required this.currentLocation,
    required this.child,
  });

  final AppFlavor flavor;
  final AppLaunchSurface launchSurface;
  final String currentLocation;
  final Widget? child;

  @override
  State<_LaunchSurfaceGate> createState() => _LaunchSurfaceGateState();
}

class _LaunchSurfaceGateState extends State<_LaunchSurfaceGate> {
  bool _removedNativeSplash = false;

  @override
  void initState() {
    super.initState();
    _syncNativeSplash();
  }

  @override
  void didUpdateWidget(covariant _LaunchSurfaceGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncNativeSplash();
  }

  void _syncNativeSplash() {
    if (kIsWeb || _removedNativeSplash) {
      return;
    }
    _removedNativeSplash = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      FlutterNativeSplash.remove();
    });
  }

  @override
  Widget build(BuildContext context) {
    switch (widget.launchSurface) {
      case AppLaunchSurface.onboarding:
        return _OnboardingScreen(flavor: widget.flavor);
      case AppLaunchSurface.ready:
        return _AppLockGate(
          currentLocation: widget.currentLocation,
          child: widget.child,
        );
    }
  }
}

class _AppLockGate extends ConsumerStatefulWidget {
  const _AppLockGate({required this.currentLocation, required this.child});

  final String currentLocation;
  final Widget? child;

  @override
  ConsumerState<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<_AppLockGate>
    with WidgetsBindingObserver {
  static const _privateSessionTimeout = Duration(minutes: 5);
  static const _privacyChannel = MethodChannel('org.ruhenheim.himemo/privacy');

  bool _privacyScreenEnabled = false;
  bool _autoPrompted = false;
  bool _updateChecked = false;
  DateTime? _backgroundedAt;
  Timer? _privateSessionTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLockState(triggerPrompt: true);
      _checkForInAppUpdate();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _privateSessionTimer?.cancel();
    unawaited(_setPrivacyScreenEnabled(false));
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncLockState(triggerPrompt: true);
      _refreshPrivateSessionTimer();
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      if (ref.read(appLockSettingsControllerProvider) &&
          ref.read(appLockRelockDelayControllerProvider) ==
              AppLockRelockDelay.immediate) {
        _lockAppSessionOnly();
      }
    }
  }

  Future<void> _syncLockState({required bool triggerPrompt}) async {
    final enabled = ref.read(appLockSettingsControllerProvider);
    if (!enabled) {
      ref.read(appSessionUnlockControllerProvider.notifier).unlock();
      _refreshPrivateSessionTimer();
      return;
    }

    if (_shouldRelockAfterBackground()) {
      _lockAppSessionOnly();
    }

    if (ref.read(appSessionUnlockControllerProvider)) {
      _refreshPrivateSessionTimer();
      return;
    }

    if (!triggerPrompt || _autoPrompted) {
      return;
    }
    if (kIsWeb) {
      return;
    }
    _autoPrompted = true;
    await ref
        .read(deviceAuthControllerProvider.notifier)
        .authenticate(reason: 'Unlock HiMemo with device authentication');
    if (mounted && ref.read(appSessionUnlockControllerProvider)) {
      setState(() {
        _autoPrompted = true;
      });
    }
  }

  bool _shouldRelockAfterBackground() {
    final backgroundedAt = _backgroundedAt;
    if (backgroundedAt == null) {
      return false;
    }
    final delay = ref.read(appLockRelockDelayControllerProvider);
    if (delay == AppLockRelockDelay.immediate) {
      return false;
    }
    final elapsed = DateTime.now().difference(backgroundedAt);
    return elapsed >= _durationForDelay(delay);
  }

  Duration _durationForDelay(AppLockRelockDelay delay) {
    return switch (delay) {
      AppLockRelockDelay.immediate => Duration.zero,
      AppLockRelockDelay.seconds30 => const Duration(seconds: 30),
      AppLockRelockDelay.minutes2 => const Duration(minutes: 2),
      AppLockRelockDelay.minutes10 => const Duration(minutes: 10),
    };
  }

  void _lockAppSessionOnly() {
    ref.read(appSessionUnlockControllerProvider.notifier).lock();
    if (ref.read(privateVaultLockOnAppLockControllerProvider)) {
      _lockPrivateSessions();
    }
    _autoPrompted = false;
  }

  void _lockProtectedSessions({required bool lockAppSession}) {
    final wasPrivateActive = _isPrivateOrAdminActive();
    if (lockAppSession) {
      ref.read(appSessionUnlockControllerProvider.notifier).lock();
    }
    _lockPrivateSessions();
    if (wasPrivateActive) {
      ref.read(searchQueryProvider.notifier).setQuery('');
      ref.read(searchFiltersControllerProvider.notifier).reset();
      ref.read(selectedNoteIdProvider.notifier).select(null);
    }
    _privateSessionTimer?.cancel();
    _autoPrompted = false;
  }

  void _lockPrivateSessions() {
    ref.read(privateVaultSessionControllerProvider.notifier).lock();
    ref.read(unlockedPrivateProfileVaultIdProvider.notifier).lock();
    ref.read(adminModeSessionControllerProvider.notifier).lock();
  }

  bool _isPrivateOrAdminActive() {
    return ref.read(privateVaultSessionControllerProvider) ||
        ref.read(unlockedPrivateProfileVaultIdProvider) != null ||
        ref.read(adminModeSessionControllerProvider);
  }

  Future<void> _setPrivacyScreenEnabled(bool enabled) async {
    if (_privacyScreenEnabled == enabled) {
      return;
    }
    if (kIsWeb ||
        !(defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.android)) {
      _privacyScreenEnabled = enabled;
      return;
    }
    try {
      await _privacyChannel.invokeMethod<void>('setProtected', {
        'enabled': enabled,
      });
      _privacyScreenEnabled = enabled;
    } catch (_) {}
  }

  void _refreshPrivateSessionTimer() {
    _privateSessionTimer?.cancel();
    if (!_isPrivateOrAdminActive()) {
      return;
    }
    _privateSessionTimer = Timer(_privateSessionTimeout, () {
      if (!mounted) {
        return;
      }
      _lockProtectedSessions(lockAppSession: false);
    });
  }

  Future<void> _checkForInAppUpdate() async {
    if (_updateChecked) {
      return;
    }
    _updateChecked = true;
    final controller = ref.read(inAppUpdateControllerProvider.notifier);
    await controller.check(silentIfUnsupported: true);
    final updateState = ref.read(inAppUpdateControllerProvider);
    final status = updateState.status;
    if (status == null || !status.updateAvailable) {
      return;
    }
    if (!mounted) {
      return;
    }
    await controller.startPreferredUpdate();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final enabled = ref.watch(appLockSettingsControllerProvider);
    final unlocked = ref.watch(appSessionUnlockControllerProvider);
    final privacyScreenActive = ref.watch(privacyScreenActiveProvider);
    final authState = ref.watch(deviceAuthControllerProvider);
    final pinState = ref.watch(appPinLockControllerProvider);
    final bypassForQuickCapture = widget.currentLocation.startsWith(
      '/widget-capture',
    );

    ref.listen<bool>(privacyScreenActiveProvider, (previous, next) {
      unawaited(_setPrivacyScreenEnabled(next));
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_setPrivacyScreenEnabled(privacyScreenActive));
    });

    if (!enabled || unlocked || bypassForQuickCapture) {
      _refreshPrivateSessionTimer();
      return Focus(
        canRequestFocus: false,
        onKeyEvent: (_, __) {
          _refreshPrivateSessionTimer();
          return KeyEventResult.ignored;
        },
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _refreshPrivateSessionTimer(),
          onPointerMove: (_) => _refreshPrivateSessionTimer(),
          onPointerSignal: (_) => _refreshPrivateSessionTimer(),
          child: widget.child ?? const SizedBox.shrink(),
        ),
      );
    }

    return Scaffold(
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = constraints.maxWidth >= 960;
            final colorScheme = Theme.of(context).colorScheme;
            return Row(
              children: [
                Expanded(
                  flex: wide ? 6 : 1,
                  child: Container(
                    color: colorScheme.surface,
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'HiMemo',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const Spacer(),
                        Icon(
                          kIsWeb
                              ? Icons.pin_outlined
                              : Icons.fingerprint_rounded,
                          size: 56,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(height: 20),
                        Text(
                          strings.unlockHiMemo,
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          kIsWeb
                              ? strings.browserPinGate
                              : strings.deviceAuthGate,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: colorScheme.onSurfaceVariant),
                        ),
                        const SizedBox(height: 24),
                        if (wide)
                          Text(
                            strings.privateVaultLockedMessage,
                            style: Theme.of(context).textTheme.bodyMedium
                                ?.copyWith(color: colorScheme.onSurfaceVariant),
                          ),
                        const Spacer(),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  flex: wide ? 5 : 1,
                  child: Container(
                    color: colorScheme.surfaceContainer,
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 440),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              kIsWeb ? pinState.summary : authState.summary,
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.bodyMedium
                                  ?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                            ),
                            const SizedBox(height: 24),
                            if (kIsWeb)
                              const _WebPinUnlockPanel()
                            else
                              FilledButton.icon(
                                onPressed: () async {
                                  await ref
                                      .read(
                                        deviceAuthControllerProvider.notifier,
                                      )
                                      .authenticate(
                                        reason:
                                            'Unlock HiMemo with device authentication',
                                      );
                                },
                                icon: const Icon(Icons.lock_open_rounded),
                                label: Text(strings.authenticate),
                              ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(
                                      appLockSettingsControllerProvider
                                          .notifier,
                                    )
                                    .setEnabled(false);
                                ref
                                    .read(
                                      appSessionUnlockControllerProvider
                                          .notifier,
                                    )
                                    .unlock();
                              },
                              child: Text(strings.disableUnlockForNow),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WebPinUnlockPanel extends ConsumerStatefulWidget {
  const _WebPinUnlockPanel();

  @override
  ConsumerState<_WebPinUnlockPanel> createState() => _WebPinUnlockPanelState();
}

class _WebPinUnlockPanelState extends ConsumerState<_WebPinUnlockPanel> {
  final TextEditingController _pinController = TextEditingController();

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pinState = ref.watch(appPinLockControllerProvider);
    final colorScheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Pinput(
          key: const Key('web-pin-unlock-input'),
          controller: _pinController,
          length: 4,
          obscureText: true,
          obscuringCharacter: '•',
          keyboardType: TextInputType.number,
          defaultPinTheme: PinTheme(
            width: 48,
            height: 56,
            textStyle: Theme.of(context).textTheme.titleLarge,
            decoration: BoxDecoration(
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          focusedPinTheme: PinTheme(
            width: 48,
            height: 56,
            textStyle: Theme.of(context).textTheme.titleLarge,
            decoration: BoxDecoration(
              border: Border.all(color: colorScheme.primary, width: 1.5),
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          onCompleted: (_) async => _submit(),
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _submit,
          icon: const Icon(Icons.lock_open_rounded),
          label: Text(strings.unlockWithPin),
        ),
        if (pinState.lastError != null) ...[
          const SizedBox(height: 12),
          Text(
            pinState.lastError!,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
          ),
        ],
      ],
    );
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length != 4) {
      return;
    }
    final matched = await ref
        .read(appPinLockControllerProvider.notifier)
        .verify(pin);
    if (matched) {
      _pinController.clear();
    }
  }
}

class _OnboardingScreen extends ConsumerStatefulWidget {
  const _OnboardingScreen({required this.flavor});

  final AppFlavor flavor;

  @override
  ConsumerState<_OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<_OnboardingScreen> {
  final PageController _pageController = PageController();
  int _pageIndex = 0;

  List<
    ({
      String title,
      String body,
      IconData icon,
      String imagePath,
      String imageSemanticLabel,
      bool isSetupPage,
    })
  >
  _pages(AppStrings strings) => [
    (
      title: strings.onboardingCaptureTitle,
      body: strings.onboardingCaptureBody,
      icon: Icons.bolt_rounded,
      imagePath: 'assets/onboarding/capture-illustration.png',
      imageSemanticLabel: strings.onboardingCaptureImageLabel,
      isSetupPage: false,
    ),
    (
      title: strings.onboardingPrivateTitle,
      body: strings.onboardingPrivateBody,
      icon: Icons.lock_person_rounded,
      imagePath: 'assets/onboarding/private-illustration.png',
      imageSemanticLabel: strings.onboardingPrivateImageLabel,
      isSetupPage: false,
    ),
    (
      title: strings.onboardingSyncTitle,
      body: strings.onboardingSyncBody,
      icon: Icons.cloud_sync_rounded,
      imagePath: 'assets/onboarding/sync-illustration.png',
      imageSemanticLabel: strings.onboardingSyncImageLabel,
      isSetupPage: false,
    ),
    (
      title: strings.onboardingFinishTitle,
      body: strings.onboardingFinishBody,
      icon: Icons.key_rounded,
      imagePath: 'assets/onboarding/private.png',
      imageSemanticLabel: strings.onboardingFinishImageLabel,
      isSetupPage: true,
    ),
  ];

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final pages = _pages(strings);
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _pageIndex == pages.length - 1;
    final pinConfigured = ref.watch(appPinLockControllerProvider).isConfigured;
    final privateProfiles = ref.watch(privateMemoProfilesControllerProvider);

    return Navigator(
      pages: [
        MaterialPage<void>(
          child: Scaffold(
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            widget.flavor.displayName,
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                        ),
                        const Spacer(),
                        TextButton(
                          onPressed: () => ref
                              .read(appLaunchControllerProvider.notifier)
                              .completeOnboarding(),
                          child: Text(strings.skip),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      strings.onboardingWelcome,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.onboardingIntro,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: pages.length,
                        onPageChanged: (index) {
                          setState(() {
                            _pageIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final page = pages[index];
                          return LayoutBuilder(
                            builder: (context, constraints) {
                              return Container(
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.all(24),
                                decoration: BoxDecoration(
                                  color: colorScheme.surface,
                                  borderRadius: BorderRadius.circular(24),
                                  border: Border.all(
                                    color: Theme.of(context).dividerColor,
                                  ),
                                ),
                                child: SingleChildScrollView(
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minHeight:
                                          constraints.maxHeight.isFinite &&
                                              constraints.maxHeight > 48
                                          ? constraints.maxHeight - 48
                                          : 0,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color: colorScheme.primary
                                                .withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(
                                              18,
                                            ),
                                          ),
                                          child: Icon(
                                            page.icon,
                                            color: colorScheme.primary,
                                          ),
                                        ),
                                        const SizedBox(height: 24),
                                        if (!page.isSetupPage) ...[
                                          _OnboardingImageCard(
                                            imagePath: page.imagePath,
                                            semanticLabel:
                                                page.imageSemanticLabel,
                                            fallbackIcon: page.icon,
                                          ),
                                          const SizedBox(height: 24),
                                        ],
                                        Text(
                                          page.title,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.titleLarge,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          page.body,
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodyLarge,
                                        ),
                                        if (page.isSetupPage) ...[
                                          const SizedBox(height: 24),
                                          _OnboardingSetupPanel(
                                            pinConfigured: pinConfigured,
                                            privateProfileCount:
                                                privateProfiles.length,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                    Row(
                      children: [
                        for (var i = 0; i < pages.length; i++)
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            margin: const EdgeInsets.only(right: 8),
                            width: i == _pageIndex ? 28 : 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: i == _pageIndex
                                  ? colorScheme.primary
                                  : colorScheme.outlineVariant,
                              borderRadius: BorderRadius.circular(999),
                            ),
                          ),
                        const Spacer(),
                        FilledButton(
                          key: const Key('onboarding-next-button'),
                          onPressed: () async {
                            if (isLastPage) {
                              await ref
                                  .read(appLaunchControllerProvider.notifier)
                                  .completeOnboarding();
                              return;
                            }
                            await _pageController.nextPage(
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOut,
                            );
                          },
                          child: Text(
                            isLastPage ? strings.finishSetup : strings.next,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
      onDidRemovePage: (_) {},
    );
  }
}

class _OnboardingImageCard extends StatelessWidget {
  const _OnboardingImageCard({
    required this.imagePath,
    required this.semanticLabel,
    required this.fallbackIcon,
  });

  final String imagePath;
  final String semanticLabel;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final strings = context.strings;

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxCardHeight = constraints.maxWidth >= 900 ? 280.0 : 360.0;
        return ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxCardHeight),
            child: AspectRatio(
              aspectRatio: 16 / 9,
              child: ColoredBox(
                color: colorScheme.surfaceContainerHighest,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(
                      imagePath,
                      fit: BoxFit.cover,
                      semanticLabel: semanticLabel,
                      filterQuality: FilterQuality.medium,
                      errorBuilder: (context, error, stackTrace) {
                        return DecoratedBox(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: [
                                colorScheme.surfaceContainerHighest,
                                colorScheme.primary.withValues(alpha: 0.16),
                              ],
                            ),
                          ),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  fallbackIcon,
                                  size: 40,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  strings.onboardingAddImageFallback,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            colorScheme.surface.withValues(alpha: 0.08),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _OnboardingSetupPanel extends ConsumerWidget {
  const _OnboardingSetupPanel({
    required this.pinConfigured,
    required this.privateProfileCount,
  });

  final bool pinConfigured;
  final int privateProfileCount;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _OnboardingSetupPanelBody(
      pinConfigured: pinConfigured,
      privateProfileCount: privateProfileCount,
    );
  }
}

class _OnboardingSetupPanelBody extends ConsumerStatefulWidget {
  const _OnboardingSetupPanelBody({
    required this.pinConfigured,
    required this.privateProfileCount,
  });

  final bool pinConfigured;
  final int privateProfileCount;

  @override
  ConsumerState<_OnboardingSetupPanelBody> createState() =>
      _OnboardingSetupPanelBodyState();
}

class _OnboardingSetupPanelBodyState
    extends ConsumerState<_OnboardingSetupPanelBody> {
  String? _pinFeedback;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-pin-button'),
          title: kIsWeb
              ? strings.setAppUnlockPin
              : strings.onboardingAppUnlockTitle,
          subtitle: kIsWeb
              ? (widget.pinConfigured
                    ? strings.onboardingPinConfiguredBrowser
                    : strings.onboardingSetPinBrowser)
              : strings.onboardingDeviceAuthLater,
          actionLabel: kIsWeb
              ? (widget.pinConfigured
                    ? strings.onboardingChangePin
                    : strings.onboardingSetPin)
              : strings.onboardingLaterInSettings,
          onPressed: kIsWeb
              ? () async {
                  final pin = await _showOnboardingPinSetupDialog(context);
                  if (pin == null) {
                    return;
                  }
                  await ref
                      .read(appPinLockControllerProvider.notifier)
                      .configure(pin);
                  await ref
                      .read(appLockSettingsControllerProvider.notifier)
                      .setEnabled(true);
                  if (!mounted) {
                    return;
                  }
                  setState(() {
                    _pinFeedback = strings.onboardingPinSaved;
                  });
                }
              : null,
          feedback: _pinFeedback,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-private-profiles-info-button'),
          title: strings.onboardingPrivateProfilesTitle,
          subtitle: widget.privateProfileCount > 0
              ? strings.onboardingPrivateProfilesConfigured(
                  widget.privateProfileCount,
                )
              : strings.onboardingPrivateProfilesBody,
          actionLabel: strings.onboardingAddInSettings,
          onPressed: null,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-sync-info-button'),
          title: strings.onboardingCloudSyncTitle,
          subtitle: strings.onboardingCloudSyncBody,
          actionLabel: strings.onboardingLaterInSettings,
          onPressed: null,
        ),
      ],
    );
  }
}

class _OnboardingSetupTile extends StatelessWidget {
  const _OnboardingSetupTile({
    required this.tileKey,
    required this.title,
    required this.subtitle,
    required this.actionLabel,
    this.onPressed,
    this.feedback,
  });

  final Key tileKey;
  final String title;
  final String subtitle;
  final String actionLabel;
  final VoidCallback? onPressed;
  final String? feedback;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border.all(color: Theme.of(context).dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                if (feedback != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    feedback!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton.tonal(
            key: tileKey,
            onPressed: onPressed,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

Future<String?> _showOnboardingPinSetupDialog(BuildContext context) {
  final strings = context.strings;
  final controller = TextEditingController();
  String? errorText;
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(strings.setAppUnlockPin),
            content: SizedBox(
              width: 320,
              child: TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: strings.pin,
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final pin = controller.text.trim();
                  if (pin.length != 4) {
                    setState(() {
                      errorText = strings.useExactly4Digits;
                    });
                    return;
                  }
                  if (!RegExp(r'^\d+$').hasMatch(pin)) {
                    setState(() {
                      errorText = strings.digitsOnly;
                    });
                    return;
                  }
                  Navigator.of(context).pop(pin);
                },
                child: Text(strings.save),
              ),
            ],
          );
        },
      );
    },
  );
}

ThemeData _buildTheme(Brightness brightness, AppColorTheme colorTheme) {
  final palette = _paletteFor(colorTheme, brightness);
  final scheme =
      ColorScheme.fromSeed(
        seedColor: palette.primary,
        brightness: brightness,
      ).copyWith(
        primary: palette.primary,
        onPrimary: palette.onPrimary,
        secondary: palette.secondary,
        onSecondary: palette.onSecondary,
        tertiary: palette.tertiary,
        onTertiary: palette.onTertiary,
        surface: palette.surface,
        onSurface: palette.onSurface,
        surfaceContainer: palette.surfaceContainer,
        surfaceContainerHighest: palette.surfaceContainerHighest,
        outline: palette.outline,
        outlineVariant: palette.outlineVariant,
        onSurfaceVariant: palette.onSurfaceVariant,
      );

  final baseTypography = Typography.material2021(
    colorScheme: scheme,
    platform: TargetPlatform.android,
  );
  final textTheme = _applyJapaneseFontFallback(
    (brightness == Brightness.dark
            ? baseTypography.white
            : baseTypography.black)
        .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface),
  );

  return ThemeData(
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.scaffoldBackground,
    canvasColor: palette.scaffoldBackground,
    appBarTheme: AppBarTheme(
      backgroundColor: palette.appBarBackground,
      foregroundColor: scheme.onSurface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      centerTitle: false,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: palette.navigationBackground,
      indicatorColor: scheme.surfaceContainerHighest,
      iconTheme: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? scheme.primary
            : scheme.onSurfaceVariant;
        return IconThemeData(color: color);
      }),
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        return TextStyle(
          color: states.contains(WidgetState.selected)
              ? scheme.onSurface
              : scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        );
      }),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: scheme.primary,
        side: BorderSide(color: scheme.outline),
      ),
    ),
    dividerColor: scheme.outline,
    textTheme: textTheme.copyWith(
      headlineSmall: textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      titleLarge: textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
      titleMedium: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
      bodyLarge: textTheme.bodyLarge?.copyWith(height: 1.6),
      bodyMedium: textTheme.bodyMedium?.copyWith(height: 1.6),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: scheme.onSurfaceVariant,
      textColor: scheme.onSurface,
      selectedColor: scheme.primary,
    ),
    chipTheme: ChipThemeData(
      backgroundColor: scheme.surfaceContainer,
      side: BorderSide(color: scheme.outline),
      labelStyle: TextStyle(color: scheme.onSurface),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: scheme.primary,
      foregroundColor: scheme.onPrimary,
    ),
    useMaterial3: true,
  );
}

const _japaneseFontFallback = <String>[
  'Noto Sans JP',
  'Hiragino Sans',
  'Yu Gothic UI',
  'Yu Gothic',
  'Meiryo',
  'MS PGothic',
  'sans-serif',
];

TextTheme _applyJapaneseFontFallback(TextTheme textTheme) {
  TextStyle? withFallback(TextStyle? style) {
    if (style == null) {
      return null;
    }
    return style.copyWith(fontFamilyFallback: _japaneseFontFallback);
  }

  return textTheme.copyWith(
    displayLarge: withFallback(textTheme.displayLarge),
    displayMedium: withFallback(textTheme.displayMedium),
    displaySmall: withFallback(textTheme.displaySmall),
    headlineLarge: withFallback(textTheme.headlineLarge),
    headlineMedium: withFallback(textTheme.headlineMedium),
    headlineSmall: withFallback(textTheme.headlineSmall),
    titleLarge: withFallback(textTheme.titleLarge),
    titleMedium: withFallback(textTheme.titleMedium),
    titleSmall: withFallback(textTheme.titleSmall),
    bodyLarge: withFallback(textTheme.bodyLarge),
    bodyMedium: withFallback(textTheme.bodyMedium),
    bodySmall: withFallback(textTheme.bodySmall),
    labelLarge: withFallback(textTheme.labelLarge),
    labelMedium: withFallback(textTheme.labelMedium),
    labelSmall: withFallback(textTheme.labelSmall),
  );
}

_ThemePalette _paletteFor(AppColorTheme theme, Brightness brightness) {
  final isDark = brightness == Brightness.dark;

  switch (theme) {
    case AppColorTheme.blue:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFF9CB1FF),
              onPrimary: Color(0xFF091338),
              secondary: Color(0xFF6C83D1),
              onSecondary: Color(0xFF071133),
              tertiary: Color(0xFFC6D2FF),
              onTertiary: Color(0xFF091338),
              surface: Color(0xFF171D2B),
              onSurface: Color(0xFFECEFF8),
              onSurfaceVariant: Color(0xFFAEB6C8),
              surfaceContainer: Color(0xFF21283A),
              surfaceContainerHighest: Color(0xFF2B344A),
              outline: Color(0xFF56627C),
              outlineVariant: Color(0xFF414B63),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF113285),
              onPrimary: Colors.white,
              secondary: Color(0xFF365AA8),
              onSecondary: Colors.white,
              tertiary: Color(0xFFB8C7F5),
              onTertiary: Color(0xFF0B1740),
              surface: Colors.white,
              onSurface: Color(0xFF191B23),
              onSurfaceVariant: Color(0xFF596171),
              surfaceContainer: Color(0xFFF5F7FC),
              surfaceContainerHighest: Color(0xFFE5EAF6),
              outline: Color(0xFFBDC5D6),
              outlineVariant: Color(0xFFDDE2EE),
              scaffoldBackground: Color(0xFFF8FAFE),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.green:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFC3D88A),
              onPrimary: Color(0xFF1D2409),
              secondary: Color(0xFFA2BC67),
              onSecondary: Color(0xFF1A2207),
              tertiary: Color(0xFFE0EBBC),
              onTertiary: Color(0xFF1D2409),
              surface: Color(0xFF202316),
              onSurface: Color(0xFFF0F3E8),
              onSurfaceVariant: Color(0xFFBBC1AA),
              surfaceContainer: Color(0xFF2B301F),
              surfaceContainerHighest: Color(0xFF394027),
              outline: Color(0xFF62694D),
              outlineVariant: Color(0xFF4B5239),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF6F9335),
              onPrimary: Colors.white,
              secondary: Color(0xFF8BAC54),
              onSecondary: Color(0xFF172006),
              tertiary: Color(0xFFD9E8B7),
              onTertiary: Color(0xFF1F2B0A),
              surface: Colors.white,
              onSurface: Color(0xFF1D2118),
              onSurfaceVariant: Color(0xFF646A59),
              surfaceContainer: Color(0xFFF8FAF3),
              surfaceContainerHighest: Color(0xFFEAF0DB),
              outline: Color(0xFFC6CDB5),
              outlineVariant: Color(0xFFE1E7D2),
              scaffoldBackground: Color(0xFFFBFCF7),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.orange:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFFFC85A),
              onPrimary: Color(0xFF311E00),
              secondary: Color(0xFFE1A530),
              onSecondary: Color(0xFF2B1B00),
              tertiary: Color(0xFFFFDF9D),
              onTertiary: Color(0xFF311E00),
              surface: Color(0xFF251E12),
              onSurface: Color(0xFFF7F0E5),
              onSurfaceVariant: Color(0xFFC9B99E),
              surfaceContainer: Color(0xFF332917),
              surfaceContainerHighest: Color(0xFF43361F),
              outline: Color(0xFF76684E),
              outlineVariant: Color(0xFF5E503B),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFFB87900),
              onPrimary: Colors.white,
              secondary: Color(0xFFFFB11B),
              onSecondary: Color(0xFF2A1A00),
              tertiary: Color(0xFFFFDF98),
              onTertiary: Color(0xFF3A2500),
              surface: Colors.white,
              onSurface: Color(0xFF231D14),
              onSurfaceVariant: Color(0xFF746754),
              surfaceContainer: Color(0xFFFCF8EF),
              surfaceContainerHighest: Color(0xFFF4E8CF),
              outline: Color(0xFFD2C5AE),
              outlineVariant: Color(0xFFE9DEC9),
              scaffoldBackground: Color(0xFFFCFAF4),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.slate:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFBCC5CC),
              onPrimary: Color(0xFF161B1F),
              secondary: Color(0xFF9BA5AD),
              onSecondary: Color(0xFF14191D),
              tertiary: Color(0xFFDCE1E5),
              onTertiary: Color(0xFF161B1F),
              surface: Color(0xFF1E2225),
              onSurface: Color(0xFFEFF1F2),
              onSurfaceVariant: Color(0xFFB6BCC0),
              surfaceContainer: Color(0xFF282D31),
              surfaceContainerHighest: Color(0xFF353B40),
              outline: Color(0xFF626A70),
              outlineVariant: Color(0xFF4C545A),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF70777E),
              onPrimary: Colors.white,
              secondary: Color(0xFF91989F),
              onSecondary: Color(0xFF171A1D),
              tertiary: Color(0xFFD8DDE0),
              onTertiary: Color(0xFF22272B),
              surface: Colors.white,
              onSurface: Color(0xFF1F2225),
              onSurfaceVariant: Color(0xFF666D72),
              surfaceContainer: Color(0xFFF7F8F8),
              surfaceContainerHighest: Color(0xFFE9ECEE),
              outline: Color(0xFFC6CBCE),
              outlineVariant: Color(0xFFE0E3E5),
              scaffoldBackground: Color(0xFFFAFAFA),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.teal:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFF8FD4D1),
              onPrimary: Color(0xFF082725),
              secondary: Color(0xFF63B8B5),
              onSecondary: Color(0xFF062421),
              tertiary: Color(0xFFC7EEEA),
              onTertiary: Color(0xFF082725),
              surface: Color(0xFF172523),
              onSurface: Color(0xFFE9F3F2),
              onSurfaceVariant: Color(0xFFA7BDBB),
              surfaceContainer: Color(0xFF213230),
              surfaceContainerHighest: Color(0xFF2C403E),
              outline: Color(0xFF536765),
              outlineVariant: Color(0xFF3E514F),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF268785),
              onPrimary: Colors.white,
              secondary: Color(0xFF529F9D),
              onSecondary: Colors.white,
              tertiary: Color(0xFFC7E8E5),
              onTertiary: Color(0xFF0C3433),
              surface: Colors.white,
              onSurface: Color(0xFF1B2221),
              onSurfaceVariant: Color(0xFF5F6B69),
              surfaceContainer: Color(0xFFF3FAF9),
              surfaceContainerHighest: Color(0xFFE0F1EF),
              outline: Color(0xFFB9CBC9),
              outlineVariant: Color(0xFFD6E6E4),
              scaffoldBackground: Color(0xFFF7FBFB),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.rose:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFFF9AAF),
              onPrimary: Color(0xFF3F0614),
              secondary: Color(0xFFEF6787),
              onSecondary: Color(0xFF390410),
              tertiary: Color(0xFFFFCBD6),
              onTertiary: Color(0xFF3F0614),
              surface: Color(0xFF29181D),
              onSurface: Color(0xFFF9EAEE),
              onSurfaceVariant: Color(0xFFCDAEB7),
              surfaceContainer: Color(0xFF372127),
              surfaceContainerHighest: Color(0xFF492C34),
              outline: Color(0xFF815762),
              outlineVariant: Color(0xFF66414C),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFFCB1B45),
              onPrimary: Colors.white,
              secondary: Color(0xFFE05272),
              onSecondary: Colors.white,
              tertiary: Color(0xFFF4B9C7),
              onTertiary: Color(0xFF4E0A1B),
              surface: Colors.white,
              onSurface: Color(0xFF25191D),
              onSurfaceVariant: Color(0xFF785D65),
              surfaceContainer: Color(0xFFFDF5F7),
              surfaceContainerHighest: Color(0xFFF5DDE4),
              outline: Color(0xFFD9BCC5),
              outlineVariant: Color(0xFFECD6DC),
              scaffoldBackground: Color(0xFFFFF7F9),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.sakura:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFFFB9BD),
              onPrimary: Color(0xFF351315),
              secondary: Color(0xFFE7A3A9),
              onSecondary: Color(0xFF301012),
              tertiary: Color(0xFFFFD7DA),
              onTertiary: Color(0xFF351315),
              surface: Color(0xFF261D21),
              onSurface: Color(0xFFF7ECEF),
              onSurfaceVariant: Color(0xFFCAB6BE),
              surfaceContainer: Color(0xFF33272C),
              surfaceContainerHighest: Color(0xFF43343A),
              outline: Color(0xFF785F68),
              outlineVariant: Color(0xFF5E4850),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFFD98991),
              onPrimary: Colors.white,
              secondary: Color(0xFFF3B6BB),
              onSecondary: Color(0xFF3A1518),
              tertiary: Color(0xFFFEDFE1),
              onTertiary: Color(0xFF3B1719),
              surface: Colors.white,
              onSurface: Color(0xFF241B1D),
              onSurfaceVariant: Color(0xFF746163),
              surfaceContainer: Color(0xFFFFF7F9),
              surfaceContainerHighest: Color(0xFFF7E4EA),
              outline: Color(0xFFD8C0C8),
              outlineVariant: Color(0xFFEBD9DF),
              scaffoldBackground: Color(0xFFFFFAFB),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.fuji:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFC9BFFF),
              onPrimary: Color(0xFF211744),
              secondary: Color(0xFFAFA4EA),
              onSecondary: Color(0xFF1D153D),
              tertiary: Color(0xFFE0D9FF),
              onTertiary: Color(0xFF211744),
              surface: Color(0xFF201D2A),
              onSurface: Color(0xFFF1EEF8),
              onSurfaceVariant: Color(0xFFBDB5CA),
              surfaceContainer: Color(0xFF2B2838),
              surfaceContainerHighest: Color(0xFF39344A),
              outline: Color(0xFF696178),
              outlineVariant: Color(0xFF514A60),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF6D63A8),
              onPrimary: Colors.white,
              secondary: Color(0xFF8B81C3),
              onSecondary: Colors.white,
              tertiary: Color(0xFFD6CFF0),
              onTertiary: Color(0xFF2B244A),
              surface: Colors.white,
              onSurface: Color(0xFF201D25),
              onSurfaceVariant: Color(0xFF686173),
              surfaceContainer: Color(0xFFF8F6FC),
              surfaceContainerHighest: Color(0xFFECE7F6),
              outline: Color(0xFFC8C1D5),
              outlineVariant: Color(0xFFE1DCEB),
              scaffoldBackground: Color(0xFFFBFAFE),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
  }
}

class _ThemePalette {
  const _ThemePalette({
    required this.primary,
    required this.onPrimary,
    required this.secondary,
    required this.onSecondary,
    required this.tertiary,
    required this.onTertiary,
    required this.surface,
    required this.onSurface,
    required this.onSurfaceVariant,
    required this.surfaceContainer,
    required this.surfaceContainerHighest,
    required this.outline,
    required this.outlineVariant,
    required this.scaffoldBackground,
    required this.appBarBackground,
    required this.navigationBackground,
  });

  final Color primary;
  final Color onPrimary;
  final Color secondary;
  final Color onSecondary;
  final Color tertiary;
  final Color onTertiary;
  final Color surface;
  final Color onSurface;
  final Color onSurfaceVariant;
  final Color surfaceContainer;
  final Color surfaceContainerHighest;
  final Color outline;
  final Color outlineVariant;
  final Color scaffoldBackground;
  final Color appBarBackground;
  final Color navigationBackground;
}
