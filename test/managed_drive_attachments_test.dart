import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:http/http.dart' as http;
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/remote_attachment_maintenance.dart';

void main() {
  group('InMemoryGoogleDriveSyncTransport managed attachments', () {
    test(
      'legacy attachments remain unmanaged instead of being copied',
      () async {
        final transport = InMemoryGoogleDriveSyncTransport(
          uploadDelay: Duration.zero,
        );
        await transport.uploadAttachmentObject(
          contentHash: 'legacy',
          encodedPayload: 'cipher',
          type: 'file',
          label: 'x',
          sizeBytes: 6,
        );
        await transport.pinAttachmentObject(
          contentHash: 'legacy',
          uploadId: 'upload',
          type: 'file',
          label: 'x',
          sizeBytes: 6,
        );
        expect(await transport.listManagedAttachmentObjects(), isEmpty);
        expect(await transport.downloadAttachmentObject('legacy'), 'cipher');
      },
    );

    test(
      'reservations are durable, bounded, and released only by upload ID',
      () async {
        final t = InMemoryGoogleDriveSyncTransport(uploadDelay: Duration.zero);
        final id = await t.pinAttachmentObject(
          contentHash: 'h',
          uploadId: 'u1',
          encodedPayload: 'cipher',
          type: 'image',
          label: 'x',
          sizeBytes: 6,
        );
        expect(await t.downloadAttachmentObject('h'), 'cipher');
        expect((await t.listAttachmentObjectContentHashes()), contains('h'));
        expect(
          await t.pinAttachmentObject(
            contentHash: 'h',
            uploadId: 'u2',
            type: 'image',
            label: 'x',
            sizeBytes: 6,
          ),
          id,
        );
        expect(
          await t.pinAttachmentObject(
            contentHash: 'h',
            uploadId: 'u3',
            type: 'image',
            label: 'x',
            sizeBytes: 6,
          ),
          id,
        );
        final fourth = await t.pinAttachmentObject(
          contentHash: 'h',
          uploadId: 'u4',
          type: 'image',
          label: 'x',
          sizeBytes: 6,
        );
        expect(fourth, isNot(id));
        await t.releaseAttachmentObject(
          recordId: id,
          uploadId: 'u1',
          publishedBundleId: 'bundle',
        );
        final snapshot = (await t.listManagedAttachmentObjects()).singleWhere(
          (o) => o.id == id,
        );
        expect(snapshot.uploadIds, {'u2', 'u3'});
        expect(snapshot.lastPublishedBundleId, 'bundle');
      },
    );

    test('claim compares revision and refuses held objects', () async {
      final t = InMemoryGoogleDriveSyncTransport(uploadDelay: Duration.zero);
      final id = await t.pinAttachmentObject(
        contentHash: 'h',
        uploadId: 'u',
        encodedPayload: 'p',
        type: 'x',
        label: 'x',
        sizeBytes: 1,
      );
      final held = (await t.listManagedAttachmentObjects()).single;
      expect(await t.claimAndDeleteAttachmentObject(held), isFalse);
      await t.releaseAttachmentObject(
        recordId: id,
        uploadId: 'u',
        publishedBundleId: 'b',
      );
      final stale = held;
      final current = (await t.listManagedAttachmentObjects()).single;
      expect(await t.claimAndDeleteAttachmentObject(stale), isFalse);
      expect(await t.claimAndDeleteAttachmentObject(current), isTrue);
      expect(await t.listManagedAttachmentObjects(), isEmpty);
      expect(await t.downloadAttachmentObject('h'), isNull);
    });

    test('pin after GC claim creates a new immutable ID', () async {
      final t = InMemoryGoogleDriveSyncTransport(uploadDelay: Duration.zero);
      final claimedId = await t.pinAttachmentObject(
        contentHash: 'h',
        uploadId: 'old',
        encodedPayload: 'cipher',
        type: 'image',
        label: 'x',
        sizeBytes: 6,
      );
      await t.releaseAttachmentObject(
        recordId: claimedId,
        uploadId: 'old',
        publishedBundleId: 'b',
      );
      final snapshot = (await t.listManagedAttachmentObjects()).single;
      expect(await t.claimAndDeleteAttachmentObject(snapshot), isTrue);
      final nextId = await t.pinAttachmentObject(
        contentHash: 'h',
        uploadId: 'new',
        encodedPayload: 'cipher',
        type: 'image',
        label: 'x',
        sizeBytes: 6,
      );
      expect(nextId, isNot(claimedId));
      expect((await t.listManagedAttachmentObjects()).single.uploadIds, {
        'new',
      });
    });
  });

  group('Google Drive managed metadata validation', () {
    test(
      'invalid metadata is excluded, cannot be released, and cannot be claimed',
      () async {
        final client = _FakeDriveHttpClient({
          'kind': 'attachment-managed-v1',
          'contentHash': 'h',
          'holds': '[]',
          'deleting': 'false',
          // Missing protocol is deliberately malformed.
        });
        final transport = GoogleApisGoogleDriveSyncTransport(
          driveApiProvider: () async => drive.DriveApi(client),
          maintenanceClient: client,
        );
        expect(await transport.listManagedAttachmentObjects(), isEmpty);
        await expectLater(
          transport.releaseAttachmentObject(
            recordId: 'bad',
            uploadId: 'u',
            publishedBundleId: 'b',
          ),
          throwsA(isA<Exception>()),
        );
        expect(
          await transport.claimAndDeleteAttachmentObject(
            const ManagedAttachmentObject(
              id: 'bad',
              contentHash: 'h',
              revision: '"rev1"',
              modifiedAt: null,
              uploadIds: {},
            ),
          ),
          isFalse,
        );
        final id = await transport.pinAttachmentObject(
          contentHash: 'h',
          uploadId: 'u',
          encodedPayload: 'cipher',
          type: 'image',
          label: 'x',
          sizeBytes: 6,
        );
        expect(id, 'fresh');
        expect(
          client.calls.where(
            (r) => r.method == 'PATCH' || r.method == 'DELETE',
          ),
          isEmpty,
        );
        expect(
          client.calls.any(
            (r) => r.method == 'POST' && r.url.path.endsWith('/drive/v3/files'),
          ),
          isTrue,
        );
      },
    );
  });

  group('Google Drive managed CAS', () {
    test(
      'legacy pin reuses the existing file without transfer or reservation',
      () async {
        final server = _StatefulManagedDriveServer()
          ..legacyFiles['hash'] = 'old-id';
        final transport = _statefulTransport(server);
        final id = await transport.pinAttachmentObject(
          contentHash: 'hash',
          uploadId: 'mine',
          encodedPayload: 'new-cipher',
          type: 'file',
          label: 'legacy',
          sizeBytes: 100,
        );
        expect(id, 'old-id');
        await transport.releaseAttachmentObject(
          recordId: id,
          uploadId: 'mine',
          publishedBundleId: 'bundle',
        );
        expect(server.calls, hasLength(1));
        expect(server.calls.single.method, 'GET');
        expect(server.calls.single.url.path, '/drive/v3/files');
        expect(server.records, isEmpty);
      },
    );

    test(
      'inventory captures etags in paginated lists without per-file GET',
      () async {
        final server = _StatefulManagedDriveServer()..inventoryPageSize = 2;
        for (var i = 0; i < 5; i++) {
          server.addRecord('id-$i', 'hash-$i', {});
        }
        final inventory = await _statefulTransport(server)
            .listManagedAttachmentObjects();
        expect(inventory, hasLength(5));
        expect(inventory.every((item) => item.revision == '"rev1"'), isTrue);
        expect(server.calls, hasLength(3));
        expect(
          server.calls.every(
            (request) => request.url.path == '/drive/v2/files',
          ),
          isTrue,
        );
        expect(
          server.calls.first.url.queryParameters['fields'],
          contains('etag'),
        );
      },
    );

    test('inventory discovery hints avoid per-hash search but still refresh CAS metadata', () async {
      final server = _StatefulManagedDriveServer()
        ..addRecord('copy-id', 'hash', {});
      final transport = _statefulTransport(server);
      await transport.listManagedAttachmentObjects();
      server.externalAddHolder('copy-id', 'other');
      await transport.pinAttachmentObject(
        contentHash: 'hash',
        uploadId: 'mine',
        type: 'file',
        label: 'x',
        sizeBytes: 6,
      );
      expect(server.records['copy-id']!.holders, {'other', 'mine'});
      final searches = server.calls
          .where((request) => request.url.path == '/drive/v3/files')
          .toList();
      expect(searches, hasLength(1));
      expect(searches.single.url.queryParameters['q'], startsWith('name = '));
      expect(server.patchRequests.single.headers['If-Match'], '"rev2"');
    });

    test('pin retries a 412 without dropping a concurrent holder', () async {
      final server = _StatefulManagedDriveServer()
        ..addRecord('copy-id', 'hash', {'prior'});
      server.conflictNextPatch('copy-id', addHolder: 'concurrent');
      final transport = _statefulTransport(server);
      expect(
        await transport.pinAttachmentObject(
          contentHash: 'hash',
          uploadId: 'mine',
          type: 'image',
          label: 'x',
          sizeBytes: 6,
        ),
        'copy-id',
      );
      expect(server.records['copy-id']!.holders, {
        'prior',
        'concurrent',
        'mine',
      });
      expect(server.patchRequests.map((r) => r.headers['If-Match']), [
        '"rev1"',
        '"rev2"',
      ]);
    });

    test(
      'release removes only its holder and records the published bundle',
      () async {
        final server = _StatefulManagedDriveServer()
          ..addRecord('copy-id', 'hash', {'mine', 'other'});
        await _statefulTransport(server).releaseAttachmentObject(
          recordId: 'copy-id',
          uploadId: 'mine',
          publishedBundleId: 'bundle-7',
        );
        final record = server.records['copy-id']!;
        expect(record.holders, {'other'});
        expect(record.properties['lastBundle'], 'bundle-7');
        expect(record.properties['kind'], 'attachment-managed-v1');
        expect(record.properties['contentHash'], 'hash');
      },
    );

    test(
      'a holder arriving after the GC snapshot makes the claim stale',
      () async {
        final server = _StatefulManagedDriveServer()
          ..addRecord('exact-uuid', 'hash', {});
        final transport = _statefulTransport(server);
        final candidate =
            (await transport.listManagedAttachmentObjects()).single;
        server.externalAddHolder('exact-uuid', 'racing-pin');
        expect(
          await transport.claimAndDeleteAttachmentObject(candidate),
          isFalse,
        );
        expect(server.records['exact-uuid']!.holders, {'racing-pin'});
        expect(server.patchRequests, isEmpty);
        expect(server.deleteRequests, isEmpty);
      },
    );

    test(
      'claim uses If-Match and deletes the exact ID; deleting blocks release',
      () async {
        final server = _StatefulManagedDriveServer()
          ..addRecord('exact-uuid', 'hash', {});
        final transport = _statefulTransport(server);
        final candidate =
            (await transport.listManagedAttachmentObjects()).single;
        expect(
          await transport.claimAndDeleteAttachmentObject(candidate),
          isTrue,
        );
        expect(
          server.patchRequests.single.url.path,
          '/drive/v2/files/exact-uuid',
        );
        expect(server.patchRequests.single.headers['If-Match'], '"rev1"');
        expect(
          server.deleteRequests.single.url.path,
          '/drive/v2/files/exact-uuid',
        );
        expect(server.deleteRequests.single.headers['If-Match'], '"rev2"');
        expect(server.records['exact-uuid']!.deleted, isTrue);

        final deletingServer = _StatefulManagedDriveServer()
          ..addRecord('already-claimed', 'hash', {}, deleting: true);
        await _statefulTransport(deletingServer).releaseAttachmentObject(
          recordId: 'already-claimed',
          uploadId: 'mine',
          publishedBundleId: 'bundle',
        );
        expect(deletingServer.patchRequests, isEmpty);
        expect(
          deletingServer.records['already-claimed']!.properties['lastBundle'],
          isNull,
        );
      },
    );
  });
}

GoogleApisGoogleDriveSyncTransport _statefulTransport(
  _StatefulManagedDriveServer server,
) => GoogleApisGoogleDriveSyncTransport(
  driveApiProvider: () async => drive.DriveApi(server),
  maintenanceClient: server,
);

class _FakeDriveHttpClient extends http.BaseClient {
  _FakeDriveHttpClient(this.properties);
  final Map<String, String> properties;
  final List<http.BaseRequest> calls = [];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    calls.add(request);
    final path = request.url.path;
    if (path == '/drive/v2/files' && request.method == 'GET') {
      return _json(200, {
        'items': [
          {
            'id': 'bad',
            'etag': '"rev1"',
            'properties': properties.entries
                .map(
                  (e) => {
                    'key': e.key,
                    'value': e.value,
                    'visibility': 'PRIVATE',
                  },
                )
                .toList(),
          },
        ],
      });
    }
    if (path == '/drive/v3/files' && request.method == 'GET') {
      if (request.url.queryParameters['q']?.startsWith('name = ') == true) {
        return _json(200, {'files': []});
      }
      return _json(200, {
        'files': [
          {
            'id': 'bad',
            'name': 'himemo_managed_attachment_bad.encjson',
            'appProperties': properties,
          },
        ],
      });
    }
    if (path == '/drive/v2/files/bad' && request.method == 'GET') {
      return _json(200, {
        'id': 'bad',
        'etag': '"rev1"',
        'modifiedDate': '2026-10-29T00:00:00Z',
        'fileSize': '6',
        'properties': properties.entries
            .map(
              (e) => {'key': e.key, 'value': e.value, 'visibility': 'PRIVATE'},
            )
            .toList(),
      });
    }
    if (path.endsWith('/drive/v3/files') && request.method == 'POST') {
      return _json(200, {'id': 'fresh'});
    }
    return _json(404, {
      'error': {'message': 'not found'},
    });
  }

  http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

class _StatefulManagedDriveServer extends http.BaseClient {
  final Map<String, _ManagedRecord> records = {};
  final Map<String, String> legacyFiles = {};
  final List<http.BaseRequest> calls = [];
  int inventoryPageSize = 1000;
  final List<http.BaseRequest> patchRequests = [];
  final List<http.BaseRequest> deleteRequests = [];
  String? _conflictId;
  String? _conflictHolder;

  void addRecord(
    String id,
    String hash,
    Set<String> holders, {
    bool deleting = false,
  }) {
    records[id] = _ManagedRecord(id, {
      'kind': 'attachment-managed-v1',
      'contentHash': hash,
      'protocol': '1',
      'holds': jsonEncode(holders.toList()),
      'deleting': deleting ? 'true' : 'false',
      'type': 'image',
      'label': 'x',
      'sizeBytes': '6',
    }, holders);
  }

  void conflictNextPatch(String id, {required String addHolder}) {
    _conflictId = id;
    _conflictHolder = addHolder;
  }

  void externalAddHolder(String id, String holder) {
    final record = records[id]!;
    record.holders.add(holder);
    record.properties['holds'] = jsonEncode(record.holders.toList());
    record.bump();
  }

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    calls.add(request);
    if (path == '/drive/v2/files' && request.method == 'GET') {
      final start =
          int.tryParse(request.url.queryParameters['pageToken'] ?? '') ?? 0;
      final all = records.values.where((record) => !record.deleted).toList();
      final page = all.skip(start).take(inventoryPageSize).toList();
      return _json(200, {
        'items': page.map(_recordBody).toList(),
        if (start + page.length < all.length)
          'nextPageToken': '${start + page.length}',
      });
    }
    if (path == '/drive/v3/files' && request.method == 'GET') {
      final query = request.url.queryParameters['q'] ?? '';
      if (query.startsWith('name = ')) {
        final legacy = legacyFiles.entries.where(
          (entry) =>
              query.contains('himemo_sync_attachment_${entry.key}.encjson'),
        );
        return _json(200, {
          'files': legacy.map((entry) => {'id': entry.value}).toList(),
        });
      }
      return _json(200, {
        'files': records.values
            .where((r) => !r.deleted)
            .map(
              (r) => {
                'id': r.id,
                'name': 'himemo_managed_attachment_${r.id}.encjson',
                'appProperties': r.properties,
                'modifiedTime': '2026-10-29T00:00:00Z',
                'size': '6',
              },
            )
            .toList(),
      });
    }
    final v2 = RegExp(r'^/drive/v2/files/([^/]+)$').firstMatch(path);
    if (v2 != null) {
      final id = v2.group(1)!;
      final record = records[id];
      if (record == null || record.deleted) {
        return _json(404, {'error': 'missing'});
      }
      if (request.method == 'GET') return _recordJson(record);
      if (request.method == 'PATCH') {
        patchRequests.add(request);
        final ifMatch = request.headers['If-Match'];
        if (_conflictId == id) {
          record.holders.add(_conflictHolder!);
          record.properties['holds'] = jsonEncode(record.holders.toList());
          record.bump();
          _conflictId = null;
          _conflictHolder = null;
          return _json(412, {'error': 'precondition failed'});
        }
        if (ifMatch != record.etag) {
          return _json(412, {'error': 'precondition failed'});
        }
        final body =
            jsonDecode((request as http.Request).body) as Map<String, dynamic>;
        final properties = body['properties'] as List;
        record.properties
          ..clear()
          ..addEntries(
            properties.whereType<Map>().map(
              (p) => MapEntry(p['key'] as String, p['value'] as String),
            ),
          );
        record.holders
          ..clear()
          ..addAll(
            (jsonDecode(record.properties['holds']!) as List).cast<String>(),
          );
        record.bump();
        return _recordJson(record);
      }
      if (request.method == 'DELETE') {
        deleteRequests.add(request);
        if (request.headers['If-Match'] != record.etag) {
          return _json(412, {'error': 'precondition failed'});
        }
        record.deleted = true;
        return _json(204, {});
      }
    }
    return _json(404, {'error': 'not found'});
  }

  http.StreamedResponse _recordJson(_ManagedRecord record) =>
      _json(200, _recordBody(record));

  Map<String, Object> _recordBody(_ManagedRecord record) => {
    'id': record.id,
    'etag': record.etag,
    'modifiedDate': '2026-10-29T00:00:00Z',
    'fileSize': '6',
    'properties': record.properties.entries
        .map((e) => {'key': e.key, 'value': e.value, 'visibility': 'PRIVATE'})
        .toList(),
  };

  http.StreamedResponse _json(int status, Object body) => http.StreamedResponse(
    Stream<List<int>>.value(utf8.encode(jsonEncode(body))),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

class _ManagedRecord {
  _ManagedRecord(this.id, this.properties, this.holders);
  final String id;
  final Map<String, String> properties;
  final Set<String> holders;
  int revision = 1;
  bool deleted = false;
  String get etag => '"rev$revision"';
  void bump() => revision++;
}
