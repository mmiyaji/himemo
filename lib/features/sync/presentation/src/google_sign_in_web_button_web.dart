import 'package:flutter/widgets.dart';
import 'package:google_sign_in_web/web_only.dart' as web;

Widget buildGoogleSignInWebButton({String? locale}) {
  return web.renderButton(
    configuration: web.GSIButtonConfiguration(
      type: web.GSIButtonType.standard,
      theme: web.GSIButtonTheme.outline,
      size: web.GSIButtonSize.large,
      text: web.GSIButtonText.signinWith,
      shape: web.GSIButtonShape.pill,
      minimumWidth: 240,
      locale: locale,
    ),
  );
}
