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

Local validation on 2026-10-28: Flutter analysis with `--fatal-infos` and formatting passed; all 373 Flutter tests passed, including the resize regression. Web build passed. The two selected Playwright onboarding / mobile note-and-archive scenarios passed after aligning the existing onboarding helper with the five-page UI and its current labels. Functions lint and all 11 tests passed. Both npm dependency trees reported zero known audit vulnerabilities after lockfile updates; the root package overrides serve's compression dependency to patched 1.8.2. The toolchain guard was checked with mocked 27.1 and older version output. These local checks did not cover macOS archive/signing or native simulator/device behavior; see the release execution result below.

2026-10-28 release execution: [GitHub Actions run 40706424640](https://github.com/mmiyaji/himemo/actions/runs/40706424640) succeeded for app version `1.0.0`, build `2610281431`, app-source commit `e5abd77`. macOS validation, CocoaPods resolution, signed IPA archive/export and CloudKit entitlement verification passed; altool reported `UPLOAD SUCCEEDED with no errors`. Apple processing completed, and the existing internal group `ruhenheim` (2 testers) shows this build as testing (`テスト中`). Japanese What to Test instructions were saved. Native simulator/device behavior still needs hands-on testing.

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

After the upload step, `tools/finalize_testflight.py` uses the same API credentials to wait for the exact build number to become VALID, save and read back Japanese What to Test notes, add the build to the existing internal `ruhenheim` group, and verify `internalBuildState=IN_BETA_TESTING`. It does not create tester groups, invite testers, upload a second binary, or alter export-compliance declarations. A processing/compliance/permission failure leaves the uploaded build intact and must be resolved before claiming distribution succeeded.

Japanese test notes are maintained in `internal-docs/testflight-what-to-test.ja.txt`. This sync update requires stopping sync/cleanup on old clients and updating every participating device before resuming. Old and new clients are not safe to mix.

The finalizer can be run again against the same build number without re-uploading. Use `--private-key-file` (or `APP_STORE_CONNECT_API_PRIVATE_KEY_PATH`) with an existing API key, or the same CI private-key environment variable. Credentials and JWTs are never printed. The unit tests use mocked API responses and signer results; actual Apple processing, note persistence and internal availability are checked in CI.

## iOS 27 startup lifecycle

Build `2610281431` crashed at launch in UIKit's `UIApplicationEvaluateRuntimeIssueForNoSceneLifecycleAdoption` (SIGTRAP). The customized AppDelegate had not been automatically migrated to UIScene. Xcode 27 builds require this lifecycle; see [Flutter's migration guide](https://docs.flutter.dev/release/breaking-changes/uiscenedelegate).

Runner now declares a scene manifest, registers plugins and custom channels through `FlutterImplicitEngineDelegate`, and handles URL/activity delivery and the privacy overlay through a `FlutterSceneDelegate` subclass. The subclass lives in AppDelegate.swift and is included by its existing Sources build phase. Multi-window support remains disabled.

The release workflow requires an iOS 27 iPhone simulator. Before archiving, `test_driver/ios_launch_app.dart` starts the production entrypoint with the driver extension, and its host test waits for the real onboarding screen and exercises native network/privacy channels. The `ios-launch-smoke-*` artifact contains the rendered onboarding screenshot. This gate covers native startup and channel registration; physical-device signing, authentication, sync, and folding still require device testing. Crash ZIPs and raw logs stay in the ignored local `.codex/` directory.

2026-10-29 recovery release: [run 40722205383](https://github.com/mmiyaji/himemo/actions/runs/40722205383) succeeded for source commit `a47a407`, version `1.0.0 (2610281605)`. The iPhone Duo simulator rendered production onboarding and passed native network/privacy channel checks; all 373 Flutter tests, analysis, Web build, Functions validation, signing and entitlement checks passed. The signed IPA's scene delegate is `Runner.SceneDelegate`, and both extensions match the app build number. Apple upload succeeded at 2026-10-28 16:30 UTC, processing completed, and the existing `ruhenheim` internal group has access. Evidence: `ios-launch-smoke-110/onboarding.png` and `himemo-ios-110` in the run artifacts. Simulator verification uses a debug build with the production entrypoint; the distributed IPA is a release build. Physical-device launch and lifecycle behavior still need tester confirmation.

Configure extension versions before the simulator gate as well as the archive: unresolved Flutter placeholders in extension Info.plist prevent simulator installation. The gate explicitly builds with the same build number as the extensions and drives that prebuilt app.

## Troubleshooting

If Xcode reports `No Accounts` or searches for `iOS App Development provisioning profiles`, the archive step is still using automatic/development signing. The workflow includes `Configure manual iOS signing` to set the app, widget, and share extension targets to manual `Apple Distribution` signing before `flutter build ipa`.

The workflow reads the embedded `Name` and `UUID` from each `.mobileprovision` file and uses those values for Xcode signing. If Xcode says a profile does not include the signing certificate, regenerate that provisioning profile in Apple Developer Portal with the Apple Distribution certificate used for `IOS_DISTRIBUTION_CERTIFICATE_BASE64`.

The widget and share extension `Info.plist` files contain Flutter build variables in source, but App Store Connect requires concrete `CFBundleShortVersionString` and `CFBundleVersion` values inside the uploaded `.appex` bundles. The workflow writes those values from `pubspec.yaml` and `build_number` before building.

2026-10-29 CI timeout correction: run 40855139139 successfully compiled the current simulator app (Xcode build 867.8 seconds), but the shared 20-minute build-and-launch step timed out before the launch test ran. The workflow now gives the simulator build its own 30-minute step, uses already resolved dependencies with `--no-pub`, then boots and tests the simulator in a separate 10-minute step. The job budget is 90 minutes to include Apple processing. Startup assertions and signing/entitlement gates remain required.

## Verified security and sync TestFlight release (2026-10-29)

Version **1.0.0 (2610291035)** is available to the existing internal **ruhenheim** group. App Store Connect API confirmed `processingState=VALID`, `internalBuildState=IN_BETA_TESTING` and `usesNonExemptEncryption=false` at 11:05 UTC. Build ID: `843d787e-7b36-488a-836d-87d49e5dab5d`; app ID: `6762381959`.

- [Build/upload run 40858534175](https://github.com/mmiyaji/himemo/actions/runs/40858534175), source commit `e105ac7`: simulator build, iPhone Duo startup/native-channel test, Dart formatting/analysis, Flutter tests, Web build, Functions validation, signed IPA, CloudKit entitlements and Apple upload all passed. `ios-launch-smoke-113/onboarding.png` and `himemo-ios-113` are the evidence artifacts. The run's final metadata step reported HTTP422 after the upload; the binary did not need rebuilding.
- [Metadata verification run 40862587026](https://github.com/mmiyaji/himemo/actions/runs/40862587026), automation commit `332bb7a`: verified the same uploaded build, saved/read back Japanese test notes, recognized the internal group's automatic access to all builds, and confirmed IN_BETA_TESTING. This run succeeded without compiling or uploading another binary.
- `finalize_only=true` with `build_number=2610291035` runs just this existing-build verification job. Automatic internal groups must not receive redundant per-build additions. The helper now reports safe API method/path and validation detail when an operation fails.
- Stop old-version sync and cleanup on every participating device; update all clients to a compatible version before resuming. Devices without a compatible release must keep sync/cleanup disabled. This requirement is included in the saved Japanese What to Test notes.

Native startup was verified in a debug simulator app using the production entrypoint. The distributed IPA is release-signed; physical-device sync, authentication, data migration and folding behavior remain the internal testers' verification scope.
