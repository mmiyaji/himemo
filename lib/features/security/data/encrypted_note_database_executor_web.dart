// ignore_for_file: deprecated_member_use

import 'package:drift/drift.dart';
import 'package:drift/web.dart';

QueryExecutor createEncryptedNoteDatabaseExecutor() {
  return WebDatabase('himemo_notes_web');
}
