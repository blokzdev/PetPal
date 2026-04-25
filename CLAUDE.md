# PetPal — Working Guide for Claude

> This file is the **harness**. Anything important must live here, in `ROADMAP.md`, in `DECISIONS.md`, or in committed code. Chat context does not survive across sessions.

---

## 1. Start-of-session protocol

At the start of every session, in this order:

1. Read `CLAUDE.md` (this file).
2. Read `ROADMAP.md` — find the **current phase** and the **next unchecked task**.
3. Read `DECISIONS.md` — recent entries first, so you don't re-litigate settled choices.
4. If the user said "Continue from where we left off," begin the next unchecked task in the current phase. Confirm before acting if the task is ambiguous.
5. **Stop at the end of each phase.** Do not auto-advance.

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

- **Deterministic mode (zero-token).** A reminder fires from a stored template. No LLM call. Example: "Flea treatment due for Milo." Used for routine reminders.
- **Synthesis mode (LLM call).** A scheduled background turn produces an LLM-generated wiki entry. Example: weekly digest summarizing the week's notes. Pro-tier gated and user-toggleable.

Choose deterministic by default. Reach for synthesis only when the value depends on summarization the user can't pre-template.

---

## 9. Skills system

**Manifest** (YAML frontmatter on the skill's root file):

```yaml
---
id: puppy
name: Puppy Care
version: 1
triggers: ["puppy", "teething", "house training", "socialization"]
loads: ["overview.md", "house-training.md", "socialization.md"]
requires_pro: false
---
```

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

- Runs on every user turn before the LLM call.
- Regex/keyword table over the input.
- On match: the system prompt for that turn is augmented with a mandatory escalation directive, and the UI shows a "vet escalation" badge on the response.

### Escalation copy (canonical)

> This sounds urgent — please contact your vet or an emergency animal hospital now. I can help you note what's happening so you have it ready when you call.

The agent then offers to log the symptoms and timing as a wiki entry.

---

## 11. MVP screen list (delivered by end of Phase 2)

1. Onboarding (welcome, API key entry, privacy disclosure)
2. Add pet (name, species, breed, DOB → seeds `SOUL.md`)
3. Chat (message list + composer)
4. Pet switcher (free tier: 1 pet)
5. Wiki browser + markdown viewer
6. Settings (API key, export wiki as zip)

Reminders, skills, paywall, sync are explicitly **not** in MVP.

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
| Cloud sync backend | **Deferred to Phase 5.** `CloudSyncAdapter` interface lands in Phase 2. |

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
- **Hit ambiguity → stop and ask.** Don't guess.
- **Plan needs to change → propose, wait for approval, then edit `ROADMAP.md`.** Never silently re-plan.
- **End of phase → hard stop.** Summarize: what changed, what to verify on the Android device, what's next. Do not auto-start the next phase.

### Definition of done (per task)

- Code compiles, `flutter analyze` clean.
- Touched code has at least one unit test where unit-testable.
- Commit on `claude/petpal-planning-S9DXN` with a clear message.
- `ROADMAP.md` updated.
- If the choice was non-obvious: `DECISIONS.md` updated.

### Phase-end self-verification pass

At each phase boundary, before reporting the phase complete, run all three:

1. `flutter analyze` — must be clean.
2. `flutter test` — must pass.
3. `flutter build apk --debug` — must produce an APK; report the path and size.

Report the results in the phase wrap-up summary. If any step fails, the phase is **not** complete — stop and fix before reporting.

For phases that introduce new runtime behavior (data, networking, scheduled tasks, billing), also explicitly flag in the wrap-up that **on-device verification is recommended and cannot be substituted** by these checks. Phase 0 (pure scaffold) is the only phase that can defer device testing.

### Installable release builds for on-device verification

The CI workflow's `release-apk` job runs `flutter build apk --release --split-per-abi` on every push to `main` and `claude/**` (and via `workflow_dispatch`). It uploads three artifacts with 7-day retention:

| Artifact name | ABI | Use this when |
|---|---|---|
| `petpal-release-arm64-v8a` | arm64-v8a | **Default for any phone made roughly post-2017.** Pixel, Galaxy, OnePlus, Xiaomi — almost certainly arm64-v8a. |
| `petpal-release-armeabi-v7a` | armeabi-v7a | Older / budget 32-bit ARM phones. Verify with `adb shell getprop ro.product.cpu.abi` if unsure. |
| `petpal-release-x86_64` | x86_64 | Most Android emulators (AVD, Genymotion). Not for physical phones. |

**To install on a phone:**

1. **Find the artifact.** GitHub → repository → Actions → click the latest green run on your branch → scroll to the *Artifacts* section at the bottom → download the matching `petpal-release-<abi>` zip.
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

See `ROADMAP.md`. Six phases: Phase 0 (scaffold) → Phase 6 (Play Store). MVP at end of Phase 2.

---

## 16. Do-not-do list (scope discipline)

- No iOS builds until post-launch.
- No vet-facing features. No diagnostic claims. Ever.
- No multi-user / shared pets before Phase 5.
- No agentic autonomy beyond the approved tool catalog.
- No silent re-planning. No auto-advancing phases.
- No new dependencies without a `DECISIONS.md` entry.
- No "while I'm here" refactors. Stay on the current task.
