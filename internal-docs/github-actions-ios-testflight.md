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

The workflow uses the `macos-26` GitHub-hosted runner so App Store Connect receives an IPA built with the iOS 26 SDK or later.

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

Export compliance:
- `HIMEMO_EXPORT_COMPLIANCE_CODE`: the `ITSEncryptionExportComplianceCode` value shown by App Store Connect after the app's export compliance documentation is approved.

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
