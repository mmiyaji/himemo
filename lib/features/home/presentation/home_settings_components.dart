part of 'home_page.dart';

class _SettingsOverviewItem {
  const _SettingsOverviewItem({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
  });

  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
}

class _ColorThemeScopeOption {
  const _ColorThemeScopeOption({required this.scope, required this.label});

  final String scope;
  final String label;
}

class _SettingsOverviewCard extends StatelessWidget {
  const _SettingsOverviewCard({required this.items});

  final List<_SettingsOverviewItem> items;

  @override
  Widget build(BuildContext context) {
    final muted = _mutedTextColor(context);
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 12.0;
          final width = constraints.maxWidth;
          final columns = width >= 720 ? 4 : (width >= 320 ? 2 : 1);
          final itemWidth = (width - spacing * (columns - 1)) / columns;
          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              for (final item in items)
                SizedBox(
                  width: itemWidth,
                  child: TextButton(
                    onPressed: item.onTap,
                    style: TextButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      padding: const EdgeInsets.all(4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    child: Row(
                      children: [
                        _SettingsSectionIcon(icon: item.icon),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                item.label,
                                style: Theme.of(
                                  context,
                                ).textTheme.labelMedium?.copyWith(color: muted),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                item.value,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.titleSmall,
                              ),
                            ],
                          ),
                        ),
                        if (item.onTap != null) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: muted,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _SettingsGroup extends StatelessWidget {
  const _SettingsGroup({
    required this.title,
    required this.summary,
    required this.icon,
    required this.children,
    this.sectionKey,
    this.controller,
    this.semanticLabel,
  });

  final String title;
  final String summary;
  final IconData icon;
  final List<Widget> children;
  final Key? sectionKey;
  final ExpansibleController? controller;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final borderRadius = BorderRadius.circular(6);
    return Semantics(
      key: sectionKey ?? (semanticLabel == null ? null : Key(semanticLabel!)),
      container: true,
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: borderRadius,
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                controller: controller,
                maintainState: true,
                tilePadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                leading: _SettingsSectionIcon(icon: icon),
                title: Text(title, style: theme.textTheme.titleMedium),
                subtitle: Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    summary,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
                shape: RoundedRectangleBorder(borderRadius: borderRadius),
                collapsedShape: RoundedRectangleBorder(
                  borderRadius: borderRadius,
                ),
                children: children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SettingsSectionLabel extends StatelessWidget {
  const _SettingsSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: _mutedTextColor(context),
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _SettingsWarningBox extends StatelessWidget {
  const _SettingsWarningBox({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colorScheme.error),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.warning_amber_rounded,
            color: colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDetailsOverviewPanel extends StatelessWidget {
  const _SyncDetailsOverviewPanel({
    required this.strings,
    required this.syncProvider,
    required this.syncAuthState,
    required this.syncTransferState,
    required this.syncQueueSummary,
    required this.syncBundleState,
    required this.syncBundleFingerprint,
    required this.onSyncNow,
  });

  final AppStrings strings;
  final SyncProvider syncProvider;
  final SyncAuthState syncAuthState;
  final SyncTransferState syncTransferState;
  final AsyncValue<SyncQueueSummary> syncQueueSummary;
  final AsyncValue<SyncBundleState> syncBundleState;
  final AsyncValue<String> syncBundleFingerprint;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final status = _syncDetailsStatusSummary(
      strings: strings,
      syncProvider: syncProvider,
      syncAuthState: syncAuthState,
      syncTransferState: syncTransferState,
      syncQueueSummary: syncQueueSummary,
    );
    final bundleState = syncBundleState.asData?.value;
    final remoteSummary = _remoteBundleSummary(
      strings,
      syncProvider,
      syncTransferState,
      bundleState,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SyncDetailsStatusBanner(status: status, onSyncNow: onSyncNow),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const spacing = 8.0;
            final width = constraints.maxWidth;
            final columns = width >= 680 ? 3 : (width >= 460 ? 2 : 1);
            final itemWidth = (width - spacing * (columns - 1)) / columns;
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                SizedBox(
                  width: itemWidth,
                  child: _SyncDetailsMetricCard(
                    label: strings.localized(
                      en: 'Pending upload',
                      ja: '送信待ち',
                      zh: '待上传',
                      ko: '업로드 대기',
                      es: 'Pendiente de envio',
                      de: 'Ausstehender Upload',
                    ),
                    value: _syncPendingMetricValue(strings, syncQueueSummary),
                    description: _syncPendingMetricDescription(
                      strings,
                      syncQueueSummary,
                    ),
                    icon: Icons.pending_actions_rounded,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _SyncDetailsMetricCard(
                    label: strings.localized(
                      en: 'Cloud check',
                      ja: '受信確認',
                      zh: '云端检查',
                      ko: '클라우드 확인',
                      es: 'Revision de nube',
                      de: 'Cloud-Prufung',
                    ),
                    value: _syncRemoteMetricValue(
                      strings,
                      syncProvider,
                      syncTransferState,
                      syncBundleState,
                    ),
                    description: remoteSummary,
                    icon: Icons.cloud_done_outlined,
                  ),
                ),
                SizedBox(
                  width: itemWidth,
                  child: _SyncDetailsMetricCard(
                    label: strings.localized(
                      en: 'Recovery key',
                      ja: '復元キー',
                      zh: '恢复密钥',
                      ko: '복구 키',
                      es: 'Clave de recuperacion',
                      de: 'Wiederherstellungsschlussel',
                    ),
                    value: _syncFingerprintMetricValue(
                      strings,
                      syncBundleFingerprint,
                    ),
                    description: strings.localized(
                      en: 'Use this when restoring sync on another device.',
                      ja: '別端末の復元に使用します。',
                      zh: '在其他设备上恢复同步时使用。',
                      ko: '다른 기기에서 동기화를 복원할 때 사용합니다.',
                      es: 'Usalo al restaurar la sincronizacion en otro dispositivo.',
                      de: 'Fur die Wiederherstellung auf einem anderen Gerat.',
                    ),
                    icon: Icons.key_outlined,
                    monospaceValue: true,
                  ),
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _SyncDetailsStatusBanner extends StatelessWidget {
  const _SyncDetailsStatusBanner({
    required this.status,
    required this.onSyncNow,
  });

  final _SyncDetailsStatusSummary status;
  final VoidCallback? onSyncNow;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final foreground = status.tone.foreground(colorScheme);
    final background = Color.alphaBlend(
      foreground.withValues(alpha: 0.10),
      colorScheme.surface,
    );
    final border = foreground.withValues(alpha: 0.34);

    return Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border),
      ),
      padding: const EdgeInsets.all(14),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final action = onSyncNow == null
              ? null
              : FilledButton.icon(
                  onPressed: onSyncNow,
                  icon: const Icon(Icons.sync_rounded),
                  label: Text(
                    context.strings.localized(
                      en: 'Sync now',
                      ja: '今すぐ同期',
                      zh: '立即同步',
                      ko: '지금 동기화',
                      es: 'Sincronizar ahora',
                      de: 'Jetzt synchronisieren',
                    ),
                  ),
                );
          final body = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(status.icon, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      status.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      status.description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );

          if (action == null) {
            return body;
          }
          if (constraints.maxWidth < 520) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [body, const SizedBox(height: 12), action],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: body),
              const SizedBox(width: 12),
              action,
            ],
          );
        },
      ),
    );
  }
}

class _SyncDetailsMetricCard extends StatelessWidget {
  const _SyncDetailsMetricCard({
    required this.label,
    required this.value,
    required this.description,
    required this.icon,
    this.monospaceValue = false,
  });

  final String label;
  final String value;
  final String description;
  final IconData icon;
  final bool monospaceValue;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      constraints: const BoxConstraints(minHeight: 116),
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: _mutedTextColor(context)),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: _mutedTextColor(context),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium?.copyWith(
              color: colorScheme.onSurface,
              fontFeatures: monospaceValue
                  ? const [ui.FontFeature.tabularFigures()]
                  : null,
              fontFamily: monospaceValue ? 'monospace' : null,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            description,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(
              color: _mutedTextColor(context),
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDetailsActionGrid extends StatelessWidget {
  const _SyncDetailsActionGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 12.0;
        final columns = constraints.maxWidth >= 760 ? 2 : 1;
        final width =
            (constraints.maxWidth - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

class _SyncDetailsActionCard extends StatelessWidget {
  const _SyncDetailsActionCard({
    required this.title,
    required this.description,
    required this.children,
  });

  final String title;
  final String description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Container(
      decoration: _sectionDecoration(context),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: colorScheme.outlineVariant),
          for (var index = 0; index < children.length; index++) ...[
            children[index],
            if (index != children.length - 1)
              Divider(height: 1, color: colorScheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _SyncDetailsActionRow extends StatelessWidget {
  const _SyncDetailsActionRow({
    required this.icon,
    required this.title,
    required this.description,
    this.actions = const [],
    this.warning = false,
  });

  final IconData icon;
  final String title;
  final String description;
  final List<Widget> actions;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconColor = warning ? Colors.orange.shade800 : colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.all(12),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final text = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurface,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      description,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: _mutedTextColor(context),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          final actionBar = Wrap(spacing: 8, runSpacing: 8, children: actions);
          if (actions.isEmpty) {
            return text;
          }
          if (constraints.maxWidth < 540) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                text,
                const SizedBox(height: 10),
                Align(alignment: Alignment.centerLeft, child: actionBar),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(child: text),
              const SizedBox(width: 12),
              Flexible(child: actionBar),
            ],
          );
        },
      ),
    );
  }
}

class _SyncDetailsStatusSummary {
  const _SyncDetailsStatusSummary({
    required this.title,
    required this.description,
    required this.icon,
    required this.tone,
  });

  final String title;
  final String description;
  final IconData icon;
  final _SyncDetailsTone tone;
}

enum _SyncDetailsTone {
  success,
  warning,
  error,
  info;

  Color foreground(ColorScheme colorScheme) {
    return switch (this) {
      _SyncDetailsTone.success => Colors.green.shade700,
      _SyncDetailsTone.warning => Colors.orange.shade800,
      _SyncDetailsTone.error => colorScheme.error,
      _SyncDetailsTone.info => colorScheme.primary,
    };
  }
}

_SyncDetailsStatusSummary _syncDetailsStatusSummary({
  required AppStrings strings,
  required SyncProvider syncProvider,
  required SyncAuthState syncAuthState,
  required SyncTransferState syncTransferState,
  required AsyncValue<SyncQueueSummary> syncQueueSummary,
}) {
  final providerName = _syncProviderName(syncProvider);
  if (syncProvider == SyncProvider.off) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: 'Cloud sync is off',
        ja: 'クラウド同期はオフです',
        zh: '云同步已关闭',
        ko: '클라우드 동기화가 꺼져 있습니다',
        es: 'La sincronizacion en la nube esta desactivada',
        de: 'Cloud-Synchronisierung ist aus',
      ),
      description: strings.text('home.keep.data.on.this.device.only'),
      icon: Icons.sync_disabled_rounded,
      tone: _SyncDetailsTone.info,
    );
  }
  if (!syncAuthState.isAuthenticated) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: '$providerName is not connected',
        ja: '$providerName に未接続です',
        zh: '$providerName 未连接',
        ko: '$providerName에 연결되지 않았습니다',
        es: '$providerName no esta conectado',
        de: '$providerName ist nicht verbunden',
      ),
      description: syncAuthState.message ?? strings.text('home.connect'),
      icon: Icons.cloud_off_outlined,
      tone: _SyncDetailsTone.warning,
    );
  }
  if (syncTransferState.stage == SyncTransferStage.busy) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: 'Sync is running',
        ja: '同期を実行中です',
        zh: '正在同步',
        ko: '동기화 중입니다',
        es: 'La sincronizacion esta en curso',
        de: 'Synchronisierung lauft',
      ),
      description: _syncProgressDescription(
        strings,
        syncTransferState,
        syncProvider,
      ),
      icon: Icons.sync_rounded,
      tone: _SyncDetailsTone.info,
    );
  }
  if (syncTransferState.stage == SyncTransferStage.error) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: 'Sync needs attention',
        ja: '同期で確認が必要です',
        zh: '同步需要确认',
        ko: '동기화 확인이 필요합니다',
        es: 'La sincronizacion requiere atencion',
        de: 'Synchronisierung benotigt Aufmerksamkeit',
      ),
      description:
          syncTransferState.detail ??
          syncTransferState.message ??
          _syncProgressDescription(strings, syncTransferState, syncProvider),
      icon: Icons.error_outline_rounded,
      tone: _SyncDetailsTone.error,
    );
  }

  final queue = syncQueueSummary.asData?.value;
  if (queue != null && queue.hasPendingChanges) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: '${queue.totalChanges} changes are waiting to upload',
        ja: '${queue.totalChanges}件の変更が送信待ちです',
        zh: '${queue.totalChanges} 项变更待上传',
        ko: '${queue.totalChanges}개 변경 사항이 업로드 대기 중입니다',
        es: '${queue.totalChanges} cambios esperan envio',
        de: '${queue.totalChanges} Anderungen warten auf Upload',
      ),
      description: _syncPendingMetricDescription(strings, syncQueueSummary),
      icon: Icons.pending_actions_rounded,
      tone: _SyncDetailsTone.warning,
    );
  }

  final queueLoading = syncQueueSummary.maybeWhen(
    loading: () => true,
    orElse: () => false,
  );
  if (queueLoading) {
    return _SyncDetailsStatusSummary(
      title: strings.localized(
        en: 'Checking local sync queue',
        ja: 'この端末の同期キューを確認中です',
        zh: '正在检查本地同步队列',
        ko: '이 기기의 동기화 대기열을 확인 중입니다',
        es: 'Revisando la cola local de sincronizacion',
        de: 'Lokale Synchronisierungswarteschlange wird gepruft',
      ),
      description: strings.text('home.checking.pending.changes'),
      icon: Icons.manage_search_rounded,
      tone: _SyncDetailsTone.info,
    );
  }

  return _SyncDetailsStatusSummary(
    title: strings.localized(
      en: 'Synced with $providerName',
      ja: '$providerName と同期済みです',
      zh: '已与 $providerName 同步',
      ko: '$providerName와 동기화되었습니다',
      es: 'Sincronizado con $providerName',
      de: 'Mit $providerName synchronisiert',
    ),
    description: strings.localized(
      en: 'There are no pending changes on this device. Check the cloud if you want to receive changes from another device.',
      ja: 'この端末に送信待ちの変更はありません。ほかの端末の変更を受け取る場合はクラウドの状態を確認します。',
      zh: '此设备没有待发送变更。如需接收其他设备的变更，请检查云端状态。',
      ko: '이 기기에 전송 대기 중인 변경 사항은 없습니다. 다른 기기의 변경 사항을 받으려면 클라우드 상태를 확인하세요.',
      es: 'No hay cambios pendientes en este dispositivo. Revisa la nube para recibir cambios de otro dispositivo.',
      de: 'Auf diesem Gerat gibt es keine ausstehenden Anderungen. Prufe die Cloud, um Anderungen anderer Gerate zu empfangen.',
    ),
    icon: Icons.check_circle_outline_rounded,
    tone: _SyncDetailsTone.success,
  );
}

String _syncPendingMetricValue(
  AppStrings strings,
  AsyncValue<SyncQueueSummary> syncQueueSummary,
) {
  return syncQueueSummary.when(
    data: (summary) => strings.localized(
      en: '${summary.totalChanges}',
      ja: '${summary.totalChanges}件',
      zh: '${summary.totalChanges}项',
      ko: '${summary.totalChanges}개',
      es: '${summary.totalChanges}',
      de: '${summary.totalChanges}',
    ),
    loading: () => strings.localized(
      en: 'Checking',
      ja: '確認中',
      zh: '检查中',
      ko: '확인 중',
      es: 'Revisando',
      de: 'Prufung',
    ),
    error: (_, _) => '--',
  );
}

String _syncPendingMetricDescription(
  AppStrings strings,
  AsyncValue<SyncQueueSummary> syncQueueSummary,
) {
  return syncQueueSummary.when(
    data: (summary) {
      if (!summary.hasPendingChanges) {
        return strings.text('home.no.pending.device.changes');
      }
      final timestamp = summary.lastQueuedAt;
      final stampText = timestamp == null
          ? strings.text('home.queue.ready')
          : strings.lastQueuedAt(_formatDateTime(timestamp, strings));
      return strings.pendingSyncSummary(
        total: summary.totalChanges,
        upserts: summary.upserts,
        deletes: summary.deletes,
        stamp: stampText,
      );
    },
    loading: () => strings.text('home.checking.pending.changes'),
    error: (_, _) =>
        strings.text('home.unable.to.inspect.the.local.sync.queue'),
  );
}

String _syncRemoteMetricValue(
  AppStrings strings,
  SyncProvider syncProvider,
  SyncTransferState syncTransferState,
  AsyncValue<SyncBundleState> syncBundleState,
) {
  if (syncProvider == SyncProvider.off) {
    return strings.localized(
      en: 'Not set',
      ja: '未設定',
      zh: '未设置',
      ko: '미설정',
      es: 'Sin configurar',
      de: 'Nicht gesetzt',
    );
  }
  if (syncTransferState.remoteStatus != null ||
      syncBundleState.asData?.value.lastRemoteModifiedAt != null) {
    return strings.localized(
      en: 'Checked',
      ja: '確認済み',
      zh: '已检查',
      ko: '확인됨',
      es: 'Revisado',
      de: 'Gepruft',
    );
  }
  final loading = syncBundleState.maybeWhen(
    loading: () => true,
    orElse: () => false,
  );
  if (loading) {
    return strings.localized(
      en: 'Checking',
      ja: '確認中',
      zh: '检查中',
      ko: '확인 중',
      es: 'Revisando',
      de: 'Prufung',
    );
  }
  return strings.localized(
    en: 'Not checked',
    ja: '未確認',
    zh: '未检查',
    ko: '미확인',
    es: 'Sin revisar',
    de: 'Nicht gepruft',
  );
}

String _syncFingerprintMetricValue(
  AppStrings strings,
  AsyncValue<String> syncBundleFingerprint,
) {
  return syncBundleFingerprint.when(
    data: _maskSyncFingerprint,
    loading: () => strings.localized(
      en: 'Preparing',
      ja: '準備中',
      zh: '准备中',
      ko: '준비 중',
      es: 'Preparando',
      de: 'Vorbereitung',
    ),
    error: (_, _) => strings.localized(
      en: 'Unavailable',
      ja: '読取不可',
      zh: '不可用',
      ko: '사용 불가',
      es: 'No disponible',
      de: 'Nicht verfugbar',
    ),
  );
}

const _maskedSyncFingerprint =
    '\u2022\u2022\u2022\u2022 '
    '\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022';

String _maskSyncFingerprint(String value) {
  return value.trim().isEmpty ? '--' : _maskedSyncFingerprint;
}

class _SettingsSectionIcon extends StatelessWidget {
  const _SettingsSectionIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      width: 40,
      height: 40,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(icon, size: 22, color: colorScheme.primary),
    );
  }
}

class _SettingsListIcon extends StatelessWidget {
  const _SettingsListIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(dimension: 24, child: Icon(icon));
  }
}

class _AdminModeAuditNotice extends StatelessWidget {
  const _AdminModeAuditNotice({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tooltip = Tooltip(
      message: text,
      child: Icon(
        Icons.info_outline_rounded,
        size: 18,
        color: colorScheme.primary,
      ),
    );
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.22)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            tooltip,
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface,
                  height: 1.35,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AuditLogPreview extends StatelessWidget {
  const _AuditLogPreview({required this.entries, required this.emptyMessage});

  final List<String> entries;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final baseStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(fontFamily: 'monospace', height: 1.35);
    if (entries.isEmpty) {
      return SelectableText(emptyMessage, style: baseStyle);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final entry in entries) _AuditLogPreviewLine(entry: entry),
      ],
    );
  }
}

class _AuditLogPreviewLine extends StatelessWidget {
  const _AuditLogPreviewLine({required this.entry});

  final String entry;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontFamily: 'monospace',
      height: 1.35,
      color: _textColor(colorScheme),
      fontWeight: _isAdminModeAuditEvent ? FontWeight.w700 : null,
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: _isAdminModeAuditEvent
          ? const EdgeInsets.symmetric(horizontal: 8, vertical: 5)
          : EdgeInsets.zero,
      decoration: _isAdminModeAuditEvent
          ? BoxDecoration(
              color: _backgroundColor(colorScheme),
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _borderColor(colorScheme)),
            )
          : null,
      child: SelectableText(entry, style: style),
    );
  }

  bool get _isAdminModeLogin => entry.contains('admin_mode_login');

  bool get _isAdminModeLogout => entry.contains('admin_mode_logout');

  bool get _isAdminModeAuditEvent => _isAdminModeLogin || _isAdminModeLogout;

  Color? _textColor(ColorScheme colorScheme) {
    if (_isAdminModeLogin) {
      return colorScheme.error;
    }
    if (_isAdminModeLogout) {
      return colorScheme.primary;
    }
    return null;
  }

  Color _backgroundColor(ColorScheme colorScheme) {
    if (_isAdminModeLogin) {
      return colorScheme.errorContainer.withValues(alpha: 0.55);
    }
    return colorScheme.primaryContainer.withValues(alpha: 0.48);
  }

  Color _borderColor(ColorScheme colorScheme) {
    if (_isAdminModeLogin) {
      return colorScheme.error.withValues(alpha: 0.28);
    }
    return colorScheme.primary.withValues(alpha: 0.24);
  }
}

class _ColorThemePicker extends StatefulWidget {
  const _ColorThemePicker({
    required this.current,
    required this.basicThemes,
    required this.extendedThemes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
    required this.tileKeyFor,
    required this.onSelect,
  });

  final AppColorTheme current;
  final List<AppColorTheme> basicThemes;
  final List<AppColorTheme> extendedThemes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;
  final Key? Function(AppColorTheme theme) tileKeyFor;
  final ValueChanged<AppColorTheme> onSelect;

  @override
  State<_ColorThemePicker> createState() => _ColorThemePickerState();
}

class _ColorThemePickerState extends State<_ColorThemePicker> {
  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final extendedSelected = widget.extendedThemes.contains(widget.current);
    final basicSelected = widget.basicThemes.contains(widget.current);
    final themes = [
      ...widget.basicThemes,
      if (extendedSelected && !basicSelected) widget.current,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final theme in themes)
          _ThemeOptionTile(
            tileKey: widget.tileKeyFor(theme),
            title: widget.titleFor(theme),
            subtitle: widget.subtitleFor(theme),
            sampleColor: widget.sampleColorFor(theme),
            selected: widget.current == theme,
            onTap: () => widget.onSelect(theme),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () => _showExtendedThemeDialog(context),
            icon: const Icon(Icons.palette_outlined),
            label: Text(
              strings.extendedThemesWithCount(widget.extendedThemes.length),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showExtendedThemeDialog(BuildContext context) async {
    final selected = await showModalBottomSheet<AppColorTheme>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      useSafeArea: true,
      showDragHandle: false,
      clipBehavior: Clip.antiAlias,
      builder: (context) {
        return _ExtendedColorThemeSheet(
          current: widget.current,
          themes: widget.extendedThemes,
          titleFor: widget.titleFor,
          subtitleFor: widget.subtitleFor,
          sampleColorFor: widget.sampleColorFor,
        );
      },
    );
    if (selected != null) {
      widget.onSelect(selected);
    }
  }
}

class _ExtendedColorThemeSheet extends StatelessWidget {
  const _ExtendedColorThemeSheet({
    required this.current,
    required this.themes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
  });

  final AppColorTheme current;
  final List<AppColorTheme> themes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      heightFactor: 0.88,
      child: _ExtendedColorThemeSheetBody(
        current: current,
        themes: themes,
        titleFor: titleFor,
        subtitleFor: subtitleFor,
        sampleColorFor: sampleColorFor,
      ),
    );
  }
}

class _ExtendedColorThemeSheetBody extends StatelessWidget {
  const _ExtendedColorThemeSheetBody({
    required this.current,
    required this.themes,
    required this.titleFor,
    required this.subtitleFor,
    required this.sampleColorFor,
  });

  final AppColorTheme current;
  final List<AppColorTheme> themes;
  final String Function(AppColorTheme theme) titleFor;
  final String Function(AppColorTheme theme) subtitleFor;
  final Color Function(AppColorTheme theme) sampleColorFor;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final grouped = <String, List<AppColorTheme>>{};
    for (final theme in themes) {
      grouped.putIfAbsent(_categoryFor(context, theme), () => []).add(theme);
    }
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: Stack(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 70),
              Expanded(
                child: ClipRect(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final columns = constraints.maxWidth >= 720
                          ? 3
                          : constraints.maxWidth >= 460
                          ? 2
                          : 1;
                      return CustomScrollView(
                        slivers: [
                          for (final entry in grouped.entries) ...[
                            SliverToBoxAdapter(
                              child: Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  12,
                                  16,
                                  8,
                                ),
                                child: Text(
                                  entry.key,
                                  style: Theme.of(context).textTheme.labelLarge,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                              ),
                              sliver: SliverGrid.builder(
                                itemCount: entry.value.length,
                                gridDelegate:
                                    SliverGridDelegateWithFixedCrossAxisCount(
                                      crossAxisCount: columns,
                                      crossAxisSpacing: 10,
                                      mainAxisSpacing: 10,
                                      childAspectRatio: columns == 1
                                          ? 3.7
                                          : 2.5,
                                    ),
                                itemBuilder: (context, index) {
                                  final theme = entry.value[index];
                                  return _ColorThemeCard(
                                    title: titleFor(theme),
                                    subtitle: subtitleFor(theme),
                                    sampleColor: sampleColorFor(theme),
                                    selected: current == theme,
                                    onTap: () =>
                                        Navigator.of(context).pop(theme),
                                  );
                                },
                              ),
                            ),
                          ],
                          const SliverToBoxAdapter(child: SizedBox(height: 16)),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          Positioned(
            left: 0,
            top: 0,
            right: 0,
            height: 70,
            child: ColoredBox(
              color: colorScheme.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      margin: const EdgeInsets.only(top: 10, bottom: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.45,
                        ),
                        borderRadius: BorderRadius.circular(999),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      strings.extendedThemes,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _categoryFor(BuildContext context, AppColorTheme theme) {
    final strings = context.strings;
    return switch (theme) {
      AppColorTheme.ai ||
      AppColorTheme.chigusa ||
      AppColorTheme.konjyo ||
      AppColorTheme.hanada ||
      AppColorTheme.sora ||
      AppColorTheme.ruri ||
      AppColorTheme.asagi => strings.themeCategoryBlueGreen,
      AppColorTheme.fuji ||
      AppColorTheme.sumire ||
      AppColorTheme.kikyo ||
      AppColorTheme.edomurasaki ||
      AppColorTheme.shion => strings.themeCategoryPurple,
      AppColorTheme.moegi ||
      AppColorTheme.seiheki ||
      AppColorTheme.wakatake ||
      AppColorTheme.tokiwa ||
      AppColorTheme.byakuroku => strings.themeCategoryGreenYellow,
      AppColorTheme.yamabuki ||
      AppColorTheme.nanohana ||
      AppColorTheme.kurumi ||
      AppColorTheme.rikyucha => strings.themeCategoryEarth,
      AppColorTheme.kurenai ||
      AppColorTheme.sakura ||
      AppColorTheme.enji ||
      AppColorTheme.haizakura ||
      AppColorTheme.akane => strings.themeCategoryRedPink,
      AppColorTheme.sumi ||
      AppColorTheme.ginnezumi ||
      AppColorTheme.shironeri ||
      AppColorTheme.gofun => strings.themeCategoryNeutral,
    };
  }
}

class _ColorThemeCard extends StatelessWidget {
  const _ColorThemeCard({
    required this.title,
    required this.subtitle,
    required this.sampleColor,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final Color sampleColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Ink(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? colorScheme.primary : colorScheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
          color: colorScheme.surface,
        ),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: sampleColor,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (selected) ...[
                const SizedBox(width: 8),
                Icon(Icons.check_circle_rounded, color: colorScheme.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ThemeOptionTile extends StatelessWidget {
  const _ThemeOptionTile({
    this.tileKey,
    required this.title,
    required this.subtitle,
    this.sampleColor,
    required this.selected,
    required this.onTap,
  });

  final Key? tileKey;
  final String title;
  final String subtitle;
  final Color? sampleColor;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final sampleColor = this.sampleColor;
    return ListTile(
      key: tileKey,
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        selected ? Icons.radio_button_checked : Icons.radio_button_off,
      ),
      title: sampleColor == null
          ? Text(title)
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title),
                const SizedBox(height: 4),
                Container(
                  width: 44,
                  height: 3,
                  decoration: BoxDecoration(
                    color: sampleColor,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ],
            ),
      subtitle: Text(subtitle),
      onTap: onTap,
    );
  }
}
