import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import 'ad_mob_config.dart';

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
  static Future<AdMobConsentResult>? _currentRequest;

  static Future<AdMobConsentResult> requestIfNeeded() {
    if (!AdMobConfig.canShowAds) {
      return Future.value(
        const AdMobConsentResult(
          canRequestAds: false,
          privacyOptionsRequired: false,
        ),
      );
    }
    _currentRequest ??= _requestConsent().then((result) {
      if (!result.canRequestAds && result.errorMessage != null) {
        _currentRequest = null;
      }
      return result;
    });
    return _currentRequest!;
  }

  static Future<AdMobConsentResult> showPrivacyOptions() async {
    try {
      final current = await requestIfNeeded();
      if (!current.privacyOptionsRequired) {
        return current;
      }

      final formError = await _showPrivacyOptionsForm();
      _currentRequest = null;
      return _readConsentResult(formError);
    } on Object catch (error) {
      return AdMobConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: false,
        errorMessage: error.toString(),
      );
    }
  }

  static Future<AdMobConsentResult> _requestConsent() async {
    FormError? requestError;
    FormError? formError;
    try {
      requestError = await _requestConsentInfoUpdate();
      if (requestError == null) {
        formError = await _loadAndShowConsentFormIfRequired();
      }
      return _readConsentResult(requestError ?? formError);
    } on Object catch (error) {
      return AdMobConsentResult(
        canRequestAds: false,
        privacyOptionsRequired: false,
        errorMessage: error.toString(),
      );
    }
  }

  static Future<FormError?> _requestConsentInfoUpdate() {
    final completer = Completer<FormError?>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(
        tagForUnderAgeOfConsent: false,
        consentDebugSettings: _consentDebugSettings(),
      ),
      () => completer.complete(null),
      completer.complete,
    );
    return completer.future;
  }

  static ConsentDebugSettings? _consentDebugSettings() {
    if (kReleaseMode) {
      return null;
    }

    final testDeviceIds = AdMobConfig.umpDebugTestDeviceIdList;
    if (!AdMobConfig.umpDebugGeographyEea && testDeviceIds == null) {
      return null;
    }

    return ConsentDebugSettings(
      debugGeography: AdMobConfig.umpDebugGeographyEea
          ? DebugGeography.debugGeographyEea
          : null,
      testIdentifiers: testDeviceIds,
    );
  }

  static Future<FormError?> _loadAndShowConsentFormIfRequired() {
    final completer = Completer<FormError?>();
    ConsentForm.loadAndShowConsentFormIfRequired(completer.complete);
    return completer.future;
  }

  static Future<FormError?> _showPrivacyOptionsForm() {
    final completer = Completer<FormError?>();
    ConsentForm.showPrivacyOptionsForm(completer.complete);
    return completer.future;
  }

  static Future<AdMobConsentResult> _readConsentResult(FormError? error) async {
    final canRequestAds = await ConsentInformation.instance.canRequestAds();
    final privacyOptionsRequired =
        await ConsentInformation.instance
            .getPrivacyOptionsRequirementStatus() ==
        PrivacyOptionsRequirementStatus.required;
    return AdMobConsentResult(
      canRequestAds: canRequestAds,
      privacyOptionsRequired: privacyOptionsRequired,
      errorMessage: _errorMessage(error),
    );
  }

  static String? _errorMessage(FormError? error) {
    if (error == null) {
      return null;
    }
    return '${error.errorCode}: ${error.message}';
  }
}
