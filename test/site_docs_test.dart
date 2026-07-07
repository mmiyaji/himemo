import 'dart:io';

import 'package:test/test.dart';

void main() {
  test('Cloudflare Pages site has required entry points', () {
    final requiredFiles = <String>[
      'docs/index.html',
      'docs/privacy/index.html',
      'docs/terms/index.html',
      'docs/app-ads.txt',
      'docs/_headers',
      'docs/_redirects',
      'docs/assets/vendor/glightbox/glightbox.min.css',
      'docs/assets/vendor/glightbox/glightbox.min.js',
      'docs/assets/vendor/glightbox/LICENSE.md',
      '.github/workflows/cloudflare-pages.yml',
    ];

    for (final path in requiredFiles) {
      expect(File(path).existsSync(), isTrue, reason: '$path should exist');
    }
  });

  test('site supports Japanese and English legal pages', () {
    final privacy = File('docs/privacy/index.html').readAsStringSync();
    final terms = File('docs/terms/index.html').readAsStringSync();

    expect(privacy, contains('data-lang-panel="ja"'));
    expect(privacy, contains('data-lang-panel="en"'));
    expect(privacy, contains('Google AdMob'));
    expect(privacy, contains('https://policies.google.com/technologies/ads'));
    expect(privacy, contains('https://adssettings.google.com/'));
    expect(terms, contains('data-lang-panel="ja"'));
    expect(terms, contains('data-lang-panel="en"'));
    expect(terms, contains('Google AdMob'));
    expect(
      terms,
      contains('advertisements in builds where advertising is enabled'),
    );
  });

  test('landing page uses screenshots and language-aware media', () {
    final index = File('docs/index.html').readAsStringSync();
    final script = File('docs/assets/site.js').readAsStringSync();

    expect(index, contains('screenshot-iphone-notes-ja.png'));
    expect(index, contains('screenshot-iphone-notes-en.png'));
    expect(index, contains('screenshot-iphone-private-ja.png'));
    expect(index, contains('screenshot-iphone-insights-en.png'));
    expect(index, contains('assets/vendor/glightbox/glightbox.min.css'));
    expect(index, contains('assets/vendor/glightbox/glightbox.min.js'));
    expect(index, contains('class="glightbox"'));
    expect(index, contains('data-gallery="himemo-screens"'));
    expect(index, contains('data-media-ja'));
    expect(index, contains('data-media-en'));
    expect(script, contains("const storageKey = 'himemo-site-language'"));
    expect(script, contains('GLightbox'));
    expect(script, contains('data-lightbox-title-ja'));
    expect(script, contains('data-lang-choice'));
  });

  test('legacy legal URLs redirect to canonical routes', () {
    final redirects = File('docs/_redirects').readAsStringSync();

    expect(redirects, contains('/privacy-ja.html /privacy/?lang=ja 301'));
    expect(redirects, contains('/privacy-en.html /privacy/?lang=en 301'));
    expect(redirects, contains('/terms-ja.html /terms/?lang=ja 301'));
    expect(redirects, contains('/terms-en.html /terms/?lang=en 301'));
  });
}
