import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/db/sqlite_vec.dart';

/// On Linux test hosts, the .so lives next to the tests at
/// test/native/libvec0.so. flutter test sets its CWD to the project root.
String _testExtensionPath() =>
    '${Directory.current.path}/test/native/libvec0.so';

Uint8List _floatBytes(List<double> floats) {
  final bd = ByteData(floats.length * 4);
  for (var i = 0; i < floats.length; i++) {
    bd.setFloat32(i * 4, floats[i], Endian.little);
  }
  return bd.buffer.asUint8List();
}

void main() {
  late AppDatabase db;

  setUpAll(() {
    registerSqliteVec(extensionPath: _testExtensionPath());
  });

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('vec_version() returns a v0.* version string', () async {
    final row = await db
        .customSelect('SELECT vec_version() AS v')
        .getSingle();
    final version = row.read<String>('v');
    expect(version, startsWith('v'));
  });

  test('vec_distance_l2 is 0 for identical vectors', () async {
    final v = _floatBytes([1, 2, 3, 4]);
    final row = await db.customSelect(
      'SELECT vec_distance_l2(?, ?) AS d',
      variables: [Variable<Uint8List>(v), Variable<Uint8List>(v)],
    ).getSingle();
    expect(row.read<double>('d'), 0.0);
  });

  test('vec_distance_l2 is positive and ordered for different vectors',
      () async {
    final base = _floatBytes([0, 0, 0, 0]);
    final near = _floatBytes([1, 0, 0, 0]);
    final far = _floatBytes([3, 4, 0, 0]);

    final near0 = await db.customSelect(
      'SELECT vec_distance_l2(?, ?) AS d',
      variables: [Variable<Uint8List>(base), Variable<Uint8List>(near)],
    ).getSingle();
    final far0 = await db.customSelect(
      'SELECT vec_distance_l2(?, ?) AS d',
      variables: [Variable<Uint8List>(base), Variable<Uint8List>(far)],
    ).getSingle();

    expect(near0.read<double>('d'), greaterThan(0));
    expect(far0.read<double>('d'), greaterThan(near0.read<double>('d')));
    // L2(0, [3,4,0,0]) == 5
    expect(far0.read<double>('d'), closeTo(5.0, 1e-5));
  });

  test('PetPal embeddings table can store vectors '
      'and order by vec_distance_l2', () async {
    final petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    Future<int> insertEntry(String path) =>
        db.into(db.entries).insert(
              EntriesCompanion.insert(
                petId: petId,
                path: path,
                type: 'note',
                ts: DateTime(2026, 4, 25),
                title: path,
                bodyHash: 'h',
              ),
            );

    final eA = await insertEntry('a.md');
    final eB = await insertEntry('b.md');
    final eC = await insertEntry('c.md');

    await db.into(db.embeddings).insert(EmbeddingsCompanion.insert(
          entryId: eA,
          chunkIdx: 0,
          vector: _floatBytes([1, 0, 0, 0]),
        ));
    await db.into(db.embeddings).insert(EmbeddingsCompanion.insert(
          entryId: eB,
          chunkIdx: 0,
          vector: _floatBytes([0.5, 0.5, 0, 0]),
        ));
    await db.into(db.embeddings).insert(EmbeddingsCompanion.insert(
          entryId: eC,
          chunkIdx: 0,
          vector: _floatBytes([0, 1, 0, 0]),
        ));

    final query = _floatBytes([1, 0, 0, 0]);
    final ranked = await db.customSelect(
      'SELECT entry_id, vec_distance_l2(vector, ?) AS d '
      'FROM embeddings ORDER BY d ASC',
      variables: [Variable<Uint8List>(query)],
    ).get();

    expect(ranked.map((r) => r.read<int>('entry_id')).toList(), [eA, eB, eC]);
  });
}
