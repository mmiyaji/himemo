import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/sync/data/sync_v2_legacy_import.dart';

Map<String, dynamic> _note(
  String id,
  String vaultId, {
  List<Map<String, dynamic>> attachments = const [],
  List<Map<String, dynamic>> blocks = const [],
}) => {
  'id': id,
  'vaultId': vaultId,
  'title': 'Synthetic $id',
  'body': 'Synthetic test content',
  'createdAt': '2026-01-02T03:04:05.000Z',
  'attachments': attachments,
  'blocks': blocks,
};

Map<String, dynamic> _attachment({String? path}) => {
  'type': 'photo',
  'label': 'synthetic-photo.jpg',
  'filePath': ?path,
};

Map<String, Object?> _manifest(
  List<Map<String, dynamic>> notes,
  Map<String, Uint8List> attachments,
) => {
  'format': 'org.ruhenheim.himemo.notes.zip',
  'version': 1,
  'noteCount': notes.length,
  'attachmentCount': attachments.length,
};

void main() {
  test(
    'accepts a ZIP v1 manifest and validates note and block attachment files',
    () {
      final notes = [
        _note(
          'note-with-attachments',
          'everyday',
          attachments: [_attachment(path: 'attachments/note-photo.jpg')],
          blocks: [
            {
              'type': 'file',
              'text': 'A block attachment',
              'attachment': _attachment(path: 'attachments/block-file.pdf'),
            },
          ],
        ),
      ];
      final files = {
        'attachments/note-photo.jpg': Uint8List.fromList([1, 2, 3]),
        'attachments/block-file.pdf': Uint8List.fromList([4, 5, 6]),
      };

      final imported = SyncV2LegacyImport.inspect(
        manifest: _manifest(notes, files),
        notes: notes,
        attachmentFiles: files,
      );

      expect(imported.noteCountsByProfile, {'everyday': 1});
      expect(imported.notesWithUnlinkedAttachments, 0);
      final mapped = imported.mapDestinations(
        privateDestinations: const {},
        unlockedPrivateProfiles: const {},
        acceptUnlinkedAttachments: false,
      );
      expect(
        mapped.single.attachments.single.filePath,
        'attachments/note-photo.jpg',
      );
      expect(
        mapped.single.blocks.single.attachment!.filePath,
        'attachments/block-file.pdf',
      );
    },
  );

  test('rejects a referenced attachment missing from the archive', () {
    final notes = [
      _note(
        'missing-file',
        'everyday',
        attachments: [_attachment(path: 'attachments/missing.jpg')],
      ),
    ];
    final files = <String, Uint8List>{};

    expect(
      () => SyncV2LegacyImport.inspect(
        manifest: _manifest(notes, files),
        notes: notes,
        attachmentFiles: files,
      ),
      throwsFormatException,
    );
  });

  test(
    'unlinked attachments need acknowledgment; unreferenced files do not',
    () {
      final notes = [
        _note('unlinked', 'everyday', attachments: [_attachment()]),
      ];
      final files = {
        'attachments/not-linked.jpg': Uint8List.fromList([7, 8]),
      };
      final imported = SyncV2LegacyImport.inspect(
        manifest: _manifest(notes, files),
        notes: notes,
        attachmentFiles: files,
      );

      expect(imported.notesWithUnlinkedAttachments, 1);
      expect(
        () => imported.mapDestinations(
          privateDestinations: const {},
          unlockedPrivateProfiles: const {},
          acceptUnlinkedAttachments: false,
        ),
        throwsStateError,
      );
      final acknowledged = imported.mapDestinations(
        privateDestinations: const {},
        unlockedPrivateProfiles: const {},
        acceptUnlinkedAttachments: true,
      );
      expect(acknowledged.single.attachments.single.filePath, isNull);
    },
  );

  test('requires distinct, unlocked destinations for every private source', () {
    final notes = [
      _note('private-one', 'private'),
      _note('private-two', 'private_profile:legacy-2'),
    ];
    final imported = SyncV2LegacyImport.inspect(
      manifest: _manifest(notes, const {}),
      notes: notes,
      attachmentFiles: const {},
    );
    const destinations = {
      'private': 'private_profile:destination-1',
      'private_profile:legacy-2': 'private_profile:destination-2',
    };

    expect(
      () => imported.mapDestinations(
        privateDestinations: destinations,
        unlockedPrivateProfiles: const {'private_profile:destination-1'},
        acceptUnlinkedAttachments: false,
      ),
      throwsStateError,
    );
    expect(
      () => imported.mapDestinations(
        privateDestinations: const {
          'private': 'private_profile:destination-1',
          'private_profile:legacy-2': 'private_profile:destination-1',
        },
        unlockedPrivateProfiles: const {'private_profile:destination-1'},
        acceptUnlinkedAttachments: false,
      ),
      throwsStateError,
    );

    final mapped = imported.mapDestinations(
      privateDestinations: destinations,
      unlockedPrivateProfiles: const {
        'private_profile:destination-1',
        'private_profile:destination-2',
      },
      acceptUnlinkedAttachments: false,
    );
    expect(mapped.map((note) => note.vaultId), [
      'private_profile:destination-1',
      'private_profile:destination-2',
    ]);
  });

  test('rejects unknown legacy vaults and inconsistent ZIP v1 manifest', () {
    final unknownVaultNote = [_note('unknown', 'private_profile:')];
    expect(
      () => SyncV2LegacyImport.inspect(
        manifest: _manifest(unknownVaultNote, const {}),
        notes: unknownVaultNote,
        attachmentFiles: const {},
      ),
      throwsFormatException,
    );

    final notes = [_note('everyday', 'everyday')];
    final manifest = _manifest(notes, const {})..['version'] = 2;
    expect(
      () => SyncV2LegacyImport.inspect(
        manifest: manifest,
        notes: notes,
        attachmentFiles: const {},
      ),
      throwsFormatException,
    );
  });
}
