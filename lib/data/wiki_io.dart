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
}
