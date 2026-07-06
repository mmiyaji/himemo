import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../features/ads/data/ad_mob_config.dart';

Future<void> initializeAdMob() async {
  if (!AdMobConfig.canShowAds) {
    return;
  }
  try {
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
