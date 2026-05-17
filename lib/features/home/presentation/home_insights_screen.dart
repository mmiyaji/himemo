part of 'home_page.dart';

class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  List<NoteEntry>? _cachedNotes;
  Locale? _cachedLocale;
  _InsightsData? _cachedInsights;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final notes = ref.watch(unfilteredVisibleNotesProvider);
    final locale = Localizations.localeOf(context);
    var insights = _cachedInsights;
    if (insights == null ||
        !identical(_cachedNotes, notes) ||
        _cachedLocale != locale) {
      insights = _buildInsightsData(context, notes);
      _cachedNotes = notes;
      _cachedLocale = locale;
      _cachedInsights = insights;
    }
    final summary = insights.summary;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Container(
          decoration: _sectionDecoration(context),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                strings.text('home.writing.activity'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 8),
              Text(
                summary.message,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: _strongMutedTextColor(context),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (notes.isEmpty)
          _InsightsEmptyGuide(
            onAddNote: () => showNoteEditorSheet(context, ref),
            onOpenNotes: () => context.go('/notes'),
          )
        else ...[
          _InsightsSummaryGrid(summary: summary),
          const SizedBox(height: 16),
          _InsightChartSection(
            title: strings.text('home.monthly.notes'),
            description: strings.text(
              'home.notes.created.over.the.last.6.months',
            ),
            child: _InsightLineChart(
              buckets: insights.monthlyBuckets,
              valueSuffix: strings.text('home.notes'),
            ),
          ),
          const SizedBox(height: 16),
          _InsightChartSection(
            title: strings.text('home.recent.days'),
            description: strings.text(
              'home.daily.note.count.over.the.last.14.days',
            ),
            child: _InsightBarChart(
              buckets: insights.recentDayBuckets,
              valueSuffix: strings.text('home.notes'),
            ),
          ),
          const SizedBox(height: 16),
          _InsightChartSection(
            title: strings.text('home.weekday.and.time.rhythm'),
            description: strings.text(
              'home.notes.by.weekday.and.3.hour.time.block',
            ),
            child: _WeekdayHourHistogram(
              buckets: insights.weekdayHourBuckets,
              valueSuffix: strings.text('home.notes'),
            ),
          ),
          const SizedBox(height: 16),
          _InsightChartSection(
            title: strings.text('home.attachments'),
            description: strings.text(
              'home.how.often.photos.videos.and.audio.are.used',
            ),
            child: _InsightHorizontalBarChart(
              buckets: insights.attachmentBuckets,
              valueSuffix: strings.text('home.items'),
            ),
          ),
        ],
      ],
    );
  }
}

class _InsightsEmptyGuide extends StatelessWidget {
  const _InsightsEmptyGuide({
    required this.onAddNote,
    required this.onOpenNotes,
  });

  final VoidCallback onAddNote;
  final VoidCallback onOpenNotes;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            strings.localized(
              en: 'Build a record first',
              ja: '\u307e\u305a\u306f\u8a18\u9332\u3092\u305f\u3081\u308b',
              zh: '\u5148\u5f00\u59cb\u79ef\u7d2f\u8bb0\u5f55',
              ko: '\uba3c\uc800 \uae30\ub85d\uc744 \uc313\uae30',
              es: 'Primero crea registros',
              de: 'Zuerst Aufzeichnungen sammeln',
            ),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            strings.localized(
              en: 'Charts become useful after a few notes. Start with one memo, then add tags, media, or a location when it helps.',
              ja: '\u30b0\u30e9\u30d5\u306f\u30e1\u30e2\u304c\u5897\u3048\u308b\u3068\u5f79\u7acb\u3061\u307e\u3059\u3002\u307e\u305a1\u4ef6\u4f5c\u308a\u3001\u5fc5\u8981\u306a\u3068\u304d\u306b\u30bf\u30b0\u30fb\u30e1\u30c7\u30a3\u30a2\u30fb\u4f4d\u7f6e\u60c5\u5831\u3092\u8ffd\u52a0\u3057\u307e\u3059\u3002',
              zh: '\u6709\u51e0\u6761\u7b14\u8bb0\u540e\uff0c\u56fe\u8868\u624d\u4f1a\u66f4\u6709\u7528\u3002\u5148\u5199\u4e00\u6761\u5907\u5fd8\uff0c\u9700\u8981\u65f6\u518d\u52a0\u6807\u7b7e\u3001\u5a92\u4f53\u6216\u4f4d\u7f6e\u3002',
              ko: '\uba54\ubaa8\uac00 \uba87 \uac1c \uc313\uc774\uba74 \ucc28\ud2b8\uac00 \uc720\uc6a9\ud574\uc9d1\ub2c8\ub2e4. \uba3c\uc800 \ud558\ub098\ub97c \uc791\uc131\ud558\uace0, \ud544\uc694\ud560 \ub54c \ud0dc\uadf8\u00b7\ubbf8\ub514\uc5b4\u00b7\uc704\uce58\ub97c \ucd94\uac00\ud558\uc138\uc694.',
              es: 'Los graficos son utiles despues de algunas notas. Empieza con una y anade etiquetas, medios o ubicacion cuando ayude.',
              de: 'Diagramme werden nach einigen Notizen nuetzlich. Beginne mit einer Notiz und ergaenze Tags, Medien oder Orte bei Bedarf.',
            ),
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: onAddNote,
                icon: const Icon(Icons.edit_note_rounded),
                label: Text(strings.addNote),
              ),
              OutlinedButton.icon(
                onPressed: onOpenNotes,
                icon: const Icon(Icons.notes_outlined),
                label: Text(strings.notes),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _InsightsSummaryGrid extends StatelessWidget {
  const _InsightsSummaryGrid({required this.summary});

  final _InsightsSummary summary;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    return Container(
      decoration: _sectionDecoration(context),
      child: Wrap(
        children: [
          _InsightKpiTile(
            label: strings.text('home.current.streak'),
            value: '${summary.currentStreak}',
            helper: strings.text('home.days'),
          ),
          _InsightKpiTile(
            label: strings.text('home.this.month'),
            value: '${summary.thisMonthCount}',
            helper: strings.text('home.notes.2'),
          ),
          _InsightKpiTile(
            label: strings.text('home.characters'),
            value: '${summary.totalCharacters}',
            helper: strings.text('home.total'),
          ),
          _InsightKpiTile(
            label: strings.text('home.attachments'),
            value: '${summary.totalAttachments}',
            helper: strings.text('home.items.2'),
          ),
          _InsightKpiTile(
            label: strings.text('home.best.day'),
            value: summary.bestDayLabel,
            helper: strings.notesCount(summary.bestDayValue),
          ),
          _InsightKpiTile(
            label: strings.text('home.best.hour'),
            value: summary.bestHourLabel,
            helper: strings.text('home.peak.time'),
          ),
          _InsightKpiTile(
            label: strings.text('home.monthly.trend'),
            value: summary.monthlyDeltaLabel,
            helper: strings.text('home.vs.last.month'),
          ),
        ],
      ),
    );
  }
}

class _InsightKpiTile extends StatelessWidget {
  const _InsightKpiTile({
    required this.label,
    required this.value,
    required this.helper,
  });

  final String label;
  final String value;
  final String helper;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.sizeOf(context).width < 560
          ? (MediaQuery.sizeOf(context).width - 64) / 2
          : 220,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: _mutedTextColor(context),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text(
                    helper,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: _mutedTextColor(context),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _InsightChartSection extends StatelessWidget {
  const _InsightChartSection({
    required this.title,
    required this.description,
    required this.child,
  });

  final String title;
  final String description;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: _sectionDecoration(context),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text(
            description,
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: _mutedTextColor(context)),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }
}

class _InsightBarChart extends StatefulWidget {
  const _InsightBarChart({required this.buckets, required this.valueSuffix});

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  State<_InsightBarChart> createState() => _InsightBarChartState();
}

class _InsightBarChartState extends State<_InsightBarChart> {
  final ScrollController _scrollController = ScrollController();
  Object? _lastScrolledBuckets;

  @override
  void initState() {
    super.initState();
    _scheduleScrollToLatest();
  }

  @override
  void didUpdateWidget(covariant _InsightBarChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.buckets, widget.buckets)) {
      _scheduleScrollToLatest();
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scheduleScrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) {
        return;
      }
      if (identical(_lastScrolledBuckets, widget.buckets)) {
        return;
      }
      _lastScrolledBuckets = widget.buckets;
      _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
    });
  }

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final buckets = widget.buckets;
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    if (buckets.isEmpty) {
      return Text(
        strings.text('home.no.data.yet'),
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final chartWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 640.0;
        final itemWidth = math.max(44.0, (chartWidth / buckets.length) - 8);
        return SingleChildScrollView(
          controller: _scrollController,
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final bucket in buckets)
                SizedBox(
                  width: itemWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Text(
                          '${bucket.value}${widget.valueSuffix}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(color: _mutedTextColor(context)),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          height: 140,
                          alignment: Alignment.bottomCenter,
                          decoration: BoxDecoration(
                            color: Theme.of(
                              context,
                            ).colorScheme.surfaceContainerLowest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: FractionallySizedBox(
                            heightFactor: maxValue == 0
                                ? 0.04
                                : bucket.value / maxValue,
                            widthFactor: 1,
                            child: Container(
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primary.withValues(alpha: 0.82),
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(8),
                                  bottom: Radius.circular(7),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          bucket.label,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.labelMedium,
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _InsightLineChart extends StatelessWidget {
  const _InsightLineChart({required this.buckets, required this.valueSuffix});

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 172,
          child: CustomPaint(
            painter: _InsightLineChartPainter(
              buckets: buckets,
              maxValue: maxValue,
              lineColor: Theme.of(context).colorScheme.primary,
              fillColor: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.12),
              gridColor: Theme.of(context).dividerColor,
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Text(
                buckets.first.label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ),
            Text(
              '${buckets.last.value}$valueSuffix',
              style: Theme.of(
                context,
              ).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            Expanded(
              child: Text(
                buckets.last.label,
                textAlign: TextAlign.end,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: _mutedTextColor(context),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _InsightLineChartPainter extends CustomPainter {
  const _InsightLineChartPainter({
    required this.buckets,
    required this.maxValue,
    required this.lineColor,
    required this.fillColor,
    required this.gridColor,
  });

  final List<_InsightBucket> buckets;
  final int maxValue;
  final Color lineColor;
  final Color fillColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (final factor in const [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height - size.height * factor;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
    if (buckets.isEmpty) {
      return;
    }
    final denominator = math.max(1, maxValue);
    final points = <Offset>[];
    for (var i = 0; i < buckets.length; i++) {
      final x = buckets.length == 1
          ? size.width / 2
          : size.width * i / (buckets.length - 1);
      final y = size.height - size.height * buckets[i].value / denominator;
      points.add(Offset(x, y));
    }
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fillColor);

    final linePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      linePath.lineTo(point.dx, point.dy);
    }
    canvas.drawPath(
      linePath,
      Paint()
        ..color = lineColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    final pointPaint = Paint()..color = lineColor;
    for (final point in points) {
      canvas.drawCircle(point, 4, pointPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _InsightLineChartPainter oldDelegate) {
    return oldDelegate.buckets != buckets ||
        oldDelegate.maxValue != maxValue ||
        oldDelegate.lineColor != lineColor ||
        oldDelegate.fillColor != fillColor ||
        oldDelegate.gridColor != gridColor;
  }
}

class _InsightHorizontalBarChart extends StatelessWidget {
  const _InsightHorizontalBarChart({
    required this.buckets,
    required this.valueSuffix,
  });

  final List<_InsightBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        for (final bucket in buckets) ...[
          Row(
            children: [
              SizedBox(
                width: 72,
                child: Text(
                  bucket.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(999),
                  child: LinearProgressIndicator(
                    minHeight: 12,
                    value: maxValue == 0 ? 0 : bucket.value / maxValue,
                    backgroundColor: colorScheme.surfaceContainerHighest,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                width: 68,
                child: Text(
                  '${bucket.value}$valueSuffix',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: _mutedTextColor(context),
                  ),
                ),
              ),
            ],
          ),
          if (bucket != buckets.last) const SizedBox(height: 10),
        ],
      ],
    );
  }
}

class _WeekdayHourHistogram extends StatelessWidget {
  const _WeekdayHourHistogram({
    required this.buckets,
    required this.valueSuffix,
  });

  final List<_WeekdayHourBucket> buckets;
  final String valueSuffix;

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return _NoInsightData();
    }
    final maxValue = buckets.fold<int>(
      0,
      (max, bucket) => math.max(max, bucket.value),
    );
    final strings = context.strings;
    final weekdays = strings.weekdayShortLabels;
    final timeLabels = [
      for (var hour = 0; hour < 24; hour += 3)
        '${hour.toString().padLeft(2, '0')}-${(hour + 2).toString().padLeft(2, '0')}',
    ];
    final colorScheme = Theme.of(context).colorScheme;
    final bucketByKey = {
      for (final bucket in buckets)
        '${bucket.weekday}-${bucket.startHour}': bucket,
    };

    Color cellColor(int value) {
      if (value == 0 || maxValue == 0) {
        return colorScheme.surfaceContainerHighest.withValues(alpha: 0.55);
      }
      final intensity = value / maxValue;
      return Color.lerp(
        colorScheme.primary.withValues(alpha: 0.12),
        colorScheme.primary,
        intensity.clamp(0.0, 1.0),
      )!;
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : 360.0;
        const labelWidth = 34.0;
        const gap = 4.0;
        final cellSize = ((maxWidth - labelWidth - gap * 7) / 7).clamp(
          18.0,
          30.0,
        );
        final labelStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          color: _mutedTextColor(context),
          fontSize: 10,
          fontWeight: FontWeight.w700,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const SizedBox(width: labelWidth),
                for (final weekday in weekdays)
                  SizedBox(
                    width: cellSize + gap,
                    child: Text(
                      weekday,
                      textAlign: TextAlign.center,
                      style: labelStyle,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 4),
            for (var row = 0; row < timeLabels.length; row++) ...[
              Row(
                children: [
                  SizedBox(
                    width: labelWidth,
                    child: Text(
                      row.isEven ? timeLabels[row].substring(0, 2) : '',
                      style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                    ),
                  ),
                  for (var weekday = 1; weekday <= 7; weekday++)
                    Padding(
                      padding: const EdgeInsets.only(right: gap, bottom: gap),
                      child: _WeekdayHourCell(
                        size: cellSize,
                        value: bucketByKey['$weekday-${row * 3}']?.value ?? 0,
                        maxValue: maxValue,
                        valueSuffix: valueSuffix,
                        color: cellColor(
                          bucketByKey['$weekday-${row * 3}']?.value ?? 0,
                        ),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 6),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  strings.text('home.less'),
                  style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                ),
                const SizedBox(width: 6),
                for (final alpha in const [0.0, 0.25, 0.5, 0.75, 1.0]) ...[
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: Color.lerp(
                        colorScheme.surfaceContainerHighest.withValues(
                          alpha: 0.55,
                        ),
                        colorScheme.primary,
                        alpha,
                      ),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: Theme.of(context).dividerColor),
                    ),
                    child: const SizedBox(width: 10, height: 10),
                  ),
                  const SizedBox(width: 3),
                ],
                const SizedBox(width: 3),
                Text(
                  strings.text('home.more'),
                  style: labelStyle?.copyWith(fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}

class _WeekdayHourCell extends StatelessWidget {
  const _WeekdayHourCell({
    required this.size,
    required this.value,
    required this.maxValue,
    required this.valueSuffix,
    required this.color,
  });

  final double size;
  final int value;
  final int maxValue;
  final String valueSuffix;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: '$value$valueSuffix',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Theme.of(context).dividerColor),
        ),
        child: SizedBox(width: size, height: size),
      ),
    );
  }
}

class _NoInsightData extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Text(
      context.strings.text('home.no.data.yet'),
      style: Theme.of(
        context,
      ).textTheme.bodyMedium?.copyWith(color: _mutedTextColor(context)),
    );
  }
}

class _InsightBucket {
  const _InsightBucket({required this.label, required this.value});

  final String label;
  final int value;
}

class _WeekdayHourBucket {
  const _WeekdayHourBucket({
    required this.weekday,
    required this.startHour,
    required this.value,
  });

  final int weekday;
  final int startHour;
  final int value;
}

class _InsightsSummary {
  const _InsightsSummary({
    required this.currentStreak,
    required this.thisMonthCount,
    required this.totalCharacters,
    required this.totalAttachments,
    required this.bestDayLabel,
    required this.bestDayValue,
    required this.bestHourLabel,
    required this.monthlyDeltaLabel,
    required this.message,
  });

  final int currentStreak;
  final int thisMonthCount;
  final int totalCharacters;
  final int totalAttachments;
  final String bestDayLabel;
  final int bestDayValue;
  final String bestHourLabel;
  final String monthlyDeltaLabel;
  final String message;
}

class _InsightsData {
  const _InsightsData({
    required this.summary,
    required this.monthlyBuckets,
    required this.recentDayBuckets,
    required this.weekdayHourBuckets,
    required this.attachmentBuckets,
  });

  final _InsightsSummary summary;
  final List<_InsightBucket> monthlyBuckets;
  final List<_InsightBucket> recentDayBuckets;
  final List<_WeekdayHourBucket> weekdayHourBuckets;
  final List<_InsightBucket> attachmentBuckets;
}

_InsightsData _buildInsightsData(BuildContext context, List<NoteEntry> notes) {
  final watch = kDebugMode ? (Stopwatch()..start()) : null;
  final strings = context.strings;
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final previousMonth = DateTime(now.year, now.month - 1);
  var thisMonthCount = 0;
  var previousMonthCount = 0;
  var totalCharacters = 0;
  var totalAttachments = 0;
  final activeDaysSet = <DateTime>{};
  final monthCounts = <int, int>{};
  final dayCounts = <DateTime, int>{};
  final weekdayHourCounts = <String, int>{};
  final hourCounts = <int, int>{};
  var photoAttachments = 0;
  var videoAttachments = 0;
  var audioAttachments = 0;

  for (final note in notes) {
    final createdAt = note.createdAt.toLocal();
    totalCharacters += note.body.trim().length;
    totalAttachments += note.attachments.length;
    if (createdAt.year == now.year && createdAt.month == now.month) {
      thisMonthCount += 1;
    }
    if (createdAt.year == previousMonth.year &&
        createdAt.month == previousMonth.month) {
      previousMonthCount += 1;
    }
    final monthKey = createdAt.year * 12 + createdAt.month;
    monthCounts[monthKey] = (monthCounts[monthKey] ?? 0) + 1;
    final day = DateTime(createdAt.year, createdAt.month, createdAt.day);
    activeDaysSet.add(day);
    dayCounts[day] = (dayCounts[day] ?? 0) + 1;
    final weekdayStartHour = (createdAt.hour ~/ 3) * 3;
    final weekdayHourKey = '${createdAt.weekday}:$weekdayStartHour';
    weekdayHourCounts[weekdayHourKey] =
        (weekdayHourCounts[weekdayHourKey] ?? 0) + 1;
    final hourStart = (createdAt.hour ~/ 4) * 4;
    hourCounts[hourStart] = (hourCounts[hourStart] ?? 0) + 1;
    for (final attachment in note.attachments) {
      switch (attachment.type) {
        case AttachmentType.photo:
          photoAttachments += 1;
        case AttachmentType.video:
          videoAttachments += 1;
        case AttachmentType.audio:
          audioAttachments += 1;
        case AttachmentType.file:
          break;
      }
    }
  }

  final activeDays = activeDaysSet.toList()..sort((a, b) => b.compareTo(a));
  var currentStreak = 0;
  if (activeDays.isNotEmpty) {
    var cursor = activeDays.first;
    for (final day in activeDays) {
      if (_isSameCalendarDay(day, cursor)) {
        currentStreak += 1;
        cursor = cursor.subtract(const Duration(days: 1));
      }
    }
  }

  final recentDayBuckets = <_InsightBucket>[];
  final recent31DayBuckets = <_InsightBucket>[];
  for (var i = 30; i >= 0; i--) {
    final day = today.subtract(Duration(days: i));
    final bucket = _InsightBucket(
      label: '${day.month}/${day.day}',
      value: dayCounts[day] ?? 0,
    );
    recent31DayBuckets.add(bucket);
    if (i < 14) {
      recentDayBuckets.add(bucket);
    }
  }
  final monthlyBuckets = <_InsightBucket>[];
  for (var i = 5; i >= 0; i--) {
    final month = DateTime(now.year, now.month - i);
    monthlyBuckets.add(
      _InsightBucket(
        label: strings.monthBucketLabel(month.month),
        value: monthCounts[month.year * 12 + month.month] ?? 0,
      ),
    );
  }
  final weekdayHourBuckets = [
    for (var startHour = 0; startHour < 24; startHour += 3)
      for (var weekday = 1; weekday <= 7; weekday++)
        _WeekdayHourBucket(
          weekday: weekday,
          startHour: startHour,
          value: weekdayHourCounts['$weekday:$startHour'] ?? 0,
        ),
  ];
  final hourBuckets = [
    for (var hour = 0; hour < 24; hour += 4)
      _InsightBucket(
        label:
            '${hour.toString().padLeft(2, '0')}-${(hour + 3).toString().padLeft(2, '0')}',
        value: hourCounts[hour] ?? 0,
      ),
  ];
  final bestDay = recent31DayBuckets
      .where((bucket) => bucket.value > 0)
      .fold<_InsightBucket?>(
        null,
        (best, bucket) =>
            best == null || bucket.value > best.value ? bucket : best,
      );
  final bestHour = hourBuckets
      .where((bucket) => bucket.value > 0)
      .fold<_InsightBucket?>(
        null,
        (best, bucket) =>
            best == null || bucket.value > best.value ? bucket : best,
      );
  final monthlyDelta = thisMonthCount - previousMonthCount;
  final message = bestDay == null || bestDay.value == 0
      ? strings.text('home.insights.summary.empty')
      : strings.text('home.insights.summary.active', {
          'thisMonthCount': thisMonthCount,
          'bestDayLabel': bestDay.label,
        });
  final data = _InsightsData(
    summary: _InsightsSummary(
      currentStreak: currentStreak,
      thisMonthCount: thisMonthCount,
      totalCharacters: totalCharacters,
      totalAttachments: totalAttachments,
      bestDayLabel: bestDay?.label ?? '-',
      bestDayValue: bestDay?.value ?? 0,
      bestHourLabel: bestHour?.label ?? '-',
      monthlyDeltaLabel: monthlyDelta == 0
          ? '0'
          : monthlyDelta > 0
          ? '+$monthlyDelta'
          : '$monthlyDelta',
      message: message,
    ),
    monthlyBuckets: List.unmodifiable(monthlyBuckets),
    recentDayBuckets: List.unmodifiable(recentDayBuckets),
    weekdayHourBuckets: List.unmodifiable(weekdayHourBuckets),
    attachmentBuckets: [
      _InsightBucket(
        label: strings.text('home.photo'),
        value: photoAttachments,
      ),
      _InsightBucket(
        label: strings.text('home.video'),
        value: videoAttachments,
      ),
      _InsightBucket(
        label: strings.text('home.audio'),
        value: audioAttachments,
      ),
    ],
  );
  final elapsed = watch?.elapsedMicroseconds;
  if (elapsed != null && (notes.length >= 500 || elapsed >= 2000)) {
    _debugNotePerf(
      'insights build notes=${notes.length} attachments=$totalAttachments completed ${elapsed / 1000}ms',
    );
  }
  return data;
}

bool _isSameCalendarDay(DateTime left, DateTime right) {
  return left.year == right.year &&
      left.month == right.month &&
      left.day == right.day;
}
