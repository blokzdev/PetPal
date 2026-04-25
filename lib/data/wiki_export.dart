import 'dart:io';

import 'package:archive/archive.dart';

import 'wiki_io.dart';

/// Bundle a pet's entire wiki into a `.zip` and write it to a file in
/// [outputDir]. Returns the resulting [File].
///
/// Pure-Dart — no platform plugins. The chat surface in 2.11 uses
/// share_plus to push the resulting file to Android's share sheet, but
/// the zipping itself stays testable on the host.
Future<File> exportPetWikiAsZip({
  required WikiIo wiki,
  required int petId,
  required Directory outputDir,
  String? filenamePrefix,
}) async {
  final paths = await wiki.listForPet(petId);
  final archive = Archive();
  for (final relPath in paths) {
    final body = await wiki.read(relPath);
    final bytes = body.codeUnits;
    archive.addFile(ArchiveFile.bytes(relPath, bytes));
  }

  final encoded = ZipEncoder().encodeBytes(archive);

  if (!await outputDir.exists()) {
    await outputDir.create(recursive: true);
  }
  final stamp = DateTime.now()
      .toIso8601String()
      .replaceAll(':', '')
      .replaceAll('-', '')
      .split('.')
      .first;
  final base = filenamePrefix ?? 'petpal-wiki-$petId';
  final outFile = File('${outputDir.path}/$base-$stamp.zip');
  await outFile.writeAsBytes(encoded, flush: true);
  return outFile;
}
