import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_note_repository.dart';

class SyncV2AttachmentReference {
  SyncV2AttachmentReference({
    required this.id,
    required this.label,
    required this.type,
    required this.size,
    required this.sha256,
    required List<String> chunks,
  }) : chunks = List.unmodifiable(chunks);
  final String id, label, type, sha256;
  final int size;
  final List<String> chunks;
  factory SyncV2AttachmentReference.fromJson(Map<String, dynamic> json) {
    if (json.length != 6 ||
        json['id'] is! String ||
        json['label'] is! String ||
        json['type'] is! String ||
        json['size'] is! int ||
        json['sha256'] is! String ||
        json['chunks'] is! List) {
      throw const FormatException('Invalid attachment reference');
    }
    final chunks = json['chunks'] as List;
    if (chunks.any((v) => v is! String)) {
      throw const FormatException('Invalid attachment chunks');
    }
    final ref = SyncV2AttachmentReference(
      id: json['id'] as String,
      label: json['label'] as String,
      type: json['type'] as String,
      size: json['size'] as int,
      sha256: json['sha256'] as String,
      chunks: chunks.cast<String>(),
    );
    ref._validate();
    return ref;
  }
  void _validate() {
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(id) ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(sha256) ||
        !const ['photo', 'video', 'audio', 'file'].contains(type) ||
        label.length > 4096 ||
        size < 1 ||
        size > SyncV2AttachmentService.maxBytes ||
        chunks.length !=
            (size + SyncV2AttachmentService.chunkBytes - 1) ~/
                SyncV2AttachmentService.chunkBytes ||
        chunks.toSet().length != chunks.length ||
        chunks.any((id) => !RegExp(r'^blob_[a-f0-9]{64}$').hasMatch(id))) {
      throw const FormatException('Invalid attachment reference');
    }
  }

  Map<String, Object?> toJson() {
    _validate();
    return {
      'id': id,
      'label': label,
      'type': type,
      'size': size,
      'sha256': sha256,
      'chunks': chunks,
    };
  }
}

class SyncV2AttachmentService {
  SyncV2AttachmentService(this.inbox, this.repository);
  final SyncV2Inbox inbox;
  final SyncV2NoteRepository repository;
  static const chunkBytes = 1024 * 1024;
  static const maxBytes = 64 * chunkBytes;

  Future<SyncV2AttachmentReference> store({
    required String generationId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileAccess,
    required Uint8List bytes,
    required String label,
    required String type,
    String? stableId,
    void Function()? checkActive,
  }) async {
    checkActive?.call();
    final content = Uint8List.fromList(bytes);
    if (content.isEmpty || content.length > maxBytes) {
      throw const FormatException('Attachment exceeds size limit');
    }
    final digest = crypto.sha256.convert(content).toString();
    final seed =
        stableId ??
        base64Url.encode(
          List.generate(32, (_) => Random.secure().nextInt(256)),
        );
    final key = await syncKey.extractBytes();
    String identify(String purpose) => crypto.Hmac(crypto.sha256, key)
        .convert(
          utf8.encode(
            jsonEncode([generationId, profileAccess.profileId, seed, purpose]),
          ),
        )
        .toString();
    final id = identify('attachment');
    final count = (content.length + chunkBytes - 1) ~/ chunkBytes;
    final chunks = [
      for (var i = 0; i < count; i++) 'blob_${identify('chunk:$i')}',
    ];
    final reference = SyncV2AttachmentReference(
      id: id,
      label: label,
      type: type,
      size: content.length,
      sha256: digest,
      chunks: chunks,
    );
    reference._validate();
    final records =
        <({String noteId, String changeId, Map<String, Object?> body})>[];
    for (var i = 0; i < count; i++) {
      checkActive?.call();
      final part = content.sublist(
        i * chunkBytes,
        min(content.length, (i + 1) * chunkBytes),
      );
      records.add((
        noteId: chunks[i],
        changeId: identify('change:$i'),
        body: {
          'type': 'attachment-chunk',
          'attachmentId': id,
          'index': i,
          'total': count,
          'digest': crypto.sha256.convert(part).toString(),
          'bytes': base64Encode(part),
        },
      ));
      checkActive?.call();
    }
    checkActive?.call();
    await repository.saveNewBatch(
      generationId: generationId,
      profileId: profileAccess.profileId,
      syncKey: syncKey,
      profileKey: profileAccess,
      notes: records,
      checkActive: checkActive,
    );
    checkActive?.call();
    return reference;
  }

  Future<Uint8List> read({
    required SyncV2AttachmentReference reference,
    required String generationId,
    required SecretKey syncKey,
    required SyncV2UnlockedProfileKey profileAccess,
    void Function()? checkActive,
  }) async {
    checkActive?.call();
    reference._validate();
    final snapshots = await repository.readMany(
      generationId: generationId,
      profileId: profileAccess.profileId,
      syncKey: syncKey,
      profileKey: profileAccess,
      noteIds: reference.chunks.toSet(),
      checkActive: checkActive,
    );
    final output = Uint8List(reference.size);
    var offset = 0;
    var succeeded = false;
    try {
      for (var i = 0; i < reference.chunks.length; i++) {
        checkActive?.call();
        final snapshot = snapshots[reference.chunks[i]];
        if (snapshot == null ||
            !snapshot.canCompareVersions ||
            snapshot.versions.length != 1 ||
            snapshot.versions.single.isDeleted) {
          throw const FormatException('Missing attachment chunk');
        }
        final body = snapshot.versions.single.body!;
        if (body.length != 6 ||
            body['type'] != 'attachment-chunk' ||
            body['attachmentId'] != reference.id ||
            body['index'] != i ||
            body['total'] != reference.chunks.length ||
            body['bytes'] is! String ||
            body['digest'] is! String) {
          throw const FormatException('Invalid attachment chunk');
        }
        final encoded = body['bytes'] as String;
        if (encoded.length > (chunkBytes + 2) ~/ 3 * 4) {
          throw const FormatException('Oversized attachment chunk');
        }
        final bytes = base64Decode(encoded);
        try {
          final expected = i == reference.chunks.length - 1
              ? reference.size - i * chunkBytes
              : chunkBytes;
          if (bytes.length != expected ||
              crypto.sha256.convert(bytes).toString() != body['digest']) {
            throw const FormatException('Corrupt attachment chunk');
          }
          output.setRange(offset, offset + bytes.length, bytes);
          offset += bytes.length;
          checkActive?.call();
        } finally {
          bytes.fillRange(0, bytes.length, 0);
        }
      }
      if (offset != reference.size ||
          crypto.sha256.convert(output).toString() != reference.sha256) {
        throw const FormatException('Corrupt attachment');
      }
      succeeded = true;
      return output;
    } finally {
      if (!succeeded) output.fillRange(0, output.length, 0);
    }
  }
}
