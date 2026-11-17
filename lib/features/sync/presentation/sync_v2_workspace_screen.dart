import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../home/domain/note_entry.dart';
import '../../home/domain/note_tags.dart';
import '../../home/presentation/marked_note_calendar.dart';
import '../../home/presentation/home_search_toolbar.dart';
import '../../home/presentation/home_page.dart'
    show
        HomeNotePreviewList,
        HomeBrandTitle,
        HomeNoteSection,
        HomeQuickTagStrip;
import '../../home/presentation/home_providers.dart'
    show
        NotesListDensity,
        NotesListSortField,
        SearchFilters,
        SearchDateRange,
        SearchDateField,
        SearchAttachmentFilter,
        notesListDensityControllerProvider,
        notesListSortControllerProvider,
        AutoTagRule,
        autoTagRulesControllerProvider,
        applyAutoTagRules,
        isSystemSyncExclusionTag,
        systemSyncExcludedTag;
import '../../security/data/sync_v2_admin_store.dart';
import '../data/sync_v2_note_repository.dart' show SyncV2NoteVersion;
import 'sync_v2_workspace.dart';
import 'sync_v2_privacy.dart';
import 'sync_v2_rich_blocks_editor.dart';
import 'sync_v2_pairing_dialogs.dart';
import 'sync_v2_original_editor.dart';
import 'sync_v2_attachment_image.dart';
import 'sync_v2_attachment_viewer.dart';
import 'sync_v2_responsive_navigation.dart';
import 'sync_v2_note_search.dart';
import 'sync_v2_tag_summaries.dart';
import 'sync_v2_search_controls.dart';
import 'sync_v2_insights_view.dart';
import 'sync_v2_note_read_only_pane.dart';
import 'sync_v2_auto_tag_rules.dart';

class _SyncV2SelectedPreview {
  const _SyncV2SelectedPreview({
    required this.entry,
    required this.note,
    required this.attachments,
    this.versionId,
  });

  final SyncV2WorkspaceNote entry;
  final NoteEntry? note;
  final List<SyncV2AttachmentReference> attachments;
  final String? versionId;

  bool get ready => note != null;
}

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

List<int> _draftSearchOffsets(String text, String query) {
  if (query.isEmpty || text.isEmpty) return const <int>[];
  final lower = text.toLowerCase();
  final offsets = <int>[];
  var cursor = 0;
  while (cursor < lower.length) {
    final index = lower.indexOf(query, cursor);
    if (index < 0) break;
    offsets.add(index);
    cursor = index + query.length;
  }
  return offsets;
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
  const SyncV2WorkspaceScreen({
    super.key,
    this.localOnly = false,
    this.cloudSandbox = false,
  });

  /// Used by the isolated developer preview, which has no remote transport.
  final bool localOnly;

  /// Isolated development CloudKit zones; not compatible with iOS pairing.
  final bool cloudSandbox;
  @override
  ConsumerState<SyncV2WorkspaceScreen> createState() =>
      _SyncV2WorkspaceScreenState();
}

class _SyncV2WorkspaceScreenState extends ConsumerState<SyncV2WorkspaceScreen>
    with WidgetsBindingObserver {
  bool get _isolatedPreview => widget.localOnly || widget.cloudSandbox;
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
  final _draftSearch = TextEditingController();
  final _draftSearchFocus = FocusNode(debugLabel: 'sync-v2-draft-search');
  final _titleFocus = FocusNode(debugLabel: 'sync-v2-draft-title');
  final _tagInput = TextEditingController();
  List<String> _draftTags = [];
  SearchFilters _searchFilters = const SearchFilters();
  bool _originalDesign = true;
  bool _calendarView = false;
  bool _insightsView = false;
  bool _trashView = false;
  bool _archiveView = false;
  DateTime _calendarDay = DateTime.now();
  late DateTime _calendarMonth = DateTime(
    _calendarDay.year,
    _calendarDay.month,
  );
  String _query = '';
  final _secrets = <TextEditingController>[];
  final _retired = <TextEditingController>[];
  SyncV2WorkspaceNote? _editing;
  _SyncV2SelectedPreview? _selectedPreview;
  String? _selectedVersionId;
  List<SyncV2AttachmentReference> _editingAttachments = [];
  List<NoteBlock> _draftBlocks = [];
  NoteEditorMode _draftEditorMode = NoteEditorMode.rich;
  bool _draftPinned = false;
  NoteLocation? _draftLocation;
  bool _editorOpen = false;
  int _draftSearchMatchIndex = 0;
  int _draftSearchRequest = 0;
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
  final _pendingIdRandom = math.Random.secure();
  GlobalKey<SyncV2RichBlocksEditorState> _richEditorKey =
      GlobalKey<SyncV2RichBlocksEditorState>();
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
        _clearEditor(clearPreview: true);
        _clearSearch();
        _insightsView = false;
        _archiveView = false;
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

  SyncV2NavigationSection get _navigationSection {
    if (_calendarView) return SyncV2NavigationSection.calendar;
    if (_insightsView) return SyncV2NavigationSection.insights;
    if (_trashView) return SyncV2NavigationSection.trash;
    return SyncV2NavigationSection.notes;
  }

  void _selectNavigation(
    SyncV2WorkspaceController controller,
    SyncV2NavigationSection section,
  ) {
    if (!mounted ||
        !_foreground ||
        controller.busy ||
        _editorOpen ||
        controller.selectedProfileId == null) {
      return;
    }
    if (section == SyncV2NavigationSection.settings) {
      if (!_isolatedPreview) context.go('/settings');
      return;
    }
    if (section == SyncV2NavigationSection.tags) {
      final tags = dedupeNoteTags(
        controller.notes
            .where(
              (entry) =>
                  entry.ready &&
                  !entry.isConflict &&
                  !entry.isDeleted &&
                  entry.note.deletedAt == null &&
                  entry.note.archivedAt == null &&
                  entry.note.vaultId == controller.selectedProfileId,
            )
            .expand((entry) => entry.note.normalizedTags),
      );
      unawaited(_manageTags(controller, tags));
      return;
    }
    setState(() {
      _calendarView = section == SyncV2NavigationSection.calendar;
      _insightsView = section == SyncV2NavigationSection.insights;
      _trashView = section == SyncV2NavigationSection.trash;
      _archiveView = false;
    });
  }

  bool _showV1Navigation(SyncV2WorkspaceController controller) =>
      _originalDesign && controller.registered && _foreground;

  Widget _navigation(
    SyncV2WorkspaceController controller, {
    required bool wide,
  }) => SyncV2ResponsiveNavigation(
    section: _navigationSection,
    wide: wide,
    enabled:
        !controller.busy &&
        !_editorOpen &&
        controller.selectedProfileId != null,
    canOpenSettings: !_isolatedPreview,
    isJapanese: Localizations.localeOf(context).languageCode == 'ja',
    tagSummaries: wide
        ? syncV2TagSummaries(controller.notes, controller.selectedProfileId)
        : const [],
    activeTags: _searchFilters.tags,
    onTagSelected: (tag) {
      if (controller.busy ||
          _editorOpen ||
          controller.selectedProfileId == null) {
        return;
      }
      setState(() {
        _search.clear();
        _query = '';
        _searchFilters = _searchFilters.copyWith(
          tags: [tag],
          requireAllTags: false,
        );
        _calendarView = false;
        _insightsView = false;
        _trashView = false;
        _archiveView = false;
        _clearSelectedPreview();
      });
    },
    onShowAllNotes: () {
      if (controller.busy ||
          _editorOpen ||
          controller.selectedProfileId == null) {
        return;
      }
      setState(() {
        _search.clear();
        _query = '';
        _searchFilters = _searchFilters.copyWith(
          tags: [],
          requireAllTags: false,
        );
        _calendarView = false;
        _insightsView = false;
        _trashView = false;
        _archiveView = false;
        _clearSelectedPreview();
      });
    },
    onSectionSelected: (section) => _selectNavigation(controller, section),
    onAddNote: () {
      if (!controller.busy &&
          !_editorOpen &&
          controller.selectedProfileId != null) {
        _open(null);
      }
    },
  );

  Widget _withV1Sidebar(SyncV2WorkspaceController controller, Widget child) {
    if (!_showV1Navigation(controller) ||
        MediaQuery.sizeOf(context).width < 840) {
      return child;
    }
    return Row(
      children: [
        _navigation(controller, wide: true),
        const VerticalDivider(width: 1),
        Expanded(child: child),
      ],
    );
  }

  void _clearSearch() {
    _search.clear();
    _query = '';
    _searchFilters = const SearchFilters();
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
    _clearEditor(clearPreview: true);
    _clearSearch();
    unawaited(_attachmentViewer.close());
    ref.read(syncV2WorkspaceProvider).background();
    _closeSyncV2DialogRoutes(List.of(_dialogRoutes));
    _dialogRoutes.clear();
    if (mounted) setState(() => _foreground = false);
  }

  void _clearSelectedPreview() {
    _attachmentViewRevision++;
    _selectedPreview = null;
    unawaited(_attachmentViewer.close());
  }

  void _clearEditor({bool clearPreview = false}) {
    _attachmentViewRevision++;
    unawaited(_attachmentViewer.close());
    _title.clear();
    _body.clear();
    _draftSearch.clear();
    _draftSearchMatchIndex = 0;
    _draftSearchRequest++;
    _tagInput.clear();
    _draftTags = [];
    _editing = null;
    _selectedVersionId = null;
    _editingAttachments = [];
    _draftBlocks = [];
    _draftEditorMode = NoteEditorMode.rich;
    _draftPinned = false;
    _draftLocation = null;
    _editorOpen = false;
    _wipePendingAttachments();
    _richEditorKey = GlobalKey<SyncV2RichBlocksEditorState>();
    _removed.clear();
    if (clearPreview) _clearSelectedPreview();
  }

  void _wipePendingAttachments() {
    for (final pending in _added) {
      pending.bytes.fillRange(0, pending.bytes.length, 0);
    }
    _added.clear();
  }

  String _newPendingAttachmentId() {
    String id;
    do {
      id = List<int>.generate(
        16,
        (_) => _pendingIdRandom.nextInt(256),
      ).map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    } while (_added.any((pending) => pending.draftId == id));
    return id;
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
    _clearEditor(clearPreview: true);
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
    _draftSearch.dispose();
    _draftSearchFocus.dispose();
    _titleFocus.dispose();
    _tagInput.dispose();
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
    'tag_conflict' => t(
      '未取得または競合中のメモがあります。同期または競合の解決後にもう一度操作してください。',
      'Sync missing notes and resolve conflicts before managing tags.',
    ),
    'invalid_tag' => t('タグ名を入力してください。', 'Enter a tag name.'),
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

  Future<void> _copyOrShareDraft({required bool share}) async {
    final active = _attachmentSessionIsActive(bindView: true);
    final noteId = _editing?.note.id;
    final versionId = _selectedVersionId;
    if (!_editorOpen || !active()) return;

    final title = _title.text.trim();
    final body = _draftEditorMode == NoteEditorMode.quick
        ? _body.text.trim()
        : syncV2EditableBody(
            (_editing?.note ??
                    NoteEntry(
                      id: 'draft',
                      vaultId: _controller.selectedProfileId ?? '',
                      title: '',
                      body: '',
                      createdAt: DateTime.now(),
                    ))
                .copyWith(blocks: _draftBlocks),
          ).trim();
    final tags = dedupeNoteTags([..._draftTags, _tagInput.text]).where(
      (tag) => !isSystemSyncExclusionTag(tag) && tag != systemSyncExcludedTag,
    );
    final text = StringBuffer(title);
    if (body.isNotEmpty && body != title) {
      text
        ..writeln()
        ..writeln()
        ..write(body);
    }
    if (tags.isNotEmpty) {
      text
        ..writeln()
        ..writeln()
        ..write(tags.map((tag) => '#$tag').join(' '));
    }
    final location = _draftLocation;
    if (location != null) {
      final address = location.address?.trim();
      text
        ..writeln()
        ..writeln()
        ..write(
          address?.isNotEmpty == true
              ? address
              : '${location.latitude}, ${location.longitude}',
        );
    }
    if (!active() ||
        _editing?.note.id != noteId ||
        _selectedVersionId != versionId) {
      return;
    }

    try {
      if (share) {
        final result = await SharePlus.instance.share(
          ShareParams(text: text.toString().trim(), subject: title),
        );
        if (result.status != ShareResultStatus.success) return;
      } else {
        await Clipboard.setData(ClipboardData(text: text.toString().trim()));
      }
      if (!active() ||
          _editing?.note.id != noteId ||
          _selectedVersionId != versionId ||
          !mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            share
                ? t('メモのテキストを共有しました。', 'Note text shared.')
                : t('メモのテキストをコピーしました。', 'Note text copied.'),
          ),
        ),
      );
    } catch (_) {
      if (!active() || !mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            share
                ? t('メモの共有に失敗しました。', 'Could not share note text.')
                : t('メモのコピーに失敗しました。', 'Could not copy note text.'),
          ),
        ),
      );
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

  Future<SyncV2NoteVersion?> _chooseConflictVersion(
    SyncV2WorkspaceNote note,
  ) async {
    if (!note.ready) return null;
    final choice = await _dialog<int>(
      (context) => AlertDialog(
        title: Text(t('すべての競合バージョン', 'All conflicting versions')),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < note.versions.length; i++)
                  ListTile(
                    title: Text(
                      note.versions[i].isDeleted
                          ? t('削除されたバージョン', 'Deleted version')
                          : ((note.versions[i].body?['note'] as Map?)?['title']
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
                      onPressed: () => Navigator.pop(context, i),
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
    return choice == null || !mounted || !_foreground
        ? null
        : note.versions[choice];
  }

  Future<void> _showPreview(SyncV2WorkspaceNote entry) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (c.busy ||
        _editorOpen ||
        !_foreground ||
        entry.note.vaultId != c.selectedProfileId) {
      if (_editorOpen && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                '編集中は別のメモを選択できません。',
                'Finish editing before selecting another note.',
              ),
            ),
          ),
        );
      }
      return;
    }
    final revision = c.privateSessionRevision;
    final profile = c.selectedProfileId;
    _attachmentViewRevision++;
    final previewToken = _attachmentViewRevision;
    unawaited(_attachmentViewer.close());

    if (!entry.ready) {
      if (!mounted ||
          !_foreground ||
          c.busy ||
          revision != c.privateSessionRevision ||
          profile != c.selectedProfileId) {
        return;
      }
      setState(() {
        _selectedPreview = _SyncV2SelectedPreview(
          entry: entry,
          note: null,
          attachments: const [],
        );
        _calendarView = false;
        _insightsView = false;
        _trashView = false;
        _archiveView = false;
      });
      return;
    }

    NoteEntry selectedNote = entry.note;
    List<SyncV2AttachmentReference> attachments = entry.attachments;
    String? versionId;
    if (entry.isConflict) {
      final version = await _chooseConflictVersion(entry);
      if (version == null ||
          !mounted ||
          !_foreground ||
          revision != c.privateSessionRevision ||
          profile != c.selectedProfileId ||
          previewToken != _attachmentViewRevision) {
        return;
      }
      versionId = version.change.id;
      if (version.isDeleted) {
        if (await _confirm(
              t('競合を削除で解決', 'Resolve as deleted'),
              t(
                '表示したすべてのバージョンを削除として解決します。',
                'Resolve all displayed versions as deleted.',
              ),
            ) &&
            mounted &&
            _foreground &&
            revision == c.privateSessionRevision &&
            profile == c.selectedProfileId) {
          await _run(() => c.deleteNote(entry));
        }
        return;
      }
      final body = version.body;
      if (body == null || !version.payloadAvailable || version.isDeleted) {
        return;
      }
      selectedNote = NoteEntry.fromJson(
        Map<String, dynamic>.from(body['note'] as Map),
      );
      attachments = [
        for (final raw in (body['attachments'] as List? ?? []))
          SyncV2AttachmentReference.fromJson(
            Map<String, dynamic>.from(raw as Map),
          ),
      ];
    }
    if (!mounted ||
        !_foreground ||
        c.busy ||
        revision != c.privateSessionRevision ||
        profile != c.selectedProfileId ||
        previewToken != _attachmentViewRevision) {
      return;
    }
    setState(() {
      _selectedPreview = _SyncV2SelectedPreview(
        entry: entry,
        note: selectedNote,
        attachments: List.unmodifiable(attachments),
        versionId: versionId,
      );
      _calendarView = false;
      _insightsView = false;
      _trashView = false;
      _archiveView = false;
    });
  }

  Future<void> _open(
    SyncV2WorkspaceNote? note, {
    String? selectedVersionId,
  }) async {
    _attachmentViewRevision++;
    unawaited(_attachmentViewer.close());
    FocusScope.of(context).unfocus();
    _wipePendingAttachments();
    _richEditorKey = GlobalKey<SyncV2RichBlocksEditorState>();
    var attachments = note?.attachments ?? <SyncV2AttachmentReference>[];
    var blocks = note?.note.blocks ?? <NoteBlock>[];
    var editorMode = note?.note.editorMode ?? NoteEditorMode.rich;
    var pinned = note?.note.isPinned ?? false;
    var location = note?.note.location;
    if (note?.isConflict == true) {
      final conflictNote = note!;
      final version = selectedVersionId == null
          ? await _chooseConflictVersion(conflictNote)
          : conflictNote.versions
                .where((item) => item.change.id == selectedVersionId)
                .firstOrNull;
      if (version == null || !mounted || !_foreground) return;
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
          await _run(
            () => ref.read(syncV2WorkspaceProvider).deleteNote(conflictNote),
          );
        }
        return;
      }
      if (version.body == null || !version.payloadAvailable) return;
      final selectedNote = NoteEntry.fromJson(
        Map<String, dynamic>.from(version.body!['note'] as Map),
      );
      blocks = selectedNote.blocks;
      editorMode = selectedNote.editorMode;
      pinned = selectedNote.isPinned;
      location = selectedNote.location;
      _draftTags = List.of(selectedNote.normalizedTags);
      _title.text = (version.body?['note'] as Map?)?['title'] as String? ?? '';
      _body.text = syncV2EditableBody(selectedNote);
    } else {
      _draftTags = List.of(note?.note.normalizedTags ?? const <String>[]);
      _title.text = note?.note.title ?? '';
      _body.text = note?.note.body ?? '';
    }
    if (blocks.isEmpty) {
      blocks = [NoteBlock(type: NoteBlockType.paragraph, text: _body.text)];
    }
    _tagInput.clear();
    setState(() {
      _editing = note;
      _selectedVersionId = selectedVersionId;
      _editingAttachments = attachments;
      _draftBlocks = List.of(blocks);
      _draftEditorMode = editorMode;
      _draftPinned = pinned;
      _draftLocation = location;
      _editorOpen = true;
      _wipePendingAttachments();
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

  String? _linkedRichAttachmentId(NoteBlock block) {
    final path = block.attachment?.filePath;
    if (path == null || !path.startsWith('v2attachment:')) return null;
    final id = path.substring('v2attachment:'.length);
    return id.isEmpty ? null : id;
  }

  Set<String> _removableRichAttachmentIds() => {
    for (final attachment in _editingAttachments)
      if (!_removed.contains(attachment.id)) attachment.id,
  };

  void _onRichBlocksChanged(List<NoteBlock> blocks) {
    final previousIds = {
      for (final block in _draftBlocks) ?_linkedRichAttachmentId(block),
    };
    final nextIds = {
      for (final block in blocks) ?_linkedRichAttachmentId(block),
    };
    setState(() {
      for (final id in previousIds.difference(nextIds)) {
        if (_removableRichAttachmentIds().contains(id) &&
            !_removed.contains(id)) {
          _removed.add(id);
        }
      }
      for (final id in nextIds.difference(previousIds)) {
        _removed.remove(id);
      }
      _draftBlocks = List.of(blocks);
      _body.text = syncV2EditableBody(
        (_editing?.note ??
                NoteEntry(
                  id: 'draft',
                  vaultId: _controller.selectedProfileId ?? '',
                  title: '',
                  body: '',
                  createdAt: DateTime.now(),
                ))
            .copyWith(blocks: blocks),
      );
    });
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
    bool bindView = false,
  }) {
    final active = _attachmentSessionIsActive(bindView: bindView);
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
          bindView ? _attachmentViewRevision : null,
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
    if (_pickingAttachments) return;
    final active = _attachmentSessionIsActive(bindView: true);
    final noteId = _editing?.note.id;
    final versionId = _selectedVersionId;
    final editorMode = _draftEditorMode;
    final rich = editorMode == NoteEditorMode.rich;
    final insertionTarget = rich
        ? _richEditorKey.currentState?.captureInsertionTarget()
        : null;
    if (!_editorOpen || !active() || (rich && insertionTarget == null)) return;
    bool stillEditing() =>
        active() &&
        _editorOpen &&
        _editing?.note.id == noteId &&
        _selectedVersionId == versionId &&
        _draftEditorMode == editorMode;
    if (mounted) setState(() => _pickingAttachments = true);
    final staged = <SyncV2PendingAttachment>[];
    var accepted = false;
    try {
      final files = await FilePicker.pickFiles();
      if (!stillEditing() || files.isEmpty) return;
      for (final file in files) {
        if (!stillEditing()) return;
        final length = await file.length();
        if (!stillEditing()) return;
        if ((length ?? 64 * 1024 * 1024 + 1) > 64 * 1024 * 1024) {
          if (mounted && _foreground) {
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
        if (!stillEditing() || bytes.length > 64 * 1024 * 1024) {
          bytes.fillRange(0, bytes.length, 0);
          if (!stillEditing()) return;
          continue;
        }
        final draftId = rich ? _newPendingAttachmentId() : null;
        staged.add(
          SyncV2PendingAttachment(
            label: file.name,
            type: AttachmentType.file,
            bytes: bytes,
            draftId: draftId,
          ),
        );
      }
      if (!stillEditing() || staged.isEmpty) return;
      if (rich) {
        final editor = _richEditorKey.currentState;
        final descriptors = [
          for (final pending in staged)
            SyncV2PendingBlock(
              draftId: pending.draftId!,
              label: pending.label,
              type: pending.type,
            ),
        ];
        if (editor == null ||
            !editor.insertPendingAttachments(insertionTarget!, descriptors)) {
          return;
        }
      }
      _added.addAll(staged);
      accepted = true;
    } finally {
      if (!accepted) {
        for (final pending in staged) {
          pending.bytes.fillRange(0, pending.bytes.length, 0);
        }
      }
      if (mounted) {
        setState(() => _pickingAttachments = false);
      } else {
        _pickingAttachments = false;
      }
    }
    if (accepted && mounted) setState(() {});
  }

  void _removePendingAttachment(SyncV2PendingAttachment pending) {
    final index = _added.indexOf(pending);
    if (index < 0) return;
    if (pending.draftId != null && _draftEditorMode == NoteEditorMode.rich) {
      _richEditorKey.currentState?.removePendingAttachment(pending.draftId!);
    }
    setState(() {
      _added.removeAt(index);
      pending.bytes.fillRange(0, pending.bytes.length, 0);
    });
  }

  Widget _previewBlock(
    NoteBlock block,
    List<SyncV2AttachmentReference> attachments,
    Object viewKey,
  ) {
    if (block.type == NoteBlockType.paragraph) {
      final text = block.text ?? '';
      return text.isEmpty
          ? const SizedBox.shrink()
          : SelectableText(
              text,
              style: Theme.of(context).textTheme.bodyLarge
                  ?.copyWith(height: 1.55),
            );
    }
    final rawPath = block.attachment?.filePath;
    final id = rawPath != null && rawPath.startsWith('v2attachment:')
        ? rawPath.substring('v2attachment:'.length)
        : null;
    final reference = id == null
        ? null
        : attachments.where((item) => item.id == id).firstOrNull;
    if (reference == null) {
      return ListTile(
        leading: const Icon(Icons.attach_file),
        title: Text(
          block.attachment?.label ?? t('添付を表示できません', 'Attachment unavailable'),
        ),
      );
    }
    return KeyedSubtree(
      key: ValueKey((viewKey, reference.id)),
      child: _attachmentPreview(reference, 240, inline: true, bindView: true),
    );
  }

  Widget _mobileNoteSwipe(SyncV2WorkspaceController c, Widget child) {
    if (MediaQuery.sizeOf(context).width >= 600) return child;
    return _MobileNoteSwipeRegion(
      onDismiss: () async {
        if (!mounted || !_foreground || c.busy) return;
        final wasEditing = _editorOpen;
        final editing = _editing;
        final preview = _selectedPreview;
        final revision = c.privateSessionRevision;
        if (wasEditing && !_archiveDraftIsClean()) {
          final discard = await _confirm(
            t('編集内容を破棄しますか？', 'Discard changes?'),
            t('保存していない変更は失われます。', 'Unsaved changes will be lost.'),
          );
          if (!discard) return;
        }
        if (!mounted ||
            !_foreground ||
            c.busy ||
            c.privateSessionRevision != revision ||
            _editorOpen != wasEditing ||
            !identical(_editing, editing) ||
            !identical(_selectedPreview, preview)) {
          return;
        }
        setState(() => _clearEditor(clearPreview: true));
      },
      child: child,
    );
  }

  Widget _previewPane(SyncV2WorkspaceController c, {required bool fullScreen}) {
    final preview = _selectedPreview;
    if (preview == null) {
      return Center(child: Text(t('メモを選択してください', 'Select a note to preview')));
    }
    if (!preview.ready) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.lock_outline_rounded),
            const SizedBox(height: 8),
            Text(t('未取得またはロック中 · 読み取り専用', 'Missing or locked · read only')),
          ],
        ),
      );
    }
    final note = preview.note!;
    final viewKey = (
      preview.entry.note.vaultId,
      c.privateSessionRevision,
      preview.entry.note.id,
      preview.versionId,
      _attachmentViewRevision,
    );
    final blockReferences = <String>{
      for (final block in note.blocks)
        if (block.attachment?.filePath case final path?)
          if (path.startsWith('v2attachment:'))
            path.substring('v2attachment:'.length),
    };
    final content = note.blocks.isEmpty
        ? null
        : <Widget>[
            for (final block in note.blocks)
              _previewBlock(block, preview.attachments, viewKey),
          ];
    final fallbackAttachments = [
      for (final attachment in preview.attachments)
        if (!blockReferences.contains(attachment.id))
          KeyedSubtree(
            key: ValueKey((viewKey, attachment.id)),
            child: _attachmentPreview(
              attachment,
              240,
              inline: true,
              bindView: true,
            ),
          ),
    ];
    return Column(
      children: [
        if (fullScreen)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextButton.icon(
              key: const ValueKey('sync-v2-preview-back'),
              onPressed: () => setState(_clearSelectedPreview),
              icon: const Icon(Icons.arrow_back),
              label: Text(t('一覧', 'Notes')),
            ),
          ),
        Expanded(
          child: SyncV2NoteReadOnlyPane(
            key: ValueKey(viewKey),
            note: SyncV2NotePreviewData(
              title: note.title,
              body: note.body,
              createdAt: note.createdAt,
              updatedAt: note.updatedAt,
              tags: note.normalizedTags,
              location: note.location,
              isPinned: note.isPinned,
            ),
            contentWidgets: content,
            attachmentWidgets: fallbackAttachments,
            onEdit: !c.busy && preview.entry.ready
                ? () => _editPreview(preview)
                : null,
            onCopy: !c.busy
                ? () => _copyOrSharePreview(preview, share: false)
                : null,
            onShare: !c.busy
                ? () => _copyOrSharePreview(preview, share: true)
                : null,
            onDelete: !c.busy && preview.entry.ready
                ? () => _deletePreview(preview)
                : null,
            onTogglePinned: !c.busy && !preview.entry.isConflict
                ? () => _togglePreviewPinned(preview)
                : null,
          ),
        ),
      ],
    );
  }

  Future<void> _editPreview(_SyncV2SelectedPreview preview) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (c.busy ||
        !preview.ready ||
        !_foreground ||
        preview.entry.note.vaultId != c.selectedProfileId) {
      return;
    }
    final current = c.notes
        .where((entry) => entry.note.id == preview.entry.note.id)
        .firstOrNull;
    if (current == null ||
        !current.ready ||
        current.headIds.length != preview.entry.headIds.length ||
        !current.headIds.containsAll(preview.entry.headIds) ||
        (preview.versionId != null &&
            !current.versions.any(
              (version) => version.change.id == preview.versionId,
            ))) {
      if (mounted) {
        setState(_clearSelectedPreview);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                'メモが更新されました。再度選択してください。',
                'This note changed. Select it again.',
              ),
            ),
          ),
        );
      }
      return;
    }
    await _open(current, selectedVersionId: preview.versionId);
  }

  Future<void> _deletePreview(_SyncV2SelectedPreview preview) async {
    final c = ref.read(syncV2WorkspaceProvider);
    if (c.busy || !_foreground || !preview.ready) {
      return;
    }
    if (!await _confirm(
      t('メモを削除', 'Delete note'),
      preview.entry.isConflict
          ? t('すべての競合バージョンを削除しますか？', 'Delete all conflicting versions?')
          : t('このメモを削除しますか？', 'Delete this note?'),
    )) {
      return;
    }
    if (!mounted ||
        !_foreground ||
        c.busy ||
        !identical(_selectedPreview, preview)) {
      return;
    }
    await _run(() async {
      await c.deleteNote(preview.entry);
      if (mounted && identical(_selectedPreview, preview)) {
        setState(() => _clearEditor(clearPreview: true));
      }
    });
  }

  Future<void> _togglePreviewPinned(_SyncV2SelectedPreview preview) async {
    final c = ref.read(syncV2WorkspaceProvider);
    final note = preview.note;
    if (c.busy || !_foreground || note == null || preview.entry.isConflict) {
      return;
    }
    await _run(
      () => c.saveNote(
        original: preview.entry,
        title: note.title,
        body: note.body,
        blocks: note.blocks,
        isPinned: !note.isPinned,
        tags: note.normalizedTags,
      ),
    );
    if (!mounted || !_foreground) return;
    final updated = c.notes
        .where((entry) => entry.note.id == note.id)
        .firstOrNull;
    setState(() {
      _selectedPreview = updated == null
          ? null
          : _SyncV2SelectedPreview(
              entry: updated,
              note: updated.ready ? updated.note : null,
              attachments: updated.ready ? updated.attachments : const [],
            );
    });
  }

  Future<void> _copyOrSharePreview(
    _SyncV2SelectedPreview preview, {
    required bool share,
  }) async {
    final note = preview.note;
    final c = ref.read(syncV2WorkspaceProvider);
    if (c.busy ||
        note == null ||
        !_foreground ||
        !identical(_selectedPreview, preview)) {
      return;
    }
    final title = note.title.trim();
    final body = syncV2EditableBody(note).trim();
    final tags = note.normalizedTags.where(
      (tag) => !isSystemSyncExclusionTag(tag) && tag != systemSyncExcludedTag,
    );
    final text = StringBuffer(title);
    if (body.isNotEmpty && body != title) {
      text
        ..writeln()
        ..writeln()
        ..write(body);
    }
    if (tags.isNotEmpty) {
      text
        ..writeln()
        ..writeln()
        ..write(tags.map((tag) => '#$tag').join(' '));
    }
    final location = note.location;
    if (location != null) {
      final address = location.address?.trim();
      text
        ..writeln()
        ..writeln()
        ..write(
          address?.isNotEmpty == true
              ? address
              : '${location.latitude}, ${location.longitude}',
        );
    }
    final revision = _backgroundVersion;
    final session = c.privateSessionRevision;
    final previewToken = _attachmentViewRevision;
    bool active() =>
        mounted &&
        _foreground &&
        revision == _backgroundVersion &&
        session == c.privateSessionRevision &&
        previewToken == _attachmentViewRevision &&
        identical(_selectedPreview, preview);
    final messenger = ScaffoldMessenger.of(context);
    try {
      if (share) {
        final result = await SharePlus.instance.share(
          ShareParams(text: text.toString().trim(), subject: title),
        );
        if (result.status != ShareResultStatus.success) return;
      } else {
        await Clipboard.setData(ClipboardData(text: text.toString().trim()));
      }
      if (!active()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            share
                ? t('メモのテキストを共有しました。', 'Note text shared.')
                : t('メモのテキストをコピーしました。', 'Note text copied.'),
          ),
        ),
      );
    } catch (_) {
      if (!active()) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            share
                ? t('メモの共有に失敗しました。', 'Could not share note text.')
                : t('メモのコピーに失敗しました。', 'Could not copy note text.'),
          ),
        ),
      );
    }
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
        if (mounted && _foreground) {
          setState(() => _clearEditor(clearPreview: true));
        }
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

  Widget _profileControls(
    SyncV2WorkspaceController c, {
    VoidCallback? dismiss,
  }) {
    final controls = Padding(
      padding: EdgeInsets.all(_originalDesign ? 0 : 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          DropdownButton<String>(
            value: c.profiles.any((p) => p.id == c.selectedProfileId)
                ? c.selectedProfileId
                : null,
            hint: Text(t('プロファイル', 'Profile')),
            items: [
              for (final p in c.profiles)
                DropdownMenuItem(
                  value: p.id,
                  child: Text(p.isNormal ? t('通常', 'Normal') : p.name),
                ),
            ],
            onChanged: c.busy
                ? null
                : (v) {
                    if (v != null) {
                      dismiss?.call();
                      setState(() {
                        _clearEditor(clearPreview: true);
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
                    dismiss?.call();
                    final password = await _input(
                      t('プライベートパスワード', 'Private password'),
                    );
                    if (password != null && mounted && _foreground) {
                      await _run(() => c.unlockPrivate(password));
                    }
                  },
            tooltip: t('プライベートを解除', 'Unlock private'),
            icon: const Icon(Icons.lock_open),
          ),
          IconButton(
            onPressed: c.busy
                ? null
                : () {
                    dismiss?.call();
                    setState(() {
                      _clearEditor(clearPreview: true);
                      _clearSearch();
                    });
                    c.lockPrivate();
                  },
            tooltip: t('ロック', 'Lock'),
            icon: const Icon(Icons.lock),
          ),
          IconButton(
            onPressed: c.busy || c.selectedProfileId == null
                ? null
                : () {
                    dismiss?.call();
                    _open(null);
                  },
            tooltip: t('新しいメモ', 'New note'),
            icon: const Icon(Icons.add),
          ),
          IconButton(
            key: const ValueKey('sync-v2-archive-toggle'),
            tooltip: _archiveView ? t('一覧', 'List') : t('アーカイブ', 'Archive'),
            icon: Icon(_archiveView ? Icons.view_list : Icons.archive_outlined),
            onPressed: c.busy || _editorOpen
                ? null
                : () {
                    dismiss?.call();
                    setState(() {
                      _archiveView = !_archiveView;
                      _trashView = false;
                      _calendarView = false;
                      _insightsView = false;
                    });
                  },
          ),
          if (dismiss != null)
            IconButton(
              key: const ValueKey('sync-v2-profile-trash'),
              tooltip: _trashView ? t('一覧', 'List') : t('ゴミ箱', 'Trash'),
              icon: Icon(_trashView ? Icons.view_list : Icons.delete_outline),
              onPressed: c.busy || _editorOpen
                  ? null
                  : () {
                      dismiss();
                      setState(() {
                        _trashView = !_trashView;
                        _archiveView = false;
                        _calendarView = false;
                        _insightsView = false;
                      });
                    },
            ),
          PopupMenuButton<String>(
            routeSettings: const RouteSettings(name: _syncV2AdminMenuRoute),
            enabled: !c.busy,
            onSelected: (action) {
              dismiss?.call();
              _adminAction(action);
            },
            itemBuilder: (_) => [
              if (!_isolatedPreview)
                PopupMenuItem(
                  value: 'sync-qr',
                  child: Text(t('他の端末をQRで追加', 'Add another device with QR')),
                ),
              PopupMenuItem(
                value: 'codes',
                child: Text(t('復元コードを表示', 'Show recovery codes')),
              ),
              if (!_isolatedPreview && c.canManageAdminCredentials)
                PopupMenuItem(
                  value: 'admin-qr',
                  child: Text(t('管理者登録用QRを表示', 'Show administrator QR')),
                ),
              if (!_isolatedPreview && c.biometricsAvailable)
                PopupMenuItem(
                  value: 'admin-scan',
                  child: Text(t('管理者登録用QRを読み取る', 'Scan administrator QR')),
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
                  child: Text(t('管理者の生体認証を有効にする', 'Enable admin biometrics')),
                ),
              if (c.biometricsAvailable)
                PopupMenuItem(
                  value: 'biometric-recover',
                  child: Text(
                    t('ADMINコードで生体認証を設定', 'Set up biometrics with ADMIN code'),
                  ),
                ),
              PopupMenuItem(
                value: 'unlock',
                child: Text(t('管理を解除', 'Unlock administration')),
              ),
              PopupMenuItem(
                value: 'recover',
                child: Text(t('管理コードで復元', 'Recover administration')),
              ),
              if (c.adminUnlocked) ...[
                PopupMenuItem(
                  value: 'create',
                  child: Text(t('プライベート作成', 'Create private profile')),
                ),
                if (c.canManageAdminCredentials)
                  PopupMenuItem(
                    value: 'password',
                    child: Text(
                      t('選択中のパスワード変更', 'Change selected profile password'),
                    ),
                  ),
                for (final conflict
                    in c.canManageAdminCredentials
                        ? c.profileConflicts
                        : const <SyncV2WorkspaceProfile>[])
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
    return KeyedSubtree(
      key: ValueKey((
        'profile-controls',
        c.privateSessionRevision,
        c.selectedProfileId,
      )),
      child: controls,
    );
  }

  Future<void> _showProfileControls(SyncV2WorkspaceController c) async {
    await _dialog<void>(
      (dialogContext) => AlertDialog(
        title: Text(t('プロファイルと同期', 'Profile and sync')),
        content: ListenableBuilder(
          listenable: c,
          builder: (_, _) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _profileControls(
                c,
                dismiss: () {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
              ),
              _displayStyleMenu(
                dismiss: () {
                  if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(t('閉じる', 'Close')),
          ),
        ],
      ),
      attachment: true,
    );
  }

  Widget _displayStyleMenu({VoidCallback? dismiss}) =>
      PopupMenuButton<SyncV2DisplayStyle>(
        key: const ValueKey('sync-v2-display-style'),
        tooltip: t('表示デザイン', 'Display design'),
        icon: const Icon(Icons.view_agenda_outlined),
        onSelected: (style) {
          dismiss?.call();
          _setDisplayStyle(style);
        },
        itemBuilder: (_) => [
          for (final style in SyncV2DisplayStyle.values)
            PopupMenuItem(
              value: style,
              child: Row(
                children: [
                  Icon(
                    (_originalDesign == (style == SyncV2DisplayStyle.original))
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
      );

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(syncV2WorkspaceProvider);
    final density = ref.watch(notesListDensityControllerProvider);
    final sortField = ref.watch(notesListSortControllerProvider);
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => Scaffold(
        appBar: AppBar(
          title: _originalDesign && c.registered
              ? const HomeBrandTitle()
              : Text(
                  widget.localOnly
                      ? t('暗号化メモ（ローカル）', 'Encrypted notes (local)')
                      : widget.cloudSandbox
                      ? t('CloudKit 開発サンドボックス', 'CloudKit development sandbox')
                      : t('暗号化同期 v2', 'Encrypted sync v2'),
                ),
          actions: [
            if (_originalDesign && c.registered && _foreground)
              IconButton(
                key: const ValueKey('sync-v2-profile-actions'),
                tooltip: t('プロファイルと同期', 'Profile and sync'),
                icon: const Icon(Icons.lock_outline_rounded),
                onPressed: c.busy || _editorOpen
                    ? null
                    : () => _showProfileControls(c),
              ),
            if (!_isolatedPreview && !(_originalDesign && c.registered))
              IconButton(
                key: const ValueKey('sync-v2-open-settings'),
                tooltip: t('設定', 'Settings'),
                icon: const Icon(Icons.settings_outlined),
                onPressed: _editorOpen ? null : () => context.go('/settings'),
              ),
            if (c.registered && !_originalDesign)
              IconButton(
                key: const ValueKey('sync-v2-trash-toggle'),
                tooltip: _trashView ? t('一覧', 'List') : t('ごみ箱', 'Trash'),
                icon: Icon(_trashView ? Icons.view_list : Icons.delete_outline),
                onPressed: _editorOpen
                    ? null
                    : () => setState(() {
                        _trashView = !_trashView;
                        _calendarView = false;
                        _insightsView = false;
                        _archiveView = false;
                      }),
              ),
            if (c.registered && !_originalDesign)
              IconButton(
                key: const ValueKey('sync-v2-calendar-toggle'),
                tooltip: _calendarView
                    ? t('一覧', 'List')
                    : t('カレンダー', 'Calendar'),
                icon: Icon(
                  _calendarView ? Icons.view_list : Icons.calendar_month,
                ),
                onPressed: _editorOpen
                    ? null
                    : () => setState(() {
                        _calendarView = !_calendarView;
                        _trashView = false;
                        _insightsView = false;
                        _archiveView = false;
                      }),
              ),
            if (c.registered && !_originalDesign)
              IconButton(
                key: const ValueKey('sync-v2-insights-toggle'),
                tooltip: _insightsView
                    ? t('一覧', 'List')
                    : t('インサイト', 'Insights'),
                icon: Icon(
                  _insightsView ? Icons.view_list : Icons.insights_outlined,
                ),
                onPressed: _editorOpen
                    ? null
                    : () => setState(() {
                        _insightsView = !_insightsView;
                        _calendarView = false;
                        _trashView = false;
                        _archiveView = false;
                      }),
              ),
            if (c.registered && (!_originalDesign || _editorOpen))
              _displayStyleMenu(),
            if (!widget.localOnly)
              IconButton(
                onPressed: c.busy || !c.registered
                    ? null
                    : () => _run(c.syncNow),
                tooltip: t('同期', 'Sync'),
                icon: const Icon(Icons.sync),
              ),
          ],
        ),
        body: _withV1Sidebar(
          c,
          !_foreground
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
                            child: Text(
                              t('同期コードで復元', 'Recover with sync code'),
                            ),
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
                                        widget.localOnly
                                            ? t(
                                                'ローカルの暗号化メモを始める',
                                                'Set up local encrypted notes',
                                              )
                                            : t(
                                                '暗号化同期を始める',
                                                'Set up encrypted sync',
                                              ),
                                        style: Theme.of(context)
                                            .textTheme
                                            .headlineSmall,
                                      ),
                                      const SizedBox(height: 16),
                                      if (!_isolatedPreview)
                                        FilledButton.icon(
                                          key: const ValueKey(
                                            'sync-v2-scan-join',
                                          ),
                                          onPressed: c.busy || !c.supported
                                              ? null
                                              : () => _scanPairing(),
                                          icon: const Icon(
                                            Icons.qr_code_scanner,
                                          ),
                                          label: Text(
                                            t(
                                              'QRを読み取って参加',
                                              'Join by scanning QR',
                                            ),
                                          ),
                                        ),
                                      if (!_isolatedPreview)
                                        const SizedBox(height: 12),
                                      Text(
                                        widget.localOnly
                                            ? t(
                                                'このブラウザで初めて利用する場合',
                                                'For first use in this browser',
                                              )
                                            : t(
                                                '初めて利用する場合',
                                                'For your first device',
                                              ),
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
                                            widget.localOnly
                                                ? '復元コード（SYNC）で復元'
                                                : '同期復元コードで復元',
                                            widget.localOnly
                                                ? 'Restore with recovery code (SYNC)'
                                                : 'Restore with sync recovery code',
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
                                final profileControls = _originalDesign
                                    ? const SizedBox.shrink()
                                    : _profileControls(c);
                                final list = Column(
                                  children: [
                                    if (!_originalDesign &&
                                        !_calendarView &&
                                        !_trashView &&
                                        !_archiveView)
                                      profileControls,
                                    Expanded(
                                      child: _insightsView
                                          ? c.selectedProfileId == null
                                                ? const SizedBox.shrink()
                                                : SyncV2InsightsView(
                                                    key: ValueKey((
                                                      c.selectedProfileId,
                                                      c.privateSessionRevision,
                                                    )),
                                                    profileId:
                                                        c.selectedProfileId!,
                                                    notes: c.notes,
                                                    onAddNote: () =>
                                                        _open(null),
                                                    onOpenNotes: () => setState(
                                                      () =>
                                                          _insightsView = false,
                                                    ),
                                                  )
                                          : _trashView
                                          ? _trash(c, profileControls)
                                          : _archiveView
                                          ? _archive(c, profileControls)
                                          : _calendarView
                                          ? _calendar(c, profileControls)
                                          : _noteList(
                                              c,
                                              density: density,
                                              sortField: sortField,
                                              header: _originalDesign
                                                  ? Column(
                                                      children: [
                                                        profileControls,
                                                        _originalSearchToolbar(
                                                          c,
                                                          density: density,
                                                        ),
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
                                                          fileName:
                                                              'himemo.zip',
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
                                    (_originalDesign ? 700 : 800)) {
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
                                      Expanded(
                                        child: _editorOpen
                                            ? _editor(c)
                                            : Padding(
                                                key: const ValueKey(
                                                  'sync-v2-wide-preview-pane',
                                                ),
                                                padding: _originalDesign
                                                    ? const EdgeInsets.fromLTRB(
                                                        16,
                                                        12,
                                                        16,
                                                        12,
                                                      )
                                                    : EdgeInsets.zero,
                                                child: _previewPane(
                                                  c,
                                                  fullScreen: false,
                                                ),
                                              ),
                                      ),
                                    ],
                                  );
                                }
                                if (_editorOpen) {
                                  return _mobileNoteSwipe(c, _editor(c));
                                }
                                if (_selectedPreview != null) {
                                  return _mobileNoteSwipe(
                                    c,
                                    _previewPane(c, fullScreen: true),
                                  );
                                }
                                return list;
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
                    if (!_isolatedPreview)
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
        bottomNavigationBar:
            _showV1Navigation(c) &&
                MediaQuery.sizeOf(context).width < 840 &&
                !_editorOpen
            ? _navigation(c, wide: false)
            : null,
      ),
    );
  }

  List<SyncV2WorkspaceNote> _visibleNotes(
    SyncV2WorkspaceController c, {
    required NotesListSortField sortField,
  }) {
    final result = c.notes
        .where(
          (entry) => syncV2NoteMatchesFilters(
            entry,
            _searchFilters,
            profileId: c.selectedProfileId,
            query: _query,
          ),
        )
        .toList();
    result.sort((a, b) {
      if (a.note.isPinned != b.note.isPinned) return a.note.isPinned ? -1 : 1;
      final am = sortField == NotesListSortField.createdAt
          ? a.note.createdAt
          : a.note.updatedAt ?? a.note.createdAt;
      final bm = sortField == NotesListSortField.createdAt
          ? b.note.createdAt
          : b.note.updatedAt ?? b.note.createdAt;
      final compared = bm.compareTo(am);
      return compared == 0 ? a.note.id.compareTo(b.note.id) : compared;
    });
    return result;
  }

  Widget _originalSearchToolbar(
    SyncV2WorkspaceController c, {
    required NotesListDensity density,
  }) {
    final compactButtons = MediaQuery.sizeOf(context).width < 560;
    final count =
        (_searchFilters.pinnedOnly ? 1 : 0) +
        (_searchFilters.attachmentFilters.isNotEmpty ? 1 : 0) +
        (_searchFilters.archivedOnly || _searchFilters.includeArchived
            ? 1
            : 0) +
        (_searchFilters.dateRange != SearchDateRange.all ? 1 : 0) +
        (_searchFilters.year != null ? 1 : 0) +
        _searchFilters.tags.length +
        (_searchFilters.requireAllTags && _searchFilters.tags.length > 1
            ? 1
            : 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: HomeNoteSection(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            HomeSearchToolbar(
              controller: _search,
              searchBoundaryKey: ValueKey((
                c.privateSessionRevision,
                c.selectedProfileId,
              )),
              searchKey: const ValueKey('sync-v2-search'),
              densityKey: const ValueKey('sync-v2-density'),
              detailsKey: const ValueKey('sync-v2-search-filters'),
              filterCountKey: const ValueKey('sync-v2-filter-count'),
              density: density,
              showDensityControl: false,
              alignSearchHeight: true,
              searchLabel: t('検索', 'Search'),
              searchHint: t(
                'ノートや添付ファイル名を検索',
                'Search notes and attachment names',
              ),
              clearLabel: t('検索をクリア', 'Clear search'),
              layoutLabel: t('一覧の表示', 'List layout'),
              standardLabel: t('標準表示', 'Standard list'),
              compactLabel: t('コンパクト表示', 'Compact list'),
              detailsLabel: t('詳細', 'Filters'),
              filterCount: count,
              compactButtons: compactButtons,
              onQueryChanged: (value) => setState(() => _query = value),
              onClear: () => setState(() {
                _search.clear();
                _query = '';
              }),
              onDensityChanged: (value) => unawaited(
                _run(
                  () => ref
                      .read(notesListDensityControllerProvider.notifier)
                      .setDensity(value),
                ),
              ),
              onDetailsPressed: () => _openSearchFilters(c),
            ),
            _tagChips(c),
            _activeSearchFilterChips(c),
            if (!_searchFilters.isDefault &&
                MediaQuery.sizeOf(context).width < 1180)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  key: const ValueKey('sync-v2-clear-filters'),
                  onPressed: () =>
                      setState(() => _searchFilters = const SearchFilters()),
                  icon: const Icon(Icons.filter_alt_off_outlined),
                  label: Text(t('絞り込みを解除', 'Clear filters')),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _activeSearchFilterChips(SyncV2WorkspaceController c) {
    final filters = _searchFilters;
    final quickTagKeys = <String>{
      for (final entry in c.notes)
        if (entry.note.vaultId == c.selectedProfileId &&
            entry.ready &&
            !entry.isConflict &&
            !entry.isDeleted &&
            entry.note.deletedAt == null &&
            entry.note.archivedAt == null)
          for (final tag in entry.note.normalizedTags) canonicalizeNoteTag(tag),
    };
    final chips = <Widget>[];
    void add(String label, SearchFilters Function() clear) {
      chips.add(
        InputChip(
          label: Text(label),
          onDeleted: () => setState(() => _searchFilters = clear()),
        ),
      );
    }

    if (filters.pinnedOnly) {
      add(t('ピン留め', 'Pinned'), () => filters.copyWith(pinnedOnly: false));
    }
    if (filters.tags.isNotEmpty) {
      for (final tag in filters.tags) {
        if (quickTagKeys.contains(canonicalizeNoteTag(tag))) continue;
        add('#$tag', () {
          final remaining = filters.tags
              .where((value) => value != tag)
              .toList();
          return filters.copyWith(
            tags: remaining,
            requireAllTags: remaining.length > 1 && filters.requireAllTags,
          );
        });
      }
      if (filters.requireAllTags && filters.tags.length > 1) {
        add(
          t('タグ: すべて', 'All tags'),
          () => filters.copyWith(requireAllTags: false),
        );
      }
    }
    for (final type in filters.attachmentFilters) {
      final label = switch (type) {
        SearchAttachmentFilter.all => t('すべて', 'All'),
        SearchAttachmentFilter.any => t('添付あり', 'Attachments'),
        SearchAttachmentFilter.photo => t('画像', 'Images'),
        SearchAttachmentFilter.video => t('動画', 'Videos'),
        SearchAttachmentFilter.audio => t('音声', 'Audio'),
        SearchAttachmentFilter.location => t('位置情報', 'Location'),
      };
      add(
        label,
        () => filters.copyWith(
          attachmentFilters: filters.attachmentFilters
              .where((value) => value != type)
              .toList(),
        ),
      );
    }
    if (filters.dateRange != SearchDateRange.all) {
      final label = switch (filters.dateRange) {
        SearchDateRange.all => '',
        SearchDateRange.last7Days => t('直近7日', 'Last 7 days'),
        SearchDateRange.last30Days => t('直近30日', 'Last 30 days'),
        SearchDateRange.thisMonth => t('今月', 'This month'),
      };
      final field = filters.dateField == SearchDateField.updatedAt
          ? t('更新日', 'Updated')
          : t('作成日', 'Created');
      add(
        '$field: $label',
        () => filters.copyWith(
          dateRange: SearchDateRange.all,
          dateField: SearchDateField.createdAt,
        ),
      );
    }
    if (filters.year != null) {
      add('${filters.year}', () => filters.copyWith(clearYear: true));
    }
    if (filters.archivedOnly || filters.includeArchived) {
      add(
        filters.archivedOnly
            ? t('アーカイブのみ', 'Archive only')
            : t('アーカイブを含む', 'Include archive'),
        () => filters.copyWith(archivedOnly: false, includeArchived: false),
      );
    }
    if (chips.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Wrap(spacing: 6, runSpacing: 4, children: chips),
    );
  }

  Future<void> _openSearchFilters(SyncV2WorkspaceController c) async {
    final profile = c.selectedProfileId;
    final revision = c.privateSessionRevision;
    if (profile == null || !_foreground) return;
    final entries = c.notes
        .where(
          (entry) =>
              entry.note.vaultId == profile &&
              entry.ready &&
              !entry.isConflict &&
              !entry.isDeleted &&
              entry.note.deletedAt == null,
        )
        .toList();
    final tags = dedupeNoteTags(
      entries.expand((entry) => entry.note.normalizedTags),
    );
    final years =
        entries
            .map((entry) => entry.note.createdAt.toLocal().year)
            .toSet()
            .toList()
          ..sort((a, b) => b.compareTo(a));
    final initialDensity = ref.read(notesListDensityControllerProvider);
    final initialSort = ref.read(notesListSortControllerProvider);
    final result = await _dialog<SyncV2SearchControlsResult>(
      (_) => SyncV2SearchFiltersDialog(
        initialFilters: _searchFilters,
        availableTags: tags,
        availableYears: years,
        hasArchivedNotes: entries.any((entry) => entry.note.archivedAt != null),
        initialDensity: initialDensity,
        initialSort: initialSort,
      ),
      attachment: true,
    );
    if (!mounted ||
        !_foreground ||
        result == null ||
        c.selectedProfileId != profile ||
        c.privateSessionRevision != revision) {
      return;
    }
    setState(() => _searchFilters = result.filters);
    await _run(() async {
      if (result.density != initialDensity) {
        await ref
            .read(notesListDensityControllerProvider.notifier)
            .setDensity(result.density);
      }
      if (!mounted ||
          !_foreground ||
          c.selectedProfileId != profile ||
          c.privateSessionRevision != revision) {
        return;
      }
      if (result.sort != initialSort) {
        await ref
            .read(notesListSortControllerProvider.notifier)
            .setSortField(result.sort);
      }
    });
  }

  Widget _tagChips(SyncV2WorkspaceController c) {
    if (c.selectedProfileId == null) return const SizedBox.shrink();
    final summaries = syncV2TagSummaries(c.notes, c.selectedProfileId);
    final wide = MediaQuery.sizeOf(context).width >= 1180;
    if (summaries.isEmpty && wide) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          Expanded(
            child: KeyedSubtree(
              key: const ValueKey('sync-v2-tag-chips'),
              child: HomeQuickTagStrip(
                summaries: summaries,
                activeTags: _searchFilters.tags,
                onTagSelected: (tag) => setState(() {
                  final key = canonicalizeNoteTag(tag);
                  final selected = _searchFilters.tags.any(
                    (item) => canonicalizeNoteTag(item) == key,
                  );
                  final tags = _searchFilters.tags
                      .where((item) => canonicalizeNoteTag(item) != key)
                      .toList();
                  if (!selected) tags.add(tag);
                  _searchFilters = _searchFilters.copyWith(
                    tags: tags,
                    requireAllTags:
                        tags.length > 1 && _searchFilters.requireAllTags,
                  );
                  _search.clear();
                  _query = '';
                  _clearSelectedPreview();
                }),
              ),
            ),
          ),
          if (!wide)
            IconButton(
              key: const ValueKey('sync-v2-tag-manage'),
              tooltip: t('タグを管理', 'Manage tags'),
              onPressed: c.busy || _editorOpen
                  ? null
                  : () => _manageTags(
                      c,
                      summaries.map((item) => item.name).toList(),
                    ),
              icon: const Icon(Icons.sell_outlined),
            ),
        ],
      ),
    );
  }

  Widget _trash(SyncV2WorkspaceController c, Widget controls) {
    final deleted = c.notes
        .where(
          (entry) =>
              entry.note.vaultId == c.selectedProfileId &&
              (entry.isDeleted || entry.note.deletedAt != null),
        )
        .toList();
    return ListView(
      key: const ValueKey('sync-v2-trash'),
      padding: const EdgeInsets.all(16),
      children: [
        controls,
        Text(t('ごみ箱', 'Trash'), style: Theme.of(context).textTheme.titleLarge),
        Text(
          t(
            '削除前の履歴を取得できるメモを復元できます。',
            'Notes can be restored when their prior history is available.',
          ),
        ),
        if (deleted.isEmpty) Text(t('削除済みのメモはありません', 'No deleted notes')),
        for (final note in deleted)
          ListTile(
            key: ValueKey('sync-v2-trash-note-${note.note.id}'),
            title: Text(
              !note.ready || note.isConflict || note.note.title.isEmpty
                  ? t('削除済みメモ', 'Deleted note')
                  : note.note.title,
            ),
            subtitle: Text(
              note.ready && !note.isConflict
                  ? note.note.id
                  : t('同期または競合解決が必要です', 'Sync or conflict resolution required'),
            ),
            trailing: TextButton(
              key: ValueKey('sync-v2-restore-${note.note.id}'),
              onPressed: c.busy || !note.ready || note.isConflict
                  ? null
                  : () => _run(() => c.restoreDeletedNote(note)),
              child: Text(t('復元', 'Restore')),
            ),
          ),
      ],
    );
  }

  Widget _archive(SyncV2WorkspaceController c, Widget controls) {
    final archived = c.notes
        .where(
          (entry) =>
              entry.note.vaultId == c.selectedProfileId &&
              entry.note.archivedAt != null &&
              !entry.isDeleted &&
              entry.note.deletedAt == null,
        )
        .toList();
    return ListView(
      key: const ValueKey('sync-v2-archive'),
      padding: const EdgeInsets.all(16),
      children: [
        controls,
        Text(
          t('アーカイブ', 'Archive'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        if (archived.isEmpty) Text(t('アーカイブ済みのメモはありません', 'No archived notes')),
        for (final note in archived)
          ListTile(
            key: ValueKey('sync-v2-archive-note-${note.note.id}'),
            title: Text(
              !note.ready || note.isConflict || note.note.title.isEmpty
                  ? t('無題', 'Untitled')
                  : note.note.title,
            ),
            subtitle: Text(
              note.ready && !note.isConflict
                  ? note.note.body
                  : t('同期または競合解決が必要です', 'Sync or conflict resolution required'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: TextButton(
              key: ValueKey('sync-v2-unarchive-${note.note.id}'),
              onPressed: c.busy || !note.ready || note.isConflict
                  ? null
                  : () => _run(() => c.setNoteArchived(note, archived: false)),
              child: Text(t('解除', 'Unarchive')),
            ),
          ),
      ],
    );
  }

  Widget _calendar(SyncV2WorkspaceController c, Widget controls) {
    final entries = c.notes
        .where(
          (entry) =>
              entry.ready &&
              !entry.isConflict &&
              !entry.isDeleted &&
              entry.note.deletedAt == null &&
              entry.note.archivedAt == null &&
              entry.note.vaultId == c.selectedProfileId,
        )
        .toList();
    final dayNotes = entries.where((entry) {
      final date = entry.note.createdAt;
      return date.year == _calendarDay.year &&
          date.month == _calendarDay.month &&
          date.day == _calendarDay.day;
    }).toList();
    return ListView(
      key: const ValueKey('sync-v2-calendar'),
      padding: const EdgeInsets.all(16),
      children: [
        controls,
        HomeNoteSection(
          child: MarkedNoteCalendar.fromNotes(
            visibleMonth: _calendarMonth,
            selectedDay: _calendarDay,
            notes: entries.map((entry) => entry.note),
            onPreviousMonth: () => setState(
              () => _calendarMonth = DateTime(
                _calendarMonth.year,
                _calendarMonth.month - 1,
              ),
            ),
            onNextMonth: () => setState(
              () => _calendarMonth = DateTime(
                _calendarMonth.year,
                _calendarMonth.month + 1,
              ),
            ),
            onTodaySelected: () => setState(() {
              _calendarDay = DateTime.now();
              _calendarMonth = DateTime(_calendarDay.year, _calendarDay.month);
            }),
            onDateSelected: (day) => setState(() {
              _calendarDay = day;
              _calendarMonth = DateTime(day.year, day.month);
            }),
          ),
        ),
        const SizedBox(height: 16),
        HomeNoteSection(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_calendarDay.year}/${_calendarDay.month.toString().padLeft(2, '0')}/${_calendarDay.day.toString().padLeft(2, '0')}',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              if (dayNotes.isEmpty)
                Text(t('この日のメモはありません', 'No notes on this day')),
              for (final entry in dayNotes)
                Material(
                  color: Colors.transparent,
                  child: ListTile(
                    key: ValueKey('sync-v2-calendar-note-${entry.note.id}'),
                    title: Text(entry.note.title),
                    subtitle: Text(
                      entry.note.body,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: c.busy ? null : () => _showPreview(entry),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tagFilter(SyncV2WorkspaceController c) {
    final tags = dedupeNoteTags(
      c.notes
          .where(
            (entry) =>
                entry.ready &&
                !entry.isConflict &&
                !entry.isDeleted &&
                entry.note.deletedAt == null &&
                entry.note.archivedAt == null &&
                entry.note.vaultId == c.selectedProfileId,
          )
          .expand((entry) => entry.note.normalizedTags),
    );
    final activeTag = _searchFilters.tags.length == 1
        ? canonicalizeNoteTag(_searchFilters.tags.single)
        : null;
    final active = tags.any((tag) => canonicalizeNoteTag(tag) == activeTag)
        ? activeTag
        : null;
    return Row(
      children: [
        Expanded(
          child: DropdownButton<String>(
            key: const ValueKey('sync-v2-tag-filter'),
            value: active,
            hint: Text(t('すべてのタグ', 'All tags')),
            isExpanded: true,
            onChanged: (value) => setState(
              () => _searchFilters = _searchFilters.copyWith(
                tags: value == null || value.isEmpty ? [] : [value],
                requireAllTags: false,
              ),
            ),
            items: [
              DropdownMenuItem(value: '', child: Text(t('すべてのタグ', 'All tags'))),
              for (final tag in tags)
                DropdownMenuItem(
                  value: canonicalizeNoteTag(tag),
                  child: Text(tag, overflow: TextOverflow.ellipsis),
                ),
            ],
          ),
        ),
        IconButton(
          key: const ValueKey('sync-v2-tag-manage'),
          tooltip: t('タグを管理', 'Manage tags'),
          onPressed: c.busy || _editorOpen ? null : () => _manageTags(c, tags),
          icon: const Icon(Icons.sell_outlined),
        ),
      ],
    );
  }

  Future<void> _manageTags(
    SyncV2WorkspaceController c,
    List<String> tags,
  ) async {
    final profile = c.selectedProfileId;
    final session = c.privateSessionRevision;
    bool active() =>
        mounted &&
        _foreground &&
        c.selectedProfileId == profile &&
        c.privateSessionRevision == session;
    final choice = await _dialog<(String?, bool?)>(
      (context) => AlertDialog(
        title: Text(t('タグを管理', 'Manage tags')),
        content: SizedBox(
          width: 420,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  key: const ValueKey('sync-v2-auto-tag-manage'),
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(t('自動タグ付与ルール', 'Automatic tag rules')),
                  onTap: () => Navigator.pop(context, (null, null)),
                ),
                for (final tag in tags)
                  ListTile(
                    title: Text(tag),
                    trailing: Wrap(
                      children: [
                        IconButton(
                          tooltip: t('名前を変更', 'Rename'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => Navigator.pop(context, (tag, true)),
                        ),
                        IconButton(
                          tooltip: t('タグを削除', 'Delete tag'),
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => Navigator.pop(context, (tag, false)),
                        ),
                      ],
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
    if (choice == null || !active()) return;
    if (choice.$1 == null) {
      await _manageAutoTagRules(c);
      return;
    }
    final tag = choice.$1!;
    String? replacement;
    if (choice.$2 == true) {
      replacement = await _input(t('新しいタグ名', 'New tag name'), secret: false);
      if (replacement == null || !active()) return;
    } else if (!await _confirm(
          t('タグを削除', 'Delete tag'),
          t(
            'このタグを選択中のプロファイルのメモから削除しますか？',
            'Remove this tag from notes in the selected profile?',
          ),
        ) ||
        !active()) {
      return;
    }
    if (!active()) return;
    await _run(() => c.updateTag(tag, replacement: replacement));
    if (active()) {
      setState(
        () => _searchFilters = _searchFilters.copyWith(
          tags: [],
          requireAllTags: false,
        ),
      );
    }
  }

  Future<void> _manageAutoTagRules(SyncV2WorkspaceController c) async {
    final profile = c.selectedProfileId;
    final session = c.privateSessionRevision;
    bool active() =>
        mounted &&
        _foreground &&
        profile != null &&
        c.selectedProfileId == profile &&
        c.privateSessionRevision == session;
    if (!active()) return;
    final notifier = ref.read(autoTagRulesControllerProvider.notifier);
    await notifier.restoreCompleted;
    while (active()) {
      final action = await _dialog<(String, AutoTagRule?, bool?)>(
        (dialogContext) => AlertDialog(
          title: Text(t('自動タグ付与ルール', 'Automatic tag rules')),
          content: SizedBox(
            width: 480,
            child: SingleChildScrollView(
              child: Consumer(
                builder: (context, ref, _) {
                  final rules = ref.watch(autoTagRulesControllerProvider);
                  return SyncV2AutoTagRulesPanel(
                    rules: rules,
                    onAdd: () =>
                        Navigator.pop(dialogContext, ('add', null, null)),
                    onEdit: (rule) =>
                        Navigator.pop(dialogContext, ('edit', rule, null)),
                    onDelete: (rule) =>
                        Navigator.pop(dialogContext, ('delete', rule, null)),
                    onToggle: (rule, value) =>
                        Navigator.pop(dialogContext, ('toggle', rule, value)),
                    onApply: () =>
                        Navigator.pop(dialogContext, ('apply', null, null)),
                  );
                },
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(t('閉じる', 'Close')),
            ),
          ],
        ),
      );
      if (action == null || !active()) return;
      final rule = action.$2;
      if (action.$1 == 'add' || action.$1 == 'edit') {
        final draft = await _dialog<SyncV2AutoTagRuleDraft>(
          (_) => SyncV2AutoTagRuleEditorDialog(initialRule: rule),
        );
        if (draft == null || !active()) continue;
        if (rule == null) {
          await notifier.addRule(
            tag: draft.tag,
            keywords: draft.keywords,
            matchTitle: draft.matchTitle,
            matchBody: draft.matchBody,
            matchAttachments: draft.matchAttachments,
          );
        } else {
          await notifier.updateRule(
            id: rule.id,
            tag: draft.tag,
            keywords: draft.keywords,
            matchTitle: draft.matchTitle,
            matchBody: draft.matchBody,
            matchAttachments: draft.matchAttachments,
          );
        }
      } else if (action.$1 == 'toggle' && rule != null) {
        await notifier.setEnabled(rule.id, action.$3 == true);
      } else if (action.$1 == 'delete' && rule != null) {
        if (await _confirm(
              t('ルールを削除', 'Delete rule'),
              t('この自動付与ルールを削除しますか？', 'Delete this automatic tagging rule?'),
            ) &&
            active()) {
          await notifier.removeRule(rule.id);
        }
      } else if (action.$1 == 'apply') {
        await _applyAutoTagRules(c, active);
      }
    }
  }

  Future<void> _applyAutoTagRules(
    SyncV2WorkspaceController c,
    bool Function() active,
  ) async {
    if (!active()) return;
    final edits = planSyncV2AutoTagEdits(
      notes: c.notes,
      rules: ref.read(autoTagRulesControllerProvider),
      selectedProfileId: c.selectedProfileId,
      locked: !active(),
    );
    if (edits.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t('適用対象のメモはありません。', 'No notes need tagging.'))),
      );
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await _confirm(
      t('自動タグを適用', 'Apply automatic tags'),
      t(
        '${edits.length}件のメモに適用します。未取得・競合中のメモは対象外です。',
        'Apply to ${edits.length} notes? Unavailable and conflicting notes are skipped.',
      ),
    );
    if (!confirmed || !active()) return;
    var completed = 0;
    try {
      for (final edit in edits.entries) {
        if (!active()) return;
        await c.saveNote(
          original: edit.key,
          title: edit.key.note.title,
          body: edit.key.note.body,
          tags: edit.value,
        );
        completed++;
      }
      if (active()) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              t('$completed件に適用しました。', 'Applied to $completed notes.'),
            ),
          ),
        );
      }
    } catch (_) {
      if (active()) {
        messenger.showSnackBar(
          SnackBar(
            content: Text(
              t(
                '$completed件に適用後、中断しました。同期状態を確認してください。',
                'Stopped after $completed notes. Check sync and try again.',
              ),
            ),
          ),
        );
      }
    }
  }

  Widget _tagEditor(bool writable) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Wrap(
        spacing: 6,
        children: [
          for (final tag in _draftTags)
            InputChip(
              label: Text(tag),
              onDeleted: writable
                  ? () => setState(() => _draftTags.remove(tag))
                  : null,
            ),
        ],
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('sync-v2-tag-input'),
              controller: _tagInput,
              readOnly: !writable,
              decoration: InputDecoration(labelText: t('タグ', 'Tag')),
              onChanged: (_) => setState(() {}),
              onSubmitted: writable ? (_) => _addDraftTag() : null,
            ),
          ),
          IconButton(
            key: const ValueKey('sync-v2-tag-add'),
            tooltip: t('タグを追加', 'Add tag'),
            onPressed: writable ? _addDraftTag : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    ],
  );

  void _addDraftTag() => setState(() {
    _draftTags = List.of(dedupeNoteTags([..._draftTags, _tagInput.text]));
    _tagInput.clear();
  });

  bool _archiveDraftIsClean() {
    final editing = _editing;
    if (editing == null ||
        _pickingAttachments ||
        _attachmentPickerInterrupted ||
        _added.isNotEmpty ||
        _removed.isNotEmpty) {
      return false;
    }
    final note = editing.note;
    if (_title.text != note.title ||
        _body.text != syncV2EditableBody(note) ||
        _draftPinned != note.isPinned ||
        _draftLocation != note.location ||
        _draftEditorMode != note.editorMode ||
        !listEquals(
          dedupeNoteTags([..._draftTags, _tagInput.text]),
          note.normalizedTags,
        )) {
      return false;
    }
    final originalBlocks = note.blocks.isEmpty
        ? [NoteBlock(type: NoteBlockType.paragraph, text: _body.text)]
        : note.blocks;
    if (_draftEditorMode != NoteEditorMode.quick &&
        !listEquals(_draftBlocks, originalBlocks)) {
      return false;
    }
    return listEquals(_editingAttachments, editing.attachments);
  }

  bool _canArchiveNote(
    SyncV2WorkspaceController controller,
    SyncV2WorkspaceNote note,
  ) =>
      mounted &&
      _foreground &&
      !controller.busy &&
      _editorOpen &&
      identical(_editing, note) &&
      note.note.vaultId == controller.selectedProfileId &&
      controller.notes.any((entry) => identical(entry, note)) &&
      note.ready &&
      !note.isConflict &&
      !note.isDeleted &&
      note.note.deletedAt == null &&
      note.note.archivedAt == null &&
      !_pickingAttachments &&
      !_attachmentPickerInterrupted &&
      _attachmentSessionIsActive(bindView: true)() &&
      _archiveDraftIsClean();

  void _archiveNote(SyncV2WorkspaceController controller) {
    final note = _editing;
    if (note == null || !_canArchiveNote(controller, note)) {
      if (mounted) setState(() {});
      return;
    }
    unawaited(
      _run(() async {
        if (!_canArchiveNote(controller, note)) {
          if (mounted) setState(() {});
          return;
        }
        await controller.setNoteArchived(note, archived: true);
        if (mounted && identical(_editing, note)) {
          setState(() => _clearEditor(clearPreview: true));
        }
      }),
    );
  }

  Widget _noteList(
    SyncV2WorkspaceController c, {
    Widget? header,
    required NotesListDensity density,
    required NotesListSortField sortField,
  }) {
    if (!_originalDesign) {
      return ListView(
        children: [
          _tagFilter(c),
          for (final note in _visibleNotes(c, sortField: sortField))
            ListTile(
              title: Text(
                !note.ready
                    ? t('未取得またはロック中', 'Missing or locked')
                    : note.isConflict
                    ? t('競合', 'Conflict')
                    : note.isDeleted
                    ? t('削除済み', 'Deleted')
                    : note.note.title,
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
              onTap: c.busy ? null : () => _showPreview(note),
            ),
        ],
      );
    }
    final entries = _visibleNotes(c, sortField: sortField);
    final byId = {for (final entry in entries) entry.note.id: entry};
    final profile = c.profiles
        .where((p) => p.id == c.selectedProfileId)
        .firstOrNull;
    return HomeNotePreviewList(
      header: header,
      attachmentPreviewBuilder: (note, index, size) {
        final entry = byId[note.id]!;
        if (!entry.ready ||
            entry.isConflict ||
            index >= entry.attachments.length) {
          return SizedBox.square(dimension: size);
        }
        return _attachmentPreview(entry.attachments[index], size);
      },
      notes: [
        for (final entry in entries)
          entry.note.copyWith(
            title: !entry.ready
                ? t('未取得またはロック中', 'Missing or locked')
                : entry.isConflict
                ? t('競合', 'Conflict')
                : entry.isDeleted
                ? t('削除済み', 'Deleted')
                : entry.note.title,
            body: !entry.ready || entry.isConflict || entry.isDeleted
                ? ''
                : entry.note.body,
            tags: !entry.ready || entry.isConflict || entry.isDeleted
                ? const <String>[]
                : entry.note.normalizedTags,
            blocks: !entry.ready || entry.isConflict || entry.isDeleted
                ? const <NoteBlock>[]
                : entry.note.blocks,
            location: !entry.ready || entry.isConflict || entry.isDeleted
                ? null
                : entry.note.location,
            isPinned: entry.ready && !entry.isConflict && entry.note.isPinned,
            syncState: entry.isConflict
                ? NoteSyncState.conflict
                : entry.note.syncState,
            attachments: [
              for (final attachment
                  in entry.ready && !entry.isConflict
                      ? entry.attachments
                      : const <SyncV2AttachmentReference>[])
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
      selectedNoteId: _selectedPreview?.entry.note.id ?? _editing?.note.id,
      query: _query,
      density: density,
      sortField: sortField,
      onNoteSelected: (note) {
        if (!c.busy) unawaited(_showPreview(byId[note.id]!));
      },
      statusBuilder: (note) => !byId[note.id]!.ready
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                t('未取得またはロック中 · 読み取り専用', 'Missing or locked · read only'),
              ),
            )
          : byId[note.id]!.isConflict
          ? Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                t('すべての競合版から表示する版を選択', 'Choose a version to preview'),
              ),
            )
          : null,
    );
  }

  Widget _editor(SyncV2WorkspaceController c) {
    if (!_editorOpen) {
      return Center(
        child: Text(t('メモを選択、または作成してください', 'Select or create a note')),
      );
    }
    final writable = !c.busy && (_editing?.ready ?? true);
    final archiveDraftClean = _archiveDraftIsClean();
    final query = _draftSearch.text.trim().toLowerCase();
    final titleMatches = _draftSearchOffsets(_title.text, query);
    final bodyMatches = <(int, int)>[];
    for (var i = 0; i < _draftBlocks.length; i++) {
      final text = _draftBlocks[i].text;
      if (_draftBlocks[i].type == NoteBlockType.paragraph && text != null) {
        for (final offset in _draftSearchOffsets(text, query)) {
          bodyMatches.add((i, offset));
        }
      }
    }
    final totalMatches = titleMatches.length + bodyMatches.length;
    final selectedMatch = totalMatches == 0
        ? 0
        : _draftSearchMatchIndex.clamp(0, totalMatches - 1);
    final selectedBodyMatch = selectedMatch < titleMatches.length
        ? -1
        : selectedMatch - titleMatches.length;
    final selectedSearchLabel = totalMatches == 0
        ? ''
        : selectedMatch < titleMatches.length
        ? t('タイトル', 'Title')
        : t(
            '本文 ${bodyMatches[selectedBodyMatch].$1 + 1}',
            'Body ${bodyMatches[selectedBodyMatch].$1 + 1}',
          );
    void selectDraftSearchMatch(int index) {
      if (totalMatches == 0) return;
      final normalized = index % totalMatches;
      setState(() {
        _draftSearchMatchIndex = normalized;
        _draftSearchRequest++;
      });
      if (normalized < titleMatches.length) {
        _titleFocus.requestFocus();
        _title.selection = TextSelection(
          baseOffset: titleMatches[normalized],
          extentOffset: titleMatches[normalized] + query.length,
        );
      }
    }

    final draftSearchBar = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const ValueKey('sync-v2-draft-search'),
          controller: _draftSearch,
          focusNode: _draftSearchFocus,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            labelText: t('この下書き内を検索', 'Search this draft'),
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _draftSearch.text.isEmpty
                ? null
                : IconButton(
                    key: const ValueKey('sync-v2-draft-search-clear'),
                    tooltip: t('検索をクリア', 'Clear search'),
                    onPressed: () => setState(() {
                      _draftSearch.clear();
                      _draftSearchMatchIndex = 0;
                    }),
                    icon: const Icon(Icons.clear_rounded),
                  ),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onChanged: (_) => setState(() => _draftSearchMatchIndex = 0),
          onSubmitted: (_) => selectDraftSearchMatch(selectedMatch),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const ValueKey('sync-v2-draft-search-previous'),
              tooltip: t('前の一致へ', 'Previous match'),
              onPressed: totalMatches == 0
                  ? null
                  : () => selectDraftSearchMatch(
                      (selectedMatch - 1 + totalMatches) % totalMatches,
                    ),
              icon: const Icon(Icons.keyboard_arrow_up_rounded),
            ),
            Text(
              totalMatches == 0
                  ? (query.isEmpty ? '0 / 0' : t('一致なし', 'No matches'))
                  : '${selectedMatch + 1} / $totalMatches · $selectedSearchLabel',
              key: const ValueKey('sync-v2-draft-search-position'),
              style: Theme.of(context).textTheme.labelMedium,
            ),
            IconButton(
              key: const ValueKey('sync-v2-draft-search-next'),
              tooltip: t('次の一致へ', 'Next match'),
              onPressed: totalMatches == 0
                  ? null
                  : () => selectDraftSearchMatch(
                      (selectedMatch + 1) % totalMatches,
                    ),
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
            ),
          ],
        ),
      ],
    );
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
            key: ValueKey(
              'sync-v2-pending-attachment-${_added[i].draftId ?? i}',
            ),
            title: Text(_added[i].label),
            trailing: IconButton(
              onPressed: writable
                  ? () => _removePendingAttachment(_added[i])
                  : null,
              icon: const Icon(Icons.close),
            ),
          ),
      ],
    );
    final actions = Wrap(
      spacing: 8,
      children: [
        if (_editing != null &&
            _editing!.note.archivedAt == null &&
            !_editing!.isDeleted &&
            _editing!.note.deletedAt == null)
          IconButton(
            key: const ValueKey('sync-v2-note-archive'),
            tooltip: archiveDraftClean
                ? t('アーカイブ', 'Archive note')
                : t(
                    '未保存の変更があります。保存またはキャンセルしてください。',
                    'Save or cancel draft changes before archiving.',
                  ),
            onPressed:
                writable &&
                    archiveDraftClean &&
                    _editing?.isConflict != true &&
                    _editing?.ready == true
                ? () => _archiveNote(c)
                : null,
            icon: const Icon(Icons.archive_outlined),
          ),
        IconButton(
          key: const ValueKey('sync-v2-copy-draft-text'),
          tooltip: t('テキストをコピー', 'Copy text'),
          onPressed: writable ? () => _copyOrShareDraft(share: false) : null,
          icon: const Icon(Icons.copy_outlined),
        ),
        IconButton(
          key: const ValueKey('sync-v2-share-draft-text'),
          tooltip: t('テキストを共有', 'Share text'),
          onPressed: writable ? () => _copyOrShareDraft(share: true) : null,
          icon: const Icon(Icons.share_outlined),
        ),
        IconButton(
          key: const ValueKey('sync-v2-note-pin'),
          tooltip: _draftPinned
              ? t('ピン留めを解除', 'Unpin note')
              : t('このノートを固定', 'Pin this note'),
          onPressed:
              writable &&
                  _editing?.isConflict != true &&
                  _editing?.isDeleted != true
              ? () => setState(() => _draftPinned = !_draftPinned)
              : null,
          icon: Icon(
            _draftPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
            color: _draftPinned ? Theme.of(context).colorScheme.primary : null,
          ),
        ),
        TextButton.icon(
          onPressed: writable && !_pickingAttachments
              ? () => _run(_pickAttachments)
              : null,
          icon: const Icon(Icons.attach_file),
          label: Text(t('添付（64 MiBまで）', 'Attach (up to 64 MiB)')),
        ),
        FilledButton(
          onPressed: writable
              ? () => _run(() async {
                  final active = _attachmentSessionIsActive(bindView: true);
                  await ref
                      .read(autoTagRulesControllerProvider.notifier)
                      .restoreCompleted;
                  if (!active() ||
                      !_editorOpen ||
                      c.selectedProfileId == null) {
                    return;
                  }
                  final draftNote = NoteEntry(
                    id: _editing?.note.id ?? '',
                    vaultId: c.selectedProfileId!,
                    title: _title.text,
                    body: _draftEditorMode == NoteEditorMode.quick
                        ? _body.text
                        : _draftBlocks
                              .where(
                                (block) =>
                                    block.type == NoteBlockType.paragraph,
                              )
                              .map((block) => block.text ?? '')
                              .join('\n'),
                    createdAt: _editing?.note.createdAt ?? DateTime.now(),
                    tags: dedupeNoteTags([..._draftTags, _tagInput.text]),
                    attachments: [
                      for (final item in _editingAttachments)
                        if (!_removed.contains(item.id))
                          NoteAttachment(
                            type: AttachmentType.values.byName(item.type),
                            label: item.label,
                          ),
                      for (final item in _added)
                        NoteAttachment(type: item.type, label: item.label),
                    ],
                  );
                  final tags = applyAutoTagRules(
                    draftNote,
                    ref
                        .read(autoTagRulesControllerProvider)
                        .where((rule) => !isSystemSyncExclusionTag(rule.tag)),
                  ).normalizedTags;
                  await c.saveNote(
                    original: _editing,
                    selectedVersionId: _selectedVersionId,
                    title: _title.text,
                    body: _body.text,
                    blocks: _draftEditorMode == NoteEditorMode.quick
                        ? null
                        : List.of(_draftBlocks),
                    isPinned:
                        _editing?.isConflict == true ||
                            _draftPinned == (_editing?.note.isPinned ?? false)
                        ? null
                        : _draftPinned,
                    tags: tags,
                    addedFiles: List.of(_added),
                    removedAttachmentIds: List.of(_removed),
                  );
                  if (mounted) setState(() => _clearEditor(clearPreview: true));
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
                        if (mounted) {
                          setState(() => _clearEditor(clearPreview: true));
                        }
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
        titleFocusNode: _titleFocus,
        onTitleChanged: (_) => setState(() {}),
        bodyController: _body,
        richBody: SyncV2RichBlocksEditor(
          key: _richEditorKey,
          blocks: _draftBlocks,
          searchQuery: query,
          selectedSearchMatch: selectedBodyMatch,
          searchRequest: _draftSearchRequest,
          enabled: writable,
          allowStructureChanges: _draftEditorMode == NoteEditorMode.rich,
          removableAttachmentIds: _removableRichAttachmentIds(),
          onChanged: _onRichBlocksChanged,
        ),
        writable: writable,
        onClose: c.busy ? null : () => setState(_clearEditor),
        attachments: Column(
          children: [draftSearchBar, _tagEditor(writable), attachments],
        ),
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
            focusNode: _titleFocus,
            readOnly: !writable,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(labelText: t('タイトル', 'Title')),
          ),
          const SizedBox(height: 12),
          SyncV2RichBlocksEditor(
            key: _richEditorKey,
            blocks: _draftBlocks,
            searchQuery: query,
            selectedSearchMatch: selectedBodyMatch,
            searchRequest: _draftSearchRequest,
            enabled: writable,
            allowStructureChanges: _draftEditorMode == NoteEditorMode.rich,
            removableAttachmentIds: _removableRichAttachmentIds(),
            onChanged: _onRichBlocksChanged,
          ),
          const SizedBox(height: 12),
          draftSearchBar,
          _tagEditor(writable),
          attachments,
          actions,
        ],
      ),
    );
  }
}

class _MobileNoteSwipeRegion extends StatefulWidget {
  const _MobileNoteSwipeRegion({required this.child, required this.onDismiss});
  final Widget child;
  final VoidCallback onDismiss;

  @override
  State<_MobileNoteSwipeRegion> createState() => _MobileNoteSwipeRegionState();
}

class _MobileNoteSwipeRegionState extends State<_MobileNoteSwipeRegion> {
  Offset? _start;
  int? _pointer;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Listener(
      key: const ValueKey('sync-v2-note-swipe-region'),
      behavior: HitTestBehavior.translucent,
      onPointerDown: (event) {
        if (event.kind != PointerDeviceKind.touch) return;
        if (_pointer != null) {
          _pointer = null;
          _start = null;
          return;
        }
        _pointer = event.pointer;
        _start = event.localPosition;
      },
      onPointerCancel: (event) {
        if (event.pointer == _pointer) {
          _pointer = null;
          _start = null;
        }
      },
      onPointerUp: (event) {
        if (event.pointer != _pointer || _start == null) return;
        final start = _start!;
        final delta = event.localPosition - start;
        _pointer = null;
        _start = null;
        final horizontal =
            delta.dx.abs() >= 90 &&
            delta.dx.abs() > delta.dy.abs() * 1.5 &&
            ((start.dx >= constraints.maxWidth - 48 && delta.dx < 0) ||
                (start.dx <= 48 && delta.dx > 0));
        final downward =
            start.dy <= 56 && delta.dy >= 90 && delta.dy > delta.dx.abs() * 1.5;
        if (horizontal || downward) widget.onDismiss();
      },
      child: Column(
        children: [
          SizedBox(
            height: 20,
            child: Center(
              child: Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).dividerColor,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
          ),
          Expanded(child: widget.child),
        ],
      ),
    ),
  );
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
