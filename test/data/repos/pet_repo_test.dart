import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/pet_repo.dart';
import 'package:petpal/data/wiki_io.dart';

class _FakeWikiIo extends WikiIo {
  final Map<String, String> writes = {};

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    writes[relPath] = body;
  }

  @override
  Future<String> read(String relPath) async {
    final body = writes[relPath];
    if (body == null) {
      throw StateError('not written: $relPath');
    }
    return body;
  }

  @override
  Future<List<String>> listForPet(int petId) async {
    final prefix = '${petDir(petId)}/';
    return writes.keys.where((k) => k.startsWith(prefix)).toList();
  }
}

void main() {
  late AppDatabase db;
  late _FakeWikiIo wiki;
  late PetRepo repo;
  // Local DateTime — Drift stores DateTime as Unix seconds and reads back
  // as local, so using a UTC fixture would fail on round-trip equality.
  final fixedNow = DateTime(2026, 4, 25, 12);

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    wiki = _FakeWikiIo();
    repo = PetRepo(db: db, wiki: wiki, now: () => fixedNow);
  });

  tearDown(() async {
    await db.close();
  });

  test('createPet inserts row and seeds SOUL.md at wiki/<id>/SOUL.md',
      () async {
    final id = await repo.createPet(
      name: 'Milo',
      category: 'dog',
      breed: 'mixed',
      dob: DateTime.utc(2022, 6, 12),
    );

    final row = await repo.getPet(id);
    expect(row, isNotNull);
    expect(row!.name, 'Milo');
    expect(row.createdAt, fixedNow);

    final soul = wiki.writes['wiki/$id/SOUL.md'];
    expect(soul, isNotNull);
    expect(soul, contains('# Milo'));
    expect(soul, contains('category: dog'));
    expect(soul, contains('breed: mixed'));
    expect(soul, contains('dob: 2022-06-12'));
  });

  test('createPet with only a name still seeds a valid SOUL.md skeleton',
      () async {
    final id = await repo.createPet(name: 'Luna');
    final soul = wiki.writes['wiki/$id/SOUL.md']!;

    expect(soul, contains('# Luna'));
    expect(soul, contains('category: \n'));
    expect(soul, contains('breed: \n'));
    expect(soul, contains('dob: \n'));
    expect(soul, contains('allergies: []'));
    expect(soul, contains('meds: []'));
    expect(soul, contains('temperament: []'));
  });

  test('two pets get distinct SOUL.md paths keyed by pet id', () async {
    final a = await repo.createPet(name: 'Milo');
    final b = await repo.createPet(name: 'Luna');

    expect(a, isNot(b));
    expect(wiki.writes.keys, containsAll(<String>{
      'wiki/$a/SOUL.md',
      'wiki/$b/SOUL.md',
    }));
  });

  test('listPets returns all created pets', () async {
    await repo.createPet(name: 'Milo');
    await repo.createPet(name: 'Luna');
    final pets = await repo.listPets();
    expect(pets.map((p) => p.name).toList(), ['Milo', 'Luna']);
  });

  test('getPet returns null for unknown id', () async {
    expect(await repo.getPet(999), isNull);
  });

  test('deletePet removes the pet row (files on disk preserved)', () async {
    final id = await repo.createPet(name: 'Milo');
    expect(await repo.getPet(id), isNotNull);

    await repo.deletePet(id);
    expect(await repo.getPet(id), isNull);
    // Deliberate: the SOUL.md write the fake captured stays around. File
    // cleanup is owned by WikiIo (1.3+), not PetRepo.
    expect(wiki.writes.containsKey('wiki/$id/SOUL.md'), isTrue);
  });
}
