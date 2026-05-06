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
