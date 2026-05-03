import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ja')];

  static const delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    final value = Localizations.of<AppStrings>(context, AppStrings);
    assert(value != null, 'AppStrings not found in context');
    return value!;
  }

  bool get isJapanese => locale.languageCode == 'ja';

  String get appTitle => 'HiMemo';
  String get notes => isJapanese ? 'ノート' : 'Notes';
  String get calendar => isJapanese ? 'カレンダー' : 'Calendar';
  String get insights => isJapanese ? '記録' : 'Insights';
  String get settings => isJapanese ? '設定' : 'Settings';
  String get addNote => isJapanese ? 'ノートを追加' : 'Add note';
  String get search => isJapanese ? '検索' : 'Search';
  String get today => isJapanese ? '今日' : 'Today';

  String get appearance => isJapanese ? '表示' : 'Appearance';
  String get language => isJapanese ? '言語' : 'Language';
  String get languageSystem => isJapanese ? 'システムに合わせる' : 'Follow system';
  String get languageJapanese => isJapanese ? '日本語' : 'Japanese';
  String get languageEnglish => isJapanese ? '英語' : 'English';
  String get languageSystemDesc => isJapanese
      ? '端末の言語設定に合わせます。未対応の言語では英語を使います。'
      : 'Follow the device language. Fall back to English when unsupported.';
  String get themeLight => isJapanese ? 'ライト' : 'Light';
  String get themeSystem => isJapanese ? 'システム' : 'System';
  String get themeDark => isJapanese ? 'ダーク' : 'Dark';
  String get accentColor => isJapanese ? 'アクセントカラー' : 'Accent color';
  String get colorBlue => isJapanese ? 'ブルー' : 'Blue';
  String get colorGreen => isJapanese ? 'グリーン' : 'Green';
  String get colorOrange => isJapanese ? 'オレンジ' : 'Orange';
  String get colorSlate => isJapanese ? 'スレート' : 'Slate';
  String get colorTeal => isJapanese ? 'ティール' : 'Teal';
  String get colorRose => isJapanese ? 'ローズ' : 'Rose';
  String get colorBlueDesc => isJapanese
      ? '落ち着いた青を基調にした標準テーマです。'
      : 'Primary blue with calm support colors.';
  String get colorGreenDesc => isJapanese
      ? '視覚的な緊張を抑えた柔らかいグリーンです。'
      : 'Muted green palette for lower visual tension.';
  String get colorOrangeDesc => isJapanese
      ? '暖かいアクセントで操作や記録を目立たせます。'
      : 'Warm orange palette for highlighted actions and notes.';
  String get colorSlateDesc => isJapanese
      ? '中立的で静かな印象のスレート配色です。'
      : 'Neutral slate palette for a quieter interface.';
  String get colorTealDesc => isJapanese
      ? '軽やかな印象を出すティール配色です。'
      : 'Fresh teal palette with a light feel.';
  String get colorRoseDesc => isJapanese
      ? '日記らしい柔らかな雰囲気のローズ配色です。'
      : 'Soft rose palette for a more diary-like tone.';
  String get lightDesc => isJapanese
      ? '白基調のメモらしい見た目を保ちます。'
      : 'Keep the white memo-style interface.';
  String get systemDesc =>
      isJapanese ? '端末の表示設定に合わせます。' : 'Follow the device setting.';
  String get darkDesc => isJapanese
      ? '高コントラストなダークテーマを明示的に使います。'
      : 'Use the higher-contrast dark theme explicitly.';

  String get about => isJapanese ? 'アプリ情報' : 'About';
  String get appVersion => isJapanese ? 'アプリバージョン' : 'App version';
  String get appUpdates => isJapanese ? 'アプリ更新' : 'App updates';
  String get appUpdatesDesc => isJapanese
      ? 'Google Play のアプリ内更新を確認し、必要な更新を開始します。'
      : 'Check Google Play in-app updates and start the recommended update flow.';
  String get checkForUpdates => isJapanese ? '更新を確認' : 'Check for updates';
  String get startUpdate => isJapanese ? '更新を開始' : 'Start update';
  String get completeUpdateInstall => isJapanese ? '更新を完了' : 'Complete update';
  String get updateSupportedOnAndroidOnly => isJapanese
      ? 'アプリ内更新は Android の Google Play 配布で利用できます。'
      : 'In-app updates are available on Android builds distributed through Google Play.';
  String get updateStatusUpToDate =>
      isJapanese ? '現在のビルドは最新です。' : 'The installed build is up to date.';
  String get updateStatusAvailable => isJapanese
      ? 'Google Play に新しい更新があります。'
      : 'A newer build is available on Google Play.';
  String get updateStatusChecking =>
      isJapanese ? '更新を確認しています...' : 'Checking for updates...';
  String get updateStatusUnsupported => isJapanese
      ? 'この実行環境ではアプリ内更新を利用できません。'
      : 'In-app updates are not available in this runtime.';
  String get updateStatusStarted => isJapanese
      ? 'Google Play の更新フローを開始しました。'
      : 'Started the Google Play update flow.';
  String get updateFlexibleReady => isJapanese
      ? '柔軟な更新がダウンロード済みです。完了を押すと再起動して更新します。'
      : 'A flexible update is downloaded. Complete it to restart and apply the update.';
  String updateVersionLabel(int? versionCode) => isJapanese
      ? (versionCode == null ? '配信中の更新' : '配信中の更新: $versionCode')
      : (versionCode == null
            ? 'Available update'
            : 'Available update: $versionCode');
  String updatePriorityLabel(int? priority) =>
      isJapanese ? '優先度: ${priority ?? 0}' : 'Priority: ${priority ?? 0}';
  String get ossLicenses => isJapanese ? 'OSS ライセンス' : 'OSS licenses';
  String get ossLicensesDesc => isJapanese
      ? '利用しているオープンソースソフトウェアのライセンスを表示します。'
      : 'View bundled open-source software licenses.';
  String currentFlavor(String name) =>
      isJapanese ? '現在の flavor: $name' : 'Current flavor: $name';
  String readingVersion() =>
      isJapanese ? 'バージョンを読み込み中...' : 'Reading app version...';

  String get homeWidgetQuickCapture =>
      isJapanese ? '外部クイックメモ' : 'Allow external quick capture';
  String get homeWidgetQuickCaptureDesc => isJapanese
      ? 'ホームウィジェットや共有メニューから、通常のアプリロックを開かずに簡易メモ画面を開けます。'
      : 'Let the home widget or Android share sheet open a quick memo surface without unlocking the full app.';
  String get homeWidgetQuickCaptureMobileOnly => isJapanese
      ? 'モバイルのみ。オンにすると、ホームウィジェットや共有メニューから通常のアプリロックを開かずに簡易メモ画面を開けます。'
      : 'Mobile-only. When enabled, the home widget or Android share sheet can open a quick memo surface outside the normal app lock.';

  String get unlockHiMemo => isJapanese ? 'HiMemo を解除' : 'Unlock HiMemo';
  String get unlockWithPin => isJapanese ? 'PIN で解除' : 'Unlock with PIN';
  String get authenticate => isJapanese ? '認証する' : 'Authenticate';
  String get disableUnlockForNow =>
      isJapanese ? '今はアプリロックを無効にする' : 'Disable app unlock for now';
  String get browserPinGate => isJapanese
      ? 'このブラウザのセッションは Web PIN で保護されています。'
      : 'This browser session is protected with a web PIN.';
  String get deviceAuthGate => isJapanese
      ? '端末認証でこのセッションを再開します。'
      : 'Resume this session with device authentication.';
  String get privateVaultLockedMessage => isJapanese
      ? 'private vault と同期状態は、セッションを戻すまでロックされたままです。'
      : 'Private vault access and sync state remain locked until the session is restored.';

  String get onboardingWelcome =>
      isJapanese ? 'HiMemo へようこそ' : 'Welcome to HiMemo';
  String get onboardingIntro => isJapanese
      ? 'メモを書き始める前に、短い初期設定だけ済ませます。'
      : 'A short setup pass before the memo vault opens.';
  String get onboardingCaptureTitle => isJapanese ? 'すばやく記録' : 'Capture fast';
  String get onboardingCaptureBody => isJapanese
      ? '1行目がそのままタイトルになるので、思いついた内容をそのまま軽く書き始められます。'
      : 'The first line becomes the memo title, so quick notes stay lightweight from the first tap.';
  String get onboardingCaptureImageLabel =>
      isJapanese ? 'クイックメモ入力のプレビュー' : 'Quick memo capture preview';
  String get onboardingPrivateTitle =>
      isJapanese ? 'プライベート領域を分ける' : 'Separate private access';
  String get onboardingPrivateBody => isJapanese
      ? 'アプリの起動ロックとは別に、複数のプロファイルを個別のパスワードで管理できます。必要なプロファイルだけをその場で開けます。'
      : 'App unlock stays separate from profile access. You can manage multiple profiles with different passwords and open only the one you need.';
  String get onboardingPrivateImageLabel =>
      isJapanese ? 'プライベートプロファイル解錠のプレビュー' : 'Private vault unlock preview';
  String get onboardingSyncTitle =>
      isJapanese ? '同期はあとから設定' : 'Prepare sync later';
  String get onboardingSyncBody => isJapanese
      ? 'iCloud や Google Drive は、あとから同期先として選べます。最初は自前サーバーなしで始められます。'
      : 'Choose iCloud or Google Drive as the future sync target without turning your own server into a dependency.';
  String get onboardingSyncImageLabel =>
      isJapanese ? 'クラウド同期先のプレビュー' : 'Cloud sync target preview';
  String get onboardingFinishTitle =>
      isJapanese ? '最初に基本だけ設定' : 'Finish the basics';
  String get onboardingFinishBody => isJapanese
      ? 'まずはアプリ起動ロックだけ設定します。プライベートプロファイルやクラウド同期は、あとから設定で追加できます。'
      : 'Set the app unlock first. Private profiles and cloud sync can be added later from Settings.';
  String get onboardingFinishImageLabel =>
      isJapanese ? '初期アクセス設定のプレビュー' : 'Initial access setup preview';
  String get onboardingAddImageFallback =>
      isJapanese ? 'オンボーディング画像を追加' : 'Add an onboarding image';
  String get onboardingAppUnlockTitle => isJapanese ? 'アプリ起動ロック' : 'App unlock';
  String get onboardingPinConfiguredBrowser => isJapanese
      ? 'このブラウザでは解除用 PIN が設定されています。'
      : 'Configured for this browser.';
  String get onboardingSetPinBrowser => isJapanese
      ? '起動時の保護として 4 桁の PIN を設定できます。'
      : 'Set a 4 digit PIN for app launch.';
  String get onboardingDeviceAuthLater => isJapanese
      ? 'iPhone や Android では、端末の生体認証や端末 PIN を起動ロックとして使います。'
      : 'Device authentication can be enabled later in Settings.';
  String get onboardingChangePin => isJapanese ? 'PIN を変更' : 'Change PIN';
  String get onboardingSetPin => isJapanese ? 'PIN を設定' : 'Set PIN';
  String get onboardingLaterInSettings =>
      isJapanese ? 'あとで設定' : 'Later in Settings';
  String get onboardingPinSaved =>
      isJapanese ? 'アプリ解除 PIN を保存しました。' : 'App unlock PIN saved.';
  String get onboardingPrivateProfilesTitle =>
      isJapanese ? 'プライベートプロファイル' : 'Private profiles';
  String onboardingPrivateProfilesConfigured(int count) => isJapanese
      ? '$count 件のプライベートプロファイルが登録されています。'
      : '$count private profiles are configured.';
  String get onboardingPrivateProfilesBody => isJapanese
      ? '鍵アイコンから、入力したパスワードに合うプロファイルだけを開けます。用途ごとに分けて管理する前提です。'
      : 'Use the key icon to open only the profile that matches the entered password. This works well for keeping different spaces under separate locks.';
  String get onboardingAddInSettings =>
      isJapanese ? '設定で追加' : 'Add in Settings';
  String get onboardingCloudSyncTitle => isJapanese ? 'クラウド同期' : 'Cloud sync';
  String get onboardingCloudSyncBody => isJapanese
      ? 'iCloud や Google Drive への同期は、あとから設定で有効化できます。最初はオフラインのまま始められます。'
      : 'Enable iCloud or Google Drive later in Settings. You can start as an offline-first memo app.';

  String get privateProfilesSettingsTitle =>
      isJapanese ? 'プライベートプロファイル' : 'Private profiles';
  String get privateProfilesSettingsAdminSummary => isJapanese
      ? '管理者モードでも、プロファイル名や保存先IDは設定画面に表示しません。'
      : 'Profile names and vault IDs stay hidden in Settings, even in admin mode.';
  String privateProfilesSettingsActiveSummary(String _) => isJapanese
      ? '現在は認証済みのプライベートプロファイルを表示しています。'
      : 'A verified private profile is currently open.';
  String get privateProfilesSettingsDefaultSummary => isJapanese
      ? '通常は Notes だけを表示し、必要なときだけ別のプロファイルを開きます。'
      : 'Notes stays visible by default. Open another profile only when you need it.';
  String get privateProfilesSettingsBody => isJapanese
      ? '右上の鍵アイコンからパスワードを入力すると、一致するプロファイルだけを開けます。設定画面では登録済みプロファイルの名前や保存先IDを列挙しません。'
      : 'Enter a password from the key icon in the top bar to open only the matching profile. Settings does not list configured profile names or vault IDs.';
  String get addPrivateProfile => isJapanese ? 'プロファイルを追加' : 'Add profile';
  String get adminModeActiveLabel =>
      isJapanese ? '管理者モード中' : 'Admin mode active';
  String get enterAdminModeLabel =>
      isJapanese ? '管理者モードへ移行' : 'Enter admin mode';
  String get exitAdminModeLabel => isJapanese ? '管理者モードを終了' : 'Exit admin mode';
  String get noPrivateProfilesMessage =>
      isJapanese ? 'まだプライベートプロファイルはありません。' : 'No private profiles yet.';
  String privateProfilesHiddenSummary(int count) => isJapanese
      ? '$count 件のプライベートプロファイルが登録されています。名前と保存先IDは非表示です。'
      : '$count private profiles are configured. Names and vault IDs are hidden.';
  String get setAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードを設定' : 'Set alternate profile password';
  String get changeAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードを変更' : 'Change alternate profile password';
  String get resetAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードをリセット' : 'Reset alternate profile password';

  String get skip => isJapanese ? 'スキップ' : 'Skip';
  String get next => isJapanese ? '次へ' : 'Next';
  String get finishSetup => isJapanese ? 'セットアップ完了' : 'Finish setup';
  String get setAppUnlockPin =>
      isJapanese ? 'アプリ解除 PIN を設定' : 'Set app unlock PIN';
  String get pin => 'PIN';
  String get cancel => isJapanese ? 'キャンセル' : 'Cancel';
  String get save => isJapanese ? '保存' : 'Save';
  String get useExactly4Digits =>
      isJapanese ? '4桁ちょうどで入力してください。' : 'Use exactly 4 digits.';
  String get digitsOnly => isJapanese ? '数字のみ入力できます。' : 'Digits only.';
  String get coverKey => isJapanese ? 'カバーキー' : 'Cover key';
  String get privateKey => isJapanese ? 'プライベートキー' : 'Private key';
  String get setPrivateKey => isJapanese ? 'プライベートキーを設定' : 'Set private key';
  String confirmPrivateKey(String label) =>
      isJapanese ? '$label を確認' : 'Confirm $label';
  String get keysDoNotMatch => isJapanese ? 'キーが一致しません。' : 'Keys do not match.';
  String get useAtLeast4Chars =>
      isJapanese ? '4文字以上で入力してください。' : 'Use at least 4 characters.';
  String get quickMemo => isJapanese ? 'クイックメモ' : 'Quick memo';
  String get richMemo => isJapanese ? 'リッチメモ' : 'Rich memo';
  String get newNote => isJapanese ? '新しいノート' : 'New note';
  String get editNote => isJapanese ? 'ノートを編集' : 'Edit note';
  String get memoLabel => isJapanese ? 'メモ' : 'Memo';
  String get memoFirstLineHint =>
      isJapanese ? '1行目をタイトルとして使います' : 'Use the first line as the title';
  String get vault => isJapanese ? '分類' : 'Vault';
  String get pinThisNote => isJapanese ? 'このノートを固定' : 'Pin this note';
  String get pinThisNoteDesc =>
      isJapanese ? '固定したノートは一覧の上に表示されます。' : 'Pinned notes stay near the top.';
  String get createNote => isJapanese ? 'ノートを作成' : 'Create note';
  String get saveChanges => isJapanese ? '変更を保存' : 'Save changes';
  String get startWritingHere =>
      isJapanese ? 'ここから書き始めます' : 'Start writing here';
  String get attachments => isJapanese ? '添付' : 'Attachments';
  String get addMedia => isJapanese ? 'メディアを追加' : 'Add media';
  String get pickPhoto => isJapanese ? '写真を選ぶ' : 'Pick photo';
  String get takePhoto => isJapanese ? '写真を撮る' : 'Take photo';
  String get pickVideo => isJapanese ? '動画を選ぶ' : 'Pick video';
  String get recordVideo => isJapanese ? '動画を撮る' : 'Record video';
  String get recordAudio => isJapanese ? '音声を録音' : 'Record audio';
  String get pickAudio => isJapanese ? '音声を選ぶ' : 'Pick audio';
  String get addCurrentLocation =>
      isJapanese ? '現在地を追加' : 'Add current location';
  String get currentLocationLabel => isJapanese ? '現在地' : 'Current location';
  String get estimatedAddressLabel => isJapanese ? '推定住所' : 'Estimated address';
  String get latitudeLabel => isJapanese ? '緯度' : 'Latitude';
  String get longitudeLabel => isJapanese ? '経度' : 'Longitude';
  String get locationAccuracyLabel => isJapanese ? '精度' : 'Accuracy';
  String get openMap => isJapanese ? '地図を開く' : 'Open map';
  String get copyMapLink => isJapanese ? '地図リンクをコピー' : 'Copy map link';
  String get mapLinkCopied =>
      isJapanese ? '地図リンクをコピーしました。' : 'Map link copied.';
  String get mapOpenFailed =>
      isJapanese ? '地図を開けませんでした。' : 'Could not open the map.';
  String get linkOpenFailed =>
      isJapanese ? 'リンクを開けませんでした。' : 'Could not open the link.';
  String get openExternalLinkTitle =>
      isJapanese ? '外部リンクを開きますか？' : 'Open external link?';
  String get openExternalLinkMessage => isJapanese
      ? 'このリンクはHiMemoの外部で開かれます。URLを確認してから続行してください。'
      : 'This link will open outside HiMemo. Check the URL before continuing.';
  String get openLink => isJapanese ? '開く' : 'Open';
  String get locationServicesOff => isJapanese
      ? '位置情報サービスがオフです。端末設定で有効にしてください。'
      : 'Location services are off. Enable them in device settings.';
  String get locationPermissionRequired => isJapanese
      ? '現在地を追加するには位置情報の許可が必要です。'
      : 'Location permission is required to add current location.';
  String get currentLocationAdded =>
      isJapanese ? '現在地をメモに追加しました。' : 'Current location added to the note.';
  String get currentLocationUnavailable =>
      isJapanese ? '現在地を取得できませんでした。' : 'Could not get current location.';
  String get attachFromBrowser => isJapanese
      ? 'このブラウザから写真・動画・音声を添付できます。'
      : 'Attach photos, videos, or audio files from this browser.';
  String get attachFromDevice => isJapanese
      ? 'カメラや端末内の写真・動画・音声を添付できます。'
      : 'Attach photos, videos, or audio files from camera or device storage.';
  String get dateTimeUpdated =>
      isJapanese ? '日時を更新しました' : 'Date and time updated';
  String get microphonePermissionNotGranted => isJapanese
      ? 'マイクの使用が許可されていません。'
      : 'Microphone permission was not granted.';
  String get microphonePermissionBrowserHelp => isJapanese
      ? 'Chrome または Edge で開き、サイト設定からマイクを許可してください。'
      : 'Open this app in Chrome or Edge and allow microphone access from the site settings.';
  String get microphonePermissionRequestTimedOut => isJapanese
      ? 'マイク許可の確認がタイムアウトしました。ブラウザの許可ダイアログを確認してください。'
      : 'Microphone permission check timed out. Check the browser permission prompt.';
  String get microphoneStartTimedOut => isJapanese
      ? 'マイクの開始がタイムアウトしました。別のアプリがマイクを使用していないか確認してください。'
      : 'Microphone startup timed out. Check whether another app is using the microphone.';
  String audioRecordingStartFailed(String diagnostic) => isJapanese
      ? '録音を開始できませんでした。$diagnostic'
      : 'Could not start recording.$diagnostic';
  String get audioRecordingNotificationTitle =>
      isJapanese ? 'HiMemoで録音中' : 'HiMemo is recording';
  String get audioRecordingNotificationContent =>
      isJapanese ? '音声メモの録音を継続しています。' : 'Audio memo recording is continuing.';
  String get audioRecordingSaveFailed =>
      isJapanese ? '録音データを保存できませんでした。' : 'Could not save the recording.';
  String get audioRecordingEmpty =>
      isJapanese ? '録音データが空でした。' : 'The recording was empty.';
  String get audioRecordingAttachFailed =>
      isJapanese ? '録音を添付できませんでした。' : 'Could not attach the recording.';
  String get audioRecordingStoreFailed =>
      isJapanese ? '録音を保存できませんでした。' : 'Could not save the recording.';
  String get audioPlaybackFailed =>
      isJapanese ? '音声を再生できませんでした。' : 'Could not play this audio.';
  String get audioMemoRecordingTitle =>
      isJapanese ? '音声メモを録音' : 'Record audio memo';
  String get stopAndAttachRecording =>
      isJapanese ? '停止して添付' : 'Stop and attach';
  String get startRecording => isJapanese ? '録音開始' : 'Start recording';
  String get undo => isJapanese ? '元に戻す' : 'Undo';
  String get draftRestored => isJapanese ? '下書きを復元しました' : 'Draft restored';
  String get discardDraft => isJapanese ? '破棄' : 'Discard';
  String get dismiss => isJapanese ? '閉じる' : 'Dismiss';
  String attachmentRemoved(String label) =>
      isJapanese ? '$label を削除しました' : '$label removed';
  String get removeBlock => isJapanese ? 'この添付を削除' : 'Remove block';
  String get moveEarlier => isJapanese ? '前へ移動' : 'Move earlier';
  String get moveLater => isJapanese ? '後へ移動' : 'Move later';
  String get syncAppleIdUnsupported => isJapanese
      ? 'このビルドでは iOS / macOS のみ iCloud 同期を利用できます。'
      : 'iCloud sync is only available on iOS and macOS in this build.';
  String get syncAppleIdUnavailable => isJapanese
      ? 'この端末では iCloud を利用できません。'
      : 'iCloud is not available on this device.';
  String get syncAppleIdConnected => isJapanese
      ? 'iCloud の利用状態を確認できました。同期設定を続けてください。'
      : 'iCloud is available. Continue setting up sync.';
  String get syncApplePluginMissing => isJapanese
      ? 'この実行環境では iCloud 同期を利用できません。'
      : 'iCloud sync is not configured in this runtime.';
  String get syncAppleUnknownError => isJapanese
      ? 'iCloud の状態を確認できませんでした。iCloud へのサインイン状態とアプリの権限を確認してください。'
      : 'Unable to confirm iCloud availability. Check the iCloud sign-in state and app capabilities.';
  String get close => isJapanese ? '閉じる' : 'Close';
  String get sendMemo => isJapanese ? 'メモを送信' : 'Send memo';
  String get sending => isJapanese ? '送信中...' : 'Sending...';
  String get sendQuickMemo => isJapanese ? 'クイックメモを送信' : 'Send a quick memo';
  String get quickMemoSaved =>
      isJapanese ? 'クイックメモを Notes に保存しました。' : 'Quick memo saved to Notes.';
  String get sharedMemoSaveFailed =>
      isJapanese ? '共有メモを保存できませんでした。' : 'Could not save the shared memo.';
  String quickCaptureDescription({required bool isShare}) => isJapanese
      ? (isShare
            ? '共有メニューから受け取ったテキストやファイルを、そのまま Notes に送れます。既存ノートやロック中のプロファイルは開きません。'
            : 'すばやくメモを記録します。この画面では既存ノートやロック中のプロファイルは表示しません。')
      : (isShare
            ? 'Shared text and files can be sent straight to Notes. This route never reveals existing notes or locked profiles.'
            : 'Capture a quick memo. This route never reveals existing notes or locked profiles.');
  String get sharedFiles => isJapanese ? '共有ファイル' : 'Shared files';
  String get filesNotImported =>
      isJapanese ? '取り込めなかったファイル' : 'Files not imported';
  String get sharedFileFallback => isJapanese ? '共有ファイル' : 'Shared file';
  String quickCaptureHint({required bool isShare}) => isJapanese
      ? (isShare
            ? '共有されたテキストを整えて、そのまま Notes に保存できます。'
            : 'メモを書いて、そのまま Notes に送ります。')
      : (isShare
            ? 'Tidy the shared text and save it to Notes.'
            : 'Write a memo and send it to Notes.');
  String sharedFileImportFailureReason(String reason) {
    switch (reason) {
      case 'unsupported_type':
        return isJapanese
            ? 'このファイル形式はサポートしていません。'
            : 'This file type is not supported.';
      case 'too_large':
        return isJapanese ? 'このファイルは大きすぎます。' : 'This file is too large.';
      case 'unreadable':
        return isJapanese
            ? 'このファイルを読み込めませんでした。'
            : 'This file could not be read.';
      default:
        return reason;
    }
  }

  String get finishSetupFirst =>
      isJapanese ? '先に初期設定を完了してください' : 'Finish setup first';
  String get quickWidgetCaptureOff =>
      isJapanese ? '外部クイックメモはオフです' : 'External quick capture is off';
  String get enableQuickWidgetInSettings => isJapanese
      ? '設定で外部クイックメモをオンにすると、ホームウィジェットや共有メニューからフルアプリを開かずにメモを送れます。'
      : 'Enable external quick capture in Settings if you want the home widget or Android share sheet to send memos without unlocking the full app.';
  String get completeOnboardingBeforeWidget => isJapanese
      ? 'ホームウィジェットから使う前に、初期設定を完了してください。'
      : 'Complete onboarding before using quick capture from the home widget.';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ja'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsX on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
