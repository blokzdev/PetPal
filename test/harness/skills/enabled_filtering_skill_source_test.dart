import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/skill_repo.dart';
import 'package:petpal/harness/skills/enabled_filtering_skill_source.dart';
import 'package:petpal/harness/skills/skill_manifest.dart';
import 'package:petpal/harness/skills/skill_source.dart';

class _FixedSource implements SkillSource {
  _FixedSource(this._entries);
  final List<SkillSourceEntry> _entries;

  @override
  Future<List<SkillSourceEntry>> list() async => _entries;
}

SkillSourceEntry _entry(String id) => SkillSourceEntry(
      manifest: SkillManifest(
        id: id,
        name: id,
        version: 1,
        species: const [],
        triggers: const ['x'],
        loads: const [],
        requiresPro: false,
      ),
      readFragment: (_) async => '',
    );

void main() {
  late AppDatabase db;
  late SkillRepo repo;
  late SkillSource inner;
  late EnabledFilteringSkillSource source;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repo = SkillRepo(db: db);
    inner = _FixedSource([
      _entry('puppy'),
      _entry('senior-dog'),
      _entry('new-cat'),
    ]);
    source = EnabledFilteringSkillSource(inner: inner, repo: repo);
  });

  tearDown(() async {
    await db.close();
  });

  test('passes through every skill when none are explicitly disabled',
      () async {
    final out = await source.list();
    expect(out.map((e) => e.manifest.id), ['puppy', 'senior-dog', 'new-cat']);
  });

  test('filters out skills the repo marks disabled', () async {
    await repo.setEnabled(skillId: 'senior-dog', version: 1, enabled: false);
    final out = await source.list();
    expect(out.map((e) => e.manifest.id), ['puppy', 'new-cat']);
  });

  test('toggling back to enabled restores the skill', () async {
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: false);
    expect(
      (await source.list()).map((e) => e.manifest.id),
      isNot(contains('puppy')),
    );
    await repo.setEnabled(skillId: 'puppy', version: 1, enabled: true);
    expect(
      (await source.list()).map((e) => e.manifest.id),
      contains('puppy'),
    );
  });
}
