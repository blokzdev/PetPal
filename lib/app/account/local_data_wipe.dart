import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/db/connection.dart';
import '../../data/wiki_io.dart';

/// Phase 7 task H.1.d.wipe — local data wipe service.
///
/// Per DECISIONS row 77 ("Local SQLite + wiki files are wiped at
/// delete-tap.") + row 90 (this row's H.1.d.wipe close).
///
/// Sequencing — strictly ordered so each step has a clean precondition:
///   1. **Wiki files** — call [WikiIo.deleteAll] to nuke
///      `<app-docs>/petpal/`. Idempotent.
///   2. **Drift database** — invalidate the database provider so
///      Riverpod's `onDispose` closes the active connection, then
///      delete the SQLite file at `<app-docs>/petpal.sqlite` (+
///      `-wal` / `-shm` / `-journal` sidecars). The next provider
///      read re-opens an empty file via `MigrationStrategy.onCreate`.
///   3. **Cached state** — invalidate the wiki-io provider for
///      symmetry; cached repo providers are auto-disposed because
///      they depend on the database provider.
///
/// **Why this seam.** Account deletion is the single user-initiated
/// flow that requires a true factory-reset of the device's PetPal
/// state. Lifting the orchestration into a single service keeps the
/// UI screen's `_confirmDelete` path readable and lets us unit-test
/// the full sequence with a recording fake [WikiIo] + lambda
/// callbacks for the provider invalidations.
///
/// **Defensive against partial failure.** Every step swallows its
/// own exception and continues — the server-side cascade has already
/// succeeded by the time we reach the local wipe; surfacing a local
/// failure would tell the user "your account is deleted but your
/// device is in a half-broken state," which is technically accurate
/// but not actionable. Failures are reported via [onError] so crash
/// analytics can surface the pattern (DECISIONS row 88 — opt-in
/// crash analytics scaffold).
class LocalDataWipe {
  const LocalDataWipe({
    this.deleteDriftFile = deleteAppDatabaseFile,
    this.onError,
  });

  /// Override for tests — defaults to the real
  /// [deleteAppDatabaseFile] which removes the on-disk SQLite file.
  final Future<void> Function() deleteDriftFile;

  /// Optional error callback. Each wipe step calls this on failure
  /// rather than propagating, so a single bad step doesn't cascade
  /// into a half-wiped device. Production wires to crash analytics;
  /// tests can inject a recording callback to assert error handling.
  final void Function(String stage, Object error)? onError;

  /// Run the full local-wipe sequence.
  ///
  /// [wikiIo] is fetched by the caller (production: `await
  /// ref.read(wikiIoProvider.future)`). [invalidateDatabase] +
  /// [invalidateWikiIo] are tiny lambdas the caller wires to
  /// `ref.invalidate(appDatabaseProvider)` and
  /// `ref.invalidate(wikiIoProvider)` respectively. Tests inject
  /// plain functions.
  ///
  /// Resolves when every step has either completed or logged its
  /// failure via [onError]. Never throws.
  Future<void> wipe({
    required WikiIo wikiIo,
    required void Function() invalidateDatabase,
    required void Function() invalidateWikiIo,
  }) async {
    // Step 1 — wiki files.
    try {
      await wikiIo.deleteAll();
    } catch (e) {
      onError?.call('wiki_files', e);
    }

    // Step 2 — Drift database. Invalidating the provider triggers
    // `onDispose` (which calls `db.close()`); then delete the file.
    try {
      invalidateDatabase();
      // Yield once so the dispose callback fires before we delete
      // the file (the dispose closes the SQLite handle so the OS
      // releases the lock on Windows; on Android/Linux the lock is
      // advisory but the close-then-delete order keeps the file in
      // a clean state for the next open).
      await Future<void>.delayed(Duration.zero);
      await deleteDriftFile();
    } catch (e) {
      onError?.call('drift_file', e);
    }

    // Step 3 — invalidate downstream providers. Other providers
    // (petsProvider, entitlementProvider, etc.) depend on the
    // database provider transitively and are auto-disposed by
    // Riverpod when their root invalidates.
    try {
      invalidateWikiIo();
    } catch (e) {
      onError?.call('invalidate_providers', e);
    }
  }
}

/// Phase 7 task H.1.d.wipe — provider seam.
///
/// Tests override with a recording fake; production gets the default
/// implementation that talks to the real Drift file + real WikiIo.
final localDataWipeProvider = Provider<LocalDataWipe>((ref) {
  return const LocalDataWipe();
});
