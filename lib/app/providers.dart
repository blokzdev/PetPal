import 'dart:typed_data';

import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/db/connection.dart';
import '../data/db/database.dart';
import '../data/onboarding_templates.dart';
import '../data/repos/pet_repo.dart';
import '../data/species_catalog.dart';
import '../data/repos/reminder_repo.dart';
import '../data/repos/skill_repo.dart';
import '../data/repos/trends_repo.dart';
import '../data/repos/wiki_repo.dart';
import '../data/repos/entitlement_repo.dart';
import '../data/soul_file.dart';
import '../data/wiki_io.dart';
import '../data/wiki_io_fs.dart';
import '../harness/agent/agent_loop.dart';
import '../harness/agent/direct_transport.dart';
import '../harness/agent/llm_client.dart';
import '../harness/agent/proxy_transport.dart';
import 'auth/auth_session_notifier.dart';
import 'sync/supabase_runtime_config.dart';
import '../platform/billing/billing_service.dart';
import '../platform/billing/iap_platform.dart';
import 'entitlement/entitlement.dart';
import 'entitlement/entitlement_notifier.dart';
import '../harness/agent/tool_dispatcher.dart';
import '../harness/guardrails/red_flag_screener.dart';
import '../harness/intake/intent_router.dart';
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
import '../harness/observation/affective_observation.dart';
import '../harness/observation/affective_observer.dart';
import '../harness/vision/photo_extractor.dart';
import '../harness/vision/vision_gate.dart';
import '../harness/skills/skill_source.dart';
import '../harness/synthesis/monthly_report.dart';
import '../harness/synthesis/weekly_digest.dart';
import '../harness/tools/scheduling_tools.dart';
import '../harness/tools/wiki_tools.dart';
import '../platform/alarm_scheduler.dart';
import '../platform/api_key_storage.dart';
import '../platform/schedule_health.dart';
import '../platform/settings_storage.dart';
import '../platform/work_scheduler.dart';
import 'active_pet/active_pet_notifier.dart';
import 'welcome/welcome_completed_notifier.dart';

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

/// True once the user has finished the welcome flow.
///
/// Phase 7 task F.1 — decoupled from `apiKeyProvider`. The proxy-
/// default model (DECISIONS row 36) lets a free-tier user be past
/// onboarding without ever entering a key; the canonical "have they
/// seen the welcome + privacy disclosure" signal is now
/// [welcomeCompletedProvider]. Existing pre-Phase-7 users with a
/// stored key are auto-promoted to completed by the notifier's
/// build() (one-time silent migration).
final isOnboardedProvider = Provider<bool>((ref) {
  final completedAsync = ref.watch(welcomeCompletedProvider);
  return completedAsync.maybeWhen(
    data: (done) => done,
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

/// Source of per-category `SOUL.md` seed templates loaded from
/// `assets/onboarding/<category>.md`. Tests inject [InMemoryOnboardingTemplates].
final onboardingTemplatesProvider = Provider<OnboardingTemplates>((ref) {
  return const AssetOnboardingTemplates();
});

/// Source of curated species data per category. Production loads JSON
/// lazily from `assets/species/<category>.json` (DECISIONS rows 42 +
/// 46). Tests inject [InMemorySpeciesCatalog].
final speciesCatalogProvider = Provider<SpeciesCatalog>((ref) {
  return AssetSpeciesCatalog();
});

final petRepoProvider = FutureProvider<PetRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  return PetRepo(db: db, wiki: wiki);
});

/// Phase 7 task B.1 — entitlement cache repo.
final entitlementRepoProvider = FutureProvider<EntitlementRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return EntitlementRepo(db: db);
});

/// Phase 7 task C.1 — Play Billing platform façade. Production wraps
/// `InAppPurchase.instance`. Tests override with a fake.
final iapPlatformProvider = Provider<IapPlatform>((ref) => IapPlatformImpl());

/// Phase 7 task C.1 — Play Billing service. Initialized eagerly so
/// the purchaseStream subscription is open before any pending-on-
/// relaunch purchases get redelivered. Caller awaits the future
/// once at app start; the broadcast `events` stream surfaces all
/// purchase outcomes.
final billingServiceProvider = FutureProvider<BillingService>((ref) async {
  final iap = ref.watch(iapPlatformProvider);
  final service = BillingService(
    iap: iap,
    onOptimisticEntitlement: (ent) async {
      // Push the optimistic state through the entitlement notifier
      // so the agent loop's quota gate + the Settings UI both see
      // Pro immediately. Server reconciliation (when
      // play-billing-verify Edge Function ships) overwrites this
      // with the canonical state from Supabase.
      await ref.read(entitlementProvider.notifier).setOptimistic(ent);
    },
    onPhotoCreditsGranted: (credits) async {
      // Phase 7 task C.2 — credit pack purchase optimistically
      // increments the cached photoCreditsBalance. Read current,
      // copyWith with new balance, set. Backend reconciliation
      // overwrites with the canonical balance once the
      // play-billing-verify Edge Function ships.
      final notifier = ref.read(entitlementProvider.notifier);
      final current = ref.read(entitlementProvider).value ??
          Entitlement.freeAnonymous();
      await notifier.setOptimistic(
        current.copyWith(
          photoCreditsBalance: current.photoCreditsBalance + credits,
        ),
      );
    },
    onCarePackOwned: (skillId) async {
      // Phase 7 task C.3 — care pack purchase optimistically adds
      // the skill ID to the cached ownedCarePackSkillIds set.
      // Backend reconciliation overwrites once the
      // play-billing-verify Edge Function ships.
      final notifier = ref.read(entitlementProvider.notifier);
      final current = ref.read(entitlementProvider).value ??
          Entitlement.freeAnonymous();
      await notifier.setOptimistic(
        current.copyWith(
          ownedCarePackSkillIds: {
            ...current.ownedCarePackSkillIds,
            skillId,
          },
        ),
      );
    },
  );
  ref.onDispose(service.dispose);
  await service.initialize();
  return service;
});

/// Phase 7 task B.1 — active-user entitlement.
///
/// Read by the agent loop's quota gate (DECISIONS row 75), Settings
/// (Pro badge, message counter, photo-credit balance), and the
/// paywall dispatcher. Backed by [EntitlementNotifier]; B.1 emits
/// [Entitlement.freeAnonymous] by default. Reconciliation against
/// Supabase wires in once auth lands (Group F.1).
final entitlementProvider =
    AsyncNotifierProvider<EntitlementNotifier, Entitlement>(
  EntitlementNotifier.new,
);

/// Snapshot list of all pets. Callers that mutate pets (add-pet flow,
/// pet switcher) must `ref.invalidate(petsProvider)` after the write so
/// downstream watchers refetch. We deliberately avoid Drift's `.watch()`
/// here because its internal stream-close timers race with widget-test
/// teardown — fine for production, an annoyance for tests.
final petsProvider = FutureProvider<List<Pet>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return db.select(db.pets).get();
});

/// Phase 6 task 6.2 — profile photo bytes for the given pet, or null
/// if no profile photo is set / SOUL is missing / the binary file is
/// stale. Watched by the home greeting backdrop + chat AppBar avatar
/// surfaces. Invalidate via
/// `ref.invalidate(profilePhotoBytesProvider(petId))` after
/// PetRepo.{set,clear}ProfilePhoto.
final profilePhotoBytesProvider =
    FutureProvider.family<Uint8List?, int>((ref, petId) async {
  final repo = await ref.watch(petRepoProvider.future);
  return repo.readProfilePhotoBytes(petId: petId);
});

/// Phase 7 task D.1 — entitlement gate for vision calls. Replaces
/// the Phase 6 always-allowed stub. Pulls the active entitlement
/// from `entitlementProvider` at check time via `ref.read` (NOT
/// watch — gates fire per-action, not per-state-change; using
/// watch would unnecessarily rebuild the gate on every counter
/// increment).
final visionGateProvider = Provider<VisionGate>((ref) {
  return RealVisionGate(
    entitlementSource: () =>
        ref.read(entitlementProvider).value ??
        Entitlement.freeAnonymous(),
  );
});

/// Phase 6 task 6.5 — photo extractor utility. Sonnet-backed
/// structured-field extraction from image bytes; called from the
/// 6.6 form-preview save flow + the 6.9 chat photo upload path.
/// Routes through `visionGateProvider` for entitlement check
/// (Phase 6 stub = always-allowed; Phase 7 = real entitlement).
final photoExtractorProvider = Provider<PhotoExtractor>((ref) {
  final llm = ref.watch(llmClientProvider);
  final gate = ref.watch(visionGateProvider);
  return PhotoExtractor(llm: llm, gate: gate);
});

/// Phase 8 task 8.0 — intake intent router. Resolves a snapped
/// photo (+ optional caption + optional explicit hint) to an
/// [IntakeIntent] so future lenses (food first) branch the capture
/// flow without reinventing classification. Hybrid resolution per
/// DECISIONS row 98 — explicit hint authoritative when present, a
/// lightweight Haiku classifier handles soft cases. Wired against
/// [haikuLlmClientProvider] per DECISIONS row 41 (f) precedent
/// (Sonnet for extraction, Haiku for lightweight classification).
/// Routes through [visionGateProvider] for entitlement-path
/// uniformity even though intake is FREE per row 102.
final intakeIntentRouterProvider = Provider<IntakeIntentRouter>((ref) {
  final llm = ref.watch(haikuLlmClientProvider);
  final gate = ref.watch(visionGateProvider);
  return IntakeIntentRouter(llm: llm, gate: gate);
});

/// Phase 6 task 6.8 — Haiku-tuned LLM client for the affective
/// observation layer. DECISIONS row 41 (f) split: Sonnet for the
/// extractor (accuracy on structured fields); Haiku for the affective
/// add-on (cost-sensitive — fires at most 1-per-5-saves, doesn't
/// need Sonnet's nuance). Same selection rules as [llmClientProvider]
/// (BYOK → DirectTransport, signed-in → ProxyTransport).
final haikuLlmClientProvider = Provider<LlmClient>((ref) {
  return _selectLlmTransport(ref, model: 'claude-haiku-4-5');
});

/// Phase 6 task 6.8 — affective observation runner. Optional warm-
/// observation pipeline that fires after a saved photo memory. Behind
/// the [showAffectiveObservationsProvider] toggle (default ON);
/// frequency-cap enforced by callers via SettingsStorage.
final affectiveObserverProvider =
    FutureProvider<AffectiveObserver>((ref) async {
  final llm = ref.watch(haikuLlmClientProvider);
  final retriever = await ref.watch(hybridRetrieverProvider.future);
  final embeddings = await ref.watch(embeddingProviderProvider.future);
  return AffectiveObserver(
    llm: llm,
    retriever: retriever,
    embeddings: embeddings,
  );
});

/// Phase 6 task 6.8 — Settings toggle "Show occasional observations".
/// Default ON per DECISIONS row 41 (e) — with three compounding gates
/// the actual fire rate is very low (~1 per 20–30 saves), so default-
/// ON makes the warm moment surface for users who'd value it without
/// risking intrusiveness. Flip OFF to mute the entire layer.
final showAffectiveObservationsProvider =
    AsyncNotifierProvider<_ShowAffectiveObservationsNotifier, bool>(
  _ShowAffectiveObservationsNotifier.new,
);

class _ShowAffectiveObservationsNotifier extends AsyncNotifier<bool> {
  static const _key = 'show_affective_observations';

  @override
  Future<bool> build() async {
    final storage = ref.read(settingsStorageProvider);
    final v = await storage.getBool(_key);
    return v ?? true;
  }

  Future<void> set(bool value) async {
    state = const AsyncValue.loading();
    final storage = ref.read(settingsStorageProvider);
    await storage.setBool(_key, value);
    state = AsyncValue.data(value);
  }
}

/// Phase 6 task 6.8 — most-recent affective observation, surfaced
/// after a photo save. Cleared by the home-screen card after the user
/// dismisses or after a TTL the card enforces. Lives in app state
/// (not on disk) — observations are ephemeral by design; the user
/// either reads them in the moment or doesn't.
///
/// Use-as-a-mailbox pattern: the photo capture screen pushes the
/// observation here on save; the home screen reads + clears.
final recentAffectiveObservationProvider =
    NotifierProvider<_RecentAffectiveObservationNotifier,
        AffectiveObservation?>(_RecentAffectiveObservationNotifier.new);

class _RecentAffectiveObservationNotifier
    extends Notifier<AffectiveObservation?> {
  @override
  AffectiveObservation? build() => null;

  void post(AffectiveObservation observation) {
    state = observation;
  }

  void dismiss() {
    state = null;
  }
}

/// Active pet's wiki entries, newest first. Invalidated by
/// `ref.invalidate(wikiEntriesProvider)` after chat-tool writes (or any
/// other mutation) so the wiki browser refetches on next build.
///
/// Phase 7 task E.2 — follows [activePetProvider] (the persisted pet
/// switcher selection, with a `pets.last` fallback). Home + Profile
/// stay scoped to the active pet via this provider; the Journal
/// screen consumes [journalEntriesProvider] so it can also surface
/// the cross-pet "All pets" mode.
final wikiEntriesProvider = FutureProvider<List<Entry>>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final pet = ref.watch(activePetProvider);
  if (pet == null) return const [];
  return (db.select(db.entries)
        ..where((e) => e.petId.equals(pet.id))
        ..orderBy([(e) => OrderingTerm.desc(e.ts)]))
      .get();
});

/// Phase 7 task E.2 — Journal-tab entries provider. `null` selection
/// = the cross-pet "All pets" timeline (interleaved by `ts desc`);
/// a non-null selection = entries for that single pet. Distinct
/// from [wikiEntriesProvider] so Home/Profile (active-pet-scoped)
/// don't have to share invalidation semantics with the Journal's
/// per-screen view selection.
///
/// Watches [wikiEntriesProvider] for its dependency signal — chat
/// / tool / form writes that invalidate the active-pet provider
/// should also refresh the Journal regardless of which selection
/// is active. The watched value isn't consumed; only the dep-graph
/// edge matters.
final journalEntriesProvider =
    FutureProvider.family<List<Entry>, int?>((ref, petId) async {
  ref.watch(wikiEntriesProvider);
  final db = await ref.watch(appDatabaseProvider.future);
  final pets = await ref.watch(petsProvider.future);
  if (pets.isEmpty) return const [];
  final query = db.select(db.entries)
    ..orderBy([(e) => OrderingTerm.desc(e.ts)]);
  if (petId == null) {
    final ids = pets.map((p) => p.id).toList();
    query.where((e) => e.petId.isIn(ids));
  } else {
    query.where((e) => e.petId.equals(petId));
  }
  return query.get();
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

/// Phase 6 task 6.12 — read-only trends repo for the SOUL profile
/// charts. Watches the wiki entries provider (so the chart refetches
/// after any tool-driven save) plus the underlying database + wiki
/// IO. The two lookups (weight history + symptom frequencies) are
/// surfaced as their own FutureProviders.family-by-petId so the
/// charts can be loaded independently and don't block each other.
final trendsRepoProvider = FutureProvider<TrendsRepo>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  return TrendsRepo(db: db, wiki: wiki);
});

/// Phase 6 task 6.12 — weight history for the active pet. Refetched
/// on `ref.invalidate(wikiEntriesProvider)` cascade since the trends
/// repo depends on entries and we already invalidate wikiEntries on
/// every write.
final weightHistoryProvider =
    FutureProvider.family<List<WeightObservation>, int>((ref, petId) async {
  // Watch wikiEntriesProvider so a new weight entry triggers a refetch.
  ref.watch(wikiEntriesProvider);
  final repo = await ref.watch(trendsRepoProvider.future);
  return repo.weightHistory(petId);
});

/// Phase 6 task 6.12 — symptom frequencies for the active pet.
/// FTS5-backed; fast even on a large journal.
final symptomFrequenciesProvider =
    FutureProvider.family<List<SymptomFrequency>, int>((ref, petId) async {
  ref.watch(wikiEntriesProvider);
  final repo = await ref.watch(trendsRepoProvider.future);
  return repo.symptomFrequencies(petId);
});

final hybridRetrieverProvider = FutureProvider<HybridRetriever>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  return HybridRetriever(db: db);
});

/// Returns a callback resolving to the active pet's id at call time.
///
/// Phase 7 task E.2 — resolves the persisted pet-switcher selection
/// (via [activePetSelectionProvider]) when set and the pet still
/// exists; otherwise falls back to `pets.last.id`. Throws
/// [StateError] when no pets exist (callers must route to
/// `/pets/add` first). The callable shape is preserved for existing
/// `ref.read(activePetIdProvider)()` call sites in chat / soul
/// editor / hub.
final activePetIdProvider = Provider<int Function()>((ref) {
  return () {
    final pets = ref.read(petsProvider).maybeWhen(
          data: (p) => p,
          orElse: () => const <Pet>[],
        );
    if (pets.isEmpty) {
      throw StateError(
        'No active pet — UI should have routed to /pets/add before chat.',
      );
    }
    final selected = ref.read(activePetSelectionProvider).value;
    if (selected != null) {
      for (final p in pets) {
        if (p.id == selected) return p.id;
      }
    }
    return pets.last.id;
  };
});

/// Phase 7 task E.2 — resolved active [Pet] (or `null` when no pets
/// exist). Watches both [petsProvider] and
/// [activePetSelectionProvider] so the active surfaces (home greeting,
/// profile, journal title) repaint when the user picks a pet from
/// the switcher or the persisted selection loads on app start.
final activePetProvider = Provider<Pet?>((ref) {
  final pets = ref.watch(petsProvider).maybeWhen(
        data: (p) => p,
        orElse: () => const <Pet>[],
      );
  if (pets.isEmpty) return null;
  final selected = ref.watch(activePetSelectionProvider).value;
  if (selected != null) {
    for (final p in pets) {
      if (p.id == selected) return p;
    }
  }
  return pets.last;
});

// ─── LLM client + agent loop ───────────────────────────────────────────────

/// Production [LlmClient]. Selects between [DirectTransport] (BYOK)
/// and [ProxyTransport] (signed-in via Supabase Edge Function) per
/// the rules in [_selectLlmTransport]. Tests override with a
/// scripted fake.
final llmClientProvider = Provider<LlmClient>((ref) {
  return _selectLlmTransport(ref);
});

/// Phase 7 task H.1.c.2 — LlmTransport selection (DECISIONS rows 36
/// + 74 + 82).
///
/// Decision matrix:
///   1. **BYOK** — `apiKeyProvider` non-empty → [DirectTransport]
///      with the user's key. Calls go straight to api.anthropic.com;
///      PetPal's proxy is bypassed (row 74).
///   2. **Signed-in proxy** — no key, but `authSessionProvider` has
///      a session AND `supabaseRuntimeConfigProvider` is populated
///      → [ProxyTransport] with the session's JWT. Calls route
///      through the Edge Function which atomically increments the
///      monthly text counter (row 75) and forwards to Anthropic.
///   3. **Otherwise** — throw `StateError`. Callers MUST guard via
///      `_chatTransportReady(ref)` (chat_screen) or analogous gates
///      so the throw is never reached in practice. Vision callers
///      gate via [VisionGate].
///
/// Anonymous (signed-out) proxy via device-token routes forward to
/// a later commit — H.1.c.2 ships the signed-in path only. The
/// Edge Function itself supports both paths today (per row 82).
LlmClient _selectLlmTransport(
  Ref ref, {
  String model = 'claude-sonnet-4-6',
  int maxTokens = 4096,
}) {
  // BYOK precedence — same rule as the entitlement notifier
  // (Entitlement.byok wins) so the transport choice agrees with the
  // tier the user sees in Settings.
  final keyAsync = ref.watch(apiKeyProvider);
  final key = keyAsync.maybeWhen(data: (k) => k, orElse: () => null);
  if (key != null && key.isNotEmpty) {
    final client = DirectTransport(
      apiKey: key,
      model: model,
      maxTokens: maxTokens,
    );
    ref.onDispose(client.close);
    return client;
  }

  // Proxy path — signed-in + Supabase configured.
  final session = ref.watch(authSessionProvider).value;
  final config = ref.watch(supabaseRuntimeConfigProvider);
  if (session != null && config != null) {
    final client = ProxyTransport(
      supabaseUrl: config.url,
      supabaseAnonKey: config.anonKey,
      userJwt: session.accessToken,
      model: model,
      maxTokens: maxTokens,
    );
    ref.onDispose(client.close);
    return client;
  }

  throw StateError(
    'No transport available: BYOK key absent + not signed in. '
    'Caller must guard with _chatTransportReady (or analogous '
    'auth + entitlement check) before reading llmClientProvider.',
  );
}

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

/// Phase 6.6 task 6.6.A.3 — pet's reminders, ordered by repo insertion.
/// Promoted from `reminders_screen.dart` (was private) so the Home
/// inline Reminders section (DECISIONS row 61) can share the same
/// data path. Callers should `ref.invalidate(remindersForPetProvider)`
/// after a create / cancel so the next watch refetches.
final remindersForPetProvider =
    FutureProvider.family<List<ReminderRow>, int>((ref, petId) async {
  final service = await ref.watch(reminderServiceProvider.future);
  return service.listForPet(petId);
});

/// Phase 7 task E.2 — family-wide reminders, sectioned by pet, in
/// pet-creation order. Each entry pairs a pet with its (possibly
/// empty) reminder list. The Reminders screen renders sections in
/// this order; sections with no reminders are dropped at the screen
/// layer (this provider returns the full set so callers can
/// distinguish "no pets" from "every pet has zero reminders").
final allRemindersProvider =
    FutureProvider<List<({Pet pet, List<ReminderRow> reminders})>>(
        (ref) async {
  final pets = await ref.watch(petsProvider.future);
  final out = <({Pet pet, List<ReminderRow> reminders})>[];
  for (final pet in pets) {
    final reminders = await ref.watch(remindersForPetProvider(pet.id).future);
    out.add((pet: pet, reminders: reminders));
  }
  return out;
});

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
    // Phase 7 task D.1 — pulls entitlement at create-time to enforce
    // the 5-reminder free-tier cap. Pull (read) not push (watch) so
    // the service stays stable across counter-increment rebuilds;
    // the gate fires per-action, reading the current value.
    entitlementSource: () =>
        ref.read(entitlementProvider).value ?? Entitlement.freeAnonymous(),
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
  // Phase 7 task C.3 — entitlement-gated `requires_pro` skills.
  // Snapshot the entitlement at construction time via `ref.read`
  // (NOT watch) so the loader stays stable across the session.
  // Entitlement changes (Pro upgrade, care pack purchase) take
  // effect on the next session — chat sessions don't span billing
  // events in practice, and a mid-session loader rebuild would
  // invalidate active skill matching.
  final entitlement = ref.read(entitlementProvider).maybeWhen(
        data: (e) => e,
        orElse: Entitlement.freeAnonymous,
      );
  return SkillLoader(
    source: source,
    isPro: entitlement.isPro,
    ownedCarePackSkillIds: entitlement.ownedCarePackSkillIds,
  );
});

/// Catalog entry for the skill browser: manifest + whether it's
/// currently enabled. Pre-filtered to the active pet's category so the
/// browser only shows relevant skills (CLAUDE.md §3 — onboarding
/// templates and skill packs are the only category-aware paths).
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
  // Category lives in SOUL.md frontmatter (CLAUDE.md §3). Empty when
  // SOUL.md is missing or the user hasn't filled in category — only
  // universal skills survive that case.
  String petCategory = '';
  try {
    final soul = await wiki.read(wiki.soulPath(pets.last.id));
    petCategory = parseSoul(soul).frontmatter['category']?.toString() ?? '';
  } catch (_) {
    // No SOUL.md yet; petCategory stays empty.
  }

  final disabled = await repo.disabledIds();
  final entries = await source.list();
  return [
    for (final e in entries)
      if (e.manifest.matchesCategory(petCategory))
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

/// Phase 6 task 6.14 — [MonthlyReportRunner] for the longer-arc Pro
/// surface. Same composition shape as the weekly runner; the
/// scheduling-side wiring (a synthesisNotify-mode reminder that fires
/// once a month) lands in Phase 7 alongside the entitlement gate.
final monthlyReportRunnerProvider =
    FutureProvider<MonthlyReportRunner>((ref) async {
  final db = await ref.watch(appDatabaseProvider.future);
  final wiki = await ref.watch(wikiIoProvider.future);
  final wikiRepo = await ref.watch(wikiRepoProvider.future);
  final llm = ref.watch(llmClientProvider);
  return MonthlyReportRunner(
    db: db,
    wiki: wiki,
    wikiRepo: wikiRepo,
    llm: llm,
  );
});
