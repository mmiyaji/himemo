const syncAttachmentObjectRefPrefix = 'sync-attachment-object://';

String syncAttachmentObjectRef(String contentHash) {
  if (contentHash.isEmpty) {
    throw ArgumentError.value(contentHash, 'contentHash', 'must not be empty');
  }
  return '$syncAttachmentObjectRefPrefix$contentHash';
}

bool isSyncAttachmentObjectRef(String? filePath) {
  return filePath?.startsWith(syncAttachmentObjectRefPrefix) == true;
}

String? syncAttachmentObjectContentHash(String? filePath) {
  if (!isSyncAttachmentObjectRef(filePath)) {
    return null;
  }
  final contentHash = filePath!.substring(syncAttachmentObjectRefPrefix.length);
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
