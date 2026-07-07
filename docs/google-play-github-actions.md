# Google Play GitHub Actions setup

The `Android Google Play` workflow builds a signed production AAB and can upload
it to a Google Play track from `workflow_dispatch`.

## Required Play Console setup

1. Create or choose a Google Cloud service account for publishing.
2. Link the service account in Google Play Console user access.
3. Grant only the target app permissions needed to upload releases.
4. Enable the Google Play Android Developer API for the Cloud project.
5. Complete the app's first Play Console setup manually before using API upload.

## GitHub secrets

Android signing:

- `ANDROID_UPLOAD_KEYSTORE_BASE64`
- `ANDROID_UPLOAD_KEYSTORE_PASSWORD`
- `ANDROID_UPLOAD_KEY_ALIAS`
- `ANDROID_UPLOAD_KEY_PASSWORD`

Build-time configuration:

- `HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID`
- `HIMEMO_FIREBASE_PROJECT_NUMBER`
- `HIMEMO_ENABLE_ADMOB` (optional; set to `true` only when AdMob is ready)
- `HIMEMO_ADMOB_ANDROID_APP_ID` (required when `HIMEMO_ENABLE_ADMOB=true`)
- `HIMEMO_ADMOB_ANDROID_INLINE_BANNER_AD_UNIT_ID` (required when `HIMEMO_ENABLE_ADMOB=true`)
- `HIMEMO_ADMOB_TEST_DEVICE_IDS` (optional comma-separated Google Mobile Ads test device IDs)
- `HIMEMO_UMP_DEBUG_EEA` (optional repository variable; set to `true` only for debug consent-flow checks)
- `HIMEMO_UMP_DEBUG_TEST_DEVICE_IDS` (optional comma-separated UMP debug test device IDs)

Google authentication, preferred:

- `GOOGLE_WORKLOAD_IDENTITY_PROVIDER`
- `GOOGLE_PLAY_SERVICE_ACCOUNT`

Google authentication, fallback:

- `GOOGLE_PLAY_SERVICE_ACCOUNT_JSON`

## Workflow inputs

- `version_code`: optional Android `versionCode`. Defaults to UTC `yyMMddHH`
  to stay below Android's `2100000000` limit.
- `track`: `internal`, `alpha`, `beta`, or `production`.
- `release_status`: `completed`, `draft`, or `inProgress`.
- `upload_to_google_play`: keep `false` for build-only dry runs.
- `google_auth_method`: use `workload_identity` unless a JSON key is required.
- `run_tests`: runs `flutter analyze` and `flutter test test` before build.
