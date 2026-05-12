import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('web video playback stays enabled through the native video element', () {
    final webVideoElement = File(
      'lib/features/home/presentation/web_video_element_view_web.dart',
    ).readAsStringSync();
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(webVideoElement, contains('html.VideoElement'));
    expect(webVideoElement, contains('..controls = true'));
    expect(webVideoElement, contains('..muted = muted'));
    expect(webVideoElement, contains('HtmlElementView'));
    expect(
      homePage,
      isNot(
        contains('VideoPlayerController.networkUrl(Uri.parse(webObjectUrl))'),
      ),
    );
  });

  test(
    'UI behavior guardrails cover repeated mobile and media regressions',
    () {
      final guardrails = File(
        'docs/ui-behavior-guardrails.md',
      ).readAsStringSync();

      expect(
        guardrails,
        contains('Do not disable video thumbnail generation on Web'),
      );
      expect(guardrails, contains('Videos must remain playable on Web'));
      expect(guardrails, contains('full-screen modal sheet'));
      expect(guardrails, contains('app header behind it'));
      expect(guardrails, contains('Automated checks should cover these rules'));
    },
  );

  test('rich editor restores a text block after trailing attachments', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();

    expect(homePage, contains('void _ensureTrailingRichParagraph'));
    expect(homePage, contains('_ensureTrailingRichParagraph(drafts);'));
    expect(homePage, contains('_ensureTrailingRichParagraph(_richBlocks);'));
  });

  test('app lock background privacy cover prevents delayed relock flashes', () {
    final appShell = File('lib/app/app.dart').readAsStringSync();

    expect(appShell, contains('_activateAppLockPrivacyCoverIfEnabled'));
    expect(appShell, contains('_lifecyclePrivacyCoverVisible'));
    expect(appShell, contains('_AppPrivacyCover'));
    expect(
      appShell,
      contains('privacyScreenActive || _lifecyclePrivacyProtectionEnabled'),
    );
  });

  test('diagnostic mode exposes iCloud storage maintenance actions', () {
    final homePage = File(
      'lib/features/home/presentation/home_page.dart',
    ).readAsStringSync();
    final iCloudTransport = File(
      'lib/features/sync/data/icloud_sync_transport.dart',
    ).readAsStringSync();

    expect(homePage, contains('diagnosticICloudStorageBreakdownKey'));
    expect(homePage, contains('diagnosticICloudPruneBundlesKey'));
    expect(iCloudTransport, contains('fetchStorageBreakdown'));
    expect(iCloudTransport, contains('pruneOldBundles'));
  });
}
