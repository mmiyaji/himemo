// Browser-only, read-only recovery helpers. Not imported by production UI.
// ignore_for_file: deprecated_member_use

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:drift/wasm.dart';
import 'package:drift/web.dart';
import 'package:web/web.dart' as web;

enum V2RecoveryCopy { legacyLocal, legacyIndexed, wasmIndexed, wasmOpfs }

class V2RecoveryInfo {
  const V2RecoveryInfo(this.copy, {this.size, this.unavailable = false});
  final V2RecoveryCopy copy;
  final int? size;
  final bool unavailable;
}

/// Inspect or export only. The source databases, markers and keys are never
/// changed. Each operation obtains the same Web Lock used by the v2 app.
class SyncV2WebRecovery {
  static const oldName = 'himemo_sync_v2_web';
  static const wasmName = 'himemo_sync_v2_web_wasm';
  static const _lockName = 'org.ruhenheim.himemo.sync-v2.database.$wasmName';

  Future<T> _locked<T>(Future<T> Function() action) async {
    final navigator = web.window.navigator;
    if (!web.window.isSecureContext ||
        navigator.getProperty<JSAny?>('locks'.toJS) == null) {
      throw UnsupportedError('Web Locks unavailable');
    }
    T? result;
    Object? failure;
    StackTrace? trace;
    final request = navigator.locks.request(
      _lockName,
      web.LockOptions(mode: 'exclusive', ifAvailable: true),
      ((web.Lock? lock) {
        Future<JSAny?> run() async {
          if (lock == null) {
            failure = StateError('V2 is open in another tab');
            return null;
          }
          try {
            result = await action();
          } catch (error, stack) {
            failure = error;
            trace = stack;
          }
          return null;
        }

        return run().toJS;
      }).toJS,
    );
    await request.toDart;
    if (failure != null) {
      Error.throwWithStackTrace(failure!, trace ?? StackTrace.current);
    }
    return result as T;
  }

  Future<bool> _legacyIndexedExists() async {
    final indexed = web.window.indexedDB;
    if (indexed.getProperty<JSAny?>('databases'.toJS) == null) {
      throw UnsupportedError('IndexedDB inventory unavailable');
    }
    final databases = (await indexed.databases().toDart).toDart;
    return databases.any((database) => database.name == 'moor_databases');
  }

  Future<Uint8List?> _legacyLocal() async {
    final storage = DriftWebStorage(oldName);
    await storage.open();
    try {
      return await storage.restore();
    } finally {
      await storage.close();
    }
  }

  Future<Uint8List?> _legacyIndexed() async {
    if (!await _legacyIndexedExists()) return null;
    // This legacy reader is used only to export existing snapshots.
    // ignore: experimental_member_use
    final storage = DriftWebStorage.indexedDb(
      oldName,
      migrateFromLocalStorage: false,
    );
    await storage.open();
    try {
      return await storage.restore();
    } finally {
      await storage.close();
    }
  }

  Future<WasmProbeResult> _probe() => WasmDatabase.probe(
    databaseName: wasmName,
    sqlite3Uri: Uri.parse(web.document.baseURI)
        .resolve('vendor/drift/sqlite3.wasm'),
    driftWorkerUri: Uri.parse(web.document.baseURI)
        .resolve('vendor/drift/drift_worker.js'),
  );

  Future<List<V2RecoveryInfo>> inspect() => _locked(() async {
    final result = <V2RecoveryInfo>[];
    for (final copy in [
      V2RecoveryCopy.legacyLocal,
      V2RecoveryCopy.legacyIndexed,
    ]) {
      Uint8List? bytes;
      try {
        bytes = copy == V2RecoveryCopy.legacyLocal
            ? await _legacyLocal()
            : await _legacyIndexed();
        result.add(V2RecoveryInfo(copy, size: bytes?.length));
      } catch (_) {
        result.add(V2RecoveryInfo(copy, unavailable: true));
      } finally {
        bytes?.fillRange(0, bytes.length, 0);
      }
    }
    WasmProbeResult? probe;
    try {
      probe = await _probe();
    } catch (_) {}
    for (final copy in [V2RecoveryCopy.wasmIndexed, V2RecoveryCopy.wasmOpfs]) {
      final api = copy == V2RecoveryCopy.wasmIndexed
          ? WebStorageApi.indexedDb
          : WebStorageApi.opfs;
      Uint8List? bytes;
      try {
        if (probe == null ||
            !probe.availableStorages.any(
              (storage) => storage.storageApi == api,
            )) {
          result.add(V2RecoveryInfo(copy, unavailable: true));
          continue;
        }
        if (!probe.existingDatabases.contains((api, wasmName))) {
          result.add(V2RecoveryInfo(copy));
          continue;
        }
        bytes = await probe.exportDatabase((api, wasmName));
        result.add(
          V2RecoveryInfo(copy, size: bytes?.length, unavailable: bytes == null),
        );
      } catch (_) {
        result.add(V2RecoveryInfo(copy, unavailable: true));
      } finally {
        bytes?.fillRange(0, bytes.length, 0);
      }
    }
    return result;
  });

  /// The caller owns and clears the returned encrypted SQLite snapshot.
  Future<Uint8List> export(V2RecoveryCopy copy) => _locked(() async {
    Uint8List? bytes;
    switch (copy) {
      case V2RecoveryCopy.legacyLocal:
        bytes = await _legacyLocal();
      case V2RecoveryCopy.legacyIndexed:
        bytes = await _legacyIndexed();
      case V2RecoveryCopy.wasmIndexed:
      case V2RecoveryCopy.wasmOpfs:
        final api = copy == V2RecoveryCopy.wasmIndexed
            ? WebStorageApi.indexedDb
            : WebStorageApi.opfs;
        final probe = await _probe();
        if (!probe.existingDatabases.contains((api, wasmName))) {
          throw StateError('Selected snapshot unavailable');
        }
        bytes = await probe.exportDatabase((api, wasmName));
    }
    if (bytes == null) throw StateError('Selected snapshot unavailable');
    return bytes;
  });
}
