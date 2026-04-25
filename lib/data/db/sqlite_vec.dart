import 'dart:ffi';

import 'package:sqlite3/sqlite3.dart';

bool _registered = false;

/// Register sqlite-vec as a SQLite auto-extension on the global [sqlite3]
/// instance. After this returns, every database opened (including Drift's
/// NativeDatabase) gets vec_*-prefixed SQL functions: `vec_version`,
/// `vec_distance_l2`, `vec_distance_cosine`, etc.
///
/// On Android, the .so files ship in `android/app/src/main/jniLibs/<abi>/`
/// and Android's dynamic linker resolves the bare name `libvec0.so`.
/// On the Linux host (used by `flutter test`), the binary lives at
/// `test/native/libvec0.so`; pass its absolute path via [extensionPath].
///
/// Idempotent: calling more than once in the same isolate is a no-op.
void registerSqliteVec({String? extensionPath}) {
  if (_registered) return;
  final lib = DynamicLibrary.open(extensionPath ?? 'libvec0.so');
  sqlite3.ensureExtensionLoaded(
    SqliteExtension.inLibrary(lib, 'sqlite3_vec_init'),
  );
  _registered = true;
}
