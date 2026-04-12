import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pinput/pinput.dart';

import '../features/home/presentation/home_providers.dart';
import 'app_flavor.dart';
import 'app_router.dart';

class HiMemoApp extends ConsumerWidget {
  const HiMemoApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final colorTheme = ref.watch(appColorThemeControllerProvider);
    final launchSurface = ref.watch(appLaunchControllerProvider);
    final router = ref.watch(appRouterProvider);

    return FlavorBanner(
      child: MaterialApp.router(
        title: flavor.displayName,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: themeMode,
        theme: _buildTheme(Brightness.light, colorTheme),
        darkTheme: _buildTheme(Brightness.dark, colorTheme),
        builder: (context, child) {
          return _LaunchSurfaceGate(
            flavor: flavor,
            launchSurface: launchSurface,
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
    required this.child,
  });

  final AppFlavor flavor;
  final AppLaunchSurface launchSurface;
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
        return _AppLockGate(child: widget.child);
    }
  }
}

class _AppLockGate extends ConsumerStatefulWidget {
  const _AppLockGate({required this.child});

  final Widget? child;

  @override
  ConsumerState<_AppLockGate> createState() => _AppLockGateState();
}

class _AppLockGateState extends ConsumerState<_AppLockGate>
    with WidgetsBindingObserver {
  bool _autoPrompted = false;
  DateTime? _backgroundedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncLockState(triggerPrompt: true);
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

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(appLockSettingsControllerProvider);
    final unlocked = ref.watch(appSessionUnlockControllerProvider);
    final authState = ref.watch(deviceAuthControllerProvider);
    final pinState = ref.watch(appPinLockControllerProvider);

    if (!enabled || unlocked) {
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
                          'Unlock HiMemo',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          kIsWeb
                              ? 'This browser session is protected with a web PIN.'
                              : 'Resume this session with device authentication.',
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                        ),
                        const SizedBox(height: 24),
                        if (wide)
                          Text(
                            'Private vault access and sync state remain locked until the session is restored.',
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
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
                              style: Theme.of(context)
                                  .textTheme
                                  .bodyMedium
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
                                          deviceAuthControllerProvider.notifier)
                                      .authenticate(
                                        reason:
                                            'Unlock HiMemo with device authentication',
                                      );
                                },
                                icon: const Icon(Icons.lock_open_rounded),
                                label: const Text('Authenticate'),
                              ),
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: () async {
                                await ref
                                    .read(appLockSettingsControllerProvider
                                        .notifier)
                                    .setEnabled(false);
                                ref
                                    .read(appSessionUnlockControllerProvider
                                        .notifier)
                                    .unlock();
                              },
                              child: const Text('Disable app unlock for now'),
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
          label: const Text('Unlock with PIN'),
        ),
        if (pinState.lastError != null) ...[
          const SizedBox(height: 12),
          Text(
            pinState.lastError!,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.error,
                ),
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
    final matched =
        await ref.read(appPinLockControllerProvider.notifier).verify(
              pin,
            );
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
      })> _pages = const [
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
                          child: const Text('Skip'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 28),
                    Text(
                      'Welcome to HiMemo',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'A short setup pass before the memo vault opens.',
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
                                      minHeight: constraints.maxHeight - 48,
                                    ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Container(
                                          width: 56,
                                          height: 56,
                                          decoration: BoxDecoration(
                                            color:
                                                colorScheme.primary.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius:
                                                BorderRadius.circular(18),
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
                                          style: Theme.of(context)
                                              .textTheme
                                              .titleLarge,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          page.body,
                                          style: Theme.of(context)
                                              .textTheme
                                              .bodyLarge,
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
                          child: Text(isLastPage ? 'Finish setup' : 'Next'),
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-pin-button'),
          title: kIsWeb ? 'App unlock PIN' : 'App unlock',
          subtitle: kIsWeb
              ? (widget.pinConfigured
                  ? 'Configured for this browser.'
                  : 'Set a 4 digit PIN for app launch.')
              : 'Device authentication can be enabled later in Settings.',
          actionLabel: kIsWeb
              ? (widget.pinConfigured ? 'Change PIN' : 'Set PIN')
              : 'Later in Settings',
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
                    _pinFeedback = 'App unlock PIN saved.';
                  });
                }
              : null,
          feedback: _pinFeedback,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-cover-key-button'),
          title: 'Cover mode key',
          subtitle: widget.coverConfigured
              ? 'Configured.'
              : 'Optional key for the alternate everyday-facing mode.',
          actionLabel: widget.coverConfigured ? 'Change key' : 'Set key',
          onPressed: () async {
            final secret = await _showOnboardingSecretSetupDialog(
              context,
              title: 'Set cover key',
              label: 'Cover key',
              confirmLabel: 'Confirm cover key',
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
              _coverFeedback = 'Cover key saved.';
            });
          },
          feedback: _coverFeedback,
        ),
        const SizedBox(height: 12),
        _OnboardingSetupTile(
          tileKey: const Key('onboarding-set-private-key-button'),
          title: 'Private mode key',
          subtitle: widget.privateConfigured
              ? 'Configured.'
              : 'Used to unlock the private memo mode and private vault.',
          actionLabel: widget.privateConfigured ? 'Change key' : 'Set key',
          onPressed: () async {
            final secret = await _showOnboardingSecretSetupDialog(
              context,
              title: 'Set private key',
              label: 'Private key',
              confirmLabel: 'Confirm private key',
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
              _privateFeedback = 'Private key saved.';
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
  final controller = TextEditingController();
  String? errorText;
  return showDialog<String>(
    context: context,
    useRootNavigator: true,
    builder: (context) {
      return StatefulBuilder(
        builder: (context, setState) {
          return AlertDialog(
            title: const Text('Set app unlock PIN'),
            content: SizedBox(
              width: 320,
              child: TextField(
                controller: controller,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'PIN',
                  border: const OutlineInputBorder(),
                  errorText: errorText,
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final pin = controller.text.trim();
                  if (pin.length != 4) {
                    setState(() {
                      errorText = 'Use exactly 4 digits.';
                    });
                    return;
                  }
                  if (!RegExp(r'^\d+$').hasMatch(pin)) {
                    setState(() {
                      errorText = 'Digits only.';
                    });
                    return;
                  }
                  Navigator.of(context).pop(pin);
                },
                child: const Text('Save'),
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
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final secret = secretController.text.trim();
                  final confirm = confirmController.text.trim();
                  if (exactLength != null && secret.length != exactLength) {
                    setState(() {
                      errorText = 'Use exactly $exactLength characters.';
                    });
                    return;
                  }
                  if (exactLength == null && secret.length < 4) {
                    setState(() {
                      errorText = 'Use at least 4 characters.';
                    });
                    return;
                  }
                  if (digitsOnly && !RegExp(r'^\d+$').hasMatch(secret)) {
                    setState(() {
                      errorText = 'Digits only.';
                    });
                    return;
                  }
                  if (secret != confirm) {
                    setState(() {
                      errorText = 'Values do not match.';
                    });
                    return;
                  }
                  Navigator.of(context).pop(secret);
                },
                child: const Text('Save'),
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
  final scheme = ColorScheme.fromSeed(
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
  final textTheme = (brightness == Brightness.dark
          ? baseTypography.white
          : baseTypography.black)
      .apply(bodyColor: scheme.onSurface, displayColor: scheme.onSurface);

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
