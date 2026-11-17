import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../data/sync_v2_device_transfer.dart';
import 'sync_v2_pairing_dialogs.dart';
import 'sync_v2_privacy.dart';
import 'sync_v2_workspace.dart';

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
            !c.biometricAuthenticating)) {
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
      final message = switch (code) {
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
    final transfer = await c.deviceTransfer();
    if (!active(revision)) return;
    final bytes = Uint8List.fromList(utf8.encode(transfer.toRecoveryFile()));
    try {
      await withPicker(() async {
        await FilePicker.saveFile(
          dialogTitle: t('復元ファイルを保存', 'Save recovery file'),
          fileName: 'himemo-recovery.json',
          bytes: bytes,
        );
      });
    } finally {
      bytes.fillRange(0, bytes.length, 0);
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

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(syncV2WorkspaceProvider);
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final busy = _working || controller.busy;
        Widget action(
          String ja,
          String en,
          Future<void> Function(int) callback, {
          bool enabled = true,
          Key? key,
        }) => OutlinedButton(
          key: key,
          onPressed: busy || !enabled ? null : () => perform(callback),
          child: Text(t(ja, en)),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!controller.registered) ...[
              Text(
                t(
                  '既存の端末から追加QRを読み取るか、復元ファイルを選んでください。',
                  'Scan the add-device QR from an existing device, or choose a recovery file.',
                ),
              ),
              Wrap(
                spacing: 8,
                children: [
                  action('端末追加QRを読み取る', 'Scan add device QR', scan),
                  action('復元ファイルから追加', 'Add from recovery file', importFile),
                  TextButton(
                    onPressed: busy ? null : () => context.push('/sync-v2'),
                    child: Text(t('新しく同期を始める', 'Set up new sync')),
                  ),
                ],
              ),
            ] else ...[
              Text(
                t('この端末の管理者解除方式', 'Administrator unlock on this device'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                controller.biometricEnabled
                    ? t('生体認証', 'Biometrics')
                    : controller.adminPasswordConfigured
                    ? t('管理パスコード', 'Administrator passcode')
                    : t('管理者未登録', 'Administrator not registered'),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (!controller.canManageAdminCredentials)
                    action('管理者認証', 'Authenticate administrator', authenticate),
                  action(
                    '管理パスコードを設定・変更',
                    'Set or change administrator passcode',
                    changePassword,
                    enabled: controller.canManageAdminCredentials,
                  ),
                  action(
                    '生体認証を使う',
                    'Use biometrics',
                    enableBiometrics,
                    enabled:
                        controller.canManageAdminCredentials &&
                        controller.biometricsAvailable &&
                        !controller.biometricEnabled,
                  ),
                ],
              ),
              const Divider(),
              Text(
                t('端末を追加・復元', 'Add or recover a device'),
                style: Theme.of(context).textTheme.titleSmall,
              ),
              Text(
                t(
                  'QRと復元ファイルは全プロファイルを開く鍵を含みます。安全な場所に保管してください。',
                  'QR codes and recovery files contain keys to every profile. Keep them safe.',
                ),
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  action(
                    '端末追加QRを表示',
                    'Show add device QR',
                    (r) => showQr(r),
                    enabled: controller.canManageAdminCredentials,
                  ),
                  action(
                    '復元ファイルを保存',
                    'Save recovery file',
                    exportFile,
                    enabled: controller.canManageAdminCredentials,
                  ),
                ],
              ),
              ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: Text(t('詳細設定', 'Advanced')),
                children: [
                  Wrap(
                    spacing: 8,
                    children: [
                      action('端末追加QRから復元', 'Recover from add device QR', scan),
                      action(
                        '復元ファイルから復元',
                        'Recover from recovery file',
                        importFile,
                      ),
                    ],
                  ),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: action(
                      '管理者なしで追加（同期のみ）',
                      'Add without administrator (sync only)',
                      (r) => showQr(r, administrator: false),
                    ),
                  ),
                ],
              ),
            ],
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
