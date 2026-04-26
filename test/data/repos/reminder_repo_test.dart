import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/reminder_repo.dart';
import 'package:petpal/harness/scheduling/schedule_mode.dart';

void main() {
  late AppDatabase db;
  late ReminderRepo repo;
  late int petId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repo = ReminderRepo(db: db);
    petId = await db.into(db.pets).insert(
          PetsCompanion.insert(name: 'Loki', createdAt: DateTime(2026, 4, 26)),
        );
  });

  tearDown(() async => db.close());

  test('create + getById round-trips every column with payload JSON', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'flea_treatment',
      whenTs: DateTime(2026, 5, 26, 9),
      mode: ScheduleMode.notification,
      payload: {'templateId': 'flea', 'vars': {'pet_name': 'Loki'}},
    );

    final row = await repo.getById(id);
    expect(row, isNotNull);
    expect(row!.petId, petId);
    expect(row.kind, 'flea_treatment');
    expect(row.whenTs, DateTime(2026, 5, 26, 9));
    expect(row.mode, ScheduleMode.notification);
    expect(row.payload['templateId'], 'flea');
    expect(row.payload['vars'], {'pet_name': 'Loki'});
  });

  test('create defaults payload to empty map when omitted', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'weekly_summary',
      whenTs: DateTime(2026, 5, 3, 9),
      mode: ScheduleMode.synthesis,
    );
    final row = await repo.getById(id);
    expect(row!.payload, isEmpty);
    expect(row.mode, ScheduleMode.synthesis);
  });

  test('listForPet returns rows in chronological order', () async {
    await repo.create(
      petId: petId,
      kind: 'a',
      whenTs: DateTime(2026, 6, 2),
      mode: ScheduleMode.notification,
    );
    await repo.create(
      petId: petId,
      kind: 'b',
      whenTs: DateTime(2026, 5, 2),
      mode: ScheduleMode.notification,
    );
    await repo.create(
      petId: petId,
      kind: 'c',
      whenTs: DateTime(2026, 7, 2),
      mode: ScheduleMode.notification,
    );

    final rows = await repo.listForPet(petId);
    expect(rows.map((r) => r.kind).toList(), ['b', 'a', 'c']);
  });

  test('listForPet scopes by petId — other pets do not leak in', () async {
    final otherPetId = await db.into(db.pets).insert(
          PetsCompanion.insert(name: 'Mochi', createdAt: DateTime(2026, 4, 26)),
        );

    await repo.create(
      petId: petId,
      kind: 'mine',
      whenTs: DateTime(2026, 5, 2),
      mode: ScheduleMode.notification,
    );
    await repo.create(
      petId: otherPetId,
      kind: 'theirs',
      whenTs: DateTime(2026, 5, 2),
      mode: ScheduleMode.notification,
    );

    final mine = await repo.listForPet(petId);
    expect(mine, hasLength(1));
    expect(mine.single.kind, 'mine');
  });

  test('reschedule moves whenTs without touching anything else', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'vaccine_due',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.notification,
      payload: {'note': 'rabies'},
    );
    await repo.reschedule(id: id, whenTs: DateTime(2026, 6, 26));
    final row = await repo.getById(id);
    expect(row!.whenTs, DateTime(2026, 6, 26));
    expect(row.kind, 'vaccine_due');
    expect(row.payload['note'], 'rabies');
  });

  test('delete removes the row', () async {
    final id = await repo.create(
      petId: petId,
      kind: 'flea_treatment',
      whenTs: DateTime(2026, 5, 26),
      mode: ScheduleMode.notification,
    );
    expect(await repo.getById(id), isNotNull);
    await repo.delete(id);
    expect(await repo.getById(id), isNull);
  });

  test('all four modes round-trip through the database', () async {
    for (final mode in ScheduleMode.values) {
      final id = await repo.create(
        petId: petId,
        kind: mode.name,
        whenTs: DateTime(2026, 5, 26),
        mode: mode,
      );
      final row = await repo.getById(id);
      expect(row!.mode, mode, reason: mode.name);
    }
  });

  test(
      'malformed payload does not crash listForPet — defensive against '
      'partial writes', () async {
    // Bypass the repo to insert a row with garbage JSON in `payload`.
    await db.into(db.reminders).insert(
          RemindersCompanion.insert(
            petId: petId,
            kind: 'corrupted',
            whenTs: DateTime(2026, 5, 26),
            mode: 'notification',
            payload: const Value('{not valid json'),
          ),
        );
    final rows = await repo.listForPet(petId);
    expect(rows, hasLength(1));
    expect(rows.single.payload, isEmpty);
  });
}
