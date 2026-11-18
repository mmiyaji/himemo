@Tags(['performance'])
@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:cryptography/cryptography.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/security/data/encryption_service.dart';
import 'package:himemo/features/security/data/sync_v2_profile_keys.dart';
import 'package:himemo/features/sync/data/sync_v2_attachment_service.dart';
import 'package:himemo/features/sync/data/sync_v2_header_codec.dart';
import 'package:himemo/features/sync/data/sync_v2_history.dart';
import 'package:himemo/features/sync/data/sync_v2_inbox.dart';
import 'package:himemo/features/sync/data/sync_v2_note_repository.dart';
import 'package:himemo/features/sync/data/sync_v2_payload_codec.dart';

// flutter test test/sync_v2_attachment_performance_test.dart --reporter expanded
// Host measurement only. No machine-specific latency thresholds.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('reports 8 MiB attachment duration and unrelated inbox-read latency', () async {
    final directory = await Directory.systemTemp.createTemp(
      'himemo-attachment-performance-',
    );
    final encryption = EncryptionService();
    final headers = SyncV2HeaderCodec(encryption);
    final payloads = _ProbedPayloads(encryption);
    // Same background-executor topology as the native app; no app is launched.
    final inbox = SyncV2Inbox(
      NativeDatabase.createInBackground(File('${directory.path}/inbox.sqlite')),
      headers,
    );
    final repository = SyncV2NoteRepository(inbox, headers, payloads);
    final attachments = SyncV2AttachmentService(inbox, repository);
    final syncKey = SecretKey(List.filled(32, 17));
    final raw = SecretKey(List.filled(32, 29));
    SyncV2UnlockedProfileKey? access;
    final content = Uint8List.fromList(
      List.generate(8 * 1024 * 1024, (index) => index % 251),
    );
    Uint8List? restored;
    try {
      final keys = SyncV2ProfileKeys(encryption);
      final record = await keys.wrap(
        generationId: 'benchmark',
        profileId: 'profile',
        keyId: 'key',
        profileKey: raw,
        passphrase: '1234',
        adminKey: syncKey,
      );
      final unlocked = await keys.unlockForAdminSession(
        generationId: 'benchmark',
        record: record,
        adminKey: syncKey,
      );
      access = unlocked;
      await inbox.readCursor('benchmark'); // Exclude opening/schema creation.
      final baseline = Stopwatch()..start();
      await inbox.readCursor('benchmark');
      baseline.stop();
      final sealStarted = Completer<void>();
      payloads.sealStarted = sealStarted;
      final write = await _measure(
        inbox: inbox,
        payloadStarted: sealStarted,
        operation: () => attachments.store(
          generationId: 'benchmark',
          syncKey: syncKey,
          profileAccess: unlocked,
          bytes: content,
          label: 'synthetic 8 MiB',
          type: 'file',
          stableId: 'eight-mib',
        ),
      );
      payloads.sealStarted = null;
      expect(write.value.chunks.length, 8);
      final openStarted = Completer<void>();
      payloads.openStarted = openStarted;
      final read = await _measure(
        inbox: inbox,
        payloadStarted: openStarted,
        operation: () => attachments.read(
          reference: write.value,
          generationId: 'benchmark',
          syncKey: syncKey,
          profileAccess: unlocked,
        ),
      );
      payloads.openStarted = null;
      restored = read.value;
      expect(restored, content);
      debugPrint(
        'SYNC_V2_ATTACHMENT_PERFORMANCE ${jsonEncode({
          'environment': {'kind': 'host_flutter_test', 'os': Platform.operatingSystem, 'dart': Platform.version, 'debug_mode': kDebugMode, 'database': 'temporary_file_background_executor'},
          'attachment_bytes': content.length,
          'chunks': write.value.chunks.length,
          'measurement': {'samples': 1, 'setup_and_correctness_checks_excluded': true, 'probe': 'same_inbox_cursor_read_started_outside_transaction_at_first_payload_codec_call', 'probe_latency_includes_event_loop_scheduling_and_transaction_queue': true},
          'idle_cursor_read_ms': baseline.elapsedMicroseconds / 1000,
          'store': write.metrics,
          'read': read.metrics,
        })}',
        wrapWidth: null,
      );
    } finally {
      payloads.sealStarted = null;
      payloads.openStarted = null;
      restored?.fillRange(0, restored.length, 0);
      content.fillRange(0, content.length, 0);
      access?.destroy();
      raw.destroy();
      syncKey.destroy();
      try {
        await inbox.close();
      } finally {
        await directory.delete(recursive: true);
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _ProbedPayloads extends SyncV2PayloadCodec {
  _ProbedPayloads(super.encryption);
  Completer<void>? sealStarted;
  Completer<void>? openStarted;

  @override
  Future<({SyncV2Change change, Uint8List encryptedPayload})> seal({
    required String generationId,
    required String changeId,
    required String profileId,
    required String noteId,
    required Set<String> parentIds,
    required Map<String, Object?> body,
    required SecretKey profileKey,
  }) {
    if (sealStarted case final signal? when !signal.isCompleted) {
      signal.complete();
    }
    return super.seal(
      generationId: generationId,
      changeId: changeId,
      profileId: profileId,
      noteId: noteId,
      parentIds: parentIds,
      body: body,
      profileKey: profileKey,
    );
  }

  @override
  Future<Map<String, Object?>> open({
    required String generationId,
    required SyncV2Change change,
    required Uint8List encryptedPayload,
    required SecretKey profileKey,
  }) {
    if (openStarted case final signal? when !signal.isCompleted) {
      signal.complete();
    }
    return super.open(
      generationId: generationId,
      change: change,
      encryptedPayload: encryptedPayload,
      profileKey: profileKey,
    );
  }
}

Future<({T value, Map<String, Object> metrics})> _measure<T>({
  required SyncV2Inbox inbox,
  required Completer<void> payloadStarted,
  required Future<T> Function() operation,
}) async {
  final clock = Stopwatch()..start();
  var previousTick = 0;
  var maximumGap = 0;
  final timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
    final now = clock.elapsedMicroseconds;
    maximumGap = math.max(maximumGap, now - previousTick);
    previousTick = now;
  });
  try {
    final result = operation();
    // Complete/error early if the operation fails before the instrumentation
    // hook. Both futures are observed so a failed operation cannot hang here.
    await Future.any<void>([
      payloadStarted.future,
      result.then<void>((_) {
        if (!payloadStarted.isCompleted) {
          throw StateError('No payload codec call');
        }
      }),
    ]);
    final probeStarted = clock.elapsedMicroseconds;
    final probeClock = Stopwatch()..start();
    // This continuation belongs to the measurement's outer Dart zone. Starting
    // the probe inside the codec callback would inherit Drift's transaction
    // context and would incorrectly measure a read within the same transaction.
    final probe = inbox.readCursor('benchmark').then((value) {
      probeClock.stop();
      return value;
    });
    late T value;
    late int operationMicros;
    // Observe and drain both futures even if either fails, so database cleanup
    // cannot leave a queued probe producing an unhandled secondary error.
    await Future.wait<void>([
      result.then((resultValue) {
        value = resultValue;
        operationMicros = clock.elapsedMicroseconds;
      }),
      probe.then((_) {}),
    ]);
    clock.stop();
    maximumGap = math.max(maximumGap, clock.elapsedMicroseconds - previousTick);
    return (
      value: value,
      metrics: {
        'operation_ms': operationMicros / 1000,
        'probe_started_ms': probeStarted / 1000,
        'concurrent_cursor_read_ms': probeClock.elapsedMicroseconds / 1000,
        'max_event_loop_gap_ms': maximumGap / 1000,
      },
    );
  } finally {
    timer.cancel();
    clock.stop();
  }
}
