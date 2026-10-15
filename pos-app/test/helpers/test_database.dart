// test/helpers/test_database.dart

import 'package:berkahtigaputeri_pos/core/database/pos_database.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

Future<PosDatabase> openTestDatabase({String? path}) {
  sqfliteFfiInit();
  return PosDatabase.openAt(
    path ?? inMemoryDatabasePath,
    factory: databaseFactoryFfi,
  );
}
