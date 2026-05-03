import 'package:drift/drift.dart';

import 'tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    Pets,
    Entries,
    Embeddings,
    Sessions,
    Messages,
    Reminders,
    SkillsInstalled,
    Entitlements,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          // FTS5 mirror of entries.title + body. body lives in the markdown
          // file, so this table is filled by WikiRepo on write — not a Drift
          // table, just a virtual table managed via raw SQL.
          await customStatement(
            'CREATE VIRTUAL TABLE entries_fts5 USING fts5(title, body, '
            "tokenize = 'unicode61 remove_diacritics 2')",
          );
        },
        onUpgrade: (m, from, to) async {
          // Phase 7 task B.1 — schema bump v1 → v2 adds the entitlements
          // cache table (mirrors the Supabase canonical state per
          // DECISIONS row 82). Additive: no data migration needed; the
          // table starts empty and fills on first sign-in / reconciliation.
          if (from < 2) {
            await m.createTable(entitlements);
          }
        },
        beforeOpen: (details) async {
          // SQLite ships with FK enforcement off; turn it on per connection
          // so our cascade rules actually fire.
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}
