import 'dart:async';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import '../../home/presentation/home_page.dart'
    show HomeNotePreviewList, HomeBrandTitle, HomeNoteSection;
import '../../home/presentation/home_providers.dart'
    show NotesListDensity, NotesListSortField;
import '../../security/data/sync_v2_admin_store.dart';
import 'sync_v2_workspace.dart';
import 'sync_v2_privacy.dart';
import 'sync_v2_pairing_dialogs.dart';
import 'sync_v2_original_editor.dart';
import 'sync_v2_attachment_image.dart';
import 'sync_v2_attachment_viewer.dart';

/// The default uses the camera. Tests can supply a deterministic scanner.
final syncV2PairingScannerBuilderProvider = Provider<Widget Function(bool)>(
  (ref) =>
      (administrator) =>
          SyncV2PairingScannerDialog(administrator: administrator),
);

enum SyncV2DisplayStyle { original, simple }

const syncV2DisplayStylePreference = 'settings.sync_v2.display_style';
const _syncV2AdminMenuRoute = 'sync-v2-admin-menu';

String syncV2AttachmentFileName(String label) {
  final name = label.replaceAll(r'\', '/').split('/').last;
  return name.isEmpty || name == '.' || name == '..' ? 'attachment.bin' : name;
}

void _closeSyncV2DialogRoutes(Iterable<Route<dynamic>> routes) {
  for (final route in routes.toList().reversed) {
    final navigator = route.navigator;
    if (navigator == null || !navigator.mounted || !route.isActive) continue;
    // Remove only our own route. Disposing its DropdownButton also dismisses
    // its menu, while unrelated pages on the navigator stay untouched.
    navigator.removeRoute(route);
  }
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
  late final SyncV2AttachmentViewer _attachmentViewer;
  bool _openingAttachment = false;
  bool _openingNativeAttachment = false;
  int _attachmentViewRevision = 0;
  late int _knownSessionRevision;
  String? _knownProfileId;
  final _title = TextEditingController();
  final _body = TextEditingController();
  final _search = TextEditingController();
  bool _originalDesign = true;
  bool _compactList = false;
  bool _sortByCreated = true;
  String _query = '';
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
  late final SyncV2SystemPicker _systemPicker;
  bool _pickingAttachments = false;
  bool _pickingArchive = false;
  bool _scanningPairing = false;
  bool _attachmentPickerInterrupted = false;
  final _added = <SyncV2PendingAttachment>[];
  final _removed = <String>[];
  final _dialogRoutes = <Route<dynamic>>[];
  final _attachmentDialogRoutes = <Route<dynamic>>[];
  int _backgroundVersion = 0;
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  @override
  void initState() {
    super.initState();
    _controller = ref.read(syncV2WorkspaceProvider);
    _attachmentViewer = ref.read(syncV2AttachmentViewerProvider);
    _knownSessionRevision = _controller.privateSessionRevision;
    _knownProfileId = _controller.selectedProfileId;
    _controller.addListener(_workspaceSessionChanged);
    _privacy = ref.read(syncV2PrivacyRouteProvider.notifier);
    _systemPicker = ref.read(syncV2SystemPickerProvider.notifier);
    Future.microtask(() {
      if (mounted) {
        _privacy.acquire();
        _privacyAcquired = true;
      }
    });
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(_loadDisplayStyle);
    Future.microtask(() {
      if (mounted) _run(_controller.initialize);
    });
  }

  void _workspaceSessionChanged() {
    final changed =
        _knownSessionRevision != _controller.privateSessionRevision ||
        _knownProfileId != _controller.selectedProfileId;
    _knownSessionRevision = _controller.privateSessionRevision;
    _knownProfileId = _controller.selectedProfileId;
    if (changed && mounted) {
      unawaited(_attachmentViewer.close());
      _closeSyncV2DialogRoutes(List.of(_attachmentDialogRoutes));
      setState(() {
        _clearEditor();
        _clearSearch();
      });
      // Close only our own popup; unrelated dialogs/pages stay untouched.
      Navigator.maybeOf(context)
          ?.popUntil((route) => route.settings.name != _syncV2AdminMenuRoute);
    }
  }

  Future<void> _loadDisplayStyle() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final style = preferences.getString(syncV2DisplayStylePreference);
      if (mounted) setState(() => _originalDesign = style != 'simple');
    } catch (_) {
      // Presentation remains usable if the optional local preference is absent.
    }
  }

  Future<void> _setDisplayStyle(SyncV2DisplayStyle style) async {
    await _run(() async {
      final preferences = await SharedPreferences.getInstance();
      if (!await preferences.setString(
        syncV2DisplayStylePreference,
        style.name,
      )) {
        throw StateError('Could not save display preference');
      }
      if (mounted) {
        setState(() => _originalDesign = style == SyncV2DisplayStyle.original);
      }
    });
  }

  void _clearSearch() {
    _search.clear();
    _query = '';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive &&
        (_controller.biometricAuthenticating ||
            _pickingArchive ||
            _scanningPairing)) {
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
    _clearSearch();
    unawaited(_attachmentViewer.close());
    ref.read(syncV2WorkspaceProvider).background();
    _closeSyncV2DialogRoutes(List.of(_dialogRoutes));
    _dialogRoutes.clear();
    if (mounted) setState(() => _foreground = false);
  }

  void _clearEditor() {
    _attachmentViewRevision++;
    unawaited(_attachmentViewer.close());
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
    _controller.removeListener(_workspaceSessionChanged);
    unawaited(_attachmentViewer.close());
    final picker = _systemPicker;
    final routes = List<Route<dynamic>>.of(_dialogRoutes);
    _dialogRoutes.clear();
    // Keep privacy protection acquired until the route cleanup and key lock
    // complete, without notifying dialog listeners while the tree is locked.
    scheduleMicrotask(() {
      picker.end();
      _closeSyncV2DialogRoutes(routes);
      _controller.background();
    });
    _foregroundChanged?.complete();
    _foregroundChanged = null;
    _clearEditor();
    for (final secret in _secrets) {
      secret.clear();
    }
    if (_privacyAcquired) Future.microtask(_privacy.release);
    for (final controller in _retired) {
      controller.dispose();
    }
    _title.dispose();
    _body.dispose();
    _search.dispose();
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
    'admin_required' => t(
      '設定で管理者モードに入るか、v2の管理者認証を行ってください。',
      'Enter admin mode in Settings or authenticate as a v2 administrator.',
    ),
    'wrong_password' => t('パスワードが一致しません。', 'Password does not match.'),
    'sync_required' => t(
      '同期途中の情報を取得できませんでした。接続を確認して一括復元を再試行してください。',
      'Some sync history is still unavailable. Check your connection and retry administrator restore.',
    ),
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

  Future<T?> _dialog<T>(
    WidgetBuilder builder, {
    bool attachment = false,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    final route = DialogRoute<T>(
      context: context,
      builder: builder,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
    );
    _dialogRoutes.add(route);
    if (attachment) _attachmentDialogRoutes.add(route);
    try {
      return await navigator.push(route);
    } finally {
      _dialogRoutes.remove(route);
      _attachmentDialogRoutes.remove(route);
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

  Future<void> _scanPairing({bool administrator = false}) async {
    if (_scanningPairing || !_foreground) return;
    final c = ref.read(syncV2WorkspaceProvider);
    if (!c.supported || c.busy || (administrator && !c.registered)) return;
    final version = _backgroundVersion;
    final builder = ref.read(syncV2PairingScannerBuilderProvider);
    _scanningPairing = true;
    _systemPicker.begin();
    String? code;
    try {
      code = await _dialog<String>((_) => builder(administrator));
      if (mounted && !_foreground && version == _backgroundVersion) {
        _foregroundChanged ??= Completer<void>();
        await _foregroundChanged!.future;
      }
    } finally {
      _scanningPairing = false;
      _systemPicker.end();
    }
    if (code == null ||
        !mounted ||
        !_foreground ||
        version != _backgroundVersion) {
      return;
    }
    final confirmed = await _confirm(
      administrator
          ? t('管理者としてこの端末を登録', 'Register this device as administrator')
          : t('既存のワークスペースに参加', 'Join the existing workspace'),
      administrator
          ? t(
              'この端末の生体認証で私用メモを管理できるようにします。',
              'Allow this device to manage private notes with biometric authentication.',
            )
          : t(
              '同じiCloudアカウントのメモを同期します。私用メモの管理者登録は別に行います。',
              'Sync notes using the same iCloud account. Administrator access to private notes is registered separately.',
            ),
    );
    if (!confirmed ||
        !mounted ||
        !_foreground ||
        version != _backgroundVersion) {
      return;
    }
    await _run(
      () => administrator ? c.recoverAdminBiometric(code!) : c.recover(code!),
    );
  }

  Future<void> _showPairingQr({bool administrator = false}) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (c.busy || !c.registered) return;
    final version = _backgroundVersion;
    await _run(() async {
      final codes = await c.showRecoveryCodes();
      if (!mounted || !_foreground || version != _backgroundVersion) return;
      final code = administrator ? codes.adminCode : codes.syncCode;
      if (code == null) throw const SyncV2WorkspaceException('admin_required');
      await _dialog<void>(
        (_) => SyncV2PairingQrDialog(code: code, administrator: administrator),
      );
    });
  }

  Future<void> _recover() async {
    final code = await _input(t('同期復元コード（SYNC）', 'Sync recovery code (SYNC)'));
    if (code != null && mounted && _foreground) {
      await _run(() => ref.read(syncV2WorkspaceProvider).recover(code));
    }
  }

  Future<void> _open(SyncV2WorkspaceNote? note) async {
    _attachmentViewRevision++;
    unawaited(_attachmentViewer.close());
    FocusScope.of(context).unfocus();
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

  bool Function() _attachmentSessionIsActive({bool bindView = false}) {
    final epoch = _controller.privateSessionRevision;
    final profile = _controller.selectedProfileId;
    final version = _backgroundVersion;
    final view = _attachmentViewRevision;
    return () =>
        mounted &&
        _foreground &&
        epoch == _controller.privateSessionRevision &&
        profile == _controller.selectedProfileId &&
        version == _backgroundVersion &&
        (!bindView || view == _attachmentViewRevision);
  }

  Future<void> _nativeAttachment(
    SyncV2AttachmentReference attachment,
    bool Function() active,
  ) async {
    if (_openingNativeAttachment || !active()) return;
    setState(() => _openingNativeAttachment = true);
    Uint8List? bytes;
    try {
      bytes = await _controller.readAttachmentPreview(
        attachment,
        isActive: active,
      );
      if (!active()) return;
      await _attachmentViewer.open(
        bytes: bytes,
        label: syncV2AttachmentFileName(attachment.label),
      );
    } finally {
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      if (mounted) setState(() => _openingNativeAttachment = false);
    }
  }

  Future<void> _openAttachment(SyncV2AttachmentReference attachment) async {
    if (_openingAttachment ||
        _openingNativeAttachment ||
        !_foreground ||
        _controller.busy) {
      return;
    }
    final sessionActive = _attachmentSessionIsActive(bindView: true);
    var ownerOpen = true;
    bool active() => ownerOpen && sessionActive();
    _openingAttachment = true;
    try {
      if (attachment.type == 'photo') {
        await _dialog<void>(
          (context) => Dialog(
            child: SizedBox(
              width: 800,
              height: MediaQuery.sizeOf(context).height * .82,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            syncV2AttachmentFileName(attachment.label),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: t('閉じる', 'Close'),
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ],
                  ),
                  Expanded(
                    child: SyncV2AttachmentImage(
                      key: ValueKey((
                        'full-photo',
                        _controller.privateSessionRevision,
                        attachment.id,
                      )),
                      label: attachment.label,
                      thumbnail: false,
                      isActive: active,
                      loadBytes: (isCurrent) =>
                          _controller.readAttachmentPreview(
                            attachment,
                            isActive: isCurrent,
                          ),
                      onUnsupported: () => unawaited(
                        _viewAttachmentAction(
                          () => _nativeAttachment(attachment, active),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          attachment: true,
        );
      } else {
        await _nativeAttachment(attachment, active);
      }
    } catch (failure) {
      if (active()) _attachmentViewError(failure);
    } finally {
      ownerOpen = false;
      if (attachment.type == 'photo') unawaited(_attachmentViewer.close());
      _openingAttachment = false;
    }
  }

  void _attachmentViewError(Object failure) {
    if (!mounted || !_foreground) return;
    if (failure is SyncV2AttachmentViewerException &&
        failure.code == 'cancelled') {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          t(
            'この添付を表示できません。ダウンロードして確認してください。',
            'Could not display this attachment. Download it to open it.',
          ),
        ),
      ),
    );
  }

  Future<void> _viewAttachmentAction(Future<void> Function() action) async {
    try {
      await action();
    } catch (failure) {
      _attachmentViewError(failure);
    }
  }

  Widget _attachmentPreview(
    SyncV2AttachmentReference attachment,
    double size, {
    bool inline = false,
    bool autoLoad = true,
  }) {
    final active = _attachmentSessionIsActive();
    if (autoLoad &&
        attachment.type == 'photo' &&
        attachment.size <= 4 * 1024 * 1024) {
      final image = SyncV2AttachmentImage(
        key: ValueKey((
          'photo',
          _controller.privateSessionRevision,
          _controller.selectedProfileId,
          attachment.id,
          inline,
        )),
        label: attachment.label,
        size: inline ? null : size,
        thumbnail: !inline,
        decodeWidth: inline ? 512 : null,
        isActive: active,
        loadBytes: (isCurrent) =>
            _controller.readAttachmentPreview(attachment, isActive: isCurrent),
        onTap: () => unawaited(_openAttachment(attachment)),
        onUnsupported: () => unawaited(
          _viewAttachmentAction(
            () => _nativeAttachment(
              attachment,
              _attachmentSessionIsActive(bindView: true),
            ),
          ),
        ),
      );
      return inline
          ? GestureDetector(
              onTap: () => _openAttachment(attachment),
              child: SizedBox(height: 240, child: image),
            )
          : image;
    }
    final icon = switch (attachment.type) {
      'photo' => Icons.image_outlined,
      'video' => Icons.play_circle_outline,
      'audio' => Icons.headphones_outlined,
      _ => Icons.insert_drive_file_outlined,
    };
    return SizedBox(
      width: inline ? null : size,
      height: inline ? 80 : size,
      child: Material(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: () => _openAttachment(attachment),
          child: Center(child: Icon(icon, size: inline ? 40 : 28)),
        ),
      ),
    );
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
    final picker = _systemPicker;
    final pickerVersion = _backgroundVersion;
    _pickingArchive = true;
    picker.begin();
    final List<PlatformFile> selected;
    try {
      selected = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['zip'],
      );
      // iOS can return the document before delivering resumed. Keep the
      // selection until that event; an actual background invalidates it.
      if (mounted && !_foreground && pickerVersion == _backgroundVersion) {
        _foregroundChanged ??= Completer<void>();
        await _foregroundChanged!.future;
      }
    } finally {
      _pickingArchive = false;
      picker.end();
    }
    if (!mounted ||
        !_foreground ||
        pickerVersion != _backgroundVersion ||
        selected.isEmpty) {
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
      final version = _backgroundVersion;
      var reviewing = true;
      bool active() =>
          mounted && _foreground && version == _backgroundVersion && reviewing;
      Future<void> waitForBiometricResume() async {
        if (mounted && !_foreground && version == _backgroundVersion) {
          _foregroundChanged ??= Completer<void>();
          await _foregroundChanged!.future;
        }
      }

      Future<void> unlockAdminByPassword() async {
        if (!active()) return;
        final password = await _input(t('管理パスワード', 'Admin password'));
        if (password != null && active()) {
          await _run(() => c.unlockAdmin(password));
        }
      }

      Future<void> unlockAdmin() async {
        if (!active() || c.adminUnlocked) return;
        if (c.settingsAdminActive && await c.unlockAdminFromSettings()) return;
        if (c.biometricEnabled) {
          await _run(c.unlockAdminBiometric);
          await waitForBiometricResume();
        } else {
          await unlockAdminByPassword();
        }
      }

      final SyncV2ImportSelection? selection;
      try {
        selection = await _dialog<SyncV2ImportSelection>(
          (_) => SyncV2ImportReviewDialog(
            controller: c,
            inspection: inspection,
            isActive: active,
            errorMessage: _errorMessage,
            unlockAdmin: unlockAdmin,
            unlockAdminWithPassword: unlockAdminByPassword,
            unlockPrivate: () async {
              final password = await _input(
                t('プライベートパスワード', 'Private password'),
              );
              if (password != null && active()) {
                await _run(() => c.unlockPrivate(password));
              }
            },
            recoverAdmin: () async {
              final code = await _input(
                t('管理復元コード（ADMIN）', 'Admin recovery code (ADMIN)'),
              );
              if (code != null && active()) {
                await _run(() => c.recoverAdminBiometric(code));
                await waitForBiometricResume();
              }
            },
            createDestination: () async {
              await unlockAdmin();
              if (!active() || !c.adminUnlocked) return null;
              final name = await _input(
                t('プロファイル名', 'Profile name'),
                secret: false,
              );
              if (name == null || !active()) return null;
              final password = await _input(
                t('プライベートパスワード', 'Private password'),
                confirm: true,
                minimum: 12,
              );
              if (password == null || !active()) return null;
              final previous = c.selectedProfileId;
              await _run(() => c.createProfile(name, password));
              if (!active()) return null;
              final created = c.selectedProfileId;
              return created != previous ? created : null;
            },
          ),
        );
      } finally {
        reviewing = false;
      }
      if (selection != null &&
          mounted &&
          _foreground &&
          version == _backgroundVersion) {
        if (selection.administratorOverwrite) {
          await c.adminImportArchive(
            bytes: bytes,
            password: password.isEmpty ? null : password,
            inspection: inspection,
          );
        } else {
          await c.importArchive(
            bytes: bytes,
            password: password.isEmpty ? null : password,
            destinations: selection.destinations,
            acceptUnlinkedAttachments: selection.acceptUnlinkedAttachments,
          );
        }
        if (mounted && _foreground) setState(_clearEditor);
      }
    });
  }

  Future<void> _adminAction(String action) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (action == 'sync-qr') {
      await _showPairingQr();
    } else if (action == 'admin-qr') {
      await _showPairingQr(administrator: true);
    } else if (action == 'admin-scan') {
      await _scanPairing(administrator: true);
    } else if (action == 'biometric-unlock') {
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
          toolbarHeight: _originalDesign && c.registered
              ? (MediaQuery.textScalerOf(context).scale(22) +
                        MediaQuery.textScalerOf(context).scale(12) +
                        20)
                    .clamp(kToolbarHeight, double.infinity)
              : null,
          title: _originalDesign && c.registered
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const HomeBrandTitle(),
                    if (_foreground)
                      Text(
                        c.profiles
                                    .where((p) => p.id == c.selectedProfileId)
                                    .firstOrNull
                                    ?.isNormal ==
                                true
                            ? t('通常', 'Normal')
                            : c.profiles
                                      .where((p) => p.id == c.selectedProfileId)
                                      .firstOrNull
                                      ?.name ??
                                  '',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                  ],
                )
              : Text(t('暗号化同期 v2', 'Encrypted sync v2')),
          actions: [
            if (c.registered)
              PopupMenuButton<SyncV2DisplayStyle>(
                key: const ValueKey('sync-v2-display-style'),
                tooltip: t('表示デザイン', 'Display design'),
                icon: const Icon(Icons.view_agenda_outlined),
                onSelected: _setDisplayStyle,
                itemBuilder: (_) => [
                  for (final style in SyncV2DisplayStyle.values)
                    PopupMenuItem(
                      value: style,
                      child: Row(
                        children: [
                          Icon(
                            (_originalDesign ==
                                    (style == SyncV2DisplayStyle.original))
                                ? Icons.radio_button_checked
                                : Icons.radio_button_off,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            style == SyncV2DisplayStyle.original
                                ? t('従来のデザイン', 'Original design')
                                : t('簡易表示', 'Simple view'),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
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
                  if (c.busy || _openingNativeAttachment)
                    const LinearProgressIndicator(),
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
                                      t('暗号化同期を始める', 'Set up encrypted sync'),
                                      style: Theme.of(context)
                                          .textTheme
                                          .headlineSmall,
                                    ),
                                    const SizedBox(height: 16),
                                    FilledButton.icon(
                                      key: const ValueKey('sync-v2-scan-join'),
                                      onPressed: c.busy || !c.supported
                                          ? null
                                          : () => _scanPairing(),
                                      icon: const Icon(Icons.qr_code_scanner),
                                      label: Text(
                                        t('QRを読み取って参加', 'Join by scanning QR'),
                                      ),
                                    ),
                                    const SizedBox(height: 12),
                                    Text(
                                      t('初めて利用する場合', 'For your first device'),
                                    ),
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
                              final controls = Padding(
                                padding: EdgeInsets.all(
                                  _originalDesign ? 0 : 12,
                                ),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  children: [
                                    DropdownButton<String>(
                                      value:
                                          c.profiles.any(
                                            (p) => p.id == c.selectedProfileId,
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
                                                setState(() {
                                                  _clearEditor();
                                                  _clearSearch();
                                                });
                                                _run(() => c.selectProfile(v));
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
                                                  () =>
                                                      c.unlockPrivate(password),
                                                );
                                              }
                                            },
                                      tooltip: t('プライベートを解除', 'Unlock private'),
                                      icon: const Icon(Icons.lock_open),
                                    ),
                                    IconButton(
                                      onPressed: c.busy
                                          ? null
                                          : () {
                                              setState(() {
                                                _clearEditor();
                                                _clearSearch();
                                              });
                                              c.lockPrivate();
                                            },
                                      tooltip: t('ロック', 'Lock'),
                                      icon: const Icon(Icons.lock),
                                    ),
                                    IconButton(
                                      onPressed:
                                          c.busy || c.selectedProfileId == null
                                          ? null
                                          : () => _open(null),
                                      tooltip: t('新しいメモ', 'New note'),
                                      icon: const Icon(Icons.add),
                                    ),
                                    PopupMenuButton<String>(
                                      routeSettings: const RouteSettings(
                                        name: _syncV2AdminMenuRoute,
                                      ),
                                      enabled: !c.busy,
                                      onSelected: _adminAction,
                                      itemBuilder: (_) => [
                                        PopupMenuItem(
                                          value: 'sync-qr',
                                          child: Text(
                                            t(
                                              '他の端末をQRで追加',
                                              'Add another device with QR',
                                            ),
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
                                        if (c.canManageAdminCredentials)
                                          PopupMenuItem(
                                            value: 'admin-qr',
                                            child: Text(
                                              t(
                                                '管理者登録用QRを表示',
                                                'Show administrator QR',
                                              ),
                                            ),
                                          ),
                                        if (c.biometricsAvailable)
                                          PopupMenuItem(
                                            value: 'admin-scan',
                                            child: Text(
                                              t(
                                                '管理者登録用QRを読み取る',
                                                'Scan administrator QR',
                                              ),
                                            ),
                                          ),
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
                                            c.canManageAdminCredentials)
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
                                            t('管理を解除', 'Unlock administration'),
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
                                          if (c.canManageAdminCredentials)
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
                                              in c.canManageAdminCredentials
                                                  ? c.profileConflicts
                                                  : const <
                                                      SyncV2WorkspaceProfile
                                                    >[])
                                            PopupMenuItem(
                                              value: 'repair:${conflict.id}',
                                              child: Text(
                                                '${t('競合を修復', 'Repair conflict')}: ${conflict.name}',
                                              ),
                                            ),
                                        ],
                                      ],
                                    ),
                                  ],
                                ),
                              );
                              final profileControls = KeyedSubtree(
                                key: ValueKey((
                                  'profile-controls',
                                  c.privateSessionRevision,
                                  c.selectedProfileId,
                                )),
                                child: controls,
                              );
                              final list = Column(
                                children: [
                                  if (!_originalDesign) profileControls,
                                  Expanded(
                                    child: _noteList(
                                      c,
                                      header: _originalDesign
                                          ? Column(
                                              children: [
                                                profileControls,
                                                _originalSearchToolbar(c),
                                              ],
                                            )
                                          : null,
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
                              if (constraints.maxWidth >=
                                  (_originalDesign ? 1180 : 800)) {
                                return Row(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SizedBox(
                                      width: _originalDesign
                                          ? (constraints.maxWidth * 5 / 11)
                                                .clamp(
                                                  320.0,
                                                  constraints.maxWidth * .62,
                                                )
                                          : 340,
                                      child: list,
                                    ),
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
                          '旧データの画面に戻る（v2同期を終了）',
                          'Open legacy data (leave v2 sync)',
                        ),
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  List<SyncV2WorkspaceNote> _visibleNotes(SyncV2WorkspaceController c) {
    final query = _query.trim().toLowerCase();
    final result = c.notes.where((entry) {
      return query.isEmpty ||
          entry.note.title.toLowerCase().contains(query) ||
          entry.note.body.toLowerCase().contains(query) ||
          entry.note.normalizedTags.any(
            (tag) => tag.toLowerCase().contains(query),
          );
    }).toList();
    result.sort((a, b) {
      if (a.note.isPinned != b.note.isPinned) return a.note.isPinned ? -1 : 1;
      final am = _sortByCreated
          ? a.note.createdAt
          : a.note.updatedAt ?? a.note.createdAt;
      final bm = _sortByCreated
          ? b.note.createdAt
          : b.note.updatedAt ?? b.note.createdAt;
      final compared = bm.compareTo(am);
      return compared == 0 ? a.note.id.compareTo(b.note.id) : compared;
    });
    return result;
  }

  Widget _originalSearchToolbar(SyncV2WorkspaceController c) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: HomeNoteSection(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          KeyedSubtree(
            // Retire TextField undo history together with its private session.
            key: ValueKey((c.privateSessionRevision, c.selectedProfileId)),
            child: TextField(
              key: const ValueKey('sync-v2-search'),
              controller: _search,
              onChanged: (value) => setState(() => _query = value),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: t('メモを検索', 'Search notes'),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _query.isEmpty
                    ? null
                    : IconButton(
                        tooltip: t('検索をクリア', 'Clear search'),
                        icon: const Icon(Icons.close_rounded),
                        onPressed: () => setState(_clearSearch),
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text(
                t(
                  '${_visibleNotes(c).length}件',
                  '${_visibleNotes(c).length} notes',
                ),
              ),
              DropdownButton<bool>(
                key: const ValueKey('sync-v2-sort'),
                value: _sortByCreated,
                underline: const SizedBox.shrink(),
                onChanged: (value) {
                  if (value != null) setState(() => _sortByCreated = value);
                },
                items: [
                  DropdownMenuItem(
                    value: true,
                    child: Text(t('作成日時', 'Created date')),
                  ),
                  DropdownMenuItem(
                    value: false,
                    child: Text(t('更新日時', 'Updated date')),
                  ),
                ],
              ),
              IconButton(
                key: const ValueKey('sync-v2-density'),
                tooltip: _compactList
                    ? t('標準表示', 'Standard list')
                    : t('コンパクト表示', 'Compact list'),
                icon: Icon(
                  _compactList
                      ? Icons.view_agenda_outlined
                      : Icons.view_headline_rounded,
                ),
                onPressed: () => setState(() => _compactList = !_compactList),
              ),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _noteList(SyncV2WorkspaceController c, {Widget? header}) {
    if (!_originalDesign) {
      return ListView(
        children: [
          for (final note in c.notes)
            ListTile(
              title: Text(
                note.isDeleted ? t('削除済み', 'Deleted') : note.note.title,
              ),
              subtitle: Text(
                note.isConflict
                    ? t('競合 · バージョンを比較', 'Conflict · compare versions')
                    : !note.ready
                    ? t('未取得またはロック中 · 読み取り専用', 'Missing or locked · read only')
                    : note.note.body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: note.isConflict ? const Icon(Icons.call_split) : null,
              onTap: c.busy ? null : () => _open(note),
            ),
        ],
      );
    }
    final entries = _visibleNotes(c);
    final byId = {for (final entry in entries) entry.note.id: entry};
    final profile = c.profiles
        .where((p) => p.id == c.selectedProfileId)
        .firstOrNull;
    return HomeNotePreviewList(
      header: header,
      attachmentPreviewBuilder: (note, index, size) {
        final entry = byId[note.id]!;
        if (!entry.ready || index >= entry.attachments.length) {
          return SizedBox.square(dimension: size);
        }
        return _attachmentPreview(entry.attachments[index], size);
      },
      notes: [
        for (final entry in entries)
          entry.note.copyWith(
            title: entry.isDeleted ? t('削除済み', 'Deleted') : entry.note.title,
            body: entry.isDeleted ? '' : entry.note.body,
            syncState: entry.isConflict
                ? NoteSyncState.conflict
                : entry.note.syncState,
            attachments: [
              for (final attachment in entry.attachments)
                NoteAttachment(
                  type: AttachmentType.values.byName(attachment.type),
                  label: attachment.label,
                ),
            ],
          ),
      ],
      profileName: profile?.isNormal == true
          ? t('通常', 'Normal')
          : profile?.name ?? '',
      selectedNoteId: _editing?.note.id,
      query: _query,
      density: _compactList
          ? NotesListDensity.compact
          : NotesListDensity.standard,
      sortField: _sortByCreated
          ? NotesListSortField.createdAt
          : NotesListSortField.updatedAt,
      onNoteSelected: (note) {
        if (!c.busy) _open(byId[note.id]!);
      },
      statusBuilder: (note) => byId[note.id]!.ready
          ? null
          : Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                t('未取得またはロック中 · 読み取り専用', 'Missing or locked · read only'),
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
    final attachments = Column(
      children: [
        for (final (index, attachment) in _editingAttachments.indexed)
          if (!_removed.contains(attachment.id))
            Card(
              clipBehavior: Clip.antiAlias,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    title: Text(
                      syncV2AttachmentFileName(attachment.label),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      attachment.size >= 1024 * 1024
                          ? '${(attachment.size / (1024 * 1024)).toStringAsFixed(1)} MB'
                          : '${(attachment.size / 1024).toStringAsFixed(0)} KB',
                    ),
                    onTap: writable ? () => _openAttachment(attachment) : null,
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: t('ダウンロード', 'Download'),
                          onPressed: writable
                              ? () => _run(() async {
                                  final active = _attachmentSessionIsActive();
                                  final bytes = await c.readAttachment(
                                    attachment,
                                  );
                                  try {
                                    if (active()) {
                                      await FilePicker.saveFile(
                                        fileName: syncV2AttachmentFileName(
                                          attachment.label,
                                        ),
                                        bytes: bytes,
                                      );
                                    }
                                  } finally {
                                    bytes.fillRange(0, bytes.length, 0);
                                  }
                                })
                              : null,
                          icon: const Icon(Icons.download),
                        ),
                        IconButton(
                          tooltip: t('添付を削除', 'Remove attachment'),
                          onPressed: writable
                              ? () =>
                                    setState(() => _removed.add(attachment.id))
                              : null,
                          icon: const Icon(Icons.close),
                        ),
                      ],
                    ),
                  ),
                  if (writable)
                    _attachmentPreview(
                      attachment,
                      240,
                      inline: true,
                      autoLoad: index < 3,
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
      ],
    );
    final actions = Wrap(
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
    );
    if (_originalDesign) {
      return SyncV2OriginalEditor(
        titleController: _title,
        bodyController: _body,
        writable: writable,
        onClose: c.busy ? null : () => setState(_clearEditor),
        attachments: attachments,
        actions: actions,
        createdAt: _editing?.note.createdAt,
        editing: _editing != null,
        wide: MediaQuery.sizeOf(context).width >= 1180,
      );
    }
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
          attachments,
          actions,
        ],
      ),
    );
  }
}

class SyncV2ImportSelection {
  SyncV2ImportSelection(
    Map<String, String> destinations,
    this.acceptUnlinkedAttachments, {
    this.administratorOverwrite = false,
  }) : destinations = Map.unmodifiable(destinations);
  final Map<String, String> destinations;
  final bool acceptUnlinkedAttachments;
  final bool administratorOverwrite;
}

/// Keeps destination preparation inside the ZIP review, after file-picker locks.
class SyncV2ImportReviewDialog extends StatefulWidget {
  const SyncV2ImportReviewDialog({
    super.key,
    required this.controller,
    required this.inspection,
    required this.isActive,
    required this.errorMessage,
    required this.unlockAdmin,
    required this.unlockAdminWithPassword,
    required this.unlockPrivate,
    required this.recoverAdmin,
    required this.createDestination,
  });
  final SyncV2WorkspaceController controller;
  final SyncV2ArchiveInspection inspection;
  final bool Function() isActive;
  final String Function(String) errorMessage;
  final Future<void> Function() unlockAdmin,
      unlockAdminWithPassword,
      unlockPrivate,
      recoverAdmin;
  final Future<String?> Function() createDestination;
  @override
  State<SyncV2ImportReviewDialog> createState() =>
      _SyncV2ImportReviewDialogState();
}

class _SyncV2ImportReviewDialogState extends State<SyncV2ImportReviewDialog> {
  final _destinations = <String, String>{};
  bool _accept = false, _working = false;
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  Future<void> _perform(Future<void> Function() action) async {
    if (_working || !widget.isActive()) return;
    setState(() => _working = true);
    try {
      await action();
    } finally {
      if (mounted && widget.isActive()) setState(() => _working = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.controller,
    builder: (context, _) {
      final c = widget.controller;
      final sources = widget.inspection.noteCountsByProfile.keys
          .where((id) => id != 'everyday')
          .toList();
      final profiles = c.profiles.where((p) => !p.isNormal).toList();
      final ids = profiles.map((p) => p.id).toSet();
      final ready =
          sources.every((source) => ids.contains(_destinations[source])) &&
          _destinations.values.toSet().length == sources.length;
      final busy = _working || c.busy;
      return AlertDialog(
        title: Text(t('インポート内容の確認', 'Review import')),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  key: const ValueKey('import-admin-overwrite'),
                  onPressed: busy
                      ? null
                      : () => _perform(() async {
                          final navigator = Navigator.of(context);
                          if (!c.adminUnlocked) await widget.unlockAdmin();
                          if (!mounted ||
                              !widget.isActive() ||
                              !c.adminUnlocked) {
                            return;
                          }
                          navigator.pop(
                            SyncV2ImportSelection(
                              const {},
                              true,
                              administratorOverwrite: true,
                            ),
                          );
                        }),
                  icon: const Icon(Icons.admin_panel_settings),
                  label: Text(
                    (c.adminUnlocked || c.settingsAdminActive)
                        ? t('管理者として一括復元・上書き', 'Restore and overwrite as admin')
                        : t('管理者認証して一括復元・上書き', 'Authenticate and restore all'),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  t(
                    '同じメモはZIPの内容で上書きし、私用の復元先は自動で用意します。未連携添付のあるメモも取り込みます。個別パスワードは後で管理者から設定できます。',
                    'Matching notes are overwritten with ZIP contents, and private destinations are prepared automatically. Notes with unlinked attachments are included. Set individual passwords later as admin.',
                  ),
                ),
                const Divider(),
                Text(
                  t('手動で復元先を選ぶ', 'Choose destinations manually'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (widget.inspection.noteCountsByProfile.containsKey(
                  'everyday',
                ))
                  Text(
                    '${t('通常', 'Normal')} · ${widget.inspection.noteCountsByProfile['everyday']} ${t('件', 'notes')}',
                  ),
                if (sources.isNotEmpty) ...[
                  if (!ready)
                    Text(
                      profiles.isEmpty
                          ? t(
                              '復元先が未作成またはロック中です。この画面で解除するか、私用グループごとに復元先を作成してください。',
                              'Destinations are missing or locked. Unlock existing profiles or create a destination for each private source here.',
                            )
                          : t(
                              '各私用グループに、異なる解除済みの復元先を選んでください。',
                              'Choose a different unlocked destination for each private source.',
                            ),
                    ),
                  Wrap(
                    spacing: 8,
                    children: [
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => _perform(widget.unlockPrivate),
                        child: Text(
                          t('既存プロファイルを解除', 'Unlock existing profile'),
                        ),
                      ),
                      if (!c.adminUnlocked)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _perform(widget.unlockAdmin),
                          child: Text(
                            c.biometricEnabled
                                ? t(
                                    '生体認証で復元先を表示',
                                    'Show profiles with biometrics',
                                  )
                                : t(
                                    '管理者認証で復元先を表示',
                                    'Show profiles with admin password',
                                  ),
                          ),
                        ),
                      if (!c.adminUnlocked && c.biometricEnabled)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _perform(widget.unlockAdminWithPassword),
                          child: Text(t('管理パスワードで解除', 'Use admin password')),
                        ),
                      if (!c.adminUnlocked && c.biometricsAvailable)
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => _perform(widget.recoverAdmin),
                          child: Text(
                            t(
                              'ADMINコードで生体認証を設定',
                              'Set up biometrics with ADMIN code',
                            ),
                          ),
                        ),
                    ],
                  ),
                  for (var i = 0; i < sources.length; i++) ...[
                    DropdownButtonFormField<String>(
                      key: ValueKey(
                        'import-destination-${sources[i]}-${ids.contains(_destinations[sources[i]]) ? _destinations[sources[i]] : ''}',
                      ),
                      initialValue: ids.contains(_destinations[sources[i]])
                          ? _destinations[sources[i]]
                          : null,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText:
                            '${t('プライベート', 'Private')} ${i + 1} · ${widget.inspection.noteCountsByProfile[sources[i]]} ${t('件', 'notes')}',
                      ),
                      items: [
                        for (final profile in profiles)
                          if (!_destinations.entries.any(
                            (entry) =>
                                entry.key != sources[i] &&
                                entry.value == profile.id,
                          ))
                            DropdownMenuItem(
                              value: profile.id,
                              child: Text(
                                profile.name,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                      ],
                      onChanged: busy
                          ? null
                          : (id) {
                              if (id != null) {
                                setState(() => _destinations[sources[i]] = id);
                              }
                            },
                    ),
                    if (!ids.contains(_destinations[sources[i]]))
                      TextButton(
                        key: ValueKey('import-create-${sources[i]}'),
                        onPressed: busy
                            ? null
                            : () => _perform(() async {
                                final id = await widget.createDestination();
                                if (!mounted ||
                                    !widget.isActive() ||
                                    id == null) {
                                  return;
                                }
                                if (!widget.controller.profiles.any(
                                      (p) => !p.isNormal && p.id == id,
                                    ) ||
                                    _destinations.values.contains(id)) {
                                  return;
                                }
                                _destinations[sources[i]] = id;
                              }),
                        child: Text(
                          t('この復元先を新規作成', 'Create destination for this source'),
                        ),
                      ),
                  ],
                ],
                if (c.error != null) Text(widget.errorMessage(c.error!)),
                if (widget.inspection.notesWithUnlinkedAttachments > 0)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _accept,
                    onChanged: busy
                        ? null
                        : (value) => setState(() => _accept = value ?? false),
                    title: Text(
                      t(
                        '未連携の添付があるメモ ${widget.inspection.notesWithUnlinkedAttachments} 件を受け入れる',
                        'Accept ${widget.inspection.notesWithUnlinkedAttachments} notes with unlinked attachments',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t('キャンセル', 'Cancel')),
          ),
          OutlinedButton(
            onPressed:
                !busy &&
                    ready &&
                    (widget.inspection.notesWithUnlinkedAttachments == 0 ||
                        _accept)
                ? () => Navigator.pop(
                    context,
                    SyncV2ImportSelection(_destinations, _accept),
                  )
                : null,
            child: Text(t('選択した復元先にインポート', 'Import to selected destinations')),
          ),
        ],
      );
    },
  );
}
