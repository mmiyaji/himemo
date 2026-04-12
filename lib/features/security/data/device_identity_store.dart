import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

class DeviceIdentityStore {
  DeviceIdentityStore({
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
    Random? random,
    this.storageKey = 'sync.device_id',
  }) : _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance,
       _random = random ?? Random.secure();

  final Future<SharedPreferences> Function() _sharedPreferencesProvider;
  final Random _random;
  final String storageKey;

  Future<String> obtain() async {
    final prefs = await _sharedPreferencesProvider();
    final existing = prefs.getString(storageKey);
    if (existing != null && existing.isNotEmpty) {
      return existing;
    }
    final generated = _generateId();
    await prefs.setString(storageKey, generated);
    return generated;
  }

  String _generateId() {
    final bytes = List<int>.generate(18, (_) => _random.nextInt(256));
    return base64UrlEncode(bytes).replaceAll('=', '');
  }
}
