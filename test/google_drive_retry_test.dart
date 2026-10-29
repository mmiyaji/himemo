import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('bundle upload replays a consumed body after a transient 500', () async {
    final uploadBodies = <String>[];
    var creates = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST' && request.url.path.endsWith('/files')) {
        uploadBodies.add(utf8.decode(request.bodyBytes));
        creates++;
        if (creates == 1) return _serverError();
        return http.Response(
          jsonEncode({'id': 'bundle-1', 'name': 'bundle.enc'}),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      return http.Response('unexpected request', 500);
    });
    final transport = _transport(client);

    final status = await transport.uploadBundle(
      encodedPayload: 'encrypted-bundle-payload',
      deviceId: 'device-1',
      noteCount: 2,
      attachmentCount: 1,
    );

    expect(status.fileId, 'bundle-1');
    expect(uploadBodies, hasLength(2));
    final encodedPayload = base64Encode(
      utf8.encode('encrypted-bundle-payload'),
    );
    expect(uploadBodies.every((body) => body.contains(encodedPayload)), isTrue);
  });

  test(
    'attachment upload replays a consumed body after a transient 500',
    () async {
      final uploadBodies = <String>[];
      var creates = 0;
      final client = MockClient((request) async {
        if (request.method == 'GET' && request.url.path.endsWith('/files')) {
          return _json({'files': []});
        }
        if (request.method == 'POST' && request.url.path.endsWith('/files')) {
          uploadBodies.add(utf8.decode(request.bodyBytes));
          creates++;
          if (creates == 1) return _serverError();
          return _json({'id': 'attachment-1', 'name': 'attachment.encjson'});
        }
        return http.Response('unexpected request', 500);
      });

      await _transport(client).uploadAttachmentObject(
        contentHash: 'abc123',
        encodedPayload: 'encrypted-attachment-payload',
        type: 'photo',
        label: 'photo.jpg',
        sizeBytes: 32,
      );

      expect(uploadBodies, hasLength(2));
      expect(
        uploadBodies.every(
          (body) => body.contains(
            base64Encode(utf8.encode('encrypted-attachment-payload')),
          ),
        ),
        isTrue,
      );
    },
  );

  test(
    'download retries a truncated stream without retaining partial bytes',
    () async {
      var mediaRequests = 0;
      const payload = 'complete-bundle-payload';
      final client = MockClient.streaming((request, bodyStream) async {
        await bodyStream.toBytes();
        if (request.method == 'GET' &&
            request.url.path.endsWith('/files/bundle-1')) {
          if (request.url.queryParameters['alt'] == 'media') {
            mediaRequests++;
            if (mediaRequests == 1) {
              final stream = Stream<List<int>>.multi((controller) {
                controller.add(utf8.encode('partial-'));
                controller.addError(http.ClientException('connection dropped'));
                controller.close();
              });
              return http.StreamedResponse(
                stream,
                200,
                headers: {'content-type': 'application/octet-stream'},
              );
            }
            return http.StreamedResponse(
              Stream<List<int>>.value(utf8.encode(payload)),
              200,
              headers: {'content-type': 'application/octet-stream'},
            );
          }
          return http.StreamedResponse(
            Stream<List<int>>.value(
              utf8.encode(jsonEncode({'id': 'bundle-1', 'name': 'bundle.enc'})),
            ),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return http.StreamedResponse(Stream<List<int>>.empty(), 404);
      });

      final downloaded = await _transport(client)
          .downloadBundleByFileId('bundle-1');

      expect(downloaded?.encodedPayload, payload);
      expect(mediaRequests, 2);
    },
  );

  test(
    'bundle history follows the page token and caps page size at 1000',
    () async {
      final listRequests = <http.Request>[];
      final client = MockClient((request) async {
        if (request.method != 'GET' || !request.url.path.endsWith('/files')) {
          return http.Response('unexpected request', 500);
        }
        listRequests.add(request);
        final pageToken = request.url.queryParameters['pageToken'];
        final pageSize = request.url.queryParameters['pageSize'];
        if (pageToken == null) {
          expect(pageSize, '1000');
          return _json({
            'nextPageToken': 'history-page-2',
            'files': [for (var i = 0; i < 1000; i++) _bundleFile('bundle-$i')],
          });
        }
        expect(pageToken, 'history-page-2');
        expect(pageSize, '1');
        return _json({
          'files': [_bundleFile('bundle-1000')],
        });
      });

      final history = await _transport(client).listBundleHistory(limit: 1001);

      expect(history, hasLength(1001));
      expect(listRequests, hasLength(2));
      expect(
        listRequests.last.url.queryParameters['pageToken'],
        'history-page-2',
      );
    },
  );

  test('maintenance deletes only the explicitly supplied bundle IDs', () async {
    final deleted = <String>[];
    final client = MockClient((request) async {
      if (request.method == 'DELETE' && request.url.path.contains('/files/')) {
        deleted.add(request.url.path.split('/').last);
        return http.Response('', 204);
      }
      return http.Response('unexpected request', 500);
    });

    await _transport(client).deleteBundleFilesByIds({'keep-1', 'remove-2'});

    expect(deleted.toSet(), {'keep-1', 'remove-2'});
    expect(deleted, hasLength(2));
  });
}

GoogleApisGoogleDriveSyncTransport _transport(http.Client client) {
  return GoogleApisGoogleDriveSyncTransport(
    driveApiProvider: () async => drive.DriveApi(client),
  );
}

http.Response _serverError() => http.Response(
  jsonEncode({
    'error': {'code': 500, 'message': 'temporary server failure'},
  }),
  500,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

http.Response _json(Object value) => http.Response(
  jsonEncode(value),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Map<String, dynamic> _bundleFile(String id) => {
  'id': id,
  'name': 'himemo_sync_bundle_$id.enc',
  'modifiedTime': '2026-10-29T00:00:00.000Z',
  'size': '20',
  'appProperties': {'kind': 'bundle'},
};
