import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/data/wiki_export.dart';
import 'package:petpal/data/wiki_io_fs.dart';

void main() {
  late Directory tempRoot;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('petpal_export_test_');
  });

  tearDown(() {
    if (tempRoot.existsSync()) tempRoot.deleteSync(recursive: true);
  });

  test('zips every entry under wiki/<petId>/ into the output zip with '
      'wiki-relative paths preserved', () async {
    final wiki = WikiIoFs(tempRoot);
    await wiki.writeAtomic('wiki/1/SOUL.md', '---\n---\n# Milo\n');
    await wiki.writeAtomic(
      'wiki/1/food/2026-04-25-carrot-trial.md',
      'Milo loves carrots.',
    );
    await wiki.writeAtomic(
      'wiki/1/vet/2026-04-26-checkup.md',
      'Vitals normal.',
    );
    // A second pet's entry must NOT leak into pet 1's export.
    await wiki.writeAtomic('wiki/2/SOUL.md', 'other pet');

    final outDir = Directory('${tempRoot.path}/out');
    final zipFile = await exportPetWikiAsZip(
      wiki: wiki,
      petId: 1,
      outputDir: outDir,
    );
    expect(zipFile.existsSync(), isTrue);
    expect(zipFile.path, endsWith('.zip'));
    expect(zipFile.path, contains('petpal-wiki-1-'));

    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    final names = archive.files.map((f) => f.name).toSet();
    expect(names, {
      'wiki/1/SOUL.md',
      'wiki/1/food/2026-04-25-carrot-trial.md',
      'wiki/1/vet/2026-04-26-checkup.md',
    });
    expect(names, isNot(contains('wiki/2/SOUL.md')));

    final carrot = archive.files.singleWhere(
      (f) => f.name == 'wiki/1/food/2026-04-25-carrot-trial.md',
    );
    expect(utf8.decode(carrot.content as List<int>),
        'Milo loves carrots.');
  });

  test('exports cleanly when the pet has no entries (empty zip)', () async {
    final wiki = WikiIoFs(tempRoot);
    final outDir = Directory('${tempRoot.path}/out');
    final zipFile = await exportPetWikiAsZip(
      wiki: wiki,
      petId: 99,
      outputDir: outDir,
    );
    expect(zipFile.existsSync(), isTrue);
    final archive = ZipDecoder().decodeBytes(await zipFile.readAsBytes());
    expect(archive.files, isEmpty);
  });
}
