# PetPal Roadmap

Eight phases. Tasks are sized to ≤30 min of agent work. Every phase ends with a deliverable I can verify on a real Android device, and a hard stop. The agent does not auto-advance.

The original plan was six phases (Phase 0 scaffold → Phase 5 monetization → Phase 6 launch). After Phase 4 we restructured: the harness is past MVP-grade (873 tests, three-layer memory, scheduling, 11-category guardrails, species-aware skills), but the app's experiential surface is still MVP-quality. Monetizing barebones UI on top of world-class architecture inverts the value perception. So we inserted **Phase 5 (Product Polish & Visual Identity)** and **Phase 6 (Feature Depth & AI Capabilities)** before monetization. The original Phase 5 became Phase 7; the original Phase 6 became Phase 8. See DECISIONS row 34 for the rationale.

**Current phase: Phase 4 — COMPLETE pending on-device verification (REQUIRED before Phase 5).**

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

- [ ] 5.1 Design system tokens — `lib/app/design/` package: `ColorScheme` seeded from sage `#5C8A7A` with manual surface-tint overrides (avoid M3 lavender drift), typography theme wiring Inter + Source Serif 4 via `google_fonts`, spacing scale (`Spacing.xs/s/m/l/xl`), elevation tokens, corner radii, motion durations. Replaces `lib/app/theme.dart:1-15`. Adds `google_fonts` to `pubspec.yaml` (DECISIONS row required).
- [ ] 5.2 Component primitives — `PetButton`, `PetCard`, `PetEmptyState` (illustration + heading + body + CTA slot), `PetSkeleton`, `PetSectionHeader`, `PetIcon`. Sit on top of 5.1.
- [ ] 5.3 App icon (adaptive) — `flutter_launcher_icons` config: foreground = journal-+-paw mark in graphite (`#2D3436`), background = warm off-white (`#F7F5F2`). Adaptive icon for Android 8+. Source asset `assets/branding/icon-foreground.png`.
- [ ] 5.4 Splash screen — `flutter_native_splash` config: warm off-white background, journal-+-paw mark centered. No animation in v1.
- [ ] 5.5 Onboarding redesign — replace 3-page config wizard (`lib/app/screens/onboarding_screen.dart:62-91`). New flow: emotional welcome (what PetPal does) → privacy disclosure (existing four bullets, copy refreshed) → API key as utility, not the welcome.
- [ ] 5.6 Empty states — wire `PetEmptyState` to journal browser, reminders, care guides, chat. Each teaches what goes there.
- [ ] 5.7 Loading & feedback — replace `CircularProgressIndicator` with `PetSkeleton` on lists; haptics on save-memory / complete-reminder / schedule-reminder via `HapticFeedback.lightImpact`; `AnimatedSwitcher` on home greeting state change.
- [ ] 5.8 Hero moment — memory saved. When `write_wiki_entry` fires: tool pill settling micro-animation + "Saved a memory about Loki" snackbar that taps to the entry + haptic.
- [ ] 5.9 Hero moment — per-pet home greeting. Pet name + warm gradient + typography (Phase 6 adds the photo). Cold-start moment polish.
- [ ] 5.10 Hero moment — weekly summary appearance. Weekly digest entries get a distinct card treatment in the journal browser, visually different from regular entries.
- [ ] 5.11 Per-screen polish audit — walk every screen in `lib/app/screens/`. Home button stack (`home_screen.dart:79-139`) becomes a card grid; chat composer gets visual lift; settings rows get section dividers; SOUL editor gets a distinct Profile-fields-vs-About-Loki visual hierarchy.
- [ ] 5.12 Microcopy pass — every button label, error message, empty-state copy, confirmation dialog walked against VOICE.md §1–§6. Tightened for shipping. Update string fixtures.
- [ ] 5.13 Skill pack content expansion — author 3 packs under `assets/skills/`: `reactive-dog` (`species: [dog]`), `senior-cat` (`species: [cat]`), `multi-cat` (`species: [cat]`). Markdown only; loader already supports.
- [ ] 5.14 Phase wrap-up commit + summary; flag **on-device verification REQUIRED**.

**On-device verification (REQUIRED):**
1. Cold launch → adaptive launcher icon visible on home screen + branded splash → arrives on the redesigned welcome page (not API key entry).
2. Walk through onboarding → confirm story-first welcome, privacy disclosure, API key framed as utility.
3. Open every screen → confirm new design system applied (palette, typography, no stray Material defaults).
4. Save a memory → confirm hero moment fires (snackbar + haptic + animation).
5. Open journal browser the morning after a weekly digest fires → confirm distinct card treatment.
6. Confirm three hero moments feel disproportionately polished vs the rest of the app.

**STOP.**

---

## Phase 6 — Feature Depth & AI Capabilities

**Goal:** take the app from "personal AI agent for pets, basic" to "personal AI agent for pets, sophisticated." Foundation → expansion: storage + display surface first, then capability features that consume them. Multimodal input is constrained to "describes what it sees, never diagnoses" per the medical-safety guardrails in DECISIONS row 29 + PRODUCT.md "What PetPal is NOT".
**Definition of done:** "I'd pay $7.99/mo for this" is a credible reaction. Photos are first-class wiki entries with a timeline view; vet visits have structured frontmatter that auto-creates follow-up reminders; weight + recurring-symptom charts surface on the profile; weekly summary surfaces trends and anomalies, not just a recap.

- [ ] 6.1 Photo storage layer — per CLAUDE.md §5, photos are `wiki/<pet_id>/photos/<id>.jpg + <id>.md`. Implement `WikiRepo` extension to write image bytes + sidecar markdown atomically. Storage budget cap (warn at 500 MB per pet, hard limit 1 GB v1). FTS5 indexes the sidecar caption.
- [ ] 6.2 Pet profile photo — single photo on the SOUL profile, used in home greeting + chat appbar. Validates the storage layer with smallest UI surface.
- [ ] 6.3 Photo timeline screen — `/photos` route, time-ordered grid of every photo across the pet's wiki. Tap → entry. Reuses Phase 5 design system.
- [ ] 6.4 Multimodal chat input — photo upload to chat. **Constrained: PetPal describes what it sees, never diagnoses.** Vision request via Anthropic API; response runs through the existing `RedFlagScreener`. New tool `attach_photo` registered alongside existing chat tools. New DECISIONS row capturing the constraint explicitly.
- [ ] 6.5 Vet-visit structured entry type — new entry kind `wiki/<pet>/vet/YYYY-MM-DD-<slug>.md` with structured frontmatter (`vet_name`, `reason`, `diagnosis`, `prescriptions: []`, `follow_up_date`). Form-driven creator UI; freeform fallback for non-vet entries.
- [ ] 6.6 Auto-follow-up reminders — when a vet-visit entry has `follow_up_date`, auto-create a `notification`-mode reminder. Reuses existing scheduling stack.
- [ ] 6.7 Weight + symptom trend charts — add `fl_chart` dep (DECISIONS row required). Charts: weight time-series, recurring-symptom frequency. Surface on the SOUL profile.
- [ ] 6.8 Smarter weekly summary — upgrade `lib/harness/synthesis/weekly_digest.dart` to surface trends, anomalies, gentle observations ("Loki's weight has trended down for 3 weeks"). New synthesis prompt; no new infrastructure.
- [ ] 6.9 Phase wrap-up commit + summary; flag **on-device verification REQUIRED**.

**Cuts (deferred to v1.1 or Phase 7):**
- *Multi-pet UI improvements* → Phase 7 (free tier = 1 pet per DECISIONS row 8; multi-pet UI is Pro-only, belongs alongside the paywall).
- *Onboarding intelligence (auto-populate from photos/voice)* → v1.1 (vision-based species/breed inference is locked OUT by DECISIONS row 25; voice transcription adds new dependency).
- *Medication tracking* → v1.1 (significant data model — durations, doses, side effects, course-end prompts; overlaps with reminders).
- *Caregiver/family sharing preview* → v1.1 (PDF export work delays shipping; not core to the compounding-memory thesis).
- *Improved chat (reactions, edit/delete, threading)* → v1.1 (edit/delete contradicts "memory persists"; threading over-engineered; search is genuinely useful — defer with the rest, revisit in v1.1).

**On-device verification (REQUIRED):**
1. Add a profile photo to a pet → confirm it renders on home greeting + chat appbar.
2. Take/upload a photo from chat ("here's Loki's paw") → confirm PetPal describes what it sees and does not diagnose; confirm the response runs through the red-flag screener.
3. Create a vet-visit structured entry with a `follow_up_date` → confirm a reminder appears in `/reminders` automatically.
4. Open the photo timeline → confirm time-ordered grid + tap-to-entry.
5. Open the SOUL profile after several weight log entries → confirm chart renders.
6. Wait or fast-forward to a weekly digest → confirm it surfaces trends/anomalies, not just a recap.

**STOP.**

---

## Phase 7 — Monetization, Cloud Sync, Multi-Pet UI

**Goal:** Pro subscription, one expert-pack IAP, cloud sync chosen and implemented, multi-pet UI behind the paywall, accessibility pass. (Renamed from old Phase 5: dropped redundant "Polish" — Phase 5 covers that — added "Multi-Pet UI" since multi-pet moves here from the Phase 6 candidate list.)
**Definition of done:** subscribe with a Play tester account → install on a second device → wiki syncs; multi-pet works for Pro users; accessibility pass clean.

- [ ] 7.1 Tier service (free: 1 pet, 30-day memory window) and gating checks
- [ ] 7.2 `in_app_purchase` integration: monthly + annual subs
- [ ] 7.3 One expert-pack IAP wired (e.g., "Senior Dog")
- [ ] 7.4 Paywall screens + restore-purchases
- [ ] 7.5 Multi-pet UI improvements — pet switcher widget, cross-pet timeline, family-wide reminders. Lives behind the Pro paywall. (Moved from the original Phase 6 candidate list per DECISIONS row 34.)
- [ ] 7.6 **Cloud sync backend decision** (Supabase vs git-remote vs BYOC object store) — append to `DECISIONS.md`
- [ ] 7.7 Implement `CloudSyncAdapter` against the chosen backend
- [ ] 7.8 Conflict resolution: last-writer-wins with `.conflict.md` fallback
- [ ] 7.9 Settings: data export, data delete, privacy info screen
- [ ] 7.10 Accessibility pass: contrast, screen reader labels, text scaling, touch-target sizes
- [ ] 7.11 Opt-in crash analytics (lightweight)
- [ ] 7.12 Phase wrap-up commit + summary

**On-device verification:** subscribe with tester account on device A → install on device B → confirm wiki syncs; add a second pet and confirm pet switcher works; trigger a conflict and confirm `.conflict.md` is created.

**STOP.**

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
