import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

QueryExecutor createEncryptedNoteDatabaseExecutor() =>
    _createDatabase('himemo_notes.sqlite');

QueryExecutor createSyncV2DatabaseExecutor() =>
    _createDatabase('himemo_sync_v2.sqlite');

QueryExecutor _createDatabase(String fileName) {
  return LazyDatabase(() async {
    final directory = await getApplicationSupportDirectory();
    final file = File(path.join(directory.path, fileName));
    return NativeDatabase.createInBackground(file);
  });
}
