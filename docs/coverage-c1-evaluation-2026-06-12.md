# C1 Coverage Evaluation - 2026-06-12

## Scope

- Target: Flutter/Dart unit tests under `test/`
- Command: `.\.fvm\flutter_sdk\bin\flutter.bat test --concurrency=1 --branch-coverage --coverage-path coverage\lcov_branch.info`
- Result: 216 tests passed
- Raw report: `coverage/lcov_branch.info`
- Branch metric: LCOV `BRDA` entries, counted as covered when `taken > 0`
- Line metric: LCOV `LH / LF`

## Summary

| Set | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All measured files | 2,882 | 8,509 | 33.9% | 10,081 | 26,426 | 38.1% |
| Adjusted | 2,575 | 7,655 | 33.6% | 9,320 | 24,638 | 37.8% |

Adjusted excludes generated localization/model files:

- `*.g.dart`
- `*.freezed.dart`
- `lib/l10n/app_localizations_*.dart`

Compared with the baseline taken before adding focused tests in this change:

- All measured C1: 33.0% -> 33.9% (`+72` covered branches)
- Adjusted C1: 32.8% -> 33.6% (`+67` covered branches)
- Test count: 185 -> 216

## Module Breakdown

### All Measured Files

| Module | Files | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `app` | 11 | 185 | 486 | 38.1% | 664 | 1,503 | 44.2% |
| `features/home/data` | 1 | 8 | 8 | 100.0% | 105 | 105 | 100.0% |
| `features/home/domain` | 5 | 25 | 31 | 80.6% | 120 | 150 | 80.0% |
| `features/home/presentation` | 26 | 1,911 | 6,065 | 31.5% | 7,032 | 20,293 | 34.7% |
| `features/security/data` | 13 | 349 | 764 | 45.7% | 1,164 | 2,114 | 55.1% |
| `features/sync/data` | 10 | 215 | 414 | 51.9% | 689 | 1,202 | 57.3% |
| `features/sync/presentation` | 1 | 1 | 1 | 100.0% | 1 | 1 | 100.0% |
| `l10n` | 8 | 183 | 740 | 24.7% | 269 | 1,058 | 25.4% |

### Adjusted

| Module | Files | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `app` | 10 | 179 | 479 | 37.4% | 654 | 1,490 | 43.9% |
| `features/home/data` | 1 | 8 | 8 | 100.0% | 105 | 105 | 100.0% |
| `features/home/domain` | 3 | 13 | 13 | 100.0% | 29 | 29 | 100.0% |
| `features/home/presentation` | 25 | 1,740 | 5,845 | 29.8% | 6,721 | 19,853 | 33.9% |
| `features/security/data` | 12 | 248 | 413 | 60.0% | 864 | 1,158 | 74.6% |
| `features/sync/data` | 10 | 215 | 414 | 51.9% | 689 | 1,202 | 57.3% |
| `features/sync/presentation` | 1 | 1 | 1 | 100.0% | 1 | 1 | 100.0% |
| `l10n` | 2 | 171 | 482 | 35.5% | 257 | 800 | 32.1% |

## Focused Test Additions

The added tests target pure logic that is directly related to sync safety:

| File | C1 After | Branch covered / branches | C0 After |
| --- | ---: | ---: | ---: |
| `lib/features/sync/data/sync_conflict_policy.dart` | 100.0% | 13 / 13 | 100.0% |
| `lib/features/sync/data/sync_attachment_refs.dart` | 100.0% | 12 / 12 | 100.0% |
| `lib/features/sync/data/sync_bundle_key_service.dart` | 100.0% | 27 / 27 | 98.3% |
| `lib/features/sync/data/sync_bundle_preview.dart` | 96.0% | 24 / 25 | 100.0% |
| `lib/features/home/domain/vault_models.dart` | 100.0% | 2 / 2 | 100.0% |
| `lib/features/home/domain/note_tags.dart` | 100.0% | 6 / 6 | 100.0% |
| `lib/features/security/data/web_attachment_payload_store_stub.dart` | 100.0% | 4 / 4 | 100.0% |
| `lib/app/play_integrity_service.dart` | 100.0% | 10 / 10 | 100.0% |
| `lib/app/diagnostic_log.dart` | 95.2% | 20 / 21 | 98.5% |
| `lib/app/audit_log.dart` | 92.9% | 13 / 14 | 97.5% |

## Lowest C1 Files

Generated files and generated localization files are excluded from this list.

| File | C1 | Branch covered / branches | C0 |
| --- | ---: | ---: | ---: |
| `lib/features/sync/data/google_sign_in_initializer.dart` | 0.0% | 0 / 4 | 0.0% |
| `lib/features/home/presentation/home_sync_support.dart` | 2.8% | 10 / 362 | 2.3% |
| `lib/features/home/presentation/home_media_viewers.dart` | 2.8% | 14 / 500 | 2.3% |
| `lib/features/home/presentation/widget_quick_capture_screen.dart` | 3.2% | 1 / 31 | 0.6% |
| `lib/features/home/presentation/home_google_drive_panel.dart` | 4.0% | 1 / 25 | 1.2% |
| `lib/features/home/presentation/home_note_content.dart` | 6.4% | 53 / 833 | 8.6% |
| `lib/features/home/presentation/home_tags_screen.dart` | 13.3% | 13 / 98 | 24.0% |
| `lib/features/home/presentation/home_settings_screen.dart` | 16.0% | 103 / 643 | 32.8% |

## Evaluation

C1 measurement was executed successfully, but C1 full coverage was not achieved.

Release-relevant backend/state modules have stronger unit coverage than UI-heavy modules:

- `features/home/data`: C1 100.0%
- `features/home/domain`: adjusted C1 100.0%
- `features/security/data`: adjusted C1 60.0%
- `features/sync/data`: adjusted C1 51.9%

The main gaps are UI/presentation-heavy files and platform-specific entry points. These files often require widget tests or E2E tests to exercise branches; their current unit-test C1 values are low and should not be interpreted as exhaustive release proof.

Recommended next coverage work:

1. Add focused widget tests for `home_note_content.dart`, `home_settings_screen.dart`, and `home_sync_support.dart`.
2. Add unit seams around platform services such as Google sign-in initialization, media viewers, and Play Integrity verification.
3. Add C1 thresholds per module only after excluding generated files and explicitly classifying platform stubs.
