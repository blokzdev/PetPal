import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/wiki_io_fs.dart';

void main() {
  late Directory tempRoot;
  late WikiIoFs io;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('petpal_wiki_test_');
    io = WikiIoFs(tempRoot);
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('writeAtomic creates parent dirs and writes the body', () async {
    await io.writeAtomic('wiki/1/SOUL.md', '# Milo\n');
    final file = File('${tempRoot.path}/wiki/1/SOUL.md');
    expect(await file.readAsString(), '# Milo\n');
  });

  test('writeAtomic leaves no .tmp file behind on success', () async {
    await io.writeAtomic('wiki/1/SOUL.md', '# Milo\n');
    final tmp = File('${tempRoot.path}/wiki/1/SOUL.md.tmp');
    expect(tmp.existsSync(), isFalse);
  });

  test('writeAtomic overwrites an existing file', () async {
    await io.writeAtomic('wiki/1/SOUL.md', 'first');
    await io.writeAtomic('wiki/1/SOUL.md', 'second');
    expect(await io.read('wiki/1/SOUL.md'), 'second');
  });

  test('read throws on a missing path', () async {
    await expectLater(
      io.read('does/not/exist.md'),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('listForPet returns relative paths under the pet dir', () async {
    await io.writeAtomic('wiki/1/SOUL.md', 'soul');
    await io.writeAtomic('wiki/1/vet/2026-01-12-checkup.md', 'visit');
    await io.writeAtomic('wiki/1/weight/log.md', 'log');
    // A different pet's file must not leak into the listing.
    await io.writeAtomic('wiki/2/SOUL.md', 'other');

    final paths = await io.listForPet(1);
    expect(paths, [
      'wiki/1/SOUL.md',
      'wiki/1/vet/2026-01-12-checkup.md',
      'wiki/1/weight/log.md',
    ]);
  });

  test('listForPet returns empty for a pet with no files yet', () async {
    expect(await io.listForPet(42), isEmpty);
  });

  test('soulPath and petDir match the documented layout', () {
    expect(io.petDir(7), 'wiki/7');
    expect(io.soulPath(7), 'wiki/7/SOUL.md');
  });

  // Phase 7 task H.1.d.wipe — deleteAll nukes the entire wiki root.
  group('deleteAll', () {
    test('removes every file across multiple pets', () async {
      await io.writeAtomic('wiki/1/SOUL.md', 'a');
      await io.writeAtomic('wiki/1/vet/2026-04-12.md', 'b');
      await io.writeAtomic('wiki/2/SOUL.md', 'c');

      await io.deleteAll();

      expect(await io.listForPet(1), isEmpty);
      expect(await io.listForPet(2), isEmpty);
    });

    test('idempotent — re-invoking on empty root is a no-op', () async {
      await io.deleteAll();
      await io.deleteAll(); // no throw
      expect(tempRoot.existsSync(), isTrue);
    });

    test('recreates the empty root so subsequent writes work', () async {
      await io.writeAtomic('wiki/1/SOUL.md', 'a');
      await io.deleteAll();

      // Post-wipe, the root must exist and writes must succeed.
      expect(tempRoot.existsSync(), isTrue);
      await io.writeAtomic('wiki/1/SOUL.md', 'fresh');
      expect(await io.read('wiki/1/SOUL.md'), 'fresh');
    });
  });
}
