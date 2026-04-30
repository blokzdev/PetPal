import 'dart:typed_data';

import '../db/database.dart';
import '../soul_file.dart';
import '../photo_id.dart';
import '../wiki_io.dart';

/// CRUD for pets. Owns SOUL.md seeding on creation: every new pet gets a
/// SOUL.md skeleton at `wiki/<petId>/SOUL.md` so the agent has a place to
/// merge frontmatter via update_soul (Phase 2+).
///
/// Phase 3.4 introduces category-specific seed templates loaded from
/// `assets/onboarding/<category>.md`. The add-pet flow renders the
/// template via [OnboardingTemplates] and passes the rendered SOUL via
/// the optional [seedSoul] parameter on [createPet]. When [seedSoul] is
/// omitted, [createPet] falls back to the inline generic skeleton (kept
/// for tests that don't want to plumb a templates source).
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
    String? category,
    String? species,
    String? breed,
    DateTime? dob,
    String? seedSoul,
  }) async {
    final id = await _db.into(_db.pets).insert(
          PetsCompanion.insert(name: name, createdAt: _now()),
        );
    final body = seedSoul ??
        _genericSeedSoul(
          name: name,
          category: category,
          species: species,
          breed: breed,
          dob: dob,
        );
    await _wiki.writeAtomic(_wiki.soulPath(id), body);
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

  /// Phase 6 task 6.2 — set the pet's profile photo. The binary lands
  /// at `wiki/<petId>/profile/<id>.<ext>` and the SOUL frontmatter
  /// gets `profile_photo: <id>.<ext>`. Profile photos are dedicated
  /// files (NOT journal photo entries via WikiRepo.writePhoto) — a
  /// profile photo is identity, not memory; including it in the
  /// timeline would feel wrong.
  ///
  /// If a previous profile photo exists, its file is deleted before
  /// the new one writes. Returns the new photo's filename
  /// (`<id>.<ext>`) for callers that want to invalidate caches.
  Future<String> setProfilePhoto({
    required int petId,
    required Uint8List imageBytes,
    String mimeType = 'image/jpeg',
  }) async {
    final id = newPhotoId();
    final ext = _extForMimeType(mimeType);
    final filename = '$id.$ext';
    final binaryPath = profilePhotoPath(petId: petId, filename: filename);

    // Best-effort cleanup of any prior profile photo. Read SOUL,
    // pull the previous filename if any, delete the file. We do
    // this BEFORE writing the new file so a successful write leaves
    // the SOUL pointing at the live filename even if cleanup fails
    // (the orphan doesn't break correctness, just wastes ~600 KB).
    final priorFilename = await _readProfilePhotoFilename(petId);
    if (priorFilename != null) {
      await _wiki.deleteIfExists(
        profilePhotoPath(petId: petId, filename: priorFilename),
      );
    }

    await _wiki.writeBytesAtomic(binaryPath, imageBytes);

    // Merge `profile_photo: <filename>` into SOUL frontmatter.
    final soul = parseSoul(await _wiki.read(_wiki.soulPath(petId)));
    final patched = mergeFrontmatter(
      soul.frontmatter,
      {'profile_photo': filename},
    );
    await _wiki.writeAtomic(
      _wiki.soulPath(petId),
      serializeSoul(frontmatter: patched, body: soul.body),
    );
    return filename;
  }

  /// Phase 6 task 6.2 — clear the pet's profile photo. Strips the
  /// `profile_photo:` field from SOUL frontmatter and deletes the
  /// underlying file. Idempotent — calling on a pet without a
  /// profile photo is a no-op.
  Future<void> clearProfilePhoto({required int petId}) async {
    final filename = await _readProfilePhotoFilename(petId);
    if (filename == null) return;
    await _wiki.deleteIfExists(
      profilePhotoPath(petId: petId, filename: filename),
    );
    final soul = parseSoul(await _wiki.read(_wiki.soulPath(petId)));
    final patched = Map<String, Object?>.of(soul.frontmatter)
      ..remove('profile_photo');
    await _wiki.writeAtomic(
      _wiki.soulPath(petId),
      serializeSoul(frontmatter: patched, body: soul.body),
    );
  }

  /// Phase 6 task 6.2 — read the current profile photo bytes for the
  /// pet, or null if no profile photo is set / SOUL is missing /
  /// the binary file is missing. Used by the home greeting backdrop
  /// + chat AppBar avatar render paths.
  Future<Uint8List?> readProfilePhotoBytes({required int petId}) async {
    final filename = await _readProfilePhotoFilename(petId);
    if (filename == null) return null;
    try {
      return await _wiki.readBytes(
        profilePhotoPath(petId: petId, filename: filename),
      );
    } catch (_) {
      // Stale SOUL pointer with missing file — render falls back to
      // the no-photo path; a future setProfilePhoto / clear call
      // re-syncs.
      return null;
    }
  }

  Future<String?> _readProfilePhotoFilename(int petId) async {
    final String soulRaw;
    try {
      soulRaw = await _wiki.read(_wiki.soulPath(petId));
    } catch (_) {
      return null;
    }
    final fm = parseSoul(soulRaw).frontmatter;
    final v = fm['profile_photo'];
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }
}

/// Wiki-relative path to a profile photo binary. Distinct directory
/// from `wiki/<petId>/photos/` (which carries journal photo entries
/// via WikiRepo.writePhoto) — profile photos are identity, not memory,
/// and don't get sidecars / FTS5 indexing.
String profilePhotoPath({required int petId, required String filename}) =>
    'wiki/$petId/profile/$filename';

String _extForMimeType(String mime) {
  switch (mime.toLowerCase()) {
    case 'image/jpeg':
    case 'image/jpg':
      return 'jpg';
    case 'image/png':
      return 'png';
    case 'image/webp':
      return 'webp';
    case 'image/heic':
    case 'image/heif':
      return 'heic';
    default:
      return 'jpg';
  }
}

String _genericSeedSoul({
  required String name,
  String? category,
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
category: ${category ?? ''}
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
