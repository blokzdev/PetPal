import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'wiki_io.dart';

/// Filesystem-backed [WikiIo]. Writes are atomic via write-temp + rename.
/// Reads and listings are direct.
///
/// In tests, construct with a temp [Directory]. In production, call
/// [WikiIoFs.openDefault] to anchor at the app's documents directory.
class WikiIoFs extends WikiIo {
  WikiIoFs(this.root);

  final Directory root;

  /// Production factory: anchors the wiki under
  /// `<app-documents>/petpal/`. Creates the root if missing.
  static Future<WikiIoFs> openDefault() async {
    final docs = await getApplicationDocumentsDirectory();
    final root = Directory('${docs.path}/petpal');
    if (!await root.exists()) {
      await root.create(recursive: true);
    }
    return WikiIoFs(root);
  }

  String _abs(String relPath) => '${root.path}/$relPath';

  @override
  Future<void> writeAtomic(String relPath, String body) async {
    final file = File(_abs(relPath));
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(body, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<String> read(String relPath) => File(_abs(relPath)).readAsString();

  @override
  Future<List<String>> listForPet(int petId) async {
    final dir = Directory(_abs(petDir(petId)));
    if (!await dir.exists()) return const [];
    final rootPrefix = '${root.path}/';
    final files = <String>[];
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        var p = entity.path;
        if (p.startsWith(rootPrefix)) p = p.substring(rootPrefix.length);
        files.add(p);
      }
    }
    files.sort();
    return files;
  }

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) async {
    final file = File(_abs(relPath));
    await file.parent.create(recursive: true);
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(file.path);
  }

  @override
  Future<Uint8List> readBytes(String relPath) =>
      File(_abs(relPath)).readAsBytes();

  @override
  Future<void> deleteIfExists(String relPath) async {
    final file = File(_abs(relPath));
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<int> bytesForPet(int petId) async {
    final dir = Directory(_abs(petDir(petId)));
    if (!await dir.exists()) return 0;
    var total = 0;
    await for (final entity in dir.list(recursive: true)) {
      if (entity is File) {
        total += await entity.length();
      }
    }
    return total;
  }

  @override
  Future<void> deleteAll() async {
    if (await root.exists()) {
      await root.delete(recursive: true);
    }
    // Recreate the empty root so subsequent writes via writeAtomic
    // don't have to re-create the directory tree from scratch + so
    // the WikiIoFs invariant ("root exists") holds post-wipe.
    await root.create(recursive: true);
  }
}
