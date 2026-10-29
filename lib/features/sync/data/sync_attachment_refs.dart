const syncAttachmentObjectRefPrefix = 'sync-attachment-object://';

String syncAttachmentObjectRef(String contentHash, {bool managed = false}) {
  if (contentHash.isEmpty) {
    throw ArgumentError.value(contentHash, 'contentHash', 'must not be empty');
  }
  return '$syncAttachmentObjectRefPrefix${managed ? 'v2:' : ''}$contentHash';
}

bool isSyncAttachmentObjectRef(String? filePath) {
  return filePath?.startsWith(syncAttachmentObjectRefPrefix) == true;
}

String? syncAttachmentObjectContentHash(String? filePath) {
  if (!isSyncAttachmentObjectRef(filePath)) {
    return null;
  }
  var contentHash = filePath!.substring(syncAttachmentObjectRefPrefix.length);
  if (contentHash.startsWith('v2:')) contentHash = contentHash.substring(3);
  return contentHash.isEmpty ? null : contentHash;
}

Set<String> syncAttachmentObjectHashesInNoteJson(Map rawNote) {
  final hashes = <String>{};

  void addFromAttachmentJson(Object? rawAttachment) {
    if (rawAttachment is! Map) {
      return;
    }
    final contentHash = syncAttachmentObjectContentHash(
      rawAttachment['filePath'] as String?,
    );
    if (contentHash != null) {
      hashes.add(contentHash);
    }
  }

  for (final rawAttachment
      in (rawNote['attachments'] as List<dynamic>? ?? const <dynamic>[])) {
    addFromAttachmentJson(rawAttachment);
  }
  for (final rawBlock
      in (rawNote['blocks'] as List<dynamic>? ?? const <dynamic>[])) {
    if (rawBlock is! Map) {
      continue;
    }
    addFromAttachmentJson(rawBlock['attachment']);
  }
  return hashes;
}
