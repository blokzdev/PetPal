# PetPal — Working Guide for Claude

> This file is the **harness**. Anything important must live here, in `ROADMAP.md`, in `DECISIONS.md`, or in committed code. Chat context does not survive across sessions.

---

## 1. Start-of-session protocol

At the start of every session, in this order:

1. Read `CLAUDE.md` (this file).
2. Read `ROADMAP.md` — find the **current phase** and the **next unchecked task**.
3. Read `DECISIONS.md` — recent entries first, so you don't re-litigate settled choices.
4. **Branch check (DECISIONS row 93 enforcement, supersedes rows 37 + 86).** Trunk is `main`; branch protection requires the `ci / analyze + test` check before merge. Each subphase = a **fresh branch off the current `main`** named `claude/<descriptive-slug>` → one PR → user merges + deletes → re-sync local `main` (`git fetch origin main && git checkout main && git reset --hard origin/main`) before cutting the next. Run `git branch --show-current`: if you're on `main`, cut a fresh subphase branch before touching anything. If you're on a stale `claude/<slug>` from a previous session (its PR already merged + closed), the branch is dead — sync `main` and cut fresh; never stack new work on a merged branch. If the harness brief named a different branch than this protocol implies, **surface the mismatch to the user before any commits land** and let them pick — the failure mode is silent drift across sessions, and the protection is making the decision explicit on every session start. Stop and ask if unsure.
5. If the user said "Continue from where we left off," begin the next unchecked task in the current phase. Confirm before acting if the task is ambiguous.
6. **Stop at the end of each phase.** Do not auto-advance.

---

## 2. Mission and positioning

**PetPal is a per-pet memory agent for pet owners.** The user chats; the agent maintains a markdown wiki and a `SOUL.md` persona file for each pet. Over weeks and months that wiki becomes the user's accumulated knowledge of their pet — vet visits, weight trends, food trials, behavior notes — and the agent uses it to give grounded, specific answers.

**The moat is the wiki, not the chat.** Chat is the interface. The corpus is the product.

**Positioning: "track + know when to call the vet."** Never diagnosis, never a vet replacement, never a generic chatbot. Medical-safety guardrails are mandatory and run in code, not just in the prompt.

---

## 3. Harness vs application (the core mental model)

Two layers, separated rigorously:

- **Harness / runtime:** agent loop, tool dispatcher, context manager (`SessionBuilder`), retrieval (FTS5 + vector), scheduler bridge, skill loader, guardrails. Stable, reused across every flow. Lives in `lib/harness/`.
- **Application:** Flutter UI, chat surface, billing, onboarding, settings, channels. Lives in `lib/app/` and `lib/platform/`.

**Rule:** features live in the harness when they are agent-visible (tools, retrieval, system prompt). They live in the application when they are only user-visible (theming, screens, paywall flow).

**Species-agnostic by design.** The harness has no built-in awareness of dogs, cats, or any specific animal. Species-specific behaviour enters through exactly two seams:

1. **Onboarding templates** seed `SOUL.md` with sensible per-species defaults (frontmatter keys, vet-contact prompt copy, weight units, common allergens). Picking "Cat" during add-pet does not change a single byte of harness code — it only changes the markdown the harness sees.
2. **Skill packs** (Phase 3) carry a `species:` field in their manifest frontmatter. The skill loader filters available skills by the active pet's species before checking triggers, so a dog-only skill never injects fragments into a cat session.

The same agent loop, the same retrieval, the same red-flag screener serves a parakeet and a Great Dane. Everything else is data.

---

## 3.5 Intake dimensions: router + lens pattern

A **lens** is how a husbandry dimension lands in the wiki. Each lens bundles five things: an **extraction schema** (what we read from the input), **structured frontmatter** (what we store), **deterministic rules** (what we screen for), **synthesis signals** (what we surface), and a **reminder kind** (what we can schedule).

The **intake intent router** sits on top of the existing photo-intake surface and resolves user input to an intent before the lens fires. Same photo gesture, different intents — e.g. `logMealAfter`, `checkMealBefore`, `generalMemory`. Resolution is hybrid:

- explicit toggle present → authoritative
- explicit toggle absent → light LLM classification, soft cases only

Food is lens #1 (Phase 8). Grooming, enclosure/environment, activity/enrichment, body-condition-over-time are downstream candidates. **The pattern is the durable part; the food feature is how we earn it.** Future lenses drop into the same five slots and reuse the same router.

The router lives in `lib/harness/intake/`. Each lens threads the existing harness modules — extractor → `vision/`, screener → `guardrails/`, frontmatter → `wiki_io.dart`, signal → `synthesis/`, reminder kind → `scheduling/` — rather than introducing parallel infrastructure.

---

## 4. Architecture diagram

```
+----------------------------------------------------------+
|                    Flutter UI Layer                      |
|  Chat • Pet list • Wiki browser • Reminders • Settings   |
+---------------------------+------------------------------+
                            |  (Riverpod / method channels)
+---------------------------v------------------------------+
|                  Agent Harness (Dart)                    |
|  SessionBuilder → SystemPrompt + SOUL.md + RetrievedCtx  |
|  AgentLoop  (turn → tool-calls → tool-results → turn)    |
|  ToolDispatcher (wiki I/O, search, schedule, red-flag)   |
|  SkillLoader   (manifest scan + progressive injection)   |
|  Guardrails    (deterministic red-flag pre-screener)     |
+---+--------------------+-----------------+---------------+
    |                    |                 |
+---v----+         +-----v-----+      +----v---------+
| LLM    |         | Storage   |      | Scheduler    |
| Claude |         | SQLite +  |      | AlarmManager |
| API    |         | FTS5 +    |      | + WorkMgr    |
| (cache)|         | sqlite-vec|      | + Notifs     |
+--------+         +-----+-----+      +----+---------+
                         |                 |
                   wiki/<pet>/*.md    notifications
                   SOUL.md per pet    (deterministic +
                   skills/*.md         synthesis modes)
```

---

## 5. Data model

### File tree (source of truth)

```
wiki/<pet_id>/
  SOUL.md                          # YAML frontmatter + identity prose
  vet/YYYY-MM-DD-<slug>.md         # vet visits
  weight/log.md                    # appended weight log
  behavior/*.md                    # behavior notes
  food/*.md                        # food trials, allergies
  photos/<id>.jpg + <id>.md        # image + sidecar markdown
skills/<skill_id>/
  manifest.yaml
  *.md                             # skill fragments
```

Files are the **source of truth**. SQLite is a rebuildable index.

### SQLite (Drift)

```
pets               (id, name, created_at)
entries            (id, pet_id, path, type, ts, title, body_hash)
entries_fts5       (FTS5 mirror of entries.title + body)
embeddings         (entry_id, chunk_idx, vector)        -- sqlite-vec
sessions           (id, pet_id, started_at)
messages           (id, session_id, role, content, ts)
reminders          (id, pet_id, kind, when_ts, mode, payload)
skills_installed   (skill_id, version, enabled)
```

### `SOUL.md` shape

```yaml
---
species: dog
breed: mixed
dob: 2022-06-12
weight_kg: 14.2
allergies: [chicken]
meds: []
vet_contact: "Dr. Patel — Maple Vet — (555) 123-4567"
temperament: ["anxious-around-strangers", "food-motivated"]
---

# Milo
Milo is a rescue mutt who came home in October 2023. He has a deep
fear of skateboards and a soft spot for frozen carrots. ...
```

---

## 6. Agent system prompt (canonical)

The system prompt is built per-turn by `SessionBuilder` from these blocks, in order:

1. **Identity block** — fixed string, edited only via PR:
   > You are PetPal, a memory-first companion for **{pet.name}**. You help the owner track their pet's life and know when to call the vet. You never diagnose. You ground every answer in the pet's wiki.
2. **`SOUL.md`** of the active pet — injected verbatim, prompt-cached.
3. **Active skill fragments** — only fragments whose triggers matched the user input; prompt-cached.
4. **Retrieved context** — top-k from hybrid FTS5+vector retrieval over the pet's wiki, freshly composed each turn.
5. **Output contract**:
   - Use tool calls for state changes (`write_wiki_entry`, `update_soul`, `schedule_reminder`).
   - Cite entry paths (`wiki/milo/vet/2026-01-12-checkup.md`) when referencing facts.
   - When the red-flag screener has flagged this turn, your response **must** open with vet-escalation language before any other content.

---

## 7. Tool catalog (harness-exposed)

| Tool | Purpose |
|---|---|
| `read_wiki(path)` | Return the markdown body at `path` |
| `search_wiki(query, pet_id)` | Hybrid FTS5 ∪ vector kNN, dedup by entry |
| `write_wiki_entry(path, body)` | Atomic write; updates FTS5 + queues embedding |
| `update_soul(pet_id, patch)` | Merge frontmatter patch into `SOUL.md` |
| `log_weight(pet_id, kg, ts)` | Append to `weight/log.md` |
| `schedule_reminder(pet_id, kind, when, mode)` | `mode ∈ {deterministic, synthesis}` |
| `list_reminders(pet_id)` | Return active reminders |
| `red_flag_check(symptoms[])` | Programmatic check; also runs as pre-screener |
| `load_skill(skill_id)` | Inject skill fragments into next turn |

New tools require a `DECISIONS.md` entry and a unit test.

---

## 8. Scheduled-task modes

PetPal follows SemaClaw §3.6's four-mode scheduled-task taxonomy. Mode is stored as a string in the `reminders.mode` text column. The agent's `schedule_reminder` tool defaults to `notification` when mode is unspecified.

| Mode               | LLM tokens | User-visible at fire? | Engine                                       | Canonical example |
|--------------------|------------|------------------------|----------------------------------------------|-------------------|
| `notification`     | 0          | Yes — system notification | AlarmManager + flutter_local_notifications | "Flea treatment due Friday for Loki" |
| `script`           | 0          | No — silent side effect | WorkManager → registered Dart task          | Monthly weight-chart roll-up; vacuum stale FTS rows |
| `synthesis`        | LLM call   | No — writes a journal entry | WorkManager → SynthesisRunner               | Weekly summary entry under `wiki/<id>/digest/` |
| `synthesisNotify`  | LLM call   | Yes — notification post-fire | WorkManager → SynthesisRunner → notification | "Loki's weekly summary is ready" (Pro tier) |

Choose `notification` by default. Reach for `script` when the work is data-only and shouldn't interrupt the user. Reach for `synthesis` when the value depends on summarization that can't be pre-templated. `synthesisNotify` is reserved for Phase 7+ Pro features (weekly summary + monthly health report notifications, per DECISIONS row 36) and is currently a stubbed dispatcher branch.

The taxonomy is locked in DECISIONS row 28.

---

## 9. Skills system

**Manifest** (YAML frontmatter on the skill's root file):

```yaml
---
id: puppy
name: Puppy Care
version: 1
species: [dog]                    # filter — see "Species filtering" below
triggers: ["puppy", "teething", "house training", "socialization"]
loads: ["overview.md", "house-training.md", "socialization.md"]
requires_pro: false
---
```

**Species filtering.** The `species:` list is the first gate: `SkillLoader` skips any skill whose list doesn't include the active pet's species (read from `SOUL.md` frontmatter). A skill with `species: [dog, cat]` matches both; an empty or omitted `species:` is treated as "any species" so universal skills stay easy to author. Trigger matching only runs against the species-filtered subset. This is the harness's only species-aware code path — see §3.

**Progressive loading.** When the user input matches one or more triggers, only the matched fragments are injected into the next turn — never the whole skill. This keeps context budgets sane and makes attribution straightforward.

---

## 10. Medical-safety guardrails

Guardrails are **code, not prompts**. The system prompt reinforces; the deterministic screener enforces.

### Red-flag list (starter; expand as evidence accumulates)

- Blood in stool or vomit
- Repeated vomiting (>3 episodes in 24h)
- Lethargy + anorexia >24h
- Seizure
- Bloated/distended abdomen
- Pale gums
- Suspected toxin ingestion (chocolate, xylitol, grapes, lilies, etc.)
- Labored breathing
- Collapse / loss of consciousness
- Suspected fracture or major trauma

### Pre-response screener

- Runs on every user **chat turn** before the LLM call. **Scope is chat input only** — wiki-entry text the user composes directly is never screened, since wiki entries are legitimately retrospective (a vet visit recorded after the fact may name urgent symptoms that are no longer urgent). Phase 6 task 6.7 locked an extension to vision findings: `RedFlagScreener.screenWithVision({chatInput, visionExtracted})` (`lib/harness/guardrails/red_flag_screener.dart`) routes the photo extractor's `freeform_caption + notable_objects` through the same screener as a second source, tagged `RedFlagSource.vision`. Per-category coverage matches the chat fixture floor (≥10 vision-cadence positives per category in `red_flags_fixture.dart`'s `visionPositives` map). Wiki-entry text remains never-screened.
- Regex/keyword table over the input. Case-insensitive, word-bounded, false-positive-tolerant per the design lock in DECISIONS row 29.
- On match: the system prompt for that turn is augmented with a mandatory escalation directive (one-shot, this turn only), and the UI shows a "vet escalation" badge on the assistant response. The badge is **subdued in stature** (small icon, no large alert chrome) but uses **coral as its primary color** — coral is the systemic medical-warning register across PetPal (red-flag badge, vet `EditorialCard` left-border, MEDICAL NOTE callout, photo entry red-flag area, chat scrollback escalation marker). The live preamble copy still owns the prominent live alert; the coral badge is the persistent historical marker. The badge persists forever — it's a historical record, not a current-state indicator. **Phase 6.6 amendment** (DECISIONS row 64): the original "muted color (`onSurfaceVariant` gray)" treatment was replaced once card-level coral context (vet `EditorialCard` left-border, MEDICAL NOTE callout) made a gray inner badge visually incoherent — one register wins, and coral is the system medical-attention primary. The "failures are failures" register (`scheme.error`, M3-default red) stays distinct from medical-attention coral; the two should not blur.

### Escalation copy (canonical, locked)

> This sounds urgent — please call your vet or an emergency animal hospital now. PetPal is software, not a vet. I can help you write down what's happening so it's ready when you call.

This copy is mirrored in VOICE.md §6 example 10. The agent then offers to log the symptoms and timing as a wiki entry.

### Coverage rule

Every red-flag category ships with **≥30 positive phrasings + ≥20 negative phrasings** in `test/harness/guardrails/red_flags_fixture.dart`. New patterns require new fixtures in the same commit. The defense-in-depth model (code primary, prompt backup, user-visible audit) is locked in DECISIONS row 29.

### Food hazard gate (Phase 8.3)

`FoodHazardScreener` is a sibling to `RedFlagScreener` — same posture (deterministic, code-not-prompt, false-positive-tolerant per row 29), same coral badge surface, different input domain. It matches the photo extractor's `identified_items` against a bundled toxin list (`assets/hazards/food_toxins.yaml`) and fires the coral medical-attention register on a hit. **Known toxins only** — we do not opine on nutritional quality, adequacy, or portion correctness; DECISIONS row 25 holds unchanged.

**Escalation copy on hit:** "This may be hazardous — contact your vet or animal poison control now." US locale appends ASPCA APCC (888) 426-4435 + Pet Poison Helpline (canonical number verified at implementation, never trusted from memory); other locales show the generic "contact your vet now." Numbers live in `assets/hazards/escalation.yaml`, never in any prompt — same code/config rule as the locked vet-escalation copy above (DECISIONS row 101).

**Fixture floor:** ≥10 phrasings per toxin category in `test/harness/guardrails/food_hazards_fixture.dart`, mirroring the 6.7 vision-cadence floor for red flags. New toxin entries require new fixtures in the same commit (mirror the row 29 rule).

---

## 11. MVP screen list (delivered by end of Phase 2) vs shipped v1

The **MVP** screen list — delivered by end of Phase 2 — is the architectural floor:

1. Onboarding (welcome, API key entry, privacy disclosure)
2. Add pet (name, species, breed, DOB → seeds `SOUL.md`)
3. Chat (message list + composer)
4. Pet switcher (free tier: 1 pet)
5. Wiki browser + markdown viewer
6. Settings (API key, export wiki as zip)

Reminders, skills, paywall, sync are explicitly **not** in MVP. Reminders shipped in Phase 4; skills shipped in Phase 3; paywall + sync land in Phase 7.

The **shipped v1** is not the MVP. Per DECISIONS row 34 we restructured after Phase 4: MVP architecture stays, but the v1 the user installs from the Play Store includes the Phase 5 design system + Phase 6 feature depth (photo timeline, multimodal chat, vet-visit structured entries + auto-follow-up reminders, weight/symptom trend charts, smarter weekly summary, monthly health report). The harness was past MVP-grade; the surface needed to catch up before monetization. Don't conflate "MVP done" with "ready to ship".

Per DECISIONS row 36, the v1 free tier is: 1 pet, unlimited local journal, 200 chat messages/month (red-flag-screened turns are exempt and never counted), 5 reminders, manual browsing, export. Pro lifts every cost-driven cap, adds sync, unlimited pets, weekly + monthly synthesis. BYOK is a free-tier modifier that lifts the message + vision quotas in exchange for the user supplying their own Anthropic key — calls then route direct to Anthropic, bypassing PetPal's backend.

---

## 12. Tech stack and rationale

| Choice | Rationale |
|---|---|
| Flutter | Single codebase, iOS-ready later, Riverpod ecosystem |
| Drift (over sqflite) | Type-safe schema, migrations, FTS5 helpers |
| sqlite3 (3.x, direct) | Bundles libsqlite3 on Android; replaces EOL `sqlite3_flutter_libs` |
| sqlite-vec | Vector search via loadable extension; FTS5+vec hybrid from Phase 1 |
| Anthropic API | Claude Sonnet/Opus; prompt caching for `SOUL.md` + skills |
| Riverpod | Async repositories, providers compose with the harness cleanly |
| go_router | Declarative routing |
| flutter_secure_storage | API key at rest |
| android_alarm_manager_plus | Exact-time reminders |
| flutter_local_notifications | Notification surface |
| workmanager | Condition-gated background work (sync, embeddings) |
| in_app_purchase | Play Billing for subs + IAPs |
| Cloud sync backend | **Deferred to Phase 7** (provider locked by DECISIONS row 36 follow-up in Phase 7 task 7.13). `CloudSyncAdapter` interface lands in Phase 2. |
| PetPal backend proxy | Phase 7 deliverable. LLM-call proxy (forwards Anthropic calls with our key, transparently passes `cache_control` blocks for prompt caching), auth, per-user metering (text msg/mo, vision/mo, photo-credit balance). Funds the free-tier 200-msg/mo allowance. BYOK users opt out at Settings and call Anthropic directly. Backend choice — Supabase Edge / Cloudflare Workers / dedicated Node — locked by DECISIONS row 36 follow-up in Phase 7 task 7.1. |

---

## 13. Folder structure

```
lib/
  harness/
    agent_loop.dart
    session_builder.dart
    tools/
    retrieval/
    skills/
    guardrails/
  data/
    db/                 # Drift definitions, migrations
    repos/              # PetRepo, WikiRepo, SessionRepo, ReminderRepo
    wiki_io.dart        # atomic file I/O
  app/
    screens/
    widgets/
    routing.dart
    theme.dart
  platform/
    notifications.dart
    billing.dart
    method_channels/
  models/
assets/
  skills/
test/
integration_test/
```

---

## 14. Working protocol (every session, every task)

- Tasks within a phase are **sequential**.
- **Commit after each task.** Conventional commit messages (`feat:`, `fix:`, `chore:`, `docs:`, `refactor:`, `test:`).
- **Tick off completed tasks** in `ROADMAP.md` in place — change `[ ]` to `[x]`.
- **Append to `DECISIONS.md`** whenever you make a non-obvious choice. Categories: storage, agent, scheduling, monetization, sync, ui, privacy.
- **Append to `V1X_BACKLOG.md` whenever you defer a v1 feature** to v1.1 / v1.2 / v1.x. Same commit as the deferral decision — don't ship a deferral that exists only in a DECISIONS row + conversation history. The backlog is the single source of truth for "what gets built post-launch." Each entry carries source phase / decision, DECISIONS row reference, scope estimate, dependencies, and load-bearing notes. PRODUCT.md keeps a one-line summary pointer; deeper specifics live in the backlog.
- **Hit ambiguity → stop and ask.** Don't guess.
- **Plan needs to change → propose, wait for approval, then edit `ROADMAP.md`.** Never silently re-plan.
- **End of phase → hard stop.** Summarize: what changed, what to verify on the Android device, what's next. Do not auto-start the next phase.

### Plugin-bump checklist (DECISIONS row 33)

Every pubspec version bump on a native Android plugin runs through this checklist **in the same commit** as the bump. `flutter analyze` and `flutter test` stub the platform binding, so a missing manifest entry is invisible until a user pushes the relevant button on a real device.

1. Read the new version's `example/android/app/src/main/AndroidManifest.xml` and `README.md` from `~/.pub-cache/hosted/pub.dev/<plugin>-<version>/`.
2. Diff the example manifest against `android/app/src/main/AndroidManifest.xml` — note any new permissions, services, receivers, or providers.
3. Patch our manifest with the missing pieces, with a comment pointing at the plugin and the canonical `dev.fluttercommunity.*` (or equivalent) class name.
4. Update `test/platform/android_manifest_test.dart` invariants so the new components are asserted; the next regression cannot land silently.
5. Only then ship the bump.

The Phase 4 hotfix added the three `android_alarm_manager_plus` components after the bug shipped — the rule above exists so that pattern doesn't repeat.

### Definition of done (per task)

- Code compiles, `flutter analyze` clean.
- Touched code has at least one unit test where unit-testable.
- Commit on the current `claude/<subphase>` branch (cut fresh from `main`, per §1 step 4 / DECISIONS row 93) with a clear message.
- `ROADMAP.md` updated.
- If the choice was non-obvious: `DECISIONS.md` updated.
- **Verify-before-PR (DECISIONS row 93).** Before opening or updating a PR, run `flutter analyze --fatal-infos; echo "exit=$?"` (must be `exit=0`) **and** `flutter test --reporter expanded; echo "exit=$?"` (must be `exit=0`) locally. CI runs `analyze + test` as one sequential job — if analyze fails, the test step never runs, and a red analyze can mask a broken test suite. The CI #167–187 pile-up (PR #1's recovery effort) was this failure mode in production. Don't skip this gate.

### Phase-end self-verification pass

At each phase boundary, before reporting the phase complete, run all three with the **exact CI invocations** and check the exit codes — never eyeball-grep truncated output (DECISIONS row 26):

1. `flutter analyze --fatal-infos; echo "exit=$?"` — exit must be 0. Plain `flutter analyze` is not enough; CI runs with `--fatal-infos`, which promotes info-level lints to failures.
2. `flutter test --reporter expanded; echo "exit=$?"` — exit must be 0. Don't pipe to `tail`; the failure summary can fall above the cut.
3. `flutter build apk --debug` — must produce an APK; report the path and size.

After every task too, not just phase boundaries: `flutter analyze --fatal-infos` and `flutter test` should be run with full output visible, and the exit code checked.

Report the results in the phase wrap-up summary. If any step fails, the phase is **not** complete — stop and fix before reporting.

For phases that introduce new runtime behavior (data, networking, scheduled tasks, billing), also explicitly flag in the wrap-up that **on-device verification is recommended and cannot be substituted** by these checks. Phase 0 (pure scaffold) is the only phase that can defer device testing.

### Installable release builds for on-device verification

The CI workflow's `release-apk` job runs `flutter build apk --release --split-per-abi` (ARM only — x86_64 is dropped per DECISIONS row 23). It is gated to push-to-`main` and manual `workflow_dispatch` to control CI minute burn (see §17). Two artifacts upload with **2-day retention**, and **each new run prunes the prior matching artifacts before uploading** (keep-only-latest, DECISIONS row 24) — so the *Artifacts* section on a finished run only ever shows the freshest pair, and storage stays well under the 500 MB free-tier cap. The 2-day retention is a safety net in case the prune step ever fails silently; the canonical lifetime of an APK artifact is "until the next successful build."

| Artifact name | ABI | Use this when |
|---|---|---|
| `petpal-release-arm64-v8a` | arm64-v8a | **Default for any phone made roughly post-2017.** Pixel, Galaxy, OnePlus, Xiaomi — almost certainly arm64-v8a. |
| `petpal-release-armeabi-v7a` | armeabi-v7a | Older / budget 32-bit ARM phones. Verify with `adb shell getprop ro.product.cpu.abi` if unsure. |

x86_64 (Android emulators) is no longer auto-built. Run `flutter build apk --release` locally if you need it.

**To trigger a build manually (recommended for `claude/**` working branches):**

- **From the GitHub web UI:** repository → *Actions* tab → pick the *ci* workflow in the left sidebar → *Run workflow* dropdown on the right → select the branch → *Run workflow*.
- **From the GitHub mobile app:** open the repo → tap the menu (three dots top-right on iOS, or the *Actions* tab) → *Actions* → *ci* workflow → tap *Run workflow* → select the branch → tap *Run workflow*. The build appears in the run list a few seconds later. Mobile lacks artifact download — switch to a desktop browser when the run finishes to grab the APK.

**To install on a phone:**

1. **Find the artifact.** GitHub → repository → Actions → click the latest green run on the branch → scroll to the *Artifacts* section at the bottom → download the matching `petpal-release-<abi>` zip.
2. **Unzip** on your computer. The zip contains one file: `petpal-release-<abi>.apk`.
3. **Get the APK to the phone.** Easiest paths:
   - Email it to yourself, open the attachment on the phone.
   - Drop it in Google Drive / Dropbox, open from the phone's app.
   - USB transfer to the phone's `Downloads/` folder (`adb push` works too).
4. **Enable installs from unknown sources for the file manager / browser you're opening from.** Settings → Apps → *the app you'll tap from* → Install unknown apps → toggle on. Android 8+ scopes this per-app, not globally.
5. **Tap the APK** in the file manager. Android shows "App not from Play Store" + a generic warning. Tap *Install*.
6. **First-run gotcha:** these builds are debug-signed (DECISIONS row 22). If you've installed a previous PetPal build with a different signing key, Android will refuse with "App not installed." Uninstall the old version first.

The release build is meaningfully smaller than `flutter build apk --debug` (R8 minification + tree-shaking — debug ~262 MB, release per-ABI ~50 MB) so it's also closer to what users will eventually install from the Play Store.

---

## 15. Phased build plan

See `ROADMAP.md`. **Twelve build phases**: Phase 0 (scaffold) → Phase 12 (Play Store). MVP architecture at end of Phase 2; shipped v1 at end of Phase 6 (including the Phase 5 design system + Phase 6 feature depth); paywall + sync in Phase 7. The original plan was six phases — DECISIONS row 34 captures the post-Phase-4 restructure that inserted Phase 5 (Product Polish & Visual Identity) and Phase 6 (Feature Depth & AI Capabilities) before the original monetization phase (now Phase 7). Row 36 captures the Phase-7 monetization-model overhaul: unlimited free local memory (no cap), cost-bounded Pro quotas (200 msg/mo free funded by a PetPal-hosted LLM proxy; unmetered text + 30 vision/mo + sync on Pro), BYOK as a free-tier modifier, photo credit packs for vision overage, dropped lifetime tier. **DECISIONS row 97 captures the Phase-8 restructure that inserted Phases 8–11 (feeding intake → scheduling → trends → synthesis) ahead of the launch phase (renumbered 8 → 12); the post-launch on-device inference placeholder renumbers from former Phase 9 to Phase 13 (V1X-deferred / scoping-only per row 85, posture unchanged).**

---

## 16. Do-not-do list (scope discipline)

- No iOS builds until post-launch.
- No vet-facing features. No diagnostic claims. Ever.
- No multi-user / shared pets before Phase 5.
- No agentic autonomy beyond the approved tool catalog.
- No silent re-planning. No auto-advancing phases.
- No new dependencies without a `DECISIONS.md` entry.
- No "while I'm here" refactors. Stay on the current task.

---

## 17. CI cost budget

GitHub Actions free-tier (private repo) caps:

- **2,000 minutes / month** of Linux runner time.
- **500 MB** total artifact + cache storage at any point.

Headroom matters. The CI is shaped to stay well clear of both ceilings:

- **`flutter` job (analyze + test)** runs on every push to `main` and on every PR. Working `claude/**` branches are validated through their PR (the always-open-a-PR workflow), so `push` is scoped to `main` to avoid double-firing the job once for the branch push and once for the PR event. Fast (~1–2 min with the Flutter SDK cache). Burn rate ≈ negligible even at heavy commit volume.
- **`release-apk` job** runs **only** on push-to-`main` and manual `workflow_dispatch` (DECISIONS row 23). Working branches don't auto-build APKs. A typical release build is ~5–10 min; manually triggering once or twice a day for verification stays under 300 min/month.
- **APK splits are ARM-only.** Dropping x86_64 cuts artifact storage roughly 1/3 and saves ~1 minute per run. Emulator users build locally.
- **Keep-only-latest artifact pruning** (DECISIONS row 24). Each `release-apk` run deletes the prior `petpal-release-arm64-v8a` and `petpal-release-armeabi-v7a` artifacts via `actions/github-script` before uploading the new pair, so steady-state storage is just one pair (~100 MB), not N runs × ~100 MB. Retention is set to **2 days** as a safety net in case the prune step silently no-ops.
- **`subosito/flutter-action@v2` SDK cache (`cache: true`)** is enabled on both jobs. First cache miss costs ~2 min for the SDK download; every run after restores in seconds.

If burn approaches the cap, the lever is to drop `release-apk`'s push-to-main trigger and rely on `workflow_dispatch` only.
