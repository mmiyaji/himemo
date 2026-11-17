import 'dart:convert';

import 'package:flutter/services.dart';

import 'sync_v2_generation_registration.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_publisher.dart';
import 'sync_v2_receiver.dart';
import 'sync_v2_cloudkit_bridge_stub.dart'
    if (dart.library.js_interop) 'sync_v2_cloudkit_bridge_browser.dart'
    as browser;

typedef SyncV2CloudKitWebInvoker = Future<Object?> Function(
  String method,
  Map<String, Object?> args,
);

/// Browser bridge for the same encrypted immutable records as the iOS client.
/// CloudKit JS and web/sync_v2_cloudkit.js must be loaded by the host page.
/// A CloudKit Dashboard API token and an authenticated user are required.
class SyncV2CloudKitWebBridge {
  const SyncV2CloudKitWebBridge();

  Future<bool> configure({
    required String containerIdentifier,
    required String apiToken,
    String environment = 'production',
    bool enableWrites = false,
    String? sandboxNamespace,
  }) async {
    final String response;
    try {
      response = await browser.configureCloudKit(
        jsonEncode({
          'containerIdentifier': containerIdentifier,
          'apiToken': apiToken,
          'environment': environment,
          'enableWrites': enableWrites,
          'sandboxNamespace': ?sandboxNamespace,
        }),
      );
    } catch (_) {
      throw PlatformException(code: 'cloudkit_v2_notConfigured');
    }
    return _decode(response) == true;
  }

  Future<Object?> invoke(String method, Map<String, Object?> args) async {
    final String response;
    try {
      response = await browser.invokeCloudKit(method, jsonEncode(args));
    } catch (_) {
      throw PlatformException(code: 'cloudkit_v2_notConfigured');
    }
    return _decode(response);
  }

  /// Waits for CloudKit's Apple sign-in button to complete authentication.
  Future<String> waitForSignIn() async {
    final String response;
    try {
      response = await browser.waitForSignIn();
    } catch (_) {
      throw PlatformException(code: 'cloudkit_v2_notConfigured');
    }
    final identity = _decode(response);
    if (identity is! String || identity.isEmpty) {
      throw const FormatException('Missing iCloud account identity');
    }
    return identity;
  }

  /// Drops bridge references. CloudKit's own button signs out the Apple session.
  Future<void> disconnect() async {
    final String response;
    try {
      response = await browser.disconnect();
    } catch (_) {
      throw PlatformException(code: 'cloudkit_v2_notConfigured');
    }
    _decode(response);
  }

  /// The owning workspace must lock and clear keys when this completes.
  Future<void> waitForSignOut() async {
    final String response;
    try {
      response = await browser.waitForSignOut();
    } catch (_) {
      throw PlatformException(code: 'cloudkit_v2_notConfigured');
    }
    _decode(response);
  }

  Object? _decode(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['ok'] is! bool) {
      throw const FormatException('Invalid CloudKit response');
    }
    if (decoded['ok'] != true) {
      final code = decoded['code'];
      throw PlatformException(
        code: code is String ? code : 'cloudkit_v2_unavailable',
      );
    }
    return decoded['value'];
  }
}

/// The generation is scoped to the enrolled user. Never use a cached account
/// after an iCloud account change. Web and native change tokens are separate.
class SyncV2CloudKitWebTransport
    implements
        SyncV2ReadTransport,
        SyncV2WriteTransport,
        SyncV2GenerationRegistrationTransport {
  SyncV2CloudKitWebTransport({
    required this.accountId,
    SyncV2CloudKitWebInvoker? invoke,
  }) : _invoke = invoke ?? const SyncV2CloudKitWebBridge().invoke;

  final String accountId;
  final SyncV2CloudKitWebInvoker _invoke;
  static const _metadata = 'metadata-v1';
  static const _registration = 'active-generation-v1';

  Map<String, Object?> _scope(String generationId) => {
    'accountId': accountId,
    'generationId': generationId,
  };

  @override
  Future<String> readCurrentAccountId() async {
    final result = await _invoke('cloudKitV2AccountId', {});
    if (result is! String || result.isEmpty) {
      throw const FormatException('Missing iCloud account identity');
    }
    return result;
  }

  @override
  Future<String?> readRegistration() async {
    try {
      return (await fetchHeader(
        generationId: _metadata,
        recordId: _registration,
      )).encryptedHeader;
    } on PlatformException catch (error) {
      if (error.code == '28') throw const SyncV2CloudDataDeleted();
      if (error.code == '11' || error.code == '26') return null;
      rethrow;
    }
  }

  @override
  Future<void> prepareGeneration(String generationId) async {
    if (generationId == _metadata) {
      throw ArgumentError('Generation collides with metadata');
    }
    await _invoke('cloudKitV2Prepare', _scope(generationId));
    await _invoke('cloudKitV2Prepare', _scope(_metadata));
  }

  @override
  Future<void> publishRegistration(String encryptedProof) => publish(
    generationId: _metadata,
    publication: (
      id: _registration,
      encryptedHeader: encryptedProof,
      encryptedPayload: null,
    ),
  );

  @override
  Future<SyncV2RemoteHeader> fetchHeader({
    required String generationId,
    required String recordId,
  }) async {
    final header = await _invoke('cloudKitV2FetchHeader', {
      ..._scope(generationId),
      'id': recordId,
    });
    if (header is! String || header.isEmpty) {
      throw const FormatException('Missing CloudKit v2 header');
    }
    return (id: recordId, encryptedHeader: header);
  }

  @override
  Future<SyncV2RemotePage> fetchHeaders({
    required String generationId,
    required String? cursor,
    required int limit,
  }) async {
    try {
      final raw = await _invoke('cloudKitV2FetchHeaders', {
        ..._scope(generationId),
        'cursor': ?cursor,
        'limit': limit,
      });
      if (raw is! Map ||
          raw['cursor'] is! String ||
          (raw['cursor'] as String).isEmpty ||
          raw['hasMore'] is! bool ||
          raw['headers'] is! List ||
          raw['issues'] is! List) {
        throw const FormatException('Invalid CloudKit v2 page');
      }
      final headers = <SyncV2RemoteHeader>[];
      for (final header in raw['headers'] as List) {
        if (header is! Map ||
            header['id'] is! String ||
            header['header'] is! String ||
            (header['id'] as String).isEmpty ||
            (header['header'] as String).isEmpty) {
          throw const FormatException('Invalid CloudKit v2 header');
        }
        headers.add((
          id: header['id'] as String,
          encryptedHeader: header['header'] as String,
        ));
      }
      final issues = <({String id, String reason})>[];
      for (final issue in raw['issues'] as List) {
        if (issue is! Map ||
            issue['id'] is! String ||
            (issue['id'] as String).isEmpty ||
            !const {
              'remote_deleted',
              'record_unavailable',
              'invalid_record',
            }.contains(issue['reason'])) {
          throw const FormatException('Invalid CloudKit v2 issue');
        }
        issues.add((
          id: issue['id'] as String,
          reason: issue['reason'] as String,
        ));
      }
      if (headers.length + issues.length > limit) {
        throw const FormatException('CloudKit v2 page exceeds requested limit');
      }
      return SyncV2RemotePage(
        nextCursor: raw['cursor'] as String,
        hasMore: raw['hasMore'] as bool,
        headers: headers,
        issues: issues,
      );
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
    final encoded = await _invoke('cloudKitV2FetchPayload', {
      ..._scope(generationId),
      'id': recordId,
    });
    if (encoded is! String || encoded.isEmpty) {
      throw const FormatException('Missing CloudKit v2 payload');
    }
    return base64Decode(encoded);
  }

  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) async {
    await _invoke('cloudKitV2Publish', {
      ..._scope(generationId),
      'id': publication.id,
      'header': publication.encryptedHeader,
      if (publication.encryptedPayload case final payload?)
        'payload': base64Encode(payload),
    });
  }
}
