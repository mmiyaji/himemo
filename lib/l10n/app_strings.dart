import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
  ];

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
  String get systemDesc => isJapanese
      ? '端末の表示設定に合わせます。'
      : 'Follow the device setting.';
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
  String get updateStatusUpToDate => isJapanese
      ? '現在のビルドは最新です。'
      : 'The installed build is up to date.';
  String get updateStatusAvailable => isJapanese
      ? 'Google Play に新しい更新があります。'
      : 'A newer build is available on Google Play.';
  String get updateStatusChecking => isJapanese ? '更新を確認しています...' : 'Checking for updates...';
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
      : (versionCode == null ? 'Available update' : 'Available update: $versionCode');
  String updatePriorityLabel(int? priority) => isJapanese
      ? '優先度: ${priority ?? 0}'
      : 'Priority: ${priority ?? 0}';
  String get ossLicenses => isJapanese ? 'OSS ライセンス' : 'OSS licenses';
  String get ossLicensesDesc => isJapanese
      ? '利用しているオープンソースソフトウェアのライセンスを表示します。'
      : 'View bundled open-source software licenses.';
  String currentFlavor(String name) =>
      isJapanese ? '現在の flavor: $name' : 'Current flavor: $name';
  String readingVersion() =>
      isJapanese ? 'バージョンを読み込み中...' : 'Reading app version...';

  String get homeWidgetQuickCapture => isJapanese
      ? '外部クイックメモ'
      : 'Allow external quick capture';
  String get homeWidgetQuickCaptureDesc => isJapanese
      ? 'ホームウィジェットや共有メニューから、通常のアプリロックを開かずにテキストだけの簡易メモ画面を開けます。'
      : 'Let the home widget or Android share sheet open a text-only quick memo surface without unlocking the full app.';
  String get homeWidgetQuickCaptureMobileOnly => isJapanese
      ? 'モバイルのみ。オンにすると、ホームウィジェットや共有メニューから通常のアプリロックを開かずにテキストだけの簡易メモ画面を開けます。'
      : 'Mobile-only. When enabled, the home widget or Android share sheet can open a text-only quick memo surface outside the normal app lock.';

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

  String get skip => isJapanese ? 'スキップ' : 'Skip';
  String get next => isJapanese ? '次へ' : 'Next';
  String get finishSetup => isJapanese ? 'セットアップ完了' : 'Finish setup';
  String get setAppUnlockPin => isJapanese ? 'アプリ解除 PIN を設定' : 'Set app unlock PIN';
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
  String get close => isJapanese ? '閉じる' : 'Close';
  String get sendMemo => isJapanese ? 'メモを送信' : 'Send memo';
  String get sending => isJapanese ? '送信中...' : 'Sending...';
  String get sendQuickMemo => isJapanese ? 'クイックメモを送信' : 'Send a quick memo';
  String get quickMemoSaved => isJapanese
      ? 'クイックメモを Daily Notes に保存しました。'
      : 'Quick memo saved to Daily Notes.';
  String get finishSetupFirst =>
      isJapanese ? '先に初期設定を完了してください' : 'Finish setup first';
  String get quickWidgetCaptureOff => isJapanese
      ? '外部クイックメモはオフです'
      : 'External quick capture is off';
  String get enableQuickWidgetInSettings => isJapanese
      ? '設定で外部クイックメモをオンにすると、ホームウィジェットや共有メニューからフルアプリを開かずにテキストだけのメモを送れます。'
      : 'Enable external quick capture in Settings if you want the home widget or Android share sheet to send text-only memos without unlocking the full app.';
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
