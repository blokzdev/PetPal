import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/db/database.dart';
import 'package:petpal/data/repos/pet_repo.dart';
import 'package:petpal/data/wiki_io.dart';
import 'package:petpal/data/wiki_io_fs.dart';

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

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) =>
      throw UnimplementedError('photo write not used in pet_repo tests');
  @override
  Future<Uint8List> readBytes(String relPath) =>
      throw UnimplementedError('photo read not used in pet_repo tests');
  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;
  @override
  Future<void> deleteAll() async {}
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

  group('Phase 6 task 6.2 — profile photo', () {
    // Real WikiIoFs against a tempdir — the binary IO methods need a
    // real filesystem; the in-memory _FakeWikiIo above only handles
    // text writes.
    late Directory tempRoot;
    late WikiIoFs fsWiki;
    late PetRepo fsRepo;
    late int petId;

    setUp(() async {
      tempRoot = Directory.systemTemp.createTempSync('petpal_profile_photo_');
      fsWiki = WikiIoFs(tempRoot);
      fsRepo = PetRepo(db: db, wiki: fsWiki, now: () => fixedNow);
      petId = await fsRepo.createPet(name: 'Loki');
    });

    tearDown(() async {
      if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
    });

    Uint8List bytes([int n = 1024, int fill = 0xff]) =>
        Uint8List.fromList(List<int>.filled(n, fill));

    test('setProfilePhoto writes the binary at wiki/<id>/profile/<id>.jpg '
        'and merges profile_photo: into SOUL frontmatter', () async {
      final filename = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(2048),
      );

      // Filename ends in .jpg (default mimeType is image/jpeg) and
      // looks like <uuid>.jpg.
      expect(filename, endsWith('.jpg'));
      expect(filename.length, greaterThan(36));

      // Binary landed.
      final binary = File(
        '${tempRoot.path}/wiki/$petId/profile/$filename',
      );
      expect(binary.existsSync(), isTrue);
      expect(binary.lengthSync(), 2048);

      // SOUL.md frontmatter has the pointer.
      final soul = File('${tempRoot.path}/wiki/$petId/SOUL.md').readAsStringSync();
      expect(soul, contains('profile_photo: $filename'));
    });

    test('readProfilePhotoBytes round-trips the bytes', () async {
      await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(512),
      );
      final read = await fsRepo.readProfilePhotoBytes(petId: petId);
      expect(read, isNotNull);
      expect(read!.length, 512);
    });

    test('returns null when no profile photo set', () async {
      final read = await fsRepo.readProfilePhotoBytes(petId: petId);
      expect(read, isNull);
    });

    test('returns null when SOUL points at a missing file (stale '
        'pointer — a future set/clear re-syncs)', () async {
      // Hand-stamp a SOUL with a profile_photo: pointer to a file
      // that doesn't exist on disk.
      await fsWiki.writeAtomic(
        'wiki/$petId/SOUL.md',
        '---\nprofile_photo: ghost.jpg\n---\n',
      );
      final read = await fsRepo.readProfilePhotoBytes(petId: petId);
      expect(read, isNull);
    });

    test('setProfilePhoto a second time deletes the prior binary AND '
        'updates SOUL to point at the new one (no orphaned files)',
        () async {
      final first = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(1000, 0xaa),
      );
      final second = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(2000, 0xbb),
      );
      expect(first, isNot(second));
      expect(
        File('${tempRoot.path}/wiki/$petId/profile/$first').existsSync(),
        isFalse,
        reason: 'prior binary cleaned up before the new write',
      );
      expect(
        File('${tempRoot.path}/wiki/$petId/profile/$second').existsSync(),
        isTrue,
      );
      final soul = File('${tempRoot.path}/wiki/$petId/SOUL.md').readAsStringSync();
      expect(soul, contains('profile_photo: $second'));
      expect(soul, isNot(contains(first)));
    });

    test('clearProfilePhoto deletes the file AND strips the field from '
        'SOUL frontmatter', () async {
      final filename = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(),
      );
      await fsRepo.clearProfilePhoto(petId: petId);

      expect(
        File('${tempRoot.path}/wiki/$petId/profile/$filename').existsSync(),
        isFalse,
      );
      final soul = File('${tempRoot.path}/wiki/$petId/SOUL.md').readAsStringSync();
      expect(soul, isNot(contains('profile_photo')));
    });

    test('clearProfilePhoto on a pet with no profile photo is a no-op',
        () async {
      // Should not throw.
      await fsRepo.clearProfilePhoto(petId: petId);
      final soul = File('${tempRoot.path}/wiki/$petId/SOUL.md').readAsStringSync();
      expect(soul, isNot(contains('profile_photo')));
    });

    test('mime-type → extension mapping: png maps to .png; unknown '
        'falls back to .jpg', () async {
      final png = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(),
        mimeType: 'image/png',
      );
      expect(png, endsWith('.png'));

      // Reset by clearing, then set again with an unknown type.
      await fsRepo.clearProfilePhoto(petId: petId);
      final fallback = await fsRepo.setProfilePhoto(
        petId: petId,
        imageBytes: bytes(),
        mimeType: 'image/something-weird',
      );
      expect(fallback, endsWith('.jpg'));
    });

    test('profilePhotoPath produces the canonical '
        'wiki/<petId>/profile/<filename> shape (NOT under photos/)', () {
      expect(
        profilePhotoPath(petId: 7, filename: 'abc.jpg'),
        'wiki/7/profile/abc.jpg',
      );
    });
  });
}
