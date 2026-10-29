import 'dart:convert';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

abstract class SecureKeyValueStore {
  Future<String?> read(String key);

  Future<void> write(String key, String value);

  Future<void> delete(String key);
}

class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  FlutterSecureKeyValueStore({
    FlutterSecureStorage? storage,
    IOSOptions iOptions = IOSOptions.defaultOptions,
    AppleOptions mOptions = MacOsOptions.defaultOptions,
  }) : _coordinationIdentity = jsonEncode([iOptions.toMap(), mOptions.toMap()]),
       _storage =
           storage ??
           FlutterSecureStorage(iOptions: iOptions, mOptions: mOptions);

  final FlutterSecureStorage _storage;
  final String _coordinationIdentity;

  Object get coordinationIdentity => _coordinationIdentity;

  @override
  Future<String?> read(String key) async {
    return _storage.read(key: key);
  }

  @override
  Future<void> write(String key, String value) async {
    await _storage.write(key: key, value: value);
  }

  @override
  Future<void> delete(String key) async {
    await _storage.delete(key: key);
  }
}

/// Preferences-backed storage for the demo Web PIN and its attempt counter.
/// Native authentication counters use FlutterSecureKeyValueStore instead.
class PreferencesKeyValueStore implements SecureKeyValueStore {
  Object get coordinationIdentity => 'himemo.shared_preferences';

  @override
  Future<String?> read(String key) async =>
      (await SharedPreferences.getInstance()).getString(key);

  @override
  Future<void> write(String key, String value) async {
    if (!await (await SharedPreferences.getInstance()).setString(key, value)) {
      throw StateError('Preferences write failed.');
    }
  }

  @override
  Future<void> delete(String key) async {
    if (!await (await SharedPreferences.getInstance()).remove(key)) {
      throw StateError('Preferences delete failed.');
    }
  }
}

Object storageCoordinationIdentity(SecureKeyValueStore store) =>
    switch (store) {
      FlutterSecureKeyValueStore() => store.coordinationIdentity,
      PreferencesKeyValueStore() => store.coordinationIdentity,
      _ => store,
    };

class MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}
