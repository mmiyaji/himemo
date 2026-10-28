# GitHub Actions iOS TestFlight Guide

HiMemo の iOS production IPA を GitHub Actions でもビルドし、App Store Connect/TestFlight へアップロードするための設定メモ。
Codemagic の `ios-testflight-production` と並行運用する前提。

関連ファイル:
- [codemagic.yaml](/C:/Users/mail/Documents/git/himemo/codemagic.yaml)
- [.github/workflows/ios-testflight.yml](/C:/Users/mail/Documents/git/himemo/.github/workflows/ios-testflight.yml)

## Workflow

Workflow 名:
- `iOS TestFlight`

起動方法:
- GitHub Actions UI から `workflow_dispatch` で手動実行
- `upload_to_testflight=false` にすると、署名済み IPA artifact の生成までで止められる
- `build_number` 未指定時は UTC の `yyMMddHHmm` を使う

The workflow uses the `xcode-27` Apple Silicon runner and explicitly selects Xcode 27.1. `tools/check_ios_toolchain.py` rejects Xcode or the iPhoneOS SDK older than 27.1 before signing. Flutter is pinned to 3.47.8 in local and CI configuration.

## iPhone Duo release preparation (2026-10-28)

Apple's [preparation guide](https://developer.apple.com/iphone-duo/prepare/) requires testing dynamic window resizing; Xcode 27.1 / iOS 27.1 SDK enables the full-display experience. The existing Runner supports iPhone and iPad, portrait and landscape, and does not require full-screen mode. Flutter layouts use available window dimensions. A widget regression in `test/ui_accessibility_regression_test.dart` exercises repeated compact, wide and landscape transitions without restarting Settings. This is a layout stress test, not native device certification.

Before uploading this candidate:

1. Run the workflow with `upload_to_testflight=false` against the branch containing these changes. Verify the SDK check, validation, signed IPA, entitlements and extension version checks.
2. On Xcode 27.1, run the iPhone Duo simulator or Device Hub. Fold/unfold and rotate while editing an unsaved note, typing with the keyboard open, viewing attachments, opening Settings, unlocking a private profile and syncing. Confirm content stays inside safe areas and drafts, selection and scroll state survive resizing.
3. Install the signed candidate on a registered device through the internal Codemagic workflow where available. Verify camera, microphone, Touch ID / biometric unlock, share extension, widget, iCloud and Google sign-in. Widget tests on Windows cannot verify these native behaviors.
4. Run with `upload_to_testflight=true`, then confirm App Store Connect processing, export compliance and tester group availability. Record the actual marketing version and generated build number from that run. External testing may require Beta App Review.

Required signing and App Store Connect secrets below must be present in the CI provider. Preparing these files on Windows does not produce an IPA or upload a build. Existing CI credentials have not been verified by this local change.

TestFlight「テスト内容」用の確認項目:

- 外側／内側画面の切り替え、縦横回転で表示が欠けず、編集中のメモが維持されること。
- キーボード表示中の保存、写真・動画・音声添付、ZIPバックアップの書き出し／復元。
- 生体認証とプライベートプロファイルのロック、共有拡張、ウィジェットからのメモ作成。
- iCloud / Google Drive の認証と同期。更新前のメモと添付ファイルが開けること。

Dependency exception: `record` remains on 6.x and `record_web` on 1.x to preserve the Android background recording service; record 7 removes that service and needs a separate foreground-service migration. Other Flutter dependencies use the newest jointly resolvable versions. Newer `build_runner`, `freezed` and `test` releases remain constrained by the selected SDK / generator dependency graph; do not override transitive analyzer or test packages to force them.

Release build fixes: Functions and CI use Node.js 22, as required by Firebase Admin 14 / Firestore 9; Firestore is an explicit dependency so installation failures are not silently treated as optional. The project retains CocoaPods through `flutter.config.enable-swift-package-manager: false` in `pubspec.yaml`. Firebase iOS 13.1.1 conflicts with GoogleSignIn 9.x: SwiftPM requests disjoint GTMSessionFetcher ranges, and CocoaPods requests AppCheckCore 12 versus 11. The mobile app therefore uses the newest Firebase 12-based FlutterFire family (firebase_core 4.x, crashlytics 5.x, performance 0.11.x, app_check 0.4.x). Firebase is an additional dependency exception until Google Sign-In's native constraints become compatible. The server-side Firebase Admin package remains on 14.x with Node.js 22.

Local validation on 2026-10-28: Flutter analysis with `--fatal-infos` and formatting passed; all 373 Flutter tests passed, including the resize regression. Web build passed. The two selected Playwright onboarding / mobile note-and-archive scenarios passed after aligning the existing onboarding helper with the five-page UI and its current labels. Functions lint and all 11 tests passed. Both npm dependency trees reported zero known audit vulnerabilities after lockfile updates; the root package overrides serve's compression dependency to patched 1.8.2. The toolchain guard was checked with mocked 27.1 and older version output. macOS archive, signing, native simulator/device checks and TestFlight upload remain unverified.

2026-10-28 release execution: [GitHub Actions run 40706424640](https://github.com/mmiyaji/himemo/actions/runs/40706424640) succeeded for app version `1.0.0`, build `2610281431`, app-source commit `e5abd77`. macOS validation, CocoaPods resolution, signed IPA archive/export and CloudKit entitlement verification passed; altool reported `UPLOAD SUCCEEDED with no errors`. App Store Connect received the build and began processing. Native simulator/device behavior still needs hands-on testing.

iPhone Duo screenshots: six Japanese screenshots (three outer-display portrait, three inner-display landscape) were uploaded to the existing Japanese App Store version draft and persisted after reload. Sources are Flutter Web UI captures with demo notes, not native simulator captures. Canonical RGB PNGs and dimension/hash manifests are under `store-assets/app-store/iphone-duo-upload/{ja,en}/`; English images are prepared locally but no English store localization was added. Regenerate source captures with `node tools/store_assets/generate_app_store_screenshots.js --iphone-duo-only`. Apple sizes: 1398×2034 outer portrait and 2853×2007 inner landscape.

Codemagic と同じく、iOS は `--flavor production` を付けずに entrypoint だけ `lib/main_production.dart` にする。

## Required Secrets

Signing:
- `IOS_DISTRIBUTION_CERTIFICATE_BASE64`
- `IOS_DISTRIBUTION_CERTIFICATE_PASSWORD`
- `IOS_PROVISIONING_PROFILE_APP_BASE64`
- `IOS_PROVISIONING_PROFILE_WIDGET_BASE64`
- `IOS_PROVISIONING_PROFILE_SHARE_EXTENSION_BASE64`

Optional signing:
- `IOS_BUILD_KEYCHAIN_PASSWORD`

App Store Connect API:
- `APP_STORE_CONNECT_API_KEY_ID`
- `APP_STORE_CONNECT_API_ISSUER_ID`
- `APP_STORE_CONNECT_API_PRIVATE_KEY`

Google Sign-In / build defines:
- `HIMEMO_GOOGLE_SIGN_IN_CLIENT_ID`
- `HIMEMO_GOOGLE_REVERSED_CLIENT_ID`
- `HIMEMO_GOOGLE_SIGN_IN_SERVER_CLIENT_ID`
- `HIMEMO_APP_STORE_ID`

## Creating Base64 Values

On macOS:

```sh
base64 -i distribution.p12 | pbcopy
base64 -i HiMemo_App_Store_Profile.mobileprovision | pbcopy
base64 -i HiMemo_Widget_App_Store_Profile.mobileprovision | pbcopy
base64 -i HiMemo_Share_Extension_App_Store_Profile.mobileprovision | pbcopy
```

For `APP_STORE_CONNECT_API_PRIVATE_KEY`, paste the full `.p8` content including:

```text
-----BEGIN PRIVATE KEY-----
...
-----END PRIVATE KEY-----
```

## Bundle IDs and Profiles

The workflow expects these App Store provisioning profile names:
- `org.ruhenheim.himemo`: `HiMemo App Store Profile`
- `org.ruhenheim.himemo.QuickCaptureWidget`: `HiMemo Widget App Store Profile`
- `org.ruhenheim.himemo.ShareExtension`: `HiMemo Share Extension App Store Profile`

If the Apple Developer Portal profile names change, update the `APP_STORE_PROFILE_NAME`, `WIDGET_PROFILE_NAME`, and `SHARE_EXTENSION_PROFILE_NAME` env values in the workflow.

## First Run Checklist

1. Run with `upload_to_testflight=false`.
2. Confirm the IPA artifact is generated.
3. Confirm the entitlement verification step prints CloudKit and `iCloud.org.ruhenheim.himemo`.
4. Run again with `upload_to_testflight=true`.
5. Confirm App Store Connect receives the build and TestFlight processing completes.

The upload step only uploads to App Store Connect. Tester group assignment should be handled by App Store Connect TestFlight settings, or added later through App Store Connect API automation if needed.

## Troubleshooting

If Xcode reports `No Accounts` or searches for `iOS App Development provisioning profiles`, the archive step is still using automatic/development signing. The workflow includes `Configure manual iOS signing` to set the app, widget, and share extension targets to manual `Apple Distribution` signing before `flutter build ipa`.

The workflow reads the embedded `Name` and `UUID` from each `.mobileprovision` file and uses those values for Xcode signing. If Xcode says a profile does not include the signing certificate, regenerate that provisioning profile in Apple Developer Portal with the Apple Distribution certificate used for `IOS_DISTRIBUTION_CERTIFICATE_BASE64`.

The widget and share extension `Info.plist` files contain Flutter build variables in source, but App Store Connect requires concrete `CFBundleShortVersionString` and `CFBundleVersion` values inside the uploaded `.appex` bundles. The workflow writes those values from `pubspec.yaml` and `build_number` before building.
