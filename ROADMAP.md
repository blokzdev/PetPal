# PetPal Roadmap

Eight phases. Tasks are sized to ≤30 min of agent work. Every phase ends with a deliverable I can verify on a real Android device, and a hard stop. The agent does not auto-advance.

The original plan was six phases (Phase 0 scaffold → Phase 5 monetization → Phase 6 launch). After Phase 4 we restructured: the harness is past MVP-grade (873 tests, three-layer memory, scheduling, 11-category guardrails, species-aware skills), but the app's experiential surface is still MVP-quality. Monetizing barebones UI on top of world-class architecture inverts the value perception. So we inserted **Phase 5 (Product Polish & Visual Identity)** and **Phase 6 (Feature Depth & AI Capabilities)** before monetization. The original Phase 5 became Phase 7; the original Phase 6 became Phase 8. See DECISIONS row 34 for the rationale.

**Current phase: Phase 5 — COMPLETE. Next: Phase 5.5 (Identity Foundations) — sub-phase inserted between Phase 5 and Phase 6 per DECISIONS rows 42 + 43. Phase 6 does not start until Phase 5.5 wraps.**

---

## Phase 0 — Architecture & Scaffolding

**Goal:** an empty Flutter app runs on Android; repo docs and CI exist.
**Definition of done:** debug APK installs on device, shows a placeholder Home screen, no crashes; `flutter analyze` is clean; CI passes on `main` and the working branch.

- [x] 0.1 Confirm and commit `CLAUDE.md`, `ROADMAP.md`, `DECISIONS.md` (this commit)
- [x] 0.2 `flutter create` with org id, package name, min SDK 24, null-safety on
- [x] 0.3 Establish folder structure (`lib/harness/`, `lib/data/`, `lib/app/`, `lib/platform/`, `lib/models/`)
- [x] 0.4 Add core deps: `drift`, `sqlite3` (3.x), `path_provider`, `flutter_riverpod`, `go_router`, `flutter_secure_storage` (+ `drift_dev`, `build_runner` dev)
- [x] 0.5 Add `analysis_options.yaml` (lints), `.editorconfig`, tighten `.gitignore`
- [x] 0.6 Placeholder Home screen + Theme + Router (one route, one widget)
- [x] 0.7 Android manifest: `POST_NOTIFICATIONS`, `SCHEDULE_EXACT_ALARM`, `RECEIVE_BOOT_COMPLETED`
- [x] 0.8 Release signing config stub in `android/app/build.gradle` (no key file yet)
- [x] 0.9 GitHub Actions: `flutter analyze` + `flutter test` on push and PR
- [x] 0.10 Phase wrap-up commit: `chore: phase 0 complete`; write phase-end summary

**On-device verification:** install debug APK, see Home screen, hot-reload works, `adb logcat` shows no errors.

**STOP.** Wait for user to verify before starting Phase 1.

---

## Phase 1 — Core Harness (Runtime + Storage)

**Goal:** the harness exists end-to-end without a UI: schema, file I/O, retrieval, agent-loop skeleton, tool dispatcher, Anthropic client.
**Definition of done:** a hidden dev screen creates a pet, writes a markdown note, and both keyword (FTS5) and semantic (vector) search return that note.

- [x] 1.1 Drift schema: `pets`, `entries`, `entries_fts5`, `embeddings`, `sessions`, `messages`, `reminders`, `skills_installed` + initial migration
- [x] 1.2 `PetRepo` (CRUD pets, seed `SOUL.md`)
- [x] 1.3 `wiki_io.dart`: atomic write, read, list-by-pet, slug rules, path helpers under `path_provider` doc dir
- [x] 1.4 `WikiRepo`: write-through to file + FTS5 + entries row; rebuild-index from files on startup
- [x] 1.5 Wire `sqlite-vec` loadable extension via FFI on Android; verify `vec_distance_l2` executes
- [x] 1.6 Embedding worker: on entry write, queue embed job (interface only — model call stubbed)
- [x] 1.7 Hybrid retrieval: FTS5 ∪ vector kNN, dedupe by `entry_id`, return ranked snippets
- [x] 1.8 `AgentLoop` skeleton: turn struct, message history, tool-call parsing
- [x] 1.9 `ToolDispatcher` with stubs for `read_wiki`, `search_wiki`, `write_wiki_entry`
- [x] 1.10 Anthropic API client: streaming, tool-use, **prompt caching** on system blocks; key from `flutter_secure_storage`
- [x] 1.11 `SessionBuilder`: assemble system prompt from identity + `SOUL.md` + retrieved context
- [x] 1.12 Wire real embedding model (Anthropic or local) behind the worker interface from 1.6
- [x] 1.13 Hidden dev screen: create pet "Milo", write a note, run keyword + semantic search, show results
- [x] 1.14 Unit tests: `WikiRepo` round-trip, FTS5 sync, retrieval dedup
- [x] 1.15 Phase wrap-up commit + summary

**On-device verification:** open dev screen → create Milo → write "Milo loves frozen carrots" → keyword search "carrot" returns it → semantic search "what treats does my dog like" returns it.

**STOP.** Wait for user verification before Phase 2.

---

## Phase 2 — Agent Loop & Chat MVP

**Goal:** end-of-phase = MVP. One pet, `SOUL.md`, chat that reads and writes the wiki, wiki browser, export.
**Definition of done:** add Milo → 3-turn chat that writes ≥2 entries → entries visible in wiki browser → export-zip received via Android share sheet.

- [x] 2.1 Onboarding: welcome screen, API key entry, privacy disclosure (LLM calls leave the device)
- [x] 2.2 Add-pet flow: name, species, breed, DOB → seeds `SOUL.md`
- [x] 2.3 Chat screen: message list, composer, streaming token rendering
- [x] 2.4 Multi-turn loop in `AgentLoop`: turn → tool-call(s) → tool-result(s) → continue
- [x] 2.5 Wire tools live: `read_wiki`, `search_wiki`, `write_wiki_entry`, `update_soul`
- [x] 2.6 `SessionBuilder` integration: per-turn retrieval, prompt-cached `SOUL.md`
- [x] 2.7 Wiki browser: folder tree + markdown viewer, tap to open
- [x] 2.8 `SOUL.md` editor: form for frontmatter, free-text for prose, save round-trips through `wiki_io`
- [x] 2.9 Pet switcher: schema supports many, UI gates to 1 (free-tier rule, even though no paywall yet)
- [x] 2.10 Error surfaces: API failure, rate-limit, offline — clear, retryable UI states
- [x] 2.11 Export: zip `wiki/<pet>/` → Android share sheet
- [x] 2.12 `CloudSyncAdapter` interface stub committed (no implementation; Phase 5 decides backend)
- [x] 2.13 Integration test: full happy-path chat → entry written → retrievable
- [x] 2.14 Phase wrap-up commit + summary

**On-device verification:** install fresh, onboard, add Milo, chat "Milo ate chicken yesterday and got itchy paws," verify a food/allergy entry appears in the wiki browser, export and confirm zip arrives in another app.

**MVP achieved at end of Phase 2. STOP.**

---

## Phase 3 — Skills & Synthesis

**Goal:** installable skill packs with progressive loading + species filtering; species-aware onboarding templates; weekly synthesis-mode digest.
**Definition of done:** install built-in "Puppy" skill → puppy-relevant questions show clear behavioral shift in answers → after a week of entries, a weekly digest entry appears in the wiki → adding a non-dog pet (e.g. cat) routes through a species-appropriate onboarding template and never sees dog-only skills as available.

- [x] 3.1 Skill manifest parser (YAML frontmatter, including `species:` filter list — empty/omitted = any)
- [x] 3.2 `SkillLoader`: scan installed skills, filter by active pet's species, match triggers, return matched fragments
- [x] 3.3 Inject matched fragments into next turn via `SessionBuilder` (prompt-cached)
- [x] 3.4 Onboarding templates: ship 6–8 species seeders (`dog`, `cat`, `bird`, `rabbit`, `reptile`, `fish`, `small-mammal`, `exotic`) under `assets/onboarding/`. Each is a `SOUL.md` skeleton with species-appropriate frontmatter keys + welcome prose. Add-pet flow picks the template by species choice.
- [x] 3.5 Bundle 2–3 launch skill packs under `assets/skills/`: `puppy` (`species: [dog]`), `senior-dog` (`species: [dog]`), `new-cat` (`species: [cat]`). Each follows the manifest shape from CLAUDE.md §9.
- [x] 3.6 Skill browser screen: installed / available, enable/disable, species-filtered to the active pet
- [x] 3.7 Synthesis-mode scheduled task: weekly per-pet digest written as a wiki entry
- [x] 3.8 Settings toggle for weekly digest
- [x] 3.9 Tests: species filtering, trigger matching, fragment selection, onboarding-template selection, digest entry shape
- [x] 3.10 Phase wrap-up commit + summary

**On-device verification:** add a dog pet → enable Puppy skill → ask "how do I house-train Milo," confirm response references skill content. Add a cat pet (multi-pet unlocks alongside the paywall in Phase 4, so this may need a manual schema poke for verification) → confirm dog-only skills are filtered out of the skill browser. Wait or fast-forward to confirm weekly digest appears.

**STOP.**

---

## Phase 3.5 — Product Voice & Vocabulary

**Goal:** lock the product story (PRODUCT.md), the user-facing voice (VOICE.md), and a public README before any more user-visible surface area lands. Migrate every UI string from internal architecture vocabulary (SOUL/wiki/skill/agent/synthesis) to the user-facing one (Profile/Journal/Care guide/PetPal/Weekly summary). Adopt the pet-name interpolation rule as a permanent design constraint.

**Definition of done:** PRODUCT.md, VOICE.md, README.md committed. Every screen in `lib/app/screens/` and every onboarding asset under `assets/onboarding/` reads in user voice. Tool pills show the friendly translation (`saving a memory…`), never the raw tool name. DECISIONS row 27 captures both the internal/external split and the interpolation rule. Self-verify clean.

- [x] 3.5.1 Write `PRODUCT.md` (Y-Combinator-style positioning: vision, target users, what PetPal is NOT, two-year horizon)
- [x] 3.5.2 Write `VOICE.md` (tone, AI framing, vocabulary translation table, forbidden tokens, before/after examples, pet-name interpolation rule)
- [x] 3.5.3 Replace the default Flutter scaffold `README.md` with a product-led intro that links the SemaClaw and Externalization arXiv references for the harness-engineering thesis
- [x] 3.5.4 Migrate `home_screen.dart` (Open journal / Edit profile / Care guides; greeting tagline interpolates the active pet's name)
- [x] 3.5.5 Migrate `wiki_browser_screen.dart` ("Loki's journal" app bar; "Export journal" tooltip; per-pet empty-state copy; drop the internal entry path from the tile subtitle)
- [x] 3.5.6 Migrate `wiki_entry_screen.dart` ("Journal unavailable" error)
- [x] 3.5.7 Migrate `soul_editor_screen.dart` ("Loki's profile" app bar; "About Loki" body field; per-pet hint copy)
- [x] 3.5.8 Migrate `skill_browser_screen.dart` ("Care guides" app bar; species-aware empty-state copy stays static — global screen)
- [x] 3.5.9 Migrate `settings_screen.dart` ("Weekly summary" section + switch + run-now action; static copy — global screen)
- [x] 3.5.10 Migrate `onboarding_screen.dart` (welcome subtitle + the four privacy bullets, with a single in-context AI mention per VOICE.md §2)
- [x] 3.5.11 Migrate `add_pet_screen.dart` (free-tier limit message — static, action surface not per-pet destination)
- [x] 3.5.12 Migrate `chat_screen.dart` (per-pet empty state interpolates the name; tool pills route through `_humanizeToolName(name, petName)` covering every harness tool from CLAUDE.md §7)
- [x] 3.5.13 Migrate the four affected onboarding templates: `dog.md`, `cat.md`, `bird.md`, `exotic.md` (wiki → journal; SOUL → profile; frontmatter → fields)
- [x] 3.5.14 Update tests asserting on changed strings: `widget_test.dart`, `wiki_browser_test.dart`, `skill_browser_test.dart`, `soul_editor_test.dart`, `settings_screen_test.dart`, `onboarding_screen_test.dart`, `chat_screen_test.dart`, `happy_path_test.dart`
- [x] 3.5.15 Append DECISIONS row 27 capturing both the internal/external vocabulary split and the pet-name interpolation rule as permanent design rules
- [x] 3.5.16 Phase wrap-up commit + summary; hard stop before Phase 4

**On-device verification:** not required — this phase changes copy, asset markdown, and pure-Dart string helpers only. No new runtime behaviour, no new data, no new networking, no new permissions. Existing Phase 1 + 2 device verification (DECISIONS row 21) covers the underlying surfaces.

**STOP.**

---

## Phase 4 — Scheduling & Medical Guardrails

**Goal:** zero-token reminders fire on time across all four scheduled-task modes (CLAUDE.md §8); red-flag detection runs in code before every chat turn.
**Definition of done:** set a flea-treatment reminder for tomorrow → it fires while the app is killed → typing "Milo has blood in stool" yields the verbatim vet-escalation preamble before any other content + a subdued scrollback badge on the assistant bubble.

Re-sequenced from the original 4.1–4.11 enumeration to **harness-first → platform → agent + UI**, so harness pieces ship behind unit tests before platform engines couple them to a real device. Architecture locked in DECISIONS rows 28 (four-mode taxonomy) and 29 (red-flag screener design).

- [x] 4.0 Architecture lockdown: DECISIONS rows 28+29; CLAUDE.md §8 (four-row mode table) + §10 (fixture coverage rule + chat-input scope); VOICE.md §6 (badge styling); this ROADMAP re-sequence
- [x] 4.1 Red-flag rule table — `lib/harness/guardrails/red_flags.dart` covering the 11 categories with case-insensitive word-bounded regexes; multi-symptom AND groups for `lethargy_anorexia`
- [x] 4.2 `RedFlagScreener` + AgentLoop integration — pre-screen every chat turn before the LLM call; `SessionBuilder.composeTurn` accepts `redFlag` and appends a one-shot escalation directive after the Output-contract block
- [x] 4.3 UI badge on flagged assistant bubbles — `ChatMessage.escalated` + `escalatedCategory` propagated through `ChatNotifier`; subdued scrollback styling per VOICE.md §6
- [x] 4.4 `ScheduleMode` enum + `ReminderRepo` — sealed-style enum at `lib/harness/scheduling/schedule_mode.dart` with `parse`/`serialise`; Drift CRUD over the existing `reminders` table
- [x] 4.5 `ReminderDispatcher` + add platform deps — pure-Dart dispatcher routes by mode to pluggable engines; add `flutter_local_notifications`, `android_alarm_manager_plus`, `workmanager`, `permission_handler` to `pubspec.yaml`; DECISIONS row 30
- [x] 4.6 Platform engines — `lib/platform/notifications_service.dart`, `alarm_scheduler.dart`, `work_scheduler.dart`, `scheduler_bootstrap.dart`, `scheduler_log.dart`; ProGuard keep rules wired pre-emptively; structured `petpal.scheduler` log + Android-14 exact-alarm fallback both ship here (DECISIONS row 31)
- [x] 4.7 Battery-optimization exemption prompt — `BatteryExemptionPrompt.maybeShow` (first-schedule one-shot, persisted via `SettingsStorage`) + `ScheduleHealthService` snapshot of all three Android perms (exact alarm, battery exemption, notifications)
- [x] 4.8 Deterministic notification templates + species-aware default cadences — four canonical kinds (flea +30d, heartworm +30d, vaccine +365d, weight check +14d). Defaults apply to dog/cat/rabbit/small-mammal; bird/reptile/fish/exotic surface a "no default — please set a date" state. Vaccine UI carries the canonical `vaccineUiNote` constant.
- [x] 4.9 Agent tool registrations — `schedule_reminder`, `list_reminders`, `red_flag_check` via `registerSchedulingTools` (default mode = `notification`; rejects unknown modes per DECISIONS row 28); also `lib/harness/scheduling/reminder_service.dart` facade over create+arm+cancel+list
- [x] 4.10 Reminders CRUD UI — `/reminders` route + per-pet "Loki's reminders" screen; FAB to add; swipe-to-delete; three calm health banners (battery, exact alarm, notifications); kind picker with species-aware default cadences and `vaccineUiNote`; first-save battery-exemption prompt
- [x] 4.11 Tests round-out — red-flag fixture (≥30 pos + ≥20 neg per category, all 11 categories landed across six commits), `ReminderRepo` CRUD, `ScheduleMode` round-trip, `ReminderDispatcher` routing with fakes, tool happy paths, AgentLoop screener integration, badge widget test
- [x] 4.12 Phase wrap-up commit + summary; flag **on-device verification REQUIRED**

**On-device verification (REQUIRED — cannot be substituted by `flutter test`):**
1. Type "Loki had blood in his stool last night" → confirm verbatim preamble + warning badge on the assistant bubble.
2. Type "Loki seems lethargic and won't eat" → confirm the multi-symptom AND pattern fires.
3. Type a deliberately-similar non-emergency phrase ("Loki had a great chocolate-coloured fur trim today") → confirm the screener does NOT fire.
4. Schedule a flea reminder for tomorrow 9am → confirm battery-exemption prompt shows once on first creation.
5. Force-stop the app → confirm the reminder fires at 9am.
6. Reboot the phone, schedule a +5min reminder → confirm BOOT_COMPLETED re-arm fires it.
7. From chat: "remind me to give Loki his heartworm tomorrow at 8am" → confirm `schedule_reminder` tool pill renders + reminder appears in the list + fires.
8. Disable PetPal's notification permission in system settings → fire a reminder → confirm graceful degradation (no crash, row still marks fired).

**STOP.**

---

## Phase 5 — Product Polish & Visual Identity

**Goal:** an app that looks and feels like it deserves a Play Store slot, even though feature-equivalent to current state. Build a design system (tokens + components) that Phase 6 will reuse — not just polish individual screens. Ship the locked design choices: Soft modern palette (sage primary, coral accent, warm off-white background, graphite ink), Inter body + Source Serif 4 journal accent, journal-+-paw adaptive icon. See DECISIONS row 35 for the locked design system.
**Definition of done:** every existing screen renders through the new design system; adaptive launcher icon + splash visible on a fresh install; onboarding leads with the product story, not the API key entry; every list screen has a teaching empty state; no `CircularProgressIndicator` left in `lib/app/screens/`; the three hero moments (memory saved, per-pet home greeting, weekly summary appearance) feel disproportionately polished.

- [x] 5.1 Design system tokens — `lib/app/design/` package: `ColorScheme` seeded from sage `#5C8A7A` with manual surface-tint overrides (avoid M3 lavender drift), typography theme wiring Inter + Source Serif 4 via `google_fonts`, spacing scale (`Spacing.xs/s/m/l/xl`), elevation tokens, corner radii, motion durations. Replaces `lib/app/theme.dart:1-15`. Adds `google_fonts` to `pubspec.yaml` (DECISIONS row required).
- [x] 5.2 Component primitives — `PetButton`, `PetCard`, `PetEmptyState` (illustration + heading + body + CTA slot), `PetSkeleton`, `PetSectionHeader`, `PetIcon`. Sit on top of 5.1.
- [x] 5.3 App icon (adaptive) — `flutter_launcher_icons` config: foreground = journal-+-paw mark in graphite (`#2D3436`), background = warm off-white (`#F7F5F2`). Adaptive icon for Android 8+. Source asset `assets/branding/icon-foreground.png`.
- [x] 5.4 Splash screen — `flutter_native_splash` config. Honest-dark-mirror treatment: light splash on warm off-white (`#F7F5F2`) with the graphite mark; dark splash on warm graphite (`#1F1E1C`, matching `darkSurfaceLow`) with a warm-off-white version of the same mark. Android 12+ system splash + pre-12 layer-list both wired. No animation in v1.
- [x] 5.5 Reusable layout shell — `AppScaffold` at `lib/app/widgets/app_scaffold.dart`. Three variants: basic `AppScaffold(title, body, actions?, floatingActionButton?)`, named `AppScaffold.hero(heroBuilder, ...)` for the home screen's per-pet greeting slot (anticipating 5.10), and static `AppScaffold.async<T>(value, data, loading?, error?, onRetry?)` that renders an `AsyncValue<T>` with PetSkeleton loading + PetEmptyState error defaults. Threads an optional `petAccent: Color?` through the AppBar background (8% blend) for Phase 6's photo-driven per-pet palette. Top-level `appSnackBar(context, message, {action})` helper. 9 screens migrated off the per-screen Scaffold+AppBar+SafeArea boilerplate (`home_screen`, `chat_screen`, `add_pet_screen` × 2 branches, `dev_screen`, `skill_browser_screen`, `settings_screen`, `reminders_screen` × 2, `soul_editor_screen` × 2, `wiki_entry_screen`, `wiki_browser_screen`). 19-test invariants suite at `test/app/widgets/app_scaffold_test.dart`.
- [x] 5.6 Onboarding redesign — replaced 3-page config wizard. Three forks surfaced and locked by the user: **narrative-led welcome** (journal-+-paw mark + serif tagline + concrete sensory details — vet visits, weight, missed food), **sectioned plain-English privacy** (two sub-headers — "Your pet's journal." / "When you chat." — with 1-2 sentence prose under each, plus an italic not-a-vet footer), **"One last thing — your Anthropic key"** API-key framing (utility-not-welcome). Phase-5 honesty invariant locked in tests: privacy copy describes the BYOK-only direct-to-Anthropic reality (not the Phase 7 proxy-default narrative from VOICE.md §6 example 15). Page indicator dots upgraded to `AnimatedContainer` for smooth width transitions on page change.
- [x] 5.7 Empty states — wired `PetEmptyState` across journal browser, reminders, care guides, chat. Three forks user-locked: **journal — narrative invitation** (frames the journal as where the pet's life accumulates, concrete sensory examples in prose, "Open chat" CTA), **reminders — action-first with category examples** (heartworm, flea treatment, vaccines + nudge framing, FAB-mirroring CTA), **chat — suggested prompts** (three name-interpolated ActionChips that pre-fill the composer on tap, no auto-send). Care guides empty state landed autonomously: static copy (global screen, no name interpolation per VOICE.md §5), no CTA, body explains how guides activate during chat. `wiki_browser_screen` and `skill_browser_screen` migrated to `AppScaffold.async`. `PetEmptyState` made scroll-safe with a `LayoutBuilder` + `SingleChildScrollView` pattern so tall content (chat chips) doesn't overflow short viewports. **Side-fix from 5.2:** `PetButton` was always-rendering its loading `CircularProgressIndicator` in an `AnimatedOpacity(opacity: 0)` layer, which kept the CPI's animation running indefinitely and broke `pumpAndSettle` for any screen containing a `PetButton`; switched to conditional mount of the spinner. 8 new invariants in `test/app/screens/empty_states_test.dart` pin the locked design directions + the chip→composer wiring.
- [x] 5.8 Loading & feedback — list-loading skeletons promoted to a richer `PetSkeletonListRow` composite (leading 40dp circle + 1–2 lines + optional trailing chip) per the user's enhanced-skeleton ask. `AppScaffold.async`'s default loading now uses it, so journal browser + care guides upgrade to authentic ListTile-shaped previews automatically; reminders_screen swaps both its loading branches to a shape-tuned `_RemindersSkeleton(hasTrailing: true)` matching the real row geometry (icon + 2 lines + trailing chip). Haptics: `HapticFeedback.lightImpact` wired at the three commit points (save-memory in `chat_notifier` on a successful `write_wiki_entry` tool result, schedule-reminder in `_AddReminderScreen._save`, complete-reminder in the `Dismissible.confirmDismiss` cancel path) via a new `Haptics` abstraction at `lib/app/platform/haptics.dart` (`SystemHaptics` prod; `NoOpHaptics` + `FakeHaptics` for tests, since `HapticFeedback`'s platform channel needs an initialized binding). Home greeting wrapped in `AnimatedSwitcher` (Material 3 default fade, `Motion.short`, keyed on `pet-<id>` ↔ `'empty'`) so empty→named-pet on first add and Pro pet-swap transition cleanly. 8 new invariants: `PetSkeletonListRow` factory variants (4 cases pinning the optional-leading / lines=1|2 / optional-trailing matrix), `Haptics` test seams (NoOpHaptics + FakeHaptics counter), schedule-reminder haptic fires on save commit, save-memory haptic fires on `write_wiki_entry` tool result, home greeting AnimatedSwitcher present + duration matches `Motion.short`. Manual on-device verification deferred to the Phase 5 batched check (DECISIONS row 39): the haptic vibration itself is not assertable in `flutter test`.
- [x] 5.9 Hero moment — memory saved. Two forks user-locked: **visual hero — bubble→journal bloom + snackbar** (a single-shot `Icons.menu_book_outlined` glyph rises 24dp from the chat thread's bottom edge over `Motion.long` (500ms) with a fade-in/hold/fade-out tween-sequence + heroCurve translate, echoing 5.7's narrative-empty journal icon and visually depositing the memory into the journal-book), **copy — "Saved to Loki's journal"** (direct, journalistic, journal-as-product framing). Plumbing: new `MemorySavedEvent {id, path, title}` signal on `ChatState` (monotonic id so back-to-back saves each re-fire); `ChatNotifier` parses the path from the tool result's JSON content (`{entry_id, path}` from wiki_tools.dart) on `write_wiki_entry` success and emits the event; `ChatScreen` uses `ref.listen` to detect id transitions and runs `_runMemorySavedHero` — mounts a fresh `JournalBloom` (keyed on event id, self-disposes via `onComplete`) into a Stack overlay above the message list and fires the snackbar via `appSnackBar` with a `View` action that `GoRouter.push('/wiki/entry', extra: path)` deep-links to the entry. The 5.8 `lightImpact` haptic continues to fire first; the visual lands as confirmation, not anticipation. 5 new invariants: bloom mount/unmount/onComplete/IgnorePointer, two-successive-blooms each fire, end-to-end widget test (scripted LLM tool-use → real wiki tools → snackbar copy + bloom mount + View action) in `chat_screen_test.dart`, and a `recentMemorySave` emission assertion in `chat_with_tools_test.dart`. Manual on-device verification of the bloom timing/curves and snackbar dismissal behavior batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.10 Hero moment — per-pet home greeting. Two forks user-locked: **composition — centered name on gradient sweep** (the 120dp zone above the body fills with a top→bottom `LinearGradient(primaryContainer @60% → surface)`; the pet name is centered in `displaySmall` (`onPrimaryContainer`), wrapped in `FittedBox(scaleDown)` so long names like "Mr. Whiskers" stay one line; Phase 6 will softly underlay the pet's photo as a low-opacity backdrop without removing anything from the current composition); **copy — name only** ("Loki" — the name itself, displayed prominently, IS the greeting; ages well across hundreds of home returns; lets composition do the warmth). Migrated `home_screen` to a conditional `AppScaffold.hero` (when a pet exists) / plain `AppScaffold` (empty-state path), preserving the 5.8 `AnimatedSwitcher` cross-fade in the body so empty→named-pet on first add still fades cleanly. The body drops the old `Icons.pets` + `headlineMedium` name header (those moved into the hero); tagline + button list keep their existing layout. New `_PetGreetingHero` widget keyed on `pet.id` so Pro pet-swap will animate the hero too. Tests: 1 new invariant in `widget_test.dart` ("Onboarded user with a pet sees the hero greeting") covering presence-of-hero, gradient structure (DecoratedBox + LinearGradient + 2-stop), name interpolation in body button labels ("Chat with Loki"), and absence of the legacy `Icons.pets` body header. Manual on-device verification of the gradient feel + Phase-6-photo-readiness batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.11 Hero moment — weekly summary appearance. Two forks user-locked: **register — editorial / magazine spread** (Material card on `surfaceContainer`, Radii.m corner; uppercase letter-spaced kicker `WEEKLY DIGEST` in `labelSmall` + `onSurfaceVariant`; title in Source Serif 4 via `JournalText.weeklySummaryTitle` — the dedicated 5.1 token, sized one notch larger than per-entry titles; date-range subtitle in `bodyMedium` + `onSurfaceVariant`; no body preview so the journal browser stays cheap and the entry viewer remains the place where the full markdown renders); **opening copy — possessive** ("`{pet}'s week`" — terse, pet-as-subject, lets the body do the talking; magazine kicker provides the formal anchor so the title can stay short and warm). Coheres with the 5.9/5.10 hero family by leaning on the Source Serif 4 accent (5.7 narrative empty state and 5.10 home greeting both already use the journal-as-product visual register). Date-range derivation: `entry.ts` is end-of-week per `WeeklyDigestRunner.run` (writes ts = asOf, default 7-day window); the card subtracts six days for the start. Same-month range collapses to `Apr 20–26`; cross-month range splits to `Apr 27 – May 3` (zero-pad-aware month abbrev table). New `_DigestCard` widget in `wiki_browser_screen.dart`; `_Tree` dispatches per-entry by `entry.type == 'digest'` to either the editorial card or the existing `_EntryTile`. `_Tree` now threads `petName` from the screen's existing `petsAsync` lookup. Tap-to-entry uses the same `/wiki/entry` push as regular entries via `Material > InkWell`. Tests: 2 new invariants in `wiki_browser_test.dart` — (a) digest renders as the editorial card with kicker + serif title (`Milo's week`) + abbreviated same-month range (`Apr 20–26`); the literal `Weekly digest 2026-04-26` title is NOT shown; non-digest entries keep their `ListTile` treatment; tap on the card navigates to the entry viewer; (b) cross-month digest renders the split format (`Apr 27 – May 3`). Manual on-device verification of the editorial register's feel + Source Serif 4 rendering on a real device batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.12 Per-screen polish audit. Two forks user-locked: **home button stack — 2-column card grid below the CTA** (the five OutlinedButton.icon rows — Journal / Profile / Reminders / Care guides / Settings — are replaced by a `GridView.count(crossAxisCount: 2)` of `PetCardButton` tiles, each = icon + label centered. The primary `Chat with Loki` `FilledButton.icon` stays prominent above the grid. Verbose labels collapsed to fit the tile aspect ratio: `Open journal → Journal`, `Edit profile → Profile`. Debug builds add a sixth `Dev` tile to square the grid; never in release. The grid is `shrinkWrap: true` + `NeverScrollableScrollPhysics` because the body already lives inside a `SingleChildScrollView` — nesting two scrollables would steal flings); **SOUL editor — single card with section divider** (form wraps in a single `PetCard`; `PetSectionHeader('Profile')` opens the frontmatter fields, `PetSectionHeader('About <pet>')` opens the prose `TextField`. The Save action sits outside the card so the action register stays separate from the form register. Pet name interpolated per VOICE.md §5). Two screens migrated autonomously per the design tokens: **chat composer** wraps in a `Material(color: surfaceContainer)` slab with a hairline `Divider(color: outlineVariant)` on its top edge separating it from the chat thread, plus `SafeArea(top: false)` so the composer respects gesture-bar insets; **settings** swaps the bespoke `surfaceContainerHigh` band header for `PetSectionHeader('Weekly summary')` and groups the toggle + run-now `ListTile` inside a single `PetCard(padding: EdgeInsets.zero)` with an internal `Divider` between the rows. Test fixtures updated for the new home labels (`'Open journal' → 'Journal'`, `'Edit profile' → 'Profile'`); `ensureVisible` added to `reminders_screen_test.dart` and `skill_browser_test.dart` because the taller grid pushes row-2/row-3 tiles below the 800×600 test viewport. 4 new invariants: home grid (5 tile labels + GridView crossAxisCount 2 + no OutlinedButton on home), SOUL editor (Profile + About `<pet>` PetSectionHeaders inside a Card), chat composer (Material with `surfaceContainer` color + Divider present), settings (SwitchListTile + run-now ListTile both ancestor-of Card; `Weekly summary` header preserved). Manual on-device verification of the visual lift on each screen batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.13 Microcopy pass — walked every user-facing string in `lib/app/screens/` and `lib/app/widgets/` against VOICE.md §1–§6. No forks surfaced (the rules in VOICE.md are the spec). Real wins: **(a) Journal browser type group headers** were rendering raw internal taxonomy (`food · 1`, `vet · 1`, `digest · 1`) — VOICE.md §4 forbids `digest`, §3 maps internal types to user-facing labels. New `_humanTypeLabel` table inside `wiki_browser_screen.dart` maps `digest → Weekly summary`, `vet → Vet visits`, `food → Food`, `weight → Weight`, `behavior → Behavior`, `photos → Photos`; unknown types title-case the raw key as a graceful fallback rather than leaking the lowercase token. **(b) 5.11 digest card kicker** was `WEEKLY DIGEST` (forbidden token); changed to `WEEKLY SUMMARY` per §3. **(c) Wiki entry screen AppBar** was rendering the literal filename via `path.split('/').last` (e.g., `2026-04-25-carrot-trial.md`) — exposes the file-system mechanic and directly leaks slugs / `.md`. New `_humanEntryTitle` helper parses the entry path via the existing `parseEntryPath` and renders `Memory` (no parse), `Weekly summary` (digest type per §3), or the title-case slug (everything else). **(d) Wiki entry screen + reminders screen error fallbacks** were `'Could not read entry: $e'` / `'Journal unavailable: $e'` / `'Could not load reminders: $e'` — exposing raw stack traces; rewritten to `"Couldn't load this entry."`, `"Couldn't open the journal."`, `"Couldn't load reminders."` (calm, no error tail per VOICE.md §1). **(e) Empty-state Home dev-tools button** read `Open harness · dev screen` — `harness` is forbidden in user-facing strings (§4), even on debug-only paths; relabeled to `Dev tools`. Vocabulary check confirmed every other surface already complies: skill browser AppBar `Care guides`, soul editor PetSectionHeaders `Profile` / `About <pet>`, settings switch and run-now subtitles, chat 5.9 snackbar copy, onboarding (5.6 lock), add-pet free-tier block (§6 ex 9), reminders empty state (5.7 lock). 1 new explicit invariant in `wiki_browser_test.dart` asserts the entry-screen AppBar reads `Weekly summary` (not the filename, not `Weekly digest 2026-04-26`); existing `_TypeHeader` test fixtures + happy-path test updated to the new locked strings (`Food · 1`, `Vet visits · 1`, `Weekly summary · 1`, `WEEKLY SUMMARY` kicker). Manual on-device verification of the new copy register batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.14 Skill pack content expansion. Three new bundled packs under `assets/skills/`, registered in `pubspec.yaml` so `AssetSkillSource` discovers them via `AssetManifest`: **`reactive-dog`** (`species: [dog]`, triggers cover reactive / lunging / fearful / aggression-on-leash / barking-at-other-dogs vocabulary; fragments `overview.md` (reactivity-as-stress-response framing, distance-as-cheapest-tool, body-language-reads-forward, severe-cases-need-a-DACVB), `thresholds.md` (LAT/Engage-Disengage + BAT 2.0 protocols, "always train under threshold," common owner mistakes — leash tension, prong/e-collars rejected, prevention-isn't-failure), `logging.md` (variables to capture per episode — date / location / trigger / first-notice distance / reaction intensity / recovery time / what-the-user-did, framed as "for the trainer, the vet behaviorist, and Future You")); **`senior-cat`** (`species: [cat]`, triggers cover senior cat / kidney / thyroid / weight loss / drinking-more / yowling-at-night / stopped-jumping vocabulary; fragments `overview.md` (AAFP senior-at-11 / geriatric-at-15 framing, twice-yearly vet visits, weight as the most useful number, behavior changes are medical until proven otherwise), `red-flags.md` (polyuria/polydipsia → vet this week not wait-and-see, hyperthyroidism pattern, feline osteoarthritis underdiagnosis, cognitive dysfunction syndrome differential, dental disease in seniors — calibrated to "call your vet this week" framing, never alarmist), `environment.md` (litter box low-entry + n+1, multi-level food/water stations, pet stairs / ramps / intermediate hop points, heated beds, routine-change sensitivity)); **`multi-cat`** (`species: [cat]`, triggers cover new cat / second cat / introducing / fighting / bullying / hissing / spraying / litter-box-outside vocabulary; fragments `overview.md` ("they'll work it out" rebuttal, body language reads small — staring/blocking/intercepting beats hissing/swatting, spraying-as-communication framing, pain-reshuffles-hierarchy), `introductions.md` (5-stage slow protocol — separate space → scent swap → barrier visual access → supervised time → unsupervised, restart-don't-push rule, 2–6 week timeline expectations), `resources.md` (n+1 litter box rule + plural feeding stations + vertical space + hiding spots + resource guarding signs to flag — adding resources framed as the cheapest intervention in cat behavior)). Voice across all packs matches existing puppy / senior-dog / new-cat: direct, vet-tech tone; concrete examples; action-orientation; explicit `write_wiki_entry` invocations at the points where logging unlocks pattern visibility ("over weeks, this log answers questions the owner can't otherwise hold in their head"); never diagnostic ("call your vet" framing per CLAUDE.md §10 + VOICE.md §1). Tests: 5 new invariants in `test/assets/skill_packs_test.dart` — every bundled pack's `manifest.md` parses cleanly + every fragment listed in `loads:` exists on disk (catches typos at build time, not on first user launch); each new pack pinned to its locked species filter + must-have triggers (reactive-dog: `reactive`, `lunging`; senior-cat: `senior cat`, `kidney`, `weight loss`; multi-cat: `introducing`, `fighting`); all three packs assert `requires_pro: false` (5.14 ships free-tier; Pro IAPs land in Phase 7). Manual on-device verification of skill activation in chat (does saying "Loki is reactive on leash" load the reactive-dog overview into the system prompt?) batched into the Phase 5 device check (DECISIONS row 39).
- [x] 5.15 Phase 5 wrap-up. All 14 prior tasks ticked; design system (5.1) + component primitives (5.2) + adaptive launcher icon (5.3) + branded splash (5.4) + AppScaffold layout shell (5.5, 9 screens migrated) + story-first onboarding (5.6, 3 forks user-locked) + four teaching empty states (5.7, 4 forks user-locked) + skeleton loading & haptic feedback (5.8, PetSkeletonListRow + Haptics abstraction + greeting AnimatedSwitcher) + three hero moments (5.9 memory-saved bloom + snackbar / 5.10 per-pet greeting on warm gradient sweep / 5.11 editorial digest card with Source Serif 4) + per-screen polish audit (5.12, home grid + SOUL editor card + chat composer lift + settings sectioning) + VOICE.md microcopy pass (5.13, type-label translation table + filename leak fixed + raw-error fallbacks softened) + three new species-filtered care packs (5.14, reactive-dog + senior-cat + multi-cat). Phase wrap commit closes the loop. Phase-end §14 self-verification: `flutter analyze --fatal-infos` exit 0 ("No issues found"); `flutter test --reporter expanded` exit 0 (1017 passed; +180 net new since Phase 4 close); `flutter build apk --debug` cannot run on the sandbox runner ("No Android SDK found") — the canonical APK build is the CI `release-apk` job on push-to-main or `workflow_dispatch` per DECISIONS rows 22–24, and the user-walked on-device verification (per DECISIONS row 39) lands on that artifact, not on a sandbox-built one. **On-device verification REQUIRED.** The phase ships behind no live users — this is pre-Play-Store work — but every Phase 5 task introduces runtime-visible behavior (fonts, palette, splash, launcher icon, redesigned screens, hero animations, haptics, skill packs) that headless tests can pin in shape but not in feel. Walkthrough script is locked in DECISIONS row 39's "Phase boundary action" — eight-step checklist covering cold launch, welcome flow, home greeting + grid, every list screen's empty state + skeleton, save-memory hero, weekly summary card the morning after a digest fires, microcopy spot-check + care guides species filter, and a system-theme toggle. **Hard stop here.** Phase 6 (feature depth — photo capture, multimodal chat, weight/symptom charts, vet-visit structured entries, smarter weekly summary, monthly health report) does not auto-start. Trigger CI on `claude/petpal-planning-S9DXN`; sideload the resulting `petpal-release-arm64-v8a.apk`; report any visual or interaction regressions. Fix-then-recommit before Phase 6 begins.

**On-device verification (REQUIRED):**
1. Cold launch → adaptive launcher icon visible on home screen + branded splash → arrives on the redesigned welcome page (not API key entry).
2. Walk through onboarding → confirm story-first welcome, privacy disclosure, API key framed as utility.
3. Open every screen → confirm new design system applied (palette, typography, no stray Material defaults).
4. Save a memory → confirm hero moment fires (snackbar + haptic + animation).
5. Open journal browser the morning after a weekly digest fires → confirm distinct card treatment.
6. Confirm three hero moments feel disproportionately polished vs the rest of the app.

**STOP.**

---

## Phase 5.5 — Identity Foundations

**Goal:** lock the species/breed/identity model that Phase 6 vision extraction and the long-tail user base depend on. Replace the eight-template species picker with a curated two-tier model — `category` ∈ {dog, cat, bird, rabbit, reptile, fish, small-mammal, exotic} (the existing onboarding template axis) + a `species` text field selected from a hand-coded curated list of ~600+ entries with iNat taxon IDs preserved per row for future enrichment. Expand the add-pet form from name/species/breed/DOB to a richer identity scaffold (DOB / approximate-age / adoption-date toggle, weight, sex, neutered, "What should PetPal know," variety with conditional rendering, **relationship picker shown to every user with "Pet" pre-selected**, conditional sub-classification picker per relationship). Land 4-value `relationship` enum (`pet` / `rescue-rehab` / `permanent-wildlife` / `wildlife-observation`) + three optional sub-classification fields (`working_role` / `rehab_context` / `care_context`) + relationship-conditional frontmatter (`intake_date`, `expected_release_date` when rescue-rehab) + template body forks per relationship. Online iNat API fallback deferred to v1.2 candidate scope. See DECISIONS rows 42 (strategic insertion + rationale), 43 (concrete locked picks — curation, fallback, onboarding prompt; wild_or_domestic + Wildlife-toggle aspects superseded by 44), 44 (relationship as first-class question; species data is pure taxonomy; no Wildlife mode toggle), 45 (three sub-classification fields).

**Definition of done:** add-pet flow uses the searchable curated species picker (~600+ entries across all 8 categories, wildlife included); SOUL.md frontmatter writes `category:` + `species:` + `relationship:` + relationship-appropriate sub-classification field (replacing the legacy single `species:`); the 6 bundled skill manifests use `category:` filter; "Other" freeform fallback works for users whose species isn't in the curated list; relationship picker shows for every user with "Pet" pre-selected; rescue-rehab relationship reveals `intake_date` + `expected_release_date` fields conditionally; PRODUCT.md acknowledges wildlife rehab as a peer use case; v1.2 candidate scope grows by the iNat API fallback bullet. Self-verify clean.

- [x] 5.5.1 Two-tier model rename — `species:` → `category:` across SOUL frontmatter writers, skill manifest parser, `matchesSpecies` → `matchesCategory`. Migrated the 6 bundled skill packs (`puppy`, `senior-dog`, `new-cat`, `reactive-dog`, `senior-cat`, `multi-cat`) + the 8 onboarding templates (`dog/cat/bird/rabbit/reptile/fish/small-mammal/exotic.md`). Renamed `Species` enum → `Category` and propagated through `add_pet_screen`, `soul_editor_screen`, `reminders_screen`, `dev_screen`, `providers`, `session_builder`, `weekly_digest`, `reminder_kinds`, `wiki_tools` description, and 17 test files. Lockstep refactor: manifests + parser + writers + tests all changed in this commit; no backwards-compat shim, no dual-key reads (PetPal hasn't shipped — pre-launch wipe-and-retry beats migrate). `flutter analyze --fatal-infos` exit 0 ("No issues found"); `flutter test` exit 0 (1017 passed; same count as Phase 5 close). Two-tier `species:` (precise label) + `variety` + the rest of the canonical frontmatter key order land in 5.5.4 + 5.5.5.
- [x] 5.5.2a Curated species JSON — **dog batch**. Hand-coded 81 entries: canonical Dog (any breed) + Mixed breed (mutt) + 79 popular AKC-recognized breeds across all 7 groups + 5 designer mixes (Goldendoodle, Labradoodle, Cockapoo, Cavapoo, Puggle). All Canis familiaris / iNat 47144. `assets/species/dog.json`. Schema (post-DECISIONS row 44 cleanup): `{display_name, scientific_name, category, inat_taxon_id, common_alternatives}`.
- [x] 5.5.2b Curated species JSON — **cat batch**. 39 entries: Cat (any breed) + Domestic Shorthair / Longhair / Mediumhair (carrying tabby / calico / tortie / moggie alternatives) + 35 CFA/TICA-recognized pure breeds. All Felis catus / iNat 118552. `assets/species/cat.json`.
- [x] 5.5.2-rabbit Curated species JSON — **rabbit batch** (inserted: coverage gap caught at 5.5.2c authoring — rabbit is one of the 8 onboarding categories but was missed in the original a–h split). 39 entries (was 40; "European Rabbit (wild)" duplicate dropped at DECISIONS row 44 schema cleanup): canonical pet rabbit + 32 ARBA-recognized pet breeds + 6 wild rabbit/hare species for rehab use (Eastern / Desert / Mountain Cottontail, Snowshoe Hare, Black-tailed Jackrabbit, European Hare). `assets/species/rabbit.json`. Wild-vs-pet distinction now lives in the 5.5.4 relationship picker, not on the species row.
- [x] 5.5.2c Curated species JSON — **small-mammal batch**. 75 entries: 33 domestic (12 guinea pig varieties, 6 hamster species, 5 rat varieties, 2 mice, 2 gerbils, 2 chinchillas, degu, prairie dog, ferret, 3 hedgehog species, sugar glider) + 40 wildlife rehab (squirrels, chipmunks, marmots, opossum, skunks, raccoons, mustelids, river otter, beaver, muskrat, nutria, voles, moles, shrews, pika, bats). `assets/species/small-mammal.json`.
- [x] 5.5.2d-i Curated species JSON — **bird batch i — pet parrots and parakeets**. ~40–50 entries: budgies, cockatiels, conures, African greys, macaws, amazons, lovebirds, lories/lorikeets, eclectus, pionus, parrotlets, caiques, senegals, rosellas, ringnecks, monk parakeets. Adds entries to `assets/species/bird.json` (file accumulates across d-i…d-v).
- [x] 5.5.2-tier1-dog Tier 1 breed-list refactor — **dog**. Collapse dog.json from 81 species rows (all `Canis familiaris`, authored under the breeds-as-species shape error per DECISIONS row 46) to **1 species row** (`Dog`) with a ~80-entry `breeds` array. Sentinel ordering: `Mixed breed` first, `Not sure` second, AKC + UKC + FCI breeds alphabetical, designer crosses (Goldendoodle, Labradoodle, Cockapoo, Cavapoo, Maltipoo, Yorkipoo, Schnoodle, Puggle, Chiweenie, Pomsky, Shorkie, etc.) after a section separator, `Other` last. All 79 current breed-rows' display_names + their `common_alternatives` consolidate into the breeds array. Wild canids (coyote, gray wolf, red fox, etc.) NOT added in this task — they land in 5.5.2h wildlife pass. Per DECISIONS row 46.
- [x] 5.5.2-tier1-cat Tier 1 breed-list refactor — **cat**. Collapse cat.json from 39 species rows (all `Felis catus`) to **1 species row** (`Cat`) with a ~38-entry `breeds` array. Sentinel ordering same as dog (Mixed breed / Not sure / CFA + TICA + WCF breeds / Other; cats have minimal designer-cross population — skip the section separator). DSH/DLH/DMH alternatives (tabby/calico/tortie/moggie etc.) consolidate into the species row's `common_alternatives`. Wild felids (bobcat, lynx, wildcat, etc.) NOT added — 5.5.2h wildlife pass.
- [x] 5.5.2-tier1-rabbit Tier 1 breed-list refactor — **rabbit**. Collapse rabbit.json from 39 species rows to **7 species rows** — 1 canonical pet `Rabbit` (`Oryctolagus cuniculus`) with ~32-entry `breeds` array (ARBA-recognized breeds + the Mixed breed / Not sure / Other sentinels) + 6 wild lagomorph species (Eastern / Desert / Mountain Cottontail; Snowshoe Hare; Black-tailed Jackrabbit; European Hare) which stay as separate species rows with `breeds: null` (wild species, no registry).
- [x] 5.5.2-tier1-sm Tier 1 breed-list refactor — **small-mammal**. Two collapses: (a) 12 `Cavia porcellus` rows → **1 Guinea Pig species row** with ~12-entry `breeds` array (ACBA + BCC pet guinea pig breeds + Mixed breed / Not sure / Other sentinels); (b) 5 `Rattus norvegicus` rows → **1 Rat species row** (no `breeds` array — rats not Tier 1; the 4 variety names "Dumbo," "Rex," "Hairless," "Manx" fold into `common_alternatives`). 58 other species rows unchanged. Net 75 → 59 species rows.
- [x] 5.5.2d-ii Curated species JSON — **bird batch ii — pet songbirds, finches, doves**. ~25–35 entries: canary, society finch, zebra finch, gouldian finch, java finch, owl finch, spice finch + diamond dove, ringneck dove, fancy pigeon variants. Appends to `assets/species/bird.json`.
- [x] 5.5.2d-iii Curated species JSON — **bird batch iii — poultry / backyard fowl + Tier 1 chicken `breeds` array**. ~10–15 species rows: chicken (`Gallus gallus domesticus`) as a Tier 1 species with a ~80-entry `breeds` array covering APA Standard of Perfection breeds (Rhode Island Red, Plymouth Rock, Leghorn, Orpington, Silkie, Wyandotte, Sussex, Australorp, Marans, Brahma, Bantam variants, Sex Links, ISA Browns, etc.) + sentinels; plus separate species rows for ducks (`Anas platyrhynchos domesticus`: Pekin, Khaki Campbell, Indian Runner, Muscovy as breed alternatives or breed entries — TBD at authoring), goose, turkey, quail (`Coturnix japonica`), guinea fowl, peafowl. Appends to `assets/species/bird.json`. Per DECISIONS row 46 chicken is the 5th Tier 1 species.
- [x] 5.5.2d-iv Curated species JSON — **bird batch iv — wildlife: raptors and waterfowl for rehab**. ~25–35 entries: Red-tailed Hawk, Cooper's Hawk, Sharp-shinned, Harris's Hawk, Great Horned Owl, Barn Owl, Eastern/Western Screech Owl, Barred Owl, Bald Eagle, Turkey Vulture, Black Vulture, American Kestrel, Peregrine Falcon, Merlin + Mallard, Canada Goose, Wood Duck, Great Blue Heron, Great Egret, Snowy Egret, pelicans. Appends to `assets/species/bird.json`.
- [x] 5.5.2d-v Curated species JSON — **bird batch v — wildlife: common rehab songbirds, corvids, passerines**. ~20–30 entries: American Robin, Northern Cardinal, Blue Jay, Steller's Jay, House Sparrow, European Starling, House Finch, Mourning Dove, American Goldfinch, American Crow, Common Raven, Black-billed Magpie, plus the most-encountered rehab passerines. Closes out `assets/species/bird.json`.
- [x] 5.5.2e Curated species JSON — **reptile batch**. ~80–100 entries: lizards (bearded dragon, leopard gecko, blue-tongue skink, monitors, iguanas, anoles), snakes (corn, ball python, kingsnake, boa, retic), turtles + tortoises (red-eared slider, Russian tortoise, Sulcata, box turtles), amphibians (frogs, salamanders, axolotls if not slotted to exotic). `assets/species/reptile.json`. **Subdivide if entry count crosses ~80 at authoring time** per the stream-timeout-shape protocol.
- [x] 5.5.2f Curated species JSON — **fish batch**. **Bumped to ~120–150 entries** — aquarium hobbyists are a real population and fish species diversity is huge. Freshwater (betta, goldfish varieties, tetras, cichlids — African + South American + dwarf, catfish/plecos, gouramis, livebearers — guppies/mollies/platies/swordtails, killifish, anabantoids — bettas/paradise fish, barbs, danios, rasboras, loaches, rainbowfish, gobies); saltwater (clownfish + Amphiprion species, tangs, dottybacks, wrasses, gobies, blennies, cardinalfish, anthias); invertebrates (cherry shrimp + Neocaridina/Caridina species, amano shrimp, mystery snails, nerite snails, hermit crabs if water-kept, common coral genera if scope allows). `assets/species/fish.json`. **Subdivide into 5.5.2f-i (freshwater) and 5.5.2f-ii (saltwater + inverts)** if author-time count crosses ~80 per stream-timeout-shape protocol.
- [x] 5.5.2g Curated species JSON — **exotic + ambiguous batch**. ~50–80 entries: tarantulas, scorpions, hermit crabs, snails, isopods, axolotls if cross-routed, capybara, domestic skunk, sugar gliders if cross-routed, hedgehog if cross-routed, wallaby/kangaroo, fennec fox, serval, civet, primates if commonly kept, etc. `assets/species/exotic.json`. **Subdivide if entry count crosses ~80** per stream-timeout-shape protocol.
- [x] 5.5.2h Wildlife coverage pass — **explicit scope, ~55–70 entries across multiple category JSONs.** Per the user-locked scope (in the row 46/47 commit), this pass adds genuinely-missing wildlife species that earlier batches deferred. Per-file additions: **dog.json** (~7 wild canids: Coyote `Canis latrans`, Gray Wolf `Canis lupus`, Red Fox `Vulpes vulpes`, Gray Fox `Urocyon cinereoargenteus`, Arctic Fox `Vulpes lagopus`, Kit Fox `Vulpes macrotis`, Dingo `Canis lupus dingo`); **cat.json** (~7 wild felids: Bobcat `Lynx rufus`, Canada Lynx `Lynx canadensis`, Eurasian Lynx `Lynx lynx`, Wildcat `Felis silvestris`, Serval `Leptailurus serval`, Ocelot `Leopardus pardalis`, Mountain Lion `Puma concolor`); **rabbit.json** (~3 additional Sylvilagus / Brachylagus: Marsh Rabbit `Sylvilagus palustris`, Swamp Rabbit `Sylvilagus aquaticus`, Pygmy Rabbit `Brachylagus idahoensis`); **small-mammal.json** (~3 missing wildlife: North American Porcupine `Erethizon dorsatum`, American Badger `Taxidea taxus`, Sea Otter `Enhydra lutris`); **reptile.json** (~12 wild amphibians: American Bullfrog, Green Frog, Leopard Frog, Wood Frog, Spring Peeper, Gray Treefrog, American Toad, Eastern Newt, Tiger Salamander, Spotted Salamander, Marbled Salamander, Hellbender); **exotic.json** (~25: ungulates — White-tailed Deer / Mule Deer / Black-tailed Deer / Elk / Moose / Pronghorn / Bighorn Sheep / Bison; pinnipeds — Harbor Seal / Gray Seal / Northern Elephant Seal / California Sea Lion / Harbor Porpoise; bears — American Black Bear / Brown (Grizzly) Bear / Polar Bear; marsupials beyond Virginia Opossum — Brushtail Possum / Ringtail Possum / Eastern Grey Kangaroo / Red Kangaroo / Koala / Wombat; misc — Nine-banded Armadillo). All entries follow the simplified schema (no `wild_or_domestic` per DECISIONS row 44; no `breeds` — wild species without registries). Single commit appending across all 6 affected JSON files. Subdivide into per-file commits if author-time count crosses ~80 per stream-timeout-shape protocol.
- [x] 5.5.3 Searchable species picker sheet — modal opened from the add-pet category step. In-memory trigram + prefix search across the active category's JSON (loaded lazily per category on tap). **Cross-category search suppressed** per DECISIONS row 46 — the search dataset is scoped to the user's category pick at the top level (categories are committed structural choices that drive skill filtering / SOUL template / frontmatter shape, not just search filters). User who picks the wrong category backs out and repicks (two taps, no new UI). Tile renderer: default `Display name / italic Scientific name`; when search hit on `common_alternatives` rather than `display_name`, surface the matched alternative — `Display name (also: matched alt) / italic Scientific name`. Tail row: `Other (type your own)` → freeform fallback (5.5.6). **No disambiguation prompt** — every species can take any relationship; the relationship picker (5.5.4) handles wild-vs-domestic per pet, not per species. **Tier 1 species (5: Dog/Cat/Rabbit/Guinea Pig/Chicken) reveal a secondary breed picker** on selection. Per DECISIONS row 48 the breed picker reads `breeds: {name, alternatives[]}[]` — search matches against breed `name` AND any entry in `alternatives[]`; picker tile shows breed name as primary; when search hit on `alternatives` rather than `name`, tile renders `Labrador Retriever (also: Lab)` (same matched-alternative surfacing pattern as species-level). Sentinels (`Mixed breed`, `Not sure`) at top, registry breeds alphabetical, designer crosses with section separator, `Other` (freeform) at bottom. Non-Tier-1 species fall through to the existing variety/breed text field per 5.5.4. Per DECISIONS rows 46 + 48.
- [x] 5.5.4 Add-pet form expansion — **relationship picker shown to every user** (4 values: `pet` default, `rescue-rehab`, `permanent-wildlife`, `wildlife-observation`; friendly labels per VOICE.md §5.5: "Pet" / "Rescue / rehab" / "Permanent wildlife" / "Wildlife observation"); **conditional secondary picker** based on relationship (per DECISIONS rows 45 + 47: `working_role` 7 values when relationship=pet — `none` (default, "companion") / `service` / `esa` / `therapy` / `working` / `breeding` / `other`; `rehab_context` 9 values when relationship=rescue-rehab — `none` / `foster` / `medical` / `behavioral` / `palliative` / `neonatal` / `conditioning` / `quarantine` / `other`; `care_context` 5 values when relationship=permanent-wildlife — `none` / `sanctuary` / `educational` / `non-releasable` / `other`; no secondary when relationship=wildlife-observation; each defaults to `none` and omits the field from SOUL frontmatter on disk); **conditional rescue-rehab fields** (`intake_date` + `expected_release_date`) when relationship=rescue-rehab; **Tier 1 breed picker** when category × species lands on a Tier 1 species (Dog/Cat/Rabbit/Guinea Pig/Chicken per DECISIONS row 46 — sentinels first, registry breeds alphabetical, designer crosses after a section separator, `Other` last with freeform fallback); DOB / approximate-age / adoption-date toggle (mutually exclusive, exactly one required); weight (kg/lb unit-aware, optional); sex (male / female / unknown); neutered (yes / no / unknown); "What should PetPal know about your pet?" optional multiline free text (populates SOUL body second paragraph); variety with conditional rendering per category for non-Tier-1 species (e.g., reptile picks "ball python" → variety field shows "morph" label; bird picks "cockatiel" → variety field shows "color mutation"). Replaces the current 4-field form. Absorbs the wildlife-mode-toggle work that was 5.5.7 in the prior plan (DECISIONS row 44).
- [x] 5.5.5 SOUL template enrichment — onboarding template files migrate to the rich frontmatter shape; canonical SOUL key order extended per DECISIONS row 45: `category, species, variety, breed, sex, neutered, relationship, working_role, rehab_context, care_context, dob, dob_approx, adoption_date, intake_date, expected_release_date, weight_kg, allergies, meds, vet_contact, temperament`. `soul_file.dart` keyOrder constant updated. Body forks on `relationship` (4 branches: `pet` reuses existing welcome prose; `rescue-rehab` opens with intake circumstances + expected release framing; `permanent-wildlife` opens with non-releasable rationale + permanent care framing; `wildlife-observation` opens with observation setup + non-intervention framing). The "What should PetPal know" field from 5.5.4 inserts as the body's second paragraph regardless of relationship.
- [x] 5.5.6 "Other" freeform fallback — picker tail row routes to a freeform text field. SOUL writes `category: exotic` + `species: <user-typed-text>`; skill loader treats `exotic` category normally; `inat_taxon_id` is null for freeform entries (v1.2 fallback API will optionally enrich on first online connection per PRODUCT.md v1.2 candidate scope). Relationship picker still shows; freeform species can take any relationship.
- [x] 5.5.7 Phase wrap-up commit + summary; on-device verification REQUIRED. (Was 5.5.8; renumbered after 5.5.7 wildlife-mode merged into 5.5.4 per DECISIONS row 44.)

**On-device verification (REQUIRED — cannot be substituted by `flutter test`):**
1. Add a pet → confirm category-step grid (8 tiles) renders → tap one → confirm searchable species picker sheet opens → search returns expected matches with display name + italic scientific name + common alternatives. Confirm picker has **no** wild-vs-domestic disambiguation prompt (DECISIONS row 44).
2. Pick a curated species → confirm SOUL.md writes `category:` + `species:` + `relationship:` in canonical key order. (No backwards-compat path — pre-launch wipe-and-retry per DECISIONS row 43.)
3. Pick the "Other" tail row → type a custom species → confirm SOUL writes `category: exotic` + the typed species; `inat_taxon_id` field is null.
4. Walk the rich add-pet form → confirm DOB / approximate-age / adoption-date toggle is mutually exclusive (exactly one required); weight unit toggle (kg/lb) works; "What should PetPal know" lands in SOUL body second paragraph; variety field renders the conditional label per category.
5. Confirm relationship picker shows for every user with **"Pet" pre-selected**; saving without touching it leaves SOUL frontmatter `relationship: pet` and writes nothing to working_role/rehab_context/care_context (defaults to `none`, omitted on disk).
6. Switch relationship to **Rescue / rehab** → confirm `rehab_context` secondary picker reveals (9 values: none / Foster / Medical / Behavioral / Palliative / Neonatal / Conditioning / Quarantine / Other per DECISIONS row 47) → confirm `intake_date` + `expected_release_date` fields render and save to SOUL frontmatter.
7. Switch relationship to **Pet** → confirm `working_role` picker reveals (7 values: none / Service / ESA / Therapy / Working / Breeding / Other per DECISIONS row 47); pick `service` and confirm SOUL frontmatter writes the field. Switch to **Permanent wildlife** with `care_context: sanctuary` → confirm `care_context` picker reveals (5 values incl. none). Switch to **Wildlife observation** → confirm **no** secondary picker shows.
7a. Tier 1 breed picker — pick category Dog → species Dog → confirm breed picker reveals with Mixed breed / Not sure at top, registry breeds alphabetical, designer crosses (Goldendoodle, Labradoodle, etc.) after a section separator, Other at bottom. Same for Cat / Rabbit / Guinea Pig / Chicken. Pick a non-Tier-1 species (e.g., Bearded Dragon) → confirm freeform variety text field reveals instead.
8. Confirm Settings has **no** Wildlife mode toggle (DECISIONS row 44 dropped it).
9. Confirm app-bar titles stay relationship-agnostic per VOICE.md §5.5: a rescue pet's journal still reads "Loki's journal" — never "Loki's rehab journal."
10. Confirm a dog-only skill (`puppy`, `senior-dog`, `reactive-dog`) is filtered OUT for a cat pet; confirm a `category: [dog, cat]` skill matches both.

**STOP.**

---

## Phase 5.6 — Feel Polish

**Goal:** close the visible gap between PetPal's harness/architecture quality (1079 tests, three-layer memory, 4-context body fork, 518 species rows) and the surface, before Phase 6 photo-capture work begins. Hard-scoped 7-item polish pass — no expansion permitted. Three commits along natural boundaries (foundation / icons / motion). See DECISIONS rows 50 (insertion + locked scope), 51 (shadcn rejection), 52 (form validation + ListView lazy-mount learning from Bug 1 fix). Two P0/P1 bug fixes from Phase 5.5 on-device verification (commits 718daa9 + 4e3b56f) ship under this phase's umbrella as foundation-cleanup; the empty-name guard pattern + the SingleChildScrollView+Column rule for forms are the durable Phase-5.6+ defaults.

**Definition of done:** the surface no longer reads as "MVP with great architecture." Default Material 3 ColorScheme.fromSeed tones, default Material Icons, default linear curves, default page transitions, and default modal sheet physics are all gone. Sage palette renders with proper M3 tonal harmony; icons render as Phosphor regular; hero moments use spring physics; `/wiki/entry` route uses a Material shared-axis transition; modal sheets feel modern-Android via `StretchingOverscrollIndicator`. PetButton tap has the ~98% scale press affordance with spring-back. Self-verify clean.

- [ ] 5.6.A Foundation / token-layer — `flex_color_scheme: ^8.4.0` adopted via `FlexColorScheme.light(...).toScheme` / `.dark(...).toScheme` with tonal harmony on the sage primary + coral tertiary anchors; manual `PetPalColors` surface overrides re-applied last so the locked DECISIONS row 35 hex values stay pinned. `Motion.springCurve` (Curve adapter over `SpringSimulation(stiffness: 180, damping: 22, mass: 1)`, damping ratio ≈ 0.82, settles in ~600 ms) and `Motion.springDescription` exposed for callsites that take raw physics. DECISIONS rows 50 + 51 + 52 land here. ROADMAP gets this Phase 5.6 entry. Test impact: 0–2 fixture updates (no goldens in the project; theme tokens stay byte-identical via the manual overrides).
- [ ] 5.6.B Icon migration — `phosphor_flutter: ^2.1.0` adopted; 32 unique `Icons.*` callsites across 53 references migrate to PhosphorIcons regular weight. Three locked refinements vs the default regular swap (per DECISIONS row 50): `Icons.warning_amber_rounded` (medical red-flag escalation badge) → `PhosphorIcons.warningOctagon()` rather than `.warning()` — medical safety context warrants visual weight; on-device verification gates whether to escalate this single icon to filled weight. `Icons.key_off` → `PhosphorIcons.keySlash()` (literal equivalent for "API key invalid"). `Icons.menu_book_outlined` → `PhosphorIcons.bookOpen()` rather than `.book()` — open-book reads as journal aesthetic; closed-book reads as library shelf. Phosphor weight UX call: regular everywhere for v1; fallback path lifts specific AppBar callsites to bold only if on-device verification surfaces optical-thinness. `pet_icon.dart` extends to accept `IconData` (Phosphor's icons are `IconData`-compatible so the equality-based test finders keep working). 9 test files' `find.byIcon` calls update to the Phosphor equivalents. Test impact: mechanical, ~30 byIcon line edits.
- [ ] 5.6.C Motion adoption — `flutter_animate: ^4.5.2` and `animations: ^2.2.0` (Google's official) adopted. JournalBloom rewrite from manual AnimationController + TweenSequence to a flutter_animate chain (same choreography, declarative form). Home greeting hero gets a subtle scale-in on first appear keyed off pet name change. Weekly summary card distinguishes from regular journal entries with mount motion as well as visual treatment. Three AnimatedSwitcher callsites in the add-pet form (relationship sub-classification reveal, lifecycle date kind swap, rescue-rehab dates reveal) plus the home-greeting hero-switch get spring-curve transitions via `Motion.springCurve`. PetButton press physics via `AnimatedScale` between 1.0 (rest) and 0.98 (pressed) wrapped at the inner `_PetButtonContent` level so all three variants inherit; spring-back on release. Modal sheet + scrollable refinement via `StretchingOverscrollIndicator` (Android 12+ native stretch behavior — user-locked direction supersedes both the original `BouncingScrollPhysics` proposal and the `AlwaysScrollableScrollPhysics`+glow fallback per DECISIONS row 50): audit every scrollable, identify M3-default inheritors, wrap the rest. Mandatory wraps: both modal sheets (species + breed pickers). Audit-driven wraps: any other `ListView` / `CustomScrollView` that doesn't already get stretch via M3. Page transition: `/wiki/entry` route gets `SharedAxisTransition` (X axis) via `GoRoute.pageBuilder:` to convey "drilling deeper into the same content"; other routes stay on `PredictiveBackPageTransitionsBuilder`. Test impact: medium — journal_bloom_test and pet_button_test get fixture rewrites; 1–2 new fixtures for press-scale and the stretch wrappers.
- [ ] 5.6.D Phase wrap-up commit + summary; on-device verification REQUIRED.

**On-device verification (REQUIRED — cannot be substituted by `flutter test`):**
1. Light theme renders with sage primary, coral tertiary, warm-cream surfaces; no lavender drift on derived surfaces. Dark theme renders with warm-graphite surfaces; sage primary still recognizable; no cool-grey M3 default.
2. Icons render as Phosphor regular across every screen — Home grid tiles, AppBar actions, chat composer Send, reminders cards, Settings rows, wiki browser, soul editor. Verify the three locked refinements: medical escalation badge uses `warningOctagon` (verify it reads urgently enough; flag if it doesn't and bump to filled); API-key-invalid surface uses `keySlash`; journal context uses `bookOpen`. Check AppBar icons specifically for optical-thinness against the AppBar surface — if any feel too thin, that single callsite goes to bold; otherwise stay regular everywhere.
3. Memory-saved hero (chat → write_wiki_entry) — JournalBloom plays the rise + fade choreography with spring physics; settles cleanly without overshoot bounce. Haptic still fires.
4. Home greeting hero — pet name renders with subtle scale-in on first appear; switching pets re-triggers (free tier ships with 1 pet so this is mostly the cold-start surface).
5. Add-pet form — relationship sub-classification reveal, lifecycle date kind swap (DOB / Approx age / Adoption), and rescue-rehab dates reveal all swap with spring transitions (not linear cross-fade). PetButton press affordance: tap any `PetButton` and confirm the ~98% scale press-down with spring-back on release. No layout shift on neighboring widgets.
6. Modal sheets — open species picker, drag the sheet body past its end-of-list. Confirm the Android 12+ stretch behavior (content stretches and snaps back) rather than the old clamp + glow. Same for breed picker.
7. Page transition — tap a journal entry from the wiki browser. Confirm shared-axis (X) transition rather than the default Material slide-up.
8. Phase 5.5 surfaces still work — add a pet end-to-end (Bug 1 fix + Bug 2 defensive empty-name handling held); empty-name pet (if force-induced via DB write) renders "Your pet" fallback with no orphan apostrophe in tagline or trailing space in chat CTA.

**STOP.**

---

## Phase 6 — Feature Depth & AI Capabilities

**Goal:** take the app from "personal AI agent for pets, basic" to "personal AI agent for pets, sophisticated." Foundation → photo-as-memory loop → capability features that consume them. Tier 2 expansion locked in DECISIONS rows 40 + 41 (April 2026): photo-as-memory becomes a primary input surface, structured vision-extraction with inline-editable form preview, memory-grounded affective observations, vision red-flag screener integration. Multimodal input is constrained to "describes what it sees, never diagnoses" per DECISIONS rows 25 + 29.
**Definition of done:** "I'd pay $7.99/mo for this" is a credible reaction. Photos are first-class wiki entries with a dedicated capture flow, vision-extracted form preview, and a timeline view; vet visits have structured frontmatter that auto-creates follow-up reminders; weight + recurring-symptom charts surface on the profile; weekly summary surfaces trends and anomalies, not just a recap; affective observations occasionally surface alongside saves but only when grounded in a retrieved prior memory.

- [x] 6.1 Photo storage layer — per CLAUDE.md §5, photos are `wiki/<pet_id>/photos/<id>.jpg + <id>.md`. Implement `WikiRepo` extension to write image bytes + sidecar markdown atomically. The `.jpg` binary lives next to the `.md` sidecar; only the sidecar is indexed as an `Entry` (referenced from the sidecar's frontmatter `image: <uuid>.jpg`). FTS5 indexes the sidecar caption. Storage budget cap (warn at 500 MB per pet, hard limit 1 GB v1). Pre-write 2048px-on-long-edge resize lands at task 6.6 to keep the budget honest (~600 KB per saved photo).
- [x] 6.2 Pet profile photo — single photo on the SOUL profile. Lands on **both** the home greeting backdrop (low-opacity image underlaying the 5.10 gradient sweep at ~25% so the displaySmall name stays legible) AND the chat AppBar (small circular avatar next to "Chat with Loki"). Validates the storage layer with two visible payoffs. Per DECISIONS row 41 lock.
- [x] 6.3 Photo timeline screen + photo entry viewer — `/photos` route, time-ordered grid of every photo across the pet's wiki. Tap a photo entry → screen renders the image at full size + the sidecar's extracted fields + freeform caption. The current `WikiEntryScreen` is text-only; photos need image rendering — that's the **scope expansion** vs the original 6.3. Reuses Phase 5 design system.
- [x] 6.4 **NEW** — Multimodal request path + VisionGate stub. Add `ImageBlock` to the `ContentBlock` sealed class in `lib/harness/agent/messages.dart`; extend `_encodeBlock()` in `lib/harness/agent/anthropic_client.dart` (lines 310–329) to emit `{type: 'image', source: {type: 'base64', media_type: 'image/jpeg', ...}}` with `cache_control: ephemeral` for prompt-cache eligibility on multi-image conversations; `VisionGate.check()` stub returns "always allowed" in Phase 6 per DECISIONS row 36. Both 6.5 (extractor) and 6.9 (chat upload) call through `VisionGate`. Phase 7 task 7.10 plugs in real Pro entitlement + photo-credit-balance enforcement without a code re-shape.
- [x] 6.5 **NEW** — Photo extractor utility + structured prompt. New `lib/harness/vision/photo_extractor.dart` — direct utility (NOT a registered tool — the camera flow doesn't need agent reasoning, the form wants typed data). Locked schema per DECISIONS row 41: `{setting: enum (home / outdoors / vet / grooming / car / other), activity: enum (resting / playing / eating / grooming / walking / exam / other), demeanor: optional hedged string ("looks relaxed"), notable_objects: [string], freeform_caption: string, enrichment_hints: [optional follow-up question strings]}`. System prompt forbids diagnosis (mirrors 6.9 chat constraint) and requires hedging on demeanor. Model: `claude-sonnet-4-6` (DECISIONS row 41). Unit tests with mocked LLM responses pin the JSON shape.
- [x] 6.6 **NEW** — Camera-as-memory capture flow + inline-editable form preview + save. Home grid gets a 6th tile (top-left position, displacing Journal): `Add photo` (`Icons.add_a_photo`). Tap → `image_picker` system camera or gallery → photo-displayed screen with `PetSkeletonListRow` form fading in → extractor (6.5) fires in parallel → fields populate → user edits inline (every field is a TextField/Dropdown from first view, per DECISIONS row 41 — no read-only review mode) → enrichment hints from the extractor surface as additional optional rows the user can fill or skip → Save writes `wiki/<pet>/photos/<uuid>.jpg` + `<uuid>.md`. Pre-write 2048px-on-long-edge resize. Optimistic UI: typing wins over extractor prefill; extractor failure or >15s timeout falls back to bare freeform caption. Save never blocks on extraction.
- [x] 6.7 **NEW** — Vision red-flag screener integration. Extend `RedFlagScreener` with `screenWithVision({chatInput, visionExtracted})` in `lib/harness/guardrails/red_flag_screener.dart` — `visionExtracted` is the `freeform_caption` + `notable_objects` joined with newlines (the `setting`/`activity` enums are too narrow to false-positive on; `demeanor` is too soft to true-positive on). ≥10 vision-relevant phrasings per category added to `red_flags_fixture.dart` (CLAUDE.md §10's coverage rule extended). Badge fires in the form preview (above Save) AND persists on the saved entry's timeline cell. New DECISIONS row capturing the screener-scope expansion from row 29's "chat-only" to "chat + vision findings"; the false-positive-tolerant tradeoff direction (row 29) holds — better to tell a worried owner "this looks urgent" about a red sock than miss a real bleed.
- [x] 6.8 **NEW** — Affective observation layer (memory-grounded, last and cuttable). Per DECISIONS row 41 lock: bare observations defer to v1.2; v1 ships only memory-grounded observations. Separate Anthropic call AFTER extraction completes — model: `claude-haiku-4-5` (cheaper; the affective layer fires at most 1-per-5-saves). Takes the freeform caption + 3–5 retrieved prior memories from existing FTS5+vector hybrid as input; returns optional observation that MUST cite a retrieved memory by date or title (ungrounded observations dropped client-side). Three compounding gates: grounding + `confidence: high` + frequency cap (1-per-5-saves, tracked in tiny `affective_log` Drift table). Settings toggle "Show occasional observations" defaults ON per DECISIONS row 41. Post-save card surfaces below the 5.9 snackbar. **Build last** so cutting to v1.2 is a clean delete, not a refactor — flagged as the Phase 6 task most likely to slip on quality (the phrasing has to feel earned, not scripted; if the prompt iteration doesn't land warm-natural in the time-box, defer the whole layer to v1.2 cleanly).
- [x] 6.9 Multimodal chat input. **Narrowed** from the original 6.4 to the conversational pathway only (the camera-as-memory pathway is 6.6). Composer photo button → `image_picker` → `chatProvider.pendingAttachedImage` (chat composer button at `lib/app/screens/chat_screen.dart:619-628` opens the picker; on pick, calls `chatProvider.notifier.attachImage(bytes:, mediaType:)`). Send threads bytes to the LLM as a parameter on `AgentLoop.run/streamRun(attachedImage:, attachedImageMediaType:)` — **NOT a registered tool**. The user's photo attachment is a UI gesture, not an agent-issued action; modeling it as a tool would let the agent hallucinate `attach_photo` tool calls. `SessionBuilder.compose(hasAttachedImage: true)` injects the describe-not-diagnose hardener into the system prompt (`lib/harness/agent/session_builder.dart:203-233`). After the loop completes, the assistant's reply text feeds `RedFlagScreener.screenWithVision(visionExtracted:)` for post-screening. Image bubble carries a "Save as memory" button that routes to 6.6's form preview prefilled with the photo + the inline AI description as the freeform-caption draft (single round-trip — chat-saved photos don't double-tick the vision quota since the assistant reply doubles as the description; the extractor isn't re-invoked for chat photos). One photo per chat turn in v1; multi-photo deferred to v1.2.
- [x] 6.10 Vet-visit structured entry type — new entry kind `wiki/<pet>/vet/YYYY-MM-DD-<slug>.md` with structured frontmatter (`vet_name`, `reason`, `diagnosis`, `prescriptions: []`, `follow_up_date`). Form-driven creator UI; freeform fallback for non-vet entries.
- [x] 6.11 Auto-follow-up reminders — when a vet-visit entry has `follow_up_date`, auto-create a `notification`-mode reminder. Reuses existing scheduling stack.
- [x] 6.12 Weight + symptom trend charts — add `fl_chart` dep (DECISIONS row required). Charts: weight time-series, recurring-symptom frequency. Surface on the SOUL profile.
- [x] 6.13 Smarter weekly summary — upgrade `lib/harness/synthesis/weekly_digest.dart` to surface trends, anomalies, gentle observations ("Loki's weight has trended down for 3 weeks"). New synthesis prompt; no new infrastructure. **Light extension from the Tier 2 expansion:** the synthesis runner already pulls all entry types; explicitly verify photo-memory sidecars are in scope so weekly summaries can reference photo memories ("Loki spent more time at the park this week — three photos at the trailhead"). Tagged Pro-feature in copy/framing per DECISIONS row 36, but no enforcement gating in Phase 6 (Pro entitlement service ships in Phase 7). Existing free-tier digest entries already in journals stay as-is on the model shift — they're memory, and memory is free.
- [x] 6.14 Monthly health report — new synthesis cadence, longer-form than the weekly: trends, weight curves, recurring patterns, vet-visit follow-up status. Reuses the `mode=synthesis` runner from Phase 4; new prompt scaffolding only. Same light extension as 6.13 — photo memories included in the synthesis context. Pro-feature framing in copy; no enforcement gating in Phase 6 (lands in Phase 7 task 7.10). Per DECISIONS row 36.
- [x] 6.15 Phase 6 wrap-up. Tasks 6.1–6.14 ticked; photo storage layer (6.1, atomic binary + sidecar with 500 MB warn / 1 GB hard cap) + pet profile photo (6.2, dual-surface home greeting backdrop + chat AppBar avatar) + photo timeline (6.3, time-ordered grid at /photos with per-tile binary read) + multimodal request path + VisionGate stub (6.4, ImageBlock content variant + Anthropic vision encoding + Phase 7-pluggable entitlement gate) + photo extractor utility (6.5, locked structured-field schema, Sonnet-backed) + camera-as-memory capture flow (6.6, image_picker chooser + form preview with parallel extractor + 2048-on-long-edge resize) + vision red-flag screener integration (6.7, screenWithVision API + ≥10 vision-cadence fixtures per of the 11 categories + RedFlagBadge widget on form preview / entry view / timeline tile + DECISIONS row 55) + affective observation layer (6.8, three-gate pipeline — Settings toggle + 1-per-5-saves frequency cap + grounded high-confidence model output — surfacing on home below the hero) + multimodal chat input (6.9, composer photo button + ImageBlock-attached user turn + describe-not-diagnose system-prompt hardener + Save-as-memory bubble affordance) + vet-visit structured entry creator (6.10, /vet/new form with locked frontmatter — type/date/vet_name/reason/diagnosis/prescriptions/follow_up_date) + auto-follow-up reminders (6.11, ReminderKind.vetFollowUp + assets/reminders/vet_followup.yaml + form-driven reminder.create on save) + weight & symptom trend charts (6.12, fl_chart-backed line + bar charts on the SOUL profile fed by TrendsRepo's frontmatter-parsing weight history + FTS5 keyword counts + DECISIONS row 56) + smarter weekly digest (6.13, structured-signal block enrichment with weight delta + symptom counts + photo memory anchors + system prompt rewrite for trends/anomalies/photo memories/gentle observations) + monthly health report (6.14, sister runner with longer-arc weight trajectory + vet-follow-up status + Settings manual-trigger surface). Phase-end §14 self-verification: `flutter analyze --fatal-infos` exit 0 ("No issues found"); `flutter test --reporter expanded` exit 0 (1308 passed, +291 net new since Phase 5 close); `flutter build apk --debug` cannot run on the sandbox runner ("No Android SDK found") — the canonical APK build is the CI `release-apk` job per DECISIONS rows 22–24, the user-walked on-device verification (per DECISIONS row 39) lands on that artifact. **On-device verification REQUIRED.** Phase 6 introduces extensive new runtime behavior — camera + gallery picker round-trips, photo extraction Sonnet calls, multimodal chat turns, structured frontmatter writes, auto-armed reminders, fl_chart canvas rendering on the profile — that headless tests pin in shape but not in feel. Walkthrough must cover: (1) cold launch + the new "Add photo" home tile lands at top-left; (2) /photos/capture happy path: pick from gallery → extractor populates → save → snackbar with View action lands the user on the photo entry view; (3) /photos/capture camera path: same flow with the camera intent; (4) photo entry view renders the binary at full width + the additive frontmatter rows + (when present) the vision-source RedFlagBadge above the photo; (5) photo timeline tile shows the icon-chip badge overlay on flagged entries; (6) chat composer photo button + thumbnail strip + send → user-bubble shows attached image + the AI describes it; (7) Save-as-memory on the chat bubble routes to /photos/capture with bytes prefilled, no picker chooser; (8) /vet/new form save → vet entry on disk + (when follow-up date set) reminder row visible on /reminders + the firstAidKit icon dispatch surfaces; (9) SOUL profile: profile-photo card (or placeholder when none) + weight chart (or "log a weight" empty state) + symptom-frequency chart (or all-clear empty state) + the Profile/About card; (10) Settings → "Generate this week's summary now" + "Generate this month's report now" both produce digest entries visible in the journal browser; (11) affective observation card surfaces on home after a save when the gates allow + dismissable; (12) the Phase 5.5 add-pet form + Phase 5.6 Feel Polish + Phase 5 design system continue to render correctly under the new code (regression check). **Hard stop here.** Phase 7 (monetization, cloud sync, multi-pet UI) does not auto-start. Trigger CI on `claude/petpal-planning-S9DXN`; sideload the resulting `petpal-release-arm64-v8a.apk`; report any visual or interaction regressions. Fix-then-recommit before Phase 7 begins.

**Cuts (deferred to v1.1, v1.2 candidate scope, or Phase 7):**
- *Multi-pet UI improvements* → Phase 7 (free tier = 1 pet per DECISIONS row 8; multi-pet UI is Pro-only, belongs alongside the paywall).
- *Cross-photo pattern recognition, photo similarity search, mood/posture trending, place/object recognition, photo albums, bare (non-grounded) affective observations, multi-photo chat upload, custom in-app camera UI* → **v1.2 candidate scope** per DECISIONS row 40 + the "What's coming in v1.2" section in PRODUCT.md. Treated as deliberate next-version roadmap, not "maybe someday." Final v1.2 plan locks once we have ~6 months of real v1 usage data.
- *Body condition scoring, wound detection, breed/species inference, any clinical-adjacent vision* → stays locked OUT even in v1.2 per DECISIONS row 25. Same reasoning as v1: liability, accuracy ceiling, "track + know when to call the vet" positioning.
- *Onboarding intelligence (auto-populate from photos/voice)* → v1.1 (vision-based species/breed inference locked OUT by DECISIONS row 25; voice transcription adds new dependency).
- *Medication tracking* → v1.1 (significant data model — durations, doses, side effects, course-end prompts; overlaps with reminders).
- *Caregiver/family sharing preview* → v1.1 (PDF export work delays shipping; not core to the compounding-memory thesis).
- *Improved chat (reactions, edit/delete, threading)* → v1.1 (edit/delete contradicts "memory persists"; threading over-engineered; search is genuinely useful — defer with the rest, revisit in v1.1).

**On-device verification (REQUIRED):**
1. Add a profile photo to a pet → confirm it renders on home greeting backdrop (low-opacity, doesn't compete with the displaySmall name) AND chat AppBar avatar.
2. Tap the home grid 6th tile "Add photo" → camera/gallery picker opens → capture or pick a photo → form preview screen renders the photo + skeleton form → extractor populates the four fields + freeform caption + any enrichment hints → user edits inline → Save → photo lands in the photo timeline.
3. Take/upload a photo from chat ("here's Loki's paw") → confirm PetPal describes what it sees and does not diagnose; confirm the AI's response runs through the red-flag screener; confirm the "Save as memory" button on the image bubble routes to the form preview prefilled.
4. Create a photo memory of something with red-flag visual signals (mock or staged "blood on paw" caption text) → confirm the screener fires the vet-escalation badge in the form preview AND on the saved entry in the timeline.
5. Save 5+ photo memories in a session → confirm the affective observation card surfaces at most once across them (frequency cap working) AND that the one observation cites a specific prior memory (grounding working).
6. Toggle "Show occasional observations" OFF in Settings → save more photos → confirm zero observations fire.
7. Create a vet-visit structured entry with a `follow_up_date` → confirm a reminder appears in `/reminders` automatically.
8. Open the photo timeline → confirm time-ordered grid + tap-to-entry → tap a photo entry → confirm the entry viewer renders the image at full size + the structured fields + the freeform caption.
9. Open the SOUL profile after several weight log entries → confirm chart renders.
10. Wait or fast-forward to a weekly digest → confirm it surfaces trends/anomalies (NOT just a recap) AND references at least one photo memory if photos were saved that week.

**STOP.**

---

## Phase 6.5 — Visual Refinement Pass (Stitch-driven concept exploration)

**Goal:** explore PetPal's visual surface beyond what was reachable
through token-and-component refinement alone. Phases 5–6 built a
disciplined design system (sage palette, Inter + Source Serif 4
pairing, Phosphor icons, spring motion, the PetCard / PetButton /
PetEmptyState / PetSkeleton primitives). Phase 6.5 takes that system
into Google's Stitch (stitch.withgoogle.com) — a generative-UI tool
that produces visual concepts from a brand brief plus per-screen
prompts — to surface concept directions the in-codebase iteration
loop wouldn't reach. Three stages, **not** auto-advancing:

- **Stage 1: DESIGN.md generation.** Single markdown file at repo
  root (`DESIGN.md`) capturing brand thesis, anti-patterns, color
  tokens with intent, typography pairing with intent, motion
  vocabulary, and component primitives. The file gets uploaded to
  Stitch alongside per-screen prompts. Doc-only; no code changes.
- **Stage 2: Stitch curation.** The user runs Stitch sessions
  against `DESIGN.md` + per-screen prompts. Outputs are reviewed
  together — kept, cut, or recombined into a curated direction.
  Task list scoped after Stage 1 lands.
- **Stage 3: Implementation.** Curated directions land as code
  changes inside the existing token + primitive system. Anything
  that requires a new dependency or token-level change gets a
  DECISIONS row. Task list scoped after Stage 2 curation completes.

The three-stage shape exists so Stitch outputs inform implementation
rather than dictating it. PetPal's design language has been built
deliberately; Stitch is a concept-generation tool, not a system
replacement. Stage 2's curation is where deliberate-vs-Stitch
tension gets resolved before any code moves.

- [x] 6.5.1 DESIGN.md Stage 1 — generate the doc. Six sections
  (Brand Thesis verbatim, Anti-Patterns verbatim, Color Tokens with
  Intent, Typography Pairing with Intent, Motion Vocabulary,
  Component Primitives). Under ~3000 words, intent over completeness,
  `[INTENT-INFERRED]` flags where intent is uncertain from code
  alone, thesis-vs-implementation conflicts surfaced in commit
  messages rather than silently reconciled. DECISIONS row captures
  the document as input-to-Stitch (intent, not spec; outputs are
  curated, not implemented wholesale).
- [ ] 6.5.2 Stitch curation (Stage 2). Task list locks once Stage 1
  ships and Stitch sessions are run.
- [ ] 6.5.3 Implementation (Stage 3). Task list locks once Stage 2
  curation completes.

**STOP after each stage.** No auto-advancement; each stage is a
deliberate handoff back to the user.

---

## Phase 6.6 — Visual & Navigation Refresh

**Goal:** land the Phase 6.5 Stage 2 curation outcome (DECISIONS row
58) as code. Four adopted directions: bottom nav (4-tab Home / Journal
/ Profile / Hub via go_router `StatefulShellRoute`), editorial card
system (productized `EditorialCard` primitive + small-caps + sage-tint
section header refresh), screen-specific visual refinement across
home / journal entry / weekly summary / pet profile, and system-wide
coral wiring as the medical-warning register (resolves the
`[INTENT-INFERRED]` flag from DESIGN.md). **Last visual phase before
launch** (DECISIONS row to land in this prep): Phase 7 is monetization
+ cloud sync + multi-pet UI; Phase 8 is launch ops; no further polish
phases land before ship. Hard scope wall — no additions mid-phase.

**Goal of phase boundary:** "I'd hand my phone to a friend and say
'this is the app I've been working on'" without the visual surface
flagging itself as undercooked.

### Group A — Navigation IA (5 tasks)

- [x] 6.6.A.0 **Lock 4-tab bottom nav structure** — DECISIONS row
  pinning Home / Journal / Profile / Hub, the Hub-vs-Settings
  reasoning, and the orphan-tile mapping (Add photo → Quick Capture
  on Home, Journal/Profile/Settings → tabs, Reminders → Home
  section, Care guides → Profile sub-page, Settings → Hub sub-page).
- [x] 6.6.A.1 **Adopt go_router `StatefulShellRoute`** — DECISIONS
  row pins the routing-layer architectural choice (vs. `IndexedStack`
  alternative). Refactor `lib/app/routing.dart`: top-level routes
  for the four tabs become `StatefulShellRoute` branches; nested
  detail routes (`/wiki/entry`, `/photos/capture`, `/vet/new`,
  `/pets/add`, etc.) become branch-nested `GoRoute`s. Each branch
  preserves its own back-stack + scroll position; back-button pops
  within branch first, exits app at branch root.
- [x] 6.6.A.2 **Bottom nav widget** — `lib/app/widgets/pet_bottom_nav.dart`.
  Phosphor outline icons (4 destinations); Inter labels; sage active
  state with subtle pill background behind icon + label; static bar
  (not floating — floating pill skews Material You per DESIGN.md
  §2 anti-patterns). Hub icon: `squaresFour` (Phosphor regular)
  per the locked DECISIONS row.
- [x] 6.6.A.3 **Migrate routes to bottom-nav-aware structure** —
  home grid removed (the 6 tiles repurposed per A.0's orphan map);
  bottom nav becomes the persistent shell across all tab branches;
  `/dev` debug route stays accessible from a debug-only entry on
  Home. Onboarding redirect target stays `/onboarding` (outside the
  shell — full-screen until the user has a pet).
- [x] 6.6.A.4 **Verify deep-link integrity, back-stack, tab state
  preservation** — chat scroll position is the canonical test case
  (today's only stateful surface that matters); journal scroll
  position becomes a second test once entries accumulate. Deep
  links to `/wiki/entry?path=...` route through the Journal branch;
  `/photos/capture` routes through Home branch (since capture is a
  Home Quick Capture action). Verify back-button pops within
  branch first, then swaps to previous branch, then exits.

### Group B — Editorial Card System (5 tasks)

- [x] 6.6.B.0 **`PetSectionHeader` refresh** — small caps
  (TextTransform / `letterSpacing 1.0–1.2` + reduced size) + sage
  tint (`scheme.primary` at low alpha or `onSurface@0.6` blended
  with `primary@0.4` — TBD by visual A/B). Existing callers don't
  change shape; only the rendered chrome shifts. Update tests that
  pin the current `letterSpacing 0.6` + `onSurface@0.65` values.
- [x] 6.6.B.1 **`EditorialCard` primitive** — new
  `lib/app/widgets/editorial_card.dart`. Composition: optional
  leading thumbnail (square, `Radii.s` clip), `JournalText.entryTitle`
  serif title (Source Serif 4, weight 600), optional small-caps
  metadata row (date / type / pet name), bodyMedium body with
  truncation (3-line max with fade), optional trailing badge slot
  (consumed by `RedFlagBadge` for medical-flagged entries; coral
  left-border accent on flagged entries — the medical context
  primary; per DECISIONS row 60 the inner badge stays `RedFlagBadge`
  for compatibility but card-level coral takes primary). The
  primitive's docstring carries the locked shape spec (the user
  confirmed no separate spec doc; intent lives in code).
- [x] 6.6.B.2 **Apply `EditorialCard` to journal browser** —
  `lib/app/screens/wiki_browser_screen.dart` `_EntryTile` consumes
  `EditorialCard`. Date-grouped sections (replacing the existing
  type-grouped layout — TBD by Phase 6.6 visual brief). Type icon
  in the metadata row. Pet name in the metadata row when multi-pet
  arrives in Phase 7 (today single-pet, label suppressed). Coral
  left-border on entries with `red_flag_match` frontmatter.
- [x] 6.6.B.3 **Apply `EditorialCard` to Home recent entries
  section** — Home gains a "Recent memories" editorial section
  beneath the per-pet greeting hero. Top 3 entries via
  `wikiEntriesProvider`. Tapping a card routes to `/wiki/entry`.
- [x] 6.6.B.4 **Apply `EditorialCard` to weekly summary HIGHLIGHTS
  section** — `_DigestCard` (today's ad-hoc serif-title-card) is
  rebuilt to consume `EditorialCard`; HIGHLIGHTS rendering inside
  the digest's body uses nested `EditorialCard`s.

### Group C — Screen-Specific Visual Refinement (6 tasks)

- [x] 6.6.C.1 **Home redesign** — Quick Capture tiles row (Photo /
  Note / Medical, replacing the 6-tile destination grid); This Week
  card above the tiles (recent memories count + most-recent digest
  if any); Reminders section below tiles (per DECISIONS row 61 —
  inline section on Home, tap header → `/home/reminders` sub-page);
  per-pet greeting hero stays (Phase 6.2 photo backdrop + sage
  gradient + displaySmall name).
- [x] 6.6.C.2 **Journal entry detail refresh** —
  `lib/app/screens/wiki_entry_screen.dart`. Header structure: serif
  `JournalText.entryTitle` + small-caps date metadata. Photo
  treatment (when entry has an image): subtle sage frame, no
  device-mockup framing. MEDICAL NOTE callout pattern for vet
  entries (coral icon + tinted left border + small-caps "MEDICAL
  NOTE" label). Markdown body styling stays as-is (Source Serif 4
  on `h1`/`h2` from Phase 5.6).
- [x] 6.6.C.3 **Weekly summary detail refresh** — editorial header
  (serif `weeklySummaryTitle` + small-caps date), INSIGHT callout
  pattern (sage icon + tinted left border + small-caps "INSIGHT"
  label) for the synthesis runner's anomaly + trend observations,
  structured HIGHLIGHTS section using nested `EditorialCard`s
  (Group B).
- [x] 6.6.C.4 **Pet profile layered restructure** —
  `lib/app/screens/soul_editor_screen.dart`. Read-only sectioned
  view as default: ABOUT / DETAILS / HEALTH SUMMARY / RECENT
  MEMORIES / GUIDES & SKILLS. Edit pencil on the AppBar opens the
  existing editor unchanged. Trend charts (Phase 6.12) relocate
  into HEALTH SUMMARY. Phase 6.2 photo card folds into the
  sectioned header (large circle photo + serif name + small-caps
  subtitle pattern from Stitch). Care guides (today reachable from
  `/skills`) move under GUIDES & SKILLS section per DECISIONS row
  62; per-pet contextual + species-filtered.
- [x] 6.6.C.5 **Empty state refinement** — adopt Stitch microcopy
  register on the four empty states (`_EmptyState` on home,
  `JournalEmptyForTesting` on journal, reminders empty, care
  guides empty). Reference register: "Luna's schedule is clear.
  Enjoy the quiet moments together." Routes through VOICE.md §5
  per-pet interpolation rule. Stays warm without saccharine
  (VOICE.md §1).
- [x] 6.6.C.6 **Microcopy refresh** — adopt "Keep Chronicling" CTA
  register and other voice gold from Stitch curation across home
  greeting body / chat empty / button labels (where they're
  per-pet — buttons stay static per VOICE.md §5 unless they're
  on a per-pet destination).

### Group D — System-Wide (3 tasks)

- [x] 6.6.D.1 **Wire coral to medical-warning surfaces** —
  `RedFlagBadge` icon shifts to coral; vet entry `EditorialCard`
  gets coral left-border accent (Group B); MEDICAL NOTE callout
  on vet entry detail uses coral icon + tinted left border (Group
  C); photo entry red-flag badge area uses coral icon (today
  `onSurfaceVariant`); chat scrollback escalation marker shifts
  to coral. Vet form save error keeps `scheme.error` (M3-default
  red — failures are failures, distinct register from
  medical-attention). Resolves DESIGN.md's `[INTENT-INFERRED]`
  flag.
- [x] 6.6.D.2 **Dark mode parity** — verify coral + sage editorial
  treatments don't wash through the warm-graphite surface scale
  (DECISIONS row 38 lock); all Group B + C surfaces render
  correctly under `buildDarkColorScheme`; coral readability on
  dark surfaces (the warm-peach hex `#E89B7A` was tuned for
  light-mode contrast — verify on the `darkSurfaceContainer`
  band). If contrast falls short, the light/dark coral split
  lands here as a follow-up DECISIONS row.
- [x] 6.6.D.3 **Phase 6.6 wrap-up + on-device verification
  REQUIRED.** §14 verify: `flutter analyze --fatal-infos` exit 0,
  `flutter test --reporter expanded` exit 0, APK build via CI
  (sandbox can't run Android SDK). Walkthrough script (locks at
  6.6.A.0): tap each of the 4 bottom-nav tabs and confirm tab
  state preserves across switch; deep-link from Recent Memories
  card → entry → back lands on the Journal tab not Home; chat
  scroll position survives a tab switch; the journal browser
  renders as `EditorialCard`s with coral left-border on flagged
  entries; pet profile renders as 5 sectioned read-only view;
  edit pencil opens the existing editor unchanged; weekly summary
  renders editorial-style with INSIGHT callouts; vet entry detail
  shows MEDICAL NOTE callout; coral consistent across red-flag
  surfaces; dark mode parity holds. **Hard stop here.** Phase 7
  (monetization) does NOT auto-start.

**Cuts to v1.x** (with V1X_BACKLOG entries — see `V1X_BACKLOG.md`):
- *Center Capture FAB in bottom nav.* Multi-modal capture doesn't
  fit a single FAB; FAB visual weight pulls toward social-app
  register; primary loop is chat-driven, not capture-driven.
  Trigger: post-launch usage signal showing capture intent from
  non-Home tabs.
- *Stitch's 6 alternate bottom-nav configurations.* Archived as
  reference for post-launch revisit; no scope.
- *Medical as top-level destination.* Mixed-with-journal IA holds
  until real signal warrants the IA promotion.
- *In-app notifications inbox + Hub future contents (Privacy &
  Data, Help/Support).* Hub v1 ships with Settings + Export +
  About; v1.1 sub-pages don't require IA changes.
- *Vitals tracker, Symptom tracker, Activity tracking.* v1.2
  candidate scope; need real-usage signal to lock the structured
  shape.
- *Multi-user "Pet Family" / family-sharing.* v1.x; depends on
  Phase 7 sync + per-pet identity model.
- *Engagement metrics.* v1.x; opt-in privacy-preserving signal
  routed through Phase 7 backend.

**On-device verification (REQUIRED at 6.6.D.3) — see Group D.3
walkthrough.**

**STOP.**

---

## Phase 7 — Monetization, Cloud Sync, Multi-Pet UI

**Goal:** ship the v1 monetization model from DECISIONS row 36 — PetPal-hosted LLM proxy funding the free 200-msg/mo allowance, Pro subscription ($7.99/mo or $59/yr) with sync + unlimited pets + unmetered text + 30 vision/mo + weekly + monthly synthesis + unlimited reminders, BYOK as a free-tier modifier that bypasses the proxy, photo credit packs for vision overage, multi-pet UI behind the paywall, accessibility pass. **Architectural locks land in DECISIONS rows 69–81 at Stage 1 sign-off** (Supabase as single-provider backend; magic-link auth; Argon2 E2EE; LWW + `.conflict.md` sync; hard wall paywall + BYOK escape valve; format + live-ping BYOK validation; hybrid client+server quota enforcement; build proxy now; full GDPR-compliant account deletion; Supabase-canonical entitlement state with Play webhook refresh + reconciliation). Stage 2 implementation builds the 17 tasks across 8 groups below.

**Definition of done:** a free user can use the app without signing in (local journal works, chat works against the proxy with the 200-msg/mo allowance); the same user can flip the BYOK toggle in Settings and continue chatting without limit; signing in via magic-link email + subscribing with a Play tester account unlocks sync, unlimited text chat, 30 vision/mo, weekly + monthly synthesis, unlimited reminders, multi-pet; installing on a second device + signing in with the same email + entering the passphrase syncs the journal end-to-end (E2EE; backend never sees plaintext); a Pro user who exceeds 30 vision/mo can buy a $2.99 = 50 photo credit pack and the balance rolls over; one care pack IAP is purchasable; account deletion flow purges all backend records within 30 days; accessibility pass clean.

### Group A — Backend Foundation (Large, 3 tasks)

Lays the seam every other group consumes. Decision-then-implementation.

- [x] 7.A.1 **Backend service architecture decision** — concrete Supabase backend spec landed in **DECISIONS row 82**. Two projects (dev/prod), region us-east-1, Pro-tier prod ($25/mo), Supabase Auth magic-link config, proxy latency budget (~150ms overhead p95 over Anthropic), `entitlements` + `anonymous_counters` schemas, observability ($50/day soft warn / $200/day hard alert), abuse-detection signals (100 msg/hour rate-limit floor + anomaly heuristics + banned-token list), counter reset triggers, Edge Function structure (`llm-proxy` + `play-billing-webhook` + `daily-reconciliation-cron`).
- [x] 7.A.2 **Backend service implementation (scaffold)** — `supabase/` directory at repo root with `config.toml` (auth + edge runtime), schema migration `0001_phase7_init.sql` (entitlements + anonymous_counters + banned_* + proxy_request_log + deleted_accounts_log + 5 SQL functions including `increment_text_counter` with `SELECT ... FOR UPDATE` row-level lock per row 75), `llm-proxy` Edge Function (Deno/TypeScript, raw-body cache_control passthrough, JWT-or-device-token identity, atomic counter increment, streaming response with tee'd token-count log), Deno test file pinning 11 invariants (cache_control passthrough byte-for-byte; auth required; quota wall 402; rate-limit 429; banned 403; Pro = unmetered; CORS preflight; malformed JSON 400; method 405; proxy_request_log row records `inbound_had_cache_control`; recursive cache_control detection across system / messages / tools), and `docs/phase7/A2-deployment.md` checklist. **Deployment requires user hand on:** Supabase project creation, master Anthropic API key as Edge Function secret, cron job registration. Sandbox-bound work is complete; provisioning is the user's manual step (one-time, ~30-45 min per `A2-deployment.md`).
- [x] 7.A.3 **`AnthropicClient` two-path refactor** — `LlmTransport` abstraction at `lib/harness/agent/llm_transport.dart`. Direct-call code at `lib/harness/agent/direct_transport.dart` is `DirectTransport` (BYOK path per row 74). `lib/harness/agent/proxy_transport.dart` is `ProxyTransport` (calls the 7.A.2 backend). Agent loop and prompt-caching layer unchanged — selection happens at construction time based on active entitlement state (Free + funded → Proxy; Free + BYOK → Direct; Pro → Proxy). Tests cover both transports including `cache_control` passthrough on the proxy path.
  - [x] 7.A.3.1 — Add `LlmTransport` abstract marker; `AnthropicClient extends LlmTransport`; new `ProxyTransport extends LlmTransport` with cache_control passthrough + auth-header switching (Bearer JWT for signed-in, x-petpal-device-token for anonymous) + quota error mapping (402/429/403 → AnthropicApiException). 13 new tests; full suite 1364.
  - [x] 7.A.3.2 — Renamed `AnthropicClient` → `DirectTransport` (file + class + all 10 caller sites across lib/ + test/). `git mv` preserves history. 1364 tests still pass; analyze clean.

### Group B — Tier Service & Entitlements (Medium, 1 task)

- [x] 7.B.1 **Entitlement model + Drift schema bump** — Drift schema bump v1→v2 with `Entitlements` table (annotated `@DataClassName('EntitlementRow')` to avoid name collision with the domain `Entitlement` class) covering all canonical Supabase fields per row 82 (`userId`, `state`, `renewalDate`, `graceUntil`, `photoCreditsBalance`, `monthlyTextCount`, `monthlyVisionCount`, `counterPeriodStart`, `fetchedAt`); domain `Entitlement` value class + `EntitlementState` enum with state-derived flag derivations (`isPro`, `isFree`, `isTextMetered`, `isVisionMetered`, `usesProxy`, `textCap`, `visionCap`, `reminderCap`, `petCap`); `EntitlementRepo` (read / upsert / clear with `insertOnConflictUpdate`); Riverpod `entitlementProvider` (`AsyncNotifierProvider`) returning `Entitlement.freeAnonymous` default with `setOptimistic` for post-IAP optimistic emit + cache persist. **B.1 ships the foundation; reconciliation against Supabase is a stub** (`refresh()` is a no-op pending Group F.1's `supabase_flutter` adoption + auth wiring). 36 new tests: 22 value-class (state-derivation invariants, wire round-trip, quota-exhaustion semantics), 10 repo (round-trip, no-op-on-anonymous, multi-user), 4 notifier (default state, refresh stub, setOptimistic persist).

### Group C — Play Billing Integration (Medium, 3 tasks)

- [x] 7.C.1 **Subscription IAPs** — `in_app_purchase: 3.2.3` adopted; plugin-bump checklist per row 33 confirmed zero manifest changes (Play Billing handles BILLING permission internally). Product IDs locked in `lib/platform/billing/product_ids.dart`: `pro_monthly`, `pro_annual`, `photo_credits_50`, `care_pack_reactive_dog`, `expert_pack_senior_dog` (all five reserved at C.1 even though only subs are wired here; Play Console product registration happens once for all of them). Architecture: `IapPlatform` abstract façade over `InAppPurchase.instance` (testable seam — production injects `IapPlatformImpl`, tests inject a fake); `BillingService` owns the `purchaseStream` subscription, dispatches PURCHASED/RESTORED to optimistic-entitlement updates via `EntitlementNotifier.setOptimistic`, surfaces `BillingEvent` sealed-class outcomes to the paywall. **Server receipt verification is stubbed at C.1 — optimistic Pro emit is the source of truth until the `play-billing-verify` Edge Function ships in a later task.** 17 new tests pin: initialization handshake (available / unavailable / product-query-error paths), `buyPro(annual:)` dispatch, all 6 purchase outcomes (pending/canceled/error/purchased/restored/non-Pro), restorePurchases forwarding. Plus a manifest regression test recording the C.1 plugin-bump audit (DECISIONS row 33 fulfilled). Risk mitigation per Stage 1: all testing via Play Console tester accounts; **no real-card testing** locked. Pubspec: `in_app_purchase: ^3.2.3` + 3 transitive deps. AndroidManifest unchanged. 1418 tests pass.
- [x] 7.C.2 **Photo credit pack IAP** — $2.99 = 50 vision analyses, consumable IAP, balance rolls over indefinitely per row 36. `BillingService.buyPhotoCredits()` triggers `iap.buyConsumable(photoCredits50)`; PURCHASED dispatch reads quantity from `ProductIds.creditPackQuantities` map and fires `onPhotoCreditsGranted(50)` callback; provider wiring optimistically increments cached `entitlement.photoCreditsBalance` via `EntitlementNotifier.setOptimistic` (current → copyWith). Server reconciliation is stubbed (lands with `play-billing-verify` Edge Function). 5 new tests pin: buyConsumable dispatch, billing-unavailable + product-not-loaded paths, PURCHASED → 50-credit grant, callback-omitted graceful skip. Updated existing C.1 photo-credit assertion to reflect new semantics (state stays free; balance increments). 1423 tests pass.
- [x] 7.C.3 **Care pack IAP** — one starter pack: `care_pack_reactive_dog` ($2.99) unlocks the existing `reactive-dog` skill. Non-consumable IAP. Wires `SkillManifest.requiresPro` enforcement at the skill-loader (the field existed at `lib/harness/skills/skill_manifest.dart:23,34,45` but was unenforced — this task lights it up via the new `SkillLoader(isPro:, ownedCarePackSkillIds:)` constructor params + the three-stage filter chain in `match()`). Schema bump v2→v3 adds `entitlements.ownedCarePackSkillIdsJson` text column (JSON-encoded `Set<String>`); `EntitlementRepo.upsert` round-trips the set; provider wiring optimistically appends the unlocked skill ID via `EntitlementNotifier.setOptimistic` on PURCHASED. `BillingService.buyCarePack(productId)` validates against `ProductIds.carePackToSkillId` (rejects unknown IDs with BillingError); PURCHASED dispatches via `_onCarePackOwned(skillId)`. Reactive-dog manifest flipped from `requires_pro: false` → `true`. 13 new tests: 6 SkillLoader entitlement-gate cases (non-Pro/no-ownership drops, ownership unlocks, Pro implicit unlock, free skills always load, mismatched ID doesn't unlock), 5 BillingService C.3 cases (buyCarePack dispatch, unknown product rejection, PURCHASED + RESTORED skill grants, callback omission), 1 EntitlementRepo (JSON serialization round-trip), 1 Entitlement value class (set equality + copyWith). Updated 1 Phase-5.14 test to reflect reactive-dog is now Pro-gated. **Expert pack ($14.99–$39.99) deferred to v1.x per Stage 1 plan + V1X_BACKLOG entry.** 1437 tests pass.

### Group D — Quota Enforcement (Medium, 1 task)

- [x] 7.D.1 **Quota gates wired across the stack** — sealed class `QuotaExceededException` at `lib/app/entitlement/quota_exception.dart` (Text/Vision/Reminder/Pet/Sync subtypes, each carrying the triggering Entitlement). Five gates wired: (1) **Chat msg gate** in `chat_notifier.dart` send path — pre-call check on `entitlement.isTextQuotaExhausted`, red-flag-screened turns exempt per row 75 safety carve-out. Optimistic counter increment after successful turn (free tier only; vision turns excluded since vision counter is separate). (2) **Vision gate** — `RealVisionGate` replaces `StubVisionGate`; full decision matrix per VOICE.md §6 example 13 register (Pro under cap → allow; Pro at cap with credits → allow; Pro at cap without credits → block with "buy credit pack" copy; BYOK → allow; Free → block with Pro-upgrade copy). (3) **Reminder gate** in `ReminderService.create` — counts existing reminders for pet, throws `ReminderQuotaExceeded` at 5 cap. **BYOK keeps the cap** (reminders are server-cost-trivial UX, NOT cost-driven; row 36). Optional `entitlementSource` callback so existing callers can opt out of the gate. (4) **Pet count gate** in `add_pet_screen` — checks `entitlement.petCap` before `repo.createPet`. (5) **Sync gate** — new `EntitlementGatedSyncAdapter` decorator wraps any `CloudSyncAdapter`; throws `SyncQuotaExceeded` on push/pull when not Pro. **BYOK does NOT unlock sync** (per row 36 — sync is server-cost). Wired but no-op until G.2 ships real sync. Chat error mapping: 402 monthly_cap_exceeded + client-side TextQuotaExceeded both map to new `ChatErrorCategory.quotaExceeded`. **Bug fix**: `EntitlementState.reminderCap` previously returned null for BYOK (giving unlimited reminders); corrected to 5, matching row 36's "BYOK lifts cost-driven caps only" rule. 27 new tests: 7 vision-gate decision-matrix, 4 reminder-service quota, 6 sync-gate, 2 chat-error mapping, 7 quota-exception value class. Pet count gate exercised via existing add-pet flow paths. 1464 tests pass.

### Group E — Paywall + Pro UX (Medium, 2 tasks)

- [x] 7.E.1 **Paywall screens + restore-purchases + 200/mo wall** — split into two sub-commits to manage UI surface area.
  - [x] 7.E.1.a Paywall foundation: `paywall_screen.dart` (Pro upsell with hero, monthly + annual cards, 7-feature list, BYOK escape note, restore link, already-Pro + billing-unavailable empty states), `photo_credit_pack_screen.dart` (focused vision purchase with VOICE.md §6 example 13 hero + Pro-required redirect for free users), `paywall_dispatcher.dart` (single switch on `QuotaExceededException` sealed class — text/reminder/pet/sync → /paywall, vision → /paywall/credits), `/paywall` + `/paywall/credits` routes registered OUTSIDE the StatefulShellRoute (full-screen takeover; no bottom nav while purchasing). Chat error bar's `quotaExceeded` branch swaps Retry for "See Pro options" → dispatcher. Add-pet inline error gets a "Compare plans" link → dispatcher (per Stage 1 user-confirmed pet-cap UX decision: inline + link rather than full paywall route). All sage register; coral never appears (DECISIONS row 64 — coral is medical-attention-only). 14 new tests pin dispatcher routing matrix + paywall + photo-credit screen renders + buy CTAs + restore + Pro/billing-unavailable empty states. Defect caught + fixed during testing: paywall restore spinner had a leaking `Future.delayed` that left a Timer past test teardown — migrated to a tracked `Timer` cancelled on dispose.
  - [x] 7.E.1.b Settings additions + reminder dispatcher: new "Plan" section in Settings with Pro/Free/BYOK badge row + ambient text counter row (VOICE.md §6 example 11 register; rendered for free + BYOK only; Pro is unmetered) + "Restore purchases" tile. Counter copy varies by remaining headroom ("plenty of room" / "X left" / "you've used all 200"). Reminder quota dispatcher: `reminders_screen.dart` `_save` catches `ReminderQuotaExceeded`, pops the form, dispatches to paywall. 5 new tests: 4 Plan card variants (free + Pro + BYOK + restore tile) + 1 reminder service contract test. Vision quota dispatcher deferred to a focused later task — wiring requires refactoring `photo_extractor` return type from null-on-block to a richer `data | blocked-with-reason` value class so callers can render the gate's `reason` + paywall CTA. Out of scope for E.1.b's "Settings + restore-purchases" line.
- [x] 7.E.2 **Multi-pet UI** — pet switcher widget, cross-pet timeline, family-wide reminders. New `lib/app/active_pet/active_pet_notifier.dart` (`AsyncNotifier<int?>`) backed by `SettingsStorage` `active_pet_id` key; `activePetIdProvider` refactored to consult the persisted selection with a `pets.last.id` fallback (existing callable signature preserved for chat / soul-editor / hub callers). New `activePetProvider` returns the resolved `Pet?` for UI ergonomics; `wikiEntriesProvider` follows it; new `journalEntriesProvider.family<List<Entry>, int?>` (null = "All pets" interleaved by `ts` desc) for the Journal tab; new `allRemindersProvider` fans out per-pet reminders for the family-wide Reminders surface. New `lib/app/widgets/pet_switcher.dart` with `PetSwitcherTitle` (tappable AppBar title + chevron + bottom-sheet sealed-result API: `PickedPet` / `PickedAllPets`). Wired on Home (AppBar `usersThree` action icon when 2+ pets — Home AppBar title stays "PetPal" brand register), Profile (tappable "$pet's profile" title; reloads SOUL on switch via `_hydratedPetId` mismatch detection), Journal (Stateful `_selectedPetId`; "All pets" mode opt-in via `includeAllPets: true` switcher; cross-pet entries get pet-name kicker prefix). Reminders screen rewritten to a single combined sectioned list (always — no active-pet read), section headers carry pet name + count, "Add reminder" FAB asks via switcher when 2+ pets exist (auto-targets single pet otherwise). Add-pet screen's `_FreeTierLimit` early-exit now reads `entitlement.petCap` (Pro users with 1 pet hit the form, not the limit screen) and the limit screen now ships VOICE.md §6 example 9 copy + a "Compare plans" CTA via `dispatchPaywall`. Settings Plan card gains a pets-row ("$N of $cap pet[s]" for free/BYOK; "$N pet[s]" for Pro; additive subtitle copy per VOICE.md §7 #1). 18 new tests across active-pet notifier + pet-switcher widget; existing reminders title test updated to assert the new household-wide static title. Pro pet-cap unlock confirmed via D.1's `entitlement.petCap == null` for Pro state. Free-tier and Pro tier users alike now route through the same provider stack — `petCap == null` skips the gate cleanly. Multi-user / family-sharing remains V1X_BACKLOG row 514.

### Group F — BYOK Path (Small, 1 task)

- [x] 7.F.1 **BYOK onboarding rewrite + Settings switcher** — `lib/app/screens/onboarding_screen.dart` rewritten as a 2-page PageView (welcome → VOICE.md §6 example 15 proxy-default privacy disclosure). API-key entry removed. New `lib/app/welcome/welcome_completed_notifier.dart` (`AsyncNotifier<bool>` over `SettingsStorage` `welcome_completed` key) replaces the API-key check inside `isOnboardedProvider`; pre-Phase-7 users with a stored key auto-promote to completed via the notifier's `build()` (one-time silent migration). `main()` pre-reads the welcome flag + applies the migration synchronously so the router doesn't bounce upgraded users through onboarding on first frame. New `Entitlement.byok()` factory; `EntitlementNotifier.build()` reads `byok_enabled` from settings and similarly auto-promotes existing-key users to BYOK so chat keeps working without re-prompting (DECISIONS row 74 "existing keys persist" lock). New `setByokActive({active, apiKey})` method routes through `ApiKeyNotifier.save()/clear()` so `apiKeyProvider` stays in sync. New `lib/app/byok/byok_validator.dart` implements DECISIONS row 74's two-stage flow (format regex `sk-ant-[A-Za-z0-9_-]{40,}` + live ping to `https://api.anthropic.com/v1/models` with `x-api-key` header; 200 → Accepted, 401/403 → RejectedAuth, network failure → soft-warning NetworkError "saving anyway"). New `lib/app/byok/byok_key_entry_sheet.dart` modal sheet captures the key, runs the validator, calls `setByokActive(active: true, apiKey:)` on accept. Settings Plan card gains a `_ByokToggleTile` `SwitchListTile` (VOICE.md §6 example 12 locked copy) — hidden for Pro (Pro is unmetered + adds sync; BYOK as cost-driven escape valve has no add-value for Pro). Toggle ON opens the entry sheet; toggle OFF prompts a confirmation dialog before clearing. Chat screen disables the composer + renders a `_ChatUnavailableBanner` ("Chat needs a connection to Claude. Add your Anthropic key in Settings — sign-in for the free monthly allowance ships in a later update.") when no API key is stored — proxy-only path waits for Group H sign-in. 27 new tests across welcome notifier (5 incl. migration), BYOK validator (9 covering format/auth/network paths), entitlement notifier BYOK additions (3 incl. setByokActive on/off + migration); existing onboarding screen tests rewritten for the 2-page flow + the proxy-default Phase 7 honesty invariant (inverts the Phase 5 "BYOK-only" pin). Defensive try/catch in entitlement + welcome notifiers' `build()` keeps tests without storage overrides safe (production overrides both in `main()`).

### Group G — Sync (Large, 3 tasks)

- [ ] 7.G.1 **Sync backend confirmation** — append to `DECISIONS.md` confirming Supabase Storage as the sync object store (per row 69 single-provider lock). Spec: bucket structure (per-user prefix), object versioning (Supabase Storage handles this natively), conflict semantics (per row 72 LWW + `.conflict.md`), encryption-at-rest (Supabase server-side AES-256 in addition to E2EE; defense in depth), BYOC option deferred to v1.x. Decision-only task; no implementation.
- [ ] 7.G.2 **CloudSyncAdapter implementation + E2EE** — implement against the existing `lib/data/sync/cloud_sync_adapter.dart` interface stub. End-to-end encryption per PRODUCT.md commitment + DECISIONS row 71: Argon2id passphrase-derived key (m=64MB, t=3, p=4 v1 starting params); key never leaves device; backend only ever sees ciphertext. **Modal two-step "we cannot recover" warning** (row 71 lock) at passphrase setup — copy + flow surface for review during this task. **Code-level audit + documented test verifying backend never receives plaintext sync content** (risk mitigation lock); independent code review on the E2EE implementation (general-purpose agent or fresh Claude session).
- [ ] 7.G.3 **Conflict resolution** — last-writer-wins with `.conflict.md` fallback for genuinely-divergent edits per row 72. Defaults: 5-second timestamp-skew tolerance, structural-change detection (frontmatter key adds/removes = genuine divergence; body prose within tolerance = LWW). Edge cases tightened during impl when real data shapes them. **Network-flakiness simulation in tests + on-device walkthrough** (risk mitigation lock): device A writes, goes offline, device B writes same path, both come back online → verify `.conflict.md` lands deterministically with loser's content + survivor stays canonical.

### Group H — Account, Settings, Pre-Launch (Medium, 3 tasks)

- [ ] 7.H.1 **Settings refresh — sign-in/out, account delete, data export, privacy info** — sign-in/out via magic-link per row 70 (free users may stay signed-out; Pro requires sign-in). Account-delete flow per row 77: modal Export prompt → Sync purge confirmation → Soft delete + 30-day recovery window → hard purge of wiki blobs + entitlement + counters + proxy logs + auth row. **Deletion-completed audit trail** (risk mitigation lock): user-visible in-app notification on hard-purge day; backend `deleted_accounts_log` table records hash of user ID + deletion date + retention-end for GDPR/CCPA audit. Privacy-info screen copy refreshed for the proxy-default + BYOK + Supabase-Auth + E2EE story (replaces the original "your key, your calls" framing).
- [ ] 7.H.2 **Accessibility pass + opt-in crash analytics with sk-ant- redaction** — contrast, screen reader labels, text scaling, touch-target sizes (audit every Phase 6.6 + Phase 7 surface). Lightweight crash analytics, opt-in + off by default. **`sk-ant-` pattern redaction layer** (risk mitigation lock): every analytics payload + crash report scrubs anything matching `sk-ant-[a-zA-Z0-9_-]{20,}` before send so a BYOK user's key can never leak through telemetry.
- [ ] 7.H.3 **Phase 7 wrap-up commit + summary; on-device verification REQUIRED ACROSS TWO DEVICES.** Sync needs cross-device validation; one-device verification is insufficient.

**On-device verification (REQUIRED, two devices):** sign in via magic-link on device A → subscribe with Play tester account → install on device B → sign in with same email → enter passphrase → confirm wiki syncs end-to-end with no plaintext on backend (proxy log inspection); add a second pet and confirm pet switcher works; trigger a sync conflict via offline writes on both devices and confirm `.conflict.md` is created with deterministic loser content; chat 200+ messages on a fresh free tester account and confirm the hard-wall fires with both Upgrade + BYOK CTAs; flip BYOK and confirm calls bypass the backend (verify via proxy logs); buy a photo credit pack and confirm balance rolls over to next month; buy the care pack and confirm Pro-gated skill loads after purchase; trigger account deletion + verify export prompt + sync purge confirmation + 30-day soft-delete window + hard-purge on the recovery-window expiration date.

**STOP.** Phase 8 (Play Store Prep & Launch) does NOT auto-start.

---

## Phase 8 — Play Store Prep & Launch

**Goal:** signed AAB on internal testing track, store listing approved.
**Definition of done:** install via Play internal track on a fresh device; sandboxed billing flow works end-to-end.

- [ ] 8.1 Verify Phase 5 adaptive icon + splash meet Play Store asset requirements (sizes, safe-zones, dark-mode preview); regenerate any missing densities
- [ ] 8.2 Privacy policy hosted; Data Safety form drafted (LLM calls leaving the device disclosed)
- [ ] 8.3 Store listing copy + 1 phone + 1 7" tablet screenshot set
- [ ] 8.4 Release keystore generated; Play App Signing enrolled (replaces the debug-signing fallback from DECISIONS row 22)
- [ ] 8.5 R8/ProGuard rules verified for Drift, Anthropic SDK, and the Phase 4 scheduling stack
- [ ] 8.6 `flutter build appbundle --release`
- [ ] 8.7 Upload AAB to internal testing track
- [ ] 8.8 Triage Play pre-launch report
- [ ] 8.9 Closed testing checklist + invite list
- [ ] 8.10 Phase wrap-up commit + summary

**On-device verification:** install via Play internal track on a fresh device, run sandboxed billing flow.

**STOP. Ready for launch decision.**
