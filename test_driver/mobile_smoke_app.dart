import 'package:flutter_driver/driver_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:himemo/app/app_flavor.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/presentation/home_page.dart'
    show showNoteEditorSheet;
import 'package:himemo/features/home/presentation/home_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> main() async {
  enableFlutterDriverExtension();
  SharedPreferences.setMockInitialValues({
    'app.onboarding_completed': true,
    'settings.widget_quick_capture_enabled': true,
  });
  configureFlavor(AppFlavor.development);
  runApp(
    ProviderScope(
      overrides: [
        deviceAuthGatewayProvider.overrideWithValue(
          _FakeDeviceAuthGateway(authenticateResults: [true, true]),
        ),
        syncAuthGatewayProvider.overrideWithValue(_FakeSyncAuthGateway()),
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

class _FakeSyncAuthGateway implements SyncAuthGateway {
  @override
  Future<SyncAuthState> connect(SyncProvider provider) async {
    return const SyncAuthState(
      provider: SyncProvider.googleDrive,
      stage: SyncAuthStage.authenticated,
      userId: 'sim-google-user',
      displayName: 'Simulator Account',
      email: 'simulator@example.com',
      message: 'Simulator Google Drive account is connected.',
    );
  }

  @override
  Future<void> disconnect(SyncProvider provider) async {}
}

class _FakeMediaImportService implements MediaImportService {
  @override
  Future<MediaImportResult> importAttachment(MediaImportAction action) async {
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
      MediaImportAction.pickAudio => const MediaImportResult.success(
        NoteAttachment(
          type: AttachmentType.audio,
          label: 'simulator-audio.m4a',
        ),
      ),
    };
  }
}
