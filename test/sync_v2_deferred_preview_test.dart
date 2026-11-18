import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/security/data/encrypted_attachment_store.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/master_key_service.dart';
import 'package:himemo/features/security/data/secure_key_value_store.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_note_store.dart';
import 'package:himemo/features/sync/presentation/sync_v2_note_store_provider.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
// Platform fake keeps this controller test independent of native video codecs.
// ignore: depend_on_referenced_packages
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import 'support/sync_v2_workspace_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a late video preview cannot restore a shared note from trash',
    () async {
      final harness = await _Harness.create();
      final original = await harness.capture();
      await harness.controller.delete(original.id);
      harness.preview.complete(Uint8List.fromList([1, 2, 3]));
      // Drain the thumbnail callback before queueing the verification reload.
      await Future<void>.delayed(Duration.zero);
      await harness.controller.reloadFromStorage();
      final stored = (await harness.store.load(fallbackNotes: const [])).single;
      expect(stored.deletedAt, isNotNull);
      expect(stored.attachments.single.previewBytesBase64, isNull);
      expect(harness.store.previewAttempts, 0);
      expect(harness.current.deletedAt, isNotNull);
    },
  );

  test('a queued video preview preserves the latest user edit', () async {
    final harness = await _Harness.create();
    final original = await harness.capture();
    final gate = harness.rules.holdNextPreparation();
    final editing = harness.controller.upsert(
      original.copyWith(
        title: 'Latest title',
        body: 'Latest body',
        blocks: [
          const NoteBlock(type: NoteBlockType.paragraph, text: 'Latest body'),
          ...original.blocks.where(
            (block) => block.type != NoteBlockType.paragraph,
          ),
        ],
      ),
    );
    await gate.entered.future;
    harness.preview.complete(Uint8List.fromList([1, 2, 3]));
    await Future<void>.delayed(Duration.zero);
    gate.release.complete();
    await editing;
    await harness.store.previewFinished.future;
    await harness.controller.reloadFromStorage();
    final stored = (await harness.store.load(fallbackNotes: const [])).single;
    expect(stored.title, 'Latest title');
    expect(stored.body, 'Latest body');
    expect(stored.deletedAt, isNull);
    expect(
      stored.attachments.single.previewBytesBase64,
      base64Encode([1, 2, 3]),
    );
    expect(harness.current.title, 'Latest title');
    expect(harness.current.body, 'Latest body');
  });

  test('an optional preview save failure is handled without an async error', () async {
    final harness = await _Harness.create();
    final original = await harness.capture();
    harness.store.failPreview = true;
    harness.preview.complete(Uint8List.fromList([1, 2, 3]));
    await harness.store.previewFinished.future;
    await harness.controller.reloadFromStorage();
    final stored = (await harness.store.load(fallbackNotes: const [])).single;
    expect(harness.store.previewAttempts, 1);
    expect(stored.title, original.title);
    expect(stored.body, original.body);
    expect(stored.attachments.single.previewBytesBase64, isNull);
    expect(harness.current.attachments.single.previewBytesBase64, isNull);
    // flutter_test fails this test if the unawaited update leaks its exception.
    await Future<void>.delayed(Duration.zero);
  });
}

class _ControlledRules extends AutoTagRulesController {
  ({Completer<void> entered, Completer<void> release})? _next;

  @override
  List<AutoTagRule> build() => const [];

  @override
  Future<void> get restoreCompleted {
    final gate = _next;
    _next = null;
    if (gate == null) return Future<void>.value();
    gate.entered.complete();
    return gate.release.future;
  }

  ({Completer<void> entered, Completer<void> release}) holdNextPreparation() =>
      _next = (entered: Completer<void>(), release: Completer<void>());
}

class _PreviewStore extends SyncV2NoteStore {
  _PreviewStore({
    required super.repository,
    required super.session,
    required super.attachmentService,
    required super.attachmentStore,
  });

  final previewFinished = Completer<void>();
  int previewAttempts = 0;
  bool failPreview = false;

  @override
  Future<NoteEntry> saveOne(NoteEntry note) async {
    final isPreview = note.attachments.any((a) => a.previewBytesBase64 != null);
    if (isPreview) previewAttempts++;
    try {
      if (isPreview && failPreview) {
        throw const SyncV2NoteStoreLocked('preview-test');
      }
      return await super.saveOne(note);
    } finally {
      if (isPreview && !previewFinished.isCompleted) previewFinished.complete();
    }
  }
}

class _AttachmentStore extends EncryptedAttachmentStore {
  _AttachmentStore(EncryptionService encryption)
    : super(
        encryptionService: encryption,
        masterKeyService: MasterKeyService(
          secureStore: MemorySecureKeyValueStore(),
          keyFactory: encryption.generateKeyBytes,
        ),
      );

  static const draft = 'v2-draft://synthetic-shared-video';

  @override
  Future<String?> storeAttachment(
    XFile sourceFile, {
    required AttachmentType type,
  }) async => draft;

  @override
  Future<List<int>?> readAttachment(
    String storedReference, {
    required AttachmentType type,
  }) async => [7, 8, 9];

  @override
  Future<void> protectAttachmentForVault(
    String storedReference, {
    required AttachmentType type,
    required String vaultId,
  }) async {}

  @override
  Future<void> deleteAttachment(String storedReference) async {}

  @override
  Future<StoredAttachmentPayloadMetadata?> storedPayloadMetadata(
    String storedReference,
  ) async =>
      const StoredAttachmentPayloadMetadata(sizeBytes: 3, modifiedAtMillis: 1);
}

class _Harness {
  final previewRequested = Completer<void>();
  final preview = Completer<Uint8List>();
  late final ProviderContainer container;
  late final _PreviewStore store;
  late final _ControlledRules rules;
  late final File source;

  NotesController get controller =>
      container.read(notesControllerProvider.notifier);
  NoteEntry get current => container.read(notesControllerProvider).single;

  static Future<_Harness> create() async {
    SharedPreferences.setMockInitialValues({});
    configureFlavor(AppFlavor.development);
    final harness = _Harness();
    final directory = await Directory.systemTemp.createTemp(
      'himemo-preview-test-',
    );
    addTearDown(() => directory.delete(recursive: true));
    harness.source = File('${directory.path}/shared-video.mp4');
    final writer = await harness.source.open(mode: FileMode.write);
    await writer.truncate(32 * 1024 * 1024 + 1);
    await writer.close();
    final videoPlatform = VideoPlayerPlatform.instance;
    VideoPlayerPlatform.instance = _VideoPlatform();
    addTearDown(() => VideoPlayerPlatform.instance = videoPlatform);
    const thumbnails = MethodChannel('plugins.justsoft.xyz/video_thumbnail');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(thumbnails, (call) {
          expect(call.method, 'data');
          harness.previewRequested.complete();
          return harness.preview.future;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(thumbnails, null),
    );
    final workspace = await createSyncV2TestWorkspace();
    addTearDown(workspace.dispose);
    final files = _AttachmentStore(EncryptionService());
    harness.store = _PreviewStore(
      repository: workspace.repository,
      session: () => workspace.noteStoreSession,
      attachmentStore: files,
      attachmentService: SyncV2AttachmentService(
        workspace.inbox,
        workspace.repository,
      ),
    );
    harness.container = ProviderContainer(
      overrides: [
        syncV2WorkspaceProvider.overrideWithValue(workspace),
        noteStoreProvider.overrideWithValue(harness.store),
        encryptedAttachmentStoreProvider.overrideWithValue(files),
        autoTagRulesControllerProvider.overrideWith(
          () => harness.rules = _ControlledRules(),
        ),
      ],
    );
    addTearDown(harness.container.dispose);
    await harness.controller.restoreCompleted;
    harness.container.read(autoTagRulesControllerProvider);
    return harness;
  }

  Future<NoteEntry> capture() async {
    await controller.createSharedFileCapture(
      rawText: 'Shared video\nOriginal body',
      files: [
        QuickCaptureFile(
          path: source.path,
          name: 'shared-video.mp4',
          mimeType: 'video/mp4',
        ),
      ],
      shareId: 'preview',
    );
    await previewRequested.future;
    expect(current.attachments.single.previewBytesBase64, isNull);
    expect(current.attachments.single.filePath, startsWith('v2attachment:'));
    return current;
  }
}

class _VideoPlatform extends VideoPlayerPlatform {
  @override
  Future<void> init() async {}
  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async => 1;
  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => Stream.value(
    VideoEvent(
      eventType: VideoEventType.initialized,
      duration: const Duration(seconds: 1),
      size: const Size(16, 16),
    ),
  );
  @override
  Future<void> dispose(int playerId) async {}
  @override
  Future<void> setLooping(int playerId, bool looping) async {}
  @override
  Future<void> setVolume(int playerId, double volume) async {}
  @override
  Future<void> pause(int playerId) async {}
  @override
  Future<void> play(int playerId) async {}
  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}
}
