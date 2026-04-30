import 'dart:typed_data';

/// File I/O surface for the per-pet wiki. The concrete implementation lands
/// in task 1.3 (atomic write under the path_provider doc dir, reads,
/// listings, slug rules). This file declares the contract so [PetRepo] and
/// other harness components can depend on the interface in task 1.2.
abstract class WikiIo {
  /// Write [body] to [relPath] atomically (write-temp + rename), creating
  /// any parent directories as needed. [relPath] is relative to the wiki
  /// root, e.g. `wiki/1/SOUL.md`.
  Future<void> writeAtomic(String relPath, String body);

  /// Read the markdown body at [relPath]. Throws if missing.
  Future<String> read(String relPath);

  /// List relative paths of every entry under the pet's wiki dir, recursively.
  Future<List<String>> listForPet(int petId);

  /// Wiki-root-relative directory for a pet: `wiki/<petId>`.
  String petDir(int petId) => 'wiki/$petId';

  /// Wiki-root-relative path to a pet's SOUL.md.
  String soulPath(int petId) => '${petDir(petId)}/SOUL.md';

  /// Phase 6 (task 6.1) photo storage. Write [bytes] to [relPath]
  /// atomically (write-temp + rename), creating any parent directories
  /// as needed. Use for photo `.jpg` binaries that sit next to their
  /// sidecar `.md` entries.
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes);

  /// Read the binary bytes at [relPath]. Throws if missing.
  Future<Uint8List> readBytes(String relPath);

  /// Delete [relPath] if it exists. Used by the photo write path's
  /// cleanup branch — when the sidecar `.md` write fails after the
  /// `.jpg` has landed, the orphaned binary is removed so storage
  /// accounting stays honest. Idempotent: missing files are silent.
  Future<void> deleteIfExists(String relPath);

  /// Total bytes occupied by all files under the pet's wiki dir.
  /// Drives storage budget tracking (Phase 6 task 6.1: warn at 500 MB,
  /// hard limit 1 GB v1). Returns 0 if the dir doesn't exist.
  Future<int> bytesForPet(int petId);
}
