import 'package:flutter_test/flutter_test.dart';
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/home/domain/vault_models.dart';
import 'package:himemo/features/security/data/encrypted_note_database.dart';
import 'package:himemo/features/sync/data/google_drive_sync_transport.dart';
import 'package:himemo/features/sync/data/sync_attachment_refs.dart';
import 'package:himemo/features/sync/data/sync_bundle_state_store.dart';
import 'package:himemo/features/sync/data/sync_bundle_preview.dart';
import 'package:himemo/features/sync/data/sync_conflict_policy.dart';
import 'package:himemo/features/sync/data/sync_engine.dart';
import 'package:shared_preferences/shared_preferences.dart';

RemoteSyncBundleStatus _status(
  String fileId, {
  String? bundleKind,
  DateTime? modifiedAt,
}) {
  return RemoteSyncBundleStatus(
    fileId: fileId,
    fileName: '$fileId.enc',
    modifiedAt: modifiedAt,
    bundleKind: bundleKind,
  );
}

NoteEntry _note(
  String id, {
  String vaultId = 'everyday',
  String title = 'Title',
  String body = 'Body',
  DateTime? updatedAt,
  DateTime? deletedAt,
  String? contentHash = 'content-hash',
  List<NoteAttachment> attachments = const <NoteAttachment>[],
  List<NoteBlock> blocks = const <NoteBlock>[],
  bool isPinned = false,
  int revision = 1,
}) {
  return NoteEntry(
    id: id,
    vaultId: vaultId,
    title: title,
    body: body,
    createdAt: DateTime.utc(2026, 1),
    updatedAt: updatedAt ?? DateTime.utc(2026, 1, 2),
    deletedAt: deletedAt,
    contentHash: contentHash,
    attachments: attachments,
    blocks: blocks,
    isPinned: isPinned,
    revision: revision,
  );
}

Map<String, dynamic> _change(
  NoteEntry note, {
  PendingNoteChangeAction action = PendingNoteChangeAction.upsert,
}) {
  return {'action': action.name, 'note': note.toJson()};
}

void main() {
  group('selectRemoteBundlesToApply', () {
    test('returns nothing for empty history', () {
      expect(
        selectRemoteBundlesToApply(
          history: const [],
          bundleState: const SyncBundleState(),
        ),
        isEmpty,
      );
    });

    test(
      'applies every bundle newer than the applied anchor, oldest first',
      () {
        final history = [
          _status('d4', bundleKind: SyncBundleKind.delta),
          _status('d3', bundleKind: SyncBundleKind.delta),
          _status('d2', bundleKind: SyncBundleKind.delta),
          _status('f1', bundleKind: SyncBundleKind.full),
        ];
        final selected = selectRemoteBundlesToApply(
          history: history,
          bundleState: const SyncBundleState(lastAppliedRemoteFileId: 'd2'),
        );
        expect(selected.map((status) => status.fileId).toList(), ['d3', 'd4']);
      },
    );

    test('returns nothing when the anchor is already the newest bundle', () {
      final history = [
        _status('d2', bundleKind: SyncBundleKind.delta),
        _status('f1', bundleKind: SyncBundleKind.full),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(lastAppliedRemoteFileId: 'd2'),
      );
      expect(selected, isEmpty);
    });

    test(
      'replays from the newest full snapshot when the anchor is unknown',
      () {
        final history = [
          _status('d5', bundleKind: SyncBundleKind.delta),
          _status('f4', bundleKind: SyncBundleKind.full),
          _status('d3', bundleKind: SyncBundleKind.delta),
          _status('f2', bundleKind: SyncBundleKind.full),
          _status('d1', bundleKind: SyncBundleKind.delta),
        ];
        final selected = selectRemoteBundlesToApply(
          history: history,
          bundleState: const SyncBundleState(),
        );
        expect(selected.map((status) => status.fileId).toList(), ['f4', 'd5']);
      },
    );

    test('replays from the newest full snapshot when the anchor was pruned '
        'from history', () {
      final history = [
        _status('d6', bundleKind: SyncBundleKind.delta),
        _status('f5', bundleKind: SyncBundleKind.full),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(
          lastAppliedRemoteFileId: 'gone-bundle',
        ),
      );
      expect(selected.map((status) => status.fileId).toList(), ['f5', 'd6']);
    });

    test('treats legacy bundles without a kind as full snapshots', () {
      final history = [
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('legacy2'),
        _status('d1', bundleKind: SyncBundleKind.delta),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      );
      expect(selected.map((status) => status.fileId).toList(), [
        'legacy2',
        'd3',
      ]);
    });

    test('replays the entire history when no full snapshot is visible', () {
      final history = [
        _status('d3', bundleKind: SyncBundleKind.delta),
        _status('d2', bundleKind: SyncBundleKind.delta),
        _status('d1', bundleKind: SyncBundleKind.delta),
      ];
      final selected = selectRemoteBundlesToApply(
        history: history,
        bundleState: const SyncBundleState(),
      );
      expect(selected.map((status) => status.fileId).toList(), [
        'd1',
        'd2',
        'd3',
      ]);
    });
  });

  group('assessSyncConflict', () {
    test(
      'returns clear when sync is disabled or required state is missing',
      () {
        final queue = SyncQueueSummary(
          totalChanges: 1,
          upserts: 1,
          deletes: 0,
          lastQueuedAt: DateTime.utc(2026, 6, 2),
        );
        final remoteStatus = _status(
          'remote-new',
          modifiedAt: DateTime.utc(2026, 6, 3),
        );
        final bundleState = SyncBundleState(
          lastAppliedAt: DateTime.utc(2026, 6),
        );

        expect(
          assessSyncConflict(
            queue: queue,
            remoteStatus: remoteStatus,
            bundleState: bundleState,
            googleDriveSelected: false,
          ).hasConflict,
          isFalse,
        );
        expect(
          assessSyncConflict(
            queue: null,
            remoteStatus: remoteStatus,
            bundleState: bundleState,
            googleDriveSelected: true,
          ).hasConflict,
          isFalse,
        );
        expect(
          assessSyncConflict(
            queue: queue,
            remoteStatus: null,
            bundleState: bundleState,
            googleDriveSelected: true,
          ).hasConflict,
          isFalse,
        );
        expect(
          assessSyncConflict(
            queue: queue,
            remoteStatus: remoteStatus,
            bundleState: null,
            googleDriveSelected: true,
          ).hasConflict,
          isFalse,
        );
      },
    );

    test('ignores empty queues and remote statuses without modified time', () {
      final bundleState = SyncBundleState(lastAppliedAt: DateTime.utc(2026, 6));

      expect(
        assessSyncConflict(
          queue: const SyncQueueSummary(
            totalChanges: 0,
            upserts: 0,
            deletes: 0,
          ),
          remoteStatus: _status(
            'remote-new',
            modifiedAt: DateTime.utc(2026, 6, 3),
          ),
          bundleState: bundleState,
          googleDriveSelected: true,
        ).hasConflict,
        isFalse,
      );
      expect(
        assessSyncConflict(
          queue: const SyncQueueSummary(
            totalChanges: 1,
            upserts: 1,
            deletes: 0,
          ),
          remoteStatus: _status('remote-no-time'),
          bundleState: bundleState,
          googleDriveSelected: true,
        ).hasConflict,
        isFalse,
      );
    });

    test('uses applied or uploaded moments as the known remote boundary', () {
      final queue = SyncQueueSummary(
        totalChanges: 1,
        upserts: 1,
        deletes: 0,
        lastQueuedAt: DateTime.utc(2026, 6, 3),
      );

      expect(
        assessSyncConflict(
          queue: queue,
          remoteStatus: _status(
            'remote-old',
            modifiedAt: DateTime.utc(2026, 6, 2),
          ),
          bundleState: SyncBundleState(
            lastAppliedAt: DateTime.utc(2026, 6, 2),
            lastUploadedAt: DateTime.utc(2026, 6),
          ),
          googleDriveSelected: true,
        ).hasConflict,
        isFalse,
      );
      expect(
        assessSyncConflict(
          queue: queue,
          remoteStatus: _status(
            'remote-old-upload',
            modifiedAt: DateTime.utc(2026, 6, 2),
          ),
          bundleState: SyncBundleState(
            lastUploadedAt: DateTime.utc(2026, 6, 2),
          ),
          googleDriveSelected: true,
        ).hasConflict,
        isFalse,
      );
      expect(
        assessSyncConflict(
          queue: queue,
          remoteStatus: _status(
            'remote-without-boundary',
            modifiedAt: DateTime.utc(2026, 6, 4),
          ),
          bundleState: const SyncBundleState(),
          googleDriveSelected: true,
        ).hasConflict,
        isFalse,
      );
    });

    test(
      'clears when local queued changes are newer than the remote update',
      () {
        final assessment = assessSyncConflict(
          queue: SyncQueueSummary(
            totalChanges: 1,
            upserts: 1,
            deletes: 0,
            lastQueuedAt: DateTime.utc(2026, 6, 4),
          ),
          remoteStatus: _status(
            'remote-before-local',
            modifiedAt: DateTime.utc(2026, 6, 3),
          ),
          bundleState: SyncBundleState(lastAppliedAt: DateTime.utc(2026, 6)),
          googleDriveSelected: true,
        );

        expect(assessment.hasConflict, isFalse);
        expect(assessment.message, isNull);
      },
    );

    test('detects pending local changes behind a newer remote bundle', () {
      final assessment = assessSyncConflict(
        queue: SyncQueueSummary(
          totalChanges: 2,
          upserts: 1,
          deletes: 1,
          lastQueuedAt: DateTime.utc(2026, 6, 2),
        ),
        remoteStatus: _status(
          'remote-newer',
          modifiedAt: DateTime.utc(2026, 6, 3),
        ),
        bundleState: SyncBundleState(lastAppliedAt: DateTime.utc(2026, 6)),
        googleDriveSelected: true,
      );

      expect(assessment.hasConflict, isTrue);
      expect(assessment.message, 'sync.error.conflict_pending_remote_newer');
    });
  });

  group('sync attachment object refs', () {
    test('creates, detects, and parses object references', () {
      final ref = syncAttachmentObjectRef('sha256:abc');

      expect(ref, 'sync-attachment-object://sha256:abc');
      expect(isSyncAttachmentObjectRef(ref), isTrue);
      expect(syncAttachmentObjectContentHash(ref), 'sha256:abc');
      expect(isSyncAttachmentObjectRef('secure-attachment://local'), isFalse);
      expect(
        syncAttachmentObjectContentHash('secure-attachment://local'),
        isNull,
      );
      expect(syncAttachmentObjectContentHash(null), isNull);
      expect(
        syncAttachmentObjectContentHash('sync-attachment-object://'),
        isNull,
      );
    });

    test('rejects empty content hashes', () {
      expect(() => syncAttachmentObjectRef(''), throwsA(isA<ArgumentError>()));
    });

    test('collects unique content hashes from attachments and blocks', () {
      final hashes = syncAttachmentObjectHashesInNoteJson({
        'attachments': [
          {'filePath': syncAttachmentObjectRef('hash-a')},
          {'filePath': syncAttachmentObjectRef('hash-b')},
          {'filePath': 'secure-attachment://local'},
          'not-a-map',
        ],
        'blocks': [
          {
            'attachment': {'filePath': syncAttachmentObjectRef('hash-a')},
          },
          {
            'attachment': {'filePath': syncAttachmentObjectRef('hash-c')},
          },
          'not-a-map',
          {'attachment': null},
        ],
      });

      expect(hashes, {'hash-a', 'hash-b', 'hash-c'});
    });
  });

  group('buildSyncBundlePreview', () {
    test('summarizes metadata, untitled adds, updates, and deletions', () {
      final preview = buildSyncBundlePreview(
        decodedBundle: {
          'deviceId': 'remote-device',
          'exportedAt': '2026-06-12T01:38:00.000Z',
          'attachments': [
            {'id': 'attachment-a'},
            {'id': 'attachment-b'},
          ],
          'notes': [
            _change(
              _note(
                'added',
                title: '   ',
                body: 'Fresh',
                contentHash: 'hash-added',
              ),
            ),
            _change(
              _note(
                'existing',
                title: 'Remote title',
                body: 'Remote body',
                contentHash: 'hash-new',
                revision: 3,
              ),
            ),
            _change(
              _note(
                'removed',
                title: 'Remote removed',
                deletedAt: DateTime.utc(2026, 6, 12),
              ),
              action: PendingNoteChangeAction.delete,
            ),
          ],
        },
        currentNotes: [
          _note(
            'existing',
            title: 'Local title',
            body: 'Local body',
            contentHash: 'hash-old',
          ),
          _note('removed', title: 'Local removed'),
        ],
      );

      expect(preview.deviceId, 'remote-device');
      expect(preview.exportedAt, DateTime.utc(2026, 6, 12, 1, 38));
      expect(preview.noteCount, 3);
      expect(preview.attachmentCount, 2);
      expect(preview.addedCount, 1);
      expect(preview.updatedCount, 1);
      expect(preview.removedCount, 1);
      expect(preview.sampleTitles, ['(Untitled)', 'Remote title']);
      expect(preview.addedTitles, ['(Untitled)']);
      expect(preview.updatedTitles, ['Remote title']);
      expect(preview.removedTitles, ['Local removed']);
    });

    test('falls back to note deletedAt when change action is unknown', () {
      final deletedNote = _note(
        'deleted-by-fallback',
        title: 'Fallback deleted',
        deletedAt: DateTime.utc(2026, 6, 12),
      );

      final preview = buildSyncBundlePreview(
        decodedBundle: {
          'exportedAt': 'not-a-date',
          'notes': [
            {'action': 'legacy-delete', 'note': deletedNote.toJson()},
          ],
        },
        currentNotes: [_note('deleted-by-fallback', title: 'Local title')],
      );

      expect(preview.exportedAt, isNull);
      expect(preview.addedCount, 0);
      expect(preview.updatedCount, 0);
      expect(preview.removedCount, 1);
      expect(preview.sampleTitles, isEmpty);
      expect(preview.removedTitles, ['Local title']);
    });

    test('detects attachment differences and ignores identical notes', () {
      const localAttachment = NoteAttachment(
        type: AttachmentType.photo,
        label: 'same.jpg',
        filePath: 'secure-attachment://same',
      );
      const changedAttachment = NoteAttachment(
        type: AttachmentType.photo,
        label: 'changed.jpg',
        filePath: 'secure-attachment://same',
      );

      final identical = _note(
        'identical',
        attachments: const [localAttachment],
      );
      final changed = _note('changed', attachments: const [changedAttachment]);

      final preview = buildSyncBundlePreview(
        decodedBundle: {
          'notes': [_change(identical), _change(changed)],
        },
        currentNotes: [
          identical,
          _note('changed', attachments: const [localAttachment]),
        ],
      );

      expect(preview.addedCount, 0);
      expect(preview.updatedCount, 1);
      expect(preview.updatedTitles, ['Title']);
    });

    test('collects private vault ids from visible and encrypted entries', () {
      final preview = buildSyncBundlePreview(
        decodedBundle: {
          'notes': [
            _change(
              _note(
                'visible-private',
                vaultId: 'private',
                title: 'Visible private',
              ),
            ),
          ],
          'encryptedPrivateNotes': [
            null,
            'not-a-map',
            {'note': {}},
            {
              'note': {'vaultId': ''},
            },
            {
              'note': {'vaultId': 'private_profile:locked'},
            },
          ],
        },
        currentNotes: const [],
      );

      expect(preview.privateVaultNoteCount, 6);
      expect(preview.privateVaultIds, {'private', 'private_profile:locked'});
    });
  });

  group('vault models', () {
    test('VaultBucket round trips JSON and supports copy equality', () {
      const bucket = VaultBucket(
        id: 'private',
        name: 'Private',
        description: 'Locked notes',
      );

      final restored = VaultBucket.fromJson(bucket.toJson());
      expect(restored, bucket);
      expect(
        bucket.copyWith(description: 'Personal notes'),
        const VaultBucket(
          id: 'private',
          name: 'Private',
          description: 'Personal notes',
        ),
      );
    });

    test('UnlockIdentity round trips visible vaults and accent metadata', () {
      const identity = UnlockIdentity(
        id: 'admin',
        name: 'Admin',
        tagline: 'All vaults',
        lockLabel: 'Unlocked',
        visibleVaultIds: ['everyday', 'private'],
        accentHex: 0xFF6A1B9A,
        warning: 'Sensitive notes are visible.',
      );

      final restored = UnlockIdentity.fromJson(identity.toJson());
      expect(restored, identity);
      expect(restored.visibleVaultIds, ['everyday', 'private']);
      expect(
        restored.copyWith(visibleVaultIds: ['private_profile:work']).toJson(),
        containsPair('visibleVaultIds', ['private_profile:work']),
      );
    });
  });

  group('SyncBundleStateStore', () {
    setUp(() {
      SharedPreferences.setMockInitialValues(const {});
    });

    test(
      'recordUpload advances the applied anchor and delta counter',
      () async {
        final store = SyncBundleStateStore();
        await store.recordUpload(
          _status('f1', modifiedAt: DateTime.utc(2026, 6, 1)),
          fullSnapshot: true,
        );
        var state = await store.read();
        expect(state.lastAppliedRemoteFileId, 'f1');
        expect(state.lastFullUploadedAt, isNotNull);
        expect(state.deltaUploadsSinceFull, 0);

        await store.recordUpload(
          _status('d2', modifiedAt: DateTime.utc(2026, 6, 2)),
          fullSnapshot: false,
        );
        await store.recordUpload(
          _status('d3', modifiedAt: DateTime.utc(2026, 6, 3)),
          fullSnapshot: false,
        );
        state = await store.read();
        expect(state.lastAppliedRemoteFileId, 'd3');
        expect(state.deltaUploadsSinceFull, 2);

        await store.recordUpload(
          _status('f4', modifiedAt: DateTime.utc(2026, 6, 4)),
          fullSnapshot: true,
        );
        state = await store.read();
        expect(state.deltaUploadsSinceFull, 0);
      },
    );

    test(
      'recordApply advances the applied anchor, status checks do not',
      () async {
        final store = SyncBundleStateStore();
        await store.recordRemoteStatus(
          _status('seen-only', modifiedAt: DateTime.utc(2026, 6, 1)),
        );
        var state = await store.read();
        expect(state.lastRemoteFileId, 'seen-only');
        expect(state.lastAppliedRemoteFileId, isNull);

        await store.recordApply(
          _status('applied', modifiedAt: DateTime.utc(2026, 6, 2)),
        );
        state = await store.read();
        expect(state.lastAppliedRemoteFileId, 'applied');
        expect(state.lastAppliedAt, isNotNull);
      },
    );

    test('state survives a JSON round trip', () async {
      final original = SyncBundleState(
        lastRemoteFileId: 'r1',
        lastRemoteModifiedAt: DateTime.utc(2026, 6, 1),
        lastRemoteDeviceId: 'device-a',
        lastUploadedAt: DateTime.utc(2026, 6, 2),
        lastAppliedAt: DateTime.utc(2026, 6, 3),
        lastAppliedRemoteFileId: 'a1',
        lastAppliedRemoteModifiedAt: DateTime.utc(2026, 6, 4),
        lastFullUploadedAt: DateTime.utc(2026, 6, 5),
        deltaUploadsSinceFull: 7,
      );
      final restored = SyncBundleState.fromJson(original.toJson());
      expect(restored.lastRemoteFileId, original.lastRemoteFileId);
      expect(
        restored.lastAppliedRemoteFileId,
        original.lastAppliedRemoteFileId,
      );
      expect(
        restored.lastAppliedRemoteModifiedAt,
        original.lastAppliedRemoteModifiedAt,
      );
      expect(restored.lastFullUploadedAt, original.lastFullUploadedAt);
      expect(restored.deltaUploadsSinceFull, original.deltaUploadsSinceFull);
    });
  });
}
