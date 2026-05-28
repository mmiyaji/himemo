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
