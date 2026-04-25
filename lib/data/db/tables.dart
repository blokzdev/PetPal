import 'package:drift/drift.dart';

/// Pets — one row per pet the user is tracking.
class Pets extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
}

/// Entries — index of every wiki markdown file. The file on disk is the
/// source of truth; this table is a rebuildable index.
///
/// `path` is the path under the pet's wiki directory, e.g.
/// `vet/2026-01-12-checkup.md`. `bodyHash` lets us detect drift between the
/// index and the file on disk during startup reconciliation.
class Entries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get petId => integer()
      .references(Pets, #id, onDelete: KeyAction.cascade)();
  TextColumn get path => text().unique()();
  TextColumn get type => text()();
  DateTimeColumn get ts => dateTime()();
  TextColumn get title => text()();
  TextColumn get bodyHash => text()();
}

/// Embeddings — one row per (entry, chunk). `vector` is raw float32 bytes
/// readable by sqlite-vec's distance functions in Phase 1.5+.
class Embeddings extends Table {
  IntColumn get entryId => integer()
      .references(Entries, #id, onDelete: KeyAction.cascade)();
  IntColumn get chunkIdx => integer()();
  BlobColumn get vector => blob()();

  @override
  Set<Column<Object>> get primaryKey => {entryId, chunkIdx};
}

/// Sessions — one row per chat session.
class Sessions extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get petId => integer()
      .references(Pets, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get startedAt => dateTime()();
}

/// Messages — chat history within a session. `role` is one of
/// 'user' | 'assistant' | 'system' | 'tool'.
class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get sessionId => integer()
      .references(Sessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()();
  TextColumn get content => text()();
  DateTimeColumn get ts => dateTime()();
}

/// Reminders — scheduled notifications. `mode` is 'deterministic' (zero-token,
/// templated) or 'synthesis' (Pro-tier; LLM-generated content). `payload` is
/// JSON-encoded mode-specific data.
class Reminders extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get petId => integer()
      .references(Pets, #id, onDelete: KeyAction.cascade)();
  TextColumn get kind => text()();
  DateTimeColumn get whenTs => dateTime()();
  TextColumn get mode => text()();
  TextColumn get payload => text().withDefault(const Constant('{}'))();
}

/// SkillsInstalled — registry of installed skill packs.
class SkillsInstalled extends Table {
  TextColumn get skillId => text()();
  IntColumn get version => integer()();
  BoolColumn get enabled => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {skillId};
}
