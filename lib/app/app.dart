import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_flavor/flutter_flavor.dart';

import 'app_flavor.dart';
import 'app_router.dart';
import '../features/home/presentation/home_providers.dart';

class HiMemoApp extends ConsumerWidget {
  const HiMemoApp({super.key, required this.flavor});

  final AppFlavor flavor;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeControllerProvider);
    final router = ref.watch(appRouterProvider);

    return FlavorBanner(
      child: MaterialApp.router(
        title: flavor.displayName,
        debugShowCheckedModeBanner: false,
        routerConfig: router,
        themeMode: themeMode,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF6B8798),
            brightness: Brightness.light,
          ),
          scaffoldBackgroundColor: const Color(0xFFF7F9FB),
          appBarTheme: const AppBarTheme(
            backgroundColor: Color(0xFFF7F9FB),
            foregroundColor: Color(0xFF24313A),
            elevation: 0,
            centerTitle: false,
          ),
          navigationBarTheme: const NavigationBarThemeData(
            backgroundColor: Colors.white,
            indicatorColor: Color(0xFFEAF0F4),
          ),
          cardColor: Colors.white,
          dividerColor: const Color(0xFFD9E1E7),
          useMaterial3: true,
        ),
        darkTheme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF8CA8B9),
            brightness: Brightness.dark,
          ),
          appBarTheme: const AppBarTheme(elevation: 0, centerTitle: false),
          useMaterial3: true,
        ),
      ),
    );
  }
}
