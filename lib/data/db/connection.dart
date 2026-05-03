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

/// Phase 7 task H.1.d.wipe — delete the on-disk SQLite file at
/// `<app-documents>/petpal.sqlite` plus its sidecar journals (`-wal`,
/// `-shm`). Caller MUST close the active [AppDatabase] before
/// invoking; the production wipe path closes via
/// `appDatabaseProvider`'s `ref.invalidate` (triggers `onDispose`).
///
/// Idempotent — missing files are silent. Subsequent calls to
/// [openAppDatabase] re-create an empty database via the Drift
/// `MigrationStrategy.onCreate` path.
Future<void> deleteAppDatabaseFile() async {
  final dir = await getApplicationDocumentsDirectory();
  for (final ext in const ['', '-wal', '-shm', '-journal']) {
    final f = File('${dir.path}/petpal.sqlite$ext');
    if (await f.exists()) {
      await f.delete();
    }
  }
}
