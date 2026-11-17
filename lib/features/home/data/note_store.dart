import '../domain/note_entry.dart';

/// Persistence boundary used by `NotesController`.
///
/// The v1 implementation is `EncryptedNoteStore` (local encrypted database).
/// The v2 implementation is `SyncV2NoteStore` (Sync v2 note history).
abstract interface class NoteStore {
  /// Returns every note the store can currently decrypt.
  Future<List<NoteEntry>> load({required List<NoteEntry> fallbackNotes});

  /// Replaces the stored set with [notes].
  ///
  /// When [preserveOmittedPrivateNotes] is true, private notes missing from
  /// [notes] are kept (they are usually omitted because they are locked).
  Future<List<NoteEntry>> save(
    List<NoteEntry> notes, {
    bool preserveOmittedPrivateNotes = false,
  });

  Future<NoteEntry> saveOne(NoteEntry note);

  Future<void> deleteById(String noteId);

  /// Removes the local copy of one vault. It does not delete synced data.
  Future<void> deleteByVaultId(String vaultId);

  Future<int> storagePayloadSizeBytes();
}
