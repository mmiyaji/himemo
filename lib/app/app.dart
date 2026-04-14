import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../features/home/presentation/home_providers.dart';
import '../l10n/app_strings.dart';
import 'app_flavor.dart';
import 'app_router.dart';

class HiMemoApp extends ConsumerWidget {
  const HiMemoApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(appColorThemeControllerProvider);
    final localeSetting = ref.watch(appLocaleControllerProvider);
    final launchSurface = ref.watch(appLaunchControllerProvider);
    final router = ref.watch(appRouterProvider);
    final currentLocation = router.routeInformationProvider.value.uri.path;
    final locale = switch (localeSetting) {
      AppLocaleSetting.system => null,
      AppLocaleSetting.japanese => const Locale('ja'),
      AppLocaleSetting.english => const Locale('en'),
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
        supportedLocales: AppStrings.supportedLocales,
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
  bool _autoPrompted = false;
  bool _updateChecked = false;
  DateTime? _backgroundedAt;

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
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _syncLockState(triggerPrompt: true);
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      if (ref.read(appLockSettingsControllerProvider) &&
          ref.read(appLockRelockDelayControllerProvider) ==
              AppLockRelockDelay.immediate) {
        _lockProtectedSessions();
      }
    }
  }

  Future<void> _syncLockState({required bool triggerPrompt}) async {
    final enabled = ref.read(appLockSettingsControllerProvider);
    if (!enabled) {
      ref.read(appSessionUnlockControllerProvider.notifier).unlock();
      return;
    }

    if (_shouldRelockAfterBackground()) {
      _lockProtectedSessions();
    }

    if (ref.read(appSessionUnlockControllerProvider)) {
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

  void _lockProtectedSessions() {
    ref.read(appSessionUnlockControllerProvider.notifier).lock();
    if (ref.read(privateVaultLockOnAppLockControllerProvider)) {
      ref.read(privateVaultSessionControllerProvider.notifier).lock();
    }
    _autoPrompted = false;
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
    final authState = ref.watch(deviceAuthControllerProvider);
    final pinState = ref.watch(appPinLockControllerProvider);
    final bypassForQuickCapture = widget.currentLocation.startsWith(
      '/widget-capture',
    );

    if (!enabled || unlocked || bypassForQuickCapture) {
      return widget.child ?? const SizedBox.shrink();
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

  final List<
    ({
      String title,
      String body,
      IconData icon,
      String imagePath,
      String imageSemanticLabel,
      bool isSetupPage,
    })
  >
  _pages = const [
    (
      title: 'Capture fast',
      body:
          'The first line becomes the memo title, so quick notes stay lightweight from the first tap.',
      icon: Icons.bolt_rounded,
      imagePath: 'assets/onboarding/capture.png',
      imageSemanticLabel: 'Quick memo capture preview',
      isSetupPage: false,
    ),
    (
      title: 'Separate private access',
      body:
          'Keep app unlock and private-vault unlock separate. Sensitive notes can stay behind their own key.',
      icon: Icons.lock_person_rounded,
      imagePath: 'assets/onboarding/private.png',
      imageSemanticLabel: 'Private vault unlock preview',
      isSetupPage: false,
    ),
    (
      title: 'Prepare sync later',
      body:
          'Choose iCloud or Google Drive as the future sync target without turning your own server into a dependency.',
      icon: Icons.cloud_sync_rounded,
      imagePath: 'assets/onboarding/sync.png',
      imageSemanticLabel: 'Cloud sync target preview',
      isSetupPage: false,
    ),
    (
      title: 'Set initial keys',
      body:
          'Configure the first access keys now, or skip and finish the setup from Settings later.',
      icon: Icons.key_rounded,
      imagePath: 'assets/onboarding/private.png',
      imageSemanticLabel: 'Initial access setup preview',
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
    final colorScheme = Theme.of(context).colorScheme;
    final isLastPage = _pageIndex == _pages.length - 1;
    final pinConfigured = ref.watch(appPinLockControllerProvider).isConfigured;
    final coverConfigured = ref.watch(coverModeSecretControllerProvider);
    final privateConfigured = ref.watch(privateVaultSecretControllerProvider);

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
                      strings.isJapanese ? 'HiMemo へようこそ' : 'Welcome to HiMemo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      strings.isJapanese
                          ? 'メモ庫を開く前に、短い初期設定を行います。'
                          : 'A short setup pass before the memo vault opens.',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 28),
                    Expanded(
                      child: PageView.builder(
                        controller: _pageController,
                        itemCount: _pages.length,
                        onPageChanged: (index) {
                          setState(() {
                            _pageIndex = index;
                          });
                        },
                        itemBuilder: (context, index) {
                          final page = _pages[index];
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
                                            coverConfigured: coverConfigured,
                                            privateConfigured:
                                                privateConfigured,
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
                        for (var i = 0; i < _pages.length; i++)
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
                          child: Text(isLastPage ? strings.finishSetup : strings.next),
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
                                  'Add an onboarding image',
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
    required this.coverConfigured,
    required this.privateConfigured,
  });

  final bool pinConfigured;
  final bool coverConfigured;
  final bool privateConfigured;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _OnboardingSetupPanelBody(
      pinConfigured: pinConfigured,
      coverConfigured: coverConfigured,
      privateConfigured: privateConfigured,
    );
  }
}

class _OnboardingSetupPanelBody extends ConsumerStatefulWidget {
  const _OnboardingSetupPanelBody({
    required this.pinConfigured,
    required this.coverConfigured,
    required this.privateConfigured,
  });

  final bool pinConfigured;
  final bool coverConfigured;
  final bool privateConfigured;

  @override
  ConsumerState<_OnboardingSetupPanelBody> createState() =>
      _OnboardingSetupPanelBodyState();
}

class _OnboardingSetupPanelBodyState
    extends ConsumerState<_OnboardingSetupPanelBody> {
  String? _pinFeedback;
  String? _coverFeedback;
  String? _privateFeedback;

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
              : (strings.isJapanese ? 'アプリ解除' : 'App unlock'),
          subtitle: kIsWeb
              ? (widget.pinConfigured
                    ? (strings.isJapanese
                          ? 'このブラウザに設定済みです。'
                          : 'Configured for this browser.')
                    : (strings.isJapanese
                          ? '起動用の4桁 PIN を設定します。'
                          : 'Set a 4 digit PIN for app launch.'))
              : (strings.isJapanese
                    ? '端末認証は後から設定で有効化できます。'
                    : 'Device authentication can be enabled later in Settings.'),
          actionLabel: kIsWeb
              ? (widget.pinConfigured
                    ? (strings.isJapanese ? 'PIN を変更' : 'Change PIN')
                    : (strings.isJapanese ? 'PIN を設定' : 'Set PIN'))
              : (strings.isJapanese ? 'あとで設定' : 'Later in Settings'),
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
                    _pinFeedback = strings.isJapanese
                        ? 'アプリ解除 PIN を保存しました。'
                        : 'App unlock PIN saved.';
                  });
                }
              : null,
          feedback: _pinFeedback,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-cover-key-button'),
          title: strings.coverKey,
          subtitle: widget.coverConfigured
              ? (strings.isJapanese ? '設定済みです。' : 'Configured.')
              : (strings.isJapanese
                    ? '別の普段使いモードへ切り替えるための任意キーです。'
                    : 'Optional key for the alternate everyday-facing mode.'),
          actionLabel: widget.coverConfigured
              ? (strings.isJapanese ? 'キーを変更' : 'Change key')
              : (strings.isJapanese ? 'キーを設定' : 'Set key'),
          onPressed: () async {
            final secret = await _showOnboardingSecretSetupDialog(
              context,
              title: strings.isJapanese ? 'カバーキーを設定' : 'Set cover key',
              label: strings.coverKey,
              confirmLabel: strings.confirmPrivateKey(strings.coverKey),
            );
            if (secret == null) {
              return;
            }
            await ref
                .read(coverModeSecretControllerProvider.notifier)
                .configure(secret);
            if (!mounted) {
              return;
            }
            setState(() {
              _coverFeedback = strings.isJapanese
                  ? 'カバーキーを保存しました。'
                  : 'Cover key saved.';
            });
          },
          feedback: _coverFeedback,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-private-key-button'),
          title: strings.privateKey,
          subtitle: widget.privateConfigured
              ? (strings.isJapanese ? '設定済みです。' : 'Configured.')
              : (strings.isJapanese
                    ? 'プライベートモードと private vault の解除に使います。'
                    : 'Used to unlock the private memo mode and private vault.'),
          actionLabel: widget.privateConfigured
              ? (strings.isJapanese ? 'キーを変更' : 'Change key')
              : (strings.isJapanese ? 'キーを設定' : 'Set key'),
          onPressed: () async {
            final secret = await _showOnboardingSecretSetupDialog(
              context,
              title: strings.setPrivateKey,
              label: strings.privateKey,
              confirmLabel: strings.confirmPrivateKey(strings.privateKey),
            );
            if (secret == null) {
              return;
            }
            await ref
                .read(privateVaultSecretControllerProvider.notifier)
                .configure(secret);
            ref.read(privateVaultSessionControllerProvider.notifier).lock();
            if (!mounted) {
              return;
            }
            setState(() {
              _privateFeedback = strings.isJapanese
                  ? 'プライベートキーを保存しました。'
                  : 'Private key saved.';
            });
          },
          feedback: _privateFeedback,
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

Future<String?> _showOnboardingSecretSetupDialog(
  BuildContext context, {
  required String title,
  required String label,
  required String confirmLabel,
  bool digitsOnly = false,
  int? exactLength,
}) {
  final strings = context.strings;
  final secretController = TextEditingController();
  final confirmController = TextEditingController();
  String? errorText;

  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: Text(title),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: secretController,
                    obscureText: true,
                    keyboardType: digitsOnly ? TextInputType.number : null,
                    decoration: InputDecoration(
                      labelText: label,
                      border: const OutlineInputBorder(),
                      errorText: errorText,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    keyboardType: digitsOnly ? TextInputType.number : null,
                    decoration: InputDecoration(
                      labelText: confirmLabel,
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(strings.cancel),
              ),
              FilledButton(
                onPressed: () {
                  final secret = secretController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (exactLength != null && secret.length != exactLength) {
                    setState(() {
                      errorText = strings.isJapanese
                          ? '$exactLength 文字ちょうどで入力してください。'
                          : 'Use exactly $exactLength characters.';
                    });
                    return;
                  }
                  if (exactLength == null && secret.length < 4) {
                    setState(() {
                      errorText = strings.useAtLeast4Chars;
                    });
                    return;
                  }
                  if (digitsOnly && !RegExp(r'^\d+$').hasMatch(secret)) {
                    setState(() {
                      errorText = strings.digitsOnly;
                    });
                    return;
                  }
                  if (secret != confirm) {
                    setState(() {
                      errorText = strings.keysDoNotMatch;
                    });
                    return;
                  }
                  Navigator.of(context).pop(secret);
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
              primary: Color(0xFF8FC7FF),
              onPrimary: Color(0xFF0E2236),
              secondary: Color(0xFF5FA4E1),
              onSecondary: Color(0xFF081A2A),
              tertiary: Color(0xFFB7DFFF),
              onTertiary: Color(0xFF0E2236),
              surface: Color(0xFF18222C),
              onSurface: Color(0xFFEAF1F6),
              onSurfaceVariant: Color(0xFFAABACA),
              surfaceContainer: Color(0xFF22303B),
              surfaceContainerHighest: Color(0xFF2D3B47),
              outline: Color(0xFF51616D),
              outlineVariant: Color(0xFF3E4D58),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF005AA3),
              onPrimary: Colors.white,
              secondary: Color(0xFF2E79B8),
              onSecondary: Colors.white,
              tertiary: Color(0xFF8FC7FF),
              onTertiary: Color(0xFF0E2236),
              surface: Colors.white,
              onSurface: Color(0xFF1A1A1A),
              onSurfaceVariant: Color(0xFF556370),
              surfaceContainer: Color(0xFFF4F8FB),
              surfaceContainerHighest: Color(0xFFE4EFF8),
              outline: Color(0xFFB8C7D1),
              outlineVariant: Color(0xFFD8E1E8),
              scaffoldBackground: Color(0xFFF8FBFD),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.green:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFF97D4A4),
              onPrimary: Color(0xFF11261A),
              secondary: Color(0xFF6FB784),
              onSecondary: Color(0xFF102017),
              tertiary: Color(0xFFC7E8CF),
              onTertiary: Color(0xFF11261A),
              surface: Color(0xFF18231C),
              onSurface: Color(0xFFEAF2EC),
              onSurfaceVariant: Color(0xFFAABCAF),
              surfaceContainer: Color(0xFF223128),
              surfaceContainerHighest: Color(0xFF2D3F33),
              outline: Color(0xFF53655A),
              outlineVariant: Color(0xFF3E5145),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF2F6B3C),
              onPrimary: Colors.white,
              secondary: Color(0xFF5A8B66),
              onSecondary: Colors.white,
              tertiary: Color(0xFFB2D8BA),
              onTertiary: Color(0xFF14301C),
              surface: Colors.white,
              onSurface: Color(0xFF1B1E1C),
              onSurfaceVariant: Color(0xFF5D665F),
              surfaceContainer: Color(0xFFF4F8F4),
              surfaceContainerHighest: Color(0xFFE4EEE5),
              outline: Color(0xFFBBC8BC),
              outlineVariant: Color(0xFFDCE5DC),
              scaffoldBackground: Color(0xFFF8FBF7),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.orange:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFFFB77A),
              onPrimary: Color(0xFF331700),
              secondary: Color(0xFFE49354),
              onSecondary: Color(0xFF2F1804),
              tertiary: Color(0xFFFFD9B8),
              onTertiary: Color(0xFF331700),
              surface: Color(0xFF251C15),
              onSurface: Color(0xFFF5EEE8),
              onSurfaceVariant: Color(0xFFC9B5A2),
              surfaceContainer: Color(0xFF33271E),
              surfaceContainerHighest: Color(0xFF433329),
              outline: Color(0xFF766253),
              outlineVariant: Color(0xFF5E4B3F),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF9A4E00),
              onPrimary: Colors.white,
              secondary: Color(0xFFBE742A),
              onSecondary: Colors.white,
              tertiary: Color(0xFFF0C9A4),
              onTertiary: Color(0xFF412000),
              surface: Colors.white,
              onSurface: Color(0xFF231B17),
              onSurfaceVariant: Color(0xFF736359),
              surfaceContainer: Color(0xFFFBF5EF),
              surfaceContainerHighest: Color(0xFFF1E5D9),
              outline: Color(0xFFD1C2B5),
              outlineVariant: Color(0xFFE7DDD4),
              scaffoldBackground: Color(0xFFFCF8F3),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.slate:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFFB3C3D6),
              onPrimary: Color(0xFF17212B),
              secondary: Color(0xFF90A6BE),
              onSecondary: Color(0xFF16212A),
              tertiary: Color(0xFFD5E0EB),
              onTertiary: Color(0xFF17212B),
              surface: Color(0xFF1C242C),
              onSurface: Color(0xFFEAF0F5),
              onSurfaceVariant: Color(0xFFADB8C2),
              surfaceContainer: Color(0xFF25303A),
              surfaceContainerHighest: Color(0xFF313E49),
              outline: Color(0xFF5B6977),
              outlineVariant: Color(0xFF46525E),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF445A72),
              onPrimary: Colors.white,
              secondary: Color(0xFF6B7F95),
              onSecondary: Colors.white,
              tertiary: Color(0xFFD3DCE6),
              onTertiary: Color(0xFF243240),
              surface: Colors.white,
              onSurface: Color(0xFF1E2327),
              onSurfaceVariant: Color(0xFF63707B),
              surfaceContainer: Color(0xFFF4F7FA),
              surfaceContainerHighest: Color(0xFFE7EDF2),
              outline: Color(0xFFC2CCD5),
              outlineVariant: Color(0xFFDCE3E9),
              scaffoldBackground: Color(0xFFF8FAFC),
              appBarBackground: Colors.white,
              navigationBackground: Colors.white,
            );
    case AppColorTheme.teal:
      return isDark
          ? const _ThemePalette(
              primary: Color(0xFF86D7D0),
              onPrimary: Color(0xFF0C2A28),
              secondary: Color(0xFF5DBBB2),
              onSecondary: Color(0xFF0A2422),
              tertiary: Color(0xFFC5EEE8),
              onTertiary: Color(0xFF0C2A28),
              surface: Color(0xFF182523),
              onSurface: Color(0xFFE9F3F2),
              onSurfaceVariant: Color(0xFFA7BDBC),
              surfaceContainer: Color(0xFF223230),
              surfaceContainerHighest: Color(0xFF2D413E),
              outline: Color(0xFF536764),
              outlineVariant: Color(0xFF3E514E),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF0E6F6A),
              onPrimary: Colors.white,
              secondary: Color(0xFF3D8F8A),
              onSecondary: Colors.white,
              tertiary: Color(0xFFBDE7E2),
              onTertiary: Color(0xFF0B3532),
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
              primary: Color(0xFFFFB8C8),
              onPrimary: Color(0xFF351722),
              secondary: Color(0xFFE594AA),
              onSecondary: Color(0xFF31131E),
              tertiary: Color(0xFFFFD7E1),
              onTertiary: Color(0xFF351722),
              surface: Color(0xFF261C20),
              onSurface: Color(0xFFF6ECEF),
              onSurfaceVariant: Color(0xFFC9B3BA),
              surfaceContainer: Color(0xFF33262B),
              surfaceContainerHighest: Color(0xFF433238),
              outline: Color(0xFF775E66),
              outlineVariant: Color(0xFF5D474F),
              scaffoldBackground: Color(0xFF272C32),
              appBarBackground: Color(0xFF272C32),
              navigationBackground: Color(0xFF272C32),
            )
          : const _ThemePalette(
              primary: Color(0xFF9A4860),
              onPrimary: Colors.white,
              secondary: Color(0xFFBC6F86),
              onSecondary: Colors.white,
              tertiary: Color(0xFFF3CDD8),
              onTertiary: Color(0xFF44202B),
              surface: Colors.white,
              onSurface: Color(0xFF241B1F),
              onSurfaceVariant: Color(0xFF746168),
              surfaceContainer: Color(0xFFFCF6F8),
              surfaceContainerHighest: Color(0xFFF2E3E8),
              outline: Color(0xFFD4C2C8),
              outlineVariant: Color(0xFFE8DADF),
              scaffoldBackground: Color(0xFFFCF8F9),
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
