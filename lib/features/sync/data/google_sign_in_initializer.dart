import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'google_drive_sync_transport.dart';

class GoogleSignInInitializer {
  GoogleSignInInitializer._();

  static Future<void>? _initialization;

  static Future<void> ensureInitialized(GoogleDriveAuthConfig config) {
    final existing = _initialization;
    if (existing != null) {
      return existing;
    }

    final clientId =
        config.normalizedClientId ??
        (kIsWeb ? config.normalizedServerClientId : null);
    if (kIsWeb && clientId == null) {
      throw const GoogleDriveAuthConfigurationException(
        'Google Drive sign-in is not configured for this web build. Pass --dart-define-from-file=.env or --dart-define=HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID=... when launching the web app.',
      );
    }

    final initialization = GoogleSignIn.instance.initialize(
      clientId: clientId,
      serverClientId: kIsWeb ? null : config.normalizedServerClientId,
    );
    _initialization = initialization;
    return initialization;
  }
}
