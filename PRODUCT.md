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

## What's coming in v1.2

v1 (Phase 8 launch) ships the photo-as-memory loop: capture → vision-extract
→ user-confirmed structured save → red-flag-screened → optionally one
memory-grounded observation. v1.2 deepens that loop into cross-photo
intelligence. The list below is **candidate scope** — committed future
direction, not committed feature parity. Final v1.2 plan locks once we have
~6 months of real v1 usage data telling us which photo behaviors actually
compound.

**Foundation: photo intelligence layer.** A photo embedding store (a second
vector index alongside the existing text-embedding store; sqlite-vec already
supports it) gives every saved photo a CLIP-style embedding for similarity
queries, place clustering, and mood trending. Text embeddings stay separate
— different signal, different index. On-device place/object detection (a
lightweight TF Lite-tier model) tags photos at save time with detected
places ("park", "vet office", "kitchen") and objects ("ball", "leash",
"treat"). On-device for privacy: photo binaries don't leave the phone for
tagging. A vision-cache layer means re-opening a saved photo doesn't
re-vision it — cached extraction results live next to the photo binary.

**User-visible features (consume the foundation).**
- *Photo similarity search.* Tap any photo → "Find similar memories" → grid
  of photos across the pet's life that match by embedding distance. Ships
  early in v1.2 as the first user-visible proof the embedding store works.
- *By-place / by-object organization.* "All photos at the park", "All photos
  with the green ball." Filter chips on the photo timeline; consumes the
  on-device tags.
- *Cross-photo mood/posture trending.* A pet's demeanor across all saved
  photos surfaced as a chart on the SOUL profile next to v1's weight +
  symptom charts. "Loki has looked anxious in 3 of the last 5 photos."
  Aggregation is the new work; the per-photo demeanor field already exists
  from v1's slim 4-field set.
- *Cross-photo grounded observations.* v1's affective layer grounds on text
  memories. v1.2 grounds on photo memories too — "Loki looks more relaxed
  than at the beach last spring" cites a specific prior photo. Same gates
  (high confidence, frequency cap), wider grounding source. The most
  ambitious user-visible v1.2 feature.
- *Bare (non-grounded) affective observations.* v1 only fires grounded
  observations. v1.2 — once the grounded version is proven solid in
  production — relaxes the gate to allow ungrounded observations on
  high-confidence photos. Still subject to the frequency cap and Settings
  toggle. Ships only if v1's grounded version has consistently felt earned;
  otherwise hold.
- *Photo albums.* Manual user-created albums + automatic albums by detected
  place/object. UI work; consumes existing tags.
- *Multi-photo chat upload.* v1 limits chat photo upload to one image per
  turn (API constraint by default). v1.2 lifts to multi-photo turns where
  useful — a user describing a behavior pattern with multiple photos.
- *Custom in-app camera UI.* v1 uses the system camera/gallery picker via
  `image_picker`. v1.2 ships an in-app camera optimized for pet photography
  (continuous shutter, instant-save shortcuts). Polish item; only ships if
  v1 usage shows users hitting friction at the system camera handoff.

**Stays locked OUT in v1.2.** DECISIONS row 25 (medical/clinical vision
gate) holds. v1.2 does **not** relax it: body condition scoring, wound
detection / injury photo interpretation, breed / species inference, and any
other diagnostic-adjacent vision stay out of bounds. The behavioral /
observational vision surface deepens; the medical-vision surface does not.
Same reasoning as v1: liability, accuracy ceiling on visual diagnosis,
"track + know when to call the vet" positioning. Owners with clinical
concerns get the existing red-flag screener output → "call your vet" copy,
not a model attempting to interpret the image clinically.

**Sequencing (rough).** Photo embedding store + vision-cache layer first
(foundation, nothing user-visible yet). Photo similarity search ships next
to validate the embedding index. On-device place/object detection lands in
parallel once embeddings are live. By-place / by-object organization
consumes the tags. Cross-photo mood/posture trending consumes the
embeddings + the per-photo demeanor field from v1. Cross-photo grounded
observations consume retrieval + trending. Bare affective observations only
ship if the v1 grounded version has been measurably warm-natural in
production. Photo albums interleave anywhere after the tags are live.
Multi-photo chat upload + custom camera UI are polish that ships if v1
usage data warrants.

**What v1 usage data should tell us before locking v1.2.**
- *Save rate.* Are users saving photos as memories, or just chatting with
  photos? If save rate is low, v1.2 should focus on lowering save friction,
  not deepening intelligence.
- *Affective observation reception.* Does v1's grounded observation feel
  warm or scripted to real users? Settings-toggle disable rate is the
  leading indicator. If disable rate is >10% of users-who-saw-an-observation,
  the v1.2 affective expansion needs the brakes pumped.
- *Search vs. browse.* Do users find old photos by scrolling the timeline
  or by recalling a query? If search/recall is rare, photo similarity +
  place organization are over-engineering and v1.2 prioritizes album
  curation instead.
- *Vision quota burn.* Does the median Pro user burn the 30/mo cap? If yes,
  photo credit pack revenue is real and v1.2 can afford richer vision
  usage. If no, every additional vision call (cross-photo grounding, mood
  trending) needs cost justification.
- *Red-flag false-positive rate.* Phase 6 ships vision-screener integration
  with the existing false-positive-tolerant tradeoff. v1.2 should re-tune
  thresholds based on real-world fire rate.
