import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AuditLogService {
  AuditLogService._();

  static final AuditLogService instance = AuditLogService._();
  static const _entriesKey = 'audit_logging.entries.v1';
  static const _maxEntries = 2000;

  final ValueNotifier<int> revision = ValueNotifier<int>(0);
  bool _loaded = false;
  List<String> _entries = <String>[];

  Future<void> record(
    String event, {
    Map<String, Object?> data = const <String, Object?>{},
  }) async {
    await _ensureLoaded();
    final values = data.entries
        .where((entry) => entry.value != null)
        .map((entry) => '${entry.key}=${_sanitize(entry.value)}')
        .join(' ');
    final line = [
      DateTime.now().toUtc().toIso8601String(),
      '[audit]',
      event,
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
      'HiMemo audit log',
      'exportedAt=${DateTime.now().toUtc().toIso8601String()}',
      '',
      ..._entries,
    ].join('\n');
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
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

void logAudit(
  String event, {
  Map<String, Object?> data = const <String, Object?>{},
}) {
  unawaited(AuditLogService.instance.record(event, data: data));
}
