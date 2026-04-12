import 'package:drift/drift.dart';

import 'encrypted_note_database_executor_io.dart'
    if (dart.library.html) 'encrypted_note_database_executor_web.dart'
    as executor_impl;

QueryExecutor createEncryptedNoteDatabaseExecutor() {
  return executor_impl.createEncryptedNoteDatabaseExecutor();
}
