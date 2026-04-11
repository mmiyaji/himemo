import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_native_splash/flutter_native_splash.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    if (kIsWeb ||
        _removedNativeSplash ||
        widget.launchSurface == AppLaunchSurface.splash) {
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
      case AppLaunchSurface.splash:
        return _SplashScreen(flavor: widget.flavor);
      case AppLaunchSurface.onboarding:
        return _OnboardingScreen(flavor: widget.flavor);
      case AppLaunchSurface.ready:
        return widget.child ?? const SizedBox.shrink();
    }
  }
}

class _SplashScreen extends StatelessWidget {
  const _SplashScreen({required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surface,
              colorScheme.surfaceContainerHighest,
              colorScheme.primary.withValues(alpha: 0.16),
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 82,
                height: 82,
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.24),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.note_alt_rounded,
                  size: 38,
                  color: colorScheme.onPrimary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                flavor.displayName,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                'Preparing your memo vault...',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
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

  final List<({
    String title,
    String body,
    IconData icon,
    String imagePath,
    String imageSemanticLabel,
  })> _pages = const [
    (
      title: 'Capture fast',
      body:
          'The first line becomes the memo title, so quick notes stay lightweight from the first tap.',
      icon: Icons.bolt_rounded,
      imagePath: 'assets/onboarding/capture.png',
      imageSemanticLabel: 'Quick memo capture preview',
    ),
    (
      title: 'Separate private access',
      body:
          'Keep app unlock and private-vault unlock separate. Sensitive notes can stay behind their own key.',
      icon: Icons.lock_person_rounded,
      imagePath: 'assets/onboarding/private.png',
      imageSemanticLabel: 'Private vault unlock preview',
    ),
    (
      title: 'Prepare sync later',
      body:
          'Choose iCloud or Google Drive as the future sync target without turning your own server into a dependency.',
      icon: Icons.cloud_sync_rounded,
      imagePath: 'assets/onboarding/sync.png',
      imageSemanticLabel: 'Cloud sync target preview',
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

    return Scaffold(
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
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    width: 56,
                                    height: 56,
                                    decoration: BoxDecoration(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.12,
                                      ),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(
                                      page.icon,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  _OnboardingImageCard(
                                    imagePath: page.imagePath,
                                    semanticLabel: page.imageSemanticLabel,
                                    fallbackIcon: page.icon,
                                  ),
                                  const SizedBox(height: 24),
                                  Text(
                                    page.title,
                                    style: Theme.of(context).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    page.body,
                                    style: Theme.of(context).textTheme.bodyLarge,
                                  ),
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
                    child: Text(isLastPage ? 'Start' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
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
      .apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
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
