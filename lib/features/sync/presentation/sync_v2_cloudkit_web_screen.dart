import 'dart:async';
import 'dart:js_interop';

import 'package:drift/wasm.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart'
    show HomeBrandTitle, HomeNotePreviewList;
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';
import 'package:himemo/features/sync/presentation/sync_v2_cloudkit_readonly.dart';
import 'package:himemo/features/sync/presentation/sync_v2_attachment_image.dart';
// This read-only screen uses the sqlite3 version already pinned by Drift.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/wasm.dart' show InMemoryFileSystem, WasmSqlite3;
import 'package:web/web.dart' as web;

class SyncV2CloudKitReadOnlyScreen extends StatefulWidget {
  const SyncV2CloudKitReadOnlyScreen({
    super.key,
    this.onExit,
    this.initialSession,
  });
  final VoidCallback? onExit;

  /// Injects an already unlocked, synthetic session for browser smoke tests.
  /// The screen owns and disposes the controller when this is provided.
  @visibleForTesting
  final SyncV2CloudKitReadOnlyController? initialSession;
  @override
  State<SyncV2CloudKitReadOnlyScreen> createState() =>
      _SyncV2CloudKitReadOnlyScreenState();
}

class _SyncV2CloudKitReadOnlyScreenState
    extends State<SyncV2CloudKitReadOnlyScreen>
    with WidgetsBindingObserver {
  final _apiToken = TextEditingController();
  final _syncCode = TextEditingController();
  final _adminCode = TextEditingController();
  final _bridge = const SyncV2CloudKitWebBridge();
  final _downloadObjectUrls = <String>{};
  late final web.HTMLDivElement _authHolder;
  bool _busy = false;
  bool _scriptsLoaded = false;
  bool _configured = false;
  String _environment = 'development';
  String? _account;
  String _status = 'CloudKitの開発環境に読み取り専用で接続します。';
  int _revision = 0;
  SyncV2CloudKitReadOnlyController? _session;
  SyncV2CloudKitReadOnlyController? _pendingSession;
  SyncV2ReadOnlyNote? _selected;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _authHolder = web.document.createElement('div') as web.HTMLDivElement;
    _authHolder.id = 'himemo-v2-readonly-auth';
    _authHolder.style.cssText = 'position:fixed;right:16px;bottom:12px;z-index:9999;display:none;background:white;padding:8px;border-radius:8px';
    for (final id in ['apple-sign-in-button', 'apple-sign-out-button']) {
      final child = web.document.createElement('div') as web.HTMLDivElement;
      child.id = id;
      _authHolder.appendChild(child);
    }
    web.document.body!.appendChild(_authHolder);
    final initialSession = widget.initialSession;
    if (initialSession != null) {
      _session = initialSession;
      _session!.addListener(_sessionChanged);
      _selected = initialSession.notes.firstOrNull;
      _configured = true;
      _status = '合成V2データを読み取り専用で表示しています。';
    }
  }

  Future<void> _loadScript(String source) async {
    final done = Completer<void>();
    final script =
        web.document.createElement('script') as web.HTMLScriptElement;
    script.src = source;
    script.async = true;
    script.addEventListener(
      'load',
      ((web.Event _) {
        if (!done.isCompleted) done.complete();
      }).toJS,
    );
    script.addEventListener(
      'error',
      ((web.Event _) {
        if (!done.isCompleted) {
          done.completeError(StateError('Script unavailable'));
        }
      }).toJS,
    );
    web.document.head!.appendChild(script);
    await done.future.timeout(const Duration(seconds: 20));
  }

  String _message(Object error) {
    if (error is PlatformException) {
      return switch (error.code) {
        'cloudkit_v2_notConfigured' => 'CloudKitの設定またはSDKを確認してください。',
        'cloudkit_v2_signedOut' ||
        'cloudkit_v2_accountChanged' => 'Appleアカウントの認証をやり直してください。',
        '11' || '26' => 'この環境には暗号化同期の登録がありません。',
        'cloudkit_v2_pageTooLarge' => '受信ページが大きすぎるため、安全のため中断しました。',
        _ => '接続できませんでした。設定と通信を確認してください。',
      };
    }
    if (error is FormatException) return '復旧コードまたは受信データを確認してください。';
    return '操作できませんでした。接続と復旧コードを確認してください。';
  }

  Future<void> _connect() async {
    if (_busy) return;
    if (!web.window.isSecureContext) {
      setState(() => _status = 'HTTPSまたはlocalhostで開いてください。');
      return;
    }
    var token = _apiToken.text.trim();
    _apiToken.clear();
    if (token.isEmpty) {
      setState(() => _status = 'CloudKit APIトークンを入力してください。');
      return;
    }
    final revision = ++_revision;
    setState(() {
      _busy = true;
      _status =
          'CloudKitの${_environment == 'production' ? '本番' : '開発'}環境に読み取り専用で接続しています。';
    });
    try {
      if (!_scriptsLoaded) {
        await _loadScript('https://cdn.apple-cloudkit.com/ck/2/cloudkit.js');
        await _loadScript(Uri.base.resolve('sync_v2_cloudkit.js').toString());
        _scriptsLoaded = true;
      }
      if (!mounted || revision != _revision) return;
      _authHolder.style.display = 'block';
      final signedIn = await _bridge.configure(
        containerIdentifier: 'iCloud.org.ruhenheim.himemo',
        apiToken: token,
        environment: _environment,
        enableWrites: false,
      );
      token = '';
      if (!mounted || revision != _revision) return;
      _configured = true;
      unawaited(_watchSignOut(revision));
      if (!signedIn) {
        setState(() {
          _busy = false;
          _status = '画面下のAppleボタンからサインインしてください。';
        });
        final account = await _bridge.waitForSignIn();
        if (!mounted || revision != _revision) return;
        setState(() {
          _account = account;
          _status = 'SYNC復旧コードを入力してください。';
        });
      } else {
        final account = await SyncV2CloudKitWebTransport(accountId: '')
            .readCurrentAccountId();
        if (!mounted || revision != _revision) return;
        setState(() {
          _account = account;
          _status = 'SYNC復旧コードを入力してください。';
        });
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _status = _message(error));
      }
    } finally {
      token = '';
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _watchSignOut(int revision) async {
    try {
      await _bridge.waitForSignOut();
    } catch (_) {
      /* Lock on monitor failure. */
    }
    if (mounted && revision == _revision) await _disconnect('Apple接続が終了しました。');
  }

  Future<void> _open() async {
    if (_busy || _account == null || _session != null) return;
    var code = _syncCode.text.trim();
    _syncCode.clear();
    if (code.isEmpty) {
      setState(() => _status = 'SYNC復旧コードを入力してください。');
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _status = '復旧コードを確認し、暗号化データを読み取っています。';
    });
    SyncV2CloudKitReadOnlyController? created;
    try {
      final sqlite = await WasmSqlite3.loadFromUrl(
        Uri.base.resolve('vendor/drift/sqlite3.wasm'),
      );
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
      if (!mounted || revision != _revision) return;
      final encryption = EncryptionService();
      final headers = SyncV2HeaderCodec(encryption);
      final inbox = SyncV2Inbox(WasmDatabase.inMemory(sqlite), headers);
      final store = SyncV2EphemeralKeyStore();
      created = SyncV2CloudKitReadOnlyController(
        inbox: inbox,
        repository: SyncV2NoteRepository(
          inbox,
          headers,
          SyncV2PayloadCodec(encryption),
        ),
        encryption: encryption,
        store: store,
        accountReader: () =>
            SyncV2CloudKitWebTransport(accountId: '').readCurrentAccountId(),
        registrationTransport: (account) =>
            SyncV2CloudKitWebTransport(accountId: account),
        readerFactory: (account) =>
            SyncV2CloudKitWebTransport(accountId: account),
      );
      _pendingSession = created;
      await created.recover(code);
      code = '';
      if (!mounted || revision != _revision) {
        created.dispose();
        return;
      }
      _pendingSession = null;
      _session = created;
      created.addListener(_sessionChanged);
      setState(
        () => _status = created!.partial
            ? '一部を読み込みました。再読み込みで続きを取得します。'
            : '読み取り専用です。編集・削除・インポートはできません。',
      );
    } catch (error) {
      if (identical(_pendingSession, created)) _pendingSession = null;
      created?.dispose();
      if (mounted && revision == _revision) {
        setState(() => _status = _message(error));
      }
    } finally {
      code = '';
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  void _sessionChanged() {
    final session = _session;
    final selected = _selected;
    if (selected != null &&
        (session == null ||
            selected.note.vaultId != session.selectedProfileId ||
            !session.notes.any((item) => identical(item, selected)))) {
      _selected = null;
    }
    if (mounted) setState(() {});
  }

  Future<void> _unlockAdmin() async {
    final session = _session;
    if (_busy || session == null) return;
    var code = _adminCode.text.trim();
    _adminCode.clear();
    if (code.isEmpty) {
      setState(() => _status = 'ADMIN復旧コードを入力してください。');
      return;
    }
    final revision = _revision;
    setState(() {
      _busy = true;
      _status = '管理者コードを確認しています。';
    });
    try {
      await session.unlockAdmin(code);
      if (mounted && revision == _revision) {
        setState(() => _status = '管理者コードで私用プロファイルを表示できます。読み取り専用です。');
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        if (error is StateError || error is PlatformException) {
          await _disconnect('認証を確認できないため接続を解除しました。${_message(error)}');
        } else {
          setState(() => _status = _message(error));
        }
      }
    } finally {
      code = '';
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _refresh() async {
    final session = _session;
    if (_busy || session == null) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _selected = null;
      _status = '読み取り中です。';
    });
    try {
      await session.sync();
      if (mounted && revision == _revision) {
        setState(
          () => _status = session.partial
              ? '一部を読み込みました。再読み込みで続きを取得します。'
              : '読み取り専用です。',
        );
      }
    } catch (error) {
      if (mounted && revision == _revision) {
        await _disconnect('読み取りが中断されたため接続を解除しました。${_message(error)}');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  Future<void> _selectProfile(String? id) async {
    final session = _session;
    if (_busy || session == null || id == null) return;
    final revision = _revision;
    _revokeDownloadObjectUrls();
    setState(() {
      _busy = true;
      _selected = null;
    });
    try {
      await session.selectProfile(id);
    } catch (error) {
      if (mounted && revision == _revision) {
        await _disconnect('読み取りが中断されたため接続を解除しました。${_message(error)}');
      }
    } finally {
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  bool _isAttachmentActive(
    SyncV2CloudKitReadOnlyController session,
    SyncV2ReadOnlyNote item,
  ) =>
      mounted &&
      identical(_session, session) &&
      identical(_selected, item) &&
      session.notes.any((note) => identical(note, item)) &&
      session.selectedProfileId == item.note.vaultId;

  Future<void> _downloadAttachment(
    SyncV2CloudKitReadOnlyController session,
    SyncV2ReadOnlyNote item,
    NoteAttachment attachment,
  ) async {
    if (_busy || !_isAttachmentActive(session, item) || item.conflicted) return;
    final revision = _revision;
    setState(() {
      _busy = true;
      _status = '添付を復号しています。';
    });
    Uint8List? bytes;
    String? objectUrl;
    try {
      bytes = await session.readAttachment(
        item: item,
        attachment: attachment,
        isCurrent: () =>
            revision == _revision && _isAttachmentActive(session, item),
      );
      if (revision != _revision || !_isAttachmentActive(session, item)) return;
      final mime = _attachmentMime(attachment);
      final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mime));
      objectUrl = web.URL.createObjectURL(blob);
      final anchor = web.document.createElement('a') as web.HTMLAnchorElement;
      anchor.href = objectUrl;
      anchor.download = _safeDownloadName(attachment.label);
      anchor.style.display = 'none';
      web.document.body!.appendChild(anchor);
      anchor.click();
      anchor.remove();
      final scheduledUrl = objectUrl;
      _downloadObjectUrls.add(scheduledUrl);
      web.window.setTimeout(
        (() {
          if (_downloadObjectUrls.remove(scheduledUrl)) {
            web.URL.revokeObjectURL(scheduledUrl);
          }
        }).toJS,
        1000.toJS,
      );
      objectUrl = null;
      setState(() => _status = '添付のダウンロードを開始しました。');
    } catch (error) {
      if (mounted && revision == _revision) {
        setState(() => _status = _message(error));
      }
    } finally {
      if (bytes != null) bytes.fillRange(0, bytes.length, 0);
      if (objectUrl != null) web.URL.revokeObjectURL(objectUrl);
      if (mounted && revision == _revision) setState(() => _busy = false);
    }
  }

  String _safeDownloadName(String label) {
    final leaf = label.replaceAll('\\', '/').split('/').last;
    final safe = leaf.replaceAll(RegExp(r'[\\/:*?"<>|\u0000-\u001f]'), '_');
    return safe.isEmpty || safe == '.' || safe == '..'
        ? 'attachment.bin'
        : safe;
  }

  void _revokeDownloadObjectUrls() {
    for (final url in _downloadObjectUrls.toList()) {
      web.URL.revokeObjectURL(url);
    }
    _downloadObjectUrls.clear();
  }

  String _attachmentMime(NoteAttachment attachment) {
    final name = attachment.label.toLowerCase();
    if (attachment.type == AttachmentType.photo) {
      if (name.endsWith('.png')) return 'image/png';
      if (name.endsWith('.gif')) return 'image/gif';
      if (name.endsWith('.webp')) return 'image/webp';
      return 'image/jpeg';
    }
    if (attachment.type == AttachmentType.video) return 'video/mp4';
    if (attachment.type == AttachmentType.audio) return 'audio/mpeg';
    return 'application/octet-stream';
  }

  Future<void> _disconnect(String message) async {
    ++_revision;
    _revokeDownloadObjectUrls();
    final session = _session;
    final pending = _pendingSession;
    _session = null;
    _pendingSession = null;
    session?.removeListener(_sessionChanged);
    session?.dispose();
    pending?.dispose();
    _selected = null;
    _account = null;
    _configured = false;
    _apiToken.clear();
    _syncCode.clear();
    _adminCode.clear();
    _authHolder.style.display = 'none';
    if (mounted) {
      setState(() {
        _busy = false;
        _status = message;
      });
    }
    try {
      await _bridge.disconnect();
    } catch (_) {
      /* The session is already discarded. */
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        (_session != null || _pendingSession != null)) {
      unawaited(_disconnect('画面が非表示になったため接続を解除しました。'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_revision;
    _revokeDownloadObjectUrls();
    _session?.removeListener(_sessionChanged);
    _session?.dispose();
    _pendingSession?.dispose();
    _authHolder.remove();
    _apiToken.dispose();
    _syncCode.dispose();
    _adminCode.dispose();
    unawaited(_bridge.disconnect().catchError((Object _) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      appBar: AppBar(
        leading: widget.onExit == null
            ? null
            : IconButton(
                tooltip: '設定に戻る',
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onExit,
              ),
        title: const HomeBrandTitle(),
        actions: [
          Center(
            child: Text(
              '${_environment == 'production' ? '本番' : '開発'}環境・読み取り専用',
            ),
          ),
          const SizedBox(width: 12),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            MaterialBanner(
              content: Text(_status),
              actions: [
                TextButton(onPressed: () {}, child: const Text('読み取り専用')),
              ],
            ),
            if (_busy || session?.busy == true) const LinearProgressIndicator(),
            Expanded(
              child: session == null ? _connectForm() : _notesView(session),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectForm() => SingleChildScrollView(
    padding: const EdgeInsets.all(24),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CloudKit${_environment == 'production' ? '本番' : '開発'}環境・読み取り専用',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text(
              '選択した環境の暗号化データをメモリ内で表示します。更新、削除、インポート、設定変更はできません。ページを閉じると復旧コードの再入力が必要です。',
            ),
            const SizedBox(height: 8),
            const Text('この機能は試験中です。実際のAppleアカウントでの接続はまだ検証されていません。'),
            if (!_configured) ...[
              DropdownButtonFormField<String>(
                initialValue: _environment,
                decoration: const InputDecoration(labelText: 'CloudKit環境'),
                items: const [
                  DropdownMenuItem(value: 'development', child: Text('開発環境')),
                  DropdownMenuItem(
                    value: 'production',
                    child: Text('本番環境（読み取り専用）'),
                  ),
                ],
                onChanged: _busy
                    ? null
                    : (value) {
                        if (value != null) setState(() => _environment = value);
                      },
              ),
              TextField(
                key: const Key('readonly-api-token'),
                controller: _apiToken,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'CloudKit APIトークン',
                ),
              ),
              FilledButton(
                key: const Key('readonly-connect'),
                onPressed: _busy ? null : _connect,
                child: const Text('Appleに接続'),
              ),
            ],
            if (_account != null) ...[
              TextField(
                key: const Key('readonly-sync-code'),
                controller: _syncCode,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'SYNC復旧コード'),
              ),
              FilledButton(
                key: const Key('readonly-open'),
                onPressed: _busy ? null : _open,
                child: const Text('読み取り専用で開く'),
              ),
            ],
            if (_configured)
              TextButton(
                onPressed: () => _disconnect('ローカル接続を解除しました。'),
                child: const Text('接続を解除'),
              ),
          ],
        ),
      ),
    ),
  );

  Widget _notesView(SyncV2CloudKitReadOnlyController session) {
    final profiles = session.profiles;
    final current = profiles
        .where((profile) => profile.id == session.selectedProfileId)
        .firstOrNull;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              DropdownButton<String>(
                value: session.selectedProfileId,
                items: [
                  for (final profile in profiles)
                    DropdownMenuItem(
                      value: profile.id,
                      child: Text(profile.name),
                    ),
                ],
                onChanged: _busy ? null : _selectProfile,
              ),
              TextButton.icon(
                onPressed: _busy ? null : _refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('再読み込み'),
              ),
              TextButton(
                onPressed: () => _disconnect('ローカル接続を解除しました。'),
                child: const Text('接続を解除'),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('readonly-admin-code'),
                  controller: _adminCode,
                  obscureText: true,
                  enableSuggestions: false,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'ADMIN復旧コード（任意）',
                  ),
                ),
              ),
              TextButton(
                onPressed: _busy ? null : _unlockAdmin,
                child: const Text('私用を表示'),
              ),
            ],
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final list = HomeNotePreviewList(
                notes: [for (final item in session.notes) item.note],
                profileName: current?.name ?? '',
                selectedNoteId: _selected?.note.id,
                onNoteSelected: (note) => setState(
                  () => _selected = session.notes.firstWhere(
                    (item) => identical(item.note, note),
                  ),
                ),
                statusBuilder: (note) =>
                    session.notes.any(
                      (item) => identical(item.note, note) && item.conflicted,
                    )
                    ? const Text('競合バージョン')
                    : null,
              );
              final selected = _selected;
              final detail = selected == null
                  ? const Center(child: Text('メモを選択してください'))
                  : _detail(session, selected);
              if (constraints.maxWidth >= 800) {
                return Row(
                  children: [
                    Expanded(child: list),
                    const VerticalDivider(width: 1),
                    Expanded(child: detail),
                  ],
                );
              }
              return selected == null
                  ? list
                  : Column(
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: TextButton(
                            onPressed: () => setState(() => _selected = null),
                            child: const Text('一覧に戻る'),
                          ),
                        ),
                        Expanded(child: detail),
                      ],
                    );
            },
          ),
        ),
      ],
    );
  }

  Widget _detail(
    SyncV2CloudKitReadOnlyController session,
    SyncV2ReadOnlyNote item,
  ) {
    final note = item.note;
    final text = note.blocks
        .where((block) => block.type == NoteBlockType.paragraph)
        .map((block) => block.text ?? '')
        .join('\n\n');
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        if (item.conflicted) const Text('競合バージョン（読み取り専用）'),
        Text(note.title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 16),
        SelectableText(text.isEmpty ? note.body : text),
        for (final attachment in note.attachments) ...[
          Builder(
            builder: (context) {
              final reference = syncV2ReadOnlyAttachmentReference(
                item,
                attachment,
              );
              final ready = reference != null;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ListTile(
                    leading: const Icon(Icons.attachment),
                    title: Text(attachment.label),
                    subtitle: Text(
                      item.conflicted
                          ? '競合中の添付は表示できません'
                          : ready
                          ? '受信済みの暗号化添付'
                          : '添付データが未連携または未受信です',
                    ),
                    trailing: IconButton(
                      key: Key('readonly-download-${attachment.label}'),
                      tooltip: '添付をダウンロード',
                      onPressed: ready && !_busy
                          ? () => _downloadAttachment(session, item, attachment)
                          : null,
                      icon: const Icon(Icons.download),
                    ),
                  ),
                  if (ready && attachment.type == AttachmentType.photo)
                    SizedBox(
                      height: 180,
                      child: SyncV2AttachmentImage(
                        key: ValueKey(
                          'readonly-image-${session.selectedProfileId}-${item.note.id}-${reference.id}',
                        ),
                        label: attachment.label,
                        isActive: () =>
                            _isAttachmentActive(session, item) && !_busy,
                        loadBytes: (isCurrent) => session.readAttachment(
                          item: item,
                          attachment: attachment,
                          isCurrent: isCurrent,
                        ),
                        thumbnail: false,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }
}
