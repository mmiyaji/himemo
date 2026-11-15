import 'dart:convert';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import 'sync_v2_attachment_service.dart';
import 'sync_v2_inbox.dart';
import 'sync_v2_legacy_import.dart';
import 'sync_v2_note_repository.dart';

class SyncV2ArchiveInspection {
  SyncV2ArchiveInspection(
    this.noteCountsByProfile,
    this.notesWithUnlinkedAttachments,
  );
  final Map<String, int> noteCountsByProfile;
  final int notesWithUnlinkedAttachments;
}

class SyncV2ArchiveService {
  SyncV2ArchiveService(this.inbox, this.repository)
    : attachments = SyncV2AttachmentService(inbox, repository);
  final SyncV2Inbox inbox;
  final SyncV2NoteRepository repository;
  final SyncV2AttachmentService attachments;
  static const maxArchiveBytes = 256 * 1024 * 1024;

  Future<SyncV2ArchiveInspection> inspect(
    Uint8List bytes, {
    String? password,
  }) => _inspectArchiveInWorker(Uint8List.fromList(bytes), password);

  Future<int> importArchive({
    required Uint8List bytes,
    String? password,
    required String generationId,
    required SecretKey syncKey,
    required Map<String, SyncV2UnlockedProfileKey> destinations,
    bool acceptUnlinkedAttachments = false,
    bool overwriteExisting = false,
    String? writerId,
    void Function()? checkActive,
  }) async {
    checkActive?.call();
    final decoded = await _decodeArchiveInWorker(
      Uint8List.fromList(bytes),
      password,
    );
    checkActive?.call();
    final sources = decoded.inspection.noteCountsByProfile.keys.toSet();
    final mappedSources = destinations.keys
        .where((source) => source != 'everyday')
        .toSet();
    final privateSources = sources
        .where((source) => source != 'everyday')
        .toSet();
    if (mappedSources.length != privateSources.length ||
        !privateSources.containsAll(mappedSources) ||
        (sources.contains('everyday') &&
            !destinations.containsKey('everyday')) ||
        destinations.values.any((v) => v.generationId != generationId) ||
        destinations.values.map((v) => v.profileId).toSet().length !=
            destinations.length ||
        (sources.contains('everyday') &&
            (destinations['everyday']!.profileId == 'private' ||
                destinations['everyday']!.profileId.startsWith(
                  'private_profile:',
                )))) {
      throw StateError('Invalid import destinations');
    }
    final legacyNotes = decoded.inspection.mapDestinations(
      privateDestinations: {
        for (final entry in destinations.entries)
          if (entry.key != 'everyday') entry.key: entry.value.profileId,
      },
      unlockedPrivateProfiles: destinations.values
          .map((v) => v.profileId)
          .toSet(),
      acceptUnlinkedAttachments: acceptUnlinkedAttachments,
    );
    final notes = [
      for (final note in legacyNotes)
        note.vaultId == 'everyday'
            ? note.copyWith(vaultId: destinations['everyday']!.profileId)
            : note,
    ];
    final hash = decoded.hash;
    final writerNamespace = overwriteExisting ? (writerId ?? '') : '';
    final random = overwriteExisting ? Random.secure() : null;
    final callNonce = overwriteExisting
        ? base64Url.encode(List.generate(24, (_) => random!.nextInt(256)))
        : '';
    final key = await syncKey.extractBytes();
    String identity(String note, String profile, String purpose) =>
        crypto.Hmac(crypto.sha256, key)
            .convert(
              utf8.encode(
                jsonEncode([generationId, hash, note, profile, purpose]),
              ),
            )
            .toString();
    String stableNoteId(String source, String note, String profile) =>
        'note_${crypto.Hmac(crypto.sha256, key).convert(utf8.encode(jsonEncode([generationId, source, note, profile, 'admin-import-note']))).toString()}';
    final sourceForDestination = {
      for (final entry in destinations.entries)
        if (entry.key != 'everyday') entry.value.profileId: entry.key,
    };
    return inbox.transaction(() async {
      checkActive?.call();
      final existingByProfile = <String, Map<String, SyncV2NoteSnapshot>>{};
      if (overwriteExisting) {
        for (final access in destinations.values) {
          checkActive?.call();
          final headers = await repository.readProfile(
            generationId: generationId,
            profileId: access.profileId,
            syncKey: syncKey,
            noteIdPrefix: 'note_',
          );
          checkActive?.call();
          final ids = {
            ...headers.keys,
            for (final note in notes)
              if (note.vaultId == access.profileId &&
                  !note.id.startsWith('blob_') &&
                  !note.id.startsWith('profile_'))
                note.id,
          };
          final recovered = await repository.readManyForArchiveRecovery(
            generationId: generationId,
            profileId: access.profileId,
            syncKey: syncKey,
            profileKey: access,
            noteIds: ids,
            checkActive: checkActive,
          );
          recovered.removeWhere((_, snapshot) => snapshot.headIds.isEmpty);
          existingByProfile[access.profileId] = recovered;
          checkActive?.call();
        }
      }
      for (final note in notes) {
        checkActive?.call();
        final access = destinations.values.singleWhere(
          (v) => v.profileId == note.vaultId,
        );
        final sourceProfile =
            note.vaultId == destinations['everyday']?.profileId
            ? 'everyday'
            : sourceForDestination[note.vaultId]!;
        final stableId = stableNoteId(sourceProfile, note.id, note.vaultId);
        final oldManualId = 'note_${identity(note.id, note.vaultId, 'note')}';
        final snapshots = existingByProfile[note.vaultId];
        String? originMatch;
        if (overwriteExisting && snapshots != null) {
          for (final entry in snapshots.entries) {
            checkActive?.call();
            for (final version in entry.value.versions) {
              final origin = version.body?['legacyImport'];
              if (origin is Map &&
                  origin['profileId'] == sourceProfile &&
                  origin['noteId'] == note.id) {
                originMatch = entry.key;
                break;
              }
            }
            if (originMatch != null) break;
          }
        }
        final noteId = overwriteExisting
            ? (snapshots?.containsKey(note.id) == true
                  ? note.id
                  : snapshots?.containsKey(oldManualId) == true
                  ? oldManualId
                  : originMatch ?? stableId)
            : oldManualId;
        final current = snapshots?[noteId];
        final currentBody = current?.versions.length == 1
            ? current!.versions.single.body
            : null;
        final oldReferences = <SyncV2AttachmentReference>[];
        for (final oldBody
            in current?.versions.map((v) => v.body) ??
                const <Map<String, Object?>?>[]) {
          final rawReferences = oldBody?['attachments'];
          if (rawReferences is! List) continue;
          for (final raw in rawReferences) {
            if (raw is! Map) continue;
            try {
              oldReferences.add(
                SyncV2AttachmentReference.fromJson(
                  Map<String, dynamic>.from(raw),
                ),
              );
            } on FormatException {
              // Ignore malformed old references; the archive replaces them.
            } on TypeError {
              // Ignore malformed old references; the archive replaces them.
            }
          }
        }
        final verifiedOldReferences = <String, bool>{};
        final refs = <String, SyncV2AttachmentReference>{};
        Future<NoteAttachment> mapAttachment(NoteAttachment attachment) async {
          final path = attachment.filePath;
          if (path == null || path.isEmpty) {
            return attachment.copyWith(
              filePath: null,
              previewBytesBase64: null,
              localPayloadSizeBytes: null,
              localPayloadModifiedAtMillis: null,
            );
          }
          var ref = refs[path];
          final sourceBytes = decoded.files[path]!;
          final contentHash = crypto.sha256.convert(sourceBytes).toString();
          if (ref == null && overwriteExisting) {
            for (final candidate in oldReferences) {
              checkActive?.call();
              if (candidate.sha256 != contentHash ||
                  candidate.size != sourceBytes.length ||
                  candidate.label != attachment.label ||
                  candidate.type != attachment.type.name) {
                continue;
              }
              try {
                final cached = verifiedOldReferences[candidate.id];
                final bool verified;
                if (cached != null) {
                  verified = cached;
                } else {
                  final existingBytes = await attachments.read(
                    reference: candidate,
                    generationId: generationId,
                    syncKey: syncKey,
                    profileAccess: access,
                    checkActive: checkActive,
                  );
                  try {
                    verified =
                        crypto.sha256.convert(existingBytes).toString() ==
                        contentHash;
                  } finally {
                    existingBytes.fillRange(0, existingBytes.length, 0);
                  }
                  verifiedOldReferences[candidate.id] = verified;
                }
                if (verified) {
                  ref = candidate;
                  break;
                }
              } on FormatException {
                verifiedOldReferences[candidate.id] = false;
              } on HimemoDecryptionException {
                verifiedOldReferences[candidate.id] = false;
              }
              checkActive?.call();
            }
          }
          ref ??= await attachments.store(
            generationId: generationId,
            syncKey: syncKey,
            profileAccess: access,
            bytes: sourceBytes,
            label: attachment.label,
            type: attachment.type.name,
            stableId: identity(
              overwriteExisting
                  ? jsonEncode([writerNamespace, callNonce, note.id])
                  : note.id,
              note.vaultId,
              path,
            ),
            checkActive: checkActive,
          );
          refs[path] = ref;
          return attachment.copyWith(
            filePath: 'v2attachment:${ref.id}',
            previewBytesBase64: null,
            localPayloadSizeBytes: null,
            localPayloadModifiedAtMillis: null,
            syncAttachmentContentHash: ref.sha256,
          );
        }

        final mappedAttachments = <NoteAttachment>[];
        for (final attachment in note.attachments) {
          checkActive?.call();
          mappedAttachments.add(await mapAttachment(attachment));
          checkActive?.call();
        }
        final blocks = <NoteBlock>[];
        for (final block in note.blocks) {
          checkActive?.call();
          blocks.add(
            block.attachment == null
                ? block
                : block.copyWith(
                    attachment: await mapAttachment(block.attachment!),
                  ),
          );
          checkActive?.call();
        }
        final mapped = note.copyWith(
          id: noteId,
          attachments: mappedAttachments,
          blocks: blocks,
        );
        final body = <String, Object?>{
          'type': 'note',
          'note': mapped.toJson(),
          'attachments': refs.values.map((r) => r.toJson()).toList(),
          if (overwriteExisting)
            'legacyImport': {'profileId': sourceProfile, 'noteId': note.id},
        };
        if (overwriteExisting &&
            current != null &&
            current.versions.isNotEmpty &&
            current.pendingIds.isEmpty &&
            !current.hasConflict &&
            !current.versions.single.isDeleted &&
            currentBody != null &&
            jsonEncode(_canonical(currentBody)) ==
                jsonEncode(_canonical(body))) {
          checkActive?.call();
          continue;
        }
        final heads = current?.headIds ?? <String>{};
        final parentIds = heads.toList()..sort();
        final changeId = overwriteExisting
            ? identity(
                // Separate authenticated ciphertext records across devices.
                jsonEncode([noteId, parentIds, writerNamespace, callNonce]),
                note.vaultId,
                'admin-overwrite-change',
              )
            : identity(note.id, note.vaultId, 'change');
        if (overwriteExisting) {
          checkActive?.call();
          await repository.replaceKnownHeads(
            generationId: generationId,
            profileId: note.vaultId,
            noteId: noteId,
            changeId: changeId,
            expectedHeadIds: heads,
            body: body,
            syncKey: syncKey,
            profileKey: access,
          );
        } else {
          checkActive?.call();
          await repository.save(
            generationId: generationId,
            profileId: note.vaultId,
            noteId: noteId,
            changeId: changeId,
            expectedHeadIds: {},
            body: body,
            syncKey: syncKey,
            profileKey: access,
          );
        }
        checkActive?.call();
      }
      checkActive?.call();
      return notes.length;
    });
  }

  Future<Uint8List> exportArchive({
    required String generationId,
    required SecretKey syncKey,
    required List<SyncV2UnlockedProfileKey> profiles,
    String? password,
  }) async {
    final files = <({String name, Uint8List bytes})>[];
    final notes = <Map<String, dynamic>>[];
    var fileCount = 0;
    for (final access in profiles) {
      final snapshots = await repository.readProfile(
        generationId: generationId,
        profileId: access.profileId,
        syncKey: syncKey,
        profileKey: access,
        noteIdPrefix: 'note_',
      );
      for (final snapshot in snapshots.values) {
        if (!snapshot.canCompareVersions || snapshot.hasConflict) {
          throw StateError(
            'Incomplete or conflicting notes cannot be exported',
          );
        }
        if (snapshot.versions.isEmpty || snapshot.versions.single.isDeleted) {
          continue;
        }
        final body = snapshot.versions.single.body!;
        if (body['type'] != 'note') continue;
        final note = NoteEntry.fromJson(
          Map<String, dynamic>.from(body['note'] as Map),
        );
        final paths = <String, String>{};
        for (final raw in body['attachments'] as List? ?? []) {
          final ref = SyncV2AttachmentReference.fromJson(
            Map<String, dynamic>.from(raw as Map),
          );
          final path = 'attachments/${fileCount++}';
          files.add((
            name: path,
            bytes: await attachments.read(
              reference: ref,
              generationId: generationId,
              syncKey: syncKey,
              profileAccess: access,
            ),
          ));
          paths['v2attachment:${ref.id}'] = path;
        }
        NoteAttachment remap(NoteAttachment a) {
          if (a.filePath == null) return a;
          final path = paths[a.filePath];
          if (path == null) {
            throw const FormatException('Missing exported attachment');
          }
          return a.copyWith(filePath: path);
        }

        notes.add(
          note
              .copyWith(
                vaultId: access.profileId.startsWith('private_profile:')
                    ? access.profileId
                    : 'everyday',
                attachments: note.attachments.map(remap).toList(),
                blocks: note.blocks
                    .map(
                      (b) => b.attachment == null
                          ? b
                          : b.copyWith(attachment: remap(b.attachment!)),
                    )
                    .toList(),
              )
              .toJson(),
        );
      }
    }
    return _encodeArchiveInWorker(files, notes, password);
  }
}

Object? _canonical(Object? value) => switch (value) {
  Map<String, dynamic>() => {
    for (final key in value.keys.toList()..sort()) key: _canonical(value[key]),
  },
  List<Object?>() => value.map(_canonical).toList(),
  _ => value,
};

_DecodedLegacyArchive _decodeLegacyArchive(Uint8List bytes, String? password) {
  if (bytes.isEmpty || bytes.length > SyncV2ArchiveService.maxArchiveBytes) {
    throw const FormatException('Archive exceeds size limit');
  }
  // Inspect sizes before the decoder can decompress entries (including links).
  final directory = ZipDirectory()
    ..read(InputMemoryStream(bytes), password: password);
  final names = <String>{};
  var total = 0;
  if (directory.fileHeaders.length > 10000) {
    throw const FormatException('Too many archive entries');
  }
  for (final header in directory.fileHeaders) {
    if (((header.externalFileAttributes >> 16) & 0xf000) == 0xa000) {
      throw const FormatException('Archive links are forbidden');
    }
    final name = header.file!.filename;
    if (!names.add(name) ||
        name.contains(r'\') ||
        name.startsWith('/') ||
        name.contains(':') ||
        name.split('/').any((p) => p == '..' || p == '.') ||
        (name != 'manifest.json' &&
            name != 'notes.json' &&
            !name.startsWith('attachments/'))) {
      throw const FormatException('Unsafe archive entry');
    }
    total += header.file!.uncompressedSize;
    if (header.file!.uncompressedSize > SyncV2AttachmentService.maxBytes ||
        total > SyncV2ArchiveService.maxArchiveBytes) {
      throw const FormatException('Expanded archive exceeds limit');
    }
  }
  final archive = ZipDecoder().decodeBytes(bytes, password: password);
  final files = <String, Uint8List>{};
  for (final file in archive.files) {
    if (file.symbolicLink != null) {
      throw const FormatException('Archive links are forbidden');
    }
    if (!file.isFile) continue;
    final data = Uint8List.fromList(file.content);
    if (data.length != file.size || getCrc32(data) != file.crc32) {
      throw const FormatException('Invalid archive checksum');
    }
    files[file.name] = data;
  }
  if (!files.containsKey('manifest.json') || !files.containsKey('notes.json')) {
    throw const FormatException('Missing archive metadata');
  }
  final manifest = Map<String, Object?>.from(
    jsonDecode(utf8.decode(files.remove('manifest.json')!)) as Map,
  );
  final raw = jsonDecode(utf8.decode(files.remove('notes.json')!)) as Map;
  final notes = (raw['notes'] as List)
      .map((n) => Map<String, dynamic>.from(n as Map))
      .toList();
  return (
    inspection: SyncV2LegacyImport.inspect(
      manifest: manifest,
      notes: notes,
      attachmentFiles: files,
    ),
    files: files,
    hash: crypto.sha256.convert(bytes).toString(),
  );
}

typedef _DecodedLegacyArchive = ({
  SyncV2LegacyImport inspection,
  Map<String, Uint8List> files,
  String hash,
});

// These top-level entry points capture only plain data, never a repository,
// database connection or borrowed profile key.
Future<_DecodedLegacyArchive> _decodeArchiveInWorker(
  Uint8List bytes,
  String? password,
) => Isolate.run(() => _decodeLegacyArchive(bytes, password));

Future<SyncV2ArchiveInspection> _inspectArchiveInWorker(
  Uint8List bytes,
  String? password,
) => Isolate.run(() {
  final decoded = _decodeLegacyArchive(bytes, password).inspection;
  return SyncV2ArchiveInspection(
    decoded.noteCountsByProfile,
    decoded.notesWithUnlinkedAttachments,
  );
});

Future<Uint8List> _encodeArchiveInWorker(
  List<({String name, Uint8List bytes})> files,
  List<Map<String, dynamic>> notes,
  String? password,
) => Isolate.run(() {
  final archive = Archive();
  for (final file in files) {
    archive.addFile(ArchiveFile.bytes(file.name, file.bytes));
  }
  archive.addFile(
    ArchiveFile.string(
      'notes.json',
      jsonEncode({'schemaVersion': 1, 'notes': notes}),
    ),
  );
  archive.addFile(
    ArchiveFile.string(
      'manifest.json',
      jsonEncode({
        'format': 'org.ruhenheim.himemo.notes.zip',
        'version': 1,
        'noteCount': notes.length,
        'attachmentCount': files.length,
      }),
    ),
  );
  return Uint8List.fromList(ZipEncoder(password: password).encode(archive));
});
