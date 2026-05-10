import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class DiagnosticLogService {
  DiagnosticLogService._();

  static final DiagnosticLogService instance = DiagnosticLogService._();
  static const _enabledKey = 'diagnostic_logging.enabled';
  static const _entriesKey = 'diagnostic_logging.entries';
  static const _maxEntries = 1000;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _loaded = false;
  bool _enabled = false;
  List<String> _entries = <String>[];

  Future<bool> isEnabled() async {
    await _ensureLoaded();
    return _enabled;
  }

  Future<void> setEnabled(bool enabled) async {
    await _ensureLoaded();
    _enabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_enabledKey, enabled);
    if (enabled) {
      await record('diagnostic', 'logging enabled', force: true);
    } else {
      await record('diagnostic', 'logging disabled', force: true);
    }
    _notify();
  }

  Future<bool> toggleEnabled() async {
    await _ensureLoaded();
    final enabled = !_enabled;
    await setEnabled(enabled);
    return enabled;
  }

  Future<void> record(
    String category,
    String message, {
    Map<String, Object?> data = const <String, Object?>{},
    bool force = false,
  }) async {
    await _ensureLoaded();
    if (!_enabled && !force) {
      return;
    }
    final values = data.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
    final line = [
      DateTime.now().toUtc().toIso8601String(),
      '[$category]',
      message,
      if (values.isNotEmpty) values,
    ].join(' ');
    _entries = [..._entries, line];
    if (_entries.length > _maxEntries) {
      _entries = _entries.sublist(_entries.length - _maxEntries);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_entriesKey, _entries);
    _notify();
  }

  Future<List<String>> entries() async {
    await _ensureLoaded();
    return List<String>.unmodifiable(_entries);
  }

  Future<String> exportText() async {
    await _ensureLoaded();
    return [
      'HiMemo diagnostic log',
      'exportedAt=${DateTime.now().toUtc().toIso8601String()}',
      'enabled=$_enabled',
      '',
      ..._entries,
    ].join('\n');
  }

  Future<void> clear() async {
    await _ensureLoaded();
    _entries = <String>[];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_entriesKey, _entries);
    await record('diagnostic', 'log cleared', force: true);
    _notify();
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _enabled = prefs.getBool(_enabledKey) ?? false;
    _entries = prefs.getStringList(_entriesKey) ?? <String>[];
    _loaded = true;
  }

  String _sanitize(Object? value) {
    final raw = '$value';
    return raw
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'[\r\n]'), '_');
  }

  void _notify() {
    revision.value += 1;
  }
}

void logDiagnostic(
  String category,
  String message, {
  Map<String, Object?> data = const <String, Object?>{},
}) {
  unawaited(
    DiagnosticLogService.instance.record(category, message, data: data),
  );
}
