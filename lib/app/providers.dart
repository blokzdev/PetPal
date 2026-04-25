import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/connection.dart';
import '../data/db/database.dart';
import '../data/repos/pet_repo.dart';
import '../data/wiki_io.dart';
import '../data/wiki_io_fs.dart';
import '../platform/api_key_storage.dart';

// ─── API key ────────────────────────────────────────────────────────────────

/// Singleton [ApiKeyStorage]. Overridden in `main()` with
/// [SecureApiKeyStorage]; widget tests override with an in-memory fake.
final apiKeyStorageProvider = Provider<ApiKeyStorage>((ref) {
  throw UnimplementedError(
    'apiKeyStorageProvider must be overridden in ProviderScope',
  );
});

/// The user's current Anthropic API key, or null if onboarding isn't done.
///
/// Implemented as a state-keeping `Notifier` so the onboarding flow can
/// `notifier.save(...)` after a successful save and the rest of the app
/// (chat, settings, the router redirect in `routerProvider`) reacts
/// immediately — no second `read()` round-trip to secure storage.
final apiKeyProvider =
    AsyncNotifierProvider<ApiKeyNotifier, String?>(ApiKeyNotifier.new);

class ApiKeyNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() => ref.read(apiKeyStorageProvider).read();

  Future<void> save(String apiKey) async {
    final trimmed = apiKey.trim();
    await ref.read(apiKeyStorageProvider).write(trimmed);
    state = AsyncData(trimmed);
  }

  Future<void> clear() async {
    await ref.read(apiKeyStorageProvider).clear();
    state = const AsyncData(null);
  }
}

/// True once the user has saved a non-empty API key. The router uses this
/// to gate the onboarding redirect.
final isOnboardedProvider = Provider<bool>((ref) {
  final keyAsync = ref.watch(apiKeyProvider);
  return keyAsync.maybeWhen(
    data: (k) => k != null && k.isNotEmpty,
    orElse: () => false,
  );
});

// ─── Data layer ─────────────────────────────────────────────────────────────

/// Production [AppDatabase] anchored at `<app-documents>/petpal.sqlite`.
/// Tests override with an in-memory database.
final appDatabaseProvider = FutureProvider<AppDatabase>((ref) async {
  final db = await openAppDatabase();
  ref.onDispose(() async {
    await db.close();
  });
  return db;
});

/// Production [WikiIo] rooted at `<app-documents>/petpal/`.
/// Tests override with a [WikiIoFs] anchored at a temp dir.
final wikiIoProvider = FutureProvider<WikiIo>((ref) async {
  return WikiIoFs.openDefault();
});

final petRepoProvider = FutureProvider<PetRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  return PetRepo(db: db, wiki: wiki);
});

/// Snapshot list of all pets. Callers that mutate pets (add-pet flow,
/// pet switcher) must `ref.invalidate(petsProvider)` after the write so
/// downstream watchers refetch. We deliberately avoid Drift's `.watch()`
/// here because its internal stream-close timers race with widget-test
/// teardown — fine for production, an annoyance for tests.
final petsProvider = FutureProvider<List<Pet>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.select(db.pets).get();
});
