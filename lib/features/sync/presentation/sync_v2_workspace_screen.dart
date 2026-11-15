import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/sync_v2_admin_store.dart';
import 'sync_v2_workspace.dart';
import 'sync_v2_privacy.dart';

String syncV2AttachmentFileName(String label) {
  final name = label.replaceAll(r'\', '/').split('/').last;
  return name.isEmpty || name == '.' || name == '..' ? 'attachment.bin' : name;
}

/// An isolated workspace: legacy notes and sync are never edited by this screen.
class SyncV2WorkspaceScreen extends ConsumerStatefulWidget {
  const SyncV2WorkspaceScreen({super.key});
  @override
  ConsumerState<SyncV2WorkspaceScreen> createState() =>
      _SyncV2WorkspaceScreenState();
}

class _SyncV2WorkspaceScreenState extends ConsumerState<SyncV2WorkspaceScreen>
    with WidgetsBindingObserver {
  late final SyncV2WorkspaceController _controller;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _secrets = <TextEditingController>[];
  final _retired = <TextEditingController>[];
  SyncV2WorkspaceNote? _editing;
  String? _selectedVersionId;
  List<SyncV2AttachmentReference> _editingAttachments = [];
  bool _editorOpen = false;
  bool _foreground = true;
  Completer<void>? _foregroundChanged;
  bool _privacyAcquired = false;
  late final SyncV2PrivacyRoute _privacy;
  bool _pickingAttachments = false;
  bool _attachmentPickerInterrupted = false;
  final _added = <SyncV2PendingAttachment>[];
  final _removed = <String>[];
  int _dialogs = 0;
  int _backgroundVersion = 0;
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(syncV2WorkspaceProvider);
    _privacy = ref.read(syncV2PrivacyRouteProvider.notifier);
    Future.microtask(() {
      if (mounted) {
        _privacy.acquire();
        _privacyAcquired = true;
      }
    });
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() {
      if (mounted) _run(_controller.initialize);
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive &&
        _controller.biometricAuthenticating) {
      if (mounted) setState(() => _foreground = false);
      return;
    }
    if (state == AppLifecycleState.resumed) {
      if (mounted) {
        setState(() => _foreground = true);
        _foregroundChanged?.complete();
        _foregroundChanged = null;
        if (!_controller.biometricAuthenticating) _run(_controller.resume);
      }
      return;
    }
    if (state != AppLifecycleState.inactive &&
        state != AppLifecycleState.hidden &&
        state != AppLifecycleState.paused) {
      return;
    }
    if (_pickingAttachments) _attachmentPickerInterrupted = true;
    _backgroundVersion++;
    _foregroundChanged?.complete();
    _foregroundChanged = null;
    for (final field in _secrets) {
      field.clear();
    }
    _clearEditor();
    ref.read(syncV2WorkspaceProvider).background();
    while (_dialogs > 0 && mounted) {
      Navigator.of(context, rootNavigator: true).pop();
      _dialogs--;
    }
    if (mounted) setState(() => _foreground = false);
  }

  void _clearEditor() {
    _title.clear();
    _body.clear();
    _editing = null;
    _selectedVersionId = null;
    _editingAttachments = [];
    _editorOpen = false;
    _added.clear();
    _removed.clear();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _foregroundChanged?.complete();
    _foregroundChanged = null;
    _clearEditor();
    for (final secret in _secrets) {
      secret.clear();
    }
    _controller.background();
    if (_privacyAcquired) Future.microtask(_privacy.release);
    for (final controller in _retired) {
      controller.dispose();
    }
    _title.dispose();
    _body.dispose();
    super.dispose();
  }

  String _errorMessage(String code) => switch (code) {
    'icloud_account' => t(
      'iCloudにサインインしているか確認してください。登録情報は保持しています。',
      'Check that you are signed in to iCloud. Your setup is preserved.',
    ),
    'icloud_network' => t(
      'iCloudに接続できません。通信を確認して登録を再開してください。',
      'Cannot reach iCloud. Check your connection and resume setup.',
    ),
    'icloud_permission' => t(
      'iCloudの権限またはクラウド設定に問題があります。登録情報は保持しています。',
      'iCloud permission or cloud configuration failed. Your setup is preserved.',
    ),
    'icloud_quota' => t(
      'iCloudの空き容量を確認してください。',
      'Check your iCloud storage space.',
    ),
    'registration_conflict' => t(
      '既存のv2登録があります。その登録のSYNCコードで参加してください。',
      'A v2 workspace already exists. Join it with its SYNC code.',
    ),
    'biometric_unavailable' => t(
      '生体認証を利用できません。管理パスワードまたはADMINコードを使ってください。',
      'Biometrics unavailable. Use your admin password or ADMIN code.',
    ),
    'authentication_cancelled' => t(
      '生体認証をキャンセルしました。もう一度試せます。',
      'Biometric authentication cancelled. You can retry.',
    ),
    'wrong_password' => t('パスワードが一致しません。', 'Password does not match.'),
    'throttled' => t(
      '試行回数が多いため、時間をおいて再試行してください。',
      'Too many attempts. Wait before retrying.',
    ),
    'locked' => t(
      '画面が非表示になったため中断しました。もう一度操作してください。',
      'Interrupted when the app became hidden. Please retry.',
    ),
    _ => t(
      '操作を完了できませんでした。登録情報は保持しています。再試行してください。',
      'Could not complete the action. Your setup is preserved. Please retry.',
    ),
  };

  Future<T?> _dialog<T>(WidgetBuilder builder) async {
    _dialogs++;
    try {
      return await showDialog<T>(context: context, builder: builder);
    } finally {
      if (_dialogs > 0) _dialogs--;
    }
  }

  Future<void> _run(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      if (mounted && _foreground) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '操作を完了できませんでした。入力と接続を確認してください。',
                'Could not complete this action. Check your input and connection.',
              ),
            ),
          ),
        );
      }
    }
  }

  Future<String?> _input(
    String label, {
    bool secret = true,
    bool confirm = false,
    int minimum = 1,
  }) async {
    final value = TextEditingController();
    final repeated = TextEditingController();
    _secrets.addAll([value, repeated]);
    try {
      return await _dialog<String>(
        (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(label),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: value,
                  obscureText: secret,
                  enableSuggestions: false,
                  autocorrect: false,
                  onChanged: (_) => update(() {}),
                  decoration: InputDecoration(
                    labelText: label,
                    helperText: minimum > 1
                        ? t('$minimum文字以上', 'At least $minimum characters')
                        : null,
                  ),
                ),
                if (confirm)
                  TextField(
                    controller: repeated,
                    obscureText: true,
                    enableSuggestions: false,
                    autocorrect: false,
                    onChanged: (_) => update(() {}),
                    decoration: InputDecoration(
                      labelText: t('パスワードを再入力', 'Confirm password'),
                    ),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('キャンセル', 'Cancel')),
              ),
              FilledButton(
                onPressed:
                    value.text.length >= minimum &&
                        (!confirm || repeated.text == value.text)
                    ? () => Navigator.pop(context, value.text)
                    : null,
                child: Text(t('続ける', 'Continue')),
              ),
            ],
          ),
        ),
      );
    } finally {
      _secrets.remove(value);
      _secrets.remove(repeated);
      value.clear();
      repeated.clear();
      _retired.addAll([value, repeated]);
    }
  }

  Future<bool> _confirm(String title, String description) async =>
      await _dialog<bool>(
        (context) => AlertDialog(
          title: Text(title),
          content: Text(description),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(t('キャンセル', 'Cancel')),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(t('確認して続行', 'Confirm and continue')),
            ),
          ],
        ),
      ) ??
      false;
  Future<void> _register({bool passwordFallback = false}) async {
    final c = ref.read(syncV2WorkspaceProvider);
    final useBiometrics = c.hasPreparedSetup
        ? c.preparedUsesBiometrics
        : c.biometricsAvailable && !passwordFallback;
    String? password;
    if (!useBiometrics) {
      password = await _input(
        t('管理パスワード', 'Admin password'),
        confirm: !c.hasPreparedSetup,
        minimum: SyncV2AdminStore.minimumPasswordLength,
      );
      if (password == null || !mounted || !_foreground) return;
    }
    final authenticationVersion = _backgroundVersion;
    await _run(() async {
      final codes = useBiometrics
          ? await c.prepareNewBiometric()
          : await c.prepareNew(password!);
      if (useBiometrics &&
          mounted &&
          !_foreground &&
          authenticationVersion == _backgroundVersion) {
        _foregroundChanged ??= Completer<void>();
        await _foregroundChanged!.future;
      }
      if (!mounted ||
          !_foreground ||
          authenticationVersion != _backgroundVersion) {
        return;
      }
      final backgroundVersion = _backgroundVersion;
      bool syncSaved = false, adminSaved = false;
      final approved = await _dialog<bool>(
        (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(t('復元コードを別々に保管', 'Save both recovery codes')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(t('同期復元コード（SYNC）', 'Sync recovery code (SYNC)')),
                  SelectableText(codes.syncCode),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: syncSaved,
                    onChanged: (v) => update(() => syncSaved = v ?? false),
                    title: Text(
                      t('同期復元コードを保存しました', 'I saved the sync recovery code'),
                    ),
                  ),
                  Text(t('管理復元コード（ADMIN）', 'Admin recovery code (ADMIN)')),
                  SelectableText(codes.adminCode),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: adminSaved,
                    onChanged: (v) => update(() => adminSaved = v ?? false),
                    title: Text(
                      t('管理復元コードを保存しました', 'I saved the admin recovery code'),
                    ),
                  ),
                  Text(
                    t(
                      '復元コードを知る人はデータにアクセスできます。安全な場所で保管してください。',
                      'Anyone with these codes can access your data. Keep them somewhere safe.',
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
                onPressed: syncSaved && adminSaved
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(t('クラウドに登録', 'Register in cloud')),
              ),
            ],
          ),
        ),
      );
      if (backgroundVersion != _backgroundVersion) return;
      if (approved == true && mounted && _foreground) {
        await c.confirmSetup();
      } else if (mounted && _foreground) {
        await c.cancelSetup();
      }
    });
  }

  Future<void> _cancelDisplayedSetup() async {
    final c = ref.read(syncV2WorkspaceProvider);
    final confirmed = await _confirm(
      t('準備中の登録を取り消す', 'Cancel prepared setup'),
      t(
        'この端末に表示中の登録準備を取り消します。未登録の復元コードは利用できなくなります。従来のメモとクラウドのメモは変更されません。すでに保留中のクラウド登録がある場合は保持され、後で再開できます。',
        'Discard the setup currently displayed on this device. Unregistered recovery codes will no longer work. Legacy and cloud notes stay unchanged. Any pending cloud registration is retained and can be resumed.',
      ),
    );
    if (!confirmed || !mounted || !_foreground) return;
    await _run(() async {
      await c.cancelSetup();
      if (mounted) setState(() {});
    });
  }

  Future<void> _recover() async {
    final code = await _input(t('同期復元コード（SYNC）', 'Sync recovery code (SYNC)'));
    if (code != null && mounted && _foreground) {
      await _run(() => ref.read(syncV2WorkspaceProvider).recover(code));
    }
  }

  Future<void> _open(SyncV2WorkspaceNote? note) async {
    String? selectedVersionId;
    var attachments = note?.attachments ?? <SyncV2AttachmentReference>[];
    if (note?.isConflict == true) {
      final choice = await _dialog<int>(
        (context) => AlertDialog(
          title: Text(t('すべての競合バージョン', 'All conflicting versions')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < note!.versions.length; i++)
                    ListTile(
                      title: Text(
                        note.versions[i].isDeleted
                            ? t('削除されたバージョン', 'Deleted version')
                            : ((note.versions[i].body?['note']
                                          as Map?)?['title']
                                      as String? ??
                                  ''),
                      ),
                      subtitle: SelectableText(
                        note.versions[i].isDeleted
                            ? note.versions[i].change.id
                            : ((note.versions[i].body?['note'] as Map?)?['body']
                                      as String? ??
                                  t('未取得またはロック中', 'Missing or locked')),
                      ),
                      trailing: TextButton(
                        onPressed: note.ready
                            ? () => Navigator.pop(context, i)
                            : null,
                        child: Text(t('このバージョンを選択', 'Choose this version')),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(t('閉じる', 'Close')),
            ),
          ],
        ),
      );
      if (choice == null || !mounted || !_foreground) return;
      final version = note!.versions[choice];
      selectedVersionId = version.change.id;
      attachments = [
        for (final raw in (version.body?['attachments'] as List? ?? []))
          SyncV2AttachmentReference.fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
      ];
      if (version.isDeleted) {
        if (await _confirm(
          t('競合を削除で解決', 'Resolve as deleted'),
          t(
            '表示したすべてのバージョンを削除として解決します。',
            'Resolve all displayed versions as deleted.',
          ),
        )) {
          await _run(() => ref.read(syncV2WorkspaceProvider).deleteNote(note));
        }
        return;
      }
      _title.text = (version.body?['note'] as Map?)?['title'] as String? ?? '';
      _body.text = syncV2EditableBody(
        NoteEntry.fromJson(
          Map<String, dynamic>.from(version.body!['note'] as Map),
        ),
      );
    } else {
      _title.text = note?.note.title ?? '';
      _body.text = note?.note.body ?? '';
    }
    setState(() {
      _editing = note;
      _selectedVersionId = selectedVersionId;
      _editingAttachments = attachments;
      _editorOpen = true;
      _added.clear();
      _removed.clear();
    });
  }

  Future<void> _pickAttachments() async {
    _pickingAttachments = true;
    final List<PlatformFile> files;
    try {
      files = await FilePicker.pickFiles();
    } finally {
      _pickingAttachments = false;
    }

    if (!mounted || !_foreground || !_editorOpen || files.isEmpty) return;
    for (final file in files) {
      if ((await file.length() ?? 64 * 1024 * 1024 + 1) > 64 * 1024 * 1024) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                t(
                  '添付ファイルは64 MiB以下にしてください。',
                  'Each attachment must be at most 64 MiB.',
                ),
              ),
            ),
          );
        }
        continue;
      }
      final bytes = await file.readAsBytes();
      if (!mounted || !_foreground || !_editorOpen) return;
      if (bytes.length > 64 * 1024 * 1024) continue;
      _added.add(
        SyncV2PendingAttachment(
          label: file.name,
          type: AttachmentType.file,
          bytes: bytes,
        ),
      );
    }
    setState(() {});
  }

  Future<void> _import() async {
    final c = ref.read(syncV2WorkspaceProvider);
    final selected = await FilePicker.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['zip'],
    );
    if (!mounted || !_foreground || selected.isEmpty) {
      return;
    }
    final bytes = await selected.single.readAsBytes();
    final password = await _input(
      t('ZIPパスワード（空欄可）', 'ZIP password (optional)'),
      minimum: 0,
    );
    if (!mounted || !_foreground || password == null) return;
    await _run(() async {
      final inspection = await c.inspectArchive(
        bytes,
        password: password.isEmpty ? null : password,
      );
      if (!mounted || !_foreground) return;
      final destinations = <String, String>{};
      bool accept = false;
      final sources = inspection.noteCountsByProfile.keys
          .where((id) => id != 'everyday')
          .toList();
      final approved = await _dialog<bool>(
        (context) => StatefulBuilder(
          builder: (context, update) => AlertDialog(
            title: Text(t('インポート内容の確認', 'Review import')),
            content: SizedBox(
              width: 500,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (inspection.noteCountsByProfile.containsKey('everyday'))
                      Text(
                        '${t('通常', 'Normal')} · ${inspection.noteCountsByProfile['everyday']} ${t('件', 'notes')}',
                      ),
                    for (var i = 0; i < sources.length; i++)
                      DropdownButtonFormField<String>(
                        initialValue: destinations[sources[i]],
                        decoration: InputDecoration(
                          labelText:
                              '${sources[i] == 'normal' ? t('通常', 'Normal') : '${t('プライベート', 'Private')} ${i + 1}'} · ${inspection.noteCountsByProfile[sources[i]]} ${t('件', 'notes')}',
                        ),
                        items: [
                          for (final profile in c.profiles)
                            if (!profile.isNormal &&
                                !destinations.entries.any(
                                  (entry) =>
                                      entry.key != sources[i] &&
                                      entry.value == profile.id,
                                ))
                              DropdownMenuItem(
                                value: profile.id,
                                child: Text(
                                  profile.isNormal
                                      ? t('通常', 'Normal')
                                      : profile.name,
                                ),
                              ),
                        ],
                        onChanged: (v) => update(() {
                          if (v != null) destinations[sources[i]] = v;
                        }),
                      ),
                    if (inspection.notesWithUnlinkedAttachments > 0)
                      CheckboxListTile(
                        value: accept,
                        onChanged: (v) => update(() => accept = v ?? false),
                        title: Text(
                          t(
                            '未連携の添付があるメモ ${inspection.notesWithUnlinkedAttachments} 件を受け入れる',
                            'Accept ${inspection.notesWithUnlinkedAttachments} notes with unlinked attachments',
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(t('キャンセル', 'Cancel')),
              ),
              FilledButton(
                onPressed:
                    destinations.length == sources.length &&
                        (inspection.notesWithUnlinkedAttachments == 0 || accept)
                    ? () => Navigator.pop(context, true)
                    : null,
                child: Text(t('インポート', 'Import')),
              ),
            ],
          ),
        ),
      );
      if (approved == true && mounted && _foreground) {
        await c.importArchive(
          bytes: bytes,
          password: password.isEmpty ? null : password,
          destinations: destinations,
          acceptUnlinkedAttachments: accept,
        );
      }
    });
  }

  Future<void> _adminAction(String action) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (action == 'biometric-unlock') {
      await _run(c.unlockAdminBiometric);
    } else if (action == 'biometric-enable') {
      await _run(c.enableAdminBiometrics);
    } else if (action == 'biometric-recover') {
      final code = await _input(
        t('管理復元コード（ADMIN）', 'Admin recovery code (ADMIN)'),
      );
      if (code != null && mounted && _foreground) {
        await _run(() => c.recoverAdminBiometric(code));
      }
    } else if (action == 'unlock') {
      final password = await _input(t('管理パスワード', 'Admin password'));
      if (password != null && mounted && _foreground) {
        await _run(() => c.unlockAdmin(password));
      }
    } else if (action == 'recover') {
      final code = await _input(
        t('管理復元コード（ADMIN）', 'Admin recovery code (ADMIN)'),
      );
      if (code == null || !mounted || !_foreground) return;
      final password = await _input(
        t('新しい管理パスワード', 'New admin password'),
        confirm: true,
        minimum: SyncV2AdminStore.minimumPasswordLength,
      );
      if (password != null && mounted && _foreground) {
        await _run(() => c.recoverAdmin(code, password));
      }
    } else if (action == 'create') {
      final name = await _input(t('プロファイル名', 'Profile name'), secret: false);
      if (name == null || !mounted || !_foreground) return;
      final password = await _input(
        t('プライベートパスワード', 'Private password'),
        confirm: true,
        minimum: 12,
      );
      if (password != null && mounted && _foreground) {
        await _run(() => c.createProfile(name, password));
      }
    } else if (action == 'password') {
      final password = await _input(
        t('新しいプライベートパスワード', 'New private password'),
        confirm: true,
        minimum: 12,
      );
      if (password != null &&
          c.selectedProfileId != null &&
          mounted &&
          _foreground) {
        await _run(
          () => c.changeProfilePassword(c.selectedProfileId!, password),
        );
      }
    } else if (action.startsWith('repair:')) {
      final password = await _input(
        t('競合プロファイルの新しいパスワード', 'New password for conflicted profile'),
        confirm: true,
        minimum: 12,
      );
      if (password != null && mounted && _foreground) {
        await _run(
          () => c.repairProfilePassword(action.substring(7), password),
        );
      }
    } else if (action == 'codes') {
      await _run(() async {
        final codes = await c.showRecoveryCodes();
        if (!mounted || !_foreground) return;
        await _dialog<void>(
          (context) => AlertDialog(
            title: Text(t('復元コード', 'Recovery codes')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('SYNC'),
                  SelectableText(codes.syncCode),
                  if (codes.adminCode != null) ...[
                    const Text('ADMIN'),
                    SelectableText(codes.adminCode!),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(t('閉じる', 'Close')),
              ),
            ],
          ),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(syncV2WorkspaceProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: Text(t('暗号化同期 v2', 'Encrypted sync v2')),
          actions: [
            IconButton(
              onPressed: c.busy || !c.registered ? null : () => _run(c.syncNow),
              tooltip: t('同期', 'Sync'),
              icon: const Icon(Icons.sync),
            ),
          ],
        ),
        body: !_foreground
            ? const SizedBox.shrink()
            : c.loading
            ? const Center(child: CircularProgressIndicator())
            : !c.supported
            ? Center(
                child: Text(
                  t('この環境では利用できません。', 'Unavailable in this environment.'),
                ),
              )
            : Column(
                children: [
                  if (c.busy) const LinearProgressIndicator(),
                  if (_attachmentPickerInterrupted)
                    MaterialBanner(
                      content: Text(
                        t(
                          '画面が非表示になったため、編集中のメモと添付の選択を破棄しました。',
                          'The editor and attachment selection were cleared when the app became hidden.',
                        ),
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => setState(
                            () => _attachmentPickerInterrupted = false,
                          ),
                          child: Text(t('閉じる', 'Dismiss')),
                        ),
                      ],
                    ),
                  if (c.error != null)
                    MaterialBanner(
                      content: Text(
                        '${_errorMessage(c.error!)}${c.diagnosticCode == null ? '' : '\n${t('診断コード', 'Diagnostic code')}: ${c.diagnosticCode}'}',
                      ),
                      actions: [
                        TextButton(
                          onPressed: c.busy ? null : _recover,
                          child: Text(t('同期コードで復元', 'Recover with sync code')),
                        ),
                      ],
                    ),
                  Expanded(
                    child: !c.registered
                        ? Center(
                            child: SingleChildScrollView(
                              child: Padding(
                                padding: const EdgeInsets.all(24),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      t(
                                        '新しい暗号化ワークスペース',
                                        'A new encrypted workspace',
                                      ),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton(
                                      onPressed: c.busy
                                          ? null
                                          : () => _register(),
                                      child: Text(
                                        c.hasPreparedSetup
                                            ? t('登録を続ける', 'Continue setup')
                                            : c.biometricsAvailable
                                            ? t(
                                                'Face ID／Touch IDで登録',
                                                'Create with Face ID / Touch ID',
                                              )
                                            : t('新規登録', 'Create workspace'),
                                      ),
                                    ),
                                    if (c.biometricsAvailable &&
                                        !c.hasPreparedSetup)
                                      TextButton(
                                        onPressed: c.busy
                                            ? null
                                            : () => _register(
                                                passwordFallback: true,
                                              ),
                                        child: Text(
                                          t(
                                            'パスワードで登録（6文字以上）',
                                            'Create with password (6+ characters)',
                                          ),
                                        ),
                                      ),
                                    TextButton(
                                      onPressed: c.busy ? null : _recover,
                                      child: Text(
                                        t(
                                          '同期復元コードで復元',
                                          'Restore with sync recovery code',
                                        ),
                                      ),
                                    ),
                                    if (c.hasPreparedSetup)
                                      TextButton(
                                        onPressed: c.busy
                                            ? null
                                            : _cancelDisplayedSetup,
                                        child: Text(
                                          t(
                                            '準備中の登録を取り消す',
                                            'Cancel prepared setup',
                                          ),
                                        ),
                                      ),
                                    if (c.hasPending)
                                      TextButton(
                                        onPressed: c.busy
                                            ? null
                                            : () => _run(c.resumePending),
                                        child: Text(
                                          t(
                                            '保留中の登録を再開',
                                            'Resume pending registration',
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          )
                        : LayoutBuilder(
                            builder: (context, constraints) {
                              final list = Column(
                                children: [
                                  Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Wrap(
                                      spacing: 8,
                                      runSpacing: 8,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        DropdownButton<String>(
                                          value:
                                              c.profiles.any(
                                                (p) =>
                                                    p.id == c.selectedProfileId,
                                              )
                                              ? c.selectedProfileId
                                              : null,
                                          hint: Text(t('プロファイル', 'Profile')),
                                          items: [
                                            for (final p in c.profiles)
                                              DropdownMenuItem(
                                                value: p.id,
                                                child: Text(
                                                  p.isNormal
                                                      ? t('通常', 'Normal')
                                                      : p.name,
                                                ),
                                              ),
                                          ],
                                          onChanged: c.busy
                                              ? null
                                              : (v) {
                                                  if (v != null) {
                                                    setState(_clearEditor);
                                                    _run(
                                                      () => c.selectProfile(v),
                                                    );
                                                  }
                                                },
                                        ),
                                        IconButton(
                                          onPressed: c.busy
                                              ? null
                                              : () async {
                                                  final password = await _input(
                                                    t(
                                                      'プライベートパスワード',
                                                      'Private password',
                                                    ),
                                                  );
                                                  if (password != null &&
                                                      mounted &&
                                                      _foreground) {
                                                    await _run(
                                                      () => c.unlockPrivate(
                                                        password,
                                                      ),
                                                    );
                                                  }
                                                },
                                          tooltip: t(
                                            'プライベートを解除',
                                            'Unlock private',
                                          ),
                                          icon: const Icon(Icons.lock_open),
                                        ),
                                        IconButton(
                                          onPressed: c.busy
                                              ? null
                                              : () {
                                                  setState(_clearEditor);
                                                  c.lockPrivate();
                                                },
                                          tooltip: t('ロック', 'Lock'),
                                          icon: const Icon(Icons.lock),
                                        ),
                                        IconButton(
                                          onPressed:
                                              c.busy ||
                                                  c.selectedProfileId == null
                                              ? null
                                              : () => _open(null),
                                          tooltip: t('新しいメモ', 'New note'),
                                          icon: const Icon(Icons.add),
                                        ),
                                        PopupMenuButton<String>(
                                          enabled: !c.busy,
                                          onSelected: _adminAction,
                                          itemBuilder: (_) => [
                                            if (c.biometricEnabled)
                                              PopupMenuItem(
                                                value: 'biometric-unlock',
                                                child: Text(
                                                  t(
                                                    'Face ID／Touch IDで管理者認証',
                                                    'Admin with Face ID / Touch ID',
                                                  ),
                                                ),
                                              ),
                                            if (c.biometricsAvailable &&
                                                !c.biometricEnabled &&
                                                c.adminUnlocked)
                                              PopupMenuItem(
                                                value: 'biometric-enable',
                                                child: Text(
                                                  t(
                                                    '管理者の生体認証を有効にする',
                                                    'Enable admin biometrics',
                                                  ),
                                                ),
                                              ),
                                            if (c.biometricsAvailable)
                                              PopupMenuItem(
                                                value: 'biometric-recover',
                                                child: Text(
                                                  t(
                                                    'ADMINコードで生体認証を設定',
                                                    'Set up biometrics with ADMIN code',
                                                  ),
                                                ),
                                              ),
                                            PopupMenuItem(
                                              value: 'unlock',
                                              child: Text(
                                                t(
                                                  '管理を解除',
                                                  'Unlock administration',
                                                ),
                                              ),
                                            ),
                                            PopupMenuItem(
                                              value: 'recover',
                                              child: Text(
                                                t(
                                                  '管理コードで復元',
                                                  'Recover administration',
                                                ),
                                              ),
                                            ),
                                            if (c.adminUnlocked) ...[
                                              PopupMenuItem(
                                                value: 'create',
                                                child: Text(
                                                  t(
                                                    'プライベート作成',
                                                    'Create private profile',
                                                  ),
                                                ),
                                              ),
                                              PopupMenuItem(
                                                value: 'password',
                                                child: Text(
                                                  t(
                                                    '選択中のパスワード変更',
                                                    'Change selected profile password',
                                                  ),
                                                ),
                                              ),
                                              for (final conflict
                                                  in c.profileConflicts)
                                                PopupMenuItem(
                                                  value:
                                                      'repair:${conflict.id}',
                                                  child: Text(
                                                    '${t('競合を修復', 'Repair conflict')}: ${conflict.name}',
                                                  ),
                                                ),
                                              PopupMenuItem(
                                                value: 'codes',
                                                child: Text(
                                                  t(
                                                    '復元コードを表示',
                                                    'Show recovery codes',
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Expanded(
                                    child: ListView(
                                      children: [
                                        for (final note in c.notes)
                                          ListTile(
                                            selected: identical(note, _editing),
                                            title: Text(
                                              note.isDeleted
                                                  ? t('削除済み', 'Deleted')
                                                  : note.note.title,
                                            ),
                                            subtitle: Text(
                                              note.isConflict
                                                  ? t(
                                                      '競合 · バージョンを比較',
                                                      'Conflict · compare versions',
                                                    )
                                                  : !note.ready
                                                  ? t(
                                                      '未取得またはロック中 · 読み取り専用',
                                                      'Missing or locked · read only',
                                                    )
                                                  : note.note.body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            trailing: note.isConflict
                                                ? const Icon(Icons.call_split)
                                                : null,
                                            onTap: c.busy
                                                ? null
                                                : () => _open(note),
                                          ),
                                      ],
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.all(8),
                                    child: Wrap(
                                      children: [
                                        TextButton(
                                          onPressed: c.busy
                                              ? null
                                              : () => _run(_import),
                                          child: Text(
                                            t('ZIPをインポート', 'Import ZIP'),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: c.busy
                                              ? null
                                              : () async {
                                                  if (!await _confirm(
                                                        t(
                                                          '平文ZIPを書き出す',
                                                          'Export plaintext ZIP',
                                                        ),
                                                        t(
                                                          '選択中の解除済みプロファイルのメモと添付を書き出します。保存先を慎重に選んでください。',
                                                          'Export notes and attachments from the selected unlocked profile. Choose a safe destination.',
                                                        ),
                                                      ) ||
                                                      !mounted ||
                                                      !_foreground) {
                                                    return;
                                                  }
                                                  await _run(() async {
                                                    final bytes = await c
                                                        .exportArchive();
                                                    if (mounted &&
                                                        _foreground) {
                                                      await FilePicker.saveFile(
                                                        fileName: 'himemo.zip',
                                                        bytes: bytes,
                                                      );
                                                    }
                                                  });
                                                },
                                          child: Text(
                                            t('ZIPを書き出す', 'Export ZIP'),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                              if (constraints.maxWidth >= 800) {
                                return Row(
                                  children: [
                                    SizedBox(width: 340, child: list),
                                    const VerticalDivider(width: 1),
                                    Expanded(child: _editor(c)),
                                  ],
                                );
                              }
                              return _editorOpen ? _editor(c) : list;
                            },
                          ),
                  ),
                  if (c.failures.isNotEmpty)
                    ExpansionTile(
                      title: Text(
                        t(
                          '再試行が必要: ${c.failures.length}件',
                          '${c.failures.length} items need retry',
                        ),
                      ),
                      children: [
                        for (final failure in c.failures)
                          ListTile(
                            title: Text(failure.reason),
                            subtitle: Text(
                              '${failure.id} · ${failure.phase} · ${failure.attempts}',
                            ),
                            trailing: IconButton(
                              onPressed: c.busy
                                  ? null
                                  : () => _run(
                                      () => c.retryFailure(
                                        failure.id,
                                        failure.phase,
                                      ),
                                    ),
                              icon: const Icon(Icons.refresh),
                            ),
                          ),
                      ],
                    ),
                  SafeArea(
                    top: false,
                    child: TextButton(
                      onPressed: c.busy
                          ? null
                          : () => _run(() async {
                              await c.leaveV2();
                              if (context.mounted) context.go('/notes');
                            }),
                      child: Text(
                        t(
                          '従来のメモに戻る（データは保持）',
                          'Return to legacy notes (keep data)',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _editor(SyncV2WorkspaceController c) {
    if (!_editorOpen) {
      return Center(
        child: Text(t('メモを選択、または作成してください', 'Select or create a note')),
      );
    }
    final writable = !c.busy && (_editing?.ready ?? true);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: c.busy ? null : () => setState(_clearEditor),
              icon: const Icon(Icons.arrow_back),
              label: Text(t('一覧', 'Notes')),
            ),
          ),
          TextField(
            key: const Key('sync-v2-title'),
            controller: _title,
            readOnly: !writable,
            decoration: InputDecoration(labelText: t('タイトル', 'Title')),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('sync-v2-body'),
            controller: _body,
            readOnly: !writable,
            minLines: 8,
            maxLines: null,
            decoration: InputDecoration(
              labelText: t('本文', 'Body'),
              border: const OutlineInputBorder(),
            ),
          ),
          for (final attachment in _editingAttachments)
            if (!_removed.contains(attachment.id))
              ListTile(
                title: Text(attachment.label),
                subtitle: Text('${attachment.size} bytes'),
                trailing: Wrap(
                  children: [
                    IconButton(
                      onPressed: writable
                          ? () => _run(() async {
                              final bytes = await c.readAttachment(attachment);
                              if (mounted && _foreground) {
                                await FilePicker.saveFile(
                                  fileName: syncV2AttachmentFileName(
                                    attachment.label,
                                  ),
                                  bytes: bytes,
                                );
                              }
                            })
                          : null,
                      icon: const Icon(Icons.download),
                    ),
                    IconButton(
                      onPressed: writable
                          ? () => setState(() => _removed.add(attachment.id))
                          : null,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
          for (var i = 0; i < _added.length; i++)
            ListTile(
              title: Text(_added[i].label),
              trailing: IconButton(
                onPressed: writable
                    ? () => setState(() => _added.removeAt(i))
                    : null,
                icon: const Icon(Icons.close),
              ),
            ),
          Wrap(
            spacing: 8,
            children: [
              TextButton.icon(
                onPressed: writable ? () => _run(_pickAttachments) : null,
                icon: const Icon(Icons.attach_file),
                label: Text(t('添付（64 MiBまで）', 'Attach (up to 64 MiB)')),
              ),
              FilledButton(
                onPressed: writable
                    ? () => _run(() async {
                        await c.saveNote(
                          original: _editing,
                          selectedVersionId: _selectedVersionId,
                          title: _title.text,
                          body: _body.text,
                          addedFiles: List.of(_added),
                          removedAttachmentIds: List.of(_removed),
                        );
                        if (mounted) setState(_clearEditor);
                      })
                    : null,
                child: Text(t('保存', 'Save')),
              ),
              if (_editing != null)
                TextButton(
                  onPressed: writable
                      ? () async {
                          if (await _confirm(
                                t('メモを削除', 'Delete note'),
                                t('このメモを削除しますか？', 'Delete this note?'),
                              ) &&
                              mounted &&
                              _foreground) {
                            await _run(() async {
                              await c.deleteNote(_editing!);
                              if (mounted) setState(_clearEditor);
                            });
                          }
                        }
                      : null,
                  child: Text(t('削除', 'Delete')),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
