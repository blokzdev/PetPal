# PetPal — product vision

## What it is

PetPal is a memory-first companion for pet owners. The user chats; PetPal
quietly accumulates everything they say into a per-pet journal — vet visits,
weight, food trials, behavior notes, photos — in plain markdown the user
owns and can export. Over months and years the journal becomes a single
source of truth for that pet's life, and PetPal answers questions grounded
in it. The chat is the interface. The journal is the product.

## The bet

Foundation models are commoditizing. Frontier models alone don't
differentiate; what does is the harness around them — memory, skills,
protocols, persistent state. Pet ownership is a near-perfect fit for that
thesis: every dimension of the harness has a clean pet analog (per-pet
profile, longitudinal journal, species-specific care knowledge, exact-time
reminders for meds and vaccines, multimodal photo input), and the lock-in
is emotional as well as functional. Owners will tolerate friction and pay
subscriptions for an app that *knows* their pet, because that knowledge is
irreplaceable and accumulates over years.

## Target users (priority order)

1. **The compounding-memory user.** Multi-year owner who wants a single
   source of truth across vets, sitters, and family. Highest LTV — pays
   for sync across devices and unlimited pets.
2. **The new-pet anxious owner.** First puppy, kitten, or exotic;
   overwhelmed by what to track and when. Highest conversion — guided
   onboarding and species-specific care guides do most of the work.
3. **The senior-pet caregiver.** Managing multiple meds, multiple vets,
   declining health. Most emotionally bonded segment; pays for reminders
   and a medical timeline they can hand to a new vet.
4. **The exotic / under-served owner.** Reptile, bird, rabbit, fish.
   Ignored by every dog-first pet app. Smaller market, near-zero
   competition, defensible niche.
5. **The wildlife rehabilitator.** Licensed rehabbers and committed
   amateurs caring for rescue/rehab/release animals (raptors, songbirds,
   opossums, fawns, native rabbits) or permanent non-releasable wildlife.
   PetPal treats wildlife rehab as a peer use case alongside pet
   ownership: the add-pet flow asks every user about their relationship
   to the animal — pet, rescue/rehab, permanent care, observation — so
   a rehabber's setup is first-class, not a hidden mode. Dedicated
   intake/release tracking and species coverage that goes beyond what
   any companion-pet app supports.

## The core problem

Pet ownership is years of small observations — a new tic, a food that
caused a flare-up, a vet's offhand comment three visits ago. None of it
lives anywhere durable. Owners hold it in their heads, in scattered notes
apps, in screenshots they can't search. When it matters — a 2 a.m.
emergency, a new sitter, a behaviorist asking "when did this start?" —
the answer is gone. PetPal solves the storage and recall problem, and
because the recall is grounded in the user's own notes, the answers are
specific instead of generic.

## What PetPal is NOT

- **Not a vet.** PetPal never diagnoses. Red-flag symptoms (lethargy +
  anorexia, blood in stool, suspected toxin ingestion, seizure, labored
  breathing) trigger an unmistakable "call your vet now" UI before any
  other content. The escalation runs as deterministic code, not as a
  prompt instruction.
- **Not a social network.** No feeds, no follows, no public profiles.
  Memory is private by default.
- **Not an AI companion.** PetPal is a knowledgeable assistant. No
  anthropomorphizing, no roleplay, no "I" with a personality.
- **Not an open marketplace at v1.** First-party care packs ship at
  launch; third-party-authored expert knowledge packs (the Year 2
  layer) come once we have real users and real signal.
- **Not cloud-first.** Local-first, user-owned markdown. Optional
  encrypted sync is a Pro feature, not a default.
- **Not a meter on every interaction.** Quotas exist to bound our AI
  costs, not to ration access to your pet's memory. Chat is unmetered
  for Pro subscribers and on BYOK. The free monthly chat allowance is
  generous and lives in Settings, not in the chat surface itself.

## Two-year vision

Year 1: ship the compounding-memory loop and prove retention. The free
tier is unlimited locally — one pet, unlimited journal, 200 chat
messages per month (safety/red-flag escalations never count toward the
allowance), 5 reminders, manual browsing, export anytime. Pro
($7.99/mo or $59/yr) adds end-to-end encrypted cross-device sync,
unlimited pets, unlimited text chat, 30 photo-vision analyses per
month, AI weekly summary plus monthly health report, and unlimited
reminders. BYOK (a free-tier modifier, not a paid tier) lets users
supply their own Anthropic API key to lift every cost-driven cap —
calls route direct to Anthropic without crossing PetPal's backend, and
the monthly limits don't apply. Photo credit packs ($2.99 = 50
analyses, roll over indefinitely) cover Pro users who exceed the
monthly vision cap. By month 12, ten species supported, three
first-party care packs (Puppy, Senior, Reactive Dog), 1,000 paying
Pro subscribers.

Year 2: open the marketplace. Credentialed vets and behaviorists author
expert knowledge packs ($14.99–$39.99 one-time); a vet-supply affiliate
layer covers reorders. The defensibility shifts from feature parity
("we have chat too") to corpus depth ("PetPal knows three years of my
animal's life and which behaviorist I trust").

The moat compounds with use. Every entry the user writes makes the next
answer better, and makes leaving more painful — that's the business.

## What's coming after v1

The post-v1 roadmap (v1.1 / v1.2 candidate / v1.x) lives in
**[V1X_BACKLOG.md](./V1X_BACKLOG.md)** as the single source of
truth. Each entry there carries its source phase / decision,
DECISIONS-row reference, scope estimate, dependencies, and
the specifics worth preserving for future-us. PRODUCT.md keeps
the v1 thesis; V1X_BACKLOG.md keeps what comes next.

**Tier headlines** (full entries in V1X_BACKLOG.md):

- **v1.1** — first post-launch maintenance window. Onboarding
  intelligence (auto-populate from photos / voice; vision-based
  species/breed inference stays locked OUT per DECISIONS row 25),
  medication tracking, caregiver / family sharing preview,
  improved chat (reactions / edit-delete / threading / search;
  edit-delete contradicts "memory persists" so revisit shape),
  horse as 9th category.
- **v1.2 candidate** — locks once ~6 months of real v1 usage data
  lands. The photo-as-memory loop deepens into cross-photo
  intelligence: photo embedding store as foundation; photo
  similarity search; by-place / by-object organization; cross-photo
  mood/posture trending; cross-photo grounded observations; bare
  (non-grounded) affective observations; photo albums; multi-photo
  chat upload; custom in-app camera UI; online iNaturalist API
  fallback for freeform species; Tier 3 broader breed taxonomy.
- **v1.x** (no specific window) — multi-provider LLM support
  (Gemini alongside Anthropic; DECISIONS row 49); the
  sub-classification-driven feature surface (service-dog skill
  pack, foster-onboarding skill pack, retirement-planning flow,
  foster-handoff export, breeding-cycle reminder presets,
  neonatal-feeding interval templates; DECISIONS rows 45 + 47);
  AI-created tags within fixed primary categories.

**Stays locked OUT — even in v1.2.** DECISIONS row 25 holds: body
condition scoring, wound detection / injury photo interpretation,
breed / species inference, and any other diagnostic-adjacent
vision stay out of bounds. The behavioral / observational vision
surface deepens; the medical-vision surface does not. Owners with
clinical concerns get the red-flag screener output → "call your
vet" copy, not a model attempting clinical interpretation.

**What v1 usage data should tell us before locking v1.2.**
- *Save rate.* Are users saving photos as memories, or just
  chatting with photos? Low save rate → v1.2 focuses on lowering
  save friction, not deepening intelligence.
- *Affective observation reception.* Does v1's grounded observation
  feel warm or scripted? Settings-toggle disable rate is the
  leading indicator. >10% of users-who-saw-an-observation disabling
  → v1.2 affective expansion gets the brakes pumped.
- *Search vs. browse.* Do users find old photos by scrolling the
  timeline or by recalling a query? If search/recall is rare,
  photo similarity + place organization are over-engineering and
  v1.2 prioritizes album curation instead.
- *Vision quota burn.* Does the median Pro user burn the 30/mo cap?
  Yes → photo credit pack revenue is real and v1.2 can afford
  richer vision usage. No → every additional vision call needs
  cost justification.
- *Red-flag false-positive rate.* Phase 6 ships vision-screener
  integration with the false-positive-tolerant tradeoff. v1.2
  re-tunes thresholds based on real-world fire rate.
- *Freeform-fallback usage rate.* Above ~5% → online iNat fallback
  is worth the public-API dependency. Below → curated list is
  doing its job; iNat fallback stays in the backlog.
