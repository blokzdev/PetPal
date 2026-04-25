import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/connection.dart';
import '../data/db/database.dart';
import '../data/repos/pet_repo.dart';
import '../data/repos/wiki_repo.dart';
import '../data/wiki_io.dart';
import '../data/wiki_io_fs.dart';
import '../harness/agent/agent_loop.dart';
import '../harness/agent/anthropic_client.dart';
import '../harness/agent/llm_client.dart';
import '../harness/agent/tool_dispatcher.dart';
import '../harness/retrieval/embedding_provider.dart';
import '../harness/retrieval/embedding_worker.dart';
import '../harness/retrieval/hybrid_retriever.dart';
import '../harness/retrieval/onnx_embedding_provider.dart';
import '../harness/tools/wiki_tools.dart';
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

// ─── Embeddings + retrieval ────────────────────────────────────────────────

/// Production [EmbeddingProvider] (Snowflake arctic-embed-xs ONNX). Tests
/// override with [StubEmbeddingProvider] — flutter_onnxruntime's native
/// plugin doesn't load in `flutter test`.
final embeddingProviderProvider = FutureProvider<EmbeddingProvider>((ref) {
  return OnnxEmbeddingProvider.fromAssets();
});

final embeddingWorkerProvider = FutureProvider<EmbeddingWorker>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final provider = await ref.watch(embeddingProviderProvider.future);
  return EmbeddingWorker(db: db, provider: provider);
});

final wikiRepoProvider = FutureProvider<WikiRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  final worker = await ref.watch(embeddingWorkerProvider.future);
  return WikiRepo(db: db, wiki: wiki, embeddings: worker);
});

final hybridRetrieverProvider = FutureProvider<HybridRetriever>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return HybridRetriever(db: db);
});

/// Returns a callback resolving to the active pet's id at call time.
/// Free-tier rule (DECISIONS row 8): the most recently-created pet is
/// active; multi-pet UI lands in 2.9.
final activePetIdProvider = Provider<int Function()>((ref) {
  return () {
    final petsAsync = ref.read(petsProvider);
    final pets = petsAsync.maybeWhen(
      data: (p) => p,
      orElse: () => const <Pet>[],
    );
    if (pets.isEmpty) {
      throw StateError(
        'No active pet — UI should have routed to /pets/add before chat.',
      );
    }
    return pets.last.id;
  };
});

// ─── LLM client + agent loop ───────────────────────────────────────────────

/// Production [LlmClient] backed by [AnthropicClient]. Reads the API key
/// from [apiKeyProvider]; when the key changes (rotation in Settings, or
/// onboarding), the provider rebuilds and emits a fresh client. Tests
/// override with a scripted fake.
final llmClientProvider = Provider<LlmClient>((ref) {
  final keyAsync = ref.watch(apiKeyProvider);
  final key = keyAsync.maybeWhen(data: (k) => k, orElse: () => null);
  if (key == null || key.isEmpty) {
    throw StateError(
      'No API key — onboarding incomplete. Cannot construct LlmClient.',
    );
  }
  final client = AnthropicClient(apiKey: key);
  ref.onDispose(client.close);
  return client;
});

/// Live [ToolDispatcher] with the four canonical wiki tools registered
/// against the production repos and IO.
final toolDispatcherProvider =
    FutureProvider<ToolDispatcher>((ref) async {
  final wiki = await ref.watch(wikiIoProvider.future);
  final repo = await ref.watch(wikiRepoProvider.future);
  final retriever = await ref.watch(hybridRetrieverProvider.future);
  final embeddings = await ref.watch(embeddingProviderProvider.future);
  final activePetId = ref.watch(activePetIdProvider);

  final dispatcher = ToolDispatcher();
  registerWikiTools(
    dispatcher,
    wiki: wiki,
    repo: repo,
    retriever: retriever,
    embeddings: embeddings,
    activePetId: activePetId,
  );
  return dispatcher;
});

/// Live [AgentLoop] wrapping the LLM client and tool dispatcher. The
/// chat surface drives `streamRun` against this provider.
final agentLoopProvider = FutureProvider<AgentLoop>((ref) async {
  final llm = ref.watch(llmClientProvider);
  final tools = await ref.watch(toolDispatcherProvider.future);
  return AgentLoop(llm: llm, tools: tools);
});
