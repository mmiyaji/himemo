import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';

import '../../home/domain/note_entry.dart';
import '../../security/data/encryption_service.dart';
import '../../security/data/secure_key_value_store.dart';
import '../../security/data/sync_v2_admin_store.dart';
import '../../security/data/sync_v2_profile_keys.dart';
import '../data/sync_v2_enrollment_store.dart';
import '../data/sync_v2_attachment_service.dart';
import '../data/sync_v2_generation_registration.dart';
import '../data/sync_v2_icloud_session.dart';
import '../data/sync_v2_inbox.dart';
import '../data/sync_v2_note_repository.dart';
import '../data/sync_v2_profile_catalog.dart';
import '../data/sync_v2_publisher.dart';
import '../data/sync_v2_receiver.dart';

/// Secret material for this isolated reader lives only for the page session.
class SyncV2EphemeralKeyStore extends MemorySecureKeyValueStore {
  bool _closed = false;

  @override
  Future<void> write(String key, String value) async {
    if (_closed) throw StateError('Session is closed');
    await super.write(key, value);
    if (_closed) {
      await super.delete(key);
      throw StateError('Session is closed');
    }
  }

  @override
  Future<String?> read(String key) =>
      _closed ? Future.value(null) : super.read(key);

  void clearSession() {
    _closed = true;
    clear();
  }
}

/// Even if an outbox somehow exists, this isolated session cannot upload it.
class SyncV2NeverWriteTransport implements SyncV2WriteTransport {
  const SyncV2NeverWriteTransport();
  @override
  Future<void> publish({
    required String generationId,
    required SyncV2Publication publication,
  }) => Future.error(UnsupportedError('Read-only session'));
}

class SyncV2ReadOnlyProfile {
  const SyncV2ReadOnlyProfile(this.id, this.name);
  final String id;
  final String name;
}

class SyncV2ReadOnlyNote {
  const SyncV2ReadOnlyNote(
    this.note, {
    required this.conflicted,
    this.attachments = const [],
  });
  final NoteEntry note;
  final bool conflicted;
  final List<SyncV2AttachmentReference> attachments;
}

/// Returns a note's authenticated V2 attachment reference when the local
/// metadata is linked to it. Older V2 notes may not cache the content hash on
/// NoteAttachment, so the authenticated reference is authoritative in that case.
SyncV2AttachmentReference? syncV2ReadOnlyAttachmentReference(
  SyncV2ReadOnlyNote item,
  NoteAttachment attachment,
) {
  if (item.conflicted) return null;
  final path = attachment.filePath;
  if (path == null || !path.startsWith('v2attachment:')) return null;
  final id = path.substring('v2attachment:'.length);
  final reference = item.attachments
      .where((entry) => entry.id == id)
      .firstOrNull;
  if (reference == null ||
      reference.type != attachment.type.name ||
      (attachment.syncAttachmentContentHash != null &&
          reference.sha256 != attachment.syncAttachmentContentHash)) {
    return null;
  }
  return reference;
}

/// Read-only controller for the standalone CloudKit Web experiment. It exposes
/// no note, profile, archive or remote write operations.
class SyncV2CloudKitReadOnlyController extends ChangeNotifier {
  SyncV2CloudKitReadOnlyController({
    required SyncV2Inbox inbox,
    required SyncV2NoteRepository repository,
    required this.encryption,
    required SyncV2EphemeralKeyStore store,
    required this.accountReader,
    required this.registrationTransport,
    required this.readerFactory,
  }) : // Public constructor arguments must not expose the mutable backends.
       // ignore: prefer_initializing_formals
       _inbox = inbox,
       // ignore: prefer_initializing_formals
       _repository = repository,
       _store = store,
       _enrollments = SyncV2EnrollmentStore(store);

  final SyncV2Inbox _inbox;
  final SyncV2NoteRepository _repository;
  final EncryptionService encryption;
  final SyncV2EphemeralKeyStore _store;
  final Future<String> Function() accountReader;
  final SyncV2GenerationRegistrationTransport Function(String)
  registrationTransport;
  final SyncV2ReadTransport Function(String) readerFactory;
  final SyncV2EnrollmentStore _enrollments;
  SyncV2RegisteredNormalProfile? _normal;
  SecretKey? _syncKey;
  String? _account;
  String? _generation;
  final _private = <SyncV2UnlockedProfile>[];
  bool _disposed = false;
  int _epoch = 0;
  Future<void>? _pending;
  bool busy = false;
  bool partial = false;
  String? selectedProfileId;
  List<SyncV2ReadOnlyNote> notes = const [];

  bool get unlocked => _normal != null;
  List<SyncV2ReadOnlyProfile> get profiles => [
    if (_normal case final normal?)
      SyncV2ReadOnlyProfile(normal.profileId, '通常'),
    for (final profile in _private)
      SyncV2ReadOnlyProfile(profile.id, profile.name),
  ];

  void _check(int epoch) {
    if (_disposed || epoch != _epoch) throw StateError('Session is closed');
  }

  Future<void> _run(Future<void> Function(int epoch) action) async {
    if (_disposed || busy) throw StateError('Session is unavailable');
    final epoch = _epoch;
    busy = true;
    notifyListeners();
    final operation = action(epoch);
    _pending = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    try {
      await operation;
    } finally {
      _pending = null;
      if (!_disposed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  /// Verifies the SYNC code against the current Apple account and cloud proof.
  Future<void> recover(String code) => _run((epoch) async {
    if (_normal != null) throw StateError('Already unlocked');
    final account = await accountReader();
    _check(epoch);
    final registration = SyncV2GenerationRegistration(
      registrationTransport(account),
      _enrollments,
      encryption: encryption,
    );
    final normal = await registration.recover(code);
    try {
      _check(epoch);
      final enrollment = await _enrollments.readForAccount(account);
      if (enrollment == null) throw StateError('Missing verified enrollment');
      try {
        _check(epoch);
        _normal = normal;
        _syncKey = enrollment.syncKey;
        _account = account;
        _generation = enrollment.generationId;
        selectedProfileId = normal.profileId;
      } catch (_) {
        enrollment.syncKey.destroy();
        rethrow;
      }
    } catch (_) {
      normal.destroy();
      rethrow;
    }
    await _sync(epoch);
  });

  Future<void> sync() => _run(_sync);

  Future<void> _sync(int epoch) async {
    final account = _account;
    final key = _syncKey;
    if (account == null || key == null || _normal == null) {
      throw StateError('Session is locked');
    }
    if (await accountReader() != account) {
      throw StateError('Apple account changed');
    }
    _check(epoch);
    final session = SyncV2ICloudSession(
      _enrollments,
      _inbox,
      stopOnQuarantine: true,
      accountReader: accountReader,
      transportFactory: (current) => (
        reader: readerFactory(current),
        writer: const SyncV2NeverWriteTransport(),
      ),
    );
    partial = true;
    for (var page = 0; page < 40; page++) {
      final progress = await session.syncOnce(limit: 50);
      _check(epoch);
      if (progress.errors.isNotEmpty) throw StateError('Read-only sync failed');
      if (!progress.hasMoreHeaders && progress.downloadedPayloads < 50) {
        partial = false;
        break;
      }
    }
    await _loadNotes(epoch);
  }

  /// Verifies ADMIN independently; no administrator settings are persisted.
  Future<void> unlockAdmin(String code) => _run((epoch) async {
    final account = _account;
    final generation = _generation;
    final key = _syncKey;
    final normal = _normal;
    if (account == null ||
        generation == null ||
        key == null ||
        normal == null) {
      throw StateError('Session is locked');
    }
    if (await accountReader() != account) {
      throw StateError('Apple account changed');
    }
    _check(epoch);
    final admin = SyncV2AdminStore(
      _store,
      encryption,
      generationId: generation,
    ).decodeRecoveryCode(code);
    try {
      await SyncV2GenerationRegistration(
        registrationTransport(account),
        _enrollments,
        encryption: encryption,
      ).verifyAdminKey(accountId: account, adminKey: admin);
      _check(epoch);
      final catalog = SyncV2ProfileCatalog(
        _inbox,
        _repository,
        encryption,
        _store,
        generationId: generation,
        syncKey: key,
        normalAccess: normal.access,
      );
      final unlocked = await catalog.unlockAdmin(admin);
      try {
        _check(epoch);
      } catch (_) {
        for (final profile in unlocked) {
          profile.destroy();
        }
        rethrow;
      }
      for (final old in _private) {
        old.destroy();
      }
      _private
        ..clear()
        ..addAll(unlocked);
      selectedProfileId = normal.profileId;
      notes = const [];
      notifyListeners();
      await _loadNotes(epoch);
    } finally {
      admin.destroy();
    }
  });

  Future<void> selectProfile(String id) => _run((epoch) async {
    if (_account == null || await accountReader() != _account) {
      throw StateError('Apple account changed');
    }
    _check(epoch);
    if (!profiles.any((profile) => profile.id == id)) {
      throw StateError('Profile is locked');
    }
    selectedProfileId = id;
    notes = const [];
    notifyListeners();
    await _loadNotes(epoch);
  });

  Future<void> _loadNotes(int epoch) async {
    final normal = _normal;
    final key = _syncKey;
    final generation = _generation;
    final selected = selectedProfileId;
    if (normal == null ||
        key == null ||
        generation == null ||
        selected == null) {
      throw StateError('Session is locked');
    }
    final SyncV2UnlockedProfileKey access;
    if (selected == normal.profileId) {
      access = normal.access;
    } else {
      access = _private.singleWhere((profile) => profile.id == selected).access;
    }
    final snapshots = await _repository.readProfile(
      generationId: generation,
      profileId: selected,
      syncKey: key,
      profileKey: access,
      noteIdPrefix: 'note_',
    );
    _check(epoch);
    final loaded = <SyncV2ReadOnlyNote>[];
    for (final entry in snapshots.entries) {
      final snapshot = entry.value;
      if (!snapshot.canCompareVersions ||
          snapshot.versions.every((version) => version.isDeleted)) {
        continue;
      }
      for (final version in snapshot.versions) {
        final body = version.body;
        if (version.isDeleted ||
            body == null ||
            body['type'] != 'note' ||
            body['note'] is! Map) {
          continue;
        }
        final note = NoteEntry.fromJson(
          Map<String, dynamic>.from(body['note'] as Map),
        );
        if (note.id != entry.key || note.vaultId != selected) {
          throw const FormatException('Invalid note identity');
        }
        final references = <String, SyncV2AttachmentReference>{};
        for (final version in snapshot.versions) {
          final body = version.body;
          if (body == null || body['type'] != 'note' || body['note'] is! Map) {
            continue;
          }
          final raw = body['attachments'];
          if (raw is! List) {
            if (raw != null) throw const FormatException('Invalid attachments');
            continue;
          }
          for (final value in raw) {
            if (value is! Map) {
              throw const FormatException('Invalid attachment');
            }
            final reference = SyncV2AttachmentReference.fromJson(
              Map<String, dynamic>.from(value),
            );
            final previous = references[reference.id];
            if (previous != null &&
                jsonEncode(previous.toJson()) !=
                    jsonEncode(reference.toJson())) {
              throw const FormatException('Conflicting attachment reference');
            }
            references[reference.id] = reference;
          }
        }
        loaded.add(
          SyncV2ReadOnlyNote(
            note,
            conflicted: snapshot.hasConflict,
            attachments: List.unmodifiable(references.values),
          ),
        );
      }
    }
    loaded.sort((a, b) => b.note.createdAt.compareTo(a.note.createdAt));
    _check(epoch);
    notes = List.unmodifiable(loaded);
  }

  /// Decrypts one attachment from the already received inbox. The caller owns
  /// and must clear the returned plaintext bytes when it is done with them.
  Future<Uint8List> readAttachment({
    required SyncV2ReadOnlyNote item,
    required NoteAttachment attachment,
    required bool Function() isCurrent,
  }) async {
    final epoch = _epoch;
    final profileId = selectedProfileId;
    final account = _account;
    final generation = _generation;
    final syncKey = _syncKey;
    final normal = _normal;
    if (_disposed || item.conflicted || !isCurrent()) {
      throw StateError('Attachment is unavailable');
    }
    final reference = syncV2ReadOnlyAttachmentReference(item, attachment);
    if (reference == null) {
      throw StateError('Attachment data is incomplete');
    }
    if (profileId == null ||
        account == null ||
        generation == null ||
        syncKey == null ||
        normal == null ||
        item.note.vaultId != profileId) {
      throw StateError('Attachment is unavailable');
    }
    final access = profileId == normal.profileId
        ? normal.access
        : _private
              .where((profile) => profile.id == profileId)
              .firstOrNull
              ?.access;
    if (access == null) throw StateError('Profile is locked');
    if (await accountReader() != account) {
      throw StateError('Apple account changed');
    }
    void checkActive() {
      if (_disposed ||
          epoch != _epoch ||
          profileId != selectedProfileId ||
          !isCurrent()) {
        throw StateError('Attachment request is no longer active');
      }
    }

    checkActive();
    final bytes = await SyncV2AttachmentService(_inbox, _repository).read(
      reference: reference,
      generationId: generation,
      syncKey: syncKey,
      profileAccess: access,
      checkActive: checkActive,
    );
    try {
      checkActive();
      if (await accountReader() != account) {
        throw StateError('Apple account changed');
      }
      checkActive();
      return bytes;
    } catch (_) {
      bytes.fillRange(0, bytes.length, 0);
      rethrow;
    }
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _epoch++;
    notes = const [];
    selectedProfileId = null;
    for (final profile in _private) {
      profile.destroy();
    }
    _private.clear();
    _normal?.destroy();
    _normal = null;
    _syncKey?.destroy();
    _syncKey = null;
    _account = null;
    _generation = null;
    _store.clearSession();
    final pending = _pending;
    unawaited((pending ?? Future<void>.value()).then((_) => _inbox.close()));
    super.dispose();
  }
}
