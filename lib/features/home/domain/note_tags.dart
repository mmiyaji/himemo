String normalizeNoteTag(String value) {
  return value
      .trim()
      .replaceAll(RegExp(r'\s+'), ' ')
      .replaceAll(RegExp(r'^#+'), '')
      .trim();
}

String canonicalizeNoteTag(String value) {
  return normalizeNoteTag(value).toLowerCase();
}

List<String> dedupeNoteTags(Iterable<String> values) {
  final seen = <String>{};
  final tags = <String>[];
  for (final raw in values) {
    final normalized = normalizeNoteTag(raw);
    if (normalized.isEmpty) {
      continue;
    }
    final key = canonicalizeNoteTag(normalized);
    if (!seen.add(key)) {
      continue;
    }
    tags.add(normalized);
  }
  return List.unmodifiable(tags);
}
