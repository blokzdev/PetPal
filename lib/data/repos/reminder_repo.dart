import 'dart:convert';

import 'package:drift/drift.dart';

import '../../harness/scheduling/schedule_mode.dart';
import '../db/database.dart';

/// CRUD for reminders. Owns the `reminders.mode` value space — every
/// row goes through [parseScheduleMode] / [ScheduleMode.serialise] at
/// the boundary so the rest of the app deals in the typed enum.
///
/// `payload` is opaque to this layer — the dispatcher (task 4.5) is
/// the only consumer that knows the per-mode payload shape. We store
/// it as a JSON-encoded map so callers don't have to think about
/// serialisation.
class ReminderRepo {
  ReminderRepo({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// Insert a new reminder. Returns the autoincrement id.
  Future<int> create({
    required int petId,
    required String kind,
    required DateTime whenTs,
    required ScheduleMode mode,
    Map<String, Object?> payload = const {},
  }) async {
    return _db.into(_db.reminders).insert(
          RemindersCompanion.insert(
            petId: petId,
            kind: kind,
            whenTs: whenTs,
            mode: mode.serialise(),
            payload: Value(jsonEncode(payload)),
          ),
        );
  }

  /// All reminders for a pet, sorted by fire time ascending so the UI
  /// can render them in chronological order.
  Future<List<ReminderRow>> listForPet(int petId) async {
    final rows = await (_db.select(_db.reminders)
          ..where((r) => r.petId.equals(petId))
          ..orderBy([(r) => OrderingTerm.asc(r.whenTs)]))
        .get();
    return [for (final r in rows) ReminderRow.fromDrift(r)];
  }

  /// Single reminder by id, or null if missing.
  Future<ReminderRow?> getById(int id) async {
    final row = await (_db.select(_db.reminders)
          ..where((r) => r.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : ReminderRow.fromDrift(row);
  }

  Future<void> delete(int id) async {
    await (_db.delete(_db.reminders)..where((r) => r.id.equals(id))).go();
  }

  /// Update the fire time of an existing reminder. Used when the user
  /// taps a row in the reminders screen to reschedule.
  Future<void> reschedule({required int id, required DateTime whenTs}) async {
    await (_db.update(_db.reminders)..where((r) => r.id.equals(id)))
        .write(RemindersCompanion(whenTs: Value(whenTs)));
  }
}

/// Typed projection of a row in the `reminders` table — the enum
/// version of `mode` and the parsed JSON payload, so callers above
/// the repo never see raw strings.
class ReminderRow {
  const ReminderRow({
    required this.id,
    required this.petId,
    required this.kind,
    required this.whenTs,
    required this.mode,
    required this.payload,
  });

  factory ReminderRow.fromDrift(Reminder r) {
    Map<String, Object?> parsedPayload = const {};
    if (r.payload.isNotEmpty) {
      try {
        final decoded = jsonDecode(r.payload);
        if (decoded is Map<String, Object?>) {
          parsedPayload = decoded;
        }
      } catch (_) {
        // Malformed payload from a partial write — leave as empty
        // rather than failing the whole list query.
      }
    }
    return ReminderRow(
      id: r.id,
      petId: r.petId,
      kind: r.kind,
      whenTs: r.whenTs,
      mode: parseScheduleMode(r.mode),
      payload: parsedPayload,
    );
  }

  final int id;
  final int petId;
  final String kind;
  final DateTime whenTs;
  final ScheduleMode mode;
  final Map<String, Object?> payload;
}
