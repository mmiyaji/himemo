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
