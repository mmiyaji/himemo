import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../home/domain/note_entry.dart';

/// Records excluded notes and the remote bundles that still contain their
/// latest effective state, allowing older bundle history to be pruned safely.
class SyncExclusionRetention {
  const SyncExclusionRetention({
    required this.excludedNoteIds,
    required this.retainedBundleIds,
    this.noteBundleIds = const <String, String>{},
  });

  final Set<String> excludedNoteIds;
  final Set<String> retainedBundleIds;
  final Map<String, String> noteBundleIds;

  Map<String, dynamic> toJson() => {
    'excludedNoteIds': excludedNoteIds.toList()..sort(),
    'retainedBundleIds': {
      ...retainedBundleIds,
      ...noteBundleIds.values,
    }.toList()..sort(),
    'noteBundleIds': Map<String, String>.fromEntries(
      noteBundleIds.entries.toList()..sort((a, b) => a.key.compareTo(b.key)),
    ),
  };

  static SyncExclusionRetention? fromJson(Object? value) {
    if (value is! Map) return null;
    final ids = value['excludedNoteIds'];
    final bundles = value['retainedBundleIds'];
    if (ids is! List || bundles is! List) return null;
    final rawNoteBundles = value['noteBundleIds'];
    Set<String>? parse(List list) {
      final result = <String>{};
      for (final item in list) {
        if (item is! String || item.trim().isEmpty || !result.add(item)) {
          return null;
        }
      }
      return result;
    }

    final parsedIds = parse(ids);
    final parsedBundles = parse(bundles);
    if (parsedIds == null || parsedBundles == null) return null;
    final noteBundles = <String, String>{};
    if (rawNoteBundles != null) {
      if (rawNoteBundles is! Map) return null;
      for (final entry in rawNoteBundles.entries) {
        if (entry.key is! String ||
            (entry.key as String).trim().isEmpty ||
            entry.value is! String ||
            (entry.value as String).trim().isEmpty ||
            !parsedIds.contains(entry.key)) {
          return null;
        }
        noteBundles[entry.key as String] = entry.value as String;
      }
    }
    if (!parsedBundles.containsAll(noteBundles.values)) return null;
    return SyncExclusionRetention(
      excludedNoteIds: parsedIds,
      retainedBundleIds: parsedBundles,
      noteBundleIds: Map.unmodifiable(noteBundles),
    );
  }
}

/// Incrementally finds the bundle holding each excluded note's latest state.
/// Only one small candidate record per note is retained while streaming.
class SyncExclusionRetentionBuilder {
  SyncExclusionRetentionBuilder({
    required Set<String> localExcludedNoteIds,
    required this.isExcluded,
  }) : _excludedIds = {...localExcludedNoteIds};

  final bool Function(NoteEntry note) isExcluded;
  final Set<String> _excludedIds;
  final Map<String, _Candidate> _latest = {};
  final Map<String, Map<String, _Candidate>> _currentVersions = {};
  final Set<String> _excludedEver = {};

  void addBundle({
    required String fileId,
    required Map<String, dynamic> payload,
    DateTime? modifiedAt,
  }) {
    final notes = payload['notes'];
    if (notes == null) return;
    if (notes is! List) {
      throw const FormatException('Malformed historical sync notes.');
    }
    for (final raw in notes) {
      if (raw is! Map) {
        throw const FormatException('Malformed historical sync note.');
      }
      final record = Map<String, dynamic>.from(raw);
      final rawNote = record['note'];
      if (rawNote is! Map) {
        throw const FormatException('Malformed historical sync note.');
      }
      NoteEntry note;
      try {
        note = NoteEntry.fromJson(Map<String, dynamic>.from(rawNote));
      } catch (_) {
        // Pruning must never discard the only copy of an unparsed record.
        throw const FormatException('Malformed historical sync note.');
      }
      if (note.id.isEmpty ||
          (record['action'] != null &&
              record['action'] != 'upsert' &&
              record['action'] != 'delete')) {
        throw const FormatException('Malformed historical sync note.');
      }
      final excluded = isExcluded(note);
      if (excluded) _excludedEver.add(note.id);
      final candidate = _Candidate(
        noteId: note.id,
        bundleId: fileId,
        revision: note.revision,
        moment:
            (record['action'] == 'delete' ? note.deletedAt : null) ??
            note.updatedAt ??
            note.createdAt,
        modifiedAt: modifiedAt ?? DateTime.fromMillisecondsSinceEpoch(0),
        excluded: excluded,
        isDelete: record['action'] == 'delete',
      );
      final previous = _latest[note.id];
      final stateOrder = previous == null
          ? 1
          : candidate.compareStateTo(previous);
      if (stateOrder > 0) _currentVersions[note.id] = {};
      if (stateOrder >= 0) {
        final fingerprint =
            '${record['action']}:${note.contentHash ?? sha256.convert(utf8.encode(jsonEncode(rawNote))).toString()}';
        final variants = _currentVersions.putIfAbsent(note.id, () => {});
        final sameContent = variants[fingerprint];
        if (sameContent == null || candidate.compareTo(sameContent) > 0) {
          variants[fingerprint] = candidate;
        }
      }
      if (previous == null || candidate.compareTo(previous) > 0) {
        _latest[note.id] = candidate;
      }
    }
  }

  SyncExclusionRetention finish() {
    final excludedIds = {..._excludedIds};
    for (final entry in _latest.entries) {
      final current = entry.value;
      if (current.excluded ||
          (current.isDelete && _excludedEver.contains(entry.key))) {
        excludedIds.add(entry.key);
      }
    }
    final noteBundleIds = <String, String>{
      for (final id in excludedIds)
        if (_latest[id] case final candidate?) id: candidate.bundleId,
    };
    return SyncExclusionRetention(
      excludedNoteIds: Set.unmodifiable(excludedIds),
      // Preserve competing maximal versions. A later upload timestamp alone
      // must not authorize deleting a different same-revision note version.
      retainedBundleIds: Set.unmodifiable({
        for (final id in excludedIds)
          for (final candidate
              in _currentVersions[id]?.values ?? <_Candidate>[])
            candidate.bundleId,
      }),
      noteBundleIds: Map.unmodifiable(noteBundleIds),
    );
  }
}

class _Candidate implements Comparable<_Candidate> {
  const _Candidate({
    required this.noteId,
    required this.bundleId,
    required this.revision,
    required this.moment,
    required this.modifiedAt,
    required this.excluded,
    required this.isDelete,
  });

  final String noteId;
  final String bundleId;
  final int revision;
  final DateTime moment;
  final DateTime modifiedAt;
  final bool excluded;
  final bool isDelete;

  int compareStateTo(_Candidate other) {
    final order = revision.compareTo(other.revision);
    return order == 0 ? moment.compareTo(other.moment) : order;
  }

  @override
  int compareTo(_Candidate other) {
    var order = compareStateTo(other);
    if (order != 0) return order;
    order = modifiedAt.compareTo(other.modifiedAt);
    if (order != 0) return order;
    order = bundleId.compareTo(other.bundleId);
    if (order != 0) return order;
    return noteId.compareTo(other.noteId);
  }
}
