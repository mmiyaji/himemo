// Standalone CloudKit read-only probe. The application also exposes this screen on Web.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_web_screen.dart';
import 'package:himemo/l10n/app_strings.dart';

void main() => runApp(
  MaterialApp(
    title: 'HiMemo CloudKit 読み取り確認',
    locale: const Locale('ja'),
    supportedLocales: const [Locale('ja'), Locale('en')],
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorSchemeSeed: const Color(0xffbd4963),
      useMaterial3: true,
    ),
    home: const SyncV2CloudKitReadOnlyScreen(),
  ),
);
