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

/// Reminders — scheduled tasks. `mode` is one of `notification` |
/// `script` | `synthesis` | `synthesisNotify` per CLAUDE.md §8 / DECISIONS
/// row 28's four-mode taxonomy. `payload` is JSON-encoded mode-specific
/// data (e.g. `{"templateId":"flea","vars":{"pet_name":"Loki"}}` for a
/// notification reminder).
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

/// Phase 7 task B.1 — local cache of the active user's entitlement.
///
/// **The Supabase `entitlements` table is the canonical source of truth**
/// (DECISIONS row 78 + 82); this table mirrors a subset of those columns
/// for offline reads and as the data source for the Riverpod
/// `entitlementProvider`. Reconciliation flow:
///
///   - On app foreground / chat-screen mount / post-IAP-purchase: fetch
///     the latest entitlement from Supabase and `upsert` here.
///   - The agent loop's quota gate reads this table — never the network
///     — so a chat turn never blocks on a network round-trip.
///
/// `userId` matches the Supabase auth user ID. When the user is signed
/// out (anonymous free path), this table has no row for them; the
/// provider returns a synthetic [Entitlement.freeAnonymous] default.
///
/// `@DataClassName('EntitlementRow')` keeps Drift's generated row
/// class out of the way of the domain `Entitlement` class in
/// `lib/app/entitlement/entitlement.dart`.
@DataClassName('EntitlementRow')
class Entitlements extends Table {
  /// Supabase auth.users.id (UUID v4 as a text string).
  TextColumn get userId => text()();

  /// One of {'free', 'pro_monthly', 'pro_annual', 'byok'} per
  /// DECISIONS row 36. Stored as text to match the Supabase enum-style
  /// `text + check constraint` column without a Drift codegen step.
  TextColumn get state => text().withDefault(const Constant('free'))();

  /// Subscription anniversary; null for free + byok rows.
  DateTimeColumn get renewalDate => dateTime().nullable()();

  /// Grace window after a billing failure (Play sometimes retries before
  /// the entitlement actually expires). Null when no grace is active.
  DateTimeColumn get graceUntil => dateTime().nullable()();

  /// Vision credit pack balance; rolls over indefinitely per row 36.
  IntColumn get photoCreditsBalance =>
      integer().withDefault(const Constant(0))();

  /// Server-side counters mirrored locally for the UI (Settings shows
  /// "127 / 200 used this month" per VOICE.md §6 example 11). The
  /// quota gate uses the SERVER counter, not these — these are purely
  /// for display.
  IntColumn get monthlyTextCount =>
      integer().withDefault(const Constant(0))();
  IntColumn get monthlyVisionCount =>
      integer().withDefault(const Constant(0))();
  DateTimeColumn get counterPeriodStart => dateTime()();

  /// When this cache row was last refreshed from Supabase. Used to
  /// surface stale-cache warnings and to drive the reconciliation
  /// schedule (refresh if older than 24 h on next app foreground).
  DateTimeColumn get fetchedAt => dateTime()();

  @override
  Set<Column<Object>> get primaryKey => {userId};
}
