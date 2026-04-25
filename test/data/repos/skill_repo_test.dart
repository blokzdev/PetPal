import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/skill_repo.dart';

void main() {
  late AppDatabase db;
  late SkillRepo repo;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SkillRepo(db: db);
  });

  tearDown(() async {
    await db.close();
  });

  test('isEnabled defaults to true for an unregistered skill', () async {
    expect(await repo.isEnabled('puppy'), isTrue);
    expect(await repo.disabledIds(), isEmpty);
  });

  test('setEnabled(false) makes the skill appear in disabledIds', () async {
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: false);
    expect(await repo.isEnabled('puppy'), isFalse);
    expect(await repo.disabledIds(), {'puppy'});
  });

  test('setEnabled(true) round-trips back to enabled', () async {
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: false);
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: true);
    expect(await repo.isEnabled('puppy'), isTrue);
    expect(await repo.disabledIds(), isEmpty);
  });

  test('multiple skills track independent state', () async {
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: false);
    await repo.setEnabled(skillId: 'new-cat', version: 1, enabled: true);
    expect(await repo.disabledIds(), {'puppy'});
    expect(await repo.isEnabled('new-cat'), isTrue);
    expect(await repo.isEnabled('senior-dog'), isTrue,
        reason: 'unregistered skill should default to enabled');
  });

  test('updating version on the same skill is allowed (insert-or-update)',
      () async {
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: true);
    await repo.setEnabled(skillId: 'puppy', version: 2, enabled: false);
    final row = await (db.select(db.skillsInstalled)
          ..where((s) => s.skillId.equals('puppy')))
        .getSingle();
    expect(row.version, 2);
    expect(row.enabled, isFalse);
  });
}
