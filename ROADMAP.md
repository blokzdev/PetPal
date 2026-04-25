# PetPal Roadmap

Six phases. Tasks are sized to ≤30 min of agent work. Every phase ends with a deliverable I can verify on a real Android device, and a hard stop. The agent does not auto-advance.

**Current phase: Phase 2 — Agent Loop & Chat MVP (in progress; next task 2.2). Phase 1 + 2 device verification batched per DECISIONS row 21.**

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
- [ ] 2.7 Wiki browser: folder tree + markdown viewer, tap to open
- [ ] 2.8 `SOUL.md` editor: form for frontmatter, free-text for prose, save round-trips through `wiki_io`
- [ ] 2.9 Pet switcher: schema supports many, UI gates to 1 (free-tier rule, even though no paywall yet)
- [ ] 2.10 Error surfaces: API failure, rate-limit, offline — clear, retryable UI states
- [ ] 2.11 Export: zip `wiki/<pet>/` → Android share sheet
- [ ] 2.12 `CloudSyncAdapter` interface stub committed (no implementation; Phase 5 decides backend)
- [ ] 2.13 Integration test: full happy-path chat → entry written → retrievable
- [ ] 2.14 Phase wrap-up commit + summary

**On-device verification:** install fresh, onboard, add Milo, chat "Milo ate chicken yesterday and got itchy paws," verify a food/allergy entry appears in the wiki browser, export and confirm zip arrives in another app.

**MVP achieved at end of Phase 2. STOP.**

---

## Phase 3 — Skills & Synthesis

**Goal:** installable skill packs with progressive loading; weekly synthesis-mode digest.
**Definition of done:** install built-in "Puppy" skill → puppy-relevant questions show clear behavioral shift in answers → after a week of entries, a weekly digest entry appears in the wiki.

- [ ] 3.1 Skill manifest parser (YAML frontmatter)
- [ ] 3.2 `SkillLoader`: scan installed skills, match triggers, return matched fragments
- [ ] 3.3 Inject matched fragments into next turn via `SessionBuilder` (prompt-cached)
- [ ] 3.4 Bundle built-in "Puppy" skill as an asset under `assets/skills/puppy/`
- [ ] 3.5 Skill browser screen: installed / available, enable/disable
- [ ] 3.6 Synthesis-mode scheduled task: weekly per-pet digest written as a wiki entry
- [ ] 3.7 Settings toggle for weekly digest
- [ ] 3.8 Tests: trigger matching, fragment selection, digest entry shape
- [ ] 3.9 Phase wrap-up commit + summary

**On-device verification:** enable Puppy skill, ask "how do I house-train Milo," confirm response references skill content; wait or fast-forward to confirm weekly digest appears.

**STOP.**

---

## Phase 4 — Scheduling & Medical Guardrails

**Goal:** zero-token reminders fire on time; red-flag detection runs in code before every LLM call.
**Definition of done:** set a flea-treatment reminder for tomorrow → it fires while the app is killed → typing "Milo has blood in stool" yields a vet-escalation preamble before any other content.

- [ ] 4.1 `Reminder` schema is already in Drift (Phase 1) — add CRUD UI
- [ ] 4.2 Wire `android_alarm_manager_plus` + `flutter_local_notifications` for exact-time
- [ ] 4.3 Wire `workmanager` for condition-gated work (embedding batches, future sync)
- [ ] 4.4 `schedule_reminder` tool exposed to the agent
- [ ] 4.5 Deterministic reminder templates (flea, heartworm, vaccine due, weight check)
- [ ] 4.6 Red-flag rule table in `harness/guardrails/red_flags.dart` (regex/keyword)
- [ ] 4.7 Pre-response screener: runs before every LLM call; on match, augments system prompt with mandatory escalation directive
- [ ] 4.8 Escalation copy + UI badge on flagged responses
- [ ] 4.9 Battery-optimization exemption prompt on first reminder schedule
- [ ] 4.10 Tests: red-flag detection coverage on a fixture corpus; reminder fire time accuracy
- [ ] 4.11 Phase wrap-up commit + summary

**On-device verification:** schedule a reminder, force-stop the app, confirm it fires; type a red-flag phrase, confirm escalation appears first.

**STOP.**

---

## Phase 5 — Monetization, Cloud Sync, Polish

**Goal:** Pro subscription, one expert-pack IAP, cloud sync chosen and implemented, accessibility pass.
**Definition of done:** subscribe with a Play tester account → install on a second device → wiki syncs.

- [ ] 5.1 Tier service (free: 1 pet, 30-day memory window) and gating checks
- [ ] 5.2 `in_app_purchase` integration: monthly + annual subs
- [ ] 5.3 One expert-pack IAP wired (e.g., "Senior Dog")
- [ ] 5.4 Paywall screens + restore-purchases
- [ ] 5.5 **Cloud sync backend decision** (Supabase vs git-remote vs BYOC object store) — append to `DECISIONS.md`
- [ ] 5.6 Implement `CloudSyncAdapter` against the chosen backend
- [ ] 5.7 Conflict resolution: last-writer-wins with `.conflict.md` fallback
- [ ] 5.8 Settings: data export, data delete, privacy info screen
- [ ] 5.9 Accessibility pass: contrast, screen reader labels, text scaling, touch-target sizes
- [ ] 5.10 Opt-in crash analytics (lightweight)
- [ ] 5.11 Phase wrap-up commit + summary

**On-device verification:** subscribe with tester account on device A → install on device B → confirm wiki syncs; trigger a conflict and confirm `.conflict.md` is created.

**STOP.**

---

## Phase 6 — Play Store Prep & Launch

**Goal:** signed AAB on internal testing track, store listing approved.
**Definition of done:** install via Play internal track on a fresh device; sandboxed billing flow works end-to-end.

- [ ] 6.1 Adaptive icon + splash
- [ ] 6.2 Privacy policy hosted; Data Safety form drafted (LLM calls leaving the device disclosed)
- [ ] 6.3 Store listing copy + 1 phone + 1 7" tablet screenshot set
- [ ] 6.4 Release keystore generated; Play App Signing enrolled
- [ ] 6.5 R8/ProGuard rules verified for Drift and Anthropic SDK
- [ ] 6.6 `flutter build appbundle --release`
- [ ] 6.7 Upload AAB to internal testing track
- [ ] 6.8 Triage Play pre-launch report
- [ ] 6.9 Closed testing checklist + invite list
- [ ] 6.10 Phase wrap-up commit + summary

**On-device verification:** install via Play internal track on a fresh device, run sandboxed billing flow.

**STOP. Ready for launch decision.**
