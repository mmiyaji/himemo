import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/ads/data/ad_mob_config.dart';

void main() {
  test('AdMob stays disabled unless the build explicitly enables it', () {
    expect(AdMobConfig.enabled, isFalse);
    expect(AdMobConfig.canShowAds, isFalse);
    expect(AdMobConfig.canShowInlineBanner, isFalse);
    expect(AdMobConfig.inlineBannerAdUnitId, isNull);
  });
}
