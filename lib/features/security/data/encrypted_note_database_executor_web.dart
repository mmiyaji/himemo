// ignore_for_file: deprecated_member_use

import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor createEncryptedNoteDatabaseExecutor() {
  return WebDatabase('himemo_notes_web');
}

QueryExecutor createSyncV2DatabaseExecutor() {
  return WebDatabase('himemo_sync_v2_web');
}
