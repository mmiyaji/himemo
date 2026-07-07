class AdMobConsentResult {
  const AdMobConsentResult({
    required this.canRequestAds,
    required this.privacyOptionsRequired,
    this.errorMessage,
  });

  final bool canRequestAds;
  final bool privacyOptionsRequired;
  final String? errorMessage;
}

abstract final class AdMobConsent {
  static Future<AdMobConsentResult> requestIfNeeded() {
    return Future.value(
      const AdMobConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: false,
      ),
    );
  }

  static Future<AdMobConsentResult> showPrivacyOptions() => requestIfNeeded();
}
