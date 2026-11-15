import 'package:flutter/services.dart';

import 'sync_v2_inbox.dart';

abstract interface class SyncV2WriteTransport {
  /// Acknowledges only after committing the immutable record. Replaying the
  /// same bytes is successful; a different record with the same ID is rejected.
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  });
}

class SyncV2Publisher {
  SyncV2Publisher(this._transport, this._inbox);

  final SyncV2WriteTransport _transport;
  final SyncV2Inbox _inbox;

  /// Ambiguous and global failures leave ciphertext queued. Record-specific
  /// failures retain local ciphertext in quarantine for explicit retry.
  Future<int> publishPage({
    required String generationId,
    required int limit,
    bool stopOnQuarantine = false,
  }) async {
    if (generationId.isEmpty || limit <= 0) {
      throw ArgumentError('A generation and positive page limit are required');
    }
    var sent = 0;
    if (stopOnQuarantine &&
        (await _inbox.readFailures(generationId))
            .any((failure) => failure.phase == 'publication')) {
      return 0;
    }
    var processed = 0;
    while (processed < limit) {
      final batch = await _inbox.readOutbox(
        generationId: generationId,
        limit: 1,
      );
      if (batch.isEmpty) break;
      final publication = batch.single;
      processed++;
      try {
        await _transport.publish(
          generationId: generationId,
          publication: publication,
        );
        await _inbox.acknowledgePublication(
          generationId: generationId,
          publication: publication,
        );
        sent++;
      } on PlatformException catch (error) {
        final reason = _permanentPublicationFailure(error.code);
        if (reason == null) rethrow;
        await _inbox.quarantinePublication(
          generationId: generationId,
          publication: publication,
          reason: reason,
        );
        // A workspace may queue attachment chunks before a referencing note.
        // Never release that note while a required earlier upload is broken.
        if (stopOnQuarantine) break;
      }
    }
    return sent;
  }

  String? _permanentPublicationFailure(String code) {
    // Native CKError codes arrive as bare numeric strings. Only quarantine
    // errors tied to this record's contents or asset; account, service, quota,
    // and request-level limits must stop the page with the queue intact.
    const nativeRecordFailures = {
      '12': 'invalidArguments',
      '16': 'assetFileNotFound',
      '17': 'assetFileModified',
    };
    final nativeReason = nativeRecordFailures[code];
    if (nativeReason != null) return nativeReason;
    const permanent = {'invalidRequest', 'invalidRecord', 'recordCollision'};
    const prefix = 'cloudkit_v2_';
    if (!code.startsWith(prefix)) return null;
    final reason = code.substring(prefix.length);
    return permanent.contains(reason) ? reason : null;
  }
}
