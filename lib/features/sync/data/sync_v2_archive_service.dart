import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import '../../home/domain/note_entry.dart';
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
  }) async {
    final decoded = await _decodeArchiveInWorker(
      Uint8List.fromList(bytes),
      password,
    );
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
    final key = await syncKey.extractBytes();
    String identity(String note, String profile, String purpose) =>
        crypto.Hmac(crypto.sha256, key)
            .convert(
              utf8.encode(
                jsonEncode([generationId, hash, note, profile, purpose]),
              ),
            )
            .toString();
    return inbox.transaction(() async {
      for (final note in notes) {
        final access = destinations.values.singleWhere(
          (v) => v.profileId == note.vaultId,
        );
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
          ref ??= await attachments.store(
            generationId: generationId,
            syncKey: syncKey,
            profileAccess: access,
            bytes: decoded.files[path]!,
            label: attachment.label,
            type: attachment.type.name,
            stableId: identity(note.id, note.vaultId, path),
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
          mappedAttachments.add(await mapAttachment(attachment));
        }
        final blocks = <NoteBlock>[];
        for (final block in note.blocks) {
          blocks.add(
            block.attachment == null
                ? block
                : block.copyWith(
                    attachment: await mapAttachment(block.attachment!),
                  ),
          );
        }
        final noteId = 'note_${identity(note.id, note.vaultId, 'note')}';
        final mapped = note.copyWith(
          id: noteId,
          attachments: mappedAttachments,
          blocks: blocks,
        );
        await repository.save(
          generationId: generationId,
          profileId: note.vaultId,
          noteId: noteId,
          changeId: identity(note.id, note.vaultId, 'change'),
          expectedHeadIds: {},
          body: {
            'type': 'note',
            'note': mapped.toJson(),
            'attachments': refs.values.map((r) => r.toJson()).toList(),
          },
          syncKey: syncKey,
          profileKey: access,
        );
      }
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
