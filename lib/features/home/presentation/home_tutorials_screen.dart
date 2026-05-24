part of 'home_page.dart';

class TutorialsScreen extends ConsumerWidget {
  const TutorialsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final strings = context.strings;
    final theme = Theme.of(context);
    final courses = AppTutorialCourse.values;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          strings.localized(
            en: 'Tutorials',
            ja: 'チュートリアル',
            zh: '教程',
            ko: '튜토리얼',
            es: 'Tutoriales',
            de: 'Tutorials',
          ),
        ),
      ),
      body: SafeArea(
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: courses.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final course = courses[index];
            return Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CircleAvatar(
                      backgroundColor: theme.colorScheme.primaryContainer,
                      foregroundColor: theme.colorScheme.onPrimaryContainer,
                      child: Icon(_tutorialCourseIcon(course)),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _tutorialCourseTitle(strings, course),
                            style: theme.textTheme.titleMedium,
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
                              onPressed: () {
                                ref
                                    .read(
                                      appTutorialControllerProvider.notifier,
                                    )
                                    .start(course);
                              },
                              icon: const Icon(Icons.play_arrow_rounded),
                              label: Text(
                                strings.localized(
                                  en: 'Start',
                                  ja: '開始',
                                  zh: '开始',
                                  ko: '시작',
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
          },
        ),
      ),
    );
  }
}

IconData _tutorialCourseIcon(AppTutorialCourse course) {
  return switch (course) {
    AppTutorialCourse.basics => Icons.tips_and_updates_outlined,
    AppTutorialCourse.writing => Icons.edit_note_rounded,
    AppTutorialCourse.privacy => Icons.lock_person_outlined,
    AppTutorialCourse.sync => Icons.cloud_sync_outlined,
    AppTutorialCourse.organize => Icons.sell_outlined,
  };
}

String _tutorialCourseTitle(AppStrings strings, AppTutorialCourse course) {
  return switch (course) {
    AppTutorialCourse.basics => strings.localized(
      en: 'First steps',
      ja: '初歩ガイド',
      zh: '入门指南',
      ko: '첫 단계',
      es: 'Primeros pasos',
      de: 'Erste Schritte',
    ),
    AppTutorialCourse.writing => strings.localized(
      en: 'Writing memos',
      ja: 'メモを書く',
      zh: '撰写笔记',
      ko: '메모 작성',
      es: 'Escribir memos',
      de: 'Notizen schreiben',
    ),
    AppTutorialCourse.privacy => strings.localized(
      en: 'Privacy and protection',
      ja: 'プライバシーと保護',
      zh: '隐私与保护',
      ko: '개인정보와 보호',
      es: 'Privacidad y proteccion',
      de: 'Privatsphaere und Schutz',
    ),
    AppTutorialCourse.sync => strings.localized(
      en: 'Sync and backup',
      ja: '同期とバックアップ',
      zh: '同步和备份',
      ko: '동기화와 백업',
      es: 'Sincronizacion y copia',
      de: 'Synchronisierung und Backup',
    ),
    AppTutorialCourse.organize => strings.localized(
      en: 'Organizing notes',
      ja: 'メモを整理する',
      zh: '整理笔记',
      ko: '메모 정리',
      es: 'Organizar notas',
      de: 'Notizen organisieren',
    ),
  };
}

String _tutorialCourseDescription(
  AppStrings strings,
  AppTutorialCourse course,
) {
  return switch (course) {
    AppTutorialCourse.basics => strings.localized(
      en: 'Learn the header buttons, memo creation, sync status, and navigation.',
      ja: 'ヘッダー、メモ作成、同期状況、画面移動の基本を確認します。',
      zh: '了解顶部按钮、创建笔记、同步状态和导航。',
      ko: '헤더 버튼, 메모 작성, 동기화 상태, 화면 이동의 기본을 확인합니다.',
      es: 'Aprende botones, creacion de memos, estado de sincronizacion y navegacion.',
      de: 'Lerne Kopfbereich, Notizerstellung, Synchronisierung und Navigation.',
    ),
    AppTutorialCourse.writing => strings.localized(
      en: 'Focus on creating memos, adding tags, and reviewing entries by date.',
      ja: 'メモ作成、タグ付け、日付からの見返しに絞って確認します。',
      zh: '重点了解创建笔记、添加标签和按日期回顾。',
      ko: '메모 작성, 태그 추가, 날짜별 확인을 중심으로 봅니다.',
      es: 'Se centra en crear memos, etiquetar y revisarlos por fecha.',
      de: 'Fokus auf Erstellen, Tags und Rueckblick nach Datum.',
    ),
    AppTutorialCourse.privacy => strings.localized(
      en: 'See where private profiles, app protection, and related settings live.',
      ja: 'プライベートプロファイル、アプリ保護、関連設定の場所を確認します。',
      zh: '查看私密配置、应用保护和相关设置的位置。',
      ko: '비공개 프로필, 앱 보호, 관련 설정 위치를 확인합니다.',
      es: 'Muestra perfiles privados, proteccion de app y ajustes relacionados.',
      de: 'Zeigt private Profile, App-Schutz und zugehoerige Einstellungen.',
    ),
    AppTutorialCourse.sync => strings.localized(
      en: 'Learn the sync indicator and where to configure cloud sync and backups.',
      ja: '同期インジケーターとクラウド同期・バックアップ設定の場所を確認します。',
      zh: '了解同步指示器以及云同步和备份设置的位置。',
      ko: '동기화 표시기와 클라우드 동기화, 백업 설정 위치를 확인합니다.',
      es: 'Aprende el indicador de sincronizacion y donde configurar copias.',
      de: 'Lerne die Sync-Anzeige und Backup-Einstellungen kennen.',
    ),
    AppTutorialCourse.organize => strings.localized(
      en: 'Walk through tags, trash, calendar, and insights for keeping notes tidy.',
      ja: 'タグ、ゴミ箱、カレンダー、記録でメモを整理する流れを確認します。',
      zh: '查看标签、废纸篓、日历和统计如何帮助整理笔记。',
      ko: '태그, 휴지통, 캘린더, 기록으로 메모를 정리하는 흐름을 봅니다.',
      es: 'Recorre etiquetas, papelera, calendario y registros para ordenar notas.',
      de: 'Fuehrt durch Tags, Papierkorb, Kalender und Auswertung.',
    ),
  };
}
