import 'package:flutter/services.dart';

import 'sync_v2_inbox.dart';
import 'sync_v2_publisher.dart';
import 'sync_v2_receiver.dart';

/// iCloud v2 transport bound to a previously enrolled account.
class SyncV2ICloudTransport
    implements SyncV2ReadTransport, SyncV2WriteTransport {
  SyncV2ICloudTransport({required this.accountId, MethodChannel? channel})
    : _channel =
          channel ?? const MethodChannel('org.ruhenheim.himemo/cloudkit');

  final String accountId;
  final MethodChannel _channel;

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async {
    final header = await _channel.invokeMethod<String>(
      'cloudKitV2FetchHeader',
      {..._scope(generationId), 'id': recordId},
    );
    if (header == null || header.isEmpty) {
      throw const FormatException('Missing iCloud v2 header');
    }
    return (id: recordId, encryptedHeader: header);
  }

  Future<String> readCurrentAccountId() async {
    final id = await _channel.invokeMethod<String>('cloudKitV2AccountId');
    if (id == null || id.isEmpty) {
      throw const FormatException('Missing iCloud account identity');
    }
    return id;
  }

  /// Called only while explicitly creating a new sync generation.
  Future<void> prepareGeneration(String generationId) =>
      _channel.invokeMethod<void>('cloudKitV2Prepare', _scope(generationId));

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    try {
      final raw = await _channel.invokeMapMethod<String, Object?>(
        'cloudKitV2FetchHeaders',
        {..._scope(generationId), 'cursor': ?cursor, 'limit': limit},
      );
      if (raw case {
        'cursor': final String nextCursor,
        'hasMore': final bool hasMore,
        'headers': final List<Object?> headers,
      }) {
        final rawIssues = raw['issues'] as List<Object?>? ?? const [];
        if (nextCursor.isEmpty || headers.length + rawIssues.length > limit) {
          throw const FormatException('Invalid iCloud v2 page');
        }
        return SyncV2RemotePage(
          nextCursor: nextCursor,
          hasMore: hasMore,
          headers: [
            for (final header in headers)
              switch (header) {
                {'id': final String id, 'header': final String encrypted}
                    when id.isNotEmpty && encrypted.isNotEmpty =>
                  (id: id, encryptedHeader: encrypted),
                _ => throw const FormatException('Invalid iCloud v2 header'),
              },
          ],
          issues: [
            for (final issue in rawIssues)
              switch (issue) {
                {'id': final String id, 'reason': final String reason}
                    when id.isNotEmpty &&
                        const {
                          'remote_deleted',
                          'record_unavailable',
                          'invalid_record',
                        }.contains(reason) =>
                  (id: id, reason: reason),
                _ => throw const FormatException(
                  'Invalid iCloud v2 record issue',
                ),
              },
          ],
        );
      }
      throw const FormatException('Invalid iCloud v2 page');
    } on PlatformException catch (error) {
      if (error.code == 'cloudkit_v2_cursor_expired') {
        throw const SyncV2CursorExpired();
      }
      rethrow;
    }
  }

  @override
  Future<Uint8List> fetchPayload({
    required String generationId,
    required String recordId,
  }) async {
    final payload = await _channel.invokeMethod<Uint8List>(
      'cloudKitV2FetchPayload',
      {..._scope(generationId), 'id': recordId},
    );
    if (payload == null || payload.isEmpty) {
      throw const FormatException('Missing iCloud v2 payload');
    }
    return payload;
  }

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) => _channel.invokeMethod<void>('cloudKitV2Publish', {
    ..._scope(generationId),
    'id': publication.id,
    'header': publication.encryptedHeader,
    'payload': ?publication.encryptedPayload,
  });

  Map<String, String> _scope(String generationId) {
    if (accountId.isEmpty || generationId.isEmpty) {
      throw ArgumentError(
        'An enrolled iCloud account and generation are required',
      );
    }
    return {'accountId': accountId, 'generationId': generationId};
  }
}
