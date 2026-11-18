import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../home/domain/note_entry.dart';
import '../data/sync_v2_note_repository.dart';
import '../data/sync_v2_note_store.dart';
import 'sync_v2_note_store_provider.dart';
import 'sync_v2_privacy.dart';
import 'sync_v2_workspace.dart';

Future<bool> showSyncV2ConflictDialog(
  BuildContext context,
  WidgetRef ref,
  NoteEntry note,
) async {
  final store = ref.read(noteStoreProvider);
  final ja = Localizations.localeOf(context).languageCode == 'ja';
  if (store is! SyncV2NoteStore) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ja
              ? '同期の準備が整っていません。設定を確認してください。'
              : 'Sync is not ready. Check your settings.',
        ),
      ),
    );
    return false;
  }
  final workspace = ref.read(syncV2WorkspaceProvider);
  final session = workspace.noteStoreSession;
  if (session == null ||
      session.profiles[SyncV2NoteStore.profileIdFor(session, note.vaultId)] ==
          null) {
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(
        content: Text(
          ja
              ? 'このプロファイルを解除してから、競合を確認してください。'
              : 'Unlock this profile before reviewing its conflict.',
        ),
      ),
    );
    return false;
  }
  late final DialogRoute<bool> route;
  route = DialogRoute<bool>(
    context: context,
    builder: (_) => _ConflictDialog(
      note: note,
      store: store,
      workspace: workspace,
      onInvalidated: () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (route.isActive) route.navigator?.removeRoute(route);
        });
      },
    ),
  );
  final privacy = ref.read(syncV2PrivacyRouteProvider.notifier);
  privacy.acquire();
  try {
    return await Navigator.of(context, rootNavigator: true).push(route) ??
        false;
  } finally {
    privacy.release();
  }
}

class _ConflictDialog extends StatefulWidget {
  const _ConflictDialog({
    required this.note,
    required this.store,
    required this.workspace,
    required this.onInvalidated,
  });
  final NoteEntry note;
  final SyncV2NoteStore store;
  final SyncV2WorkspaceController workspace;
  final VoidCallback onInvalidated;
  @override
  State<_ConflictDialog> createState() => _ConflictState();
}

class _ConflictState extends State<_ConflictDialog>
    with WidgetsBindingObserver {
  SyncV2NoteSnapshot? _snapshot;
  String? _selected, _error;
  bool _loading = true, _saving = false;
  final _expanded = <String>{};
  Object? _access;
  String? _generation;
  String t(String ja, String en) =>
      Localizations.localeOf(context).languageCode == 'ja' ? ja : en;
  Object? get _currentAccess {
    final session = widget.workspace.noteStoreSession;
    if (session == null) return null;
    return session.profiles[SyncV2NoteStore.profileIdFor(
      session,
      widget.note.vaultId,
    )];
  }

  bool get _active =>
      mounted &&
      _access != null &&
      identical(_access, _currentAccess) &&
      _generation == widget.workspace.generationId;

  @override
  void initState() {
    super.initState();
    _access = _currentAccess;
    _generation = widget.workspace.generationId;
    WidgetsBinding.instance.addObserver(this);
    widget.workspace.addListener(_sessionChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.workspace.removeListener(_sessionChanged);
    WidgetsBinding.instance.removeObserver(this);
    _snapshot = null;
    super.dispose();
  }

  void _sessionChanged() {
    if (!_active) {
      setState(() => _snapshot = null);
      widget.onInvalidated();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      widget.workspace.background();
      _sessionChanged();
    }
  }

  Future<void> _load({bool sync = false}) async {
    if (!_active) {
      widget.onInvalidated();
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
      _selected = null;
      _expanded.clear();
    });
    try {
      if (sync) await widget.workspace.syncNow();
      if (!_active) return;
      final snapshot = await widget.store.readConflict(widget.note);
      if (_active) setState(() => _snapshot = snapshot);
    } catch (_) {
      if (_active) {
        setState(() {
          _snapshot = null;
          _error = t(
            '版を読み込めませんでした。同期して再度お試しください。',
            'Could not load the versions. Sync and try again.',
          );
        });
      }
    } finally {
      if (_active) setState(() => _loading = false);
    }
  }

  Future<void> _resolve() async {
    final snapshot = _snapshot;
    final selected = _selected;
    if (!_active || _saving || snapshot == null || selected == null) return;
    setState(() => _saving = true);
    try {
      await widget.store.resolveConflict(
        widget.note,
        reviewedHeads: snapshot.headIds,
        selectedChangeId: selected,
      );
      if (mounted && _active) Navigator.pop(context, true);
    } on SyncV2StaleNote {
      await _load();
      if (_active) {
        setState(
          () => _error = t(
            '内容が更新されました。最新版を確認して選び直してください。',
            'The note changed. Review the latest versions and choose again.',
          ),
        );
      }
    } on SyncV2NoteStoreLocked {
      widget.onInvalidated();
    } catch (_) {
      if (_active) {
        setState(
          () => _error = t(
            '解決できませんでした。再読込してお試しください。',
            'Could not resolve the conflict. Reload and try again.',
          ),
        );
      }
    } finally {
      if (_active) setState(() => _saving = false);
    }
  }

  Widget _version(SyncV2NoteVersion version, int index, bool ready) {
    final note = version.isDeleted || version.body == null
        ? null
        : NoteEntry.fromJson(
            Map<String, dynamic>.from(version.body!['note'] as Map),
          );
    final body = note?.body ?? '';
    final expanded = _expanded.contains(version.change.id);
    final date = note == null
        ? ''
        : MaterialLocalizations.of(context)
              .formatShortDate(note.updatedAt ?? note.createdAt);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RadioListTile<String>(
          value: version.change.id,
          enabled: ready,
          title: Text(
            version.isDeleted
                ? t('削除された版', 'Deleted version')
                : '${t('版', 'Version')} ${index + 1}: ${note?.title.isNotEmpty == true ? note!.title : t('無題', 'Untitled')}',
          ),
          subtitle: Text(
            version.isDeleted
                ? t(
                    '採用するとこのメモを削除します。',
                    'Choosing this version deletes the note.',
                  )
                : note == null
                ? t('本文が未受信です', 'Content has not arrived')
                : date,
          ),
        ),
        if (note != null)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 16,
              end: 16,
              bottom: 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SelectableText(
                  !expanded && body.length > 1000
                      ? '${body.substring(0, 1000)}…'
                      : body,
                ),
                if (!expanded && body.length > 1000)
                  TextButton(
                    onPressed: () =>
                        setState(() => _expanded.add(version.change.id)),
                    child: Text(t('全文を表示', 'Show full text')),
                  ),
                if (note.attachments.isNotEmpty)
                  Text(
                    '${t('添付', 'Attachments')}: ${note.attachments.map((a) => a.label).join(', ')}',
                  ),
              ],
            ),
          ),
        const Divider(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_active) return const SizedBox.shrink();
    final snapshot = _snapshot;
    final ready = snapshot != null && snapshot.canCompareVersions;
    final settled = ready && !snapshot.hasConflict;
    return AlertDialog(
      title: Text(t('残す版を選ぶ', 'Choose the version to keep')),
      content: SizedBox(
        width: 560,
        height: MediaQuery.sizeOf(context).height * .5,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_error != null)
                      Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    if (settled)
                      Text(
                        t(
                          '競合はすでに解消されています。',
                          'This conflict has already been resolved.',
                        ),
                      )
                    else if (snapshot != null) ...[
                      Text(
                        ready
                            ? t(
                                '同時に編集された版があります。内容と添付を確認し、残す版を選んでください。',
                                'This note has concurrent edits. Review the content and attachments, then choose a version.',
                              )
                            : t(
                                '未受信のデータがあります。同期後、すべての版を確認してから解決できます。',
                                'Some data has not arrived. Sync before reviewing and resolving all versions.',
                              ),
                      ),
                      RadioGroup<String>(
                        groupValue: _selected,
                        onChanged: _saving || !ready
                            ? (_) {}
                            : (value) => setState(() => _selected = value),
                        child: Column(
                          children: [
                            for (var i = 0; i < snapshot.versions.length; i++)
                              _version(
                                snapshot.versions[i],
                                i,
                                ready && !_saving,
                              ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
      ),
      actions: [
        TextButton(
          onPressed: _saving || _loading ? null : () => _load(sync: true),
          child: Text(t('同期して再読込', 'Sync and reload')),
        ),
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, settled),
          child: Text(t('閉じる', 'Close')),
        ),
        if (!settled)
          FilledButton(
            onPressed: !_saving && !_loading && ready && _selected != null
                ? _resolve
                : null,
            child: Text(t('この版を採用', 'Keep this version')),
          ),
      ],
    );
  }
}
