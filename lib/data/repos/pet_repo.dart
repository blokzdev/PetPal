import '../db/database.dart';
import '../wiki_io.dart';

/// CRUD for pets. Owns SOUL.md seeding on creation: every new pet gets a
/// SOUL.md skeleton at `wiki/<petId>/SOUL.md` so the agent has a place to
/// merge frontmatter via update_soul (Phase 2+).
class PetRepo {
  PetRepo({
    required AppDatabase db,
    required WikiIo wiki,
    DateTime Function()? now,
  })  : _db = db,
        _wiki = wiki,
        _now = now ?? DateTime.now;

  final AppDatabase _db;
  final WikiIo _wiki;
  final DateTime Function() _now;

  Future<int> createPet({
    required String name,
    String? species,
    String? breed,
    DateTime? dob,
  }) async {
    final id = await _db.into(_db.pets).insert(
          PetsCompanion.insert(name: name, createdAt: _now()),
        );
    await _wiki.writeAtomic(
      _wiki.soulPath(id),
      _seedSoul(name: name, species: species, breed: breed, dob: dob),
    );
    return id;
  }

  Future<List<Pet>> listPets() => _db.select(_db.pets).get();

  Future<Pet?> getPet(int id) =>
      (_db.select(_db.pets)..where((p) => p.id.equals(id))).getSingleOrNull();

  /// Removes the pet row. FK cascades wipe entries/embeddings/sessions/etc.
  /// Files on disk are *not* removed — that is a deliberate separate
  /// operation owned by [WikiIo] in 1.3+ so an accidental delete is
  /// recoverable from disk.
  Future<void> deletePet(int id) async {
    await (_db.delete(_db.pets)..where((p) => p.id.equals(id))).go();
  }
}

String _seedSoul({
  required String name,
  String? species,
  String? breed,
  DateTime? dob,
}) {
  final dobStr = dob == null
      ? ''
      : '${dob.year.toString().padLeft(4, '0')}-'
          '${dob.month.toString().padLeft(2, '0')}-'
          '${dob.day.toString().padLeft(2, '0')}';
  return '''---
species: ${species ?? ''}
breed: ${breed ?? ''}
dob: $dobStr
weight_kg:
allergies: []
meds: []
vet_contact: ''
temperament: []
---

# $name
''';
}
