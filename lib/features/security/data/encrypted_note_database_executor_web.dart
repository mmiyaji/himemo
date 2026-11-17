// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:drift/drift.dart';
import 'package:drift/wasm.dart';
import 'package:drift/web.dart';
import 'package:web/web.dart' as web;

QueryExecutor createEncryptedNoteDatabaseExecutor() {
  return WebDatabase('himemo_notes_web');
}

QueryExecutor createSyncV2DatabaseExecutor() => _v2Database(
  'himemo_sync_v2_web_wasm',
  legacyDatabase: 'himemo_sync_v2_web',
);

QueryExecutor createSyncV2LocalPreviewDatabaseExecutor() =>
    _v2Database('himemo_sync_v2_local_preview_wasm');

/// The legacy sql.js backend does not await persistence on transaction commit.
/// The WASM backend uses SQLite's synchronous VFS and fails closed if the
/// browser cannot provide a persistent, concurrency-safe implementation.
QueryExecutor _v2Database(String name, {String? legacyDatabase}) {
  final lock = _V2DatabaseLock(name);
  final lazy = LazyDatabase(() async {
    await lock.acquire();
    try {
      final probe = await WasmDatabase.probe(
        databaseName: name,
        sqlite3Uri: Uri.parse(web.document.baseURI)
            .resolve('vendor/drift/sqlite3.wasm'),
        driftWorkerUri: Uri.parse(web.document.baseURI)
            .resolve('vendor/drift/drift_worker.js'),
      );
      final existing = probe.existingDatabases
          .where((entry) => entry.$2 == name)
          .toList();
      if (existing.length > 1) {
        throw StateError('Multiple v2 database copies require recovery');
      }
      final backend = web.window.localStorage.getItem(lock.backendMarker);
      lock.backendNeedsWrite = backend == null;
      if (backend != null && backend != 'opfs' && backend != 'indexedDb') {
        throw StateError('Invalid v2 database storage marker');
      }
      if (backend != null &&
          (existing.isEmpty || existing.single.$1.name != backend)) {
        throw StateError('The existing v2 database storage is unavailable');
      }
      final candidates =
          probe.availableStorages
              .where(
                (storage) =>
                    storage != WasmStorageImplementation.inMemory &&
                    storage != WasmStorageImplementation.unsafeIndexedDb &&
                    (existing.isEmpty ||
                        storage.storageApi == existing.single.$1),
              )
              .toList()
            ..sort((a, b) => a.index.compareTo(b.index));
      if (candidates.isEmpty) {
        throw UnsupportedError(
          'A durable, concurrency-safe Web database is required',
        );
      }
      final marker = web.window.localStorage.getItem(lock.migrationMarker);
      if (marker != null && marker != 'pending' && marker != 'creating') {
        throw StateError('Invalid v2 migration marker');
      }
      if (marker != null && existing.isNotEmpty) {
        // Never replace an existing destination after an interrupted migration.
        throw StateError('Interrupted v2 migration requires recovery');
      }
      Uint8List? legacyBytes;
      if (legacyDatabase != null) {
        if (existing.isEmpty) {
          // Read the original before creating any destination. Drift's worker
          // treats initializer errors as an empty database otherwise.
          legacyBytes = await _readLegacyDatabase(legacyDatabase);
          if (legacyBytes != null && !_isSqliteDatabase(legacyBytes)) {
            throw const FormatException('Invalid legacy v2 SQLite database');
          }
          if (marker == 'pending' && legacyBytes == null) {
            throw StateError('Interrupted v2 migration source is missing');
          }
        }
      }
      if (existing.isEmpty) {
        web.window.localStorage.setItem(
          lock.migrationMarker,
          legacyBytes == null ? 'creating' : 'pending',
        );
        lock.migrationPending = true;
      }
      lock.selectedBackend = candidates.first.storageApi!.name;
      final initial = legacyBytes;
      lock.workerOpening = true;
      final connection = await probe.open(
        candidates.first,
        name,
        initializeDatabase: initial == null ? null : () => initial,
      );
      lock.workerOpening = false;
      lock.workerOpened = true;
      return connection;
    } catch (_) {
      if (lock.workerOpening) {
        lock.markUncertain();
        throw StateError(
          'The v2 database worker state is uncertain; close or reload this tab before retrying',
        );
      }
      await lock.release();
      rethrow;
    }
  });
  return lazy.interceptWith(_V2ExecutorGuard(lock), sticky: false);
}

bool _isSqliteDatabase(Uint8List bytes) {
  const magic = <int>[
    83,
    81,
    76,
    105,
    116,
    101,
    32,
    102,
    111,
    114,
    109,
    97,
    116,
    32,
    51,
    0,
  ];
  if (bytes.length < 100) return false;
  for (var index = 0; index < magic.length; index++) {
    if (bytes[index] != magic[index]) return false;
  }
  return true;
}

/// Keep every old copy. If two different snapshots exist, do not guess which
/// one is newer; require explicit recovery instead of discarding changes.
Future<Uint8List?> _readLegacyDatabase(String name) async {
  // Drift's legacy snapshot reader is needed only to preserve old databases.
  // ignore: experimental_member_use
  final indexed = DriftWebStorage.indexedDb(
    name,
    migrateFromLocalStorage: false,
  );
  await indexed.open();
  Uint8List? indexedBytes;
  try {
    indexedBytes = await indexed.restore();
  } finally {
    await indexed.close();
  }
  final local = DriftWebStorage(name);
  await local.open();
  try {
    final localBytes = await local.restore();
    if (indexedBytes != null && localBytes != null) {
      if (indexedBytes.length != localBytes.length) {
        throw StateError('Conflicting legacy v2 databases require recovery');
      }
      for (var index = 0; index < indexedBytes.length; index++) {
        if (indexedBytes[index] != localBytes[index]) {
          throw StateError('Conflicting legacy v2 databases require recovery');
        }
      }
    }
    return indexedBytes ?? localBytes;
  } finally {
    await local.close();
  }
}

class _V2ExecutorGuard extends QueryInterceptor {
  _V2ExecutorGuard(this._lock);
  final _V2DatabaseLock _lock;
  bool _failed = false;
  bool _backendRecorded = false;

  @override
  Future<bool> ensureOpen(
    QueryExecutor executor,
    QueryExecutorUser user,
  ) async {
    if (_failed) throw StateError('The v2 database must be reopened');
    try {
      final opened = await executor.ensureOpen(user);
      if (opened && !_backendRecorded) {
        if (_lock.backendNeedsWrite) {
          web.window.localStorage.setItem(
            _lock.backendMarker,
            _lock.selectedBackend!,
          );
        }
        if (_lock.migrationPending) {
          web.window.localStorage.removeItem(_lock.migrationMarker);
          _lock.migrationPending = false;
        }
        _backendRecorded = true;
      }
      return opened;
    } catch (_) {
      _failed = true;
      try {
        await executor.close();
      } catch (_) {
        if (_lock.workerOpening || _lock.workerOpened) {
          _lock.markUncertain();
        }
      } finally {
        await _lock.release();
      }
      if (_lock.holdUntilPageExit) {
        throw StateError(
          'The v2 database worker state is uncertain; close or reload this tab before retrying',
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> close(QueryExecutor inner) async {
    try {
      await inner.close();
    } catch (_) {
      if (!_lock.workerOpening && !_lock.workerOpened) {
        await _lock.release();
        rethrow;
      }
      _lock.markUncertain();
      throw StateError(
        'The v2 database could not close safely; close or reload this tab before retrying',
      );
    }
    await _lock.release();
  }
}

/// Hold an origin-scoped, exclusive lock throughout a V2 database session.
/// Refuse access if the browser cannot provide the lock or another tab owns it.
final _localLocks = <String, _V2DatabaseLock>{};

class _V2DatabaseLock {
  _V2DatabaseLock(this.name);
  final String name;
  String get migrationMarker => 'himemo.sync-v2.migration.$name.v1';
  String get backendMarker => 'himemo.sync-v2.backend.$name.v1';
  bool migrationPending = false;
  bool backendNeedsWrite = false;
  bool workerOpening = false;
  bool workerOpened = false;
  bool holdUntilPageExit = false;
  final _uncertain = Completer<void>();
  String? selectedBackend;
  Completer<JSAny?>? _release;
  Future<JSAny?>? _lockRequest;
  Completer<void>? _localRelease;
  Future<void>? _releasing;

  Future<void> acquire() async {
    final navigator = web.window.navigator;
    if (!web.window.isSecureContext ||
        navigator.getProperty<JSAny?>('locks'.toJS) == null) {
      throw UnsupportedError('Web Locks are required for the v2 database');
    }
    while (true) {
      final previous = _localLocks[name];
      if (previous == null) break;
      if (previous.holdUntilPageExit) {
        throw StateError(
          'V2 database worker state is uncertain; close or reload this tab before retrying',
        );
      }
      await Future.any([
        previous._localRelease!.future,
        previous._uncertain.future,
      ]);
    }
    final localRelease = Completer<void>();
    _localLocks[name] = this;
    _localRelease = localRelease;
    final acquired = Completer<void>();
    final release = Completer<JSAny?>();
    _release = release;
    try {
      final request = navigator.locks.request(
        'org.ruhenheim.himemo.sync-v2.database.$name',
        web.LockOptions(mode: 'exclusive', ifAvailable: true),
        ((web.Lock? lock) {
          if (lock == null) {
            acquired.completeError(
              StateError('V2 database is open in another tab'),
            );
            return Future<JSAny?>.value(null).toJS;
          }
          acquired.complete();
          return release.future.toJS;
        }).toJS,
      );
      _lockRequest = request.toDart.then(
        (value) => value,
        onError: (Object error, StackTrace stack) {
          if (!acquired.isCompleted) acquired.completeError(error, stack);
          return null;
        },
      );
      await acquired.future;
    } catch (_) {
      await this.release();
      rethrow;
    }
  }

  Future<void> release() =>
      holdUntilPageExit ? Future.value() : (_releasing ??= _releaseInner());

  void markUncertain() {
    holdUntilPageExit = true;
    if (!_uncertain.isCompleted) _uncertain.complete();
  }

  Future<void> _releaseInner() async {
    final release = _release;
    _release = null;
    if (release != null && !release.isCompleted) release.complete(null);
    final request = _lockRequest;
    _lockRequest = null;
    try {
      if (request != null) await request;
    } finally {
      final localRelease = _localRelease;
      _localRelease = null;
      if (localRelease != null) {
        if (identical(_localLocks[name], this)) {
          _localLocks.remove(name);
        }
        if (!localRelease.isCompleted) localRelease.complete();
      }
    }
  }
}
