# v1.x Backlog

Source-of-truth for v1.x candidate features — anything deferred from
v1 phases that we intend to revisit post-launch. **Every v1 deferral
lands here in the same commit as the deferral decision** (CLAUDE.md
§14 working protocol). PRODUCT.md "What's coming after v1" keeps a
one-line summary pointer to this file; deeper specifics live here.

## Schema

Each entry uses the same shape:

- **Source:** when/where the deferral happened (phase number, session
  context).
- **DECISIONS:** row number(s) referenced. `—` if none yet.
- **Scope:** small (≤2 task-days) / medium (~1 week) / large (~2+
  weeks) — rough sizing for prioritization, not a commitment.
- **Dependencies:** what has to ship first.
- **Notes:** specifics worth preserving (schema, UI shape, behaviour
  invariants) so future-us can build without re-litigating.

## Tiers

- **v1.1** — first post-launch maintenance window. Small fixes,
  real-user signal absorption, items with clear scope that didn't
  fit the v1 critical path.
- **v1.2 candidate** — committed future direction, locks once we
  have ~6 months of real v1 usage data. Larger features that depend
  on knowing how users actually use v1.
- **v1.x** — post-launch with no specific window. Items where the
  trigger to revisit is "a real user case surfaces" or "we get more
  signal," not "the v1.1 / v1.2 ship calendar."

---

## v1.1

### Onboarding intelligence (auto-populate from photos / voice)

- **Source:** Phase 6 cuts (ROADMAP.md line 302).
- **DECISIONS:** 25 (medical/clinical vision gate — vision-based
  species/breed inference stays locked OUT regardless).
- **Scope:** Medium.
- **Dependencies:** Phase 6 vision pipeline; v1 photo capture flow;
  potential voice-transcription dependency (new; not in v1 stack).
- **Notes:** Original Phase 6 candidate. **Vision-based species /
  breed inference stays locked OUT** under DECISIONS row 25 even in
  v1.1; the in-scope work is photo-extracted *non-clinical* facts
  (date stamp, simple subject framing) auto-populating the add-pet
  form. Voice transcription adds a new dependency (likely on-device
  whisper or platform speech APIs) so will need its own DECISIONS
  row at the time. Skip if v1 onboarding completion rate is healthy.

### Medication tracking

- **Source:** Phase 6 cuts (ROADMAP.md line 303).
- **DECISIONS:** —.
- **Scope:** Large.
- **Dependencies:** v1 reminders stack (Phase 4); SOUL `meds:` field
  (already shipped in v1 SOUL frontmatter).
- **Notes:** Significant data model: durations, dose schedules,
  side-effect logs, course-end prompts. Overlaps with the existing
  reminders surface — design needs to avoid two-system confusion.
  Out of v1 because the data model is non-trivial and the v1
  reminders surface already captures the "remind me to give the
  medication" use case via the existing reminder kinds.

### Caregiver / family sharing preview

- **Source:** Phase 6 cuts (ROADMAP.md line 304).
- **DECISIONS:** —.
- **Scope:** Medium.
- **Dependencies:** v1 sync layer (Phase 7); PDF export tooling
  (new).
- **Notes:** "Preview" framing because the full multi-user model
  (family accounts, per-pet ACL, real-time sync) is a Phase 7+
  problem. v1.1 candidate is a one-off PDF export of the pet's
  recent journal that the owner can share with a sitter / vet /
  family member. Useful but not core to the compounding-memory
  thesis; PDF export work delays shipping.

### Improved chat (reactions, edit/delete, threading, search)

- **Source:** Phase 6 cuts (ROADMAP.md line 305).
- **DECISIONS:** —.
- **Scope:** Medium (4 sub-features).
- **Dependencies:** v1 chat surface; FTS5 index over message bodies
  (new — currently FTS5 indexes wiki entries only).
- **Notes:** **Edit/delete contradicts "memory persists"** — the
  v1.x revisit needs to decide whether to add it at all, or only
  ship reactions + search. Threading is over-engineered for a
  single-pet single-user chat. **Search is genuinely useful** and
  is the strongest sub-feature here; if the four ship separately,
  search ships first and the rest gate on UX signal.

### Horse as 9th category

- **Source:** Phase 5.5 species-catalog scoping.
- **DECISIONS:** 46 (Tier 1 breed structure — horse explicitly
  deferred to v1.1).
- **Scope:** Medium.
- **Dependencies:** None (additive).
- **Notes:** Adding a 9th `Category` enum value is structural change
  beyond breed authoring — onboarding template (`assets/onboarding/horse.md`),
  skill manifest filter, add-pet flow plumbing, species JSON
  (`assets/species/horse.json`) with horse breeds (USEF /
  AQHA / TB registries). v1's target users skew dog/cat/rabbit so
  v1 ships without it. v1.1 can land horses without schema change
  to existing categories.

### In-app notifications screen

- **Source:** Phase 6.6 scoping; Hub future-contents reservation.
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Medium.
- **Dependencies:** v1 reminders stack (Phase 4 — system notifications
  already fire via `flutter_local_notifications`); v1 Hub destination
  (Phase 6.6 — surface for the inbox to live under).
- **Notes:** v1 fires reminders + escalations as system notifications
  only; there is no in-app inbox / history view. v1.1 adds an
  inbox screen surfaced from Hub (mirrors Stitch's "Notifications"
  config; per the Hub-vs-tab decision in Phase 6.6, lives as a Hub
  sub-page rather than a top-level destination). Schema: read /
  unread state per delivered notification, payload archive (kind +
  fired-at + linked entry path), tap-to-deeplink to the relevant
  entry / reminder / digest. Surfaces Hub-icon badge count when
  unread > 0. Out of scope for v1 because system notifications
  cover the immediate-attention case and an inbox without real
  signal on which kinds users want to revisit risks shipping a
  half-used surface; v1.1 lands once we see actual notification
  taps + dismissal patterns.

### Hub future contents — Privacy & Data, Help / Support

- **Source:** Phase 6.6 scoping; Hub future-contents reservation.
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome); 59 follow-up
  (Phase 6.6 Hub v1 contents — Settings + Export + About).
- **Scope:** Small (per sub-page).
- **Dependencies:** v1 Hub destination (Phase 6.6).
- **Notes:** Phase 6.6 Hub v1 ships with Settings + Export + About.
  Reserved for v1.1 (additive sub-pages; no IA change): **Privacy &
  Data** (data deletion, export-all, encryption status — currently
  partial in Settings; v1.1 promotes to its own page) and **Help /
  Support** (FAQ, contact link, troubleshooting). In-app
  Notifications inbox tracked separately above. Phase 7 reserves Hub
  for Account / Subscription / Sync status alongside the paywall.
  v1.1 sub-pages don't require routing-level changes — they nest
  under Hub's existing route.

---

## v1.2 candidate

### Foundation: photo intelligence layer

- **Source:** Phase 6 Tier 3 expansion.
- **DECISIONS:** 40 (Phase 6 + Tier 3 deferral).
- **Scope:** Large (foundation for #6.0–#6.5 below).
- **Dependencies:** v1 photo storage (Phase 6 task 6.1); v1
  embedding stack (sqlite-vec already supports a second index).
- **Notes:** Photo embedding store (CLIP-style; second vector index
  alongside the existing text-embedding index — different signal,
  different index). On-device place/object detection (lightweight
  TF Lite model) tagging photos at save time with detected places
  ("park", "vet office", "kitchen") and objects ("ball", "leash",
  "treat"). Vision-cache layer means re-opening a saved photo
  doesn't re-vision it; cached extraction results live next to the
  photo binary. **On-device for privacy** — photo binaries don't
  leave the phone for tagging.

### Photo similarity search

- **Source:** PRODUCT.md "What's coming in v1.2" first item.
- **DECISIONS:** 40.
- **Scope:** Small (consumes the foundation).
- **Dependencies:** Photo intelligence layer (above).
- **Notes:** Tap any photo → "Find similar memories" → grid of
  photos across the pet's life that match by embedding distance.
  Ships early in v1.2 as the first user-visible proof the embedding
  store works.

### By-place / by-object organization

- **Source:** PRODUCT.md.
- **DECISIONS:** 40.
- **Scope:** Small.
- **Dependencies:** Photo intelligence layer (on-device tagging).
- **Notes:** "All photos at the park", "All photos with the green
  ball." Filter chips on the photo timeline; consumes the
  on-device tags.

### Cross-photo mood/posture trending

- **Source:** PRODUCT.md.
- **DECISIONS:** 40.
- **Scope:** Medium.
- **Dependencies:** Photo intelligence layer; v1's per-photo
  demeanor field (already exists in the slim 4-field set).
- **Notes:** A pet's demeanor across all saved photos surfaced as
  a chart on the SOUL profile next to v1's weight + symptom charts.
  "Loki has looked anxious in 3 of the last 5 photos." Aggregation
  is the new work; the per-photo demeanor field already ships.

### Cross-photo grounded observations

- **Source:** PRODUCT.md.
- **DECISIONS:** 40, 41 (affective observation gates).
- **Scope:** Medium.
- **Dependencies:** Photo intelligence layer; v1's affective
  observation surface.
- **Notes:** v1's affective layer grounds on text memories. v1.2
  grounds on photo memories too — "Loki looks more relaxed than at
  the beach last spring" cites a specific prior photo. Same gates
  (high confidence, frequency cap, Settings toggle), wider grounding
  source. **The most ambitious user-visible v1.2 feature.**

### Bare (non-grounded) affective observations

- **Source:** PRODUCT.md.
- **DECISIONS:** 41 (gate model).
- **Scope:** Small (gate-relax — the surface already exists).
- **Dependencies:** v1's grounded observation in production +
  consistently feeling earned (Settings disable rate <10% target).
- **Notes:** v1 only fires *grounded* observations. v1.2 — once
  the grounded version is proven solid in production — relaxes the
  gate to allow ungrounded observations on high-confidence photos.
  Still subject to frequency cap and Settings toggle. **Ships only
  if v1's grounded version has consistently felt earned;
  otherwise hold.**

### Photo albums

- **Source:** PRODUCT.md.
- **DECISIONS:** 40.
- **Scope:** Small.
- **Dependencies:** Photo intelligence layer (for auto-album
  detection); v1 photo timeline.
- **Notes:** Manual user-created albums + automatic albums by
  detected place/object. UI work; consumes existing tags. Interleaves
  anywhere in v1.2 sequencing after tags are live.

### Multi-photo chat upload

- **Source:** PRODUCT.md.
- **DECISIONS:** —.
- **Scope:** Small.
- **Dependencies:** v1 multimodal chat (Phase 6 task 6.9).
- **Notes:** v1 limits chat photo upload to one image per turn (API
  constraint by default — Anthropic supports multi-image but v1's
  vision quota model is per-image). v1.2 lifts to multi-photo turns
  where useful — a user describing a behavior pattern with multiple
  photos. Quota model needs a second look at the same time.

### Custom in-app camera UI

- **Source:** PRODUCT.md.
- **DECISIONS:** —.
- **Scope:** Small.
- **Dependencies:** v1 system camera handoff (Phase 6).
- **Notes:** v1 uses the system camera/gallery picker via
  `image_picker`. v1.2 ships an in-app camera optimized for pet
  photography (continuous shutter, instant-save shortcuts). Polish
  item; **only ships if v1 usage shows users hitting friction at
  the system camera handoff.**

### Online iNaturalist API fallback for freeform species

- **Source:** Phase 5.5 species-picker scoping.
- **DECISIONS:** 43, 44 (curated list path), 50 (Phase 5.5 wrap
  references the v1.2 fallback).
- **Scope:** Small.
- **Dependencies:** v1 freeform "Other" species path (Phase 5.5.6,
  shipped); network connectivity gating.
- **Notes:** v1's add-pet flow uses a hand-coded curated list of
  ~600+ species with iNat taxon IDs preserved per row. Users whose
  pet isn't in the curated list fall through to a freeform "Other"
  path that writes `species: <user-text>` and `inat_taxon_id: null`.
  v1.2 optionally enriches those freeform entries on first online
  connection — a single iNat API lookup fills in scientific name,
  taxonomy, taxon ID. **Opt-in** (the v1 freeform path is fully
  functional without it); offline-degrades to v1 behavior. **Ships
  only if v1 usage shows freeform-fallback usage rate above ~5%** —
  under that threshold the curated list is doing its job and the
  fallback enrichment isn't worth the public-API dependency.

### Tier 3 broader breed taxonomy

- **Source:** Phase 5.5 breed-structure lock.
- **DECISIONS:** 46.
- **Scope:** Large (broad authoring effort).
- **Dependencies:** v1 Tier 1 breed picker (shipped Phase 5.5).
- **Notes:** v1 ships Tier 1 (5 species: Dog, Cat, Rabbit, Guinea
  Pig, Chicken) with proper `breeds: [{name, alternatives[]}]`
  arrays. v1.2 expands the breed structure to additional species
  with bounded breed registries — goats (ADGA), horse breeds (if
  horse lands in v1.1 per #5 above), more bird breeds (heritage
  poultry registries). Authoring effort is the cost; UX is
  unchanged from Tier 1.

### Vitals tracker

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Medium.
- **Dependencies:** v1 SOUL.md frontmatter (`weight_kg` already
  ships); v1 trends repo (`lib/data/repos/trends_repo.dart` —
  weight history + symptom keyword counts already wired); v1
  trend chart primitives (`lib/app/widgets/charts/`).
- **Notes:** v1 captures weight as `type: weight` entries that the
  6.12 trends repo parses into a line chart. v1.2 expands to
  structured **vitals** beyond weight: heart rate, body condition
  score (1–9 scale, vet-shorthand), hydration, temperature,
  respiratory rate. Each lands as either a structured frontmatter
  field on a vet-visit entry OR as its own typed entry shape (TBD
  — depends on whether users measure vitals at home vs. only
  during vet visits). UI: per-pet HEALTH SUMMARY section (Phase
  6.6 already lays out the section) shows latest values + sparkline
  per measure. Trigger to revisit: real signal on which vitals
  users actually want structured tracking for vs. which stay as
  freeform body prose. Body-condition-scoring stays locked OUT
  per DECISIONS row 25's clinical-vision gate even in v1.2 —
  user-entered BCS is fine; AI-inferred BCS from photos is not.

### Symptom Tracker

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Medium / Large depending on structure depth.
- **Dependencies:** v1 trends repo symptom-frequency surface
  (FTS5 keyword counts in `TrendsRepo.symptomFrequencies`); v1
  red-flag screener; AI-tags v1.x (this entry; structured tag
  layer would feed the symptom tracker).
- **Notes:** v1 surfaces symptom frequency as five-keyword FTS5
  counts (Vomiting / Diarrhea / Lethargy / Scratching / Limping)
  on the SOUL profile chart. v1.2 expands to **structured symptom
  logging**: a chat-side or quick-capture-side flow where the
  user logs a symptom episode with severity + duration + body
  location + linked photo. Episodes accumulate into a
  per-symptom timeline shown on the HEALTH SUMMARY section.
  Trigger to revisit: usage signal showing which symptoms users
  log freeform repeatedly (the FTS5 count is a proxy — the right
  symptom set comes from real journal data). Structured symptom
  logs feed the weekly digest's "anomalies" surface and let the
  6.7 vision red-flag screener cross-reference structured history
  vs. extracted vision findings.

### Activity tracking

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Medium.
- **Dependencies:** v1 entry catalog (would add `type: activity`);
  v1 chat tool catalog (`write_wiki_entry` already accepts
  arbitrary type strings; adding the structured shape is the
  scope).
- **Notes:** v1 has no first-class concept of activity — walks /
  play / training sessions land as `type: behavior` entries with
  freeform prose. v1.2 adds structured `type: activity` with
  duration + activity-kind enum (walk / run / fetch / training /
  swim / play) + optional distance + optional location. UI: per-
  pet activity timeline + weekly minutes total + streak feedback
  (the engagement-loop angle, not gamification — the user sees
  patterns, not points). Trigger to revisit: real signal on
  whether activity tracking has standalone retention value or
  whether it's a feature subsumed by structured symptom + weight
  (i.e., the activity is implicit in the freeform story). Stays
  out of v1 because v1's lightweight chat-driven journal already
  captures activity as prose; promoting to structured shape needs
  evidence the structured layer adds value beyond what FTS5
  retrieval surfaces.

---

## v1.x (no specific window)

### Multi-provider LLM support (Gemini alongside Anthropic)

- **Source:** post-Phase-5.5 wrap-up, pre-Phase-6 kickoff.
- **DECISIONS:** 49.
- **Scope:** Large (~5–7 tasks).
- **Dependencies:** v1's `LlmTransport` abstraction (already in
  place); Phase 7 BYOK proxy work.
- **Notes:** Parallel Gemini transport implementation, tool-format
  conversion (Anthropic tool blocks ↔ Gemini function calls),
  vision adapter for Phase 6 photo-capture surfaces, provider
  selection UX in onboarding + Settings, voice calibration on
  Gemini (the §1–§6 voice register translates but needs validation
  per provider), quota logic for users with one or both keys
  configured, and proxy routing changes to support both providers'
  billing models. **Retention feature** (cost flexibility, quota
  independence), not an acquisition feature — post-launch timing
  aligns with when the user value compounds. v1 ships
  Anthropic-only via `LlmTransport`; the abstraction is the
  affordance, not a commitment that v1 ships multi-provider.
  **Why v1.x and not v1.1:** v1.1 is the first post-launch
  maintenance window — small fixes, real-user signal absorption.
  Multi-provider is bigger than that.

### Sub-classification-driven feature surface

- **Source:** Phase 5.5 sub-classification field locks.
- **DECISIONS:** 45 (three sub-classification fields), 47 (final
  value sets).
- **Scope:** Medium (six sub-features, each small individually).
- **Dependencies:** v1 SOUL frontmatter sub-classification fields
  (shipped: `working_role`, `rehab_context`, `care_context`).
- **Notes:** v1 captures the sub-classification fields as data
  ("v1.x discipline: capture the fields now, defer the features
  that *use* them"). v1.x revisit ships the feature surface that
  consumes the fields. Six concrete sub-features, each small:
    1. **Service-dog skill pack** — activates on `working_role: service`
       (public-access training notes, task-specific care, IRS
       documentation reminders for service-animal owners).
    2. **Foster-onboarding skill pack** — activates on
       `rehab_context: foster` (intake protocol, foster-coordinator
       contact pattern, kitten/puppy weight-gain trajectories).
    3. **Retirement-planning flow** — activates on
       `rehab_context: palliative` (quality-of-life check-ins,
       end-of-life decision support, vet-conversation prompts).
    4. **Foster-handoff export** — fires when `rehab_context`
       transitions out (foster → adopted / released). One-shot PDF
       summary the foster sends with the animal.
    5. **Breeding-cycle reminder presets** — `working_role: breeding`
       triggers heat-cycle / ovulation / whelping schedule presets
       in the reminders surface.
    6. **Neonatal-feeding interval templates** — `rehab_context:
       neonatal` triggers feeding-interval presets (every 2–4 hours,
       elimination stimulation reminders, weight-monitoring
       cadence).
  Triggers in v1.x once real usage shows which sub-classifications
  see meaningful adoption. If `working_role: service` is rare in
  the user base, that pack stays unbuilt; if `rehab_context:
  foster` is common (rehab/rescue user persona is real), foster
  features ship first.

### AI-created tags within fixed primary categories

- **Source:** post-Phase-5.6 v1.x backlog scoping; surfaced
  pre-Phase-6.
- **DECISIONS:** 53.
- **Scope:** Medium.
- **Dependencies:** v1 journal category enum (locked, fixed); v1
  chat tool catalog (`write_wiki_entry` accepts a primary
  `type:`); v1 FTS5 index (extending it to tag arrays is part of
  the v1.x scope).
- **Notes:** v1 ships with **fixed primary journal categories**
  only — the entry's `type:` field is a closed enum (`vet`,
  `food`, `weight`, `behavior`, `photos`, `digest`, …). AI-created
  tags are a **secondary axis nested under the fixed primary**
  — for a `type: vet` entry the agent could attach free-form tags
  like `rabies`, `annual-checkup`, `follow-up-needed`,
  `prescription-active` that capture finer-grained signal without
  expanding the closed-enum primary. **Why fixed primary in v1.**
  Fixed-enum primaries make the v1 surface predictable: the
  journal browser groups by a known list, the FTS5 index has a
  small set of group keys, the tool dispatcher's
  `write_wiki_entry` has a closed argument shape, and the agent
  doesn't drift into cluttered taxonomy on day one. **What v1.x
  adds.** (a) Schema: per-entry `tags: [string]` frontmatter
  field; FTS5 indexes the tags inline with title + body; tags
  participate in retrieval ranking. (b) Tool: `write_wiki_entry`
  gains an optional `tags: List<String>` arg; the agent generates
  tags when entry content warrants it, suppresses tags when the
  entry is too thin to tag meaningfully. (c) UI: tag chips on
  entry tiles in the journal browser; tap a chip to filter the
  view to entries sharing the tag. Tag editor in the entry detail
  screen for user-level corrections / additions / removals. (d)
  Normalization: lowercase + hyphen-snake by default; near-dup
  collapse (`rabies-vaccine` near `rabies` near `Rabies`); the
  agent's prompt includes the pet's existing tag set so it
  prefers reusing established tags over inventing variants. (e)
  Pruning: when the last entry carrying a tag is deleted, the
  tag retires from the global tag set; the user-visible tag list
  shrinks naturally rather than accumulating dead labels. (f)
  Cap: ≤5 tags per entry to keep the chip row legible. **Why
  v1.x and not v1.1 / v1.2.** This is a "behaviour-tunes-on-real-
  usage" feature, not a cost-controlled v1.2-photo-intelligence
  candidate or a v1.1-clear-scope cut. Trigger to revisit: ~3–6
  months of real journal entries showing patterns that the fixed
  primaries don't surface cleanly. If users naturally taxonomize
  entries inside the body prose ("scratching since Tuesday",
  "still on prednisone") and the existing FTS5 search finds
  them, tags add ceremony without value; if users want to
  *filter* by recurring concepts, tags pull their weight.

### Medical as top-level destination

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Medium.
- **Dependencies:** v1 vet-visit structured entry (Phase 6.10);
  v1 auto-follow-up reminders (Phase 6.11); v1.2 vitals tracker
  (this backlog) — would feed naturally into a Medical surface.
- **Notes:** v1 surfaces vet visits as a `type: vet` filter inside
  the journal browser; medical content lives mixed with all other
  entries and is reachable only through the journal IA. v1.x
  considers promoting Medical to its own top-level destination
  (sibling to Journal, Profile, Hub) consolidating vet visits +
  prescriptions + vitals + medical-flagged photos into one IA
  surface. Holds Phase 6.6's "memory is the moat — medical lives
  inside the journal, not the other way around" anti-pattern
  hard until real signal warrants the IA promotion. Trigger:
  usage data showing users reach for medical content frequently
  enough that mixing it with Journal entries causes friction (e.g.
  vet-visit retrieval rate >> behavioral-entry retrieval rate),
  AND that the v1.2 vitals tracker accumulates enough structured
  data to fill a dedicated surface. If trigger fires, the
  bottom-nav swap is small (replace Hub or split Journal — TBD by
  Phase 6.6's settled IA); the content move is bigger (the
  Medical destination's empty state + day-one population pattern
  needs to land cleanly so a new user without medical history
  doesn't see a barren tab).

### Multi-user "Pet Family" / family-sharing

- **Source:** Phase 6.6 scoping (cofounder review). Extends the
  v1.1 "Caregiver / family sharing preview" entry above with a
  multi-edit framing.
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Large.
- **Dependencies:** Phase 7 cloud sync backend (DECISIONS row 36);
  per-pet identity model (currently single-device, single-user);
  invite + auth flow.
- **Notes:** The v1.1 "Caregiver / family sharing preview" entry
  scopes **read-only** sharing — PDF export, vet-facing summary,
  invite a sitter / vet to view. This entry scopes the broader
  **multi-user "Pet Family"** model: multiple humans (partners,
  caregivers, family members) with edit access to the same pet's
  journal. Schema: per-pet `members: [{user_id, role}]` where role
  ∈ {owner, caregiver, viewer}; entry attribution
  (`authored_by: user_id`) so the journal preserves who wrote
  what; conflict resolution at sync layer. Phase 7 sync is the
  load-bearing dependency. Out of v1 scope because single-device
  single-user is the simplest correct shape for the compounding-
  memory thesis; multi-user adds permission semantics + sync
  conflict resolution that v1 doesn't need. Trigger: real signal
  from v1 / v1.1 users that a partner / caregiver wants
  write-access (vs. just read). Coordinated with the v1.1
  read-only sharing preview; doesn't supersede it.

### Bottom nav variant configurations Stitch surfaced

- **Source:** Phase 6.5 Stage 2 curation (Stitch sessions).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome); Phase 6.6
  rows that lock the chosen 4-tab Home / Journal / Profile / Hub
  shape.
- **Scope:** Reference only — no scope.
- **Dependencies:** Real-usage signal post-launch.
- **Notes:** Stitch surfaced 6 different bottom-nav configurations
  across 13 mockup screens (varying tab counts 3–5, varying
  destinations including Care, Health, Add, Photos, Stories).
  Phase 6.6 designed from PetPal's actual IA rather than
  reconciling Stitch's varied configs (DECISIONS row 58). This
  entry preserves the Stitch alternates as design exploration
  artifacts: if post-launch usage signal shows the chosen 4-tab
  shape isn't serving users, the Stitch alternates are the
  starting point for revisiting (rather than re-running Stitch).
  No implementation scope here — this is an archival / reference
  entry. The captured alternates: 3-tab Home/Journal/More;
  4-tab with Photos as separate tab; 4-tab with Health as
  separate tab; 5-tab adding Care guides + Photos; FAB-centered
  4-tab; bottom-sheet drawer instead of nav.

### Center Capture FAB in bottom nav

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome); Phase 6.6
  follow-up rows.
- **Scope:** Small (~3–4 tasks).
- **Dependencies:** v1 bottom nav (Phase 6.6); usage signal.
- **Notes:** Considered for Phase 6.6 and rejected for v1.
  Reasoning: capture is multi-modal (Photo / Note / Medical) and a
  single FAB requires either an extra-tap action sheet (worse than
  Stitch's inline Home Quick Capture tiles which are zero-extra-
  tap) or arbitrary mode-pick. Visual weight of a center-mounted
  FAB conflicts with the warm-journal thesis — pulls toward
  social-app-action register (Instagram, Facebook). PetPal's
  primary loop is chat-driven, not capture-driven. Quick Capture
  tiles on Home + photo button in chat composer + camera entry
  point cover the use cases. Trigger to revisit: post-launch
  usage signal showing frequent capture intent from non-Home tabs
  (especially Journal browser → "I want to add a memory while
  browsing"). Scope if revisited: small — a single-action FAB
  opening camera-as-memory directly (the primary capture mode),
  not a multi-action sheet (the multi-action design is what
  failed the v1 evaluation). Photo mode only because a FAB needs
  one obvious action; if Note + Medical also need fast access,
  they stay on Home Quick Capture or chat composer.

### Engagement metrics

- **Source:** Phase 6.6 scoping (cofounder review).
- **DECISIONS:** 58 (Phase 6.5 Stage 2 curation outcome).
- **Scope:** Small.
- **Dependencies:** Phase 7 backend service (DECISIONS row 36 — the
  PetPal-hosted LLM proxy is the natural place to also collect
  opt-in engagement signal); user opt-in surface (Settings —
  privacy lock).
- **Notes:** v1 ships zero engagement instrumentation — no DAU,
  no retention metrics, no feature-usage telemetry. This is
  intentional for the privacy positioning ("memory is private by
  default" — PRODUCT.md "Not a social network"). v1.x adds
  **opt-in** engagement metrics for product decisions: which
  features users reach for, where they drop off in onboarding,
  which entry types accumulate vs. stay near-zero. Schema:
  privacy-preserving event log (no entry content, no chat content,
  no pet-identifying data) — only feature-tap counts + screen-
  visit counts + session duration buckets. Default OFF; opt-in via
  Settings → Privacy & Data with plain-language explanation of
  what's collected and what isn't. Routes through the Phase 7
  backend (extending the LLM proxy is cheaper than a separate
  analytics surface). Trigger to revisit: post-launch product
  decisions need data we don't have (e.g., "is the photo timeline
  used? do users actually open weekly summaries? does the
  affective observation card get tapped or dismissed?").

---

## Items considered but not landed in this backlog

These came up in the audit / session memory but lack a committed
deferral decision in the codebase docs. If they should land in
v1.x, they need a DECISIONS row + the deferral context first.

- **Photo-driven palette extensions beyond Phase 6 scope.** No
  source decision in PRODUCT.md / DECISIONS.md / ROADMAP. Surfaced
  conversationally; no row to reference. If pursued, needs a
  DECISIONS row capturing what specifically is being deferred
  (per-pet UI accent from dominant photo color? per-photo album
  cover tinting? something else?) and the v1-scope reasoning.

---

## Process — adding a new entry

1. When deferring something from a v1 phase, decide which tier
   (v1.1 / v1.2 / v1.x) it lives in.
2. Add the entry to this file in the **same commit** as the
   deferral decision (CLAUDE.md §14 working protocol). Don't ship
   the deferral with only a DECISIONS row + conversation context.
3. Cross-reference: the DECISIONS row text mentions "see V1X_BACKLOG.md
   for the v1.x feature shape"; the backlog entry's `DECISIONS:`
   line points back at the row.
4. PRODUCT.md keeps a one-line summary pointer to this file —
   don't duplicate prose between the two.
