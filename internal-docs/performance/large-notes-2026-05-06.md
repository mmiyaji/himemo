# Large note set performance notes - 2026-05-06

## Test setup

- Branch: `codex/large-note-performance`
- Flutter: `D:\Flutter\versions\3.41.6`
- Web target: Chrome debug build
- Seed flag: `--dart-define=HIMEMO_PERF_NOTE_COUNT=1000`
- Seed data: 1000 generated notes, 1 normal vault, every 5th note includes location metadata.

## Baseline

- Desktop split view reload to first visible note: about 6.7s.
- Desktop note selection wall time: about 0.95s with a detail pane frame of 145ms.
- Mobile-width list previously nested all note widgets inside a section `Column`, so every note tile in a vault could be built eagerly.

## Changes

1. Added a development-only 1000-note seed hook.
2. Fixed an onboarding restore race so the seed hook can run after onboarding completion.
3. Replaced the mobile note section `Column` with a flattened `ListView.builder`.
4. Added row-build performance logging for mobile lists.
5. Added a year partition filter so large note histories can be narrowed before list rendering and searching.

## After changes

- Desktop split view reload to first visible note: about 7.1s in debug mode. This did not improve because the dominant cost is app bootstrap, encrypted restore, and debug module loading rather than visible row construction.
- Desktop note selection wall time: about 0.75s with a detail pane frame of 81.6ms.
- Mobile row model construction: 1000 notes produce 2010 rows in about 1.9-5.8ms.
- Mobile visual check: first visible rows render correctly at 742x909 viewport with the same card-style borders.

## Remaining risks

- Web debug reload time is not representative of production builds.
- The web note store still restores the full encrypted note payload before the list appears.
- True storage-level paging requires a queryable encrypted-note index per vault/year. Native already uses a database, but web currently uses a single encrypted payload.

## Cycle 1 follow-up

Plan:

- Avoid repeated visible-note scans when grouping by vault.
- Avoid building tag suggestions until the advanced filter panel is visible.

Changes:

- Added `visibleNotesByVaultProvider` and routed mobile list grouping through it.
- Kept `notesForVaultProvider` as a compatibility wrapper over the grouped map.
- Moved `visibleTagSuggestionsProvider` watch into the advanced filter UI branch.

Measurements:

- Mobile row model after this cycle: 1000 notes, 2010 rows, 2.2ms.
- In-app browser navigation on an already-loaded debug session showed the list content immediately; cold debug reload remains dominated by Flutter web bootstrap and encrypted payload restore.

Conclusion:

- This cycle reduces redundant provider work during normal note-list rendering.
- The next high-impact cycle is storage/index work: split web note restore into lightweight metadata plus lazy note payloads.

## Cycle 2 follow-up

Plan:

- Reduce full-list filtering while the user is typing in the note search field.

Changes:

- Replaced immediate search-provider updates with a 260ms debounce in the notes toolbar.
- Kept clearing immediate so removing a search term still restores the list without waiting.
- Synced external search resets back into the text field so private-mode cleanup and tag-filter actions still update the UI.

Measurements:

- Browser E2E with 1000 notes confirmed that typing in the search box does not immediately filter the list, then applies the result after the debounce delay.
- Static validation remained clean with `flutter analyze`.

Conclusion:

- This cycle reduces repeated O(n) search scans during typing without changing the visible search UI.
- The next practical improvement is either cached calendar/insights summaries or the larger web storage split.

## Cycle 3 follow-up

Plan:

- Avoid rebuilding calendar day lists and selected-day note lists from scratch in the calendar screen.

Changes:

- Added `visibleNotesByDayProvider`.
- Added `visibleNoteDaysProvider`.
- Updated the calendar screen and calendar detail sheet to reuse the cached day grouping.

Measurements:

- Browser E2E opened the calendar route with 1000 seeded notes and confirmed generated notes were rendered for the selected day.
- Static validation remained clean with `flutter analyze`.

Conclusion:

- This cycle moves calendar grouping cost out of the widget build path and makes day navigation reuse the same grouped data.
- Insights summaries still compute several aggregates from the full visible note list and remain a future optimization target.

## Cycle 4 follow-up

Plan:

- Reduce the per-query cost after the search input debounce fires.

Changes:

- Added `noteSearchIndexProvider`, which builds a lower-cased searchable string per note only when notes change.
- Updated visible-note filtering to use the cached search index for title/body/tag/attachment/location matching.
- Extended the search filter test to cover body search through the index.

Measurements:

- Browser E2E with 1000 seeded notes confirmed location/text search still returns matching performance notes.
- Static validation remained clean with `flutter analyze`.

Conclusion:

- Search now avoids repeated lower-casing and string assembly on every query change.
- The remaining large cost for Web is still storage restore: all note data must be decrypted before the first list can render.

## Cycle 5 follow-up

Plan:

- Avoid repeated scans for resolving the selected note ID to its visible list index.

Changes:

- Added `visibleNoteIndexByIdProvider`.
- Updated the notes screen to resolve the selected index through the cached map instead of `any` plus `indexWhere`.
- Routed `noteByIdProvider` through the same index map.

Measurements:

- Provider test confirms index map generation for filtered visible notes.
- Static validation remained clean with `flutter analyze`.

Conclusion:

- This removes repeated O(n) scans from note selection rebuilds.
- The improvement is smaller than storage/index work, but it compounds with the previous list virtualization work.

## Cycle 6 follow-up

Plan:

- Reduce repeated scans in the Insights tab.

Changes:

- Replaced separate summary/month/day/hour/attachment aggregation passes with a single `_buildInsightsData` pass.
- Reused the single aggregate result for all KPI and chart sections.

Measurements:

- Browser E2E opened the Insights route with 1000 seeded notes and confirmed the summary and chart text rendered.
- Static validation remained clean with `flutter analyze`.

Conclusion:

- Insights no longer performs several independent full-list scans for the same visible note set.
- Remaining high-impact work is still Web storage restore and lazy payload loading.

## Cycle 7 follow-up

Plan:

- Avoid year-list aggregation while the advanced filter UI is closed.

Changes:

- Moved `visibleNoteYearsProvider` reads into the advanced filter branch.
- Normal list rendering no longer computes the year list unless the user opens detailed filters.

Measurements:

- Static validation remained clean with `flutter analyze`.
- Year partition provider test remained green.

Conclusion:

- This mirrors the previous lazy tag-suggestion change and keeps the common note-list path lighter.

## Cycle 8 follow-up

Plan:

- Reduce repeated thumbnail decode work when notes with image attachments are rebuilt while scrolling.

Changes:

- Cached decoded `previewBytesBase64` inside `_AttachmentPreviewState`.
- Changed `_AttachmentImageBox` to accept `Uint8List` directly so build no longer copies bytes with `Uint8List.fromList` for already-decoded previews.
- Kept encrypted attachment fallback behavior unchanged.

Measurements:

- Static validation remained clean with `flutter analyze`.
- Existing provider/search test remained green.

Conclusion:

- This cycle targets attachment-heavy note lists. The 1000 generated note set is mostly text, so the improvement is preventive for real user datasets with many photos.

## Cycle 9 follow-up

Plan:

- Reuse the existing photo attachment bytes cache across list previews and the lightbox viewer.
- Avoid re-reading the same encrypted image file when users move between note detail, list preview, and image viewer surfaces.

Changes:

- Routed `_AttachmentPreview` file-backed photo reads through `_readPhotoAttachmentBytesWithPerf`.
- Routed `_PhotoAttachmentViewer` reads through the same cached path.
- Kept inline preview decoding local to the preview widget because it is already cached as `Uint8List` after Cycle 8.

Measurements:

- `flutter analyze` passed.
- `flutter test test\app_test.dart --plain-name "search filters can narrow notes by tags"` passed.
- A headless browser session opened the 1000-note route and captured note selection frame logs, but the reused `web-server` debug session later stayed on Splash during reconnect. The code path was therefore validated by static tests and cache-aware debug instrumentation rather than a second full browser replay in the same server session.

Conclusion:

- This is a targeted attachment-heavy improvement. It should reduce repeated decrypt/read work when photo attachments are visible in multiple surfaces during the same app session.

## Cycle 10 follow-up

Plan:

- Reduce save latency for large local databases on iOS/Android/desktop.
- Avoid full-database re-encryption when a single note is created, edited, or tombstoned.

Changes:

- Added `EncryptedNoteDatabase.upsertOne` to update one encrypted note record, its attachment metadata, and its pending sync queue entry in one transaction.
- Added `EncryptedNoteStore.saveOne` for native incremental persistence.
- Updated `NotesController.upsert` and normal delete/tombstone handling to call the incremental path on native platforms.
- Kept Web on the existing full-save path because Web storage is still a single encrypted payload.

Measurements:

- `flutter analyze` passed.
- `flutter test test\security_storage_test.dart` passed, including attachment cleanup, sync metadata, tombstone delete, and sync merge tests.

Conclusion:

- This is a high-impact native-path improvement for large note sets. Editing one note no longer requires encrypting and replacing every note in the local SQLite database.
- Remaining large-data bottleneck is Web storage, which still stores all notes in one encrypted blob.

## Cycle 11 follow-up

Plan:

- Reduce one-time bulk persistence cost for native local databases.
- Improve initial demo/performance seed insertion, sync restore, and full replacement paths.

Changes:

- Replaced per-row awaited inserts in `EncryptedNoteDatabase.replaceAll` with Drift batch inserts.
- Batched note records, attachment metadata records, and pending sync queue records inside the existing transaction.

Measurements:

- `flutter analyze` passed.
- `flutter test test\security_storage_test.dart` passed.

Conclusion:

- Full replacements still encrypt each note individually, but database writes are now grouped rather than awaited one row at a time.
- This complements Cycle 10: routine edits use incremental persistence, while unavoidable full replacements have lower database write overhead.

## Cycle 12 follow-up

Plan:

- Make future performance cycles easier to measure without adding external profilers.
- Separate restore, full persist, and single-note persist timings in debug logs.

Changes:

- Added debug-only `[home-perf]` logs for note restore, full persistence, and incremental one-note persistence.
- Included note counts, note IDs, attachment counts, and elapsed milliseconds where relevant.

Measurements:

- `flutter analyze` passed.
- `flutter test test\security_storage_test.dart --plain-name "NotesController writes sync metadata and tombstones deletes"` passed.
- The targeted test emitted restore and single-note persistence timings, confirming the instrumentation path works.

Conclusion:

- This does not directly speed up release builds, but it gives the next cycles clearer measurements for 1000+ note scenarios and validates that Cycle 10 is exercising the incremental path.

## Cycle 13 follow-up

Plan:

- Check note detail performance beyond the list itself.
- Improve the case where a note has many blocks or many attachments.

Changes:

- Replaced the detail pane's eager `SingleChildScrollView` + `Column` content construction with a `CustomScrollView` and `SliverList.builder`.
- Kept the metadata header eager, but made body blocks, location cards, and embedded attachments build lazily as they enter the viewport.

Measurements:

- `flutter analyze` passed.
- `flutter test test\app_test.dart --plain-name "search filters can partition notes by year"` passed.

Conclusion:

- Multi-attachment detail pages no longer instantiate every embedded attachment viewer during the first frame.
- This should reduce detail-open latency and memory pressure for notes with many images, videos, audio clips, or files.

## Cycle 14 follow-up

Plan:

- Check long text display performance in note details.
- Avoid repeating URL regex scans and tap recognizer allocation on every rebuild.

Changes:

- Cached parsed memo text segments inside `_LinkifiedMemoTextState`.
- Re-parse and recreate recognizers only when the source text changes.
- Kept theme-dependent link styling in `build` so color changes still apply without re-parsing text.

Measurements:

- `flutter analyze` passed.
- `flutter test test\app_test.dart --plain-name "widget quick capture stores first line only as title"` passed.

Conclusion:

- Long notes with URLs should rebuild more cheaply, especially when theme, selection, or parent layout changes trigger a detail rebuild without changing the note text.

## Cycle 15 follow-up

Plan:

- Check long text behavior in both note display and rich editor creation paths.
- Avoid treating every normal paragraph as a possible legacy location memo.

Changes:

- Added a heading guard to `_tryParseLocationMemo`.
- Normal text now returns before newline normalization, splitting, list allocation, and URL regex checks.

Measurements:

- `flutter analyze` passed.
- `flutter test test\app_test.dart --plain-name "note attachments preserve media duration metadata"` passed.

Conclusion:

- Long ordinary paragraphs are cheaper to render and edit.
- Legacy embedded location text is still supported when the paragraph starts with the expected current-location heading.

## Cycle 16 follow-up

Plan:

- Check note creation and edit performance for notes with many attachments.
- Reduce per-save latency from attachment metadata encryption.

Changes:

- Added a shared `_encryptAttachmentRecords` helper in `EncryptedNoteStore`.
- Encrypt attachment metadata for a single note with `Future.wait` instead of awaiting each attachment sequentially.
- Reused the helper for both full native save and incremental native `saveOne`.

Measurements:

- `dart format` applied to the touched store file.
- `flutter analyze` passed.
- `flutter test test\security_storage_test.dart --plain-name "EncryptedNoteStore persists and restores notes without plaintext leakage"` passed.

Conclusion:

- Notes with many attachments should save faster on native platforms because attachment metadata encryption can overlap.
- The encrypted attachment bytes themselves remain protected by the existing attachment store path.

## Cycle 17 follow-up

Plan:

- Add coverage for the long-text and many-attachment case so future performance work does not regress correctness.
- Validate the incremental native save path with a heavier note shape than normal unit fixtures.

Changes:

- Added a storage test that saves one note with 220 text lines, 40 attachments, and matching rich blocks through `EncryptedNoteStore.saveOne`.
- Verified restore equality, encrypted attachment metadata count, and absence of plaintext in encrypted note/attachment payloads.

Measurements:

- `dart format` applied to the touched test file.
- `flutter analyze` passed.
- `flutter test test\security_storage_test.dart --plain-name "incrementally persists notes with long text and many attachments"` passed.

Conclusion:

- The multi-attachment incremental persistence path is now covered by a targeted regression test.
