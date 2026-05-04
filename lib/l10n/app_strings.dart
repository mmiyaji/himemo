import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class AppStrings {
  AppStrings(this.locale);

  final Locale locale;

  static const supportedLocales = <Locale>[
    Locale('en'),
    Locale('ja'),
    Locale('zh'),
    Locale('ko'),
    Locale('es'),
    Locale('de'),
  ];

  static const delegate = _AppStringsDelegate();

  static AppStrings of(BuildContext context) {
    final value = Localizations.of<AppStrings>(context, AppStrings);
    assert(value != null, 'AppStrings not found in context');
    return value!;
  }

  bool get isJapanese => locale.languageCode == 'ja';
  bool get isChinese => locale.languageCode == 'zh';
  bool get isKorean => locale.languageCode == 'ko';
  bool get isSpanish => locale.languageCode == 'es';
  bool get isGerman => locale.languageCode == 'de';

  String localized({
    required String en,
    required String ja,
    String? zh,
    String? ko,
    String? es,
    String? de,
  }) {
    return switch (locale.languageCode) {
      'ja' => ja,
      'zh' => zh ?? en,
      'ko' => ko ?? en,
      'es' => es ?? en,
      'de' => de ?? en,
      _ => en,
    };
  }

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
      'home.lock.private.access': 'Lock private access',
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
      'home.insights.summary.empty':
          'Your writing activity will appear here. Write for a few days to make trends visible.',
      'home.insights.summary.active':
          'This month has {thisMonthCount} notes. Your best day was {bestDayLabel}. Keeping a streak makes progress easier to see.',
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
    'es': {
      'action.delete': 'Eliminar',
      'date.yesterday': 'Ayer',
      'date.weekday.mon.short': 'lun',
      'date.weekday.tue.short': 'mar',
      'date.weekday.wed.short': 'mié',
      'date.weekday.thu.short': 'jue',
      'date.weekday.fri.short': 'vie',
      'date.weekday.sat.short': 'sáb',
      'date.weekday.sun.short': 'dom',
      'date.month.1': 'enero',
      'date.month.2': 'febrero',
      'date.month.3': 'marzo',
      'date.month.4': 'abril',
      'date.month.5': 'mayo',
      'date.month.6': 'junio',
      'date.month.7': 'julio',
      'date.month.8': 'agosto',
      'date.month.9': 'septiembre',
      'date.month.10': 'octubre',
      'date.month.11': 'noviembre',
      'date.month.12': 'diciembre',
      'notes.empty.title': 'No hay notas coincidentes',
      'notes.empty.body':
          'Crea una nueva nota o borra el filtro de búsqueda actual para ver las entradas guardadas.',
      'home.remote.bundle.storage.is.not.configured.yet':
          'El almacenamiento del paquete remoto aún no está configurado.',
      'home.remote.bundle.storage.is.not.configured.yet.2':
          'El paquete remoto aún no está configurado.',
      'home.no.remote.bundle.metadata.loaded.yet':
          'Aún no se han cargado metadatos del paquete remoto.',
      'home.lock.private.access': 'Bloquear acceso privado',
      'home.use.a.4.digit.pin.for.this.browser':
          'Usa un PIN de 4 dígitos para este navegador.',
      'home.pin.must.be.exactly.4.digits':
          'El PIN debe tener exactamente 4 dígitos.',
      'home.pin.must.contain.digits.only': 'El PIN solo debe contener dígitos.',
      'home.pin.confirmation.did.not.match':
          'La confirmación del PIN no coincide.',
      'settings.demo.create': 'Crear notas de demostración',
      'settings.demo.create.none': 'No hay notas de demostración para crear.',
      'settings.demo.create.done': 'Se crearon {count} notas de demostración.',
      'settings.demo.delete': 'Eliminar notas de demostración',
      'settings.demo.delete.title': '¿Eliminar notas de demostración?',
      'settings.demo.delete.body':
          'Esto elimina {count} notas de demostración de este dispositivo. Las notas que creaste no se eliminan.',
      'settings.demo.delete.done':
          'Se eliminaron {count} notas de demostración.',
    },
    'de': {
      'action.delete': 'Löschen',
      'date.yesterday': 'Gestern',
      'date.weekday.mon.short': 'Mo',
      'date.weekday.tue.short': 'Di',
      'date.weekday.wed.short': 'Mi',
      'date.weekday.thu.short': 'Do',
      'date.weekday.fri.short': 'Fr',
      'date.weekday.sat.short': 'Sa',
      'date.weekday.sun.short': 'So',
      'date.month.1': 'Januar',
      'date.month.2': 'Februar',
      'date.month.3': 'März',
      'date.month.4': 'April',
      'date.month.5': 'Mai',
      'date.month.6': 'Juni',
      'date.month.7': 'Juli',
      'date.month.8': 'August',
      'date.month.9': 'September',
      'date.month.10': 'Oktober',
      'date.month.11': 'November',
      'date.month.12': 'Dezember',
      'notes.empty.title': 'Keine passenden Notizen',
      'notes.empty.body':
          'Erstelle eine neue Notiz oder lösche den aktuellen Suchfilter, um gespeicherte Einträge zu sehen.',
      'home.remote.bundle.storage.is.not.configured.yet':
          'Der Remote-Bundle-Speicher ist noch nicht eingerichtet.',
      'home.remote.bundle.storage.is.not.configured.yet.2':
          'Das Remote-Bundle ist noch nicht eingerichtet.',
      'home.no.remote.bundle.metadata.loaded.yet':
          'Es wurden noch keine Remote-Bundle-Metadaten geladen.',
      'home.lock.private.access': 'Privaten Zugriff sperren',
      'home.use.a.4.digit.pin.for.this.browser':
          'Verwende eine 4-stellige PIN für diesen Browser.',
      'home.pin.must.be.exactly.4.digits':
          'Die PIN muss genau 4 Ziffern haben.',
      'home.pin.must.contain.digits.only':
          'Die PIN darf nur Ziffern enthalten.',
      'home.pin.confirmation.did.not.match':
          'Die PIN-Bestätigung stimmt nicht überein.',
      'settings.demo.create': 'Demo-Notizen erstellen',
      'settings.demo.create.none': 'Keine Demo-Notizen zum Erstellen.',
      'settings.demo.create.done': '{count} Demo-Notizen erstellt.',
      'settings.demo.delete': 'Demo-Notizen löschen',
      'settings.demo.delete.title': 'Demo-Notizen löschen?',
      'settings.demo.delete.body':
          'Dies löscht {count} Demo-Notizen von diesem Gerät. Von dir erstellte Notizen werden nicht gelöscht.',
      'settings.demo.delete.done': '{count} Demo-Notizen gelöscht.',
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
      'home.lock.private.access': 'ロックする',
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
      'home.insights.summary.empty': '書いた量がここにたまります。まずは数日続けてみると変化が見えます。',
      'home.insights.summary.active':
          '今月は {thisMonthCount} 件、最も書いた日は {bestDayLabel} です。連続記録を保つと積み上がりが見えやすくなります。',
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
    'zh': {
      'action.delete': '删除',
      'date.yesterday': '昨天',
      'date.weekday.mon.short': '周一',
      'date.weekday.tue.short': '周二',
      'date.weekday.wed.short': '周三',
      'date.weekday.thu.short': '周四',
      'date.weekday.fri.short': '周五',
      'date.weekday.sat.short': '周六',
      'date.weekday.sun.short': '周日',
      'date.month.1': '1月',
      'date.month.2': '2月',
      'date.month.3': '3月',
      'date.month.4': '4月',
      'date.month.5': '5月',
      'date.month.6': '6月',
      'date.month.7': '7月',
      'date.month.8': '8月',
      'date.month.9': '9月',
      'date.month.10': '10月',
      'date.month.11': '11月',
      'date.month.12': '12月',
      'notes.empty.title': '没有匹配的笔记',
      'notes.empty.body': '创建新备忘录，或清除当前搜索条件以查看已保存的条目。',
      'home.admin.mode.active': '管理员模式已启用',
      'home.switch.private.access': '切换私密访问',
      'home.lock': '锁定',
      'home.lock.private.access': '锁定私密访问',
      'home.unlock': '解锁',
      'home.delete.note': '删除笔记',
      'home.delete': '删除',
      'home.previous.month': '上个月',
      'home.next.month': '下个月',
      'home.writing.activity': '书写活动',
      'home.monthly.notes': '每月笔记',
      'home.notes': ' 条笔记',
      'home.recent.days': '最近几天',
      'home.weekday.and.time.rhythm': '星期与时间节奏',
      'home.attachments': '附件',
      'home.items': ' 项',
      'home.current.streak': '当前连续记录',
      'home.days': '天',
      'home.this.month': '本月',
      'home.notes.2': '条笔记',
      'home.characters': '字符数',
      'home.total': '总计',
      'home.items.2': '项',
      'home.best.day': '最佳日期',
      'home.best.hour': '最佳时段',
      'home.peak.time': '高峰时间',
      'home.monthly.trend': '月度趋势',
      'home.vs.last.month': '较上月',
      'home.no.data.yet': '暂无数据。',
      'home.less': '少',
      'home.more': '多',
      'home.photo': '照片',
      'home.video': '视频',
      'home.audio': '音频',
      'home.reset': '重置',
      'home.add.private.profile': '添加私密档案',
      'home.profile.name': '档案名称',
      'home.add': '添加',
      'home.new.password': '新密码',
      'home.confirm.new.password': '确认新密码',
      'home.normal.memo.mode': '普通备忘录模式',
      'home.device.only.storage': '仅设备存储',
      'home.mode': '模式',
      'home.enabled': '已启用',
      'home.disabled': '已停用',
      'home.off': '关闭',
      'home.configured': '已配置',
      'home.theme': '主题',
      'home.access.modes': '访问模式',
      'home.current.mode': '当前模式',
      'home.app.security': '应用安全',
      'home.save.pin': '保存 PIN',
      'home.session.status': '会话状态',
      'home.update.pin': '更新 PIN',
      'home.change.pin': '更改 PIN',
      'home.set.pin': '设置 PIN',
      'home.remove': '移除',
      'home.remove.pin': '移除 PIN',
      'home.immediately': '立即',
      'home.after.30.seconds': '30 秒后',
      'home.after.2.minutes': '2 分钟后',
      'home.after.10.minutes': '10 分钟后',
      'home.authenticate.now': '立即认证',
      'home.lock.session.now': '立即锁定会话',
      'home.external.quick.memo': '外部快速备忘录',
      'home.write.target': '写入目标',
      'home.private.vault': '私密保险库',
      'home.status': '状态',
      'home.set.private.key': '设置私密密钥',
      'home.backup.and.sync': '备份与同步',
      'home.selected.target': '已选择目标',
      'home.pending.sync.queue': '待同步队列',
      'home.queue.ready': '队列就绪',
      'home.remote.bundle': '远程包',
      'home.copy.recovery.key': '复制恢复密钥',
      'home.last.sync.activity': '最近同步活动',
      'home.local.bundle.cache': '本地包缓存',
      'home.refresh.remote': '刷新远程',
      'home.upload.bundle': '上传包',
      'home.force.upload': '强制上传',
      'home.bundle.history': '包历史',
      'home.download.bundle': '下载包',
      'home.review.bundle': '查看包',
      'home.apply.bundle': '应用包',
      'home.inspect.snapshot': '检查快照',
      'home.storage': '存储',
      'home.cancel': '取消',
      'home.icloud.availability': 'iCloud 可用性',
      'home.authentication': '认证',
      'home.check.icloud': '检查 iCloud',
      'home.connect': '连接',
      'home.check.again': '再次检查',
      'home.reconnect': '重新连接',
      'home.stop.using.icloud': '停止使用 iCloud',
      'home.disconnect': '断开连接',
      'home.sync.is.disabled': '同步已关闭。',
      'home.previous.note': '上一条笔记',
      'home.next.note': '下一条笔记',
      'home.previous.image': '上一张图片',
      'home.next.image': '下一张图片',
      'home.restore.frame': '恢复框内显示',
      'home.maximize': '最大化',
      'home.zoom.out': '缩小',
      'home.zoom.in': '放大',
      'home.fit.to.screen': '适合屏幕',
      'home.share': '分享',
      'home.pause.audio': '暂停音频',
      'home.play.audio': '播放音频',
      'home.list.layout': '列表布局',
      'home.standard.list': '标准列表',
      'home.compact.list': '紧凑列表',
      'home.filters': '筛选',
      'home.pinned.only': '仅固定',
      'home.with.media': '含媒体',
      'home.vault': '分类',
      'home.filter.by.tag': '按标签筛选',
      'home.reset.filters': '重置筛选',
      'home.select.a.note': '选择笔记',
      'home.private.profile': '私密档案',
      'home.tags': '标签',
      'home.add.a.tag': '添加标签',
      'home.tap.to.open.image': '点按打开图片',
      'home.import.recovery.key': '导入恢复密钥',
      'home.import': '导入',
      'home.confirm.pin': '确认 PIN',
      'home.unlock.private.profile': '解锁私密档案',
      'home.unlock.private.profile.2': '解锁私密档案',
      'settings.demo.create': '创建演示笔记',
      'settings.demo.create.none': '没有可创建的演示笔记。',
      'settings.demo.create.done': '已创建 {count} 条演示笔记。',
      'settings.demo.delete': '删除演示笔记',
      'settings.demo.delete.title': '要删除演示笔记吗？',
      'settings.demo.delete.body': '将从此设备删除 {count} 条演示笔记。你创建的笔记不会被删除。',
      'settings.demo.delete.done': '已删除 {count} 条演示笔记。',
      'home.use.japanese.across.the.app': '在整个应用中使用日语。',
      'home.use.english.across.the.app': '在整个应用中使用英语。',
      'home.use.chinese.across.the.app': '在整个应用中使用中文。',
      'home.use.korean.across.the.app': '在整个应用中使用韩语。',
      'home.no.private.profile.matched.that.password': '没有匹配该密码的私密档案。',
      'home.private.profile.unlocked': '私密档案已解锁。',
      'home.admin.mode.is.currently.active': '当前为管理员模式。',
      'home.profile.password': '档案密码',
      'home.enter.a.password': '请输入密码。',
      'home.review.notes.grouped.by.day.and.keep.diary.entries.ancho':
          '按日期回顾笔记，并将日记条目固定到日期。',
      'home.previous.day.with.notes': '上一个有笔记的日期',
      'home.next.day.with.notes': '下一个有笔记的日期',
      'home.no.notes.on.this.day.yet': '这一天还没有笔记。',
      'home.previous.day.with.notes.2': '上一个有笔记的日期',
      'home.next.day.with.notes.2': '下一个有笔记的日期',
      'home.notes.created.over.the.last.6.months': '过去 6 个月创建的笔记。',
      'home.daily.note.count.over.the.last.14.days': '过去 14 天的每日笔记数。',
      'home.notes.by.weekday.and.3.hour.time.block': '按星期和 3 小时时段统计笔记。',
      'home.how.often.photos.videos.and.audio.are.used': '照片、视频和音频的使用频率。',
      'home.alternate.profile.password': '备用档案密码',
      'home.confirm.alternate.profile.password': '确认备用档案密码',
      'home.use.this.password.to.switch.to.a.different.everyday.prof':
          '使用此密码切换到另一个日常档案。',
      'home.alternate.profile.password.saved': '备用档案密码已保存。',
      'home.this.removes.the.configured.password.for.the.alternate.p':
          '这将移除为备用档案设置的密码。',
      'home.profile.password.2': '档案密码',
      'home.enter.a.password.2': '请输入密码。',
      'home.confirm.password': '确认密码',
      'home.passwords.do.not.match': '密码不一致。',
      'home.private.profile.added.and.opened': '已添加并打开私密档案。',
      'home.admin.mode.is.not.available.in.this.environment': '此环境不支持管理员模式。',
      'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h':
          '管理员模式已解锁。档案名称和保险库 ID 仍会隐藏。',
      'home.change.current.profile.password': '更改当前档案密码',
      'home.change.current.profile.password.2': '更改当前档案密码',
      'home.update.the.password.used.to.unlock.this.profile': '更新用于解锁此档案的密码。',
      'home.profile.password.updated': '档案密码已更新。',
      'home.off.turning.this.on.asks.for.a.password.or.device.authen':
          '关闭。开启后会要求输入密码或进行设备认证。',
      'home.on.this.session.is.unlocked': '开启。此会话已解锁。',
      'home.on.this.session.is.locked': '开启。此会话已锁定。',
      'home.manage.access.sync.and.display.policy': '管理访问、同步和显示策略。',
      'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe':
          '应用默认保持普通备忘录模式。仅在需要其他视图时输入特殊访问密钥。',
      'home.enter.special.access.key': '输入特殊访问密钥',
      'home.return.to.normal.mode': '返回普通模式',
      'home.require.pin.on.launch': '启动时要求 PIN',
      'home.require.device.auth.on.launch': '启动时要求设备认证',
      'home.set.unlock.pin': '设置解锁 PIN',
      'home.set.unlock.pin.2': '设置解锁 PIN',
      'home.device.authentication.was.not.completed.so.launch.protec':
          '设备认证未完成，因此启动保护保持关闭。',
      'home.when.icloud.sync.is.selected.this.key.is.shared.automati':
          '选择 iCloud 同步时，此密钥会在登录同一 iCloud 账户的 Apple 设备间自动共享，无需手动传输。',
      'home.this.session.is.currently.unlocked': '此会话当前已解锁。',
      'home.this.browser.stays.locked.until.the.correct.pin.is.enter':
          '在输入正确 PIN 前，此浏览器会保持锁定。',
      'home.this.session.stays.locked.until.device.authentication.su':
          '在设备认证成功前，此会话会保持锁定。',
      'home.change.unlock.pin': '更改解锁 PIN',
      'home.unlock.pin.updated': '解锁 PIN 已更新。',
      'home.unlock.pin.configured': '解锁 PIN 已配置。',
      'home.remove.unlock.pin': '移除解锁 PIN',
      'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off':
          '要移除此浏览器的 Web 解锁 PIN 并关闭启动 PIN 保护吗？',
      'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla':
          'Web PIN 是浏览器级访问门禁，不能替代设备级安全存储或生物认证。',
      'home.quick.widget.capture.only.writes.plain.text.into.notes.i':
          '快捷组件捕获只会将纯文本写入 Notes，不会显示现有笔记。',
      'home.re.lock.after.app.leaves.the.foreground': '应用离开前台后重新锁定',
      'home.lock.the.app.as.soon.as.it.moves.to.the.background': '应用进入后台后立即锁定。',
      'home.allow.quick.app.switching.without.immediate.re.auth':
          '允许快速切换应用而无需立即重新认证。',
      'home.useful.when.capturing.photos.or.audio.between.notes':
          '适合在笔记之间拍照或录音时使用。',
      'home.keep.the.app.open.during.longer.editing.sessions':
          '在较长编辑会话中保持应用打开。',
      'home.lock.legacy.private.area.when.app.locks': '应用锁定时也锁定旧私密区域',
      'home.normally.this.locks.whenever.the.app.locks': '通常会随应用锁定而锁定。',
      'home.pin.unlock.on.lock.screen': '锁屏上的 PIN 解锁',
      'home.web.pin.active': 'Web PIN 已启用',
      'home.refresh.availability': '刷新可用性',
      'home.allow.widget.writes.while.locked': '锁定时允许组件写入',
      'home.only.the.submitted.text.is.saved.existing.notes.and.lock':
          '只保存提交的文本。现有笔记和已锁定档案保持隐藏。',
      'home.widget.quick.writes.are.allowed.while.the.app.is.locked':
          '应用锁定时允许组件快速写入。',
      'home.widget.quick.writes.are.off': '组件快速写入已关闭。',
      'home.configured.and.currently.unlocked': '已配置，当前已解锁',
      'home.configured.and.locked': '已配置并锁定',
      'home.no.private.vault.key.has.been.set.yet': '尚未设置私密保险库密钥。',
      'home.configured.and.unlocked.for.this.session': '已配置，并在此会话中解锁。',
      'home.configured.and.locked.a.separate.key.is.required': '已配置并锁定。需要单独密钥。',
      'home.not.configured.yet.set.a.separate.key.for.the.private.va':
          '尚未配置。请为私密保险库设置单独密钥。',
      'home.unlock.private.vault': '解锁私密保险库',
      'home.lock.private.vault': '锁定私密保险库',
      'home.no.pending.device.changes': '没有待处理的设备更改。',
      'home.checking.pending.changes': '正在检查待处理更改',
      'home.unable.to.inspect.the.local.sync.queue': '无法检查本地同步队列。',
      'home.no.cloud.account.is.connected': '尚未连接云端账户。',
      'home.no.cloud.account.is.connected.2': '尚未连接云端账户。',
      'home.no.account.connected.yet': '尚未连接账户。',
      'home.no.account.connected.yet.2': '尚未连接账户。',
      'home.waiting.for.authentication.to.complete': '正在等待认证完成。',
      'home.waiting.for.authentication.to.complete.2': '正在等待认证完成。',
      'home.authentication.is.not.available': '认证不可用。',
      'home.authentication.is.not.available.2': '认证不可用。',
      'home.cloud.recovery.key.fingerprint': '云端恢复密钥指纹',
      'home.preparing.cloud.recovery.key': '正在准备云端恢复密钥',
      'home.unable.to.read.the.cloud.recovery.key.fingerprint': '无法读取云端恢复密钥指纹。',
      'home.cloud.recovery.key.copied.to.clipboard': '云端恢复密钥已复制到剪贴板。',
      'home.no.sync.activity.has.been.recorded.on.this.device.yet':
          '此设备尚未记录同步活动。',
      'home.reading.sync.activity': '正在读取同步活动',
      'home.unable.to.read.local.sync.activity': '无法读取本地同步活动。',
      'home.keep.data.on.this.device.only': '只在此设备上保存数据。',
      'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo':
          '使用此设备的 iCloud 作为同步目标。不需要 HiMemo 登录。',
      'home.google.drive.app.data.sync.target': 'Google Drive 应用数据同步目标。',
      'home.icloud.selected.the.app.checks.this.device.s.icloud.avai':
          '已选择 iCloud。应用会检查此设备的 iCloud 可用性。',
      'home.this.device.s.icloud.availability.has.not.been.checked.y':
          '尚未检查此设备的 iCloud 可用性。',
      'home.checking.this.device.s.icloud.availability': '正在检查此设备的 iCloud 可用性。',
      'home.this.device.can.use.icloud.as.the.himemo.sync.target':
          '此设备可以将 iCloud 用作 HiMemo 同步目标。',
      'home.icloud.sync.is.not.available.on.this.device': '此设备无法使用 iCloud 同步。',
      'home.google.drive.selected.authorize.access.to.drive.app.data':
          '已选择 Google Drive。请授权访问 Drive 应用数据。',
      'home.a.newer.remote.bundle.was.found.while.this.device.still':
          '发现了更新的远程包，但此设备仍有本地更改。',
      'home.force.upload.2': '强制上传',
      'home.no.remote.bundle.history.is.available': '没有可用的远程包历史。',
      'home.keep.for.apply': '保留以应用',
      'home.selected.bundle.is.ready.for.apply': '所选包已准备好应用。',
      'home.prepared.sync.snapshot': '已准备同步快照',
      'home.saved.notes.on.this.device': '此设备上保存的笔记',
      'home.search.notes.diary.entries.and.attachment.labels': '搜索笔记、日记条目和附件标签',
      'home.search.terms.are.cleared.when.private.mode.closes':
          '私密模式关闭时会清除搜索词。',
      'home.add.tags.to.narrow.the.list': '添加标签以缩小列表范围',
      'home.all.visible.vaults': '所有可见分类',
      'home.pick.a.note.from.the.list.to.preview.it.here': '从列表中选择笔记在此预览。',
      'home.swipe.left.or.right.to.move.between.notes': '左右滑动可在笔记之间移动。',
      'home.choose.which.private.profile.to.save.into.while.in.admin':
          '在管理员模式下选择要保存到的私密档案。',
      'home.save.into.the.currently.unlocked.private.profile': '保存到当前已解锁的私密档案。',
      'home.save.to.private.profile': '保存到私密档案',
      'home.type.a.tag.and.press.enter': '输入标签并按 Enter',
      'home.locked.profiles.are.hidden.unlock.the.target.profile.fro':
          '已锁定的档案会被隐藏。请从设置中解锁目标档案以显示其笔记。',
      'home.remote.bundle.storage.is.not.configured.yet': '远程包存储尚未配置。',
      'home.no.icloud.bundle.metadata.loaded.yet': '尚未加载 iCloud 包元数据。',
      'home.remote.bundle.transport.is.not.available.yet': '远程包传输尚不可用。',
      'home.remote.bundle.storage.is.not.configured.yet.2': '远程包尚未配置。',
      'home.no.icloud.bundle.metadata.loaded.yet.2': '尚未加载 iCloud 包元数据。',
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r':
          '远程包传输目前仅支持 Google Drive。',
      'home.no.remote.bundle.metadata.loaded.yet': '尚未加载远程包元数据。',
      'home.removed.locally.after.apply': '应用后会从此设备移除的笔记',
      'home.paste.himemo.sync.key.v1': '粘贴 himemo-sync-key-v1:...',
      'home.use.a.4.digit.pin.for.this.browser': '为此浏览器设置 4 位 PIN。',
      'home.reset.private.key': '重置私密密钥',
      'home.pin.must.be.exactly.4.digits': 'PIN 必须正好为 4 位。',
      'home.pin.must.contain.digits.only': 'PIN 只能包含数字。',
      'home.pin.confirmation.did.not.match': '确认 PIN 不匹配。',
      'home.bundle.review': '包审核',
      'home.added.notes': '新增笔记',
      'home.updated.notes': '更新笔记',
      'home.remote.bundle.history': '远程包历史',
      'home.unknown.time': '未知时间',
      'home.unknown.time.2': '未知时间',
      'home.size.unknown': '大小未知',
      'home.unknown.device': '未知设备',
    },
    'ko': {
      'action.delete': '삭제',
      'date.yesterday': '어제',
      'date.weekday.mon.short': '월',
      'date.weekday.tue.short': '화',
      'date.weekday.wed.short': '수',
      'date.weekday.thu.short': '목',
      'date.weekday.fri.short': '금',
      'date.weekday.sat.short': '토',
      'date.weekday.sun.short': '일',
      'date.month.1': '1월',
      'date.month.2': '2월',
      'date.month.3': '3월',
      'date.month.4': '4월',
      'date.month.5': '5월',
      'date.month.6': '6월',
      'date.month.7': '7월',
      'date.month.8': '8월',
      'date.month.9': '9월',
      'date.month.10': '10월',
      'date.month.11': '11월',
      'date.month.12': '12월',
      'notes.empty.title': '일치하는 노트가 없습니다',
      'notes.empty.body': '새 메모를 만들거나 현재 검색 조건을 지우면 저장된 항목을 볼 수 있습니다.',
      'home.admin.mode.active': '관리자 모드 활성화',
      'home.switch.private.access': '비공개 접근 전환',
      'home.lock': '잠금',
      'home.lock.private.access': '비공개 접근 잠금',
      'home.unlock': '잠금 해제',
      'home.delete.note': '노트 삭제',
      'home.delete': '삭제',
      'home.previous.month': '이전 달',
      'home.next.month': '다음 달',
      'home.writing.activity': '작성 활동',
      'home.monthly.notes': '월별 노트',
      'home.notes': '개 노트',
      'home.recent.days': '최근 일수',
      'home.weekday.and.time.rhythm': '요일 및 시간 리듬',
      'home.attachments': '첨부',
      'home.items': '개 항목',
      'home.current.streak': '현재 연속 기록',
      'home.days': '일',
      'home.this.month': '이번 달',
      'home.notes.2': '노트',
      'home.characters': '문자 수',
      'home.total': '합계',
      'home.items.2': '항목',
      'home.best.day': '가장 많이 쓴 날',
      'home.best.hour': '가장 많이 쓴 시간',
      'home.peak.time': '피크 시간',
      'home.monthly.trend': '월간 추세',
      'home.vs.last.month': '지난달 대비',
      'home.no.data.yet': '아직 데이터가 없습니다.',
      'home.less': '적음',
      'home.more': '많음',
      'home.photo': '사진',
      'home.video': '동영상',
      'home.audio': '오디오',
      'home.reset': '재설정',
      'home.add.private.profile': '비공개 프로필 추가',
      'home.profile.name': '프로필 이름',
      'home.add': '추가',
      'home.new.password': '새 비밀번호',
      'home.confirm.new.password': '새 비밀번호 확인',
      'home.normal.memo.mode': '일반 메모 모드',
      'home.device.only.storage': '기기 전용 저장소',
      'home.mode': '모드',
      'home.enabled': '사용',
      'home.disabled': '사용 안 함',
      'home.off': '꺼짐',
      'home.configured': '설정됨',
      'home.theme': '테마',
      'home.access.modes': '접근 모드',
      'home.current.mode': '현재 모드',
      'home.app.security': '앱 보안',
      'home.save.pin': 'PIN 저장',
      'home.session.status': '세션 상태',
      'home.update.pin': 'PIN 업데이트',
      'home.change.pin': 'PIN 변경',
      'home.set.pin': 'PIN 설정',
      'home.remove': '제거',
      'home.remove.pin': 'PIN 제거',
      'home.immediately': '즉시',
      'home.after.30.seconds': '30초 후',
      'home.after.2.minutes': '2분 후',
      'home.after.10.minutes': '10분 후',
      'home.authenticate.now': '지금 인증',
      'home.lock.session.now': '지금 세션 잠금',
      'home.external.quick.memo': '외부 빠른 메모',
      'home.write.target': '작성 대상',
      'home.private.vault': '비공개 보관함',
      'home.status': '상태',
      'home.set.private.key': '비공개 키 설정',
      'home.backup.and.sync': '백업 및 동기화',
      'home.selected.target': '선택된 대상',
      'home.pending.sync.queue': '대기 중인 동기화 큐',
      'home.queue.ready': '큐 준비됨',
      'home.remote.bundle': '원격 번들',
      'home.copy.recovery.key': '복구 키 복사',
      'home.last.sync.activity': '최근 동기화 활동',
      'home.local.bundle.cache': '로컬 번들 캐시',
      'home.refresh.remote': '원격 새로고침',
      'home.upload.bundle': '번들 업로드',
      'home.force.upload': '강제 업로드',
      'home.bundle.history': '번들 기록',
      'home.download.bundle': '번들 다운로드',
      'home.review.bundle': '번들 검토',
      'home.apply.bundle': '번들 적용',
      'home.inspect.snapshot': '스냅샷 검사',
      'home.storage': '저장소',
      'home.cancel': '취소',
      'home.icloud.availability': 'iCloud 사용 가능 여부',
      'home.authentication': '인증',
      'home.check.icloud': 'iCloud 확인',
      'home.connect': '연결',
      'home.check.again': '다시 확인',
      'home.reconnect': '다시 연결',
      'home.stop.using.icloud': 'iCloud 사용 중지',
      'home.disconnect': '연결 해제',
      'home.sync.is.disabled': '동기화가 꺼져 있습니다.',
      'home.previous.note': '이전 노트',
      'home.next.note': '다음 노트',
      'home.previous.image': '이전 이미지',
      'home.next.image': '다음 이미지',
      'home.restore.frame': '프레임으로 되돌리기',
      'home.maximize': '최대화',
      'home.zoom.out': '축소',
      'home.zoom.in': '확대',
      'home.fit.to.screen': '화면에 맞춤',
      'home.share': '공유',
      'home.pause.audio': '오디오 일시정지',
      'home.play.audio': '오디오 재생',
      'home.list.layout': '목록 레이아웃',
      'home.standard.list': '표준 목록',
      'home.compact.list': '간결한 목록',
      'home.filters': '필터',
      'home.pinned.only': '고정만',
      'home.with.media': '미디어 포함',
      'home.vault': '분류',
      'home.filter.by.tag': '태그로 필터',
      'home.reset.filters': '필터 재설정',
      'home.select.a.note': '노트 선택',
      'home.private.profile': '비공개 프로필',
      'home.tags': '태그',
      'home.add.a.tag': '태그 추가',
      'home.tap.to.open.image': '탭하여 이미지 열기',
      'home.import.recovery.key': '복구 키 가져오기',
      'home.import': '가져오기',
      'home.confirm.pin': 'PIN 확인',
      'home.unlock.private.profile': '비공개 프로필 잠금 해제',
      'home.unlock.private.profile.2': '비공개 프로필 잠금 해제',
      'settings.demo.create': '데모 노트 만들기',
      'settings.demo.create.none': '만들 수 있는 데모 노트가 없습니다.',
      'settings.demo.create.done': '데모 노트 {count}개를 만들었습니다.',
      'settings.demo.delete': '데모 노트 삭제',
      'settings.demo.delete.title': '데모 노트를 삭제할까요?',
      'settings.demo.delete.body':
          '이 기기에서 데모 노트 {count}개를 삭제합니다. 직접 만든 노트는 삭제되지 않습니다.',
      'settings.demo.delete.done': '데모 노트 {count}개를 삭제했습니다.',
      'home.use.japanese.across.the.app': '앱 전체에서 일본어를 사용합니다.',
      'home.use.english.across.the.app': '앱 전체에서 영어를 사용합니다.',
      'home.use.chinese.across.the.app': '앱 전체에서 중국어를 사용합니다.',
      'home.use.korean.across.the.app': '앱 전체에서 한국어를 사용합니다.',
      'home.no.private.profile.matched.that.password':
          '해당 비밀번호와 일치하는 비공개 프로필이 없습니다.',
      'home.private.profile.unlocked': '비공개 프로필이 잠금 해제되었습니다.',
      'home.admin.mode.is.currently.active': '현재 관리자 모드입니다.',
      'home.profile.password': '프로필 비밀번호',
      'home.enter.a.password': '비밀번호를 입력하세요.',
      'home.review.notes.grouped.by.day.and.keep.diary.entries.ancho':
          '날짜별로 노트를 돌아보고 일기 항목을 날짜에 고정해 봅니다.',
      'home.previous.day.with.notes': '노트가 있는 이전 날짜',
      'home.next.day.with.notes': '노트가 있는 다음 날짜',
      'home.no.notes.on.this.day.yet': '이 날짜에는 아직 노트가 없습니다.',
      'home.previous.day.with.notes.2': '노트가 있는 이전 날짜',
      'home.next.day.with.notes.2': '노트가 있는 다음 날짜',
      'home.notes.created.over.the.last.6.months': '최근 6개월 동안 만든 노트입니다.',
      'home.daily.note.count.over.the.last.14.days': '최근 14일의 일별 노트 수입니다.',
      'home.notes.by.weekday.and.3.hour.time.block': '요일과 3시간 단위별 노트입니다.',
      'home.how.often.photos.videos.and.audio.are.used':
          '사진, 동영상, 오디오 사용 빈도입니다.',
      'home.alternate.profile.password': '대체 프로필 비밀번호',
      'home.confirm.alternate.profile.password': '대체 프로필 비밀번호 확인',
      'home.use.this.password.to.switch.to.a.different.everyday.prof':
          '이 비밀번호로 다른 일상 프로필로 전환합니다.',
      'home.alternate.profile.password.saved': '대체 프로필 비밀번호를 저장했습니다.',
      'home.this.removes.the.configured.password.for.the.alternate.p':
          '대체 프로필에 설정된 비밀번호를 제거합니다.',
      'home.profile.password.2': '프로필 비밀번호',
      'home.enter.a.password.2': '비밀번호를 입력하세요.',
      'home.confirm.password': '비밀번호 확인',
      'home.passwords.do.not.match': '비밀번호가 일치하지 않습니다.',
      'home.private.profile.added.and.opened': '비공개 프로필을 추가하고 열었습니다.',
      'home.admin.mode.is.not.available.in.this.environment':
          '이 환경에서는 관리자 모드를 사용할 수 없습니다.',
      'home.admin.mode.unlocked.profile.names.and.vault.ids.remain.h':
          '관리자 모드가 해제되었습니다. 프로필 이름과 보관함 ID는 계속 숨겨집니다.',
      'home.change.current.profile.password': '현재 프로필 비밀번호 변경',
      'home.change.current.profile.password.2': '현재 프로필 비밀번호 변경',
      'home.update.the.password.used.to.unlock.this.profile':
          '이 프로필을 잠금 해제하는 비밀번호를 업데이트합니다.',
      'home.profile.password.updated': '프로필 비밀번호를 업데이트했습니다.',
      'home.off.turning.this.on.asks.for.a.password.or.device.authen':
          '꺼짐. 켜면 비밀번호 또는 기기 인증을 요청합니다.',
      'home.on.this.session.is.unlocked': '켜짐. 이 세션은 잠금 해제되었습니다.',
      'home.on.this.session.is.locked': '켜짐. 이 세션은 잠겨 있습니다.',
      'home.manage.access.sync.and.display.policy': '접근, 동기화, 표시 정책을 관리합니다.',
      'home.the.app.stays.in.normal.memo.mode.by.default.enter.a.spe':
          '앱은 기본적으로 일반 메모 모드로 유지됩니다. 다른 보기가 필요할 때만 특수 접근 키를 입력하세요.',
      'home.enter.special.access.key': '특수 접근 키 입력',
      'home.return.to.normal.mode': '일반 모드로 돌아가기',
      'home.require.pin.on.launch': '실행 시 PIN 요구',
      'home.require.device.auth.on.launch': '실행 시 기기 인증 요구',
      'home.set.unlock.pin': '잠금 해제 PIN 설정',
      'home.set.unlock.pin.2': '잠금 해제 PIN 설정',
      'home.device.authentication.was.not.completed.so.launch.protec':
          '기기 인증이 완료되지 않아 실행 보호가 꺼진 상태로 유지되었습니다.',
      'home.when.icloud.sync.is.selected.this.key.is.shared.automati':
          'iCloud 동기화를 선택하면 같은 iCloud 계정의 Apple 기기 간에 이 키가 자동 공유됩니다. 수동 전송은 필요 없습니다.',
      'home.this.session.is.currently.unlocked': '이 세션은 현재 잠금 해제되어 있습니다.',
      'home.this.browser.stays.locked.until.the.correct.pin.is.enter':
          '올바른 PIN을 입력할 때까지 이 브라우저는 잠겨 있습니다.',
      'home.this.session.stays.locked.until.device.authentication.su':
          '기기 인증이 성공할 때까지 이 세션은 잠겨 있습니다.',
      'home.change.unlock.pin': '잠금 해제 PIN 변경',
      'home.unlock.pin.updated': '잠금 해제 PIN을 업데이트했습니다.',
      'home.unlock.pin.configured': '잠금 해제 PIN이 설정되었습니다.',
      'home.remove.unlock.pin': '잠금 해제 PIN 제거',
      'home.remove.the.web.unlock.pin.for.this.browser.and.turn.off':
          '이 브라우저의 Web 잠금 해제 PIN을 제거하고 실행 PIN 보호를 끌까요?',
      'home.web.pin.is.a.browser.level.access.gate.it.does.not.repla':
          'Web PIN은 브라우저 수준의 접근 장치이며 기기 기반 보안 저장소나 생체 인증을 대체하지 않습니다.',
      'home.quick.widget.capture.only.writes.plain.text.into.notes.i':
          '빠른 위젯 캡처는 일반 텍스트만 Notes에 저장하며 기존 노트는 표시하지 않습니다.',
      'home.re.lock.after.app.leaves.the.foreground': '앱이 전면을 벗어난 후 다시 잠금',
      'home.lock.the.app.as.soon.as.it.moves.to.the.background':
          '앱이 백그라운드로 이동하면 즉시 잠급니다.',
      'home.allow.quick.app.switching.without.immediate.re.auth':
          '즉시 재인증 없이 빠른 앱 전환을 허용합니다.',
      'home.useful.when.capturing.photos.or.audio.between.notes':
          '노트 사이에서 사진이나 오디오를 캡처할 때 유용합니다.',
      'home.keep.the.app.open.during.longer.editing.sessions':
          '긴 편집 세션 동안 앱을 열어 둡니다.',
      'home.lock.legacy.private.area.when.app.locks': '앱이 잠길 때 기존 비공개 영역도 잠금',
      'home.normally.this.locks.whenever.the.app.locks':
          '일반적으로 앱이 잠길 때 함께 잠깁니다.',
      'home.pin.unlock.on.lock.screen': '잠금 화면의 PIN 해제',
      'home.web.pin.active': 'Web PIN 활성화',
      'home.refresh.availability': '사용 가능 여부 새로고침',
      'home.allow.widget.writes.while.locked': '잠금 중 위젯 쓰기 허용',
      'home.only.the.submitted.text.is.saved.existing.notes.and.lock':
          '제출한 텍스트만 저장됩니다. 기존 노트와 잠긴 프로필은 숨겨진 상태로 유지됩니다.',
      'home.widget.quick.writes.are.allowed.while.the.app.is.locked':
          '앱이 잠겨 있어도 위젯 빠른 쓰기가 허용됩니다.',
      'home.widget.quick.writes.are.off': '위젯 빠른 쓰기가 꺼져 있습니다.',
      'home.configured.and.currently.unlocked': '설정됨, 현재 잠금 해제됨',
      'home.configured.and.locked': '설정됨, 잠김',
      'home.no.private.vault.key.has.been.set.yet': '아직 비공개 보관함 키가 설정되지 않았습니다.',
      'home.configured.and.unlocked.for.this.session':
          '설정되었고 이 세션에서 잠금 해제되었습니다.',
      'home.configured.and.locked.a.separate.key.is.required':
          '설정되었고 잠겨 있습니다. 별도 키가 필요합니다.',
      'home.not.configured.yet.set.a.separate.key.for.the.private.va':
          '아직 설정되지 않았습니다. 비공개 보관함용 별도 키를 설정하세요.',
      'home.unlock.private.vault': '비공개 보관함 잠금 해제',
      'home.lock.private.vault': '비공개 보관함 잠금',
      'home.no.pending.device.changes': '대기 중인 기기 변경 사항이 없습니다.',
      'home.checking.pending.changes': '대기 중인 변경 사항 확인 중',
      'home.unable.to.inspect.the.local.sync.queue': '로컬 동기화 큐를 확인할 수 없습니다.',
      'home.no.cloud.account.is.connected': '연결된 클라우드 계정이 없습니다.',
      'home.no.cloud.account.is.connected.2': '연결된 클라우드 계정이 없습니다.',
      'home.no.account.connected.yet': '아직 연결된 계정이 없습니다.',
      'home.no.account.connected.yet.2': '아직 연결된 계정이 없습니다.',
      'home.waiting.for.authentication.to.complete': '인증 완료를 기다리는 중입니다.',
      'home.waiting.for.authentication.to.complete.2': '인증 완료를 기다리는 중입니다.',
      'home.authentication.is.not.available': '인증을 사용할 수 없습니다.',
      'home.authentication.is.not.available.2': '인증을 사용할 수 없습니다.',
      'home.cloud.recovery.key.fingerprint': '클라우드 복구 키 지문',
      'home.preparing.cloud.recovery.key': '클라우드 복구 키 준비 중',
      'home.unable.to.read.the.cloud.recovery.key.fingerprint':
          '클라우드 복구 키 지문을 읽을 수 없습니다.',
      'home.cloud.recovery.key.copied.to.clipboard': '클라우드 복구 키를 클립보드에 복사했습니다.',
      'home.no.sync.activity.has.been.recorded.on.this.device.yet':
          '이 기기에 기록된 동기화 활동이 아직 없습니다.',
      'home.reading.sync.activity': '동기화 활동 읽는 중',
      'home.unable.to.read.local.sync.activity': '로컬 동기화 활동을 읽을 수 없습니다.',
      'home.keep.data.on.this.device.only': '이 기기에만 데이터를 보관합니다.',
      'home.use.this.device.s.icloud.as.the.sync.target.no.himemo.lo':
          '이 기기의 iCloud를 동기화 대상으로 사용합니다. HiMemo 로그인은 필요 없습니다.',
      'home.google.drive.app.data.sync.target': 'Google Drive 앱 데이터 동기화 대상입니다.',
      'home.icloud.selected.the.app.checks.this.device.s.icloud.avai':
          'iCloud가 선택되었습니다. 앱이 이 기기의 iCloud 사용 가능 여부를 확인합니다.',
      'home.this.device.s.icloud.availability.has.not.been.checked.y':
          '이 기기의 iCloud 사용 가능 여부를 아직 확인하지 않았습니다.',
      'home.checking.this.device.s.icloud.availability':
          '이 기기의 iCloud 사용 가능 여부 확인 중',
      'home.this.device.can.use.icloud.as.the.himemo.sync.target':
          '이 기기는 iCloud를 HiMemo 동기화 대상으로 사용할 수 있습니다.',
      'home.icloud.sync.is.not.available.on.this.device':
          '이 기기에서는 iCloud 동기화를 사용할 수 없습니다.',
      'home.google.drive.selected.authorize.access.to.drive.app.data':
          'Google Drive가 선택되었습니다. Drive 앱 데이터 접근 권한을 승인하세요.',
      'home.a.newer.remote.bundle.was.found.while.this.device.still':
          '더 새로운 원격 번들을 찾았지만 이 기기에는 아직 로컬 변경 사항이 있습니다.',
      'home.force.upload.2': '강제 업로드',
      'home.no.remote.bundle.history.is.available': '사용 가능한 원격 번들 기록이 없습니다.',
      'home.keep.for.apply': '적용을 위해 보관',
      'home.selected.bundle.is.ready.for.apply': '선택한 번들을 적용할 준비가 되었습니다.',
      'home.prepared.sync.snapshot': '동기화 스냅샷 준비됨',
      'home.saved.notes.on.this.device': '이 기기에 저장된 노트',
      'home.search.notes.diary.entries.and.attachment.labels':
          '노트, 일기 항목, 첨부 파일 이름 검색',
      'home.search.terms.are.cleared.when.private.mode.closes':
          '비공개 모드가 닫히면 검색어가 지워집니다.',
      'home.add.tags.to.narrow.the.list': '태그를 추가해 목록을 좁히세요',
      'home.all.visible.vaults': '보이는 모든 분류',
      'home.pick.a.note.from.the.list.to.preview.it.here':
          '목록에서 노트를 선택하면 여기에서 미리 볼 수 있습니다.',
      'home.swipe.left.or.right.to.move.between.notes':
          '좌우로 스와이프하여 노트 사이를 이동합니다.',
      'home.choose.which.private.profile.to.save.into.while.in.admin':
          '관리자 모드에서 저장할 비공개 프로필을 선택하세요.',
      'home.save.into.the.currently.unlocked.private.profile':
          '현재 잠금 해제된 비공개 프로필에 저장합니다.',
      'home.save.to.private.profile': '비공개 프로필에 저장',
      'home.type.a.tag.and.press.enter': '태그를 입력하고 Enter를 누르세요',
      'home.locked.profiles.are.hidden.unlock.the.target.profile.fro':
          '잠긴 프로필은 숨겨집니다. 노트를 보려면 설정에서 대상 프로필을 잠금 해제하세요.',
      'home.remote.bundle.storage.is.not.configured.yet':
          '원격 번들 저장소가 아직 설정되지 않았습니다.',
      'home.no.icloud.bundle.metadata.loaded.yet':
          'iCloud 번들 메타데이터를 아직 불러오지 않았습니다.',
      'home.remote.bundle.transport.is.not.available.yet':
          '원격 번들 전송은 아직 사용할 수 없습니다.',
      'home.remote.bundle.storage.is.not.configured.yet.2':
          '원격 번들이 아직 설정되지 않았습니다.',
      'home.no.icloud.bundle.metadata.loaded.yet.2':
          'iCloud 번들 메타데이터를 아직 불러오지 않았습니다.',
      'home.remote.bundle.transport.is.only.wired.for.google.drive.r':
          '원격 번들 전송은 현재 Google Drive만 지원합니다.',
      'home.no.remote.bundle.metadata.loaded.yet':
          '원격 번들 메타데이터를 아직 불러오지 않았습니다.',
      'home.removed.locally.after.apply': '적용 후 이 기기에서 제거될 노트',
      'home.paste.himemo.sync.key.v1': 'himemo-sync-key-v1:... 붙여넣기',
      'home.use.a.4.digit.pin.for.this.browser': '이 브라우저에서 사용할 4자리 PIN을 설정합니다.',
      'home.reset.private.key': '비공개 키 재설정',
      'home.pin.must.be.exactly.4.digits': 'PIN은 정확히 4자리여야 합니다.',
      'home.pin.must.contain.digits.only': 'PIN은 숫자만 포함해야 합니다.',
      'home.pin.confirmation.did.not.match': '확인 PIN이 일치하지 않습니다.',
      'home.bundle.review': '번들 검토',
      'home.added.notes': '추가된 노트',
      'home.updated.notes': '업데이트된 노트',
      'home.remote.bundle.history': '원격 번들 기록',
      'home.unknown.time': '알 수 없는 시간',
      'home.unknown.time.2': '알 수 없는 시간',
      'home.size.unknown': '크기 알 수 없음',
      'home.unknown.device': '알 수 없는 기기',
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
  String get notes => localized(
    en: 'Notes',
    ja: 'ノート',
    zh: '笔记',
    ko: '노트',
    es: 'Notas',
    de: 'Notizen',
  );
  String get calendar => localized(
    en: 'Calendar',
    ja: 'カレンダー',
    zh: '日历',
    ko: '캘린더',
    es: 'Calendario',
    de: 'Kalender',
  );
  String get insights => localized(
    en: 'Insights',
    ja: '記録',
    zh: '统计',
    ko: '기록',
    es: 'Estadísticas',
    de: 'Auswertung',
  );
  String get settings => localized(
    en: 'Settings',
    ja: '設定',
    zh: '设置',
    ko: '설정',
    es: 'Ajustes',
    de: 'Einstellungen',
  );
  String get addNote => localized(
    en: 'Add note',
    ja: 'ノートを追加',
    zh: '添加笔记',
    ko: '노트 추가',
    es: 'Añadir nota',
    de: 'Notiz hinzufügen',
  );
  String get collapseSidebar => localized(
    en: 'Collapse sidebar',
    ja: 'サイドバーを折りたたむ',
    zh: '折叠侧边栏',
    ko: '사이드바 접기',
    es: 'Contraer barra lateral',
    de: 'Seitenleiste einklappen',
  );
  String get expandSidebar => localized(
    en: 'Expand sidebar',
    ja: 'サイドバーを開く',
    zh: '展开侧边栏',
    ko: '사이드바 펼치기',
    es: 'Expandir barra lateral',
    de: 'Seitenleiste ausklappen',
  );
  String get search => localized(
    en: 'Search',
    ja: '検索',
    zh: '搜索',
    ko: '검색',
    es: 'Buscar',
    de: 'Suchen',
  );
  String get today => localized(
    en: 'Today',
    ja: '今日',
    zh: '今天',
    ko: '오늘',
    es: 'Hoy',
    de: 'Heute',
  );
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
    if (isJapanese || isChinese || isKorean) {
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
  String viewingPrivateProfile(String label) => localized(
    en: 'Viewing $label',
    ja: '$label を表示中',
    zh: '正在查看 $label',
    ko: '$label 보는 중',
    es: 'Viendo $label',
    de: '$label wird angezeigt',
  );
  String currentPrivateProfile(String? label) => localized(
    en: 'Currently viewing $label.',
    ja: '現在は $label を表示しています。',
    zh: '当前正在查看 $label。',
    ko: '현재 $label을 보고 있습니다.',
    es: 'Viendo $label actualmente.',
    de: '$label wird derzeit angezeigt.',
  );
  String filteredByTag(String tag) => localized(
    en: 'Filtered notes by #$tag',
    ja: '#$tag のタグで絞り込みました',
    zh: '已按 #$tag 筛选笔记',
    ko: '#$tag 태그로 노트를 필터링했습니다',
    es: 'Notas filtradas por #$tag',
    de: 'Notizen nach #$tag gefiltert',
  );
  String deleteNoteConfirmation(String title) => localized(
    en: 'Delete "$title" permanently from this device?',
    ja: '「$title」をこの端末から完全に削除しますか？',
    zh: '要从此设备永久删除“$title”吗？',
    ko: '이 기기에서 "$title"을(를) 영구 삭제할까요?',
    es: '¿Eliminar "$title" permanentemente de este dispositivo?',
    de: '"$title" dauerhaft von diesem Gerät löschen?',
  );
  String get deleteNote => localized(
    en: 'Delete note',
    ja: 'ノートを削除',
    zh: '删除笔记',
    ko: '노트 삭제',
    es: 'Eliminar nota',
    de: 'Notiz löschen',
  );
  String noteDeleted(String title) => localized(
    en: '"$title" deleted',
    ja: '「$title」を削除しました',
    zh: '已删除“$title”',
    ko: '"$title" 삭제됨',
    es: '"$title" eliminada',
    de: '"$title" gelöscht',
  );
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
  String get unableToShareAttachment => localized(
    en: 'This attachment cannot be shared yet.',
    ja: 'この添付はまだ共有できません。',
    zh: '此附件暂时无法分享。',
    ko: '이 첨부 파일은 아직 공유할 수 없습니다.',
    es: 'Este adjunto aún no se puede compartir.',
    de: 'Dieser Anhang kann noch nicht geteilt werden.',
  );
  String get unableToDecryptAttachment => localized(
    en: 'Unable to decrypt this attachment.',
    ja: 'この添付を復号できませんでした。',
    zh: '无法解密此附件。',
    ko: '이 첨부 파일을 복호화할 수 없습니다.',
    es: 'No se pudo descifrar este adjunto.',
    de: 'Dieser Anhang konnte nicht entschlüsselt werden.',
  );
  String get unableToLoadImage => localized(
    en: 'Unable to load this image.',
    ja: 'この画像を読み込めませんでした。',
    zh: '无法加载此图片。',
    ko: '이 이미지를 불러올 수 없습니다.',
    es: 'No se pudo cargar esta imagen.',
    de: 'Dieses Bild konnte nicht geladen werden.',
  );
  String get unableToDecryptImage => localized(
    en: 'Unable to decrypt this image.',
    ja: 'この画像を復号できませんでした。',
    zh: '无法解密此图片。',
    ko: '이 이미지를 복호화할 수 없습니다.',
    es: 'No se pudo descifrar esta imagen.',
    de: 'Dieses Bild konnte nicht entschlüsselt werden.',
  );
  String get videoPreviewUnavailableWeb => localized(
    en: 'Video preview is not enabled on web.',
    ja: 'Web では動画プレビューを利用できません。',
    zh: 'Web 上未启用视频预览。',
    ko: '웹에서는 동영상 미리보기를 사용할 수 없습니다.',
    es: 'La vista previa de vídeo no está activada en web.',
    de: 'Die Videovorschau ist im Web nicht aktiviert.',
  );
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
  String get unlockedNotes => localized(
    en: 'Unlocked notes',
    ja: '解除済みのノート',
    zh: '已解锁的笔记',
    ko: '잠금 해제된 노트',
    es: 'Notas desbloqueadas',
    de: 'Entsperrte Notizen',
  );
  String get photoPlaceholder => localized(
    en: 'Photo placeholder',
    ja: '写真のプレースホルダー',
    zh: '照片占位符',
    ko: '사진 자리 표시자',
    es: 'Marcador de posición de foto',
    de: 'Foto-Platzhalter',
  );
  String get tapToViewPhoto => localized(
    en: 'Tap to view photo',
    ja: 'タップして写真を表示',
    zh: '点按查看照片',
    ko: '탭하여 사진 보기',
    es: 'Toca para ver la foto',
    de: 'Tippen, um das Foto anzusehen',
  );
  String get videoPlaceholder => localized(
    en: 'Video placeholder',
    ja: '動画のプレースホルダー',
    zh: '视频占位符',
    ko: '동영상 자리 표시자',
    es: 'Marcador de posición de vídeo',
    de: 'Video-Platzhalter',
  );
  String get tapToPlayVideo => localized(
    en: 'Tap to play video',
    ja: 'タップして動画を再生',
    zh: '点按播放视频',
    ko: '탭하여 동영상 재생',
    es: 'Toca para reproducir el vídeo',
    de: 'Tippen, um das Video abzuspielen',
  );
  String get audioPlaceholder => localized(
    en: 'Audio placeholder',
    ja: '音声のプレースホルダー',
    zh: '音频占位符',
    ko: '오디오 자리 표시자',
    es: 'Marcador de posición de audio',
    de: 'Audio-Platzhalter',
  );
  String get tapToPlayAudio => localized(
    en: 'Tap to play audio',
    ja: 'タップして音声を再生',
    zh: '点按播放音频',
    ko: '탭하여 오디오 재생',
    es: 'Toca para reproducir el audio',
    de: 'Tippen, um Audio abzuspielen',
  );
  String get closeImageViewer => localized(
    en: 'Close image viewer',
    ja: '画像ビューアを閉じる',
    zh: '关闭图片查看器',
    ko: '이미지 뷰어 닫기',
    es: 'Cerrar visor de imágenes',
    de: 'Bildbetrachter schließen',
  );
  String get syncLabel => localized(
    en: 'Sync',
    ja: '同期',
    zh: '同步',
    ko: '동기화',
    es: 'Sincronización',
    de: 'Synchronisierung',
  );
  String get enableDeviceAuthReason => localized(
    en: 'Enable device authentication for HiMemo',
    ja: 'HiMemo の端末認証を有効にします',
    zh: '为 HiMemo 启用设备认证',
    ko: 'HiMemo 기기 인증을 활성화합니다',
    es: 'Activar la autenticación del dispositivo para HiMemo',
    de: 'Geräteauthentifizierung für HiMemo aktivieren',
  );
  String get unlockWithDeviceAuthReason => localized(
    en: 'Unlock HiMemo with device authentication',
    ja: '端末認証で HiMemo を解除します',
    zh: '使用设备认证解锁 HiMemo',
    ko: '기기 인증으로 HiMemo를 잠금 해제합니다',
    es: 'Desbloquear HiMemo con la autenticación del dispositivo',
    de: 'HiMemo mit Geräteauthentifizierung entsperren',
  );
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
  String webPinProtectionSummary(String pinSummary) => localized(
    en: 'Protect this browser session with a 4 digit PIN. $pinSummary',
    ja: 'このブラウザでは 4 桁の PIN でメモ画面を保護します。$pinSummary',
    zh: '使用 4 位 PIN 保护此浏览器会话。$pinSummary',
    ko: '이 브라우저 세션을 4자리 PIN으로 보호합니다. $pinSummary',
    es: 'Protege esta sesión del navegador con un PIN de 4 dígitos. $pinSummary',
    de: 'Schütze diese Browsersitzung mit einer 4-stelligen PIN. $pinSummary',
  );
  String deviceAuthProtectionSummary(String summary) => localized(
    en: 'Protect the app with device authentication. Availability: $summary',
    ja: 'この端末の生体認証や画面ロックで保護します。利用状況: $summary',
    zh: '使用设备认证保护应用。可用性：$summary',
    ko: '기기 인증으로 앱을 보호합니다. 사용 가능 상태: $summary',
    es: 'Protege la app con la autenticación del dispositivo. Disponibilidad: $summary',
    de: 'Schütze die App mit Geräteauthentifizierung. Verfügbarkeit: $summary',
  );
  String lastQueuedAt(String timestamp) => localized(
    en: 'last queued $timestamp',
    ja: '最終追加 $timestamp',
    zh: '最后加入队列 $timestamp',
    ko: '마지막 대기열 추가 $timestamp',
    es: 'último en cola $timestamp',
    de: 'zuletzt eingereiht $timestamp',
  );
  String pendingSyncSummary({
    required int total,
    required int upserts,
    required int deletes,
    required String stamp,
  }) => localized(
    en: '$total changes pending ($upserts upserts, $deletes deletes), $stamp',
    ja: '$total件が保留中（更新 $upserts / 削除 $deletes）、$stamp',
    zh: '$total 项更改待同步（更新 $upserts / 删除 $deletes），$stamp',
    ko: '$total개 변경 대기 중(업데이트 $upserts / 삭제 $deletes), $stamp',
    es: '$total cambios pendientes ($upserts actualizaciones, $deletes eliminaciones), $stamp',
    de: '$total Änderungen ausstehend ($upserts Aktualisierungen, $deletes Löschungen), $stamp',
  );
  String recoveryKeyImported(String fingerprint) => localized(
    en: 'Cloud recovery key imported. Fingerprint: $fingerprint',
    ja: 'クラウド復元キーを読み込みました。フィンガープリント: $fingerprint',
    zh: '已导入云恢复密钥。指纹：$fingerprint',
    ko: '클라우드 복구 키를 가져왔습니다. 지문: $fingerprint',
    es: 'Clave de recuperación en la nube importada. Huella: $fingerprint',
    de: 'Cloud-Wiederherstellungsschlüssel importiert. Fingerabdruck: $fingerprint',
  );
  String lastUploadAt(String timestamp) => localized(
    en: 'Last upload $timestamp',
    ja: '最終アップロード $timestamp',
    zh: '最后上传 $timestamp',
    ko: '마지막 업로드 $timestamp',
    es: 'Última subida $timestamp',
    de: 'Letzter Upload $timestamp',
  );
  String lastApplyAt(String timestamp) => localized(
    en: 'Last apply $timestamp',
    ja: '最終適用 $timestamp',
    zh: '最后应用 $timestamp',
    ko: '마지막 적용 $timestamp',
    es: 'Última aplicación $timestamp',
    de: 'Zuletzt angewendet $timestamp',
  );
  String remoteBundleAt(String timestamp) => localized(
    en: 'Remote bundle $timestamp',
    ja: 'リモート更新 $timestamp',
    zh: '远程包 $timestamp',
    ko: '원격 번들 $timestamp',
    es: 'Paquete remoto $timestamp',
    de: 'Remote-Bundle $timestamp',
  );
  String localBundleStoredAt(String reference) => localized(
    en: 'Stored at $reference',
    ja: '$reference に保存済み',
    zh: '已存储在 $reference',
    ko: '$reference에 저장됨',
    es: 'Guardado en $reference',
    de: 'Gespeichert unter $reference',
  );
  String syncSnapshotSummary({
    required int notes,
    required int attachments,
    required int pending,
    required String deviceId,
  }) => localized(
    en: 'Notes: $notes\nAttachments: $attachments\nQueue: $pending pending\nDevice ID: $deviceId',
    ja: 'ノート: $notes\n添付: $attachments\nキュー: $pending件保留中\n端末 ID: $deviceId',
    zh: '笔记：$notes\n附件：$attachments\n队列：$pending 项待处理\n设备 ID：$deviceId',
    ko: '노트: $notes\n첨부: $attachments\n대기열: $pending개 대기 중\n기기 ID: $deviceId',
    es: 'Notas: $notes\nAdjuntos: $attachments\nCola: $pending pendientes\nID del dispositivo: $deviceId',
    de: 'Notizen: $notes\nAnhänge: $attachments\nWarteschlange: $pending ausstehend\nGeräte-ID: $deviceId',
  );
  String syncConnected({String? identity, String suffix = ''}) {
    if (identity == null) {
      return localized(
        en: 'Connected.$suffix',
        ja: '接続済みです。$suffix',
        zh: '已连接。$suffix',
        ko: '연결되었습니다. $suffix',
        es: 'Conectado. $suffix',
        de: 'Verbunden. $suffix',
      );
    }
    return localized(
      en: 'Connected as $identity.$suffix',
      ja: '$identity で接続済みです。$suffix',
      zh: '已用 $identity 连接。$suffix',
      ko: '$identity로 연결되었습니다. $suffix',
      es: 'Conectado como $identity. $suffix',
      de: 'Verbunden als $identity. $suffix',
    );
  }

  String syncConnectedLegacy({String? identity, String suffix = ''}) {
    if (identity == null) {
      return localized(
        en: 'Connected.$suffix',
        ja: '接続済み。$suffix',
        zh: '已连接。$suffix',
        ko: '연결됨. $suffix',
        es: 'Conectado. $suffix',
        de: 'Verbunden. $suffix',
      );
    }
    return localized(
      en: 'Connected as $identity.$suffix',
      ja: '$identity で接続済み。$suffix',
      zh: '已用 $identity 连接。$suffix',
      ko: '$identity로 연결됨. $suffix',
      es: 'Conectado como $identity. $suffix',
      de: 'Verbunden als $identity. $suffix',
    );
  }

  String identityActive(String name) =>
      isJapanese ? '$name 利用中' : '$name active';
  String byteCount(int bytes) => isJapanese ? '$bytes バイト' : '$bytes bytes';
  String remoteBundleSummary({
    required String modifiedAt,
    required String sizeLabel,
    required String noteCount,
    required String attachmentCount,
  }) => localized(
    en: 'Last bundle: $modifiedAt, $sizeLabel, $noteCount notes, $attachmentCount attachments.',
    ja: '最新バンドル: $modifiedAt、$sizeLabel、ノート $noteCount 件、添付 $attachmentCount 件。',
    zh: '最新包：$modifiedAt，$sizeLabel，笔记 $noteCount 条，附件 $attachmentCount 个。',
    ko: '최신 번들: $modifiedAt, $sizeLabel, 노트 $noteCount개, 첨부 $attachmentCount개.',
    es: 'Último paquete: $modifiedAt, $sizeLabel, $noteCount notas, $attachmentCount adjuntos.',
    de: 'Letztes Bundle: $modifiedAt, $sizeLabel, $noteCount Notizen, $attachmentCount Anhänge.',
  );
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

  String get appearance => localized(
    en: 'Appearance',
    ja: '表示',
    zh: '外观',
    ko: '표시',
    es: 'Apariencia',
    de: 'Darstellung',
  );
  String get appearanceWithControls => localized(
    en: 'Appearance (language and color)',
    ja: '表示（言語・カラー）',
    zh: '外观（语言与颜色）',
    ko: '표시(언어·색상)',
    es: 'Apariencia (idioma y color)',
    de: 'Darstellung (Sprache und Farbe)',
  );
  String appearanceSummary({
    required String language,
    required String theme,
    required String color,
  }) => localized(
    en: 'Language: $language / Theme: $theme / Color: $color',
    ja: '言語: $language / テーマ: $theme / カラー: $color',
    zh: '语言：$language / 主题：$theme / 颜色：$color',
    ko: '언어: $language / 테마: $theme / 색상: $color',
    es: 'Idioma: $language / Tema: $theme / Color: $color',
    de: 'Sprache: $language / Design: $theme / Farbe: $color',
  );
  String get language => localized(
    en: 'Language',
    ja: '言語',
    zh: '语言',
    ko: '언어',
    es: 'Idioma',
    de: 'Sprache',
  );
  String get languageSystem => localized(
    en: 'Follow system',
    ja: 'システムに合わせる',
    zh: '跟随系统',
    ko: '시스템 따르기',
    es: 'Seguir sistema',
    de: 'System folgen',
  );
  String get languageSystemOption => localized(
    en: 'Follow system',
    ja: 'システムに合わせる (System)',
    zh: '跟随系统 (System)',
    ko: '시스템 따르기 (System)',
    es: 'Seguir sistema (System)',
    de: 'System folgen (System)',
  );
  String get languageJapanese => localized(
    en: 'Japanese',
    ja: '日本語',
    zh: '日语',
    ko: '일본어',
    es: 'Japonés',
    de: 'Japanisch',
  );
  String get languageJapaneseOption => localized(
    en: 'Japanese',
    ja: '日本語 (Japanese)',
    zh: '日语 (Japanese)',
    ko: '일본어 (Japanese)',
    es: 'Japonés (Japanese)',
    de: 'Japanisch (Japanese)',
  );
  String get languageEnglish => localized(
    en: 'English',
    ja: '英語',
    zh: '英语',
    ko: '영어',
    es: 'Inglés',
    de: 'Englisch',
  );
  String get languageEnglishOption => 'English';
  String get languageChinese => localized(
    en: 'Chinese',
    ja: '中国語',
    zh: '中文',
    ko: '중국어',
    es: 'Chino',
    de: 'Chinesisch',
  );
  String get languageChineseOption => localized(
    en: 'Chinese',
    ja: '中国語 (Chinese)',
    zh: '中文 (Chinese)',
    ko: '중국어 (Chinese)',
    es: 'Chino (Chinese)',
    de: 'Chinesisch (Chinese)',
  );
  String get languageKorean => localized(
    en: 'Korean',
    ja: '韓国語',
    zh: '韩语',
    ko: '한국어',
    es: 'Coreano',
    de: 'Koreanisch',
  );
  String get languageKoreanOption => localized(
    en: 'Korean',
    ja: '韓国語 (Korean)',
    zh: '韩语 (Korean)',
    ko: '한국어 (Korean)',
    es: 'Coreano (Korean)',
    de: 'Koreanisch (Korean)',
  );
  String get languageSpanish => localized(
    en: 'Spanish',
    ja: 'スペイン語',
    zh: '西班牙语',
    ko: '스페인어',
    es: 'Español',
    de: 'Spanisch',
  );
  String get languageSpanishOption => localized(
    en: 'Spanish',
    ja: 'スペイン語 (Spanish)',
    zh: '西班牙语 (Spanish)',
    ko: '스페인어 (Spanish)',
    es: 'Español (Spanish)',
    de: 'Spanisch (Spanish)',
  );
  String get languageGerman => localized(
    en: 'German',
    ja: 'ドイツ語',
    zh: '德语',
    ko: '독일어',
    es: 'Alemán',
    de: 'Deutsch',
  );
  String get languageGermanOption => localized(
    en: 'German',
    ja: 'ドイツ語 (German)',
    zh: '德语 (German)',
    ko: '독일어 (German)',
    es: 'Alemán (German)',
    de: 'Deutsch (German)',
  );
  String get languageSystemDesc => localized(
    en: 'Follow the device language. Fall back to English when unsupported.',
    ja: '端末の言語設定に合わせます。未対応の言語では英語を使います。',
    zh: '跟随设备语言。未支持的语言将回退到英语。',
    ko: '기기 언어 설정을 따릅니다. 지원하지 않는 언어는 영어로 표시됩니다.',
    es: 'Usa el idioma del dispositivo. Si no es compatible, se usa inglés.',
    de: 'Folgt der Gerätesprache. Nicht unterstützte Sprachen fallen auf Englisch zurück.',
  );
  String get themeLight => localized(
    en: 'Light',
    ja: 'ライト',
    zh: '浅色',
    ko: '라이트',
    es: 'Claro',
    de: 'Hell',
  );
  String get themeSystem => localized(
    en: 'System',
    ja: 'システム',
    zh: '系统',
    ko: '시스템',
    es: 'Sistema',
    de: 'System',
  );
  String get themeDark => localized(
    en: 'Dark',
    ja: 'ダーク',
    zh: '深色',
    ko: '다크',
    es: 'Oscuro',
    de: 'Dunkel',
  );
  String get accentColor => localized(
    en: 'Accent color',
    ja: 'アクセントカラー',
    zh: '强调色',
    ko: '강조 색상',
    es: 'Color de acento',
    de: 'Akzentfarbe',
  );
  String get accentColorJapanesePaletteDesc => localized(
    en: 'These accents are inspired by traditional Japanese colors.',
    ja: '日本の伝統色をもとにしたアクセントカラーです。',
    zh: '这些强调色以日本传统色为灵感。',
    ko: '일본 전통색에서 영감을 받은 강조 색상입니다.',
    es: 'Estos acentos se inspiran en colores tradicionales japoneses.',
    de: 'Diese Akzentfarben sind von traditionellen japanischen Farben inspiriert.',
  );
  String get extendedThemes => localized(
    en: 'Extended themes',
    ja: '拡張テーマ',
    zh: '扩展主题',
    ko: '확장 테마',
    es: 'Temas ampliados',
    de: 'Erweiterte Themen',
  );
  String extendedThemesWithCount(int count) => localized(
    en: 'Extended themes ($count total)',
    ja: '拡張テーマ（全$count種）',
    zh: '扩展主题（共$count 种）',
    ko: '확장 테마(총 $count종)',
    es: 'Temas ampliados ($count en total)',
    de: 'Erweiterte Themen ($count insgesamt)',
  );
  String get hideExtendedThemes => localized(
    en: 'Hide extended themes',
    ja: '拡張テーマを隠す',
    zh: '隐藏扩展主题',
    ko: '확장 테마 숨기기',
    es: 'Ocultar temas ampliados',
    de: 'Erweiterte Themen ausblenden',
  );
  String get themeCategoryBlueGreen => localized(
    en: 'Blue',
    ja: '青系',
    zh: '蓝色系',
    ko: '파랑 계열',
    es: 'Azules',
    de: 'Blau',
  );
  String get themeCategoryPurple => localized(
    en: 'Purple',
    ja: '紫系',
    zh: '紫色系',
    ko: '보라 계열',
    es: 'Púrpuras',
    de: 'Violett',
  );
  String get themeCategoryRedPink => localized(
    en: 'Red and pink',
    ja: '赤・桃系',
    zh: '红粉系',
    ko: '빨강·분홍 계열',
    es: 'Rojos y rosas',
    de: 'Rot und Rosa',
  );
  String get themeCategoryGreenYellow => localized(
    en: 'Green',
    ja: '緑系',
    zh: '绿色系',
    ko: '초록 계열',
    es: 'Verdes',
    de: 'Grün',
  );
  String get themeCategoryEarth => localized(
    en: 'Yellow and brown',
    ja: '黄・茶系',
    zh: '黄棕系',
    ko: '노랑·갈색 계열',
    es: 'Amarillos y marrones',
    de: 'Gelb und Braun',
  );
  String get themeCategoryNeutral => localized(
    en: 'White, black, and neutral',
    ja: '白・黒・無彩色',
    zh: '白、黑与中性色',
    ko: '흰색, 검정, 무채색',
    es: 'Blanco, negro y neutros',
    de: 'Weiß, Schwarz und Neutral',
  );
  String get colorKonjyo => localized(
    en: '紺青 (Konjyo)',
    ja: '紺青 (Konjyo)',
    zh: '紺青 (Konjyo)',
    ko: '紺青 (Konjyo)',
    es: '紺青 (Konjyo)',
    de: '紺青 (Konjyo)',
  );
  String get colorMoegi => localized(
    en: '萌黄 (Moegi)',
    ja: '萌黄 (Moegi)',
    zh: '萌黄 (Moegi)',
    ko: '萌黄 (Moegi)',
    es: '萌黄 (Moegi)',
    de: '萌黄 (Moegi)',
  );
  String get colorYamabuki => localized(
    en: '山吹 (Yamabuki)',
    ja: '山吹 (Yamabuki)',
    zh: '山吹 (Yamabuki)',
    ko: '山吹 (Yamabuki)',
    es: '山吹 (Yamabuki)',
    de: '山吹 (Yamabuki)',
  );
  String get colorGinnezumi => localized(
    en: '銀鼠 (Ginnezumi)',
    ja: '銀鼠 (Ginnezumi)',
    zh: '銀鼠 (Ginnezumi)',
    ko: '銀鼠 (Ginnezumi)',
    es: '銀鼠 (Ginnezumi)',
    de: '銀鼠 (Ginnezumi)',
  );
  String get colorSeiheki => localized(
    en: '青碧 (Seiheki)',
    ja: '青碧 (Seiheki)',
    zh: '青碧 (Seiheki)',
    ko: '青碧 (Seiheki)',
    es: '青碧 (Seiheki)',
    de: '青碧 (Seiheki)',
  );
  String get colorKurenai => localized(
    en: '紅 (Kurenai)',
    ja: '紅 (Kurenai)',
    zh: '紅 (Kurenai)',
    ko: '紅 (Kurenai)',
    es: '紅 (Kurenai)',
    de: '紅 (Kurenai)',
  );
  String get colorSakura => localized(
    en: '桜 (Sakura)',
    ja: '桜 (Sakura)',
    zh: '桜 (Sakura)',
    ko: '桜 (Sakura)',
    es: '桜 (Sakura)',
    de: '桜 (Sakura)',
  );
  String get colorFuji => localized(
    en: '藤 (Fuji)',
    ja: '藤 (Fuji)',
    zh: '藤 (Fuji)',
    ko: '藤 (Fuji)',
    es: '藤 (Fuji)',
    de: '藤 (Fuji)',
  );
  String get colorAi => localized(
    en: '藍 (Ai)',
    ja: '藍 (Ai)',
    zh: '藍 (Ai)',
    ko: '藍 (Ai)',
    es: '藍 (Ai)',
    de: '藍 (Ai)',
  );
  String get colorKurumi => localized(
    en: '胡桃 (Kurumi)',
    ja: '胡桃 (Kurumi)',
    zh: '胡桃 (Kurumi)',
    ko: '胡桃 (Kurumi)',
    es: '胡桃 (Kurumi)',
    de: '胡桃 (Kurumi)',
  );
  String get colorChigusa => localized(
    en: '千草 (Chigusa)',
    ja: '千草 (Chigusa)',
    zh: '千草 (Chigusa)',
    ko: '千草 (Chigusa)',
    es: '千草 (Chigusa)',
    de: '千草 (Chigusa)',
  );
  String get colorSumire => localized(
    en: '菫 (Sumire)',
    ja: '菫 (Sumire)',
    zh: '菫 (Sumire)',
    ko: '菫 (Sumire)',
    es: '菫 (Sumire)',
    de: '菫 (Sumire)',
  );
  String get colorSumi => localized(
    en: '墨 (Sumi)',
    ja: '墨 (Sumi)',
    zh: '墨 (Sumi)',
    ko: '墨 (Sumi)',
    es: '墨 (Sumi)',
    de: '墨 (Sumi)',
  );
  String get colorShironeri => localized(
    en: '白練 (Shironeri)',
    ja: '白練 (Shironeri)',
    zh: '白練 (Shironeri)',
    ko: '白練 (Shironeri)',
    es: '白練 (Shironeri)',
    de: '白練 (Shironeri)',
  );
  String get colorGofun => localized(
    en: '胡粉 (Gofun)',
    ja: '胡粉 (Gofun)',
    zh: '胡粉 (Gofun)',
    ko: '胡粉 (Gofun)',
    es: '胡粉 (Gofun)',
    de: '胡粉 (Gofun)',
  );
  String get colorEnji => localized(
    en: '臙脂 (Enji)',
    ja: '臙脂 (Enji)',
    zh: '臙脂 (Enji)',
    ko: '臙脂 (Enji)',
    es: '臙脂 (Enji)',
    de: '臙脂 (Enji)',
  );
  String get colorHanada => localized(
    en: '縹 (Hanada)',
    ja: '縹 (Hanada)',
    zh: '縹 (Hanada)',
    ko: '縹 (Hanada)',
    es: '縹 (Hanada)',
    de: '縹 (Hanada)',
  );
  String get colorSora => localized(
    en: '空 (Sora)',
    ja: '空 (Sora)',
    zh: '空 (Sora)',
    ko: '空 (Sora)',
    es: '空 (Sora)',
    de: '空 (Sora)',
  );
  String get colorRuri => localized(
    en: '瑠璃 (Ruri)',
    ja: '瑠璃 (Ruri)',
    zh: '瑠璃 (Ruri)',
    ko: '瑠璃 (Ruri)',
    es: '瑠璃 (Ruri)',
    de: '瑠璃 (Ruri)',
  );
  String get colorAsagi => localized(
    en: '浅葱 (Asagi)',
    ja: '浅葱 (Asagi)',
    zh: '浅葱 (Asagi)',
    ko: '浅葱 (Asagi)',
    es: '浅葱 (Asagi)',
    de: '浅葱 (Asagi)',
  );
  String get colorWakatake => localized(
    en: '若竹 (Wakatake)',
    ja: '若竹 (Wakatake)',
    zh: '若竹 (Wakatake)',
    ko: '若竹 (Wakatake)',
    es: '若竹 (Wakatake)',
    de: '若竹 (Wakatake)',
  );
  String get colorTokiwa => localized(
    en: '常磐 (Tokiwa)',
    ja: '常磐 (Tokiwa)',
    zh: '常磐 (Tokiwa)',
    ko: '常磐 (Tokiwa)',
    es: '常磐 (Tokiwa)',
    de: '常磐 (Tokiwa)',
  );
  String get colorByakuroku => localized(
    en: '白緑 (Byakuroku)',
    ja: '白緑 (Byakuroku)',
    zh: '白緑 (Byakuroku)',
    ko: '白緑 (Byakuroku)',
    es: '白緑 (Byakuroku)',
    de: '白緑 (Byakuroku)',
  );
  String get colorNanohana => localized(
    en: '菜の花 (Nanohana)',
    ja: '菜の花 (Nanohana)',
    zh: '菜の花 (Nanohana)',
    ko: '菜の花 (Nanohana)',
    es: '菜の花 (Nanohana)',
    de: '菜の花 (Nanohana)',
  );
  String get colorHaizakura => localized(
    en: '灰桜 (Haizakura)',
    ja: '灰桜 (Haizakura)',
    zh: '灰桜 (Haizakura)',
    ko: '灰桜 (Haizakura)',
    es: '灰桜 (Haizakura)',
    de: '灰桜 (Haizakura)',
  );
  String get colorAkane => localized(
    en: '茜 (Akane)',
    ja: '茜 (Akane)',
    zh: '茜 (Akane)',
    ko: '茜 (Akane)',
    es: '茜 (Akane)',
    de: '茜 (Akane)',
  );
  String get colorKikyo => localized(
    en: '桔梗 (Kikyo)',
    ja: '桔梗 (Kikyo)',
    zh: '桔梗 (Kikyo)',
    ko: '桔梗 (Kikyo)',
    es: '桔梗 (Kikyo)',
    de: '桔梗 (Kikyo)',
  );
  String get colorEdomurasaki => localized(
    en: '江戸紫 (Edomurasaki)',
    ja: '江戸紫 (Edomurasaki)',
    zh: '江戸紫 (Edomurasaki)',
    ko: '江戸紫 (Edomurasaki)',
    es: '江戸紫 (Edomurasaki)',
    de: '江戸紫 (Edomurasaki)',
  );
  String get colorShion => localized(
    en: '紫苑 (Shion)',
    ja: '紫苑 (Shion)',
    zh: '紫苑 (Shion)',
    ko: '紫苑 (Shion)',
    es: '紫苑 (Shion)',
    de: '紫苑 (Shion)',
  );
  String get colorRikyucha => localized(
    en: '利休茶 (Rikyucha)',
    ja: '利休茶 (Rikyucha)',
    zh: '利休茶 (Rikyucha)',
    ko: '利休茶 (Rikyucha)',
    es: '利休茶 (Rikyucha)',
    de: '利休茶 (Rikyucha)',
  );
  String get colorKonjyoDesc => localized(
    en: 'Deep traditional blue based on Konjyo.',
    ja: '深い伝統色の紺青を基調にした配色です。',
    zh: '以深邃传统绀青为主的配色。',
    ko: '깊은 전통 감청색을 중심으로 한 배색입니다.',
    es: 'Azul tradicional profundo basado en Konjyo.',
    de: 'Tiefes traditionelles Blau auf Basis von Konjyo.',
  );
  String get colorMoegiDesc => localized(
    en: 'Fresh yellow-green based on Moegi.',
    ja: '芽吹きの色を思わせる萌黄の配色です。',
    zh: '以新芽般的萌黄为主的配色。',
    ko: '새싹을 떠올리게 하는 모에기 배색입니다.',
    es: 'Verde amarillento fresco basado en Moegi.',
    de: 'Frisches Gelbgrün auf Basis von Moegi.',
  );
  String get colorYamabukiDesc => localized(
    en: 'Golden yellow based on Yamabuki.',
    ja: '華やかな山吹色を基調にした配色です。',
    zh: '以明亮山吹色为主的配色。',
    ko: '화사한 야마부키색을 중심으로 한 배색입니다.',
    es: 'Amarillo dorado basado en Yamabuki.',
    de: 'Goldgelb auf Basis von Yamabuki.',
  );
  String get colorGinnezumiDesc => localized(
    en: 'Quiet blue-gray based on Ginnezumi.',
    ja: '静かな青みの銀鼠を基調にした配色です。',
    zh: '以安静带蓝感的银鼠为主的配色。',
    ko: '차분한 푸른빛의 긴네즈미 배색입니다.',
    es: 'Gris azulado sereno basado en Ginnezumi.',
    de: 'Ruhiges Blaugrau auf Basis von Ginnezumi.',
  );
  String get colorSeihekiDesc => localized(
    en: 'Balanced blue-green based on Seiheki.',
    ja: '青と緑の間を落ち着かせた青碧の配色です。',
    zh: '以平衡蓝与绿的青碧为主的配色。',
    ko: '파랑과 초록 사이를 차분하게 잡은 청벽 배색입니다.',
    es: 'Azul verdoso equilibrado basado en Seiheki.',
    de: 'Ausgewogenes Blaugrün auf Basis von Seiheki.',
  );
  String get colorKurenaiDesc => localized(
    en: 'Vivid safflower red based on Kurenai.',
    ja: '鮮やかな紅を基調にした赤系の配色です。',
    zh: '以鲜明红色为主的配色。',
    ko: '선명한 쿠레나이 붉은색을 중심으로 한 배색입니다.',
    es: 'Rojo vivo de cártamo basado en Kurenai.',
    de: 'Lebendiges Färberdistelrot auf Basis von Kurenai.',
  );
  String get colorSakuraDesc => localized(
    en: 'Pale cherry blossom pink for a soft reading surface.',
    ja: '淡い桜色を基調にした柔らかな配色です。',
    zh: '以淡樱花色为主的柔和配色。',
    ko: '옅은 벚꽃색을 중심으로 한 부드러운 배색입니다.',
    es: 'Rosa cerezo pálido para una superficie suave.',
    de: 'Helles Kirschblütenrosa für eine sanfte Oberfläche.',
  );
  String get colorFujiDesc => localized(
    en: 'Wisteria purple based on Fuji.',
    ja: '藤の花を思わせる紫系の配色です。',
    zh: '以藤花般紫色为主的配色。',
    ko: '등꽃을 떠올리게 하는 보라색 배색입니다.',
    es: 'Púrpura glicinia basado en Fuji.',
    de: 'Glyzinienviolett auf Basis von Fuji.',
  );
  String get colorAiDesc => localized(
    en: 'Classic indigo blue for a calm interface.',
    ja: '藍染を思わせる落ち着いた青の配色です。',
    zh: '让人联想到蓝染的沉稳蓝色配色。',
    ko: '쪽염을 떠올리게 하는 차분한 파란 배색입니다.',
    es: 'Azul índigo clásico para una interfaz tranquila.',
    de: 'Klassisches Indigoblau für eine ruhige Oberfläche.',
  );
  String get colorKurumiDesc => localized(
    en: 'Walnut brown for a warm, grounded profile.',
    ja: '胡桃のような温かい茶系の配色です。',
    zh: '如胡桃般温暖的棕色配色。',
    ko: '호두를 닮은 따뜻한 갈색 배색입니다.',
    es: 'Marrón nogal para un perfil cálido.',
    de: 'Walnussbraun für ein warmes Profil.',
  );
  String get colorChigusaDesc => localized(
    en: 'Light blue-green based on Chigusa.',
    ja: '軽やかな青緑の千草を基調にした配色です。',
    zh: '以轻快蓝绿色千草为主的配色。',
    ko: '가벼운 청록빛 치구사를 중심으로 한 배색입니다.',
    es: 'Azul verdoso ligero basado en Chigusa.',
    de: 'Helles Blaugrün auf Basis von Chigusa.',
  );
  String get colorSumireDesc => localized(
    en: 'Deep violet based on Sumire.',
    ja: '菫の花を思わせる深い紫の配色です。',
    zh: '让人联想到菫花的深紫色配色。',
    ko: '제비꽃을 떠올리게 하는 깊은 보라 배색입니다.',
    es: 'Violeta profundo basado en Sumire.',
    de: 'Tiefes Violett auf Basis von Sumire.',
  );
  String get colorSumiDesc => localized(
    en: 'Ink black with restrained contrast.',
    ja: '墨の黒を基調にした落ち着いた配色です。',
    zh: '以墨黑为主的沉稳配色。',
    ko: '먹색 검정을 중심으로 한 차분한 배색입니다.',
    es: 'Negro tinta con contraste contenido.',
    de: 'Tuscheschwarz mit zurückhaltendem Kontrast.',
  );
  String get colorShironeriDesc => localized(
    en: 'Soft off-white based on Shironeri.',
    ja: '白練を基調にした柔らかな白ベースです。',
    zh: '以白练为主的柔和白色基调。',
    ko: '시로네리를 중심으로 한 부드러운 흰색 기반입니다.',
    es: 'Blanco suave basado en Shironeri.',
    de: 'Sanftes Off-White auf Basis von Shironeri.',
  );
  String get colorGofunDesc => localized(
    en: 'Warm mineral white based on Gofun.',
    ja: '胡粉を思わせる温かい白ベースです。',
    zh: '如胡粉般温暖的白色基调。',
    ko: '고훈을 떠올리게 하는 따뜻한 흰색 기반입니다.',
    es: 'Blanco mineral cálido basado en Gofun.',
    de: 'Warmes Mineralweiß auf Basis von Gofun.',
  );
  String get colorEnjiDesc => localized(
    en: 'Deep traditional crimson based on Enji.',
    ja: '臙脂の深い赤を基調にした配色です。',
    zh: '以深沉胭脂红为主的配色。',
    ko: '깊은 연지색을 중심으로 한 배색입니다.',
    es: 'Carmesí tradicional profundo basado en Enji.',
    de: 'Tiefes traditionelles Karminrot auf Basis von Enji.',
  );
  String get colorHanadaDesc => localized(
    en: 'Clear blue based on Hanada.',
    ja: '澄んだ縹の青を基調にした配色です。',
    zh: '以清澈缥色蓝为主的配色。',
    ko: '맑은 하나다 파랑을 중심으로 한 배색입니다.',
    es: 'Azul claro basado en Hanada.',
    de: 'Klares Blau auf Basis von Hanada.',
  );
  String get colorSoraDesc => localized(
    en: 'Bright sky blue based on Sora.',
    ja: '明るい空色を基調にした配色です。',
    zh: '以明亮天空蓝为主的配色。',
    ko: '밝은 하늘색을 중심으로 한 배색입니다.',
    es: 'Azul cielo claro basado en Sora.',
    de: 'Helles Himmelblau auf Basis von Sora.',
  );
  String get colorRuriDesc => localized(
    en: 'Lapis lazuli blue based on Ruri.',
    ja: '瑠璃の深い青を基調にした配色です。',
    zh: '以瑠璃般深蓝为主的配色。',
    ko: '유리색의 깊은 파랑을 중심으로 한 배색입니다.',
    es: 'Azul lapislázuli basado en Ruri.',
    de: 'Lapislazuliblau auf Basis von Ruri.',
  );
  String get colorAsagiDesc => localized(
    en: 'Fresh blue-green based on Asagi.',
    ja: '浅葱の爽やかな青緑を基調にした配色です。',
    zh: '以浅葱般清爽蓝绿色为主的配色。',
    ko: '아사기의 산뜻한 청록을 중심으로 한 배색입니다.',
    es: 'Azul verdoso fresco basado en Asagi.',
    de: 'Frisches Blaugrün auf Basis von Asagi.',
  );
  String get colorWakatakeDesc => localized(
    en: 'Fresh bamboo green based on Wakatake.',
    ja: '若竹を思わせる爽やかな緑の配色です。',
    zh: '以若竹般清新的绿色为主的配色。',
    ko: '어린 대나무를 떠올리게 하는 산뜻한 녹색 배색입니다.',
    es: 'Verde bambú fresco basado en Wakatake.',
    de: 'Frisches Bambusgrün auf Basis von Wakatake.',
  );
  String get colorTokiwaDesc => localized(
    en: 'Evergreen tone based on Tokiwa.',
    ja: '常緑を思わせる常磐の緑を基調にした配色です。',
    zh: '以常绿般常磐绿为主的配色。',
    ko: '상록을 떠올리게 하는 도키와 녹색 배색입니다.',
    es: 'Verde perenne basado en Tokiwa.',
    de: 'Immergrüner Ton auf Basis von Tokiwa.',
  );
  String get colorByakurokuDesc => localized(
    en: 'Pale mineral green based on Byakuroku.',
    ja: '白緑の淡い鉱物感を基調にした配色です。',
    zh: '以白绿般淡雅矿物绿色为主的配色。',
    ko: '백록의 옅은 광물감 있는 초록을 중심으로 한 배색입니다.',
    es: 'Verde mineral pálido basado en Byakuroku.',
    de: 'Helles Mineralgrün auf Basis von Byakuroku.',
  );
  String get colorNanohanaDesc => localized(
    en: 'Rapeseed flower yellow based on Nanohana.',
    ja: '菜の花の明るい黄色を基調にした配色です。',
    zh: '以油菜花般明亮黄色为主的配色。',
    ko: '유채꽃의 밝은 노랑을 중심으로 한 배색입니다.',
    es: 'Amarillo flor de colza basado en Nanohana.',
    de: 'Rapsblütengelb auf Basis von Nanohana.',
  );
  String get colorHaizakuraDesc => localized(
    en: 'Muted pale cherry tone based on Haizakura.',
    ja: '灰桜のくすんだ淡色を基調にした配色です。',
    zh: '以灰樱般柔和浅色为主的配色。',
    ko: '하이자쿠라의 차분한 연색을 중심으로 한 배색입니다.',
    es: 'Tono cerezo apagado basado en Haizakura.',
    de: 'Gedämpfter heller Kirschton auf Basis von Haizakura.',
  );
  String get colorAkaneDesc => localized(
    en: 'Madder red based on Akane.',
    ja: '茜の深い赤を基調にした配色です。',
    zh: '以茜草般深红为主的配色。',
    ko: '꼭두서니의 깊은 빨강을 중심으로 한 배색입니다.',
    es: 'Rojo rubia basado en Akane.',
    de: 'Krapprot auf Basis von Akane.',
  );
  String get colorKikyoDesc => localized(
    en: 'Bellflower purple based on Kikyo.',
    ja: '桔梗の花を思わせる紫の配色です。',
    zh: '以桔梗花般紫色为主的配色。',
    ko: '도라지꽃을 떠올리게 하는 보라 배색입니다.',
    es: 'Púrpura campanilla basado en Kikyo.',
    de: 'Glockenblumenviolett auf Basis von Kikyo.',
  );
  String get colorEdomurasakiDesc => localized(
    en: 'Refined Edo purple with a deeper tone.',
    ja: '江戸紫の深みをもたせた紫系の配色です。',
    zh: '以更有深度的江户紫为主的配色。',
    ko: '에도무라사키의 깊이를 살린 보라 배색입니다.',
    es: 'Púrpura Edo refinado con un tono más profundo.',
    de: 'Raffiniertes Edo-Violett mit tieferem Ton.',
  );
  String get colorShionDesc => localized(
    en: 'Aster purple based on Shion.',
    ja: '紫苑の落ち着いた紫を基調にした配色です。',
    zh: '以紫苑般沉稳紫色为主的配色。',
    ko: '시온의 차분한 보라를 중심으로 한 배색입니다.',
    es: 'Púrpura de áster basado en Shion.',
    de: 'Asterviolett auf Basis von Shion.',
  );
  String get colorRikyuchaDesc => localized(
    en: 'Tea-toned green brown based on Rikyucha.',
    ja: '利休茶の渋い緑茶系を基調にした配色です。',
    zh: '以利休茶般沉稳茶绿色为主的配色。',
    ko: '리큐차의 차분한 녹갈색을 중심으로 한 배색입니다.',
    es: 'Verde marrón de té basado en Rikyucha.',
    de: 'Teeartiges Grünbraun auf Basis von Rikyucha.',
  );
  String get lightDesc => localized(
    en: 'Keep the white memo-style interface.',
    ja: '白基調のメモらしい見た目を保ちます。',
    zh: '保持白色为主的备忘录外观。',
    ko: '흰색 중심의 메모다운 화면을 유지합니다.',
    es: 'Mantiene una interfaz blanca de estilo memo.',
    de: 'Behält die weiße Memo-Oberfläche bei.',
  );
  String get systemDesc => localized(
    en: 'Follow the device setting.',
    ja: '端末の表示設定に合わせます。',
    zh: '跟随设备显示设置。',
    ko: '기기의 표시 설정을 따릅니다.',
    es: 'Sigue la configuración del dispositivo.',
    de: 'Folgt der Geräteeinstellung.',
  );
  String get darkDesc => localized(
    en: 'Use the higher-contrast dark theme explicitly.',
    ja: '高コントラストなダークテーマを明示的に使います。',
    zh: '明确使用高对比度深色主题。',
    ko: '대비가 높은 다크 테마를 명시적으로 사용합니다.',
    es: 'Usa explícitamente el tema oscuro de mayor contraste.',
    de: 'Verwendet ausdrücklich das kontrastreichere dunkle Design.',
  );

  String get about => localized(
    en: 'About',
    ja: 'アプリ情報',
    zh: '应用信息',
    ko: '앱 정보',
    es: 'Información',
    de: 'Info',
  );
  String get appVersion => localized(
    en: 'App version',
    ja: 'アプリバージョン',
    zh: '应用版本',
    ko: '앱 버전',
    es: 'Versión de la app',
    de: 'App-Version',
  );
  String get appUpdates => localized(
    en: 'App updates',
    ja: 'アプリ更新',
    zh: '应用更新',
    ko: '앱 업데이트',
    es: 'Actualizaciones de la app',
    de: 'App-Updates',
  );
  String get appUpdatesDesc => localized(
    en: 'Check Google Play in-app updates and start the recommended update flow.',
    ja: 'Google Play のアプリ内更新を確認し、必要な更新を開始します。',
    zh: '检查 Google Play 应用内更新，并启动推荐的更新流程。',
    ko: 'Google Play 인앱 업데이트를 확인하고 권장 업데이트 흐름을 시작합니다.',
    es: 'Comprueba las actualizaciones integradas de Google Play e inicia el flujo recomendado.',
    de: 'Prüft Google Play In-App-Updates und startet den empfohlenen Update-Ablauf.',
  );
  String get checkForUpdates => localized(
    en: 'Check for updates',
    ja: '更新を確認',
    zh: '检查更新',
    ko: '업데이트 확인',
    es: 'Buscar actualizaciones',
    de: 'Nach Updates suchen',
  );
  String get startUpdate => localized(
    en: 'Start update',
    ja: '更新を開始',
    zh: '开始更新',
    ko: '업데이트 시작',
    es: 'Iniciar actualización',
    de: 'Update starten',
  );
  String get completeUpdateInstall => localized(
    en: 'Complete update',
    ja: '更新を完了',
    zh: '完成更新',
    ko: '업데이트 완료',
    es: 'Completar actualización',
    de: 'Update abschließen',
  );
  String get updateSupportedOnAndroidOnly => localized(
    en: 'In-app updates are available on Android builds distributed through Google Play.',
    ja: 'アプリ内更新は Android の Google Play 配布で利用できます。',
    zh: '应用内更新可用于通过 Google Play 分发的 Android 版本。',
    ko: '인앱 업데이트는 Google Play로 배포된 Android 빌드에서 사용할 수 있습니다.',
    es: 'Las actualizaciones integradas están disponibles en builds de Android distribuidas por Google Play.',
    de: 'In-App-Updates sind für Android-Builds verfügbar, die über Google Play verteilt werden.',
  );
  String get updateStatusUpToDate => localized(
    en: 'The installed build is up to date.',
    ja: '現在のビルドは最新です。',
    zh: '当前安装的版本已是最新。',
    ko: '설치된 빌드가 최신입니다.',
    es: 'La build instalada está actualizada.',
    de: 'Der installierte Build ist aktuell.',
  );
  String get updateStatusAvailable => localized(
    en: 'A newer build is available on Google Play.',
    ja: 'Google Play に新しい更新があります。',
    zh: 'Google Play 上有新版本可用。',
    ko: 'Google Play에 새 빌드가 있습니다.',
    es: 'Hay una build más reciente en Google Play.',
    de: 'Ein neuerer Build ist auf Google Play verfügbar.',
  );
  String get updateStatusChecking => localized(
    en: 'Checking for updates...',
    ja: '更新を確認しています...',
    zh: '正在检查更新...',
    ko: '업데이트 확인 중...',
    es: 'Buscando actualizaciones...',
    de: 'Updates werden gesucht...',
  );
  String get updateStatusUnsupported => localized(
    en: 'In-app updates are not available in this runtime.',
    ja: 'この実行環境ではアプリ内更新を利用できません。',
    zh: '此运行环境不支持应用内更新。',
    ko: '이 실행 환경에서는 인앱 업데이트를 사용할 수 없습니다.',
    es: 'Las actualizaciones integradas no están disponibles en este entorno.',
    de: 'In-App-Updates sind in dieser Laufzeit nicht verfügbar.',
  );
  String get updateStatusStarted => localized(
    en: 'Started the Google Play update flow.',
    ja: 'Google Play の更新フローを開始しました。',
    zh: '已开始 Google Play 更新流程。',
    ko: 'Google Play 업데이트 흐름을 시작했습니다.',
    es: 'Se inició el flujo de actualización de Google Play.',
    de: 'Der Google Play Update-Ablauf wurde gestartet.',
  );
  String get updateFlexibleReady => localized(
    en: 'A flexible update is downloaded. Complete it to restart and apply the update.',
    ja: '柔軟な更新がダウンロード済みです。完了を押すと再起動して更新します。',
    zh: '灵活更新已下载。完成后将重启并应用更新。',
    ko: '유연한 업데이트가 다운로드되었습니다. 완료하면 재시작 후 업데이트가 적용됩니다.',
    es: 'Se descargó una actualización flexible. Complétala para reiniciar y aplicarla.',
    de: 'Ein flexibles Update wurde heruntergeladen. Schließe es ab, um neu zu starten und es anzuwenden.',
  );
  String updateVersionLabel(int? versionCode) => isJapanese
      ? (versionCode == null ? '配信中の更新' : '配信中の更新: $versionCode')
      : (versionCode == null
            ? 'Available update'
            : 'Available update: $versionCode');
  String updatePriorityLabel(int? priority) =>
      isJapanese ? '優先度: ${priority ?? 0}' : 'Priority: ${priority ?? 0}';
  String get ossLicenses => localized(
    en: 'OSS licenses',
    ja: 'OSS ライセンス',
    zh: 'OSS 许可证',
    ko: 'OSS 라이선스',
    es: 'Licencias OSS',
    de: 'OSS-Lizenzen',
  );
  String get ossLicensesDesc => localized(
    en: 'View bundled open-source software licenses.',
    ja: '利用しているオープンソースソフトウェアのライセンスを表示します。',
    zh: '查看捆绑的开源软件许可证。',
    ko: '포함된 오픈 소스 소프트웨어 라이선스를 봅니다.',
    es: 'Muestra las licencias del software de código abierto incluido.',
    de: 'Zeigt die Lizenzen der gebündelten Open-Source-Software an.',
  );
  String currentFlavor(String name) =>
      isJapanese ? '現在の flavor: $name' : 'Current flavor: $name';
  String readingVersion() =>
      isJapanese ? 'バージョンを読み込み中...' : 'Reading app version...';

  String get homeWidgetQuickCapture => localized(
    en: 'Allow external quick capture',
    ja: '外部クイックメモ',
    zh: '允许外部快速记录',
    ko: '외부 빠른 캡처 허용',
    es: 'Permitir captura rápida externa',
    de: 'Externe Schnellnotiz erlauben',
  );
  String get homeWidgetQuickCaptureDesc => localized(
    en: 'Let the home widget or Android share sheet open a quick memo surface without unlocking the full app.',
    ja: 'ホームウィジェットや共有メニューから、通常のアプリロックを開かずに簡易メモ画面を開けます。',
    zh: '允许主屏幕小组件或 Android 分享面板在不解锁完整应用的情况下打开快速备忘录界面。',
    ko: '홈 위젯이나 Android 공유 시트에서 전체 앱 잠금 해제 없이 빠른 메모 화면을 열 수 있습니다.',
    es: 'Permite que el widget de inicio o la hoja para compartir de Android abra una nota rápida sin desbloquear toda la app.',
    de: 'Erlaubt dem Home-Widget oder Android-Teilen-Menü, eine Schnellnotiz zu öffnen, ohne die ganze App zu entsperren.',
  );
  String get homeWidgetQuickCaptureMobileOnly => localized(
    en: 'Mobile-only. When enabled, the home widget or Android share sheet can open a quick memo surface outside the normal app lock.',
    ja: 'モバイルのみ。オンにすると、ホームウィジェットや共有メニューから通常のアプリロックを開かずに簡易メモ画面を開けます。',
    zh: '仅限移动端。开启后，主屏幕小组件或 Android 分享面板可在普通应用锁之外打开快速备忘录界面。',
    ko: '모바일 전용입니다. 켜면 홈 위젯이나 Android 공유 시트에서 일반 앱 잠금 밖의 빠른 메모 화면을 열 수 있습니다.',
    es: 'Solo móvil. Al activarlo, el widget de inicio o la hoja para compartir de Android puede abrir una nota rápida fuera del bloqueo normal.',
    de: 'Nur mobil. Wenn aktiviert, können Home-Widget oder Android-Teilen-Menü eine Schnellnotiz außerhalb der normalen App-Sperre öffnen.',
  );

  String get unlockHiMemo => localized(
    en: 'Unlock HiMemo',
    ja: 'HiMemo を解除',
    zh: '解锁 HiMemo',
    ko: 'HiMemo 잠금 해제',
    es: 'Desbloquear HiMemo',
    de: 'HiMemo entsperren',
  );
  String get unlockWithPin => localized(
    en: 'Unlock with PIN',
    ja: 'PIN で解除',
    zh: '使用 PIN 解锁',
    ko: 'PIN으로 잠금 해제',
    es: 'Desbloquear con PIN',
    de: 'Mit PIN entsperren',
  );
  String get authenticate => localized(
    en: 'Authenticate',
    ja: '認証する',
    zh: '认证',
    ko: '인증',
    es: 'Autenticar',
    de: 'Authentifizieren',
  );
  String get disableUnlockForNow => localized(
    en: 'Disable app unlock for now',
    ja: '今はアプリロックを無効にする',
    zh: '暂时关闭应用解锁',
    ko: '지금은 앱 잠금 해제 끄기',
    es: 'Desactivar el desbloqueo por ahora',
    de: 'App-Entsperrung vorerst deaktivieren',
  );
  String get browserPinGate => localized(
    en: 'This browser session is protected with a web PIN.',
    ja: 'このブラウザのセッションは Web PIN で保護されています。',
    zh: '此浏览器会话受 Web PIN 保护。',
    ko: '이 브라우저 세션은 Web PIN으로 보호됩니다.',
    es: 'Esta sesión del navegador está protegida con un PIN web.',
    de: 'Diese Browsersitzung ist mit einer Web-PIN geschützt.',
  );
  String get deviceAuthGate => localized(
    en: 'Resume this session with device authentication.',
    ja: '端末認証でこのセッションを再開します。',
    zh: '使用设备认证恢复此会话。',
    ko: '기기 인증으로 이 세션을 다시 시작합니다.',
    es: 'Reanuda esta sesión con la autenticación del dispositivo.',
    de: 'Setze diese Sitzung mit Geräteauthentifizierung fort.',
  );
  String pinLockSummary({required bool isConfigured, String? lastError}) {
    if (isConfigured) {
      return localized(
        en: 'A web-only unlock PIN is configured for this browser session.',
        ja: 'このブラウザでは解除用 PIN が設定されています。',
        zh: '此浏览器会话已设置仅限 Web 的解锁 PIN。',
        ko: '이 브라우저 세션에는 웹 전용 잠금 해제 PIN이 설정되어 있습니다.',
        es: 'Hay un PIN de desbloqueo web configurado para esta sesión del navegador.',
        de: 'Für diese Browsersitzung ist eine Web-Entsperr-PIN eingerichtet.',
      );
    }
    if (lastError != null && lastError.isNotEmpty) {
      return lastError;
    }
    return localized(
      en: 'No unlock PIN is configured for this browser yet.',
      ja: 'このブラウザでは解除用 PIN はまだ設定されていません。',
      zh: '此浏览器尚未设置解锁 PIN。',
      ko: '이 브라우저에는 아직 잠금 해제 PIN이 설정되어 있지 않습니다.',
      es: 'Todavía no hay un PIN de desbloqueo configurado para este navegador.',
      de: 'Für diesen Browser ist noch keine Entsperr-PIN eingerichtet.',
    );
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
  String onboardingColorThemeBody(int count) => localized(
    en: 'Choose a basic accent now. In Settings > Appearance, you can choose from $count+ traditional Japanese color themes.',
    ja: 'ここでは基本のアクセントカラーを選びます。設定の「表示」では、全$count色以上の日本の伝統色テーマから選択できます。',
    zh: '现在选择一个基础强调色。之后可在“设置”>“外观”中从 $count+ 种日本传统色主题中选择。',
    ko: '여기서는 기본 강조 색상을 선택합니다. 설정 > 표시에서 $count가지 이상의 일본 전통색 테마를 선택할 수 있습니다.',
    es: 'Elige ahora un acento básico. En Ajustes > Apariencia puedes elegir entre más de $count temas de colores tradicionales japoneses.',
    de: 'Wähle jetzt eine grundlegende Akzentfarbe. Unter Einstellungen > Darstellung kannst du aus über $count traditionellen japanischen Farbthemen wählen.',
  );
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

  String get privateProfilesSettingsTitle => localized(
    en: 'Private profiles',
    ja: 'プライベートプロファイル',
    zh: '私密档案',
    ko: '비공개 프로필',
    es: 'Perfiles privados',
    de: 'Private Profile',
  );
  String get privateProfilesSettingsAdminSummary => localized(
    en: 'Profile names and vault IDs stay hidden in Settings, even in admin mode.',
    ja: '管理者モードでも、プロファイル名や保存先IDは設定画面に表示しません。',
    zh: '即使在管理员模式下，设置中也不会显示档案名称和保险库 ID。',
    ko: '관리자 모드에서도 설정 화면에는 프로필 이름과 보관함 ID를 표시하지 않습니다.',
    es: 'Los nombres de perfiles y los ID de bóveda permanecen ocultos en Ajustes, incluso en modo administrador.',
    de: 'Profilnamen und Tresor-IDs bleiben in den Einstellungen verborgen, auch im Administratormodus.',
  );
  String privateProfilesSettingsActiveSummary(String _) => localized(
    en: 'A verified private profile is currently open.',
    ja: '現在は認証済みのプライベートプロファイルを表示しています。',
    zh: '当前已打开经过验证的私密档案。',
    ko: '현재 인증된 비공개 프로필이 열려 있습니다.',
    es: 'Hay un perfil privado verificado abierto.',
    de: 'Ein verifiziertes privates Profil ist derzeit geöffnet.',
  );
  String get privateProfilesSettingsDefaultSummary => localized(
    en: 'Notes stays visible by default. Open another profile only when you need it.',
    ja: '通常は Notes だけを表示し、必要なときだけ別のプロファイルを開きます。',
    zh: '默认只显示 Notes。仅在需要时打开其他档案。',
    ko: '기본적으로 Notes만 표시하고, 필요할 때만 다른 프로필을 엽니다.',
    es: 'Notes permanece visible de forma predeterminada. Abre otro perfil solo cuando lo necesites.',
    de: 'Notes bleibt standardmäßig sichtbar. Öffne ein anderes Profil nur bei Bedarf.',
  );
  String get privateProfilesSettingsBody => localized(
    en: 'Enter a password from the key icon in the top bar to open only the matching profile. Settings does not list configured profile names or vault IDs. When a profile is open, Appearance can set its accent color separately from normal mode.',
    ja: '右上の鍵アイコンからパスワードを入力すると、一致するプロファイルだけを開けます。設定画面では登録済みプロファイルの名前や保存先IDを列挙しません。プロファイルを開いている間は、「表示」から通常モードとは別のアクセントカラーを設定できます。',
    zh: '从顶部栏的钥匙图标输入密码后，只会打开匹配的档案。设置中不会列出已配置档案的名称或保险库 ID。打开档案时，可在“外观”中为该档案设置不同于普通模式的强调色。',
    ko: '상단의 열쇠 아이콘에서 비밀번호를 입력하면 일치하는 프로필만 열립니다. 설정 화면에는 구성된 프로필 이름이나 보관함 ID를 나열하지 않습니다. 프로필이 열려 있을 때는 표시 설정에서 일반 모드와 다른 강조 색상을 따로 설정할 수 있습니다.',
    es: 'Introduce una contraseña desde el icono de llave de la barra superior para abrir solo el perfil que coincida. Ajustes no enumera nombres de perfiles ni ID de bóveda configurados. Cuando un perfil está abierto, Apariencia puede definir su color de acento por separado del modo normal.',
    de: 'Gib über das Schlüsselsymbol in der oberen Leiste ein Passwort ein, um nur das passende Profil zu öffnen. Die Einstellungen listen keine eingerichteten Profilnamen oder Tresor-IDs auf. Wenn ein Profil geöffnet ist, kann Darstellung seine Akzentfarbe getrennt vom normalen Modus festlegen.',
  );
  String get addPrivateProfile => localized(
    en: 'Add profile',
    ja: 'プロファイルを追加',
    zh: '添加档案',
    ko: '프로필 추가',
    es: 'Añadir perfil',
    de: 'Profil hinzufügen',
  );
  String get adminModeActiveLabel => localized(
    en: 'Admin mode active',
    ja: '管理者モード中',
    zh: '管理员模式已启用',
    ko: '관리자 모드 활성화',
    es: 'Modo administrador activo',
    de: 'Administratormodus aktiv',
  );
  String get enterAdminModeLabel => localized(
    en: 'Enter admin mode',
    ja: '管理者モードへ移行',
    zh: '进入管理员模式',
    ko: '관리자 모드로 전환',
    es: 'Entrar en modo administrador',
    de: 'Administratormodus öffnen',
  );
  String get exitAdminModeLabel => localized(
    en: 'Exit admin mode',
    ja: '管理者モードを終了',
    zh: '退出管理员模式',
    ko: '관리자 모드 종료',
    es: 'Salir del modo administrador',
    de: 'Administratormodus beenden',
  );
  String get noPrivateProfilesMessage => localized(
    en: 'No private profiles yet.',
    ja: 'まだプライベートプロファイルはありません。',
    zh: '还没有私密档案。',
    ko: '아직 비공개 프로필이 없습니다.',
    es: 'Todavía no hay perfiles privados.',
    de: 'Noch keine privaten Profile.',
  );
  String privateProfilesHiddenSummary(int count) => localized(
    en: '$count private profiles are configured. Names and vault IDs are hidden.',
    ja: '$count 件のプライベートプロファイルが登録されています。名前と保存先IDは非表示です。',
    zh: '已配置 $count 个私密档案。名称和保险库 ID 已隐藏。',
    ko: '비공개 프로필 $count개가 설정되어 있습니다. 이름과 보관함 ID는 숨겨집니다.',
    es: 'Hay $count perfiles privados configurados. Los nombres y los ID de bóveda están ocultos.',
    de: '$count private Profile sind eingerichtet. Namen und Tresor-IDs sind verborgen.',
  );
  String get setAlternateProfilePassword => localized(
    en: 'Set alternate profile password',
    ja: '別プロファイル用パスワードを設定',
    zh: '设置备用档案密码',
    ko: '대체 프로필 비밀번호 설정',
    es: 'Definir contraseña de perfil alternativo',
    de: 'Passwort für alternatives Profil festlegen',
  );
  String get changeAlternateProfilePassword => localized(
    en: 'Change alternate profile password',
    ja: '別プロファイル用パスワードを変更',
    zh: '更改备用档案密码',
    ko: '대체 프로필 비밀번호 변경',
    es: 'Cambiar contraseña de perfil alternativo',
    de: 'Passwort für alternatives Profil ändern',
  );
  String get resetAlternateProfilePassword => localized(
    en: 'Reset alternate profile password',
    ja: '別プロファイル用パスワードをリセット',
    zh: '重置备用档案密码',
    ko: '대체 프로필 비밀번호 재설정',
    es: 'Restablecer contraseña de perfil alternativo',
    de: 'Passwort für alternatives Profil zurücksetzen',
  );

  String get skip => localized(
    en: 'Skip',
    ja: 'スキップ',
    zh: '跳过',
    ko: '건너뛰기',
    es: 'Omitir',
    de: 'Überspringen',
  );
  String get next => localized(
    en: 'Next',
    ja: '次へ',
    zh: '下一步',
    ko: '다음',
    es: 'Siguiente',
    de: 'Weiter',
  );
  String get finishSetup => localized(
    en: 'Finish setup',
    ja: 'セットアップ完了',
    zh: '完成设置',
    ko: '설정 완료',
    es: 'Finalizar configuración',
    de: 'Einrichtung abschließen',
  );
  String get setAppUnlockPin => localized(
    en: 'Set app unlock PIN',
    ja: 'アプリ解除 PIN を設定',
    zh: '设置应用解锁 PIN',
    ko: '앱 잠금 해제 PIN 설정',
    es: 'Definir PIN de desbloqueo de la app',
    de: 'App-Entsperr-PIN festlegen',
  );
  String get pin => 'PIN';
  String get cancel => localized(
    en: 'Cancel',
    ja: 'キャンセル',
    zh: '取消',
    ko: '취소',
    es: 'Cancelar',
    de: 'Abbrechen',
  );
  String get delete => text('action.delete');
  String get save => localized(
    en: 'Save',
    ja: '保存',
    zh: '保存',
    ko: '저장',
    es: 'Guardar',
    de: 'Speichern',
  );
  String get useExactly4Digits => localized(
    en: 'Use exactly 4 digits.',
    ja: '4桁ちょうどで入力してください。',
    zh: '请正好输入 4 位数字。',
    ko: '정확히 4자리로 입력하세요.',
    es: 'Usa exactamente 4 dígitos.',
    de: 'Verwende genau 4 Ziffern.',
  );
  String get digitsOnly => localized(
    en: 'Digits only.',
    ja: '数字のみ入力できます。',
    zh: '只能输入数字。',
    ko: '숫자만 입력할 수 있습니다.',
    es: 'Solo dígitos.',
    de: 'Nur Ziffern.',
  );
  String get coverKey => localized(
    en: 'Cover key',
    ja: 'カバーキー',
    zh: '掩护密钥',
    ko: '커버 키',
    es: 'Clave de cobertura',
    de: 'Tarnschlüssel',
  );
  String get privateKey => localized(
    en: 'Private key',
    ja: 'プライベートキー',
    zh: '私密密钥',
    ko: '비공개 키',
    es: 'Clave privada',
    de: 'Privater Schlüssel',
  );
  String get setPrivateKey => localized(
    en: 'Set private key',
    ja: 'プライベートキーを設定',
    zh: '设置私密密钥',
    ko: '비공개 키 설정',
    es: 'Definir clave privada',
    de: 'Privaten Schlüssel festlegen',
  );
  String get unlockPrivateVault => localized(
    en: 'Unlock private vault',
    ja: 'プライベート領域を解除',
    zh: '解锁私密保险库',
    ko: '비공개 보관함 잠금 해제',
    es: 'Desbloquear bóveda privada',
    de: 'Privaten Tresor entsperren',
  );
  String get unlock => localized(
    en: 'Unlock',
    ja: '解除',
    zh: '解锁',
    ko: '잠금 해제',
    es: 'Desbloquear',
    de: 'Entsperren',
  );
  String confirmPrivateKey(String label) => localized(
    en: 'Confirm $label',
    ja: '$label を確認',
    zh: '确认$label',
    ko: '$label 확인',
    es: 'Confirmar $label',
    de: '$label bestätigen',
  );
  String get keysDoNotMatch => localized(
    en: 'Keys do not match.',
    ja: 'キーが一致しません。',
    zh: '密钥不一致。',
    ko: '키가 일치하지 않습니다.',
    es: 'Las claves no coinciden.',
    de: 'Die Schlüssel stimmen nicht überein.',
  );
  String get privateKeyIncorrect => localized(
    en: 'Private key is not correct.',
    ja: 'プライベートキーが正しくありません。',
    zh: '私密密钥不正确。',
    ko: '비공개 키가 올바르지 않습니다.',
    es: 'La clave privada no es correcta.',
    de: 'Der private Schlüssel ist nicht korrekt.',
  );
  String get useAtLeast4Chars => localized(
    en: 'Use at least 4 characters.',
    ja: '4文字以上で入力してください。',
    zh: '请至少输入 4 个字符。',
    ko: '4자 이상 입력하세요.',
    es: 'Usa al menos 4 caracteres.',
    de: 'Verwende mindestens 4 Zeichen.',
  );
  String get quickMemo => localized(
    en: 'Quick memo',
    ja: 'クイックメモ',
    zh: '快速备忘录',
    ko: '빠른 메모',
    es: 'Memo rápido',
    de: 'Schnellnotiz',
  );
  String get richMemo => localized(
    en: 'Rich memo',
    ja: 'リッチメモ',
    zh: '富文本备忘录',
    ko: '리치 메모',
    es: 'Memo enriquecido',
    de: 'Rich-Memo',
  );
  String get newNote => localized(
    en: 'New note',
    ja: '新しいノート',
    zh: '新笔记',
    ko: '새 노트',
    es: 'Nota nueva',
    de: 'Neue Notiz',
  );
  String get editNote => localized(
    en: 'Edit note',
    ja: 'ノートを編集',
    zh: '编辑笔记',
    ko: '노트 편집',
    es: 'Editar nota',
    de: 'Notiz bearbeiten',
  );
  String get memoLabel => localized(
    en: 'Memo',
    ja: 'メモ',
    zh: '备忘录',
    ko: '메모',
    es: 'Memo',
    de: 'Memo',
  );
  String get memoFirstLineHint => localized(
    en: 'Use the first line as the title',
    ja: '1行目をタイトルとして使います',
    zh: '第一行会作为标题',
    ko: '첫 줄을 제목으로 사용합니다',
    es: 'Usa la primera línea como título',
    de: 'Die erste Zeile wird als Titel verwendet',
  );
  String get vault => localized(
    en: 'Vault',
    ja: '分類',
    zh: '分类',
    ko: '분류',
    es: 'Bóveda',
    de: 'Tresor',
  );
  String get pinThisNote => localized(
    en: 'Pin this note',
    ja: 'このノートを固定',
    zh: '固定此笔记',
    ko: '이 노트 고정',
    es: 'Fijar esta nota',
    de: 'Diese Notiz anheften',
  );
  String get pinThisNoteDesc => localized(
    en: 'Pinned notes stay near the top.',
    ja: '固定したノートは一覧の上に表示されます。',
    zh: '固定的笔记会显示在列表上方。',
    ko: '고정한 노트는 목록 위쪽에 표시됩니다.',
    es: 'Las notas fijadas permanecen cerca de la parte superior.',
    de: 'Angeheftete Notizen bleiben weiter oben.',
  );
  String get createNote => localized(
    en: 'Create note',
    ja: 'ノートを作成',
    zh: '创建笔记',
    ko: '노트 만들기',
    es: 'Crear nota',
    de: 'Notiz erstellen',
  );
  String get saveChanges => localized(
    en: 'Save changes',
    ja: '変更を保存',
    zh: '保存更改',
    ko: '변경 사항 저장',
    es: 'Guardar cambios',
    de: 'Änderungen speichern',
  );
  String get startWritingHere => localized(
    en: 'Start writing here',
    ja: 'ここから書き始めます',
    zh: '从这里开始书写',
    ko: '여기에서 쓰기 시작합니다',
    es: 'Empieza a escribir aquí',
    de: 'Hier mit dem Schreiben beginnen',
  );
  String get attachments => localized(
    en: 'Attachments',
    ja: '添付',
    zh: '附件',
    ko: '첨부',
    es: 'Adjuntos',
    de: 'Anhänge',
  );
  String get addMedia => localized(
    en: 'Add media',
    ja: 'メディアを追加',
    zh: '添加媒体',
    ko: '미디어 추가',
    es: 'Añadir multimedia',
    de: 'Medien hinzufügen',
  );
  String get pickPhoto => localized(
    en: 'Pick photo',
    ja: '写真を選ぶ',
    zh: '选择照片',
    ko: '사진 선택',
    es: 'Elegir foto',
    de: 'Foto auswählen',
  );
  String get takePhoto => localized(
    en: 'Take photo',
    ja: '写真を撮る',
    zh: '拍照',
    ko: '사진 촬영',
    es: 'Tomar foto',
    de: 'Foto aufnehmen',
  );
  String get pickVideo => localized(
    en: 'Pick video',
    ja: '動画を選ぶ',
    zh: '选择视频',
    ko: '동영상 선택',
    es: 'Elegir vídeo',
    de: 'Video auswählen',
  );
  String get recordVideo => localized(
    en: 'Record video',
    ja: '動画を撮る',
    zh: '录制视频',
    ko: '동영상 녹화',
    es: 'Grabar vídeo',
    de: 'Video aufnehmen',
  );
  String get recordAudio => localized(
    en: 'Record audio',
    ja: '音声を録音',
    zh: '录音',
    ko: '오디오 녹음',
    es: 'Grabar audio',
    de: 'Audio aufnehmen',
  );
  String get pickAudio => localized(
    en: 'Pick audio',
    ja: '音声を選ぶ',
    zh: '选择音频',
    ko: '오디오 선택',
    es: 'Elegir audio',
    de: 'Audio auswählen',
  );
  String get addCurrentLocation => localized(
    en: 'Add current location',
    ja: '現在地を追加',
    zh: '添加当前位置',
    ko: '현재 위치 추가',
    es: 'Añadir ubicación actual',
    de: 'Aktuellen Standort hinzufügen',
  );
  String get currentLocationLabel => localized(
    en: 'Current location',
    ja: '現在地',
    zh: '当前位置',
    ko: '현재 위치',
    es: 'Ubicación actual',
    de: 'Aktueller Standort',
  );
  String get estimatedAddressLabel => localized(
    en: 'Estimated address',
    ja: '推定住所',
    zh: '推测地址',
    ko: '추정 주소',
    es: 'Dirección estimada',
    de: 'Geschätzte Adresse',
  );
  String get latitudeLabel => localized(
    en: 'Latitude',
    ja: '緯度',
    zh: '纬度',
    ko: '위도',
    es: 'Latitud',
    de: 'Breitengrad',
  );
  String get longitudeLabel => localized(
    en: 'Longitude',
    ja: '経度',
    zh: '经度',
    ko: '경도',
    es: 'Longitud',
    de: 'Längengrad',
  );
  String get locationAccuracyLabel => localized(
    en: 'Accuracy',
    ja: '精度',
    zh: '精度',
    ko: '정확도',
    es: 'Precisión',
    de: 'Genauigkeit',
  );
  String get openMap => localized(
    en: 'Open map',
    ja: '地図を開く',
    zh: '打开地图',
    ko: '지도 열기',
    es: 'Abrir mapa',
    de: 'Karte öffnen',
  );
  String get copyMapLink => localized(
    en: 'Copy map link',
    ja: '地図リンクをコピー',
    zh: '复制地图链接',
    ko: '지도 링크 복사',
    es: 'Copiar enlace del mapa',
    de: 'Kartenlink kopieren',
  );
  String get mapLinkCopied => localized(
    en: 'Map link copied.',
    ja: '地図リンクをコピーしました。',
    zh: '已复制地图链接。',
    ko: '지도 링크를 복사했습니다.',
    es: 'Enlace del mapa copiado.',
    de: 'Kartenlink kopiert.',
  );
  String get mapOpenFailed => localized(
    en: 'Could not open the map.',
    ja: '地図を開けませんでした。',
    zh: '无法打开地图。',
    ko: '지도를 열 수 없습니다.',
    es: 'No se pudo abrir el mapa.',
    de: 'Die Karte konnte nicht geöffnet werden.',
  );
  String get linkOpenFailed => localized(
    en: 'Could not open the link.',
    ja: 'リンクを開けませんでした。',
    zh: '无法打开链接。',
    ko: '링크를 열 수 없습니다.',
    es: 'No se pudo abrir el enlace.',
    de: 'Der Link konnte nicht geöffnet werden.',
  );
  String get openExternalLinkTitle => localized(
    en: 'Open external link?',
    ja: '外部リンクを開きますか？',
    zh: '要打开外部链接吗？',
    ko: '외부 링크를 열까요?',
    es: '¿Abrir enlace externo?',
    de: 'Externen Link öffnen?',
  );
  String get openExternalLinkMessage => localized(
    en: 'This link will open outside HiMemo. Check the URL before continuing.',
    ja: 'このリンクはHiMemoの外部で開かれます。URLを確認してから続行してください。',
    zh: '此链接将在 HiMemo 外部打开。继续前请确认 URL。',
    ko: '이 링크는 HiMemo 외부에서 열립니다. 계속하기 전에 URL을 확인하세요.',
    es: 'Este enlace se abrirá fuera de HiMemo. Comprueba la URL antes de continuar.',
    de: 'Dieser Link wird außerhalb von HiMemo geöffnet. Prüfe die URL, bevor du fortfährst.',
  );
  String get openLink => localized(
    en: 'Open',
    ja: '開く',
    zh: '打开',
    ko: '열기',
    es: 'Abrir',
    de: 'Öffnen',
  );
  String get locationServicesOff => localized(
    en: 'Location services are off. Enable them in device settings.',
    ja: '位置情報サービスがオフです。端末設定で有効にしてください。',
    zh: '定位服务已关闭。请在设备设置中启用。',
    ko: '위치 서비스가 꺼져 있습니다. 기기 설정에서 켜세요.',
    es: 'Los servicios de ubicación están desactivados. Actívalos en los ajustes del dispositivo.',
    de: 'Standortdienste sind deaktiviert. Aktiviere sie in den Geräteeinstellungen.',
  );
  String get locationPermissionRequired => localized(
    en: 'Location permission is required to add current location.',
    ja: '現在地を追加するには位置情報の許可が必要です。',
    zh: '添加当前位置需要位置权限。',
    ko: '현재 위치를 추가하려면 위치 권한이 필요합니다.',
    es: 'Se necesita permiso de ubicación para añadir la ubicación actual.',
    de: 'Zum Hinzufügen des aktuellen Standorts ist eine Standortberechtigung erforderlich.',
  );
  String get currentLocationAdded => localized(
    en: 'Current location added to the note.',
    ja: '現在地をメモに追加しました。',
    zh: '已将当前位置添加到笔记。',
    ko: '현재 위치를 노트에 추가했습니다.',
    es: 'Ubicación actual añadida a la nota.',
    de: 'Aktueller Standort zur Notiz hinzugefügt.',
  );
  String get currentLocationUnavailable => localized(
    en: 'Could not get current location.',
    ja: '現在地を取得できませんでした。',
    zh: '无法获取当前位置。',
    ko: '현재 위치를 가져올 수 없습니다.',
    es: 'No se pudo obtener la ubicación actual.',
    de: 'Aktueller Standort konnte nicht abgerufen werden.',
  );
  String get attachFromBrowser => localized(
    en: 'Attach photos, videos, or audio files from this browser.',
    ja: 'このブラウザから写真・動画・音声を添付できます。',
    zh: '可从此浏览器添加照片、视频或音频文件。',
    ko: '이 브라우저에서 사진, 동영상 또는 오디오 파일을 첨부할 수 있습니다.',
    es: 'Adjunta fotos, vídeos o archivos de audio desde este navegador.',
    de: 'Füge Fotos, Videos oder Audiodateien aus diesem Browser hinzu.',
  );
  String get attachFromDevice => localized(
    en: 'Attach photos, videos, or audio files from camera or device storage.',
    ja: 'カメラや端末内の写真・動画・音声を添付できます。',
    zh: '可从相机或设备存储添加照片、视频或音频文件。',
    ko: '카메라나 기기 저장소에서 사진, 동영상 또는 오디오 파일을 첨부할 수 있습니다.',
    es: 'Adjunta fotos, vídeos o archivos de audio desde la cámara o el almacenamiento del dispositivo.',
    de: 'Füge Fotos, Videos oder Audiodateien von Kamera oder Gerätespeicher hinzu.',
  );
  String get dateTimeUpdated => localized(
    en: 'Date and time updated',
    ja: '日時を更新しました',
    zh: '已更新时间',
    ko: '날짜와 시간을 업데이트했습니다',
    es: 'Fecha y hora actualizadas',
    de: 'Datum und Uhrzeit aktualisiert',
  );
  String get microphonePermissionNotGranted => localized(
    en: 'Microphone permission was not granted.',
    ja: 'マイクの使用が許可されていません。',
    zh: '未授予麦克风权限。',
    ko: '마이크 권한이 허용되지 않았습니다.',
    es: 'No se concedió el permiso del micrófono.',
    de: 'Die Mikrofonberechtigung wurde nicht erteilt.',
  );
  String get microphonePermissionBrowserHelp => localized(
    en: 'Open this app in Chrome or Edge and allow microphone access from the site settings.',
    ja: 'Chrome または Edge で開き、サイト設定からマイクを許可してください。',
    zh: '请在 Chrome 或 Edge 中打开此应用，并在网站设置中允许麦克风访问。',
    ko: 'Chrome 또는 Edge에서 이 앱을 열고 사이트 설정에서 마이크 접근을 허용하세요.',
    es: 'Abre esta app en Chrome o Edge y permite el acceso al micrófono desde la configuración del sitio.',
    de: 'Öffne diese App in Chrome oder Edge und erlaube den Mikrofonzugriff in den Website-Einstellungen.',
  );
  String get microphonePermissionRequestTimedOut => localized(
    en: 'Microphone permission check timed out. Check the browser permission prompt.',
    ja: 'マイク許可の確認がタイムアウトしました。ブラウザの許可ダイアログを確認してください。',
    zh: '麦克风权限检查超时。请查看浏览器权限提示。',
    ko: '마이크 권한 확인 시간이 초과되었습니다. 브라우저 권한 알림을 확인하세요.',
    es: 'La comprobación del permiso del micrófono agotó el tiempo. Revisa el aviso de permisos del navegador.',
    de: 'Die Mikrofon-Berechtigungsprüfung ist abgelaufen. Prüfe die Berechtigungsabfrage des Browsers.',
  );
  String get microphoneStartTimedOut => localized(
    en: 'Microphone startup timed out. Check whether another app is using the microphone.',
    ja: 'マイクの開始がタイムアウトしました。別のアプリがマイクを使用していないか確認してください。',
    zh: '麦克风启动超时。请检查是否有其他应用正在使用麦克风。',
    ko: '마이크 시작 시간이 초과되었습니다. 다른 앱이 마이크를 사용 중인지 확인하세요.',
    es: 'El inicio del micrófono agotó el tiempo. Comprueba si otra app está usando el micrófono.',
    de: 'Der Mikrofonstart ist abgelaufen. Prüfe, ob eine andere App das Mikrofon verwendet.',
  );
  String audioRecordingStartFailed(String diagnostic) => localized(
    en: 'Could not start recording.$diagnostic',
    ja: '録音を開始できませんでした。$diagnostic',
    zh: '无法开始录音。$diagnostic',
    ko: '녹음을 시작할 수 없습니다. $diagnostic',
    es: 'No se pudo iniciar la grabación. $diagnostic',
    de: 'Die Aufnahme konnte nicht gestartet werden. $diagnostic',
  );
  String get audioRecordingNotificationTitle => localized(
    en: 'HiMemo is recording',
    ja: 'HiMemoで録音中',
    zh: 'HiMemo 正在录音',
    ko: 'HiMemo 녹음 중',
    es: 'HiMemo está grabando',
    de: 'HiMemo nimmt auf',
  );
  String get audioRecordingNotificationContent => localized(
    en: 'Audio memo recording is continuing.',
    ja: '音声メモの録音を継続しています。',
    zh: '音频备忘录录音正在继续。',
    ko: '오디오 메모 녹음이 계속되고 있습니다.',
    es: 'La grabación del memo de audio continúa.',
    de: 'Die Audiomemo-Aufnahme läuft weiter.',
  );
  String get audioRecordingSaveFailed => localized(
    en: 'Could not save the recording.',
    ja: '録音データを保存できませんでした。',
    zh: '无法保存录音。',
    ko: '녹음 데이터를 저장할 수 없습니다.',
    es: 'No se pudo guardar la grabación.',
    de: 'Die Aufnahme konnte nicht gespeichert werden.',
  );
  String get audioRecordingEmpty => localized(
    en: 'The recording was empty.',
    ja: '録音データが空でした。',
    zh: '录音为空。',
    ko: '녹음 데이터가 비어 있습니다.',
    es: 'La grabación estaba vacía.',
    de: 'Die Aufnahme war leer.',
  );
  String get audioRecordingAttachFailed => localized(
    en: 'Could not attach the recording.',
    ja: '録音を添付できませんでした。',
    zh: '无法附加录音。',
    ko: '녹음을 첨부할 수 없습니다.',
    es: 'No se pudo adjuntar la grabación.',
    de: 'Die Aufnahme konnte nicht angehängt werden.',
  );
  String get audioRecordingStoreFailed => localized(
    en: 'Could not save the recording.',
    ja: '録音を保存できませんでした。',
    zh: '无法保存录音。',
    ko: '녹음을 저장할 수 없습니다.',
    es: 'No se pudo guardar la grabación.',
    de: 'Die Aufnahme konnte nicht gespeichert werden.',
  );
  String get audioPlaybackFailed => localized(
    en: 'Could not play this audio.',
    ja: '音声を再生できませんでした。',
    zh: '无法播放此音频。',
    ko: '이 오디오를 재생할 수 없습니다.',
    es: 'No se pudo reproducir este audio.',
    de: 'Dieses Audio konnte nicht abgespielt werden.',
  );
  String get audioMemoRecordingTitle => localized(
    en: 'Record audio memo',
    ja: '音声メモを録音',
    zh: '录制音频备忘录',
    ko: '오디오 메모 녹음',
    es: 'Grabar memo de audio',
    de: 'Audiomemo aufnehmen',
  );
  String get stopAndAttachRecording => localized(
    en: 'Stop and attach',
    ja: '停止して添付',
    zh: '停止并附加',
    ko: '중지하고 첨부',
    es: 'Detener y adjuntar',
    de: 'Stoppen und anhängen',
  );
  String get startRecording => localized(
    en: 'Start recording',
    ja: '録音開始',
    zh: '开始录音',
    ko: '녹음 시작',
    es: 'Iniciar grabación',
    de: 'Aufnahme starten',
  );
  String get undo => localized(
    en: 'Undo',
    ja: '元に戻す',
    zh: '撤销',
    ko: '실행 취소',
    es: 'Deshacer',
    de: 'Rückgängig',
  );
  String get draftRestored => localized(
    en: 'Draft restored',
    ja: '下書きを復元しました',
    zh: '草稿已恢复',
    ko: '초안을 복원했습니다',
    es: 'Borrador restaurado',
    de: 'Entwurf wiederhergestellt',
  );
  String get discardDraft => localized(
    en: 'Discard',
    ja: '破棄',
    zh: '丢弃',
    ko: '삭제',
    es: 'Descartar',
    de: 'Verwerfen',
  );
  String get dismiss => localized(
    en: 'Dismiss',
    ja: '閉じる',
    zh: '关闭',
    ko: '닫기',
    es: 'Cerrar',
    de: 'Schließen',
  );
  String attachmentRemoved(String label) => localized(
    en: '$label removed',
    ja: '$label を削除しました',
    zh: '已移除 $label',
    ko: '$label 제거됨',
    es: '$label eliminado',
    de: '$label entfernt',
  );
  String get removeBlock => localized(
    en: 'Remove block',
    ja: 'この添付を削除',
    zh: '移除此块',
    ko: '이 블록 제거',
    es: 'Eliminar bloque',
    de: 'Block entfernen',
  );
  String get moveEarlier => localized(
    en: 'Move earlier',
    ja: '前へ移動',
    zh: '向前移动',
    ko: '앞으로 이동',
    es: 'Mover antes',
    de: 'Nach vorne verschieben',
  );
  String get moveLater => localized(
    en: 'Move later',
    ja: '後へ移動',
    zh: '向后移动',
    ko: '뒤로 이동',
    es: 'Mover después',
    de: 'Nach hinten verschieben',
  );
  String get syncAppleIdUnsupported => localized(
    en: 'iCloud sync is only available on iOS and macOS in this build.',
    ja: 'このビルドでは iOS / macOS のみ iCloud 同期を利用できます。',
    zh: '此版本仅在 iOS 和 macOS 上支持 iCloud 同步。',
    ko: '이 빌드에서는 iOS 및 macOS에서만 iCloud 동기화를 사용할 수 있습니다.',
    es: 'La sincronización con iCloud solo está disponible en iOS y macOS en esta build.',
    de: 'iCloud-Synchronisierung ist in diesem Build nur unter iOS und macOS verfügbar.',
  );
  String get syncAppleIdUnavailable => localized(
    en: 'iCloud is not available on this device.',
    ja: 'この端末では iCloud を利用できません。',
    zh: '此设备无法使用 iCloud。',
    ko: '이 기기에서는 iCloud를 사용할 수 없습니다.',
    es: 'iCloud no está disponible en este dispositivo.',
    de: 'iCloud ist auf diesem Gerät nicht verfügbar.',
  );
  String get syncAppleIdConnected => localized(
    en: 'iCloud is available. Continue setting up sync.',
    ja: 'iCloud の利用状態を確認できました。同期設定を続けてください。',
    zh: 'iCloud 可用。请继续设置同步。',
    ko: 'iCloud를 사용할 수 있습니다. 동기화 설정을 계속하세요.',
    es: 'iCloud está disponible. Continúa configurando la sincronización.',
    de: 'iCloud ist verfügbar. Fahre mit der Synchronisierungseinrichtung fort.',
  );
  String get syncApplePluginMissing => localized(
    en: 'iCloud sync is not configured in this runtime.',
    ja: 'この実行環境では iCloud 同期を利用できません。',
    zh: '此运行环境未配置 iCloud 同步。',
    ko: '이 실행 환경에는 iCloud 동기화가 설정되어 있지 않습니다.',
    es: 'La sincronización con iCloud no está configurada en este entorno.',
    de: 'iCloud-Synchronisierung ist in dieser Laufzeit nicht konfiguriert.',
  );
  String get syncAppleUnknownError => localized(
    en: 'Unable to confirm iCloud availability. Check the iCloud sign-in state and app capabilities.',
    ja: 'iCloud の状態を確認できませんでした。iCloud へのサインイン状態とアプリの権限を確認してください。',
    zh: '无法确认 iCloud 可用性。请检查 iCloud 登录状态和应用权限。',
    ko: 'iCloud 사용 가능 여부를 확인할 수 없습니다. iCloud 로그인 상태와 앱 권한을 확인하세요.',
    es: 'No se pudo confirmar la disponibilidad de iCloud. Comprueba el inicio de sesión en iCloud y las capacidades de la app.',
    de: 'Die iCloud-Verfügbarkeit konnte nicht bestätigt werden. Prüfe den iCloud-Anmeldestatus und die App-Berechtigungen.',
  );
  String get close => localized(
    en: 'Close',
    ja: '閉じる',
    zh: '关闭',
    ko: '닫기',
    es: 'Cerrar',
    de: 'Schließen',
  );
  String get sendMemo => localized(
    en: 'Send memo',
    ja: 'メモを送信',
    zh: '发送备忘录',
    ko: '메모 보내기',
    es: 'Enviar memo',
    de: 'Memo senden',
  );
  String get sending => localized(
    en: 'Sending...',
    ja: '送信中...',
    zh: '正在发送...',
    ko: '보내는 중...',
    es: 'Enviando...',
    de: 'Wird gesendet...',
  );
  String get sendQuickMemo => localized(
    en: 'Send a quick memo',
    ja: 'クイックメモを送信',
    zh: '发送快速备忘录',
    ko: '빠른 메모 보내기',
    es: 'Enviar memo rápido',
    de: 'Schnellnotiz senden',
  );
  String get quickMemoSaved => localized(
    en: 'Quick memo saved to Notes.',
    ja: 'クイックメモを Notes に保存しました。',
    zh: '快速备忘录已保存到 Notes。',
    ko: '빠른 메모를 Notes에 저장했습니다.',
    es: 'Memo rápido guardado en Notes.',
    de: 'Schnellnotiz in Notes gespeichert.',
  );
  String get sharedMemoSaveFailed => localized(
    en: 'Could not save the shared memo.',
    ja: '共有メモを保存できませんでした。',
    zh: '无法保存共享备忘录。',
    ko: '공유 메모를 저장할 수 없습니다.',
    es: 'No se pudo guardar el memo compartido.',
    de: 'Das geteilte Memo konnte nicht gespeichert werden.',
  );
  String quickCaptureDescription({required bool isShare}) => isShare
      ? localized(
          en: 'Shared text and files can be sent straight to Notes. This route never reveals existing notes or locked profiles.',
          ja: '共有メニューから受け取ったテキストやファイルを、そのまま Notes に送れます。既存ノートやロック中のプロファイルは開きません。',
          zh: '共享的文本和文件可直接发送到 Notes。此入口不会显示现有笔记或锁定的档案。',
          ko: '공유된 텍스트와 파일을 바로 Notes로 보낼 수 있습니다. 이 경로는 기존 노트나 잠긴 프로필을 표시하지 않습니다.',
          es: 'El texto y los archivos compartidos se pueden enviar directamente a Notes. Esta ruta nunca muestra notas existentes ni perfiles bloqueados.',
          de: 'Geteilte Texte und Dateien können direkt an Notes gesendet werden. Diese Route zeigt niemals vorhandene Notizen oder gesperrte Profile.',
        )
      : localized(
          en: 'Capture a quick memo. This route never reveals existing notes or locked profiles.',
          ja: 'すばやくメモを記録します。この画面では既存ノートやロック中のプロファイルは表示しません。',
          zh: '快速记录备忘录。此入口不会显示现有笔记或锁定的档案。',
          ko: '빠른 메모를 기록합니다. 이 화면에서는 기존 노트나 잠긴 프로필을 표시하지 않습니다.',
          es: 'Captura un memo rápido. Esta ruta nunca muestra notas existentes ni perfiles bloqueados.',
          de: 'Erfasse eine Schnellnotiz. Diese Route zeigt niemals vorhandene Notizen oder gesperrte Profile.',
        );
  String get sharedFiles => localized(
    en: 'Shared files',
    ja: '共有ファイル',
    zh: '共享文件',
    ko: '공유 파일',
    es: 'Archivos compartidos',
    de: 'Geteilte Dateien',
  );
  String get filesNotImported => localized(
    en: 'Files not imported',
    ja: '取り込めなかったファイル',
    zh: '未导入的文件',
    ko: '가져오지 못한 파일',
    es: 'Archivos no importados',
    de: 'Nicht importierte Dateien',
  );
  String get sharedFileFallback => localized(
    en: 'Shared file',
    ja: '共有ファイル',
    zh: '共享文件',
    ko: '공유 파일',
    es: 'Archivo compartido',
    de: 'Geteilte Datei',
  );
  String quickCaptureHint({required bool isShare}) => isShare
      ? localized(
          en: 'Tidy the shared text and save it to Notes.',
          ja: '共有されたテキストを整えて、そのまま Notes に保存できます。',
          zh: '整理共享文本并保存到 Notes。',
          ko: '공유된 텍스트를 정리해 Notes에 저장할 수 있습니다.',
          es: 'Ordena el texto compartido y guárdalo en Notes.',
          de: 'Bereinige den geteilten Text und speichere ihn in Notes.',
        )
      : localized(
          en: 'Write a memo and send it to Notes.',
          ja: 'メモを書いて、そのまま Notes に送ります。',
          zh: '写一条备忘录并发送到 Notes。',
          ko: '메모를 작성해 Notes로 보냅니다.',
          es: 'Escribe un memo y envíalo a Notes.',
          de: 'Schreibe ein Memo und sende es an Notes.',
        );
  String sharedFileImportFailureReason(String reason) {
    switch (reason) {
      case 'unsupported_type':
        return localized(
          en: 'This file type is not supported.',
          ja: 'このファイル形式はサポートしていません。',
          zh: '不支持此文件类型。',
          ko: '이 파일 형식은 지원되지 않습니다.',
          es: 'Este tipo de archivo no es compatible.',
          de: 'Dieser Dateityp wird nicht unterstützt.',
        );
      case 'too_large':
        return localized(
          en: 'This file is too large.',
          ja: 'このファイルは大きすぎます。',
          zh: '此文件太大。',
          ko: '이 파일은 너무 큽니다.',
          es: 'Este archivo es demasiado grande.',
          de: 'Diese Datei ist zu groß.',
        );
      case 'unreadable':
        return localized(
          en: 'This file could not be read.',
          ja: 'このファイルを読み込めませんでした。',
          zh: '无法读取此文件。',
          ko: '이 파일을 읽을 수 없습니다.',
          es: 'No se pudo leer este archivo.',
          de: 'Diese Datei konnte nicht gelesen werden.',
        );
      default:
        return reason;
    }
  }

  String get finishSetupFirst => localized(
    en: 'Finish setup first',
    ja: '先に初期設定を完了してください',
    zh: '请先完成初始设置',
    ko: '먼저 초기 설정을 완료하세요',
    es: 'Completa primero la configuración',
    de: 'Schließe zuerst die Einrichtung ab',
  );
  String get quickWidgetCaptureOff => localized(
    en: 'External quick capture is off',
    ja: '外部クイックメモはオフです',
    zh: '外部快速记录已关闭',
    ko: '외부 빠른 캡처가 꺼져 있습니다',
    es: 'La captura rápida externa está desactivada',
    de: 'Externe Schnellnotiz ist deaktiviert',
  );
  String get enableQuickWidgetInSettings => localized(
    en: 'Enable external quick capture in Settings if you want the home widget or Android share sheet to send memos without unlocking the full app.',
    ja: '設定で外部クイックメモをオンにすると、ホームウィジェットや共有メニューからフルアプリを開かずにメモを送れます。',
    zh: '如果希望主屏幕小组件或 Android 分享面板在不解锁完整应用的情况下发送备忘录，请在设置中启用外部快速记录。',
    ko: '홈 위젯이나 Android 공유 시트에서 전체 앱 잠금 해제 없이 메모를 보내려면 설정에서 외부 빠른 캡처를 켜세요.',
    es: 'Activa la captura rápida externa en Ajustes si quieres que el widget de inicio o la hoja para compartir de Android envíen memos sin desbloquear toda la app.',
    de: 'Aktiviere externe Schnellnotizen in den Einstellungen, wenn Home-Widget oder Android-Teilen-Menü Memos senden sollen, ohne die ganze App zu entsperren.',
  );
  String get completeOnboardingBeforeWidget => localized(
    en: 'Complete onboarding before using quick capture from the home widget.',
    ja: 'ホームウィジェットから使う前に、初期設定を完了してください。',
    zh: '从主屏幕小组件使用快速记录前，请先完成引导设置。',
    ko: '홈 위젯에서 빠른 캡처를 사용하기 전에 온보딩을 완료하세요.',
    es: 'Completa la introducción antes de usar la captura rápida desde el widget de inicio.',
    de: 'Schließe das Onboarding ab, bevor du Schnellnotizen über das Home-Widget verwendest.',
  );
}

class _AppStringsDelegate extends LocalizationsDelegate<AppStrings> {
  const _AppStringsDelegate();

  @override
  bool isSupported(Locale locale) =>
      ['en', 'ja', 'zh', 'ko', 'es', 'de'].contains(locale.languageCode);

  @override
  Future<AppStrings> load(Locale locale) =>
      SynchronousFuture<AppStrings>(AppStrings(locale));

  @override
  bool shouldReload(_AppStringsDelegate old) => false;
}

extension AppStringsX on BuildContext {
  AppStrings get strings => AppStrings.of(this);
}
