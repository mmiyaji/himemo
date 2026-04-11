import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_flavor/flutter_flavor.dart';

enum AppFlavor {
  development(
    name: 'development',
    displayName: 'HiMemo Dev',
    bannerName: 'DEV',
    bannerColor: Colors.deepOrange,
  ),
  production(
    name: 'production',
    displayName: 'HiMemo',
    bannerName: 'PROD',
    bannerColor: Colors.blueGrey,
  );

  const AppFlavor({
    required this.name,
    required this.displayName,
    required this.bannerName,
    required this.bannerColor,
  });

  final String name;
  final String displayName;
  final String bannerName;
  final Color bannerColor;
}

void configureFlavor(AppFlavor flavor) {
  FlavorConfig(
    name: kDebugMode ? flavor.bannerName : '',
    color: flavor.bannerColor,
    location: BannerLocation.topStart,
    variables: {'flavor': flavor.name, 'displayName': flavor.displayName},
  );
}
