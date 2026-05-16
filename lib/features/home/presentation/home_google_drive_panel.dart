part of 'home_page.dart';

class _GoogleDriveWebSignInPanel extends ConsumerStatefulWidget {
  const _GoogleDriveWebSignInPanel();

  @override
  ConsumerState<_GoogleDriveWebSignInPanel> createState() =>
      _GoogleDriveWebSignInPanelState();
}

class _GoogleDriveWebSignInPanelState
    extends ConsumerState<_GoogleDriveWebSignInPanel> {
  StreamSubscription<GoogleSignInAuthenticationEvent>? _subscription;
  Object? _error;
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    if (useFakeGoogleDriveSync) {
      _ready = true;
      return;
    }
    unawaited(_initialize());
  }

  @override
  void dispose() {
    unawaited(_subscription?.cancel());
    super.dispose();
  }

  Future<void> _initialize() async {
    try {
      await GoogleSignInInitializer.ensureInitialized(
        ref.read(googleDriveAuthConfigProvider),
      );
      _subscription = GoogleSignIn.instance.authenticationEvents.listen(
        _handleAuthenticationEvent,
        onError: _handleAuthenticationError,
      );
      GoogleSignIn.instance.attemptLightweightAuthentication();
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = true;
        _error = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ready = false;
        _error = error is GoogleDriveAuthConfigurationException
            ? error.message
            : error;
      });
    }
  }

  Future<void> _handleAuthenticationEvent(
    GoogleSignInAuthenticationEvent event,
  ) async {
    switch (event) {
      case GoogleSignInAuthenticationEventSignIn(user: final user):
        await ref
            .read(syncAuthControllerProvider.notifier)
            .completeGoogleDriveWebAuthentication(user);
      case GoogleSignInAuthenticationEventSignOut():
        await ref
            .read(syncAuthControllerProvider.notifier)
            .disconnect(SyncProvider.googleDrive);
    }
  }

  void _handleAuthenticationError(Object error) {
    if (!mounted) {
      return;
    }
    setState(() {
      _error = error;
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final colorScheme = Theme.of(context).colorScheme;
    final error = _error;
    final fakeMode = useFakeGoogleDriveSync;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 8, bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            fakeMode
                ? strings.localized(
                    en: 'Fake Google Drive sync',
                    ja: 'Google Drive シミュレータ',
                    zh: 'Google Drive 模拟器',
                    ko: 'Google Drive 시뮬레이터',
                    es: 'Simulador de Google Drive',
                    de: 'Google-Drive-Simulator',
                  )
                : strings.googleDriveWebSignInTitle,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            fakeMode
                ? strings.localized(
                    en: 'Local testing mode is enabled. Sync uses an in-memory Google Drive simulator and does not contact Google.',
                    ja: 'ローカルテストモードです。同期はメモリ内の Google Drive シミュレータを使い、Google には接続しません。',
                    zh: '已启用本地测试模式。同步会使用内存中的 Google Drive 模拟器，不会连接 Google。',
                    ko: '로컬 테스트 모드입니다. 동기화는 메모리 내 Google Drive 시뮬레이터를 사용하며 Google에 연결하지 않습니다.',
                    es: 'El modo de prueba local esta activo. La sincronizacion usa un simulador de Google Drive en memoria y no contacta con Google.',
                    de: 'Der lokale Testmodus ist aktiv. Die Synchronisierung nutzt einen Google-Drive-Simulator im Speicher und kontaktiert Google nicht.',
                  )
                : strings.googleDriveWebSignInBody,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 12),
          if (fakeMode)
            FilledButton(
              key: SettingsScreen.syncConnectKey,
              onPressed:
                  ref
                          .watch(
                            syncAuthControllerProvider,
                          )[SyncProvider.googleDrive]
                          ?.stage ==
                      SyncAuthStage.busy
                  ? null
                  : () => ref
                        .read(syncAuthControllerProvider.notifier)
                        .connect(SyncProvider.googleDrive),
              child: Text(
                strings.localized(
                  en: 'Connect simulator',
                  ja: 'シミュレータに接続',
                  zh: '连接模拟器',
                  ko: '시뮬레이터에 연결',
                  es: 'Conectar simulador',
                  de: 'Simulator verbinden',
                ),
              ),
            )
          else if (_ready)
            buildGoogleSignInWebButton(locale: strings.locale.languageCode)
          else
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Text(
              '$error',
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.error),
            ),
          ],
        ],
      ),
    );
  }
}
