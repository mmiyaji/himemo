import 'package:flutter/foundation.dart';

const _androidTestInlineBannerAdUnitId =
    'ca-app-pub-3940256099942544/9214589741';
const _iosTestInlineBannerAdUnitId = 'ca-app-pub-3940256099942544/2934735716';

abstract final class AdMobConfig {
  static const enabled = bool.fromEnvironment('HIMEMO_ENABLE_ADMOB');
  static const forceTestAds = bool.fromEnvironment(
    'HIMEMO_ADMOB_FORCE_TEST_ADS',
  );

  static const _androidAppId = String.fromEnvironment(
    'HIMEMO_ADMOB_ANDROID_APP_ID',
  );
  static const _iosAppId = String.fromEnvironment('HIMEMO_ADMOB_IOS_APP_ID');
  static const _androidInlineBannerAdUnitId = String.fromEnvironment(
    'HIMEMO_ADMOB_ANDROID_INLINE_BANNER_AD_UNIT_ID',
  );
  static const _iosInlineBannerAdUnitId = String.fromEnvironment(
    'HIMEMO_ADMOB_IOS_INLINE_BANNER_AD_UNIT_ID',
  );
  static const _testDeviceIds = String.fromEnvironment(
    'HIMEMO_ADMOB_TEST_DEVICE_IDS',
  );
  static const umpDebugGeographyEea = bool.fromEnvironment(
    'HIMEMO_UMP_DEBUG_EEA',
  );
  static const umpDebugTestDeviceIds = String.fromEnvironment(
    'HIMEMO_UMP_DEBUG_TEST_DEVICE_IDS',
  );

  static bool get canShowAds {
    if (!enabled || kIsWeb) {
      return false;
    }
    return switch (defaultTargetPlatform) {
      TargetPlatform.android => _androidNativeAppId.trim().isNotEmpty,
      TargetPlatform.iOS => _iosNativeAppId.trim().isNotEmpty,
      _ => false,
    };
  }

  static bool get useTestAds => forceTestAds || kDebugMode;

  static String get _androidNativeAppId => _androidAppId;

  static String get _iosNativeAppId => _iosAppId;

  static List<String>? get testDeviceIds {
    final ids = _testDeviceIds
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ids.isEmpty ? null : ids;
  }

  static List<String>? get umpDebugTestDeviceIdList {
    final ids = umpDebugTestDeviceIds
        .split(',')
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toList(growable: false);
    return ids.isEmpty ? null : ids;
  }

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
