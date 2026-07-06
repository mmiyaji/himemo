import 'package:flutter/foundation.dart';

const _androidTestInlineBannerAdUnitId =
    'ca-app-pub-3940256099942544/9214589741';
const _iosTestInlineBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

abstract final class AdMobConfig {
  static const enabled = bool.fromEnvironment('HIMEMO_ENABLE_ADMOB');
  static const forceTestAds = bool.fromEnvironment(
    'HIMEMO_ADMOB_FORCE_TEST_ADS',
  );

  static const _androidInlineBannerAdUnitId = String.fromEnvironment(
    'HIMEMO_ADMOB_ANDROID_INLINE_BANNER_AD_UNIT_ID',
  );
  static const _iosInlineBannerAdUnitId = String.fromEnvironment(
    'HIMEMO_ADMOB_IOS_INLINE_BANNER_AD_UNIT_ID',
  );

  static bool get canShowAds {
    if (!enabled || kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android || TargetPlatform.iOS => true,
      _ => false,
    };
  }

  static bool get useTestAds => forceTestAds || kDebugMode;

  static String? get inlineBannerAdUnitId {
    if (!canShowAds) {
      return null;
    }
    if (useTestAds) {
      return switch (defaultTargetPlatform) {
        TargetPlatform.android => _androidTestInlineBannerAdUnitId,
        TargetPlatform.iOS => _iosTestInlineBannerAdUnitId,
        _ => null,
      };
    }
    final configuredId = switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidInlineBannerAdUnitId,
      TargetPlatform.iOS => _iosInlineBannerAdUnitId,
      _ => '',
    };
    final trimmedId = configuredId.trim();
    return trimmedId.isEmpty ? null : trimmedId;
  }

  static bool get canShowInlineBanner => inlineBannerAdUnitId != null;
}
