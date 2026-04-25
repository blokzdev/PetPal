import 'package:drift/drift.dart' show Value;

import '../db/database.dart';

/// CRUD over the `skills_installed` table. Phase 3.6 uses this for
/// enabled-state persistence; explicit "install"/"uninstall" lands
/// later when the user can sideload their own skill packs.
///
/// Default state for an unregistered skill is **enabled** — every
/// bundled skill is on by default; toggling off writes a row with
/// `enabled = false`. Re-enabling overwrites the same row.
class SkillRepo {
  SkillRepo({required AppDatabase db}) : _db = db;
  final AppDatabase _db;

  /// Set of skill ids the user has explicitly disabled. Anything not in
  /// this set is treated as enabled.
  Future<Set<String>> disabledIds() async {
    final rows = await (_db.select(_db.skillsInstalled)
          ..where((s) => s.enabled.equals(false)))
        .get();
    return rows.map((r) => r.skillId).toSet();
  }

  Future<bool> isEnabled(String skillId) async {
    final row = await (_db.select(_db.skillsInstalled)
          ..where((s) => s.skillId.equals(skillId)))
        .getSingleOrNull();
    if (row == null) return true;
    return row.enabled;
  }

  Future<void> setEnabled({
    required String skillId,
    required int version,
    required bool enabled,
  }) async {
    await _db.into(_db.skillsInstalled).insertOnConflictUpdate(
          SkillsInstalledCompanion.insert(
            skillId: skillId,
            version: version,
            enabled: Value(enabled),
          ),
        );
  }
}
