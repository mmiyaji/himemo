# Android Sync Debug Playbook

Last updated: 2026-05-11

This document captures the Android emulator workflow used to debug HiMemo cloud sync convergence. It is intended for future Codex sessions and local debugging.

## Goal

Verify Google Drive production-flavor sync on multiple Android emulators with minimal user-visible sync operations.

Primary checks:

- latest APK is installed on both emulators
- Google Drive app-data sync can run in production flavor
- local pending queues drain to zero
- note revisions and content hashes converge across devices
- attachments remain present after sync
- stale remote bundles do not overwrite newer local notes
- newer local notes are republished automatically during seamless sync

## Required Environment

- Android SDK platform tools: `D:\Android\Sdk\platform-tools\adb.exe`
- Flutter/FVM environment able to build this repository
- At least two online emulators
- Google Drive sync enabled in the app on both emulators
- Production flavor build, because Google Drive sync is enabled only for production

Known emulator setup used during debugging:

- phone: `emulator-5554`
- tablet: `emulator-5556`

Check devices:

```powershell
D:\Android\Sdk\platform-tools\adb.exe devices -l
```

Ignore offline entries such as physical devices that appear as `offline`.

## Build APK

Use production debug with local diagnostic flags for App Check / Play Integrity:

```powershell
flutter build apk --debug --flavor production -t lib/main_production.dart `
  --dart-define=HIMEMO_USE_DEBUG_APP_CHECK_FOR_LOCAL_PRODUCTION=true `
  --dart-define=HIMEMO_SKIP_PLAY_INTEGRITY_FOR_LOCAL_PRODUCTION=true
```

Output:

```text
build\app\outputs\flutter-apk\app-production-debug.apk
```

### Build A One-Time Sync Load APK

For Google Drive performance checks, build a temporary production debug APK that seeds synthetic load on launch. Install it on only one emulator, launch once, sync, then reinstall the normal APK above. This avoids both devices generating the same test IDs independently.

```powershell
flutter build apk --debug --flavor production -t lib/main_production.dart `
  --dart-define=HIMEMO_USE_DEBUG_APP_CHECK_FOR_LOCAL_PRODUCTION=true `
  --dart-define=HIMEMO_SKIP_PLAY_INTEGRITY_FOR_LOCAL_PRODUCTION=true `
  --dart-define=HIMEMO_PERF_NOTE_COUNT=30 `
  --dart-define=HIMEMO_PERF_ATTACHMENTS_PER_NOTE=3
```

Observed 2026-05-11 result:

```text
tablet seed: 34 notes, 91 attachments, 30 pending uploads
tablet manual Sync: pending 0 after the first 10-second poll
phone seamless apply: 34 notes, 91 attachments, pending 0
```

Performance seed attachments are synthetic image/video/audio payloads intended for sync throughput testing, not media playback quality checks.

## Install And Launch

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
$apk = 'build\app\outputs\flutter-apk\app-production-debug.apk'

foreach ($device in @('emulator-5554', 'emulator-5556')) {
  & $adb -s $device install -r $apk
  & $adb -s $device shell am force-stop org.ruhenheim.himemo
  & $adb -s $device shell am start -n org.ruhenheim.himemo/.MainActivity
}
```

Wait 20-30 seconds after launch for seamless sync.

## Pull Local Database

The app database is inside the app sandbox:

```text
/data/data/org.ruhenheim.himemo/files/himemo_notes.sqlite
```

Pull snapshots:

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'

cmd /c "$adb -s emulator-5554 exec-out run-as org.ruhenheim.himemo cat /data/data/org.ruhenheim.himemo/files/himemo_notes.sqlite > %TEMP%\himemo-5554.sqlite"
cmd /c "$adb -s emulator-5556 exec-out run-as org.ruhenheim.himemo cat /data/data/org.ruhenheim.himemo/files/himemo_notes.sqlite > %TEMP%\himemo-5556.sqlite"
```

Inspect notes, attachments, and pending queue:

```powershell
@'
import os
import sqlite3

files = {
    '5554': r'%TEMP%\himemo-5554.sqlite',
    '5556': r'%TEMP%\himemo-5556.sqlite',
}

for device, raw_path in files.items():
    path = os.path.expandvars(raw_path)
    con = sqlite3.connect(path)
    cur = con.cursor()
    print('---', device)
    print('notes', cur.execute(
        'select id,revision,sync_state,substr(content_hash,1,12) '
        'from encrypted_notes order by cast(id as integer)'
    ).fetchall())
    print('attachments', cur.execute(
        'select count(*) from encrypted_note_attachments'
    ).fetchone()[0])
    print('pending', cur.execute(
        'select note_id,revision,sync_action,substr(content_hash,1,12) '
        'from pending_note_changes order by note_id'
    ).fetchall())
    con.close()
'@ | python -
```

Expected final healthy state:

- same note IDs on both devices
- same revision/content hash for each shared note
- same attachment count
- `pending_note_changes` count is `0`
- no note remains in `pendingUpload`, `pendingDelete`, or `conflict`

## Inspect Sync State Preferences

The sync bundle metadata is stored in shared preferences:

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'

foreach ($device in @('emulator-5554', 'emulator-5556')) {
  Write-Host "--- $device sync state"
  & $adb -s $device shell run-as org.ruhenheim.himemo `
    grep -R sync.bundle_state /data/data/org.ruhenheim.himemo/shared_prefs/FlutterSharedPreferences.xml

  Write-Host "--- $device device id"
  & $adb -s $device shell run-as org.ruhenheim.himemo `
    grep -R sync.device_id /data/data/org.ruhenheim.himemo/shared_prefs/FlutterSharedPreferences.xml
}
```

Important fields:

- `lastRemoteFileId`
- `lastRemoteModifiedAt`
- `lastRemoteDeviceId`
- `lastUploadedAt`
- `lastAppliedAt`

`lastRemoteFileId` means the latest remote was observed, not necessarily applied. Apply/upload timestamps determine whether a remote bundle should be acted on.

Automatic seamless sync stores its last attempt timestamp here:

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
& $adb -s emulator-5554 shell run-as org.ruhenheim.himemo `
  grep -R runtime.cloud_sync_automatic_synced_at /data/data/org.ruhenheim.himemo/shared_prefs/FlutterSharedPreferences.xml
```

Normal automatic sync is throttled to once per hour per device to reduce Google Drive API usage. Manual Sync remains immediate.

## UI Dump Helpers

Use UI Automator when coordinates are uncertain:

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
$device = 'emulator-5554'

& $adb -s $device shell uiautomator dump /sdcard/window.xml | Out-Null
& $adb -s $device pull /sdcard/window.xml "$env:TEMP\ui-$device.xml" | Out-Null
Select-String -Path "$env:TEMP\ui-$device.xml" `
  -Pattern 'Backup and sync|Selected target|Authentication|Sync|Details|Re-upload|Remote bundle|Pending sync|Google Drive'
```

Take a screenshot if needed:

```powershell
$adb = 'D:\Android\Sdk\platform-tools\adb.exe'
$device = 'emulator-5554'

& $adb -s $device shell screencap -p /sdcard/himemo-screen.png
& $adb -s $device pull /sdcard/himemo-screen.png "$env:TEMP\himemo-screen.png"
```

## Manual Sync Test Cases

### 1. Baseline Launch Sync

1. Install the latest APK on both emulators.
2. Force-stop and launch both.
3. Wait 20-30 seconds.
4. Pull both DBs.
5. Confirm both devices have the same note IDs, attachment counts, and no pending queue.

### 2. Phone To Tablet New Note

1. On phone, create a new note.
2. Confirm phone DB shows the new note as `pendingUpload` and one pending `upsert`.
3. Trigger Sync or restart the app and wait for seamless sync.
4. Confirm phone DB changes the new note to `synced` and pending queue becomes empty.
5. Restart tablet and wait for seamless sync.
6. Confirm tablet DB contains the new note, `synced`, with pending queue empty.

### 3. Tablet To Phone New Note

Same as above, reversing the devices.

During one tablet test, a transient Android screen showed `Item not found`. Restarting the app recovered and the pending note was synced. If this recurs, keep the DB snapshot before restarting.

### 4. Stale Remote Bundle Convergence

This is the key case for seamless sync convergence.

1. Ensure tablet has a newer version of an existing note than phone.
2. From phone, use Settings > Backup and sync > Details > Re-upload all notes.
3. Confirm phone uploads a new remote bundle and remains `synced`.
4. Restart tablet and wait 20-30 seconds.
5. Confirm tablet keeps its newer note revision and briefly queues it as `pendingUpload` if the remote is stale.
6. Confirm tablet automatically uploads the newer local version and returns to `synced` / pending `0`.
7. Restart phone and wait 20-30 seconds.
8. Confirm phone applies the tablet-republished version and converges to the same revision/hash.

Final expected state observed after the fix:

```text
phone  4 notes, 1 attachment, pending 0
tablet 4 notes, 1 attachment, pending 0

target note:
revision 4
hash ab275d04ee31
sync_state synced
```

## Useful Button Coordinates

Coordinates vary with layout, locale, and scroll position. Prefer UI dumps first.

Common phone coordinates observed on `emulator-5554`:

- bottom Settings tab: around `(945, 2230)`
- Backup and sync card when visible: around `(540, 1390)`
- top Sync button in expanded backup section: around `(540, 1480)` or `(540, 741)` depending on scroll
- Details row: around `(540, 1690)` or `(540, 949)` depending on scroll
- Re-upload all notes when visible: around `(365, 1320)` or `(365, 1990)` depending on scroll
- Re-upload confirmation: around `(765, 1505)`

Common tablet coordinates observed on `emulator-5556`:

- left Settings nav: around `(220, 690)`
- Backup and sync card: around `(1500, 1495)`
- Sync button in expanded section: around `(1537, 829)` or `(1535, 1478)` depending on scroll

Always verify with `uiautomator dump` before destructive actions such as `Re-upload all notes`.

## Diagnostic Logging

Hidden diagnostic logging can be toggled inside the app:

1. Settings tab
2. App information
3. Tap the app version section 5 times within 5 seconds
4. Logging mode is toggled
5. A log section appears near the bottom of Settings

Use this when diagnosing cloud sync timing and remote bundle decisions.

## Validation Commands

Run focused tests:

```powershell
flutter test test\security_storage_test.dart
```

Run analyzer:

```powershell
flutter analyze
```

Build/install after code changes before emulator validation.

## Known Pitfalls

- Google Drive sync is only enabled in production flavor.
- App Check / Play Integrity can block local production debug builds unless the local debug dart defines are used.
- A remote bundle status refresh must not be treated as a completed apply.
- If a device receives a stale remote bundle while its local note is newer, the local note should be queued and republished automatically.
- A note can show `synced` on both devices while revisions/hashes differ if convergence did not run correctly. Always compare `(id, revision, sync_state, content_hash)`, not only pending queue count.
- Attachment table only stores `note_id`, `position`, and `encrypted_payload`; do not query a nonexistent `payload_hash` column.
- `lastRemoteFileId` alone is not proof that the bundle was applied. Check `lastAppliedAt` / `lastUploadedAt` and DB content.
