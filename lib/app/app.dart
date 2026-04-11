import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';
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
    final router = ref.watch(appRouterProvider);

    return FlavorBanner(
      child: MaterialApp.router(
        title: flavor.displayName,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: themeMode,
        theme: _buildTheme(Brightness.light, colorTheme),
        darkTheme: _buildTheme(Brightness.dark, colorTheme),
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
              scaffoldBackground: Color(0xFF10181F),
              appBarBackground: Color(0xFF10181F),
              navigationBackground: Color(0xFF162029),
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
              scaffoldBackground: Color(0xFF101813),
              appBarBackground: Color(0xFF101813),
              navigationBackground: Color(0xFF16211A),
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
              scaffoldBackground: Color(0xFF17110D),
              appBarBackground: Color(0xFF17110D),
              navigationBackground: Color(0xFF211812),
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
