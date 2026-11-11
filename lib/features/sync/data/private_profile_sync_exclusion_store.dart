import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../../app/diagnostic_log.dart';

/// Private profiles the user chose to leave out of sync while they stay
/// locked, typically because their unlock key is no longer known.
class PrivateProfileSyncExclusionStore {
  PrivateProfileSyncExclusionStore({
    Future<SharedPreferences> Function()? sharedPreferencesProvider,
  }) : _sharedPreferencesProvider =
           sharedPreferencesProvider ?? SharedPreferences.getInstance;

  static const storageKey = 'sync.excluded_private_profiles.v1';

  final Future<SharedPreferences> Function() _sharedPreferencesProvider;

  Future<Set<String>> read() async {
    final prefs = await _sharedPreferencesProvider();
    final stored = prefs.getString(storageKey);
    if (stored == null || stored.isEmpty) {
      return const <String>{};
    }
    try {
      final decoded = jsonDecode(stored);
      if (decoded is List && decoded.every((id) => id is String)) {
        return Set.unmodifiable(decoded.cast<String>().where((id) => id != ''));
      }
    } on FormatException {
      // Fall through: a damaged list only makes the profiles syncable again.
    }
    logDiagnostic('sync', 'invalid private profile sync exclusions ignored');
    return const <String>{};
  }

  Future<Set<String>> setExcluded(String vaultId, bool excluded) async {
    final current = await read();
    final next = {...current};
    if (excluded) {
      next.add(vaultId);
    } else {
      next.remove(vaultId);
    }
    final prefs = await _sharedPreferencesProvider();
    await prefs.setString(storageKey, jsonEncode(next.toList()..sort()));
    return Set.unmodifiable(next);
  }
}
