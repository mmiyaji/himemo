# Release Notes Rule

When `pubspec.yaml` `version:` is changed, update `assets/release_notes/release_notes.json` in the same change.

Rules:
- The release note entry `version` must match the pubspec version name without the build number.
- Example: `version: 1.2.0+47` requires `"version": "1.2.0"` in `release_notes.json`.
- For the first public version, describe it as an initial release.
- For later versions, describe user-visible changes, fixes, or migration notes.

Enforcement:
- `flutter test test\app_test.dart` checks that the current pubspec version has a non-empty release note entry.
