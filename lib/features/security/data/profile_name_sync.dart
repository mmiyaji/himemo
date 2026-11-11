/// A rename and the profile-name history it has observed. A clock component
/// belongs to one device and increases only when that device writes a name.
class ProfileNameChange {
  ProfileNameChange._(this.id, this.name, Map<String, int> clock)
    : clock = Map.unmodifiable(clock);

  // The largest counter that is also exact on Flutter Web.
  static const _maxCounter = 9007199254740991;

  final String id;
  final String name;
  final Map<String, int> clock;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'clock': {
      for (final device in clock.keys.toList()..sort()) device: clock[device],
    },
  };

  static ProfileNameChange? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final name = value['name'];
    final rawClock = value['clock'];
    if (id is! String ||
        id.trim().isEmpty ||
        name is! String ||
        name.trim().isEmpty ||
        rawClock is! Map ||
        rawClock.isEmpty) {
      return null;
    }
    final clock = <String, int>{};
    for (final entry in rawClock.entries) {
      final device = entry.key;
      final counter = entry.value;
      if (device is! String ||
          device.trim().isEmpty ||
          counter is! int ||
          counter < 1 ||
          counter > _maxCounter) {
        return null;
      }
      clock[device] = counter;
    }
    return ProfileNameChange._(id, name, clock);
  }

  bool _dominates(ProfileNameChange other) {
    var strictlyNewer = false;
    for (final entry in other.clock.entries) {
      final counter = clock[entry.key] ?? 0;
      if (counter < entry.value) return false;
      if (counter > entry.value) strictlyNewer = true;
    }
    return strictlyNewer || clock.length > other.clock.length;
  }

  bool _sameChange(ProfileNameChange other) =>
      name == other.name &&
      clock.length == other.clock.length &&
      clock.entries.every((entry) => other.clock[entry.key] == entry.value);
}

/// Stores only maximal revisions. Concurrent names remain visible until a
/// user chooses a name, producing a revision that supersedes both histories.
class ProfileNameSync {
  const ProfileNameSync() : heads = const [], pendingId = null;

  ProfileNameSync._(Iterable<ProfileNameChange> heads, this.pendingId)
    : heads = List.unmodifiable(
        heads.toList()..sort((a, b) => a.id.compareTo(b.id)),
      );

  final List<ProfileNameChange> heads;
  final String? pendingId;

  String? get preferredName => heads.firstOrNull?.name;

  bool get hasConflict => heads.any((head) => head.name != preferredName);

  String? get sendableId => hasConflict ? null : pendingId;

  ProfileNameSync rename({
    required String name,
    required String deviceId,
    required String changeId,
  }) {
    if (name.trim().isEmpty ||
        deviceId.trim().isEmpty ||
        changeId.trim().isEmpty) {
      throw ArgumentError('A name, device ID and change ID are required.');
    }
    if (heads.any((head) => head.id == changeId)) {
      throw ArgumentError('The name change ID is already in use.');
    }
    final clock = <String, int>{};
    for (final head in heads) {
      for (final entry in head.clock.entries) {
        if (entry.value > (clock[entry.key] ?? 0)) {
          clock[entry.key] = entry.value;
        }
      }
    }
    final counter = clock[deviceId] ?? 0;
    if (counter == ProfileNameChange._maxCounter) {
      throw StateError('The profile-name revision counter is exhausted.');
    }
    clock[deviceId] = counter + 1;
    return ProfileNameSync._([
      ProfileNameChange._(changeId, name, clock),
    ], changeId);
  }

  ProfileNameSync merge(ProfileNameSync remote) {
    final changes = {for (final head in heads) head.id: head};
    for (final head in remote.heads) {
      final previous = changes[head.id];
      if (previous != null && !previous._sameChange(head)) {
        throw const FormatException('Conflicting profile-name change IDs.');
      }
      changes[head.id] = head;
    }
    final merged = _maximalHeads(changes.values);
    // A remote descendant already represents the pending edit. Otherwise a
    // pending edit survives retries and ordinary historical replays.
    return ProfileNameSync._(
      merged,
      merged.any((head) => head.id == pendingId) ? pendingId : null,
    );
  }

  ProfileNameSync acknowledge(String id) =>
      id == pendingId ? ProfileNameSync._(heads, null) : this;

  Map<String, dynamic> toJson({bool includePending = true}) => {
    'heads': [for (final head in heads) head.toJson()],
    if (includePending && pendingId != null) 'pendingId': pendingId,
  };

  static ProfileNameSync? fromJson(Object? value) {
    if (value is! Map || value['heads'] is! List) return null;
    final heads = <ProfileNameChange>[];
    final ids = <String>{};
    for (final raw in value['heads'] as List) {
      final head = ProfileNameChange.fromJson(raw);
      if (head == null || !ids.add(head.id)) return null;
      heads.add(head);
    }
    final pendingId = value['pendingId'];
    if (pendingId != null &&
        (pendingId is! String || !ids.contains(pendingId))) {
      return null;
    }
    if (_maximalHeads(heads).length != heads.length) return null;
    return ProfileNameSync._(heads, pendingId as String?);
  }

  static List<ProfileNameChange> _maximalHeads(
    Iterable<ProfileNameChange> changes,
  ) => [
    for (final change in changes)
      if (!changes.any((other) => other._dominates(change))) change,
  ];
}
