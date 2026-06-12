# C1 Coverage Evaluation - 2026-06-12

## Scope

- Target: Flutter/Dart unit tests under `test/`
- Command: `flutter test --concurrency=1 --branch-coverage --coverage-path coverage\lcov_branch.info`
- Result: 247 tests passed
- Raw report: `coverage/lcov_branch.info`
- Branch metric: LCOV `BRDA` entries, counted as covered when `taken > 0`
- Line metric: LCOV `LH / LF`

## Summary

| Set | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| All measured files | 3,125 | 8,509 | 36.7% | 10,631 | 26,426 | 40.2% |
| Adjusted | 2,813 | 7,655 | 36.7% | 9,869 | 24,638 | 40.1% |

Adjusted excludes generated localization/model files:

- `*.g.dart`
- `*.freezed.dart`
- `lib/l10n/app_localizations_*.dart`

Compared with the baseline taken before adding focused tests in this change:

- All measured C1: 33.0% -> 36.7% (`+315` covered branches)
- Adjusted C1: 32.8% -> 36.7% (`+305` covered branches)
- Test count: 185 -> 247

## Module Breakdown

### All Measured Files

| Module | Files | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `app` | 11 | 184 | 486 | 37.9% | 663 | 1,503 | 44.1% |
| `features/home/data` | 1 | 8 | 8 | 100.0% | 105 | 105 | 100.0% |
| `features/home/domain` | 5 | 30 | 31 | 96.8% | 149 | 150 | 99.3% |
| `features/home/presentation` | 26 | 1,953 | 6,065 | 32.2% | 7,113 | 20,293 | 35.1% |
| `features/security/data` | 13 | 396 | 764 | 51.8% | 1,252 | 2,114 | 59.2% |
| `features/sync/data` | 10 | 281 | 414 | 67.9% | 858 | 1,202 | 71.4% |
| `features/sync/presentation` | 1 | 1 | 1 | 100.0% | 1 | 1 | 100.0% |
| `l10n` | 8 | 272 | 740 | 36.8% | 490 | 1,058 | 46.3% |

### Adjusted

| Module | Files | Branch covered | Branches | C1 | Line covered | Lines | C0 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| `app` | 10 | 178 | 479 | 37.2% | 653 | 1,490 | 43.8% |
| `features/home/data` | 1 | 8 | 8 | 100.0% | 105 | 105 | 100.0% |
| `features/home/domain` | 3 | 13 | 13 | 100.0% | 29 | 29 | 100.0% |
| `features/home/presentation` | 25 | 1,782 | 5,845 | 30.5% | 6,794 | 19,853 | 34.2% |
| `features/security/data` | 12 | 290 | 413 | 70.2% | 951 | 1,158 | 82.1% |
| `features/sync/data` | 10 | 281 | 414 | 67.9% | 858 | 1,202 | 71.4% |
| `features/sync/presentation` | 1 | 1 | 1 | 100.0% | 1 | 1 | 100.0% |
| `l10n` | 2 | 260 | 482 | 53.9% | 478 | 800 | 59.8% |

## Focused Test Additions

The added tests target pure logic that is directly related to sync safety:

| File | C1 After | Branch covered / branches | C0 After |
| --- | ---: | ---: | ---: |
| `lib/features/sync/data/sync_conflict_policy.dart` | 100.0% | 13 / 13 | 100.0% |
| `lib/features/sync/data/sync_attachment_refs.dart` | 100.0% | 12 / 12 | 100.0% |
| `lib/features/sync/data/sync_bundle_key_service.dart` | 100.0% | 27 / 27 | 98.3% |
| `lib/features/sync/data/sync_bundle_preview.dart` | 96.0% | 24 / 25 | 100.0% |
| `lib/features/sync/data/icloud_sync_transport.dart` | 85.1% | 86 / 101 | 85.9% |
| `lib/features/sync/data/secure_sync_bundle_store.dart` | 77.4% | 24 / 31 | 86.8% |
| `lib/features/sync/data/google_drive_sync_transport.dart` | 29.1% | 34 / 117 | 23.1% |
| `lib/l10n/app_strings.dart` | 52.9% | 248 / 469 | 58.8% |
| `lib/features/home/presentation/home_providers.dart` | 50.3% | 1,077 / 2,140 | 56.4% |
| `lib/features/home/domain/vault_models.dart` | 100.0% | 2 / 2 | 100.0% |
| `lib/features/home/domain/note_tags.dart` | 100.0% | 6 / 6 | 100.0% |
| `lib/features/security/data/profile_data_key_service.dart` | 94.1% | 32 / 34 | 100.0% |
| `lib/features/security/data/encrypted_note_database.dart` | 73.3% | 77 / 105 | 86.1% |
| `lib/features/security/data/encrypted_attachment_store.dart` | 56.7% | 85 / 150 | 74.5% |
| `lib/features/security/data/web_attachment_payload_store_stub.dart` | 100.0% | 4 / 4 | 100.0% |
| `lib/features/security/data/private_vault_secret_store.dart` | 100.0% | 9 / 9 | 97.1% |
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
- `features/security/data`: adjusted C1 70.2%
- `features/sync/data`: adjusted C1 67.9%
- `l10n`: adjusted C1 53.9%

The main gaps are UI/presentation-heavy files and platform-specific entry points. These files often require widget tests or E2E tests to exercise branches; their current unit-test C1 values are low and should not be interpreted as exhaustive release proof.

Recommended next coverage work:

1. Add focused widget tests for `home_note_content.dart`, `home_settings_screen.dart`, and `home_sync_support.dart`.
2. Add unit seams around platform services such as Google sign-in initialization, media viewers, and Play Integrity verification.
3. Add C1 thresholds per module only after excluding generated files and explicitly classifying platform stubs.
