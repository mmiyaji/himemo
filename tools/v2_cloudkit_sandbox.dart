// Explicit, development-only CloudKit sandbox experiment. No production routes.
// Run: flutter run -d chrome -t tools/v2_cloudkit_sandbox.dart
import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:drift/wasm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/sync/data/sync_v2_cloudkit_web.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace_screen.dart';
import 'package:himemo/features/sync/testing/sync_v2_cloudkit_sandbox.dart';
import 'package:himemo/l10n/app_strings.dart';
// This development-only entry uses the sqlite3 version pinned by Drift.
// ignore: depend_on_referenced_packages
import 'package:sqlite3/wasm.dart' show InMemoryFileSystem, WasmSqlite3;
import 'package:web/web.dart' as web;

void main() => runApp(const _SandboxApp());

class _SandboxApp extends StatelessWidget {
  const _SandboxApp();
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ja'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorSchemeSeed: const Color(0xFFC64759),
      useMaterial3: true,
    ),
    home: const _SandboxScreen(),
  );
}

class _SandboxScreen extends StatefulWidget {
  const _SandboxScreen();
  @override
  State<_SandboxScreen> createState() => _SandboxScreenState();
}

class _SandboxScreenState extends State<_SandboxScreen>
    with WidgetsBindingObserver {
  final _bridge = const SyncV2CloudKitWebBridge();
  final _token = TextEditingController();
  final _namespace = TextEditingController(text: _newNamespace());
  late final web.HTMLDivElement _authHolder;
  SyncV2CloudKitSandboxSession? _session;
  SyncV2CloudKitSandboxSession? _pendingSession;
  bool _scriptsLoaded = false;
  Future<void>? _scriptLoading;
  bool _busy = false;
  bool _configured = false;
  int _revision = 0;
  String _status = '接続するまではCloudKitへアクセスしません。';

  static String _newNamespace() {
    final random = Random.secure();
    return 'web_${List.generate(12, (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  @override
  void initState() {
    super.initState();
    web.document.documentElement?.setAttribute(
      'data-v2-sandbox-state',
      'disconnected',
    );
    WidgetsBinding.instance.addObserver(this);
    _authHolder = web.document.createElement('div') as web.HTMLDivElement;
    _authHolder.id = 'himemo-v2-sandbox-auth';
    _authHolder.style.cssText = 'position:fixed;right:16px;bottom:12px;z-index:9999;display:none;background:white;padding:8px;border-radius:8px';
    for (final id in ['apple-sign-in-button', 'apple-sign-out-button']) {
      final child = web.document.createElement('div') as web.HTMLDivElement;
      child.id = id;
      _authHolder.appendChild(child);
    }
    web.document.body!.appendChild(_authHolder);
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

  Future<void> _ensureScripts() {
    if (_scriptsLoaded) return Future<void>.value();
    return _scriptLoading ??= _loadScripts();
  }

  Future<void> _loadScripts() async {
    try {
      await _loadScript('https://cdn.apple-cloudkit.com/ck/2/cloudkit.js');
      await _loadScript(Uri.base.resolve('sync_v2_cloudkit.js').toString());
      _scriptsLoaded = true;
    } catch (_) {
      _scriptLoading = null;
      rethrow;
    }
  }

  Future<void> _connect() async {
    if (_busy || _session != null) return;
    final namespace = _namespace.text.trim();
    var token = _token.text.trim();
    _token.clear();
    if (!web.window.isSecureContext ||
        token.isEmpty ||
        !RegExp(r'^[A-Za-z0-9_-]{16,32}$').hasMatch(namespace)) {
      setState(
        () => _status = 'HTTPSまたはlocalhost、APIトークン、16〜32文字のサンドボックス名が必要です。',
      );
      token = '';
      return;
    }
    final revision = ++_revision;
    web.document.documentElement?.setAttribute(
      'data-v2-sandbox-state',
      'connecting',
    );
    setState(() {
      _busy = true;
      _status = '開発サンドボックスに接続しています。';
    });
    try {
      await _ensureScripts();
      if (!mounted || revision != _revision) return;
      _authHolder.style.display = 'block';
      final signedIn = await configureCloudKitSandbox(
        bridge: _bridge,
        apiToken: token,
        namespace: namespace,
      );
      token = '';
      if (!mounted || revision != _revision) return;
      _configured = true;
      unawaited(_watchSignOut(revision));
      if (!signedIn) {
        setState(() => _status = '画面下のAppleボタンからサインインしてください。');
        await _bridge.waitForSignIn();
      }
      if (!mounted || revision != _revision) return;
      final sqlite = await WasmSqlite3.loadFromUrl(
        Uri.base.resolve('vendor/drift/sqlite3.wasm'),
      );
      sqlite.registerVirtualFileSystem(InMemoryFileSystem(), makeDefault: true);
      if (!mounted || revision != _revision) return;
      final session = SyncV2CloudKitSandboxSession.create(
        executor: WasmDatabase.inMemory(sqlite),
        invoke: _bridge.invoke,
        disconnect: _bridge.disconnect,
      );
      _pendingSession = session;
      await session.workspace.initialize();
      if (!mounted || revision != _revision) {
        await session.close();
        return;
      }
      _pendingSession = null;
      web.document.documentElement?.setAttribute(
        'data-v2-sandbox-state',
        'connected',
      );
      setState(() {
        _session = session;
        _status = '開発サンドボックスに接続中です。';
      });
    } catch (_) {
      if (mounted && revision == _revision) {
        await _disconnect('接続できませんでした。設定、アカウントと通信を確認してください。');
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
      /* Fail closed. */
    }
    if (mounted && revision == _revision) await _disconnect('Apple接続が終了しました。');
  }

  Future<void> _disconnect(String message) async {
    ++_revision;
    web.document.documentElement?.setAttribute(
      'data-v2-sandbox-state',
      'disconnected',
    );
    final session = _session;
    final pending = _pendingSession;
    _session = null;
    _pendingSession = null;
    _configured = false;
    _token.clear();
    _authHolder.style.display = 'none';
    if (mounted) {
      setState(() {
        _busy = false;
        _status = message;
      });
    }
    // Revocation is synchronous; already-dispatched remote writes cannot be
    // recalled, but all zones remain restricted to this test namespace.
    Future<void> closeSafely(Future<void> Function() close) async {
      try {
        await close();
      } catch (_) {
        // The owning session already revoked keys and invalidated its gate.
      }
    }

    final closures = <Future<void>>[
      if (session != null) closeSafely(session.close),
      if (pending != null && !identical(pending, session))
        closeSafely(pending.close),
      if (session == null && pending == null) closeSafely(_bridge.disconnect),
    ];
    await Future.wait(closures);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if ((state == AppLifecycleState.hidden ||
            state == AppLifecycleState.paused) &&
        (_session != null || _pendingSession != null)) {
      unawaited(_disconnect('非表示になったため接続を解除しました。'));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    ++_revision;
    final session = _session;
    final pending = _pendingSession;
    _session = null;
    _pendingSession = null;
    if (session != null) unawaited(session.close().catchError((Object _) {}));
    if (pending != null && !identical(pending, session)) {
      unawaited(pending.close().catchError((Object _) {}));
    }
    if (session == null && pending == null) {
      unawaited(_bridge.disconnect().catchError((Object _) {}));
    }
    _authHolder.remove();
    web.document.documentElement?.removeAttribute('data-v2-sandbox-state');
    _token.dispose();
    _namespace.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Material(
              color: const Color(0xFFFFE082),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Column(
                  children: [
                    const Text('開発用サンドボックス：本番・iOSのデータとは別領域です。実データを使わないでください。'),
                    const Text(
                      '一時メモリで動作します。未同期の変更は接続解除や再読み込みで失われます。送信済みの操作は取り消せません。',
                    ),
                    if (_configured) Text('サンドボックス名：${_namespace.text.trim()}'),
                    if (_configured)
                      TextButton(
                        onPressed: () => _disconnect('接続を解除しました。'),
                        child: const Text('接続を解除'),
                      ),
                  ],
                ),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            Expanded(
              child: session == null
                  ? _connectForm()
                  : ProviderScope(
                      key: ObjectKey(session),
                      overrides: [
                        syncV2WorkspaceProvider.overrideWithValue(
                          session.workspace,
                        ),
                      ],
                      child: const SyncV2WorkspaceScreen(cloudSandbox: true),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _connectForm() => Center(
    child: SingleChildScrollView(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 560),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'CloudKit 開発サンドボックス',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text(_status),
              const SizedBox(height: 16),
              TextField(
                key: const Key('sandbox-namespace'),
                controller: _namespace,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'サンドボックス名（16〜32文字）',
                ),
              ),
              TextField(
                key: const Key('sandbox-api-token'),
                controller: _token,
                enabled: !_busy,
                obscureText: true,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  labelText: 'CloudKit APIトークン',
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                key: const Key('sandbox-connect'),
                onPressed: _busy ? null : _connect,
                child: const Text('開発環境に接続'),
              ),
              if (_busy || _configured)
                TextButton(
                  onPressed: () => _disconnect('接続を解除しました。'),
                  child: const Text('接続を解除'),
                ),
            ],
          ),
        ),
      ),
    ),
  );
}
