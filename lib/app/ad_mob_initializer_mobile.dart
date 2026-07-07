import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../features/ads/data/ad_mob_config.dart';

Future<void>? _adMobInitialization;

Future<void> initializeAdMob() {
  if (!AdMobConfig.canShowAds) {
    return Future<void>.value();
  }
  _adMobInitialization ??= _initializeAdMob();
  return _adMobInitialization!;
}

Future<void> _initializeAdMob() async {
  try {
    await MobileAds.instance.updateRequestConfiguration(
      RequestConfiguration(
        maxAdContentRating: MaxAdContentRating.g,
        testDeviceIds: AdMobConfig.testDeviceIds,
      ),
    );
    await MobileAds.instance.initialize();
  } catch (error, stackTrace) {
    if (kDebugMode) {
      FlutterError.reportError(
        FlutterErrorDetails(
          exception: error,
          stack: stackTrace,
          library: 'ad_mob_initializer',
        ),
      );
    }
  }
}
