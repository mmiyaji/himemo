# Cloud sync replay

Normal sync, upload preparation, and private profile unlock use the same cloud
replay. The replay validates the history before applying bundles. If it finds an
unapplied full checkpoint with explicit coverage, it applies the checkpoint
first, then walks the uncovered IDs from oldest to newest. When the local
applied-ID set is absent, the selector treats it as empty. Replay acknowledges
the latest bundle published by this device without merging it again. An
explicitly forced full upload can recover incomplete history.

## Apply and publication

| Apply result | Acknowledgement | Replay behavior |
| --- | --- | --- |
| Applied | Record the ID | Continue |
| Applied with encrypted notes waiting for unlock | Record the ID | Continue and retain the unlock notice for sync completion |
| Deferred because legacy private notes are locked | Leave the ID unapplied | Continue and retry the bundle on a later replay |
| Failed | Keep acknowledgements already recorded | Stop the walk |

An upload result or a held conflict can supersede the completion notice. A
held conflict does not stop replay. Its local edit stays out of publication.

Upload preparation keeps deferred legacy IDs for that upload. Ordinary
publication checks the latest bundle and the full history before writing.
Those checks allow verified deferrals. A reviewed upload instead checks the
explicitly reviewed latest ID. Snapshot coverage uses only persisted applied
IDs, so a bundle that arrives after the final check remains eligible for
replay.

## Unlock and manual apply

The sync controller holds one operation owner across replay and publication.
Unlock waits for the owner to finish, then replays without publishing. Both
manual apply and replay pair the payload with the status captured at download.
The mobile preflight uses declared pending bundle sizes. Other history reads
and attachment hydration are outside that estimate. Unlock skips known-offline
connections. Drive replay and attachment hydration require authorization and
a key already prepared in this session.

Manual apply can leave a legacy private bundle waiting for unlock. That
payload has a dedicated cache slot on native and Web. Unlock tries that cache
first, then checks cloud history. Cached apply retains attachment references
and defers bundles that need a missing history dependency. The cache carries
no verified remote identity, so local import does not acknowledge a remote
ID or claim snapshot coverage. Older installs can still read the previous
download slot. Before a new manual download replaces it, the controller
copies any pending payload to the dedicated slot. Cloud replay acknowledges
the remote record normally.

## Scope and verification

- Modify `lib/features/sync/presentation/sync_controllers.dart`,
  `lib/features/sync/data/secure_sync_bundle_store.dart`, and
  `test/app_test.dart`. Add this design note and
  `test/sync_bundle_web_cache_test.dart`. Keep the bundle format and existing
  applied-ID store.
- First share the per-bundle replay and return explicit apply results. Verify
  locked deferral, held conflicts, and independent publication.
- Then serialize sync and unlock and preserve the manual cached fallback.
  Verify a paused download, an unavailable cloud history, and a later
  successful cloud replay. Verify that unlock preserves unrelated pending
  edits and does not publish. Test separate cache slots and legacy reads on
  Web.
- Run the sync regressions, full Flutter suite, and static analysis. Verify the
  release build separately on an iPad with iCloud.
