import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[Locale('en'), Locale('ja')];

  static const delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    final value = Localizations.of<AppStrings>(context, AppStrings);
    assert(value != null, 'AppStrings not found in context');
    return value!;
  }

  bool get isJapanese => locale.languageCode == 'ja';

  static const _localizedValues = <String, Map<String, String>>{
    'en': {
      'action.delete': 'Delete',
      'date.yesterday': 'Yesterday',
      'date.weekday.mon.short': 'Mon',
      'date.weekday.tue.short': 'Tue',
      'date.weekday.wed.short': 'Wed',
      'date.weekday.thu.short': 'Thu',
      'date.weekday.fri.short': 'Fri',
      'date.weekday.sat.short': 'Sat',
      'date.weekday.sun.short': 'Sun',
      'date.month.1': 'January',
      'date.month.2': 'February',
      'date.month.3': 'March',
      'date.month.4': 'April',
      'date.month.5': 'May',
      'date.month.6': 'June',
      'date.month.7': 'July',
      'date.month.8': 'August',
      'date.month.9': 'September',
      'date.month.10': 'October',
      'date.month.11': 'November',
      'date.month.12': 'December',
      'notes.empty.title': 'No matching notes',
      'notes.empty.body':
          'Create a new memo or clear the current search filter to see saved entries.',
      'home.admin.mode.active': 'Admin mode active',
      'home.switch.private.access': 'Switch private access',
      'home.lock': 'Lock',
      'home.unlock': 'Unlock',
      'home.delete.note': 'Delete note',
      'home.delete': 'Delete',
      'home.previous.month': 'Previous month',
      'home.next.month': 'Next month',
      'home.writing.activity': 'Writing activity',
      'home.monthly.notes': 'Monthly notes',
      'home.notes': ' notes',
      'home.recent.days': 'Recent days',
      'home.weekday.and.time.rhythm': 'Weekday and time rhythm',
      'home.attachments': 'Attachments',
      'home.items': ' items',
      'home.current.streak': 'Current streak',
      'home.days': 'days',
      'home.this.month': 'This month',
      'home.notes.2': 'notes',
      'home.characters': 'Characters',
      'home.total': 'total',
      'home.items.2': 'items',
      'home.best.day': 'Best day',
      'home.best.hour': 'Best hour',
      'home.peak.time': 'peak time',
      'home.monthly.trend': 'Monthly trend',
      'home.vs.last.month': 'vs last month',
      'home.no.data.yet': 'No data yet.',
      'home.less': 'Less',
      'home.more': 'More',
      'home.photo': 'Photo',
      'home.video': 'Video',
      'home.audio': 'Audio',
      'home.reset': 'Reset',
      'home.add.private.profile': 'Add private profile',
      'home.profile.name': 'Profile name',
      'home.add': 'Add',
      'home.new.password': 'New password',
      'home.confirm.new.password': 'Confirm new password',
      'home.normal.memo.mode': 'Normal memo mode',
      'home.device.only.storage': 'Device-only storage',
      'home.mode': 'Mode',
      'home.enabled': 'Enabled',
      'home.disabled': 'Disabled',
      'home.off': 'Off',
      'home.configured': 'Configured',
      'home.theme': 'Theme',
      'home.access.modes': 'Access modes',
      'home.current.mode': 'Current mode',
      'home.app.security': 'App security',
      'home.save.pin': 'Save PIN',
      'home.session.status': 'Session status',
      'home.update.pin': 'Update PIN',
      'home.change.pin': 'Change PIN',
      'home.set.pin': 'Set PIN',
      'home.remove': 'Remove',
      'home.remove.pin': 'Remove PIN',
      'home.immediately': 'Immediately',
      'home.after.30.seconds': 'After 30 seconds',
      'home.after.2.minutes': 'After 2 minutes',
      'home.after.10.minutes': 'After 10 minutes',
      'home.authenticate.now': 'Authenticate now',
      'home.lock.session.now': 'Lock session now',
      'home.external.quick.memo': 'External quick memo',
      'home.write.target': 'Write target',
      'home.private.vault': 'Private vault',
      'home.status': 'Status',
      'home.set.private.key': 'Set private key',
      'home.backup.and.sync': 'Backup and sync',
      'home.selected.target': 'Selected target',
      'home.pending.sync.queue': 'Pending sync queue',
      'home.queue.ready': 'queue ready',
      'home.remote.bundle': 'Remote bundle',
      'home.copy.recovery.key': 'Copy recovery key',
      'home.last.sync.activity': 'Last sync activity',
      'home.local.bundle.cache': 'Local bundle cache',
      'home.refresh.remote': 'Refresh remote',
      'home.upload.bundle': 'Upload bundle',
      'home.force.upload': 'Force upload',
      'home.bundle.history': 'Bundle history',
      'home.download.bundle': 'Download bundle',
      'home.review.bundle': 'Review bundle',
      'home.apply.bundle': 'Apply bundle',
      'home.inspect.snapshot': 'Inspect snapshot',
      'home.storage': 'Storage',
      'home.cancel': 'Cancel',
      'home.icloud.availability': 'iCloud availability',
      'home.authentication': 'Authentication',
      'home.check.icloud': 'Check iCloud',
      'home.connect': 'Connect',
      'home.check.again': 'Check again',
      'home.reconnect': 'Reconnect',
      'home.stop.using.icloud': 'Stop using iCloud',
      'home.disconnect': 'Disconnect',
      'home.sync.is.disabled': 'Sync is disabled.',
      'home.previous.note': 'Previous note',
      'home.next.note': 'Next note',
      'home.previous.image': 'Previous image',
      'home.next.image': 'Next image',
      'home.restore.frame': 'Restore frame',
      'home.maximize': 'Maximize',
      'home.zoom.out': 'Zoom out',
      'home.zoom.in': 'Zoom in',
      'home.fit.to.screen': 'Fit to screen',
      'home.share': 'Share',
      'home.pause.audio': 'Pause audio',
      'home.play.audio': 'Play audio',
      'home.list.layout': 'List layout',
      'home.standard.list': 'Standard list',
      'home.compact.list': 'Compact list',
      'home.filters': 'Filters',
      'home.pinned.only': 'Pinned only',
      'home.with.media': 'With media',
      'home.vault': 'Vault',
      'home.filter.by.tag': 'Filter by tag',
      'home.reset.filters': 'Reset filters',
      'home.select.a.note': 'Select a note',
      'home.private.profile': 'Private profile',
      'home.tags': 'Tags',
      'home.add.a.tag': 'Add a tag',
      'home.tap.to.open.image': 'Tap to open image',
      'home.unknown.time': 'unknown time',
      'home.size.unknown': 'size unknown',
      'home.bundle.review': 'Bundle review',
      'home.added.notes': 'Added notes',
      'home.updated.notes': 'Updated notes',
      'home.remote.bundle.history': 'Remote bundle history',
      'home.unknown.time.2': 'Unknown time',
      'home.unknown.device': 'Unknown device',
      'home.import.recovery.key': 'Import recovery key',
      'home.import': 'Import',
      'home.confirm.pin': 'Confirm PIN',
      'home.unlock.private.profile': 'Unlock private profile',
      'home.no.private.profile.matched.that.password':
          'No private profile matched that password.',
      'home.private.profile.unlocked': 'Private profile unlocked.',
      'home.unlock.private.profile.2': 'Unlock private profile',
      'home.admin.mode.is.currently.active': 'Admin mode is currently active.',
      'home.profile.password': 'Profile password',
      'home.enter.a.password': 'Enter a password.',
      'home.review.notes.grouped.by.day.and.keep.diary.entries.ancho':
          'Review notes grouped by day and keep diary entries anchored to dates.',
      'home.previous.day.with.notes': 'Previous day with notes',
      'home.next.day.with.notes': 'Next day with notes',
      'home.no.notes.on.this.day.yet': 'No notes on this day yet.',
      'home.previous.day.with.notes.2': 'Previous day with notes',
      'home.next.day.with.notes.2': 'Next day with notes',
      'home.notes.created.over.the.last.6.months':
          'Notes created over the last 6 months.',
      'home.daily.note.count.over.the.last.14.days':
          'Daily note count over the last 14 days.',
      'home.notes.by.weekday.and.3.hour.time.block':
          'Notes by weekday and 3-hour time block.',
      'home.how.often.photos.videos.and.audio.are.used':
          'How often photos, videos, and audio are used.',
      'home.alternate.profile.password': 'Alternate profile password',
      'home.confirm.alternate.profile.password':
          'Confirm alternate profile password',
      'home.use.this.password.to.switch.to.a.different.everyday.prof':
          'Use this password to switch to a different everyday profile.',
      'home.alternate.profile.password.saved':
          'Alternate profile password saved.',
      'home.this.removes.the.configured.password.for.the.alternate.p':
          'This removes the configured password for the alternate profile.',
      'home.profile.password.2': 'Profile password',
      'home.enter.a.password.2': 'Enter a password.',
      'home.confirm.password': 'Confirm password',
      'home.passwords.do.not.match': 'Passwords do not match.',
      'home.private.profile.added.and.opened':
          'Private profile added and opened.',
      'home.admin.mode.is.not.available.in.this.environment':
          'Admin mode is not available in this environment.',
      'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h':
          'Admin mode unlocked. Profile names and vault IDs remain hidden.',
      'home.change.current.profile.password': 'Change current profile password',
      'home.update.the.password.used.to.unlock.this.profile':
          'Update the password used to unlock this profile.',
      'home.profile.password.updated': 'Profile password updated.',
      'home.off.turning.this.on.asks.for.a.password.or.device.authen':
          'Off. Turning this on asks for a password or device authentication.',
      'home.on.this.session.is.unlocked': 'On. This session is unlocked.',
      'home.on.this.session.is.locked': 'On. This session is locked.',
      'home.manage.access.sync.and.display.policy':
          'Manage access, sync, and display policy.',
      'home.change.current.profile.password.2':
          'Change current profile password',
      'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe':
          'The app stays in normal memo mode by default. Enter a special access key only when you need another view.',
      'home.enter.special.access.key': 'Enter special access key',
      'home.return.to.normal.mode': 'Return to normal mode',
      'home.require.pin.on.launch': 'Require PIN on launch',
      'home.require.device.auth.on.launch': 'Require device auth on launch',
      'home.set.unlock.pin': 'Set unlock PIN',
      'home.device.authentication.was.not.completed.so.launch.protec':
          'Device authentication was not completed, so launch protection stayed off.',
      'home.when.icloud.sync.is.selected.this.key.is.shared.automati':
          'When iCloud sync is selected, this key is shared automatically across Apple devices signed in with the same iCloud account. Manual transfer is not required.',
      'home.this.session.is.currently.unlocked':
          'This session is currently unlocked.',
      'home.this.browser.stays.locked.until.the.correct.pin.is.enter':
          'This browser stays locked until the correct PIN is entered.',
      'home.this.session.stays.locked.until.device.authentication.su':
          'This session stays locked until device authentication succeeds.',
      'home.change.unlock.pin': 'Change unlock PIN',
      'home.set.unlock.pin.2': 'Set unlock PIN',
      'home.unlock.pin.updated': 'Unlock PIN updated.',
      'home.unlock.pin.configured': 'Unlock PIN configured.',
      'home.remove.unlock.pin': 'Remove unlock PIN',
      'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off':
          'Remove the web unlock PIN for this browser and turn off launch PIN protection?',
      'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla':
          'Web PIN is a browser-level access gate. It does not replace device-backed secure storage or biometrics.',
      'home.quick.widget.capture.only.writes.plain.text.into.notes.i':
          'Quick widget capture only writes plain text into Notes. It never opens existing notes or locked profiles.',
      'home.re.lock.after.app.leaves.the.foreground':
          'Re-lock after app leaves the foreground',
      'home.lock.the.app.as.soon.as.it.moves.to.the.background':
          'Lock the app as soon as it moves to the background.',
      'home.allow.quick.app.switching.without.immediate.re.auth':
          'Allow quick app switching without immediate re-auth.',
      'home.useful.when.capturing.photos.or.audio.between.notes':
          'Useful when capturing photos or audio between notes.',
      'home.keep.the.app.open.during.longer.editing.sessions':
          'Keep the app open during longer editing sessions.',
      'home.lock.legacy.private.area.when.app.locks':
          'Lock legacy private area when app locks',
      'home.normally.this.locks.whenever.the.app.locks':
          'Normally this locks whenever the app locks.',
      'home.pin.unlock.on.lock.screen': 'PIN unlock on lock screen',
      'home.web.pin.active': 'Web PIN active',
      'home.refresh.availability': 'Refresh availability',
      'home.widget.quick.writes.are.allowed.while.the.app.is.locked':
          'Widget quick writes are allowed while the app is locked.',
      'home.widget.quick.writes.are.off': 'Widget quick writes are off.',
      'home.allow.widget.writes.while.locked':
          'Allow widget writes while locked',
      'home.only.the.submitted.text.is.saved.existing.notes.and.lock':
          'Only the submitted text is saved. Existing notes and locked profiles stay hidden.',
      'home.configured.and.currently.unlocked':
          'Configured and currently unlocked.',
      'home.configured.and.locked': 'Configured and locked.',
      'home.no.private.vault.key.has.been.set.yet':
          'No private vault key has been set yet.',
      'home.configured.and.unlocked.for.this.session':
          'Configured and unlocked for this session.',
      'home.configured.and.locked.a.separate.key.is.required':
          'Configured and locked. A separate key is required.',
      'home.not.configured.yet.set.a.separate.key.for.the.private.va':
          'Not configured yet. Set a separate key for the private vault.',
      'home.unlock.private.vault': 'Unlock private vault',
      'home.lock.private.vault': 'Lock private vault',
      'home.reset.private.key': 'Reset private key',
      'home.no.pending.device.changes': 'No pending device changes.',
      'home.checking.pending.changes': 'Checking pending changes...',
      'home.unable.to.inspect.the.local.sync.queue':
          'Unable to inspect the local sync queue.',
      'home.cloud.recovery.key.fingerprint': 'Cloud recovery key fingerprint',
      'home.preparing.cloud.recovery.key': 'Preparing cloud recovery key...',
      'home.unable.to.read.the.cloud.recovery.key.fingerprint':
          'Unable to read the cloud recovery key fingerprint.',
      'home.cloud.recovery.key.copied.to.clipboard':
          'Cloud recovery key copied to clipboard.',
      'home.no.sync.activity.has.been.recorded.on.this.device.yet':
          'No sync activity has been recorded on this device yet.',
      'home.reading.sync.activity': 'Reading sync activity...',
      'home.unable.to.read.local.sync.activity':
          'Unable to read local sync activity.',
      'home.keep.data.on.this.device.only': 'Keep data on this device only.',
      'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo':
          'Use this device’s iCloud as the sync target. No HiMemo login is required.',
      'home.google.drive.app.data.sync.target':
          'Google Drive app-data sync target.',
      'home.force.upload.2': 'Force upload?',
      'home.a.newer.remote.bundle.was.found.while.this.device.still':
          'A newer remote bundle was found while this device still has pending changes. Force upload will overwrite the remote backup with this device state.',
      'home.no.remote.bundle.history.is.available':
          'No remote bundle history is available.',
      'home.keep.for.apply': 'Keep for apply',
      'home.selected.bundle.is.ready.for.apply':
          'Selected bundle is ready for apply.',
      'home.prepared.sync.snapshot': 'Prepared sync snapshot',
      'home.saved.notes.on.this.device': 'Saved notes on this device',
      'home.use.japanese.across.the.app': 'Use Japanese across the app.',
      'home.use.english.across.the.app': 'Use English across the app.',
      'home.icloud.selected.the.app.checks.this.device.s.icloud.avai':
          'iCloud selected. The app checks this device’s iCloud availability before syncing. No HiMemo login is required.',
      'home.google.drive.selected.authorize.access.to.drive.app.data':
          'Google Drive selected. Authorize access to Drive app data before syncing.',
      'home.this.device.s.icloud.availability.has.not.been.checked.y':
          'This device’s iCloud availability has not been checked yet.',
      'home.checking.this.device.s.icloud.availability':
          'Checking this device’s iCloud availability...',
      'home.this.device.can.use.icloud.as.the.himemo.sync.target':
          'This device can use iCloud as the HiMemo sync target.',
      'home.icloud.sync.is.not.available.on.this.device':
          'iCloud sync is not available on this device.',
      'home.no.cloud.account.is.connected': 'No cloud account is connected.',
      'home.no.account.connected.yet': 'No account connected yet.',
      'home.waiting.for.authentication.to.complete':
          'Waiting for authentication to complete...',
      'home.authentication.is.not.available':
          'Authentication is not available.',
      'home.no.cloud.account.is.connected.2': 'No cloud account is connected.',
      'home.no.account.connected.yet.2': 'No account connected yet.',
      'home.waiting.for.authentication.to.complete.2':
          'Waiting for authentication to complete...',
      'home.authentication.is.not.available.2':
          'Authentication is not available.',
      'home.locked.profiles.are.hidden.unlock.the.target.profile.fro':
          'Locked profiles are hidden. Unlock the target profile from Settings to show its notes.',
      'home.swipe.left.or.right.to.move.between.notes':
          'Swipe left or right to move between notes.',
      'home.search.notes.diary.entries.and.attachment.labels':
          'Search notes, diary entries, and attachment labels',
      'home.search.terms.are.cleared.when.private.mode.closes':
          'Search terms are cleared when private mode closes.',
      'home.all.visible.vaults': 'All visible vaults',
      'home.add.tags.to.narrow.the.list': 'Add tags to narrow the list',
      'home.pick.a.note.from.the.list.to.preview.it.here':
          'Pick a note from the list to preview it here.',
      'home.type.a.tag.and.press.enter': 'Type a tag and press enter',
      'home.save.to.private.profile': 'Save to private profile',
      'home.choose.which.private.profile.to.save.into.while.in.admin':
          'Choose which private profile to save into while in admin mode.',
      'home.save.into.the.currently.unlocked.private.profile':
          'Save into the currently unlocked private profile.',
      'home.remote.bundle.storage.is.not.configured.yet':
          'Remote bundle storage is not configured yet.',
      'home.no.icloud.bundle.metadata.loaded.yet':
          'No iCloud bundle metadata loaded yet.',
      'home.remote.bundle.transport.is.not.available.yet':
          'Remote bundle transport is not available yet.',
      'home.remote.bundle.storage.is.not.configured.yet.2':
          'Remote bundle storage is not configured yet.',
      'home.no.icloud.bundle.metadata.loaded.yet.2':
          'No iCloud bundle metadata loaded yet.',
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r':
          'Remote bundle transport is only wired for Google Drive right now.',
      'home.no.remote.bundle.metadata.loaded.yet':
          'No remote bundle metadata loaded yet.',
      'home.removed.locally.after.apply': 'Removed locally after apply',
      'home.paste.himemo.sync.key.v1': 'Paste himemo-sync-key-v1:...',
      'home.use.a.4.digit.pin.for.this.browser':
          'Use a 4 digit PIN for this browser.',
      'home.pin.must.be.exactly.4.digits': 'PIN must be exactly 4 digits.',
      'home.pin.must.contain.digits.only': 'PIN must contain digits only.',
      'home.pin.confirmation.did.not.match': 'PIN confirmation did not match.',
      'settings.demo.create': 'Create demo notes',
      'settings.demo.create.none': 'No demo notes to create.',
      'settings.demo.create.done': 'Created {count} demo notes.',
      'settings.demo.delete': 'Delete demo notes',
      'settings.demo.delete.title': 'Delete demo notes?',
      'settings.demo.delete.body':
          'This deletes {count} demo notes from this device. Notes you created are not deleted.',
      'settings.demo.delete.done': 'Deleted {count} demo notes.',
    },
    'ja': {
      'action.delete': '削除',
      'date.yesterday': '昨日',
      'date.weekday.mon.short': '月',
      'date.weekday.tue.short': '火',
      'date.weekday.wed.short': '水',
      'date.weekday.thu.short': '木',
      'date.weekday.fri.short': '金',
      'date.weekday.sat.short': '土',
      'date.weekday.sun.short': '日',
      'notes.empty.title': '一致するノートはありません',
      'notes.empty.body': '新しいメモを作成するか、現在の検索条件を解除すると保存済みのノートを表示できます。',
      'home.admin.mode.active': '管理者モード中',
      'home.switch.private.access': 'プライベート表示を切り替え',
      'home.lock': '閉じる',
      'home.unlock': '開く',
      'home.delete.note': 'ノートを削除',
      'home.delete': '削除',
      'home.previous.month': '前の月',
      'home.next.month': '次の月',
      'home.writing.activity': '記録のまとめ',
      'home.monthly.notes': '月ごとのノート数',
      'home.notes': '件',
      'home.recent.days': '直近の日別推移',
      'home.notes.2': '件',
      'home.weekday.and.time.rhythm': '曜日と時間帯の傾向',
      'home.notes.3': '件',
      'home.attachments': '添付メディア',
      'home.items': '件',
      'home.current.streak': '連続記録',
      'home.days': '日',
      'home.this.month': '今月',
      'home.notes.4': '件',
      'home.characters': '文字数',
      'home.total': '累計',
      'home.attachments.2': '添付数',
      'home.items.2': '件',
      'home.best.day': '最も書いた日',
      'home.best.hour': '記録しやすい時間',
      'home.peak.time': 'ピーク',
      'home.monthly.trend': '前月比',
      'home.vs.last.month': '先月比',
      'home.no.data.yet': 'まだデータがありません。',
      'home.less': '少',
      'home.more': '多',
      'home.no.data.yet.2': 'まだデータがありません。',
      'home.photo': '写真',
      'home.video': '動画',
      'home.audio': '音声',
      'home.reset': 'リセット',
      'home.add.private.profile': 'プライベートプロファイルを追加',
      'home.profile.name': '表示名',
      'home.add': '追加',
      'home.new.password': '新しいパスワード',
      'home.confirm.new.password': '新しいパスワードを確認',
      'home.normal.memo.mode': '通常メモモード',
      'home.device.only.storage': 'この端末のみ',
      'home.mode': 'モード',
      'home.unlock.2': 'ロック',
      'home.enabled': '有効',
      'home.disabled': '無効',
      'home.off': 'オフ',
      'home.configured': '設定済み',
      'home.theme': 'テーマ',
      'home.access.modes': 'アクセスモード',
      'home.current.mode': '現在のモード',
      'home.normal.memo.mode.2': '通常メモモード',
      'home.app.security': 'アプリ保護',
      'home.save.pin': 'PIN を保存',
      'home.session.status': 'セッション状態',
      'home.update.pin': 'PIN を更新',
      'home.save.pin.2': 'PIN を保存',
      'home.change.pin': 'PIN を変更',
      'home.set.pin': 'PIN を設定',
      'home.remove': '削除',
      'home.remove.pin': 'PIN を削除',
      'home.immediately': 'すぐに',
      'home.after.30.seconds': '30秒後',
      'home.after.2.minutes': '2分後',
      'home.after.10.minutes': '10分後',
      'home.authenticate.now': '今すぐ認証',
      'home.lock.session.now': '今すぐセッションをロック',
      'home.external.quick.memo': '外部クイックメモ',
      'home.write.target': '書き込み先',
      'home.private.vault': 'Private vault',
      'home.status': '状態',
      'home.set.private.key': 'プライベートキーを設定',
      'home.backup.and.sync': 'バックアップと同期',
      'home.selected.target': '選択中の同期先',
      'home.pending.sync.queue': '保留中の同期キュー',
      'home.queue.ready': 'キュー準備済み',
      'home.remote.bundle': 'リモートバンドル',
      'home.copy.recovery.key': 'クラウド復元キーをコピー',
      'home.last.sync.activity': '直近の同期履歴',
      'home.local.bundle.cache': 'ローカルバンドルキャッシュ',
      'home.off.2': 'オフ',
      'home.refresh.remote': 'リモートを更新',
      'home.upload.bundle': 'バンドルをアップロード',
      'home.force.upload': '強制アップロード',
      'home.bundle.history': 'バンドル履歴',
      'home.download.bundle': 'バンドルをダウンロード',
      'home.review.bundle': 'バンドルを確認',
      'home.apply.bundle': 'バンドルを適用',
      'home.inspect.snapshot': 'スナップショットを確認',
      'home.storage': 'ストレージ',
      'home.cancel': 'キャンセル',
      'home.icloud.availability': 'iCloud の利用状態',
      'home.authentication': '認証',
      'home.check.icloud': 'iCloud を確認',
      'home.connect': '接続',
      'home.check.again': 'iCloud を再確認',
      'home.reconnect': '再接続',
      'home.stop.using.icloud': 'iCloud 同期を解除',
      'home.disconnect': '切断',
      'home.sync.is.disabled': '同期はオフです。',
      'home.previous.note': '前のメモ',
      'home.next.note': '次のメモ',
      'home.previous.note.2': '前のメモ',
      'home.next.note.2': '次のメモ',
      'home.list.layout': '表示形式',
      'home.standard.list': '標準表示',
      'home.compact.list': 'コンパクト表示',
      'home.list.layout.2': '表示形式',
      'home.list.layout.3': '表示形式',
      'home.filters': '詳細',
      'home.filters.2': '詳細',
      'home.filters.3': '詳細条件',
      'home.pinned.only': '固定したノートだけ',
      'home.with.media': '添付があるノートだけ',
      'home.vault': '保存先',
      'home.filter.by.tag': 'タグで絞り込み',
      'home.reset.filters': '条件をリセット',
      'home.select.a.note': 'メモを選択してください',
      'home.private.profile': 'プライベートプロファイル',
      'home.tags': 'タグ',
      'home.add.a.tag': 'タグを追加',
      'home.tap.to.open.image': 'タップして画像を表示',
      'home.unknown.time': '時刻不明',
      'home.size.unknown': 'サイズ不明',
      'home.bundle.review': 'バンドル確認',
      'home.added.notes': '追加されるノート',
      'home.updated.notes': '更新されるノート',
      'home.remote.bundle.history': 'リモートバンドル履歴',
      'home.unknown.time.2': '時刻不明',
      'home.unknown.device': '端末不明',
      'home.import.recovery.key': 'クラウド復元キーを読み込む',
      'home.import': '読み込む',
      'home.confirm.pin': 'PIN を確認',
      'home.unlock.private.profile': 'プライベートプロファイルを開く',
      'home.no.private.profile.matched.that.password':
          '一致するプライベートプロファイルは見つかりませんでした。',
      'home.private.profile.unlocked': 'プライベートプロファイルを開きました。',
      'home.unlock.private.profile.2': 'プライベートプロファイルを開く',
      'home.admin.mode.is.currently.active': '現在は管理者モードです。',
      'home.profile.password': 'プロファイルパスワード',
      'home.enter.a.password': 'パスワードを入力してください。',
      'home.review.notes.grouped.by.day.and.keep.diary.entries.ancho':
          '日付ごとにノートを振り返り、日記を日付にひも付けて見返します。',
      'home.previous.day.with.notes': '前の記録がある日',
      'home.next.day.with.notes': '次の記録がある日',
      'home.no.notes.on.this.day.yet': 'この日にはまだノートがありません。',
      'home.previous.day.with.notes.2': '前の記録がある日',
      'home.next.day.with.notes.2': '次の記録がある日',
      'home.notes.created.over.the.last.6.months': '最近6か月のノート件数',
      'home.daily.note.count.over.the.last.14.days': '直近14日の日別ノート件数',
      'home.notes.by.weekday.and.3.hour.time.block': '曜日別、3時間ごとの記録量をまとめて見ます。',
      'home.how.often.photos.videos.and.audio.are.used': '写真・動画・音声の使用数',
      'home.alternate.profile.password': '別プロファイル用パスワード',
      'home.confirm.alternate.profile.password': '別プロファイル用パスワードを確認',
      'home.use.this.password.to.switch.to.a.different.everyday.prof':
          '通常の表示とは別のプロファイルへ切り替えるためのパスワードです。',
      'home.alternate.profile.password.saved': '別プロファイル用パスワードを保存しました。',
      'home.this.removes.the.configured.password.for.the.alternate.p':
          '別プロファイル用に設定したパスワードを削除します。',
      'home.profile.password.2': 'プロファイルパスワード',
      'home.enter.a.password.2': 'パスワードを入力してください。',
      'home.confirm.password': 'パスワードを再入力',
      'home.passwords.do.not.match': 'パスワードが一致しません。',
      'home.private.profile.added.and.opened': 'プライベートプロファイルを追加して開きました。',
      'home.admin.mode.is.not.available.in.this.environment':
          '管理者モードはこの環境では利用できません。',
      'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h':
          '管理者モードに入りました。プロファイル名と保存先IDは引き続き非表示です。',
      'home.change.current.profile.password': '現在のプロファイルのパスワードを変更',
      'home.update.the.password.used.to.unlock.this.profile':
          'このプロファイルの解除に使うパスワードを更新します。',
      'home.profile.password.updated': 'プロファイルのパスワードを更新しました。',
      'home.off.turning.this.on.asks.for.a.password.or.device.authen':
          '未設定です。オンにするとパスワードまたは生体認証を設定します。',
      'home.on.this.session.is.unlocked': '有効です。このセッションは解除中です。',
      'home.on.this.session.is.locked': '有効です。このセッションはロック中です。',
      'home.manage.access.sync.and.display.policy': 'アクセス、同期、表示ポリシーを管理します。',
      'home.change.current.profile.password.2': '現在のプロファイルのパスワードを変更',
      'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe':
          '通常はそのまま通常メモモードで使います。別の表示が必要なときだけ特別なアクセスキーを入力します。',
      'home.enter.special.access.key': '特別なアクセスキーを入力',
      'home.return.to.normal.mode': '通常モードに戻す',
      'home.require.pin.on.launch': '起動時に PIN を要求',
      'home.require.device.auth.on.launch': '起動時に端末認証を要求',
      'home.set.unlock.pin': '解除用 PIN を設定',
      'home.device.authentication.was.not.completed.so.launch.protec':
          '端末認証が完了しなかったため、アプリ保護はオンになりませんでした。',
      'home.when.icloud.sync.is.selected.this.key.is.shared.automati':
          'iCloud を使う場合、この鍵は同じ iCloud アカウントの Apple デバイス間で自動共有されます。手動でコピーする必要はありません。',
      'home.this.session.is.currently.unlocked': 'このセッションではメモを開ける状態です。',
      'home.this.browser.stays.locked.until.the.correct.pin.is.enter':
          '正しい PIN を入力するまで、このブラウザではメモを開けません。',
      'home.this.session.stays.locked.until.device.authentication.su':
          '端末認証が成功するまで、このセッションはロックされたままです。',
      'home.change.unlock.pin': '解除用 PIN を変更',
      'home.set.unlock.pin.2': '解除用 PIN を設定',
      'home.unlock.pin.updated': '解除用 PIN を更新しました。',
      'home.unlock.pin.configured': '解除用 PIN を設定しました。',
      'home.remove.unlock.pin': '解除用 PIN を削除',
      'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off':
          'このブラウザで使っている Web 用 PIN を削除し、起動時の PIN 保護もオフにしますか。',
      'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla':
          'Web 用 PIN は、このブラウザでメモ画面を開きにくくするための保護です。端末の安全領域や生体認証の代わりにはなりません。',
      'home.quick.widget.capture.only.writes.plain.text.into.notes.i':
          'クイックキャプチャは Notes に平文テキストだけを書き込みます。既存ノートやロック中のプロファイルは開きません。',
      'home.re.lock.after.app.leaves.the.foreground': 'アプリが前面から外れた後に再ロック',
      'home.lock.the.app.as.soon.as.it.moves.to.the.background':
          'バックグラウンドに移動したらすぐロックします。',
      'home.allow.quick.app.switching.without.immediate.re.auth':
          'すぐ戻るときは再認証なしで切り替えられます。',
      'home.useful.when.capturing.photos.or.audio.between.notes':
          'ノート間で写真や音声を扱うときに向いています。',
      'home.keep.the.app.open.during.longer.editing.sessions':
          '長めの編集中でも開いたままにできます。',
      'home.lock.legacy.private.area.when.app.locks': 'アプリロック時にレガシー領域もロック',
      'home.normally.this.locks.whenever.the.app.locks':
          '通常は常にアプリロックと同時にロックします。',
      'home.pin.unlock.on.lock.screen': 'ロック画面で PIN 解除',
      'home.web.pin.active': 'Web PIN 利用中',
      'home.refresh.availability': '利用可否を更新',
      'home.widget.quick.writes.are.allowed.while.the.app.is.locked':
          'ロック中でもウィジェットから Notes に追記できます。',
      'home.widget.quick.writes.are.off': 'ウィジェットからのクイック書き込みは無効です。',
      'home.allow.widget.writes.while.locked': 'ロック中でもウィジェットから書き込む',
      'home.only.the.submitted.text.is.saved.existing.notes.and.lock':
          '既存のメモやロック中のプロファイルは表示せず、入力内容だけを保存します。',
      'home.configured.and.currently.unlocked': '設定済みで現在は解除中です。',
      'home.configured.and.locked': '設定済みでロック中です。',
      'home.no.private.vault.key.has.been.set.yet':
          'まだ private vault のキーが設定されていません。',
      'home.configured.and.unlocked.for.this.session': 'このセッションでは解除されています。',
      'home.configured.and.locked.a.separate.key.is.required':
          '設定済みでロック中です。別のキーが必要です。',
      'home.not.configured.yet.set.a.separate.key.for.the.private.va':
          '未設定です。private vault 用の別キーを設定してください。',
      'home.unlock.private.vault': 'Private vault を解除',
      'home.lock.private.vault': 'Private vault をロック',
      'home.reset.private.key': 'プライベートキーをリセット',
      'home.no.pending.device.changes': 'この端末に保留中の変更はありません。',
      'home.checking.pending.changes': '保留中の変更を確認中...',
      'home.unable.to.inspect.the.local.sync.queue': 'ローカル同期キューを確認できませんでした。',
      'home.cloud.recovery.key.fingerprint': 'クラウド復元キーのフィンガープリント',
      'home.preparing.cloud.recovery.key': 'クラウド復元キーを準備中...',
      'home.unable.to.read.the.cloud.recovery.key.fingerprint':
          'クラウド復元キーのフィンガープリントを読めませんでした。',
      'home.cloud.recovery.key.copied.to.clipboard':
          'クラウド復元キーをクリップボードにコピーしました。',
      'home.no.sync.activity.has.been.recorded.on.this.device.yet':
          'この端末ではまだ同期履歴がありません。',
      'home.reading.sync.activity': '同期履歴を読み込み中...',
      'home.unable.to.read.local.sync.activity': 'ローカル同期履歴を読めませんでした。',
      'home.keep.data.on.this.device.only': 'データをこの端末のみに保存します。',
      'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo':
          'この端末の iCloud を使う同期先です。HiMemo 用のログインは不要です。',
      'home.google.drive.app.data.sync.target':
          'Google Drive の app-data 同期先です。',
      'home.force.upload.2': '強制アップロードしますか？',
      'home.a.newer.remote.bundle.was.found.while.this.device.still':
          'この端末に保留中の変更がある状態で、より新しいリモートバンドルが見つかりました。強制アップロードすると、リモートのバックアップをこの端末の状態で上書きします。',
      'home.no.remote.bundle.history.is.available': '利用できるリモートバンドル履歴がありません。',
      'home.keep.for.apply': '適用候補として保持',
      'home.selected.bundle.is.ready.for.apply': '選択したバンドルを適用候補として保持しました。',
      'home.prepared.sync.snapshot': '同期スナップショットを準備しました',
      'home.saved.notes.on.this.device': 'この端末に保存されたノート',
      'home.use.japanese.across.the.app': '表示を日本語に固定します。',
      'home.use.english.across.the.app': '表示を英語に固定します。',
      'home.icloud.selected.the.app.checks.this.device.s.icloud.avai':
          'iCloud を選択中です。この端末で iCloud が使えるか確認してから同期します。HiMemo 用のログインは不要です。',
      'home.google.drive.selected.authorize.access.to.drive.app.data':
          'Google Drive を選択中です。Drive のアプリ専用領域へのアクセスを許可して同期します。',
      'home.this.device.s.icloud.availability.has.not.been.checked.y':
          'まだこの端末の iCloud 利用状態を確認していません。',
      'home.checking.this.device.s.icloud.availability':
          'この端末の iCloud 利用状態を確認しています...',
      'home.this.device.can.use.icloud.as.the.himemo.sync.target':
          'この端末の iCloud を HiMemo の同期先として利用できます。',
      'home.icloud.sync.is.not.available.on.this.device':
          'この端末では iCloud 同期を利用できません。',
      'home.no.cloud.account.is.connected': 'クラウド同期は接続されていません。',
      'home.no.account.connected.yet': 'まだアカウントは接続されていません。',
      'home.waiting.for.authentication.to.complete': '認証の完了を待っています...',
      'home.authentication.is.not.available': '認証を利用できません。',
      'home.no.cloud.account.is.connected.2': 'クラウドアカウントは接続されていません。',
      'home.no.account.connected.yet.2': 'まだアカウントが接続されていません。',
      'home.waiting.for.authentication.to.complete.2': '認証完了を待っています...',
      'home.authentication.is.not.available.2': '認証は利用できません。',
      'home.locked.profiles.are.hidden.unlock.the.target.profile.fro':
          'ロック中のプロファイルは表示されません。設定から対象のプロファイルを解除してください。',
      'home.swipe.left.or.right.to.move.between.notes':
          '左右にスワイプして前後のメモへ移動できます。',
      'home.search.notes.diary.entries.and.attachment.labels': 'ノート、日記、添付名を検索',
      'home.search.terms.are.cleared.when.private.mode.closes':
          'プライベート表示を閉じると検索語は消去されます。',
      'home.all.visible.vaults': '表示中の保存先すべて',
      'home.add.tags.to.narrow.the.list': 'タグを追加して絞り込み',
      'home.pick.a.note.from.the.list.to.preview.it.here':
          '一覧からメモを選ぶと、ここに内容が表示されます。',
      'home.type.a.tag.and.press.enter': '自由なタグを追加できます',
      'home.save.to.private.profile': 'プライベートプロファイルに保存',
      'home.choose.which.private.profile.to.save.into.while.in.admin':
          '管理者モードでは保存先のプロファイルを選べます。',
      'home.save.into.the.currently.unlocked.private.profile':
          '現在開いているプライベートプロファイルに保存します。',
      'home.remote.bundle.storage.is.not.configured.yet':
          'リモートバンドル保存先はまだ設定されていません。',
      'home.no.icloud.bundle.metadata.loaded.yet':
          'iCloud 側のバンドル情報はまだ取得されていません。',
      'home.remote.bundle.transport.is.not.available.yet':
          'リモートバンドル転送はまだ利用できません。',
      'home.remote.bundle.storage.is.not.configured.yet.2':
          'リモートバンドルはまだ設定されていません。',
      'home.no.icloud.bundle.metadata.loaded.yet.2':
          'iCloud 側のバンドル情報はまだ取得されていません。',
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r':
          'リモートバンドル転送は現在 Google Drive のみ対応しています。',
      'home.no.remote.bundle.metadata.loaded.yet':
          'まだリモートバンドルのメタデータは読み込まれていません。',
      'home.removed.locally.after.apply': '適用後にこの端末で消えるノート',
      'home.paste.himemo.sync.key.v1': 'himemo-sync-key-v1:... を貼り付け',
      'home.use.a.4.digit.pin.for.this.browser': 'このブラウザで使う 4 桁の PIN を設定します。',
      'home.pin.must.be.exactly.4.digits': 'PIN は 4 桁ちょうどで入力してください。',
      'home.pin.must.contain.digits.only': 'PIN は数字だけで入力してください。',
      'home.pin.confirmation.did.not.match': '確認用 PIN が一致しません。',
      'home.previous.image': '前の画像',
      'home.next.image': '次の画像',
      'home.restore.frame': '枠内表示に戻す',
      'home.maximize': '最大化',
      'home.zoom.out': '縮小',
      'home.zoom.in': '拡大',
      'home.fit.to.screen': '画面に合わせる',
      'home.share': '共有',
      'home.pause.audio': '音声を一時停止',
      'home.play.audio': '音声を再生',
      'settings.demo.create': 'デモ用ノートを作成',
      'settings.demo.create.none': '作成できるデモ用ノートはありません。',
      'settings.demo.create.done': 'デモ用ノート {count} 件を作成しました。',
      'settings.demo.delete': 'デモ用ノートを削除',
      'settings.demo.delete.title': 'デモ用ノートを削除しますか？',
      'settings.demo.delete.body':
          'デモ用ノート {count} 件をこの端末から削除します。自分で作成したノートは削除されません。',
      'settings.demo.delete.done': 'デモ用ノート {count} 件を削除しました。',
    },
  };

  String text(String key, [Map<String, Object?> args = const {}]) {
    final template =
        _localizedValues[locale.languageCode]?[key] ??
        _localizedValues['en']?[key] ??
        key;
    return args.entries.fold(
      template,
      (value, entry) => value.replaceAll('{${entry.key}}', '${entry.value}'),
    );
  }

  String get appTitle => 'HiMemo';
  String get notes => isJapanese ? 'ノート' : 'Notes';
  String get calendar => isJapanese ? 'カレンダー' : 'Calendar';
  String get insights => isJapanese ? '記録' : 'Insights';
  String get settings => isJapanese ? '設定' : 'Settings';
  String get addNote => isJapanese ? 'ノートを追加' : 'Add note';
  String get collapseSidebar => isJapanese ? 'サイドバーを折りたたむ' : 'Collapse sidebar';
  String get expandSidebar => isJapanese ? 'サイドバーを開く' : 'Expand sidebar';
  String get search => isJapanese ? '検索' : 'Search';
  String get today => isJapanese ? '今日' : 'Today';
  String get yesterday => text('date.yesterday');
  String weekdayShort(int weekday) => text(
    const [
      'date.weekday.mon.short',
      'date.weekday.tue.short',
      'date.weekday.wed.short',
      'date.weekday.thu.short',
      'date.weekday.fri.short',
      'date.weekday.sat.short',
      'date.weekday.sun.short',
    ][weekday - 1],
  );
  String monthName(int month) => text('date.month.$month');
  String noteDayLabel(DateTime date) {
    final weekday = weekdayShort(date.weekday);
    if (isJapanese) {
      return '${date.year}/${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}($weekday)';
    }
    return '${monthName(date.month)} ${date.day}, ${date.year} ($weekday)';
  }

  String get emptyNotesTitle => text('notes.empty.title');
  String get emptyNotesBody => text('notes.empty.body');
  String get createDemoNotes => text('settings.demo.create');
  String demoNotesCreated(int count) =>
      text('settings.demo.create.done', {'count': count});
  String get noDemoNotesToCreate => text('settings.demo.create.none');
  String get deleteDemoNotes => text('settings.demo.delete');
  String get deleteDemoNotesTitle => text('settings.demo.delete.title');
  String deleteDemoNotesBody(int count) =>
      text('settings.demo.delete.body', {'count': count});
  String demoNotesDeleted(int count) =>
      text('settings.demo.delete.done', {'count': count});
  List<String> get weekdayShortLabels => [
    for (var weekday = 1; weekday <= 7; weekday++) weekdayShort(weekday),
  ];
  String viewingPrivateProfile(String label) =>
      isJapanese ? '$label を表示中' : 'Viewing $label';
  String currentPrivateProfile(String? label) =>
      isJapanese ? '現在は $label を表示しています。' : 'Currently viewing $label.';
  String filteredByTag(String tag) =>
      isJapanese ? '#$tag のタグで絞り込みました' : 'Filtered notes by #$tag';
  String deleteNoteConfirmation(String title) => isJapanese
      ? '「$title」をこの端末から完全に削除しますか？'
      : 'Delete "$title" permanently from this device?';
  String get deleteNote => isJapanese ? 'ノートを削除' : 'Delete note';
  String noteDeleted(String title) =>
      isJapanese ? '「$title」を削除しました' : '"$title" deleted';
  String get accessKey => isJapanese ? 'アクセスキー' : 'Access key';
  String get specialAccessKeyHelp => isJapanese
      ? '有効なキーを入力すると別のモードに切り替わります。'
      : 'A valid key switches the app into another mode.';
  String get unlockMode => isJapanese ? 'モードを解除' : 'Unlock mode';
  String get privateModeActive =>
      isJapanese ? 'プライベートモードを有効にしました。' : 'Private mode is now active.';
  String get coverModeActive =>
      isJapanese ? 'カバーモードを有効にしました。' : 'Cover mode is now active.';
  String get accessKeyNoMatch => isJapanese
      ? 'そのアクセスキーに一致するモードはありません。'
      : 'That access key did not match any mode.';
  String get resetPrivateKey => text('home.reset.private.key');
  String get resetPrivateKeyBody => isJapanese
      ? '設定済みのプライベート領域キーを削除し、プライベート領域をすぐにロックします。'
      : 'This removes the configured private-vault key and locks the private vault immediately.';
  String get reset => text('home.reset');
  String get unableToShareAttachment =>
      isJapanese ? 'この添付はまだ共有できません。' : 'This attachment cannot be shared yet.';
  String get unableToDecryptAttachment =>
      isJapanese ? 'この添付を復号できませんでした。' : 'Unable to decrypt this attachment.';
  String get unableToLoadImage =>
      isJapanese ? 'この画像を読み込めませんでした。' : 'Unable to load this image.';
  String get unableToDecryptImage =>
      isJapanese ? 'この画像を復号できませんでした。' : 'Unable to decrypt this image.';
  String get videoPreviewUnavailableWeb => isJapanese
      ? 'Web では動画プレビューを利用できません。'
      : 'Video preview is not enabled on web.';
  String get replaceRecoveryKey =>
      isJapanese ? '復元キーを置き換え' : 'Replace recovery key';
  String replaceRecoveryKeyBody({
    required String currentFingerprint,
    required String incomingFingerprint,
  }) => isJapanese
      ? '現在のフィンガープリント: $currentFingerprint\n'
            'インポートするフィンガープリント: $incomingFingerprint\n\n'
            '復元キーを置き換えると、元のキーを戻すまで、この端末で既存のリモートバンドルを読めなくなる可能性があります。'
      : 'Current fingerprint: $currentFingerprint\n'
            'Imported fingerprint: $incomingFingerprint\n\n'
            'Replacing the recovery key can make existing remote bundles unreadable on this device until the original key is restored.';
  String get replaceKey => isJapanese ? 'キーを置き換え' : 'Replace key';
  String editedAt(String label) => isJapanese ? '編集済み $label' : 'Edited $label';
  String createdRevision(String createdLabel, int revision) => isJapanese
      ? '作成 $createdLabel ・ リビジョン $revision'
      : 'Created $createdLabel · Revision $revision';
  String get unlockedPrivateNotes =>
      isJapanese ? '解除済みのプライベートノート' : 'Unlocked private notes';
  String get photoPlaceholder =>
      isJapanese ? '写真のプレースホルダー' : 'Photo placeholder';
  String get tapToViewPhoto => isJapanese ? 'タップして写真を表示' : 'Tap to view photo';
  String get videoPlaceholder =>
      isJapanese ? '動画のプレースホルダー' : 'Video placeholder';
  String get tapToPlayVideo => isJapanese ? 'タップして動画を再生' : 'Tap to play video';
  String get audioPlaceholder =>
      isJapanese ? '音声のプレースホルダー' : 'Audio placeholder';
  String get tapToPlayAudio => isJapanese ? 'タップして音声を再生' : 'Tap to play audio';
  String get closeImageViewer =>
      isJapanese ? '画像ビューアを閉じる' : 'Close image viewer';
  String get syncLabel => isJapanese ? '同期' : 'Sync';
  String get enableDeviceAuthReason => isJapanese
      ? 'HiMemo の端末認証を有効にします'
      : 'Enable device authentication for HiMemo';
  String get unlockWithDeviceAuthReason => isJapanese
      ? '端末認証で HiMemo を解除します'
      : 'Unlock HiMemo with device authentication';
  String notesCount(int count, {bool spacedEnglish = true}) =>
      isJapanese ? '$count件' : '$count${spacedEnglish ? ' ' : ''}notes';
  String entriesCount(int count) => isJapanese ? '$count 件' : '$count entries';
  String noteCountSummary(int count) => isJapanese
      ? 'この端末に $count 件のノートを保存しています。'
      : '$count notes saved on this device.';
  String monthBucketLabel(int month) => isJapanese ? '$month月' : '$month';
  String accessModeSummary(String modeLabel) => isJapanese
      ? '$modeLabel。別の表示が必要なときだけ特別キーを使います。'
      : '$modeLabel. Special keys are used only when another view is needed.';
  String webPinProtectionSummary(String pinSummary) => isJapanese
      ? 'このブラウザでは 4 桁の PIN でメモ画面を保護します。$pinSummary'
      : 'Protect this browser session with a 4 digit PIN. $pinSummary';
  String deviceAuthProtectionSummary(String summary) => isJapanese
      ? 'この端末の生体認証や画面ロックで保護します。利用状況: $summary'
      : 'Protect the app with device authentication. Availability: $summary';
  String lastQueuedAt(String timestamp) =>
      isJapanese ? '最終追加 $timestamp' : 'last queued $timestamp';
  String pendingSyncSummary({
    required int total,
    required int upserts,
    required int deletes,
    required String stamp,
  }) => isJapanese
      ? '$total件が保留中（更新 $upserts / 削除 $deletes）、$stamp'
      : '$total changes pending ($upserts upserts, $deletes deletes), $stamp';
  String recoveryKeyImported(String fingerprint) => isJapanese
      ? 'クラウド復元キーを読み込みました。フィンガープリント: $fingerprint'
      : 'Cloud recovery key imported. Fingerprint: $fingerprint';
  String lastUploadAt(String timestamp) =>
      isJapanese ? '最終アップロード $timestamp' : 'Last upload $timestamp';
  String lastApplyAt(String timestamp) =>
      isJapanese ? '最終適用 $timestamp' : 'Last apply $timestamp';
  String remoteBundleAt(String timestamp) =>
      isJapanese ? 'リモート更新 $timestamp' : 'Remote bundle $timestamp';
  String localBundleStoredAt(String reference) =>
      isJapanese ? '$reference に保存済み' : 'Stored at $reference';
  String syncSnapshotSummary({
    required int notes,
    required int attachments,
    required int pending,
    required String deviceId,
  }) => isJapanese
      ? 'ノート: $notes\n添付: $attachments\nキュー: $pending件保留中\n端末 ID: $deviceId'
      : 'Notes: $notes\nAttachments: $attachments\nQueue: $pending pending\nDevice ID: $deviceId';
  String syncConnected({String? identity, String suffix = ''}) {
    if (identity == null) {
      return isJapanese ? '接続済みです。$suffix' : 'Connected.$suffix';
    }
    return isJapanese
        ? '$identity で接続済みです。$suffix'
        : 'Connected as $identity.$suffix';
  }

  String syncConnectedLegacy({String? identity, String suffix = ''}) {
    if (identity == null) {
      return isJapanese ? '接続済み。$suffix' : 'Connected.$suffix';
    }
    return isJapanese
        ? '$identity で接続済み。$suffix'
        : 'Connected as $identity.$suffix';
  }

  String identityActive(String name) =>
      isJapanese ? '$name 利用中' : '$name active';
  String byteCount(int bytes) => isJapanese ? '$bytes バイト' : '$bytes bytes';
  String remoteBundleSummary({
    required String modifiedAt,
    required String sizeLabel,
    required String noteCount,
    required String attachmentCount,
  }) => isJapanese
      ? '最新バンドル: $modifiedAt、$sizeLabel、ノート $noteCount 件、添付 $attachmentCount 件。'
      : 'Last bundle: $modifiedAt, $sizeLabel, $noteCount notes, $attachmentCount attachments.';
  String bundleNotes(int count) =>
      isJapanese ? 'バンドル内ノート: $count' : 'Notes in bundle: $count';
  String bundleAttachments(int count) =>
      isJapanese ? 'バンドル内添付: $count' : 'Attachments in bundle: $count';
  String bundleAdds(int count) => isJapanese ? '追加: $count' : 'Adds: $count';
  String bundleUpdates(int count) =>
      isJapanese ? '更新: $count' : 'Updates: $count';
  String bundleRemovals(int count) =>
      isJapanese ? 'この端末で削除されるもの: $count' : 'Removals on this device: $count';
  String bundlePrivateVaultAffected(int count) => isJapanese
      ? 'Private vault に影響するノート: $count'
      : 'Private vault notes affected: $count';
  String bundleRemoteDevice(String deviceId) =>
      isJapanese ? 'リモート端末: $deviceId' : 'Remote device: $deviceId';
  String bundleExportedAt(String timestamp) =>
      isJapanese ? '書き出し日時: $timestamp' : 'Exported at: $timestamp';
  String bundleSample(String sample) =>
      isJapanese ? 'サンプル: $sample' : 'Bundle sample: $sample';
  String bundleHistoryCounts({int? notes, int? attachments}) => isJapanese
      ? '${notes ?? '?'}件のノート / ${attachments ?? '?'}件の添付'
      : '${notes ?? '?'} notes, ${attachments ?? '?'} attachments';
  String locationMemo({
    required String latitude,
    required String longitude,
    required String accuracy,
    required String mapUrl,
    String? estimatedAddress,
  }) {
    final address = estimatedAddress?.trim();
    final addressLine = address == null || address.isEmpty
        ? ''
        : isJapanese
        ? '推定住所: $address\n'
        : 'Estimated address: $address\n';
    if (isJapanese) {
      return '現在地\n'
          '$addressLine'
          '緯度: $latitude\n'
          '経度: $longitude\n'
          '精度: 約$accuracy\n'
          '$mapUrl';
    }
    return 'Current location\n'
        '$addressLine'
        'Latitude: $latitude\n'
        'Longitude: $longitude\n'
        'Accuracy: about $accuracy\n'
        '$mapUrl';
  }

  String get previousImage => text('home.previous.image');
  String get nextImage => text('home.next.image');
  String get restoreFrame => text('home.restore.frame');
  String get maximize => text('home.maximize');
  String get zoomOut => text('home.zoom.out');
  String get zoomIn => text('home.zoom.in');
  String get fitToScreen => text('home.fit.to.screen');
  String get share => text('home.share');
  String get pauseAudio => text('home.pause.audio');
  String get playAudio => text('home.play.audio');
  String get insightsSummaryEmpty => isJapanese
      ? '書いた量がここにたまります。まずは数日続けてみると変化が見えます。'
      : 'Your writing activity will appear here. Write for a few days to make trends visible.';
  String insightsSummaryActive(int thisMonthCount, String bestDayLabel) =>
      isJapanese
      ? '今月は $thisMonthCount 件、最も書いた日は $bestDayLabel です。連続記録を保つと積み上がりが見えやすくなります。'
      : 'This month has $thisMonthCount notes. Your best day was $bestDayLabel. Keeping a streak makes progress easier to see.';

  String get appearance => isJapanese ? '表示' : 'Appearance';
  String get language => isJapanese ? '言語' : 'Language';
  String get languageSystem => isJapanese ? 'システムに合わせる' : 'Follow system';
  String get languageJapanese => isJapanese ? '日本語' : 'Japanese';
  String get languageEnglish => isJapanese ? '英語' : 'English';
  String get languageSystemDesc => isJapanese
      ? '端末の言語設定に合わせます。未対応の言語では英語を使います。'
      : 'Follow the device language. Fall back to English when unsupported.';
  String get themeLight => isJapanese ? 'ライト' : 'Light';
  String get themeSystem => isJapanese ? 'システム' : 'System';
  String get themeDark => isJapanese ? 'ダーク' : 'Dark';
  String get accentColor => isJapanese ? 'アクセントカラー' : 'Accent color';
  String get colorBlue => isJapanese ? 'ブルー' : 'Blue';
  String get colorGreen => isJapanese ? 'グリーン' : 'Green';
  String get colorOrange => isJapanese ? 'オレンジ' : 'Orange';
  String get colorSlate => isJapanese ? 'スレート' : 'Slate';
  String get colorTeal => isJapanese ? 'ティール' : 'Teal';
  String get colorRose => isJapanese ? 'ローズ' : 'Rose';
  String get colorBlueDesc => isJapanese
      ? '落ち着いた青を基調にした標準テーマです。'
      : 'Primary blue with calm support colors.';
  String get colorGreenDesc => isJapanese
      ? '視覚的な緊張を抑えた柔らかいグリーンです。'
      : 'Muted green palette for lower visual tension.';
  String get colorOrangeDesc => isJapanese
      ? '暖かいアクセントで操作や記録を目立たせます。'
      : 'Warm orange palette for highlighted actions and notes.';
  String get colorSlateDesc => isJapanese
      ? '中立的で静かな印象のスレート配色です。'
      : 'Neutral slate palette for a quieter interface.';
  String get colorTealDesc => isJapanese
      ? '軽やかな印象を出すティール配色です。'
      : 'Fresh teal palette with a light feel.';
  String get colorRoseDesc => isJapanese
      ? '日記らしい柔らかな雰囲気のローズ配色です。'
      : 'Soft rose palette for a more diary-like tone.';
  String get lightDesc => isJapanese
      ? '白基調のメモらしい見た目を保ちます。'
      : 'Keep the white memo-style interface.';
  String get systemDesc =>
      isJapanese ? '端末の表示設定に合わせます。' : 'Follow the device setting.';
  String get darkDesc => isJapanese
      ? '高コントラストなダークテーマを明示的に使います。'
      : 'Use the higher-contrast dark theme explicitly.';

  String get about => isJapanese ? 'アプリ情報' : 'About';
  String get appVersion => isJapanese ? 'アプリバージョン' : 'App version';
  String get appUpdates => isJapanese ? 'アプリ更新' : 'App updates';
  String get appUpdatesDesc => isJapanese
      ? 'Google Play のアプリ内更新を確認し、必要な更新を開始します。'
      : 'Check Google Play in-app updates and start the recommended update flow.';
  String get checkForUpdates => isJapanese ? '更新を確認' : 'Check for updates';
  String get startUpdate => isJapanese ? '更新を開始' : 'Start update';
  String get completeUpdateInstall => isJapanese ? '更新を完了' : 'Complete update';
  String get updateSupportedOnAndroidOnly => isJapanese
      ? 'アプリ内更新は Android の Google Play 配布で利用できます。'
      : 'In-app updates are available on Android builds distributed through Google Play.';
  String get updateStatusUpToDate =>
      isJapanese ? '現在のビルドは最新です。' : 'The installed build is up to date.';
  String get updateStatusAvailable => isJapanese
      ? 'Google Play に新しい更新があります。'
      : 'A newer build is available on Google Play.';
  String get updateStatusChecking =>
      isJapanese ? '更新を確認しています...' : 'Checking for updates...';
  String get updateStatusUnsupported => isJapanese
      ? 'この実行環境ではアプリ内更新を利用できません。'
      : 'In-app updates are not available in this runtime.';
  String get updateStatusStarted => isJapanese
      ? 'Google Play の更新フローを開始しました。'
      : 'Started the Google Play update flow.';
  String get updateFlexibleReady => isJapanese
      ? '柔軟な更新がダウンロード済みです。完了を押すと再起動して更新します。'
      : 'A flexible update is downloaded. Complete it to restart and apply the update.';
  String updateVersionLabel(int? versionCode) => isJapanese
      ? (versionCode == null ? '配信中の更新' : '配信中の更新: $versionCode')
      : (versionCode == null
            ? 'Available update'
            : 'Available update: $versionCode');
  String updatePriorityLabel(int? priority) =>
      isJapanese ? '優先度: ${priority ?? 0}' : 'Priority: ${priority ?? 0}';
  String get ossLicenses => isJapanese ? 'OSS ライセンス' : 'OSS licenses';
  String get ossLicensesDesc => isJapanese
      ? '利用しているオープンソースソフトウェアのライセンスを表示します。'
      : 'View bundled open-source software licenses.';
  String currentFlavor(String name) =>
      isJapanese ? '現在の flavor: $name' : 'Current flavor: $name';
  String readingVersion() =>
      isJapanese ? 'バージョンを読み込み中...' : 'Reading app version...';

  String get homeWidgetQuickCapture =>
      isJapanese ? '外部クイックメモ' : 'Allow external quick capture';
  String get homeWidgetQuickCaptureDesc => isJapanese
      ? 'ホームウィジェットや共有メニューから、通常のアプリロックを開かずに簡易メモ画面を開けます。'
      : 'Let the home widget or Android share sheet open a quick memo surface without unlocking the full app.';
  String get homeWidgetQuickCaptureMobileOnly => isJapanese
      ? 'モバイルのみ。オンにすると、ホームウィジェットや共有メニューから通常のアプリロックを開かずに簡易メモ画面を開けます。'
      : 'Mobile-only. When enabled, the home widget or Android share sheet can open a quick memo surface outside the normal app lock.';

  String get unlockHiMemo => isJapanese ? 'HiMemo を解除' : 'Unlock HiMemo';
  String get unlockWithPin => isJapanese ? 'PIN で解除' : 'Unlock with PIN';
  String get authenticate => isJapanese ? '認証する' : 'Authenticate';
  String get disableUnlockForNow =>
      isJapanese ? '今はアプリロックを無効にする' : 'Disable app unlock for now';
  String get browserPinGate => isJapanese
      ? 'このブラウザのセッションは Web PIN で保護されています。'
      : 'This browser session is protected with a web PIN.';
  String get deviceAuthGate => isJapanese
      ? '端末認証でこのセッションを再開します。'
      : 'Resume this session with device authentication.';
  String pinLockSummary({required bool isConfigured, String? lastError}) {
    if (isConfigured) {
      return isJapanese
          ? 'このブラウザでは解除用 PIN が設定されています。'
          : 'A web-only unlock PIN is configured for this browser session.';
    }
    if (lastError != null && lastError.isNotEmpty) {
      return lastError;
    }
    return isJapanese
        ? 'このブラウザでは解除用 PIN はまだ設定されていません。'
        : 'No unlock PIN is configured for this browser yet.';
  }

  String get privateVaultLockedMessage => isJapanese
      ? 'private vault と同期状態は、セッションを戻すまでロックされたままです。'
      : 'Private vault access and sync state remain locked until the session is restored.';

  String get onboardingWelcome =>
      isJapanese ? 'HiMemo へようこそ' : 'Welcome to HiMemo';
  String get onboardingIntro => isJapanese
      ? 'メモを書き始める前に、短い初期設定だけ済ませます。'
      : 'A short setup pass before the memo vault opens.';
  String get onboardingCaptureTitle => isJapanese ? 'すばやく記録' : 'Capture fast';
  String get onboardingCaptureBody => isJapanese
      ? '1行目がそのままタイトルになるので、思いついた内容をそのまま軽く書き始められます。'
      : 'The first line becomes the memo title, so quick notes stay lightweight from the first tap.';
  String get onboardingCaptureImageLabel =>
      isJapanese ? 'クイックメモ入力のプレビュー' : 'Quick memo capture preview';
  String get onboardingPrivateTitle =>
      isJapanese ? 'プライベート領域を分ける' : 'Separate private access';
  String get onboardingPrivateBody => isJapanese
      ? 'アプリの起動ロックとは別に、複数のプロファイルを個別のパスワードで管理できます。必要なプロファイルだけをその場で開けます。'
      : 'App unlock stays separate from profile access. You can manage multiple profiles with different passwords and open only the one you need.';
  String get onboardingPrivateImageLabel =>
      isJapanese ? 'プライベートプロファイル解錠のプレビュー' : 'Private vault unlock preview';
  String get onboardingSyncTitle =>
      isJapanese ? '同期はあとから設定' : 'Prepare sync later';
  String get onboardingSyncBody => isJapanese
      ? 'iCloud や Google Drive は、あとから同期先として選べます。最初は自前サーバーなしで始められます。'
      : 'Choose iCloud or Google Drive as the future sync target without turning your own server into a dependency.';
  String get onboardingSyncImageLabel =>
      isJapanese ? 'クラウド同期先のプレビュー' : 'Cloud sync target preview';
  String get onboardingFinishTitle =>
      isJapanese ? '最初に基本だけ設定' : 'Finish the basics';
  String get onboardingFinishBody => isJapanese
      ? 'まずはアプリ起動ロックだけ設定します。プライベートプロファイルやクラウド同期は、あとから設定で追加できます。'
      : 'Set the app unlock first. Private profiles and cloud sync can be added later from Settings.';
  String get onboardingFinishImageLabel =>
      isJapanese ? '初期アクセス設定のプレビュー' : 'Initial access setup preview';
  String get onboardingAddImageFallback =>
      isJapanese ? 'オンボーディング画像を追加' : 'Add an onboarding image';
  String get onboardingAppUnlockTitle => isJapanese ? 'アプリ起動ロック' : 'App unlock';
  String get onboardingPinConfiguredBrowser => isJapanese
      ? 'このブラウザでは解除用 PIN が設定されています。'
      : 'Configured for this browser.';
  String get onboardingSetPinBrowser => isJapanese
      ? '起動時の保護として 4 桁の PIN を設定できます。'
      : 'Set a 4 digit PIN for app launch.';
  String get onboardingDeviceAuthLater => isJapanese
      ? 'iPhone や Android では、端末の生体認証や端末 PIN を起動ロックとして使います。'
      : 'Device authentication can be enabled later in Settings.';
  String get onboardingChangePin => isJapanese ? 'PIN を変更' : 'Change PIN';
  String get onboardingSetPin => isJapanese ? 'PIN を設定' : 'Set PIN';
  String get onboardingLaterInSettings =>
      isJapanese ? 'あとで設定' : 'Later in Settings';
  String get onboardingPinSaved =>
      isJapanese ? 'アプリ解除 PIN を保存しました。' : 'App unlock PIN saved.';
  String get onboardingPrivateProfilesTitle =>
      isJapanese ? 'プライベートプロファイル' : 'Private profiles';
  String onboardingPrivateProfilesConfigured(int count) => isJapanese
      ? '$count 件のプライベートプロファイルが登録されています。'
      : '$count private profiles are configured.';
  String get onboardingPrivateProfilesBody => isJapanese
      ? '鍵アイコンから、入力したパスワードに合うプロファイルだけを開けます。用途ごとに分けて管理する前提です。'
      : 'Use the key icon to open only the profile that matches the entered password. This works well for keeping different spaces under separate locks.';
  String get onboardingAddInSettings =>
      isJapanese ? '設定で追加' : 'Add in Settings';
  String get onboardingCloudSyncTitle => isJapanese ? 'クラウド同期' : 'Cloud sync';
  String get onboardingCloudSyncBody => isJapanese
      ? 'iCloud や Google Drive への同期は、あとから設定で有効化できます。最初はオフラインのまま始められます。'
      : 'Enable iCloud or Google Drive later in Settings. You can start as an offline-first memo app.';

  String get privateProfilesSettingsTitle =>
      isJapanese ? 'プライベートプロファイル' : 'Private profiles';
  String get privateProfilesSettingsAdminSummary => isJapanese
      ? '管理者モードでも、プロファイル名や保存先IDは設定画面に表示しません。'
      : 'Profile names and vault IDs stay hidden in Settings, even in admin mode.';
  String privateProfilesSettingsActiveSummary(String _) => isJapanese
      ? '現在は認証済みのプライベートプロファイルを表示しています。'
      : 'A verified private profile is currently open.';
  String get privateProfilesSettingsDefaultSummary => isJapanese
      ? '通常は Notes だけを表示し、必要なときだけ別のプロファイルを開きます。'
      : 'Notes stays visible by default. Open another profile only when you need it.';
  String get privateProfilesSettingsBody => isJapanese
      ? '右上の鍵アイコンからパスワードを入力すると、一致するプロファイルだけを開けます。設定画面では登録済みプロファイルの名前や保存先IDを列挙しません。'
      : 'Enter a password from the key icon in the top bar to open only the matching profile. Settings does not list configured profile names or vault IDs.';
  String get addPrivateProfile => isJapanese ? 'プロファイルを追加' : 'Add profile';
  String get adminModeActiveLabel =>
      isJapanese ? '管理者モード中' : 'Admin mode active';
  String get enterAdminModeLabel =>
      isJapanese ? '管理者モードへ移行' : 'Enter admin mode';
  String get exitAdminModeLabel => isJapanese ? '管理者モードを終了' : 'Exit admin mode';
  String get noPrivateProfilesMessage =>
      isJapanese ? 'まだプライベートプロファイルはありません。' : 'No private profiles yet.';
  String privateProfilesHiddenSummary(int count) => isJapanese
      ? '$count 件のプライベートプロファイルが登録されています。名前と保存先IDは非表示です。'
      : '$count private profiles are configured. Names and vault IDs are hidden.';
  String get setAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードを設定' : 'Set alternate profile password';
  String get changeAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードを変更' : 'Change alternate profile password';
  String get resetAlternateProfilePassword =>
      isJapanese ? '別プロファイル用パスワードをリセット' : 'Reset alternate profile password';

  String get skip => isJapanese ? 'スキップ' : 'Skip';
  String get next => isJapanese ? '次へ' : 'Next';
  String get finishSetup => isJapanese ? 'セットアップ完了' : 'Finish setup';
  String get setAppUnlockPin =>
      isJapanese ? 'アプリ解除 PIN を設定' : 'Set app unlock PIN';
  String get pin => 'PIN';
  String get cancel => isJapanese ? 'キャンセル' : 'Cancel';
  String get delete => text('action.delete');
  String get save => isJapanese ? '保存' : 'Save';
  String get useExactly4Digits =>
      isJapanese ? '4桁ちょうどで入力してください。' : 'Use exactly 4 digits.';
  String get digitsOnly => isJapanese ? '数字のみ入力できます。' : 'Digits only.';
  String get coverKey => isJapanese ? 'カバーキー' : 'Cover key';
  String get privateKey => isJapanese ? 'プライベートキー' : 'Private key';
  String get setPrivateKey => isJapanese ? 'プライベートキーを設定' : 'Set private key';
  String get unlockPrivateVault =>
      isJapanese ? 'プライベート領域を解除' : 'Unlock private vault';
  String get unlock => isJapanese ? '解除' : 'Unlock';
  String confirmPrivateKey(String label) =>
      isJapanese ? '$label を確認' : 'Confirm $label';
  String get keysDoNotMatch => isJapanese ? 'キーが一致しません。' : 'Keys do not match.';
  String get privateKeyIncorrect =>
      isJapanese ? 'プライベートキーが正しくありません。' : 'Private key is not correct.';
  String get useAtLeast4Chars =>
      isJapanese ? '4文字以上で入力してください。' : 'Use at least 4 characters.';
  String get quickMemo => isJapanese ? 'クイックメモ' : 'Quick memo';
  String get richMemo => isJapanese ? 'リッチメモ' : 'Rich memo';
  String get newNote => isJapanese ? '新しいノート' : 'New note';
  String get editNote => isJapanese ? 'ノートを編集' : 'Edit note';
  String get memoLabel => isJapanese ? 'メモ' : 'Memo';
  String get memoFirstLineHint =>
      isJapanese ? '1行目をタイトルとして使います' : 'Use the first line as the title';
  String get vault => isJapanese ? '分類' : 'Vault';
  String get pinThisNote => isJapanese ? 'このノートを固定' : 'Pin this note';
  String get pinThisNoteDesc =>
      isJapanese ? '固定したノートは一覧の上に表示されます。' : 'Pinned notes stay near the top.';
  String get createNote => isJapanese ? 'ノートを作成' : 'Create note';
  String get saveChanges => isJapanese ? '変更を保存' : 'Save changes';
  String get startWritingHere =>
      isJapanese ? 'ここから書き始めます' : 'Start writing here';
  String get attachments => isJapanese ? '添付' : 'Attachments';
  String get addMedia => isJapanese ? 'メディアを追加' : 'Add media';
  String get pickPhoto => isJapanese ? '写真を選ぶ' : 'Pick photo';
  String get takePhoto => isJapanese ? '写真を撮る' : 'Take photo';
  String get pickVideo => isJapanese ? '動画を選ぶ' : 'Pick video';
  String get recordVideo => isJapanese ? '動画を撮る' : 'Record video';
  String get recordAudio => isJapanese ? '音声を録音' : 'Record audio';
  String get pickAudio => isJapanese ? '音声を選ぶ' : 'Pick audio';
  String get addCurrentLocation =>
      isJapanese ? '現在地を追加' : 'Add current location';
  String get currentLocationLabel => isJapanese ? '現在地' : 'Current location';
  String get estimatedAddressLabel => isJapanese ? '推定住所' : 'Estimated address';
  String get latitudeLabel => isJapanese ? '緯度' : 'Latitude';
  String get longitudeLabel => isJapanese ? '経度' : 'Longitude';
  String get locationAccuracyLabel => isJapanese ? '精度' : 'Accuracy';
  String get openMap => isJapanese ? '地図を開く' : 'Open map';
  String get copyMapLink => isJapanese ? '地図リンクをコピー' : 'Copy map link';
  String get mapLinkCopied =>
      isJapanese ? '地図リンクをコピーしました。' : 'Map link copied.';
  String get mapOpenFailed =>
      isJapanese ? '地図を開けませんでした。' : 'Could not open the map.';
  String get linkOpenFailed =>
      isJapanese ? 'リンクを開けませんでした。' : 'Could not open the link.';
  String get openExternalLinkTitle =>
      isJapanese ? '外部リンクを開きますか？' : 'Open external link?';
  String get openExternalLinkMessage => isJapanese
      ? 'このリンクはHiMemoの外部で開かれます。URLを確認してから続行してください。'
      : 'This link will open outside HiMemo. Check the URL before continuing.';
  String get openLink => isJapanese ? '開く' : 'Open';
  String get locationServicesOff => isJapanese
      ? '位置情報サービスがオフです。端末設定で有効にしてください。'
      : 'Location services are off. Enable them in device settings.';
  String get locationPermissionRequired => isJapanese
      ? '現在地を追加するには位置情報の許可が必要です。'
      : 'Location permission is required to add current location.';
  String get currentLocationAdded =>
      isJapanese ? '現在地をメモに追加しました。' : 'Current location added to the note.';
  String get currentLocationUnavailable =>
      isJapanese ? '現在地を取得できませんでした。' : 'Could not get current location.';
  String get attachFromBrowser => isJapanese
      ? 'このブラウザから写真・動画・音声を添付できます。'
      : 'Attach photos, videos, or audio files from this browser.';
  String get attachFromDevice => isJapanese
      ? 'カメラや端末内の写真・動画・音声を添付できます。'
      : 'Attach photos, videos, or audio files from camera or device storage.';
  String get dateTimeUpdated =>
      isJapanese ? '日時を更新しました' : 'Date and time updated';
  String get microphonePermissionNotGranted => isJapanese
      ? 'マイクの使用が許可されていません。'
      : 'Microphone permission was not granted.';
  String get microphonePermissionBrowserHelp => isJapanese
      ? 'Chrome または Edge で開き、サイト設定からマイクを許可してください。'
      : 'Open this app in Chrome or Edge and allow microphone access from the site settings.';
  String get microphonePermissionRequestTimedOut => isJapanese
      ? 'マイク許可の確認がタイムアウトしました。ブラウザの許可ダイアログを確認してください。'
      : 'Microphone permission check timed out. Check the browser permission prompt.';
  String get microphoneStartTimedOut => isJapanese
      ? 'マイクの開始がタイムアウトしました。別のアプリがマイクを使用していないか確認してください。'
      : 'Microphone startup timed out. Check whether another app is using the microphone.';
  String audioRecordingStartFailed(String diagnostic) => isJapanese
      ? '録音を開始できませんでした。$diagnostic'
      : 'Could not start recording.$diagnostic';
  String get audioRecordingNotificationTitle =>
      isJapanese ? 'HiMemoで録音中' : 'HiMemo is recording';
  String get audioRecordingNotificationContent =>
      isJapanese ? '音声メモの録音を継続しています。' : 'Audio memo recording is continuing.';
  String get audioRecordingSaveFailed =>
      isJapanese ? '録音データを保存できませんでした。' : 'Could not save the recording.';
  String get audioRecordingEmpty =>
      isJapanese ? '録音データが空でした。' : 'The recording was empty.';
  String get audioRecordingAttachFailed =>
      isJapanese ? '録音を添付できませんでした。' : 'Could not attach the recording.';
  String get audioRecordingStoreFailed =>
      isJapanese ? '録音を保存できませんでした。' : 'Could not save the recording.';
  String get audioPlaybackFailed =>
      isJapanese ? '音声を再生できませんでした。' : 'Could not play this audio.';
  String get audioMemoRecordingTitle =>
      isJapanese ? '音声メモを録音' : 'Record audio memo';
  String get stopAndAttachRecording =>
      isJapanese ? '停止して添付' : 'Stop and attach';
  String get startRecording => isJapanese ? '録音開始' : 'Start recording';
  String get undo => isJapanese ? '元に戻す' : 'Undo';
  String get draftRestored => isJapanese ? '下書きを復元しました' : 'Draft restored';
  String get discardDraft => isJapanese ? '破棄' : 'Discard';
  String get dismiss => isJapanese ? '閉じる' : 'Dismiss';
  String attachmentRemoved(String label) =>
      isJapanese ? '$label を削除しました' : '$label removed';
  String get removeBlock => isJapanese ? 'この添付を削除' : 'Remove block';
  String get moveEarlier => isJapanese ? '前へ移動' : 'Move earlier';
  String get moveLater => isJapanese ? '後へ移動' : 'Move later';
  String get syncAppleIdUnsupported => isJapanese
      ? 'このビルドでは iOS / macOS のみ iCloud 同期を利用できます。'
      : 'iCloud sync is only available on iOS and macOS in this build.';
  String get syncAppleIdUnavailable => isJapanese
      ? 'この端末では iCloud を利用できません。'
      : 'iCloud is not available on this device.';
  String get syncAppleIdConnected => isJapanese
      ? 'iCloud の利用状態を確認できました。同期設定を続けてください。'
      : 'iCloud is available. Continue setting up sync.';
  String get syncApplePluginMissing => isJapanese
      ? 'この実行環境では iCloud 同期を利用できません。'
      : 'iCloud sync is not configured in this runtime.';
  String get syncAppleUnknownError => isJapanese
      ? 'iCloud の状態を確認できませんでした。iCloud へのサインイン状態とアプリの権限を確認してください。'
      : 'Unable to confirm iCloud availability. Check the iCloud sign-in state and app capabilities.';
  String get close => isJapanese ? '閉じる' : 'Close';
  String get sendMemo => isJapanese ? 'メモを送信' : 'Send memo';
  String get sending => isJapanese ? '送信中...' : 'Sending...';
  String get sendQuickMemo => isJapanese ? 'クイックメモを送信' : 'Send a quick memo';
  String get quickMemoSaved =>
      isJapanese ? 'クイックメモを Notes に保存しました。' : 'Quick memo saved to Notes.';
  String get sharedMemoSaveFailed =>
      isJapanese ? '共有メモを保存できませんでした。' : 'Could not save the shared memo.';
  String quickCaptureDescription({required bool isShare}) => isJapanese
      ? (isShare
            ? '共有メニューから受け取ったテキストやファイルを、そのまま Notes に送れます。既存ノートやロック中のプロファイルは開きません。'
            : 'すばやくメモを記録します。この画面では既存ノートやロック中のプロファイルは表示しません。')
      : (isShare
            ? 'Shared text and files can be sent straight to Notes. This route never reveals existing notes or locked profiles.'
            : 'Capture a quick memo. This route never reveals existing notes or locked profiles.');
  String get sharedFiles => isJapanese ? '共有ファイル' : 'Shared files';
  String get filesNotImported =>
      isJapanese ? '取り込めなかったファイル' : 'Files not imported';
  String get sharedFileFallback => isJapanese ? '共有ファイル' : 'Shared file';
  String quickCaptureHint({required bool isShare}) => isJapanese
      ? (isShare
            ? '共有されたテキストを整えて、そのまま Notes に保存できます。'
            : 'メモを書いて、そのまま Notes に送ります。')
      : (isShare
            ? 'Tidy the shared text and save it to Notes.'
            : 'Write a memo and send it to Notes.');
  String sharedFileImportFailureReason(String reason) {
    switch (reason) {
      case 'unsupported_type':
        return isJapanese
            ? 'このファイル形式はサポートしていません。'
            : 'This file type is not supported.';
      case 'too_large':
        return isJapanese ? 'このファイルは大きすぎます。' : 'This file is too large.';
      case 'unreadable':
        return isJapanese
            ? 'このファイルを読み込めませんでした。'
            : 'This file could not be read.';
      default:
        return reason;
    }
  }

  String get finishSetupFirst =>
      isJapanese ? '先に初期設定を完了してください' : 'Finish setup first';
  String get quickWidgetCaptureOff =>
      isJapanese ? '外部クイックメモはオフです' : 'External quick capture is off';
  String get enableQuickWidgetInSettings => isJapanese
      ? '設定で外部クイックメモをオンにすると、ホームウィジェットや共有メニューからフルアプリを開かずにメモを送れます。'
      : 'Enable external quick capture in Settings if you want the home widget or Android share sheet to send memos without unlocking the full app.';
  String get completeOnboardingBeforeWidget => isJapanese
      ? 'ホームウィジェットから使う前に、初期設定を完了してください。'
      : 'Complete onboarding before using quick capture from the home widget.';
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) => ['en', 'ja'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsX on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
