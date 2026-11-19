import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/presentation/home_providers.dart'
    show deviceAuthControllerProvider;
import '../data/sync_v2_device_transfer.dart';
import 'sync_v2_pairing_dialogs.dart';
import 'sync_v2_privacy.dart';
import 'sync_v2_workspace.dart';

final syncV2RecoveryFileWriterProvider =
    Provider<Future<bool> Function(Uint8List, String)>(
      (ref) => (bytes, title) async {
        final uri = await FilePicker.saveFile(
          dialogTitle: title,
          fileName: 'himemo-recovery.json',
          bytes: bytes,
        );
        // Browser downloads return no URI; the user must also confirm safekeeping.
        return kIsWeb || uri != null;
      },
    );

/// Device-owned ADMIN credentials and device transfer controls shared by the
/// v1 settings route and the temporary v2 setup route.
class SyncV2DeviceSecuritySettings extends ConsumerStatefulWidget {
  const SyncV2DeviceSecuritySettings({super.key});
  @override
  ConsumerState<SyncV2DeviceSecuritySettings> createState() =>
      _DeviceSecurityState();
}

class _DeviceSecurityState extends ConsumerState<SyncV2DeviceSecuritySettings>
    with WidgetsBindingObserver {
  bool _working = false, _foreground = true, _picker = false;
  int _revision = 0;
  final _routes = <DialogRoute<dynamic>>{};
  SyncV2WorkspaceController get c => ref.read(syncV2WorkspaceProvider);
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    final routes = _routes.toList();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final route in routes) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    });
    _revision++;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
      unawaited(c.resume().catchError((Object _) {}));
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached ||
        (state == AppLifecycleState.inactive &&
            !_picker &&
            !c.biometricAuthenticating &&
            !ref.read(deviceAuthControllerProvider).isAuthenticating)) {
      _foreground = false;
      _revision++;
      c.background();
      for (final route in _routes.toList()) {
        if (route.isActive) route.navigator?.removeRoute(route);
      }
    }
  }

  bool active(int revision) => mounted && _foreground && revision == _revision;

  Future<T?> dialog<T>(
    WidgetBuilder builder, {
    bool administrator = false,
  }) async {
    final controller = c;
    final route = DialogRoute<T>(
      context: context,
      builder: (context) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) =>
            administrator && !controller.canManageAdminCredentials
            ? AlertDialog(
                title: Text(t('セッションを解除してください', 'Unlock this session')),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(t('閉じる', 'Close')),
                  ),
                ],
              )
            : builder(context),
      ),
    );
    _routes.add(route);
    final privacy = ref.read(syncV2PrivacyRouteProvider.notifier);
    privacy.acquire();
    try {
      return await Navigator.of(context, rootNavigator: true).push(route);
    } finally {
      _routes.remove(route);
      privacy.release();
    }
  }

  Future<void> perform(Future<void> Function(int revision) action) async {
    if (_working || !_foreground) return;
    final revision = _revision;
    setState(() => _working = true);
    try {
      await action(revision);
    } catch (failure) {
      if (!mounted || !_foreground || revision != _revision) return;
      final code = failure is SyncV2WorkspaceException ? failure.code : '';
      if (code == 'locked' ||
          code == 'closed' ||
          code == 'authentication_cancelled') {
        return;
      }
      final message = switch (code) {
        'wrong_password' => t(
          '管理パスコードが違います。',
          'Incorrect administrator passcode.',
        ),
        'duplicate_passcode' => t(
          'プロファイルとは異なる管理パスコードを使用してください。',
          'Use an administrator passcode different from profile passcodes.',
        ),
        'throttled' => t(
          'しばらくしてから再度お試しください。',
          'Please wait before trying again.',
        ),
        'admin_required' => t(
          '管理者認証を行ってください。',
          'Authenticate as administrator first.',
        ),
        _ => t(
          '操作を完了できませんでした。入力と接続を確認してください。',
          'Could not complete the action. Check your input and connection.',
        ),
      };
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<String?> passcode({required bool confirm}) =>
      dialog<String>((_) => _AdminPasscodeDialog(confirm: confirm));

  Future<void> authenticate(int revision) async {
    if (c.canManageAdminCredentials) return;
    if (c.biometricEnabled) {
      final picker = ref.read(syncV2SystemPickerProvider.notifier);
      picker.begin();
      try {
        await c.unlockAdminBiometric();
      } finally {
        picker.end();
      }
    } else {
      final password = await passcode(confirm: false);
      if (password == null || !active(revision)) return;
      await c.unlockAdmin(password);
    }
  }

  Future<void> changePassword(int revision) async {
    await authenticate(revision);
    if (!active(revision) || !c.canManageAdminCredentials) return;
    final password = await passcode(confirm: true);
    if (password != null && active(revision)) {
      await c.configureAdminPassword(password);
    }
  }

  Future<void> enableBiometrics(int revision) async {
    await authenticate(revision);
    if (!active(revision) || !c.canManageAdminCredentials) return;
    final picker = ref.read(syncV2SystemPickerProvider.notifier);
    picker.begin();
    try {
      await c.enableAdminBiometrics();
    } finally {
      picker.end();
    }
  }

  Future<void> showQr(int revision, {bool administrator = true}) async {
    if (administrator) {
      await authenticate(revision);
      if (!active(revision) || !c.canManageAdminCredentials) return;
    }
    final transfer = await c.deviceTransfer(
      includeAdministrator: administrator,
    );
    if (!active(revision)) return;
    await dialog<void>(
      (_) => SyncV2PairingQrDialog.device(transfer: transfer),
      administrator: administrator,
    );
  }

  Future<void> withPicker(Future<void> Function() action) async {
    final picker = ref.read(syncV2SystemPickerProvider.notifier);
    _picker = true;
    picker.begin();
    try {
      await action();
    } finally {
      _picker = false;
      picker.end();
    }
  }

  Future<void> exportFile(int revision) async {
    await authenticate(revision);
    if (!active(revision) || !c.canManageAdminCredentials) return;
    final transfer = await c.deviceTransfer();
    if (!active(revision)) return;
    await saveRecoveryFile(transfer);
  }

  Future<bool> saveRecoveryFile(SyncV2DeviceTransfer transfer) async {
    var saved = false;
    final bytes = Uint8List.fromList(utf8.encode(transfer.toRecoveryFile()));
    try {
      await withPicker(() async {
        saved = await ref.read(syncV2RecoveryFileWriterProvider)(
          bytes,
          t('復元ファイルを保存', 'Save recovery file'),
        );
      });
    } finally {
      bytes.fillRange(0, bytes.length, 0);
    }
    return saved;
  }

  Future<void> startSync(int revision) async {
    // Prepared registrations survive a failed cloud confirmation. Re-enter the
    // same local passcode to resume them rather than generating another key.
    var useBiometrics = c.hasPreparedSetup && c.preparedUsesBiometrics;
    if (!c.hasPreparedSetup && c.biometricsAvailable) {
      final method = await dialog<String>(
        (context) => SimpleDialog(
          title: Text(t('この端末の管理者解除方式', 'Administrator unlock on this device')),
          children: [
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'biometric'),
              child: Text(t('生体認証', 'Biometrics')),
            ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'passcode'),
              child: Text(t('管理パスコード', 'Administrator passcode')),
            ),
          ],
        ),
      );
      if (method == null || !active(revision)) return;
      useBiometrics = method == 'biometric';
    }
    final password = useBiometrics
        ? null
        : await passcode(confirm: !c.hasPreparedSetup);
    if ((!useBiometrics && password == null) || !active(revision)) return;
    late final ({String syncCode, String adminCode}) codes;
    await withPicker(() async {
      codes = useBiometrics
          ? await c.prepareNewBiometric()
          : await c.prepareNew(password!);
    });
    if (!active(revision)) return;
    final transfer = SyncV2DeviceTransfer(
      syncCode: codes.syncCode,
      adminCode: codes.adminCode,
    );
    var saved = false, fileWritten = false, saving = false;
    final accepted = await dialog<bool>(
      (context) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text(t('復元用ファイルを保管', 'Keep your recovery file')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    '端末を失った場合の復元に必要です。このファイルを持つ人はメモにアクセスできます。安全な場所に保存してください。',
                    'You need this file if you lose your device. Anyone with it can access your notes. Save it somewhere safe.',
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: saving
                      ? null
                      : () async {
                          update(() => saving = true);
                          try {
                            final written = await saveRecoveryFile(transfer);
                            if (context.mounted && active(revision)) {
                              update(() => fileWritten = written);
                            }
                          } catch (_) {
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    t(
                                      '保存できませんでした。もう一度お試しください。',
                                      'Could not save the file. Please try again.',
                                    ),
                                  ),
                                ),
                              );
                            }
                          } finally {
                            if (context.mounted) update(() => saving = false);
                          }
                        },
                  icon: const Icon(Icons.save_alt),
                  label: Text(t('復元用ファイルを保存', 'Save recovery file')),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  value: saved,
                  onChanged: fileWritten && !saving
                      ? (value) => update(() => saved = value ?? false)
                      : null,
                  title: Text(
                    t(
                      '復元用ファイルを安全な場所に保存しました',
                      'I saved the recovery file somewhere safe',
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: saved && fileWritten && !saving
                  ? () => Navigator.pop(context, true)
                  : null,
              child: Text(t('iCloud同期を始める', 'Start iCloud sync')),
            ),
          ],
        ),
      ),
    );
    if (!active(revision)) return;
    if (accepted == true) {
      await c.confirmSetup();
    } else {
      await c.cancelSetup();
    }
  }

  Future<void> receive(SyncV2DeviceTransfer transfer, int revision) async {
    if (!active(revision)) return;
    final accepted = await dialog<bool>(
      (context) => AlertDialog(
        title: Text(t('この端末を追加', 'Add this device')),
        content: Text(
          transfer.includesAdministrator
              ? t(
                  '同期と全プロファイルの管理をこの端末で有効にします。',
                  'Enable sync and administration of every profile on this device.',
                )
              : t(
                  '同期だけを有効にします。管理者権限は追加しません。',
                  'Enable sync only, without administrator access.',
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(t('キャンセル', 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(t('続ける', 'Continue')),
          ),
        ],
      ),
    );
    if (accepted != true || !active(revision)) return;
    var biometric = false;
    String? password;
    if (transfer.includesAdministrator) {
      final method = await dialog<String>(
        (context) => SimpleDialog(
          title: Text(t('この端末の管理者解除方式', 'Administrator unlock on this device')),
          children: [
            if (c.biometricsAvailable)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(context, 'biometric'),
                child: Text(t('生体認証', 'Biometrics')),
              ),
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'passcode'),
              child: Text(t('管理パスコード', 'Administrator passcode')),
            ),
          ],
        ),
      );
      if (method == null || !active(revision)) return;
      biometric = method == 'biometric';
      if (!biometric) {
        password = await passcode(confirm: true);
        if (password == null || !active(revision)) return;
      }
    }
    final picker = ref.read(syncV2SystemPickerProvider.notifier);
    picker.begin();
    try {
      await c.recoverDeviceTransfer(
        transfer,
        adminPassword: password,
        useBiometrics: biometric,
      );
    } finally {
      picker.end();
    }
  }

  Future<void> scan(int revision) async {
    String? code;
    await withPicker(() async {
      code = await dialog<String>(
        (_) => const SyncV2PairingScannerDialog.device(),
      );
    });
    if (code != null && active(revision)) {
      await receive(SyncV2DeviceTransfer.fromQr(code!), revision);
    }
  }

  Future<void> importFile(int revision) async {
    String? data;
    await withPicker(() async {
      final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (result.length != 1) return;
      final file = result.single;
      final length = await file.length();
      if (length == null || length > SyncV2DeviceTransfer.maxFileBytes) {
        throw const FormatException('Recovery file too large');
      }
      final bytes = await file.readAsBytes();
      try {
        data = utf8.decode(bytes);
      } finally {
        bytes.fillRange(0, bytes.length, 0);
      }
    });
    if (data != null && active(revision)) {
      await receive(SyncV2DeviceTransfer.fromRecoveryFile(data!), revision);
    }
  }

  Future<void> chooseUnlockMethod(int revision) async {
    await authenticate(revision);
    if (!active(revision) || !c.canManageAdminCredentials) return;
    final method = await dialog<String>(
      (context) => SimpleDialog(
        title: Text(t('この端末の管理者解除', 'Administrator unlock on this device')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'password'),
            child: Text(
              t('管理パスコードを設定・変更', 'Set or change administrator passcode'),
            ),
          ),
          if (c.biometricsAvailable && !c.biometricEnabled)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, 'biometric'),
              child: Text(
                t(
                  '管理パスコードの代わりに生体認証を使う',
                  'Use biometrics instead of an administrator passcode',
                ),
              ),
            ),
        ],
      ),
    );
    if (!active(revision)) return;
    if (method == 'password') await changePassword(revision);
    if (method == 'biometric') {
      final accepted = await dialog<bool>(
        (context) => AlertDialog(
          title: Text(t('生体認証に切り替える', 'Switch to biometrics')),
          content: Text(
            t(
              '管理パスコードは削除されます。生体情報を変更した場合は、別の端末のQRコードか復元用ファイルが必要です。先に復元用ファイルを保存してください。',
              'Your administrator passcode will be removed. If your biometric enrollment changes, you will need another device’s QR code or your recovery file. Save a recovery file first.',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('切り替える', 'Switch')),
            ),
          ],
        ),
      );
      if (accepted == true && active(revision)) {
        await enableBiometrics(revision);
      }
    }
  }

  Future<void> restoreDevice(int revision) async {
    final source = await dialog<String>(
      (context) => SimpleDialog(
        title: Text(t('管理者権限を追加', 'Add administrator access')),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'qr'),
            child: Text(t('別の端末のQRコードを読み取る', 'Scan QR from another device')),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(context, 'file'),
            child: Text(t('復元用ファイルを読み込む', 'Open recovery file')),
          ),
        ],
      ),
    );
    if (!active(revision)) return;
    if (source == 'qr') await scan(revision);
    if (source == 'file') await importFile(revision);
  }

  String syncStatus(SyncV2WorkspaceController controller) {
    if (controller.syncing) return t('同期中…', 'Syncing…');
    if (controller.syncError != null) {
      return t(
        controller.syncError == 'account_changed'
            ? 'iCloudアカウントが変更されています。元のアカウントを確認してください。'
            : '同期できませんでした。接続状態を確認して再試行してください。',
        controller.syncError == 'account_changed'
            ? 'Your iCloud account has changed. Check the original account.'
            : 'Could not sync. Check your connection and retry.',
      );
    }
    final completed = controller.lastSyncCompletedAt;
    if (completed == null) {
      return t('メモの変更は自動で同期されます。', 'Changes to your notes sync automatically.');
    }
    final local = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(completed),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    final now = DateTime.now();
    final date = DateUtils.isSameDay(now, completed)
        ? ''
        : '${MaterialLocalizations.of(context).formatShortDate(completed)} ';
    return t('最終同期 $date$local', 'Last synced $date$local');
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(syncV2WorkspaceProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = _working || controller.busy;
        final administratorAvailable =
            controller.canManageAdminCredentials ||
            controller.biometricEnabled ||
            controller.adminPasswordConfigured;
        Widget action(
          String ja,
          String en,
          Future<void> Function(int) callback, {
          bool enabled = true,
        }) => OutlinedButton(
          onPressed: busy || !enabled ? null : () => perform(callback),
          child: Text(t(ja, en)),
        );
        Widget section(
          String title,
          String description,
          List<Widget> actions,
        ) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(description),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: actions),
            ],
          ),
        );
        if (!controller.registered) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              section(
                t('この端末を追加する', 'Add this device'),
                t(
                  'すでに使っている端末のQRコード、または復元用ファイルを使います。',
                  'Use the QR code from an existing device, or your recovery file.',
                ),
                [
                  action('QRコードを読み取る', 'Scan QR code', scan),
                  action('復元用ファイルを読み込む', 'Open recovery file', importFile),
                ],
              ),
              if (controller.hasPreparedSetup)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => perform((_) => controller.cancelSetup()),
                  child: Text(t('準備中の登録を取り消す', 'Cancel prepared setup')),
                ),
              if (controller.hasPending)
                TextButton(
                  onPressed: busy
                      ? null
                      : () => perform((_) => controller.resumePending()),
                  child: Text(
                    t(
                      '中断したiCloud登録を再開',
                      'Resume interrupted iCloud registration',
                    ),
                  ),
                ),
              TextButton(
                onPressed: busy ? null : () => perform(startSync),
                child: Text(
                  t('初めて使う：iCloud同期を始める', 'First time: set up iCloud sync'),
                ),
              ),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            section(
              t('iCloudで自動同期', 'Automatic iCloud sync'),
              syncStatus(controller),
              [
                FilledButton.icon(
                  onPressed: busy
                      ? null
                      : () => perform((_) async {
                          try {
                            await controller.syncNow();
                          } catch (_) {
                            // The persistent sync status already explains failure.
                          }
                        }),
                  icon: controller.syncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.sync),
                  label: Text(
                    controller.syncError == null
                        ? t('今すぐ同期', 'Sync now')
                        : t('同期を再試行', 'Retry sync'),
                  ),
                ),
              ],
            ),
            const Divider(),
            section(
              t('別の端末を追加する', 'Add another device'),
              t(
                '追加する端末で、この端末のQRコードを読み取ってください。',
                'Scan this device’s QR code on the device you want to add.',
              ),
              [
                action(
                  '追加用QRコードを表示',
                  'Show pairing QR',
                  (r) => showQr(r),
                  enabled: administratorAvailable,
                ),
              ],
            ),
            section(
              t('機種変更・復元に備える', 'Prepare for device replacement or recovery'),
              t(
                '復元用ファイルには同期と管理者の鍵が含まれます。安全な場所に保管してください。',
                'Your recovery file contains sync and administrator keys. Keep it somewhere safe.',
              ),
              [
                action(
                  '復元用ファイルを保存',
                  'Save recovery file',
                  exportFile,
                  enabled: administratorAvailable,
                ),
                action('管理者権限を追加', 'Add administrator access', restoreDevice),
              ],
            ),
            const Divider(),
            section(
              t('この端末の管理者解除', 'Administrator unlock on this device'),
              controller.biometricEnabled
                  ? t('生体認証', 'Biometrics')
                  : controller.adminPasswordConfigured
                  ? t('管理パスコード', 'Administrator passcode')
                  : t(
                      'この端末には管理者権限が登録されていません。',
                      'Administrator access is not registered on this device.',
                    ),
              [
                action(
                  '解除方法を変更',
                  'Change unlock method',
                  chooseUnlockMethod,
                  enabled: administratorAvailable,
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                t(
                  '管理者権限を付けずに追加する場合',
                  'Add a device without administrator access',
                ),
              ),
              children: [
                Text(
                  t(
                    '追加先でも、プロファイルのパスコードを知る人はそのプロファイルを開けます。',
                    'People who know a profile passcode can still open that profile on the added device.',
                  ),
                ),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: action(
                    '同期のみのQRコードを表示',
                    'Show sync-only QR',
                    (r) => showQr(r, administrator: false),
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _AdminPasscodeDialog extends StatefulWidget {
  const _AdminPasscodeDialog({required this.confirm});
  final bool confirm;
  @override
  State<_AdminPasscodeDialog> createState() => _PasscodeState();
}

class _PasscodeState extends State<_AdminPasscodeDialog> {
  final _password = TextEditingController(),
      _confirmation = TextEditingController();
  String? _error;
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  @override
  void dispose() {
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void submit() {
    if (_password.text.length < 4 ||
        (widget.confirm && _password.text != _confirmation.text)) {
      setState(
        () => _error = t(
          '4文字以上の一致するパスコードを入力してください。',
          'Enter matching passcodes of at least four characters.',
        ),
      );
      return;
    }
    Navigator.pop(context, _password.text);
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.confirm
          ? t('管理パスコードを設定', 'Set administrator passcode')
          : t('管理パスコード', 'Administrator passcode'),
    ),
    content: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _password,
          obscureText: true,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('管理パスコード', 'Administrator passcode'),
            errorText: _error,
          ),
          onSubmitted: (_) {
            if (!widget.confirm) submit();
          },
        ),
        if (widget.confirm)
          TextField(
            controller: _confirmation,
            obscureText: true,
            decoration: InputDecoration(labelText: t('確認', 'Confirm')),
            onSubmitted: (_) => submit(),
          ),
      ],
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: Text(t('キャンセル', 'Cancel')),
      ),
      FilledButton(onPressed: submit, child: Text(t('続ける', 'Continue'))),
    ],
  );
}
