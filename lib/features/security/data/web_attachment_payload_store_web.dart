// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class WebAttachmentPayloadStore {
  WebAttachmentPayloadStore();

  static const _databaseName = 'himemo_attachments';
  static const _storeName = 'payloads';
  Future<web.IDBDatabase>? _database;

  Future<web.IDBDatabase> get _db => _database ??= _openDatabase();

  Future<void> put(String id, String payload) async {
    final database = await _db;
    final transaction = database.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).put(payload.toJS, id.toJS);
    await _transactionCompleted(transaction);
  }

  Future<String?> get(String id) async {
    final database = await _db;
    final transaction = database.transaction(_storeName.toJS, 'readonly');
    final request = transaction.objectStore(_storeName).get(id.toJS);
    final value = await _requestResult(request);
    await _transactionCompleted(transaction);
    return (value as JSString?)?.toDart;
  }

  Future<void> delete(String id) async {
    final database = await _db;
    final transaction = database.transaction(_storeName.toJS, 'readwrite');
    transaction.objectStore(_storeName).delete(id.toJS);
    await _transactionCompleted(transaction);
  }

  Future<web.IDBDatabase> _openDatabase() {
    final completer = Completer<web.IDBDatabase>();
    final request = web.window.indexedDB.open(_databaseName, 1);
    request.onupgradeneeded = ((web.Event _) {
      final database = request.result as web.IDBDatabase;
      if (!database.objectStoreNames.contains(_storeName)) {
        database.createObjectStore(_storeName);
      }
    }).toJS;
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result as web.IDBDatabase);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDB open failed.'));
    }).toJS;
    return completer.future;
  }

  Future<JSAny?> _requestResult(web.IDBRequest request) {
    final completer = Completer<JSAny?>();
    request.onsuccess = ((web.Event _) {
      completer.complete(request.result);
    }).toJS;
    request.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDB request failed.'));
    }).toJS;
    return completer.future;
  }

  Future<void> _transactionCompleted(web.IDBTransaction transaction) {
    final completer = Completer<void>();
    transaction.oncomplete = ((web.Event _) {
      completer.complete();
    }).toJS;
    transaction.onerror = ((web.Event _) {
      completer.completeError(StateError('IndexedDB transaction failed.'));
    }).toJS;
    return completer.future;
  }
}
