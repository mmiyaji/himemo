// Development-only: flutter run -d chrome -t tools/v2_web_preview.dart
// Synthetic in-memory notes only; no persistence or cloud sync.
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_enrollment_store.dart';
import 'package:himemo/features/sync/data/sync_v2_generation_registration.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace_screen.dart';
import 'package:himemo/l10n/app_strings.dart';

class _Inbox implements SyncV2Inbox {
  @override
  Future<void> close() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Repository implements SyncV2NoteRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _NoCloud implements SyncV2GenerationRegistrationTransport {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

SyncV2WorkspaceNote _previewNote(NoteEntry note, int revision) =>
    SyncV2WorkspaceNote(
      note,
      SyncV2NoteSnapshot(
        versions: [
          SyncV2NoteVersion(
            change: SyncV2Change(
              id: 'preview-${note.id}-$revision',
              profileId: note.vaultId,
              noteId: note.id,
              operation: SyncV2Operation.upsert,
              parentIds: {},
              payloadDigest: 'preview',
            ),
            payloadAvailable: true,
            body: {'type': 'note', 'note': note.toJson(), 'attachments': []},
          ),
        ],
        pendingIds: {},
      ),
      [],
    );

class _PreviewController extends SyncV2WorkspaceController {
  _PreviewController()
    : super(
        inbox: _Inbox(),
        repository: _Repository(),
        store: MemorySecureKeyValueStore(),
        enrollments: SyncV2EnrollmentStore(MemorySecureKeyValueStore()),
        registrationTransport: _NoCloud(),
        registrationFactory: (_) => throw UnsupportedError('Preview only'),
        syncOperation: () => throw UnsupportedError('Preview only'),
        activate: () async {},
        deactivate: () async {},
        supported: true,
        automaticSync: false,
      ) {
    registered = true;
    selectedProfileId = 'normal';
    final now = DateTime.now();
    notes = [
      _previewNote(
        NoteEntry(
          id: 'demo-1',
          vaultId: 'normal',
          title: '今日のメモ',
          body: 'これは画面確認用のサンプルです。',
          createdAt: now,
        ),
        1,
      ),
      _previewNote(
        NoteEntry(
          id: 'demo-2',
          vaultId: 'normal',
          title: '週末の予定',
          body: '買い物と散歩',
          createdAt: now.subtract(const Duration(days: 1)),
          tags: ['予定'],
        ),
        1,
      ),
    ];
  }
  int _revision = 1;
  @override
  Future<void> initialize() async {
    loading = false;
    notifyListeners();
  }

  @override
  List<SyncV2WorkspaceProfile> get profiles => const [
    SyncV2WorkspaceProfile('normal', '通常', isNormal: true),
  ];
  @override
  Future<void> saveNote({
    SyncV2WorkspaceNote? original,
    DateTime? createdAt,
    required String title,
    required String body,
    List<NoteBlock>? blocks,
    bool? isPinned,
    List<String>? tags,
    String? selectedVersionId,
    List<SyncV2PendingAttachment> addedFiles = const [],
    List<String> removedAttachmentIds = const [],
  }) async {
    if (addedFiles.isNotEmpty || removedAttachmentIds.isNotEmpty) {
      throw UnsupportedError('Attachments are unavailable in this preview');
    }
    final now = DateTime.now();
    final base =
        original?.note ??
        NoteEntry(
          id: 'demo-${++_revision}',
          vaultId: 'normal',
          title: '',
          body: '',
          createdAt: createdAt ?? now,
        );
    final updated = _previewNote(
      base.copyWith(
        title: title,
        body: body,
        blocks: blocks ?? base.blocks,
        isPinned: isPinned ?? base.isPinned,
        tags: tags ?? base.tags,
        updatedAt: now,
      ),
      ++_revision,
    );
    notes = [updated, ...notes.where((entry) => entry.note.id != base.id)];
    notifyListeners();
  }

  @override
  Future<void> deleteNote(SyncV2WorkspaceNote note) async {
    notes = notes.where((entry) => entry.note.id != note.note.id).toList();
    notifyListeners();
  }

  @override
  Future<void> syncNow() async => throw UnsupportedError('Preview has no sync');
  @override
  void background() {}
  @override
  Future<void> resume() async {}
}

void main() {
  final controller = _PreviewController();
  runApp(
    ProviderScope(
      overrides: [syncV2WorkspaceProvider.overrideWithValue(controller)],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        locale: const Locale('ja'),
        localizationsDelegates: const [
          AppStrings.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppStrings.supportedLocales,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFC64759)),
          useMaterial3: true,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Column(
              children: [
                const Material(
                  color: Color(0xFFFFE082),
                  child: Padding(
                    padding: EdgeInsets.all(8),
                    child: Text(
                      '画面確認用デモ：データは保存・同期されません',
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
                const Expanded(child: SyncV2WorkspaceScreen(localOnly: true)),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
