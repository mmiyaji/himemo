/// An immutable identity plus optimistic-concurrency token for a managed object.
class ManagedAttachmentObject {
  const ManagedAttachmentObject({
    required this.id,
    required this.contentHash,
    required this.revision,
    required this.modifiedAt,
    required this.uploadIds,
    this.lastPublishedBundleId,
    this.deleting = false,
    this.sizeBytes = 0,
  });
  final String id;
  final String contentHash;
  final String revision;
  final DateTime? modifiedAt;
  final Set<String> uploadIds;
  final String? lastPublishedBundleId;
  final bool deleting;
  final int sizeBytes;
}

/// Durable reservations do not expire: a suspended writer can resume much later.
/// Legacy objects are outside this interface and must never be swept by age.
abstract interface class RemoteAttachmentMaintenanceTransport {
  Future<String> pinAttachmentObject({
    required String contentHash,
    required String uploadId,
    String? encodedPayload,
    required String type,
    required String label,
    required int sizeBytes,
  });
  Future<void> releaseAttachmentObject({
    required String recordId,
    required String uploadId,
    required String publishedBundleId,
  });
  Future<List<ManagedAttachmentObject>> listManagedAttachmentObjects();

  /// Compare and claim with the supplied revision before deleting the exact ID.
  /// A pin racing with the claim must make the claim fail; claimed objects can
  /// never be reused by writers, which create a fresh immutable ID instead.
  Future<bool> claimAndDeleteAttachmentObject(
    ManagedAttachmentObject candidate,
  );
}
