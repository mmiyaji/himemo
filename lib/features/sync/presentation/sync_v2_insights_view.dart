import 'package:flutter/material.dart';

import '../../home/domain/note_entry.dart';
import '../../../l10n/app_strings.dart';
import 'sync_v2_workspace.dart';

/// Read-only activity summary for the currently selected V2 profile.
///
/// The caller supplies the workspace's decrypted projection. This widget does
/// not read legacy providers or repositories, and rechecks the profile ID
/// before using any note so accidentally mixed profile lists cannot leak into
/// the displayed aggregates.
class SyncV2InsightsView extends StatelessWidget {
  const SyncV2InsightsView({
    super.key,
    required this.profileId,
    required this.notes,
    this.onAddNote,
    this.onOpenNotes,
    this.now,
  });

  final String profileId;
  final List<SyncV2WorkspaceNote> notes;
  final VoidCallback? onAddNote;
  final VoidCallback? onOpenNotes;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final eligible = notes
        .where(
          (entry) =>
              entry.note.vaultId == profileId &&
              entry.ready &&
              !entry.isConflict &&
              !entry.isDeleted &&
              entry.note.deletedAt == null &&
              entry.note.archivedAt == null,
        )
        .map((entry) => entry.note)
        .toList(growable: false);
    final strings = context.strings;
    final data = _V2InsightData.build(eligible, now ?? DateTime.now(), strings);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
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
                  data.bestDayLabel == '-'
                      ? strings.text('home.insights.summary.empty')
                      : strings.text('home.insights.summary.active', {
                          'thisMonthCount': data.thisMonth,
                          'bestDayLabel': data.bestDayLabel,
                        }),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (eligible.isEmpty)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    strings.localized(
                      en: 'Writing activity appears here when this profile has notes.',
                      ja: 'このプロフィールにメモを作成すると、ここに記録が表示されます。',
                      zh: '此个人资料中的笔记活动会显示在这里。',
                      ko: '이 프로필에 메모가 있으면 작성 활동이 여기에 표시됩니다.',
                      es: 'La actividad aparecerá aquí cuando este perfil tenga notas.',
                      de: 'Die Aktivität dieses Profils erscheint hier, sobald Notizen vorhanden sind.',
                    ),
                  ),
                  if (onAddNote != null || onOpenNotes != null) ...[
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        if (onAddNote != null)
                          FilledButton.icon(
                            onPressed: onAddNote,
                            icon: const Icon(Icons.edit_note_rounded),
                            label: Text(strings.addNote),
                          ),
                        if (onOpenNotes != null)
                          OutlinedButton.icon(
                            onPressed: onOpenNotes,
                            icon: const Icon(Icons.notes_outlined),
                            label: Text(strings.notes),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          )
        else ...[
          _V2InsightStats(data: data),
          const SizedBox(height: 12),
          _V2InsightLine(
            title: strings.text('home.monthly.notes'),
            labels: data.monthLabels,
            values: data.monthCounts,
          ),
          const SizedBox(height: 12),
          _V2InsightBars(
            title: strings.text('home.recent.days'),
            labels: data.dayLabels,
            values: data.dayCounts,
          ),
          const SizedBox(height: 12),
          _V2InsightHeatmap(data: data),
          const SizedBox(height: 12),
          _V2InsightStats(data: data, details: true),
          const SizedBox(height: 12),
          _V2InsightBars(
            title: strings.text('home.attachments'),
            labels: [
              strings.text('home.photo'),
              strings.text('home.video'),
              strings.text('home.audio'),
            ],
            values: data.attachmentTypeCounts,
          ),
        ],
      ],
    );
  }
}

class _V2InsightStats extends StatelessWidget {
  const _V2InsightStats({required this.data, this.details = false});
  final _V2InsightData data;
  final bool details;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final items = details
        ? <(String, String)>[
            (
              strings.text('home.current.streak'),
              '${data.streak} ${strings.text('home.days')}',
            ),
            (strings.text('home.best.day'), data.bestDayLabel),
            (strings.text('home.best.hour'), data.bestHourLabel),
            (
              strings.text('home.attachments'),
              '${data.attachments} ${strings.text('home.items.2')}',
            ),
            (strings.text('home.monthly.trend'), data.monthlyDelta),
          ]
        : <(String, String)>[
            (strings.text('home.this.month'), '${data.thisMonth}'),
            (strings.text('home.characters'), '${data.characters}'),
          ];
    return Card(
      child: Wrap(
        children: [
          for (final item in items)
            SizedBox(
              width: 170,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.$1,
                      style: Theme.of(context).textTheme.labelMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.$2,
                      style: Theme.of(context).textTheme.titleLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _V2InsightBars extends StatelessWidget {
  const _V2InsightBars({
    required this.title,
    required this.labels,
    required this.values,
  });
  final String title;
  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(
      0,
      (maximum, value) => maximum > value ? maximum : value,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            SizedBox(
              height: 118,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < values.length; i++)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 2),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              '${values[i]}',
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                            const SizedBox(height: 3),
                            Expanded(
                              child: Align(
                                alignment: Alignment.bottomCenter,
                                child: FractionallySizedBox(
                                  heightFactor: maxValue == 0
                                      ? 0.03
                                      : values[i] / maxValue,
                                  widthFactor: 1,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              labels[i],
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context).textTheme.labelSmall,
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _V2InsightLine extends StatelessWidget {
  const _V2InsightLine({
    required this.title,
    required this.labels,
    required this.values,
  });
  final String title;
  final List<String> labels;
  final List<int> values;

  @override
  Widget build(BuildContext context) {
    final maximum = values.fold<int>(
      0,
      (value, item) => value > item ? value : item,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 4),
            Text(
              context.strings.text('home.notes.created.over.the.last.6.months'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            SizedBox(
              height: 150,
              width: double.infinity,
              child: CustomPaint(
                painter: _V2InsightLinePainter(
                  values: values,
                  maximum: maximum,
                  line: Theme.of(context).colorScheme.primary,
                  fill: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.12),
                  grid: Theme.of(context).dividerColor,
                ),
              ),
            ),
            Row(
              children: [
                for (var i = 0; i < labels.length; i++)
                  Expanded(
                    child: Text(
                      labels[i],
                      textAlign: i == 0
                          ? TextAlign.start
                          : i == labels.length - 1
                          ? TextAlign.end
                          : TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
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

class _V2InsightLinePainter extends CustomPainter {
  const _V2InsightLinePainter({
    required this.values,
    required this.maximum,
    required this.line,
    required this.fill,
    required this.grid,
  });
  final List<int> values;
  final int maximum;
  final Color line, fill, grid;

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = grid
      ..strokeWidth = 1;
    for (final factor in const [0.25, 0.5, 0.75, 1.0]) {
      final y = size.height - size.height * factor;
      canvas.drawLine(
        Offset.zero.translate(0, y),
        Offset(size.width, y),
        gridPaint,
      );
    }
    if (values.isEmpty) return;
    final denominator = maximum == 0 ? 1 : maximum;
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          values.length == 1
              ? size.width / 2
              : size.width * i / (values.length - 1),
          size.height - size.height * values[i] / denominator,
        ),
    ];
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fillPath = Path()..moveTo(points.first.dx, size.height);
    for (final point in points) {
      fillPath.lineTo(point.dx, point.dy);
    }
    fillPath
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(fillPath, Paint()..color = fill);
    canvas.drawPath(
      path,
      Paint()
        ..color = line
        ..strokeWidth = 2.5
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke,
    );
    for (final point in points) {
      canvas.drawCircle(point, 3.5, Paint()..color = line);
    }
  }

  @override
  bool shouldRepaint(covariant _V2InsightLinePainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.maximum != maximum ||
      oldDelegate.line != line ||
      oldDelegate.fill != fill ||
      oldDelegate.grid != grid;
}

class _V2InsightHeatmap extends StatelessWidget {
  const _V2InsightHeatmap({required this.data});
  final _V2InsightData data;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final labels = strings.weekdayShortLabels;
    final maximum = data.weekdayHourCounts.fold<int>(
      0,
      (value, item) => value > item ? value : item,
    );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              strings.text('home.weekday.and.time.rhythm'),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              strings.text('home.notes.by.weekday.and.3.hour.time.block'),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 12),
            for (var hour = 0; hour < 8; hour++)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    SizedBox(
                      width: 40,
                      child: Text(
                        '${(hour * 3).toString().padLeft(2, '0')}:00',
                        style: Theme.of(context).textTheme.labelSmall,
                      ),
                    ),
                    for (var weekday = 0; weekday < 7; weekday++)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 2),
                          child: Tooltip(
                            message:
                                '${labels[weekday]} ${(hour * 3).toString().padLeft(2, '0')}:00 · ${data.weekdayHourCounts[hour * 7 + weekday]}',
                            child: Container(
                              height: 22,
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primary
                                    .withValues(
                                      alpha: maximum == 0
                                          ? 0.04
                                          : 0.12 +
                                                0.78 *
                                                    data.weekdayHourCounts[hour *
                                                            7 +
                                                        weekday] /
                                                    maximum,
                                    ),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: Theme.of(context).dividerColor,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            Row(
              children: [
                const SizedBox(width: 40),
                for (var weekday = 0; weekday < 7; weekday++)
                  Expanded(
                    child: Text(
                      labels[weekday],
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.labelSmall,
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

class _V2InsightData {
  const _V2InsightData({
    required this.thisMonth,
    required this.characters,
    required this.attachments,
    required this.streak,
    required this.bestDayLabel,
    required this.bestHourLabel,
    required this.monthlyDelta,
    required this.monthLabels,
    required this.monthCounts,
    required this.dayLabels,
    required this.dayCounts,
    required this.weekdayHourCounts,
    required this.attachmentTypeCounts,
  });

  final int thisMonth, characters, attachments, streak;
  final String bestDayLabel, bestHourLabel, monthlyDelta;
  final List<String> monthLabels, dayLabels;
  final List<int> monthCounts, dayCounts;
  final List<int> weekdayHourCounts, attachmentTypeCounts;

  factory _V2InsightData.build(
    List<NoteEntry> notes,
    DateTime current,
    AppStrings strings,
  ) {
    final localNow = current.toLocal();
    final today = DateTime(localNow.year, localNow.month, localNow.day);
    final monthCountsByKey = <int, int>{};
    final dayCountsByKey = <DateTime, int>{};
    final hourCounts = <int, int>{};
    final weekdayHourCounts = <String, int>{};
    final attachmentTypeCounts = List<int>.filled(3, 0);
    var characters = 0;
    var attachments = 0;
    for (final note in notes) {
      final created = note.createdAt.toLocal();
      characters += note.body.trim().length;
      attachments += note.attachments.length;
      final monthKey = created.year * 12 + created.month;
      monthCountsByKey[monthKey] = (monthCountsByKey[monthKey] ?? 0) + 1;
      final day = DateTime(created.year, created.month, created.day);
      dayCountsByKey[day] = (dayCountsByKey[day] ?? 0) + 1;
      final hourStart = (created.hour ~/ 4) * 4;
      hourCounts[hourStart] = (hourCounts[hourStart] ?? 0) + 1;
      final weekdayHourStart = (created.hour ~/ 3) * 3;
      final weekdayHourKey = '${created.weekday}:$weekdayHourStart';
      weekdayHourCounts[weekdayHourKey] =
          (weekdayHourCounts[weekdayHourKey] ?? 0) + 1;
      for (final attachment in note.attachments) {
        switch (attachment.type) {
          case AttachmentType.photo:
            attachmentTypeCounts[0]++;
          case AttachmentType.video:
            attachmentTypeCounts[1]++;
          case AttachmentType.audio:
            attachmentTypeCounts[2]++;
          case AttachmentType.file:
            break;
        }
      }
    }
    final monthStart = DateTime(localNow.year, localNow.month);
    final previousMonth = DateTime(localNow.year, localNow.month - 1);
    final thisMonth =
        monthCountsByKey[monthStart.year * 12 + monthStart.month] ?? 0;
    final previous =
        monthCountsByKey[previousMonth.year * 12 + previousMonth.month] ?? 0;
    final monthLabels = <String>[];
    final monthValues = <int>[];
    for (var offset = 5; offset >= 0; offset--) {
      final month = DateTime(localNow.year, localNow.month - offset);
      monthLabels.add(strings.monthBucketLabel(month.month));
      monthValues.add(monthCountsByKey[month.year * 12 + month.month] ?? 0);
    }
    final dayLabels = <String>[];
    final dayValues = <int>[];
    for (var offset = 13; offset >= 0; offset--) {
      final day = today.subtract(Duration(days: offset));
      dayLabels.add('${day.month}/${day.day}');
      dayValues.add(dayCountsByKey[day] ?? 0);
    }
    final activeDays = dayCountsByKey.keys.toList()
      ..sort((a, b) => b.compareTo(a));
    var streak = 0;
    if (activeDays.isNotEmpty) {
      var cursor = activeDays.first;
      for (final day in activeDays) {
        if (day == cursor) {
          streak++;
          cursor = cursor.subtract(const Duration(days: 1));
        }
      }
    }
    MapEntry<DateTime, int>? bestDayEntry;
    // V1 visits the last 31 days oldest-first and preserves the first tie.
    for (var offset = 30; offset >= 0; offset--) {
      final day = today.subtract(Duration(days: offset));
      final value = dayCountsByKey[day] ?? 0;
      if (value > 0 && (bestDayEntry == null || value > bestDayEntry.value)) {
        bestDayEntry = MapEntry(day, value);
      }
    }
    MapEntry<int, int>? bestHour;
    // V1 scans 4-hour buckets in ascending order, preserving the earliest tie.
    for (var hour = 0; hour < 24; hour += 4) {
      final value = hourCounts[hour] ?? 0;
      if (value > 0 && (bestHour == null || value > bestHour.value)) {
        bestHour = MapEntry(hour, value);
      }
    }
    return _V2InsightData(
      thisMonth: thisMonth,
      characters: characters,
      attachments: attachments,
      streak: streak,
      bestDayLabel: bestDayEntry == null
          ? '-'
          : '${bestDayEntry.key.month}/${bestDayEntry.key.day}',
      bestHourLabel: bestHour == null
          ? '-'
          : '${bestHour.key.toString().padLeft(2, '0')}-${(bestHour.key + 3).toString().padLeft(2, '0')}',
      monthlyDelta: thisMonth - previous == 0
          ? '0'
          : thisMonth > previous
          ? '+${thisMonth - previous}'
          : '${thisMonth - previous}',
      monthLabels: monthLabels,
      monthCounts: monthValues,
      dayLabels: dayLabels,
      dayCounts: dayValues,
      weekdayHourCounts: [
        for (var hour = 0; hour < 24; hour += 3)
          for (var weekday = 1; weekday <= 7; weekday++)
            weekdayHourCounts['$weekday:$hour'] ?? 0,
      ],
      attachmentTypeCounts: attachmentTypeCounts,
    );
  }
}
