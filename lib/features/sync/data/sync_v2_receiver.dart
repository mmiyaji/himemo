import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';

import 'sync_v2_inbox.dart';

class SyncV2RemotePage {
  const SyncV2RemotePage({
    required this.nextCursor,
    required this.hasMore,
    required this.headers,
    this.issues = const [],
  });
  final String nextCursor;
  final bool hasMore;
  final List<SyncV2RemoteHeader> headers;
  final List<({String id, String reason})> issues;
}

class SyncV2CursorExpired implements Exception {
  const SyncV2CursorExpired();
}

class SyncV2PayloadUnavailable implements Exception {
  const SyncV2PayloadUnavailable();
}

abstract interface class SyncV2ReadTransport {
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  });
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  });

  Future<Uint8List> fetchPayload({
    required String generationId,
    required String recordId,
  });
}

/// Receives cloud changes without accessing profile keys.
class SyncV2Receiver {
  SyncV2Receiver(this._transport, this._inbox);

  final SyncV2ReadTransport _transport;
  final SyncV2Inbox _inbox;

  /// Reports a stale fetch when another caller advanced the cursor.
  Future<({bool staged, bool hasMore})> pullPage({
    required String generationId,
    required SecretKey syncKey,
    required int limit,
  }) async {
    if (generationId.isEmpty || limit <= 0) {
      throw ArgumentError('A generation and positive page limit are required');
    }
    final cursor = await _inbox.readCursor(generationId);
    Future<SyncV2RemotePage> fetch(String? start) => _transport.fetchHeaders(
      generationId: generationId,
      cursor: start,
      limit: limit,
    );
    final SyncV2RemotePage page;
    try {
      page = await fetch(cursor);
    } on SyncV2CursorExpired {
      if (cursor == null) rethrow;
      // Keep staged history and commit the replacement cursor atomically.
      return _stagePage(
        generationId,
        cursor,
        await fetch(null),
        syncKey,
        limit,
      );
    }
    return _stagePage(generationId, cursor, page, syncKey, limit);
  }

  Future<({bool staged, bool hasMore})> _stagePage(
    String generationId,
    String? cursor,
    SyncV2RemotePage page,
    SecretKey syncKey,
    int limit,
  ) async {
    if (page.headers.length + page.issues.length > limit) {
      throw const FormatException('Sync v2 page exceeds requested limit');
    }
    final staged = await _inbox.stagePage(
      generationId: generationId,
      expectedCursor: cursor,
      nextCursor: page.nextCursor,
      records: page.headers,
      syncKey: syncKey,
      remoteIssues: page.issues,
    );
    if (staged) await _retryHeaders(generationId, syncKey, limit);
    return (staged: staged, hasMore: staged && page.hasMore);
  }

  Future<void> _retryHeaders(
    String generationId,
    SecretKey syncKey,
    int limit,
  ) async {
    final ids = await _inbox.readRetryableHeaderIds(generationId, limit);
    for (final id in ids) {
      final SyncV2RemoteHeader header;
      try {
        header = await _transport.fetchHeader(
          generationId: generationId,
          recordId: id,
        );
      } on PlatformException catch (error) {
        if (error.code == 'cloudkit_v2_accountChanged') rethrow;
        await _inbox.recordFetchFailure(
          generationId: generationId,
          recordId: id,
          phase: 'remote',
          reason: 'record_unavailable',
          permanent: error.code == 'cloudkit_v2_invalidRecord',
        );
        continue;
      } on Exception {
        await _inbox.recordFetchFailure(
          generationId: generationId,
          recordId: id,
          phase: 'remote',
          reason: 'record_unavailable',
          permanent: false,
        );
        continue;
      }
      if (header.id != id) {
        await _inbox.recordFetchFailure(
          generationId: generationId,
          recordId: id,
          phase: 'remote',
          reason: 'record_id_mismatch',
          permanent: true,
        );
        continue;
      }
      final cursor = await _inbox.readCursor(generationId);
      if (cursor == null) return;
      await _inbox.stagePage(
        generationId: generationId,
        expectedCursor: cursor,
        nextCursor: cursor,
        records: [header],
        syncKey: syncKey,
      );
    }
  }

  Future<void> pullPayload({
    required String generationId,
    required String recordId,
    required SecretKey syncKey,
  }) async {
    final Uint8List payload;
    try {
      payload = await _transport.fetchPayload(
        generationId: generationId,
        recordId: recordId,
      );
    } on PlatformException catch (error) {
      if (error.code == 'cloudkit_v2_accountChanged') rethrow;
      if (error.code == 'cloudkit_v2_invalidRecord') {
        throw const FormatException('Invalid iCloud v2 payload');
      }
      throw const SyncV2PayloadUnavailable();
    } on FormatException {
      rethrow;
    } on Exception {
      throw const SyncV2PayloadUnavailable();
    }
    if (payload.isEmpty || payload.length > 16 * 1024 * 1024) {
      throw const FormatException('Sync v2 payload size is invalid');
    }
    await _inbox.storePayload(
      generationId: generationId,
      recordId: recordId,
      encryptedPayload: payload,
      syncKey: syncKey,
    );
  }

  /// Fetches outstanding bodies even if their header page was staged during
  /// a previous session. Failed downloads remain queued for retry.
  Future<int> pullPendingPayloads({
    required String generationId,
    required SecretKey syncKey,
    required int limit,
  }) async {
    final pending = await _inbox.readPendingPayloadIds(
      generationId: generationId,
      limit: limit,
    );
    var downloaded = 0;
    for (final id in pending) {
      try {
        await pullPayload(
          generationId: generationId,
          recordId: id,
          syncKey: syncKey,
        );
        downloaded++;
      } on FormatException {
        await _inbox.recordFetchFailure(
          generationId: generationId,
          recordId: id,
          phase: 'payload',
          reason: 'invalid_payload',
          permanent: true,
        );
      } on SyncV2PayloadUnavailable {
        await _inbox.recordFetchFailure(
          generationId: generationId,
          recordId: id,
          phase: 'payload',
          reason: 'payload_unavailable',
          permanent: false,
        );
      }
    }
    return downloaded;
  }
}
