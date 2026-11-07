/// Exact remote bundle IDs whose changes are represented by a full snapshot.
/// The manifest is stored inside the encrypted bundle payload.
class SyncBundleCoverage {
  const SyncBundleCoverage({required this.coveredBundleIds, this.version = 1});

  final int version;
  final Set<String> coveredBundleIds;

  Map<String, Object?> toJson() => {
    'version': version,
    'coveredBundleIds': coveredBundleIds.toList()..sort(),
  };

  static SyncBundleCoverage? tryParse(Object? value) {
    if (value is! Map) return null;
    final version = value['version'];
    final ids = value['coveredBundleIds'];
    if (version != 1 ||
        ids is! List ||
        ids.any((id) => id is! String || id.isEmpty)) {
      return null;
    }
    final set = ids.cast<String>().toSet();
    if (set.length != ids.length) return null;
    return SyncBundleCoverage(coveredBundleIds: Set.unmodifiable(set));
  }
}
