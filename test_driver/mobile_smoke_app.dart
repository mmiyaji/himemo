import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart'
    show showNoteEditorSheet;
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test/support/sync_v2_workspace_fixture.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  SharedPreferences.setMockInitialValues({
    'app.onboarding_completed': true,
    'settings.widget_quick_capture_enabled': true,
  });
  configureFlavor(AppFlavor.development);
  final workspace = await createSyncV2TestWorkspace();
  runApp(
    ProviderScope(
      overrides: [
        deviceAuthGatewayProvider.overrideWithValue(
          _FakeDeviceAuthGateway(authenticateResults: [true, true]),
        ),
        syncV2WorkspaceProvider.overrideWithValue(workspace),
        mediaImportServiceProvider.overrideWithValue(_FakeMediaImportService()),
      ],
      child: const _MobileSmokeApp(),
    ),
  );
}

class _MobileSmokeApp extends StatelessWidget {
  const _MobileSmokeApp();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Consumer(
        builder: (context, ref, _) {
          final notes = ref.watch(visibleNotesProvider);
          return Scaffold(
            appBar: AppBar(title: const Text('Driver Smoke')),
            body: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Android simulator smoke harness',
                      key: Key('driver-smoke-ready'),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      notes.isEmpty ? 'No notes yet' : notes.first.title,
                      key: const Key('driver-smoke-latest-title'),
                    ),
                  ],
                ),
              ),
            ),
            floatingActionButton: FloatingActionButton(
              key: const Key('add-note-button'),
              onPressed: () => showNoteEditorSheet(context, ref),
              child: const Icon(Icons.add_rounded),
            ),
          );
        },
      ),
    );
  }
}

class _FakeDeviceAuthGateway implements DeviceAuthGateway {
  _FakeDeviceAuthGateway({required List<bool> authenticateResults})
    : _authenticateResults = List<bool>.from(authenticateResults);

  final List<bool> _authenticateResults;

  @override
  Future<bool> authenticate({
    required String reason,
    bool biometricOnly = false,
  }) async {
    if (_authenticateResults.isEmpty) {
      return true;
    }
    return _authenticateResults.removeAt(0);
  }

  @override
  Future<DeviceAuthState> checkAvailability() async {
    return const DeviceAuthState(
      availability: DeviceAuthAvailability.available,
      methods: ['Fingerprint', 'Device credential'],
    );
  }
}

class _FakeMediaImportService implements MediaImportService {
  @override
  Future<MediaImportResult> importAttachment(
    MediaImportAction action, {
    VoidCallback? onProcessingStarted,
  }) async {
    onProcessingStarted?.call();
    return switch (action) {
      MediaImportAction.takePhoto ||
      MediaImportAction.pickPhoto => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.photo,
          label: 'simulator-photo.jpg',
        ),
      ),
      MediaImportAction.recordVideo ||
      MediaImportAction.pickVideo => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.video,
          label: 'simulator-video.mp4',
        ),
      ),
      MediaImportAction.recordAudio ||
      MediaImportAction.pickAudio => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.audio,
          label: 'simulator-audio.m4a',
        ),
      ),
      MediaImportAction.pickFile => const MediaImportResult.success(
        NoteAttachment(type: AttachmentType.file, label: 'simulator-file.pdf'),
      ),
      MediaImportAction.addLocation => const MediaImportResult.failure(
        'Location insertion is handled by the note editor.',
      ),
    };
  }
}
