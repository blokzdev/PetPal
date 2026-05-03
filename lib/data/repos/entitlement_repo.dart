import 'dart:convert';

import 'package:drift/drift.dart';

import '../../app/entitlement/entitlement.dart';
import '../db/database.dart';

/// Phase 7 task B.1 — local cache I/O for the entitlements table.
///
/// Reads the cached server state for the active user; writes
/// (upserts) on reconciliation passes (post-IAP, post-webhook,
/// app-foreground refresh per DECISIONS row 78).
///
/// **Never call this from the agent loop's quota gate directly** — go
/// through the Riverpod `entitlementProvider`, which caches the
/// `AsyncValue` and avoids repeat DB reads on every chat turn.
class EntitlementRepo {
  EntitlementRepo({required AppDatabase db}) : _db = db;

  final AppDatabase _db;

  /// Read the cached entitlement for [userId]. Returns null when no
  /// row exists (caller surfaces [Entitlement.freeAnonymous] as the
  /// default).
  Future<Entitlement?> read(String userId) async {
    final row = await (_db.select(_db.entitlements)
          ..where((e) => e.userId.equals(userId)))
        .getSingleOrNull();
    if (row == null) return null;
    return _decode(row);
  }

  /// Insert-or-update the cache row for `ent.userId`. No-op when
  /// `ent.state == EntitlementState.freeAnonymous` or `ent.userId`
  /// is null (anonymous users have no row by design — the synthetic
  /// default covers them).
  Future<void> upsert(Entitlement ent) async {
    if (ent.state == EntitlementState.freeAnonymous || ent.userId == null) {
      return;
    }
    await _db.into(_db.entitlements).insertOnConflictUpdate(
          EntitlementsCompanion(
            userId: Value(ent.userId!),
            state: Value(ent.state.wireValue),
            renewalDate: Value(ent.renewalDate),
            graceUntil: Value(ent.graceUntil),
            photoCreditsBalance: Value(ent.photoCreditsBalance),
            monthlyTextCount: Value(ent.monthlyTextCount),
            monthlyVisionCount: Value(ent.monthlyVisionCount),
            counterPeriodStart: Value(ent.counterPeriodStart),
            fetchedAt: Value(ent.fetchedAt ?? DateTime.now()),
            ownedCarePackSkillIdsJson: Value(
              jsonEncode(ent.ownedCarePackSkillIds.toList()),
            ),
          ),
        );
  }

  /// Delete the cache row for [userId]. Called on sign-out + on
  /// account deletion (per DECISIONS row 77 immediate-purge step).
  Future<void> clear(String userId) async {
    await (_db.delete(_db.entitlements)
          ..where((e) => e.userId.equals(userId)))
        .go();
  }

  Entitlement _decode(EntitlementRow row) => Entitlement(
        state: EntitlementState.fromWire(row.state),
        userId: row.userId,
        renewalDate: row.renewalDate,
        graceUntil: row.graceUntil,
        photoCreditsBalance: row.photoCreditsBalance,
        monthlyTextCount: row.monthlyTextCount,
        monthlyVisionCount: row.monthlyVisionCount,
        counterPeriodStart: row.counterPeriodStart,
        fetchedAt: row.fetchedAt,
        ownedCarePackSkillIds: _decodeSkillIds(row.ownedCarePackSkillIdsJson),
      );

  Set<String> _decodeSkillIds(String json) {
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded.whereType<String>().toSet();
      }
    } catch (_) {
      // Malformed JSON — defensive fallback to empty set; the
      // reconciliation pass overwrites with the canonical value.
    }
    return const <String>{};
  }
}
