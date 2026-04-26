import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/connection.dart';
import '../data/db/database.dart';
import '../data/onboarding_templates.dart';
import '../data/repos/pet_repo.dart';
import '../data/repos/reminder_repo.dart';
import '../data/repos/skill_repo.dart';
import '../data/repos/wiki_repo.dart';
import '../data/soul_file.dart';
import '../data/wiki_io.dart';
import '../data/wiki_io_fs.dart';
import '../harness/agent/agent_loop.dart';
import '../harness/agent/anthropic_client.dart';
import '../harness/agent/llm_client.dart';
import '../harness/agent/tool_dispatcher.dart';
import '../harness/guardrails/red_flag_screener.dart';
import '../harness/retrieval/embedding_provider.dart';
import '../harness/retrieval/embedding_worker.dart';
import '../harness/retrieval/hybrid_retriever.dart';
import '../harness/retrieval/onnx_embedding_provider.dart';
import '../harness/scheduling/notification_template.dart';
import '../harness/scheduling/reminder_scheduler.dart';
import '../harness/scheduling/reminder_service.dart';
import '../harness/session_builder.dart';
import '../harness/skills/asset_skill_source.dart';
import '../harness/skills/enabled_filtering_skill_source.dart';
import '../harness/skills/skill_loader.dart';
import '../harness/skills/skill_manifest.dart';
import '../harness/skills/skill_source.dart';
import '../harness/synthesis/weekly_digest.dart';
import '../harness/tools/scheduling_tools.dart';
import '../harness/tools/wiki_tools.dart';
import '../platform/alarm_scheduler.dart';
import '../platform/api_key_storage.dart';
import '../platform/schedule_health.dart';
import '../platform/settings_storage.dart';
import '../platform/work_scheduler.dart';

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

/// Source of per-species `SOUL.md` seed templates loaded from
/// `assets/onboarding/<species>.md`. Tests inject [InMemoryOnboardingTemplates].
final onboardingTemplatesProvider = Provider<OnboardingTemplates>((ref) {
  return const AssetOnboardingTemplates();
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

/// Active pet's wiki entries, newest first. Invalidated by
/// `ref.invalidate(wikiEntriesProvider)` after chat-tool writes (or any
/// other mutation) so the wiki browser refetches on next build.
final wikiEntriesProvider = FutureProvider<List<Entry>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final pets = await ref.watch(petsProvider.future);
  if (pets.isEmpty) return const [];
  final petId = pets.last.id;
  return (db.select(db.entries)
        ..where((e) => e.petId.equals(petId))
        ..orderBy([(e) => OrderingTerm.desc(e.ts)]))
      .get();
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

/// Production [AlarmScheduler] / [WorkScheduler] / [ReminderScheduler] —
/// each constructs its plugin bindings lazily so the providers are
/// safe to instantiate in `flutter test` (no plugin call until you
/// actually arm a reminder, which tests don't do).
final alarmSchedulerProvider =
    Provider<AlarmScheduler>((ref) => AlarmScheduler());

final workSchedulerProvider =
    Provider<WorkScheduler>((ref) => WorkScheduler());

final reminderSchedulerProvider = Provider<ReminderScheduler>((ref) {
  return ReminderScheduler(
    alarms: ref.watch(alarmSchedulerProvider),
    work: ref.watch(workSchedulerProvider),
  );
});

final reminderRepoProvider = FutureProvider<ReminderRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return ReminderRepo(db: db);
});

/// Production notification-template loader (asset-backed). Tests can
/// override with [InMemoryNotificationTemplates].
final notificationTemplatesProvider = Provider<NotificationTemplates>(
  (ref) => const AssetNotificationTemplates(),
);

/// Production red-flag screener using the canonical pattern table.
/// Singleton — the table is immutable across the session.
final redFlagScreenerProvider =
    Provider<RedFlagScreener>((ref) => RedFlagScreener());

/// Read-only schedule-health snapshot service. Used by the reminders
/// screen banner (4.10) and the battery-exemption prompt (4.7).
final scheduleHealthServiceProvider = Provider<ScheduleHealthService>(
  (ref) => const PlatformScheduleHealthService(),
);

/// Top-level facade over reminder create/cancel/list. Wraps repo +
/// scheduler + template renderer so callers (tools + UI) don't have
/// to wire those individually.
final reminderServiceProvider = FutureProvider<ReminderService>((ref) async {
  final repo = await ref.watch(reminderRepoProvider.future);
  final scheduler = ref.watch(reminderSchedulerProvider);
  final templates = ref.watch(notificationTemplatesProvider);
  final petRepo = await ref.watch(petRepoProvider.future);
  return ReminderService(
    repo: repo,
    scheduler: scheduler,
    templates: templates,
    petNameLookup: (id) async => (await petRepo.getPet(id))?.name,
  );
});

/// Live [ToolDispatcher] with the canonical wiki tools + the Phase 4
/// scheduling/safety tools (`schedule_reminder`, `list_reminders`,
/// `red_flag_check`) registered against the production services.
final toolDispatcherProvider =
    FutureProvider<ToolDispatcher>((ref) async {
  final wiki = await ref.watch(wikiIoProvider.future);
  final repo = await ref.watch(wikiRepoProvider.future);
  final retriever = await ref.watch(hybridRetrieverProvider.future);
  final embeddings = await ref.watch(embeddingProviderProvider.future);
  final activePetId = ref.watch(activePetIdProvider);
  final reminders = await ref.watch(reminderServiceProvider.future);
  final screener = ref.watch(redFlagScreenerProvider);

  final dispatcher = ToolDispatcher();
  registerWikiTools(
    dispatcher,
    wiki: wiki,
    repo: repo,
    retriever: retriever,
    embeddings: embeddings,
    activePetId: activePetId,
  );
  registerSchedulingTools(
    dispatcher,
    reminders: reminders,
    screener: screener,
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

/// Repo over the `skills_installed` table — enabled-state persistence.
final skillRepoProvider = FutureProvider<SkillRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return SkillRepo(db: db);
});

/// **Raw** discovery source for skills (no enabled filter applied).
/// Production: discover via `assets/skills/<id>/manifest.md` (Phase 3.5
/// ships puppy, senior-dog, new-cat). Tests inject in-memory or empty.
final skillSourceProvider = Provider<SkillSource>((ref) {
  return const AssetSkillSource();
});

/// The source [SkillLoader] consumes — wraps [skillSourceProvider] with
/// the user's enable/disable preferences from [skillRepoProvider]. The
/// browser screen reads the raw source directly so disabled skills
/// stay visible (toggleable); the loader sees only the enabled ones.
final filteredSkillSourceProvider =
    FutureProvider<SkillSource>((ref) async {
  final inner = ref.watch(skillSourceProvider);
  final repo = await ref.watch(skillRepoProvider.future);
  return EnabledFilteringSkillSource(inner: inner, repo: repo);
});

final skillLoaderProvider = FutureProvider<SkillLoader>((ref) async {
  final source = await ref.watch(filteredSkillSourceProvider.future);
  return SkillLoader(source: source);
});

/// Catalog entry for the skill browser: manifest + whether it's
/// currently enabled. Pre-filtered to the active pet's species so the
/// browser only shows relevant skills (CLAUDE.md §3 — onboarding
/// templates and skill packs are the only species-aware paths).
class SkillCatalogEntry {
  const SkillCatalogEntry({required this.manifest, required this.enabled});
  final SkillManifest manifest;
  final bool enabled;
}

final skillCatalogProvider =
    FutureProvider<List<SkillCatalogEntry>>((ref) async {
  final source = ref.watch(skillSourceProvider);
  final repo = await ref.watch(skillRepoProvider.future);
  final pets = await ref.watch(petsProvider.future);
  if (pets.isEmpty) return const [];
  final wiki = await ref.watch(wikiIoProvider.future);
  // Species lives in SOUL.md frontmatter (CLAUDE.md §3). Empty when
  // SOUL.md is missing or the user hasn't filled in species — only
  // universal skills survive that case.
  String petSpecies = '';
  try {
    final soul = await wiki.read(wiki.soulPath(pets.last.id));
    petSpecies = parseSoul(soul).frontmatter['species']?.toString() ?? '';
  } catch (_) {
    // No SOUL.md yet; petSpecies stays empty.
  }

  final disabled = await repo.disabledIds();
  final entries = await source.list();
  return [
    for (final e in entries)
      if (e.manifest.matchesSpecies(petSpecies))
        SkillCatalogEntry(
          manifest: e.manifest,
          enabled: !disabled.contains(e.manifest.id),
        ),
  ];
});

/// [SessionBuilder] that composes per-turn inputs (cache-stable system
/// prompt + retrieval-augmented user message). Backed by the live
/// retrieval, embedding, and skill stacks.
final sessionBuilderProvider =
    FutureProvider<SessionBuilder>((ref) async {
  final wiki = await ref.watch(wikiIoProvider.future);
  final retriever = await ref.watch(hybridRetrieverProvider.future);
  final embeddings = await ref.watch(embeddingProviderProvider.future);
  final skills = await ref.watch(skillLoaderProvider.future);
  return SessionBuilder(
    wiki: wiki,
    retriever: retriever,
    embeddings: embeddings,
    skills: skills,
  );
});

// ─── Settings ──────────────────────────────────────────────────────────────

const _weeklyDigestKey = 'weekly_digest_enabled';

/// Singleton [SettingsStorage]. Override in `main()` with the
/// SharedPreferences-backed impl; widget tests use an in-memory fake.
final settingsStorageProvider = Provider<SettingsStorage>((ref) {
  throw UnimplementedError(
    'settingsStorageProvider must be overridden in ProviderScope',
  );
});

/// Whether the weekly synthesis-mode digest is enabled. Defaults to
/// **off** — Pro-tier feature per CLAUDE.md §8, the user opts in.
final weeklyDigestEnabledProvider =
    AsyncNotifierProvider<WeeklyDigestEnabledNotifier, bool>(
  WeeklyDigestEnabledNotifier.new,
);

class WeeklyDigestEnabledNotifier extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    final stored =
        await ref.read(settingsStorageProvider).getBool(_weeklyDigestKey);
    return stored ?? false;
  }

  Future<void> setEnabled(bool enabled) async {
    await ref
        .read(settingsStorageProvider)
        .setBool(_weeklyDigestKey, enabled);
    state = AsyncData(enabled);
  }
}

/// [WeeklyDigestRunner] composed from the live data + LLM stack.
final weeklyDigestRunnerProvider =
    FutureProvider<WeeklyDigestRunner>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  final wikiRepo = await ref.watch(wikiRepoProvider.future);
  final llm = ref.watch(llmClientProvider);
  return WeeklyDigestRunner(
    db: db,
    wiki: wiki,
    wikiRepo: wikiRepo,
    llm: llm,
  );
});
