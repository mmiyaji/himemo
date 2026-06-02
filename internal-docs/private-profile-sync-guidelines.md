# Private profile sync guidelines

HiMemo sync must be independent of private profile lock state. A lock controls
whether the UI can decrypt and show a profile. It must not decide whether the
profile's encrypted note records are included in a sync bundle.

## Required design

- Treat normal notes and private profile notes as different sync channels.
- Normal bundle `notes` must contain only non-private vault notes.
- Private profile notes must be exported from `EncryptedNoteDatabase` into
  `encryptedPrivateNotes`.
- Admin mode is not a sync permission. It must not be used as an input to sync
  inclusion or pruning decisions.
- Profile unlock state is a decryption/display permission. It must not be used
  as an input to sync inclusion or pruning decisions.
- A full or forced upload, and any upload caused by pending changes, must carry
  all encrypted private profile note snapshots that still exist in the encrypted
  note database.
- Applying a downloaded bundle may store encrypted private notes while the
  profile is locked. Unlocking later is the only step that requires the profile
  data key.

## Forbidden patterns

- Do not build sync payloads from only the currently visible note list.
- Do not omit private notes because `ProfileDataKeyService.isProfileUnlocked`
  is false.
- Do not serialize private vault notes into the normal `notes` array, even when
  the profile is currently unlocked.
- Do not make automatic prune decisions after an upload whose note count is
  lower than a recent historical bundle. Keep multiple bundles and preserve
  larger recent history.
- Do not call `EncryptedNoteStore.save` from normal replace/merge flows in a way
  that drops omitted private snapshots. Use the guarded preservation path unless
  the operation is an explicit delete, reset, or profile removal.

## Regression tests required for sync changes

Any change touching sync snapshots, profile locks, private storage, or cloud
bundle pruning must include focused tests for these cases:

- Locked private profile notes remain in `encryptedPrivateNotes` on upload.
- Unlocked private profile notes are not emitted in normal `notes`.
- Download/apply stores encrypted private notes without needing profile unlock.
- Replacing normal notes from sync preserves omitted local private snapshots.
- Automatic iCloud pruning keeps older larger bundles after a smaller upload.

## 2026-06-02 incident note

The failure mode was not a user delete. A later upload contained fewer notes
than the previous remote bundle because private profile notes were omitted when
the profile was not available through the normal note snapshot path. Automatic
iCloud pruning then kept only the newest bundle, so the older larger bundle was
removed from cloud history.

The fix is to keep private profile sync based on encrypted storage, not visible
or unlocked UI state, and to avoid pruning away larger recent bundles after a
smaller upload.
