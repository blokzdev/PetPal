import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('schema creates all tables and the FTS5 virtual table', () async {
    final result = await db.customSelect(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'view') "
      "AND name NOT LIKE 'sqlite_%' ORDER BY name",
    ).get();
    final tableNames = result.map((row) => row.read<String>('name')).toSet();

    expect(
      tableNames,
      containsAll(<String>{
        'pets',
        'entries',
        'embeddings',
        'sessions',
        'messages',
        'reminders',
        'skills_installed',
        'entries_fts5',
      }),
    );
  });

  test('inserting a pet round-trips with autoincrement id', () async {
    final id = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    final row = await (db.select(db.pets)
          ..where((p) => p.id.equals(id)))
        .getSingle();
    expect(row.name, 'Milo');
    expect(id, greaterThan(0));
  });

  test('cascade delete: removing a pet removes its entries', () async {
    final petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    await db.into(db.entries).insert(
          EntriesCompanion.insert(
            petId: petId,
            path: 'note/2026-04-25-hello.md',
            type: 'note',
            ts: DateTime(2026, 4, 25),
            title: 'Hello',
            bodyHash: 'deadbeef',
          ),
        );
    expect(await db.select(db.entries).get(), hasLength(1));

    await (db.delete(db.pets)..where((p) => p.id.equals(petId))).go();
    expect(await db.select(db.entries).get(), isEmpty);
  });

  test('FTS5 virtual table supports MATCH queries', () async {
    await db.customStatement(
      '''INSERT INTO entries_fts5 (rowid, title, body) VALUES
         (1, 'Milo vet visit', 'Milo loves frozen carrots and naps')''',
    );
    final hits = await db.customSelect(
      '''SELECT rowid FROM entries_fts5 WHERE entries_fts5 MATCH 'carrot*' ''',
    ).get();
    expect(hits, hasLength(1));
    expect(hits.first.read<int>('rowid'), 1);
  });

  test('reminder mode column accepts deterministic and synthesis', () async {
    final petId = await db.into(db.pets).insert(
          PetsCompanion.insert(
            name: 'Milo',
            createdAt: DateTime(2026, 4, 25),
          ),
        );
    await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            petId: petId,
            kind: 'flea',
            whenTs: DateTime(2026, 5, 15),
            mode: 'deterministic',
          ),
        );
    await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            petId: petId,
            kind: 'weekly_digest',
            whenTs: DateTime(2026, 5, 2),
            mode: 'synthesis',
            payload: const Value('{"window":"7d"}'),
          ),
        );
    expect(await db.select(db.reminders).get(), hasLength(2));
  });
}
