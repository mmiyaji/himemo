enum SyncV2Operation { upsert, delete }

/// Verified metadata for an immutable change. Payloads are kept separately.
class SyncV2Change {
  SyncV2Change({
    required this.id,
    required this.profileId,
    required this.noteId,
    required this.operation,
    required Set<String> parentIds,
    this.payloadDigest,
  }) : parentIds = Set.unmodifiable(parentIds) {
    if (id.isEmpty ||
        profileId.isEmpty ||
        noteId.isEmpty ||
        this.parentIds.any((parent) => parent.isEmpty || parent == id) ||
        (operation == SyncV2Operation.upsert
            ? payloadDigest == null || payloadDigest!.isEmpty
            : payloadDigest != null)) {
      throw const FormatException('Invalid sync v2 change');
    }
  }

  final String id;
  final String profileId;
  final String noteId;
  final SyncV2Operation operation;
  final Set<String> parentIds;
  final String? payloadDigest;

  bool _sameRecord(SyncV2Change other) =>
      profileId == other.profileId &&
      noteId == other.noteId &&
      operation == other.operation &&
      payloadDigest == other.payloadDigest &&
      parentIds.length == other.parentIds.length &&
      parentIds.containsAll(other.parentIds);
}

/// Resolves verified changes from one sync generation without opening notes.
///
/// Both updates and tombstones can be heads. Only an applicable child consumes
/// a parent, so a resolution with a missing parent leaves known heads intact.
({Set<String> headIds, Set<String> pendingIds}) resolveSyncV2History(
  Iterable<SyncV2Change> changes,
) {
  final byId = <String, SyncV2Change>{};
  for (final change in changes) {
    final previous = byId[change.id];
    if (previous != null && !previous._sameRecord(change)) {
      throw const FormatException('Conflicting sync v2 change ID');
    }
    byId[change.id] = change;
  }

  final children = <String, List<String>>{};
  final remainingParents = <String, int>{};
  final pending = <String>{};
  final ready = <String>[];
  for (final change in byId.values) {
    var knownParents = 0;
    for (final parentId in change.parentIds) {
      final parent = byId[parentId];
      if (parent == null) {
        pending.add(change.id);
        continue;
      }
      if (parent.profileId != change.profileId ||
          parent.noteId != change.noteId) {
        throw const FormatException('Sync v2 parent belongs to another note');
      }
      knownParents++;
      children.putIfAbsent(parentId, () => []).add(change.id);
    }
    remainingParents[change.id] = knownParents;
    if (knownParents == 0) ready.add(change.id);
  }

  final heads = <String>{};
  for (var index = 0; index < ready.length; index++) {
    final id = ready[index];
    final isPending = pending.contains(id);
    if (!isPending) {
      heads.add(id);
      heads.removeAll(byId[id]!.parentIds);
    }
    for (final childId in children[id] ?? const <String>[]) {
      if (isPending) pending.add(childId);
      final remaining = remainingParents[childId]! - 1;
      remainingParents[childId] = remaining;
      if (remaining == 0) ready.add(childId);
    }
  }
  if (ready.length != byId.length) {
    throw const FormatException('Cyclic sync v2 history');
  }
  return (
    headIds: Set.unmodifiable(heads),
    pendingIds: Set.unmodifiable(pending),
  );
}
