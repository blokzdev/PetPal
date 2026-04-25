import 'dart:io';

import 'package:drift/native.dart';
import 'package:path_provider/path_provider.dart';

import 'database.dart';
import 'sqlite_vec.dart';

/// Open the production [AppDatabase] anchored at
/// `<app-documents>/petpal.sqlite`. Registers sqlite-vec as a SQLite
/// auto-extension on first call so vec_distance_l2 etc. are available
/// to every connection that follows.
Future<AppDatabase> openAppDatabase() async {
  registerSqliteVec();
  final dir = await getApplicationDocumentsDirectory();
  final file = File('${dir.path}/petpal.sqlite');
  return AppDatabase(NativeDatabase(file));
}
