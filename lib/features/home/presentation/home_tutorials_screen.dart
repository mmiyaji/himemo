part of 'home_page.dart';

class TutorialsScreen extends ConsumerWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final completed = ref.watch(appTutorialCompletionControllerProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.localized(
            en: 'Tutorials',
            ja: 'チュートリアル',
            zh: 'Tutorials',
            ko: 'Tutorials',
            es: 'Tutoriales',
            de: 'Tutorials',
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final level in AppTutorialCourseLevel.values) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 8, 4, 10),
                child: Text(
                  _tutorialLevelTitle(strings, level),
                  style: theme.textTheme.titleSmall?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              for (final course in AppTutorialCourse.values.where(
                (course) => _tutorialCourseLevel(course) == level,
              )) ...[
                _TutorialCourseCard(
                  course: course,
                  completed: completed.contains(course),
                  onStart: () => _startTutorialCourse(context, ref, course),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _TutorialCourseCard extends StatelessWidget {
  const _TutorialCourseCard({
    required this.course,
    required this.completed,
    required this.onStart,
  });

  final AppTutorialCourse course;
  final bool completed;
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) {
    final strings = context.strings;
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              backgroundColor: completed
                  ? theme.colorScheme.secondaryContainer
                  : theme.colorScheme.primaryContainer,
              foregroundColor: completed
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onPrimaryContainer,
              child: Icon(
                completed ? Icons.check_rounded : _tutorialCourseIcon(course),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _tutorialCourseTitle(strings, course),
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (completed)
                        Text(
                          strings.localized(
                            en: 'Done',
                            ja: '完了',
                            zh: 'Done',
                            ko: 'Done',
                            es: 'Listo',
                            de: 'Fertig',
                          ),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    _tutorialCourseDescription(strings, course),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: FilledButton.icon(
                      onPressed: onStart,
                      icon: Icon(
                        completed
                            ? Icons.replay_rounded
                            : Icons.play_arrow_rounded,
                      ),
                      label: Text(
                        completed
                            ? strings.localized(
                                en: 'Replay',
                                ja: 'もう一度',
                                zh: 'Replay',
                                ko: 'Replay',
                                es: 'Repetir',
                                de: 'Erneut',
                              )
                            : strings.localized(
                                en: 'Start',
                                ja: '開始',
                                zh: 'Start',
                                ko: 'Start',
                                es: 'Iniciar',
                                de: 'Starten',
                              ),
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

String _tutorialLevelTitle(AppStrings strings, AppTutorialCourseLevel level) {
  return switch (level) {
    AppTutorialCourseLevel.beginner => strings.localized(
      en: 'Beginner',
      ja: '初級',
      zh: 'Beginner',
      ko: 'Beginner',
      es: 'Inicial',
      de: 'Grundlagen',
    ),
    AppTutorialCourseLevel.intermediate => strings.localized(
      en: 'Intermediate',
      ja: '中級',
      zh: 'Intermediate',
      ko: 'Intermediate',
      es: 'Intermedio',
      de: 'Mittelstufe',
    ),
    AppTutorialCourseLevel.advanced => strings.localized(
      en: 'Advanced',
      ja: '上級',
      zh: 'Advanced',
      ko: 'Advanced',
      es: 'Avanzado',
      de: 'Fortgeschritten',
    ),
  };
}

AppTutorialCourseLevel _tutorialCourseLevel(AppTutorialCourse course) {
  return switch (course) {
    AppTutorialCourse.basics ||
    AppTutorialCourse.mainScreen ||
    AppTutorialCourse.writing ||
    AppTutorialCourse.find => AppTutorialCourseLevel.beginner,
    AppTutorialCourse.review ||
    AppTutorialCourse.attachments ||
    AppTutorialCourse.privateMemo ||
    AppTutorialCourse.privacy ||
    AppTutorialCourse.sync => AppTutorialCourseLevel.intermediate,
    AppTutorialCourse.syncTroubleshooting ||
    AppTutorialCourse.trashRecovery ||
    AppTutorialCourse.organize ||
    AppTutorialCourse.maintenance => AppTutorialCourseLevel.advanced,
  };
}

IconData _tutorialCourseIcon(AppTutorialCourse course) {
  return switch (course) {
    AppTutorialCourse.basics => Icons.tips_and_updates_outlined,
    AppTutorialCourse.mainScreen => Icons.dashboard_customize_outlined,
    AppTutorialCourse.writing => Icons.edit_note_rounded,
    AppTutorialCourse.find => Icons.search_rounded,
    AppTutorialCourse.attachments => Icons.attach_file_rounded,
    AppTutorialCourse.privateMemo => Icons.lock_person_outlined,
    AppTutorialCourse.review => Icons.event_note_outlined,
    AppTutorialCourse.privacy => Icons.lock_person_outlined,
    AppTutorialCourse.sync => Icons.cloud_sync_outlined,
    AppTutorialCourse.syncTroubleshooting => Icons.manage_search_rounded,
    AppTutorialCourse.trashRecovery => Icons.restore_from_trash_outlined,
    AppTutorialCourse.organize => Icons.sell_outlined,
    AppTutorialCourse.maintenance => Icons.admin_panel_settings_outlined,
  };
}

String _tutorialCourseTitle(AppStrings strings, AppTutorialCourse course) {
  return switch (course) {
    AppTutorialCourse.basics => strings.localized(
      en: 'First steps',
      ja: 'はじめての操作',
    ),
    AppTutorialCourse.mainScreen => strings.localized(
      en: 'Main screen guide',
      ja: 'メイン画面の見方',
    ),
    AppTutorialCourse.writing => strings.localized(
      en: 'Writing memos',
      ja: 'メモを書く',
    ),
    AppTutorialCourse.find => strings.localized(
      en: 'Search and filter',
      ja: '検索と絞り込み',
    ),
    AppTutorialCourse.attachments => strings.localized(
      en: 'Using attachments',
      ja: '添付ファイル',
    ),
    AppTutorialCourse.privateMemo => strings.localized(
      en: 'Private memo creation',
      ja: 'プライベートメモ作成',
    ),
    AppTutorialCourse.review => strings.localized(
      en: 'Review by date',
      ja: '日付で見返す',
    ),
    AppTutorialCourse.privacy => strings.localized(
      en: 'Privacy and protection',
      ja: 'プライバシーと保護',
    ),
    AppTutorialCourse.sync => strings.localized(
      en: 'Sync and backup',
      ja: '同期とバックアップ',
    ),
    AppTutorialCourse.syncTroubleshooting => strings.localized(
      en: 'Sync troubleshooting',
      ja: '同期トラブル確認',
    ),
    AppTutorialCourse.trashRecovery => strings.localized(
      en: 'Trash and restore',
      ja: 'ゴミ箱と復元',
    ),
    AppTutorialCourse.organize => strings.localized(
      en: 'Organizing notes',
      ja: 'メモを整理する',
    ),
    AppTutorialCourse.maintenance => strings.localized(
      en: 'Maintenance workflow',
      ja: 'メンテナンス',
    ),
  };
}

String _tutorialCourseDescription(
  AppStrings strings,
  AppTutorialCourse course,
) {
  return switch (course) {
    AppTutorialCourse.basics => strings.localized(
      en: 'Move through notes, the header actions, sync status, and navigation.',
      ja: 'ノート画面、ヘッダー操作、同期状態、画面移動を順に確認します。',
    ),
    AppTutorialCourse.mainScreen => strings.localized(
      en: 'Learn the search box, filters, memo list, header actions, sync indicator, and navigation on the main screen.',
      ja: 'メイン画面の検索、フィルタ、メモ一覧、ヘッダー操作、同期インジケーター、ナビゲーションを確認します。',
    ),
    AppTutorialCourse.writing => strings.localized(
      en: 'Create memos, add tags, then jump to the calendar for review.',
      ja: 'メモ作成、タグ、カレンダーでの見返しまで確認します。',
    ),
    AppTutorialCourse.find => strings.localized(
      en: 'Use the main screen search box, filters, and tags to find notes.',
      ja: 'メイン画面の検索欄、フィルタ、タグでメモを探す流れを確認します。',
    ),
    AppTutorialCourse.attachments => strings.localized(
      en: 'Start a memo and learn where photos, videos, audio, and files are attached.',
      ja: 'メモ作成から写真、動画、音声、ファイルを添付する入口を確認します。',
    ),
    AppTutorialCourse.privateMemo => strings.localized(
      en: 'Unlock a profile, create a memo, and check private save behavior.',
      ja: 'プロファイル解除、メモ作成、プライベート保存の考え方を確認します。',
    ),
    AppTutorialCourse.review => strings.localized(
      en: 'Use calendar, tags, and navigation together to find past memos.',
      ja: 'カレンダー、タグ、画面移動を組み合わせて過去のメモを探します。',
    ),
    AppTutorialCourse.privacy => strings.localized(
      en: 'Check private profiles, app protection, and the settings area.',
      ja: 'プライベートプロファイル、アプリ保護、設定画面を確認します。',
    ),
    AppTutorialCourse.sync => strings.localized(
      en: 'Follow the sync indicator, then open the sync settings area.',
      ja: '同期インジケーターから設定画面の同期項目まで確認します。',
    ),
    AppTutorialCourse.syncTroubleshooting => strings.localized(
      en: 'Check progress from the header, then move to settings for history and conflicts.',
      ja: 'ヘッダーの進捗確認から、設定の履歴や競合確認へ進みます。',
    ),
    AppTutorialCourse.trashRecovery => strings.localized(
      en: 'Open Trash from navigation and learn when to restore or permanently delete.',
      ja: 'ナビゲーションからゴミ箱を開き、復元と完全削除の使い分けを確認します。',
    ),
    AppTutorialCourse.organize => strings.localized(
      en: 'Walk through tags, trash, calendar, and note cleanup habits.',
      ja: 'タグ、ゴミ箱、カレンダーを移動しながら整理の流れを確認します。',
    ),
    AppTutorialCourse.maintenance => strings.localized(
      en: 'Review settings, sync status, and trash as a maintenance routine.',
      ja: '設定、同期状態、ゴミ箱をメンテナンスの流れとして確認します。',
    ),
  };
}
