// Browser integration checks for the isolated local preview. Uses sample data.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show listEquals;
import 'package:himemo/features/home/domain/note_entry.dart';
import 'package:himemo/features/sync/presentation/sync_v2_workspace.dart';
import 'package:himemo/features/sync/testing/sync_v2_local_preview.dart';

void _check(bool condition, String description) {
  if (!condition) throw StateError(description);
}

Future<void> runLocalV2Smoke() async {
  final first = createLocalPreviewController();
  var firstDisposed = false;
  var stage = 'initialize';
  SyncV2WorkspaceController? second;
  try {
    stage = 'database';
    await first.inbox.customSelect('SELECT 1').get();
    stage = 'initialize';
    await first.initialize();
    stage = 'prepare';
    final codes = await first.prepareNew('preview-password');
    stage = 'confirm';
    await first.confirmSetup();
    const title = 'Private sample title 92731';
    const body = 'Private sample body 40315';
    final bytes = Uint8List.fromList([1, 2, 3, 4]);
    stage = 'save';
    await first.saveNote(
      title: title,
      body: body,
      addedFiles: [
        SyncV2PendingAttachment(
          label: 'sample.dat',
          type: AttachmentType.file,
          bytes: bytes,
        ),
      ],
    );
    _check(first.notes.single.note.title == title, 'Local save');
    final stored = await first.inbox
        .customSelect(
          'SELECT encrypted_header, encrypted_payload FROM sync_v2_inbox',
        )
        .get();
    _check(stored.isNotEmpty, 'Encrypted rows');
    for (final row in stored) {
      _check(
        !row.read<String>('encrypted_header').contains(title),
        'Encrypted header',
      );
      final encrypted = row.data['encrypted_payload'];
      if (encrypted is List<int>) {
        final encoded = utf8.decode(encrypted, allowMalformed: true);
        _check(
          !encoded.contains(body) && !encoded.contains(title),
          'Encrypted payload',
        );
      }
    }
    first.dispose();
    firstDisposed = true;
    // Controller disposal closes the database asynchronously.
    await Future<void>.delayed(const Duration(seconds: 1));
    second = createLocalPreviewController();
    stage = 'reinitialize';
    await second.initialize();
    _check(!second.registered, 'No persistent local key');
    stage = 'recover';
    await second.recover(codes.syncCode);
    stage = 'recoverAdmin';
    await second.recoverAdmin(codes.adminCode, 'preview-new-password');
    _check(second.adminUnlocked, 'Administrator recovery');
    _check(
      second.notes.single.note.title == title &&
          second.notes.single.note.body == body,
      'Note recovery',
    );
    _check(
      listEquals(
        await second.readAttachment(second.notes.single.attachments.single),
        bytes,
      ),
      'Attachment recovery',
    );
    stage = 'createPrivate';
    await second.createProfile('Private sample', 'private-preview-password');
    await second.saveNote(
      title: 'Private profile sample',
      body: 'Private body',
    );
    second.lockPrivate();
    _check(
      !second.notes.any((item) => item.note.title == 'Private profile sample'),
      'Private lock',
    );
    await second.unlockPrivate('private-preview-password');
    _check(
      second.notes.single.note.title == 'Private profile sample',
      'Private unlock',
    );
  } catch (failure) {
    throw StateError(
      '$stage: $failure (${second?.diagnosticCode ?? first.diagnosticCode ?? "no diagnostic"})',
    );
  } finally {
    if (!firstDisposed) first.dispose();
    second?.dispose();
  }
}
