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
   for unlimited memory and sync.
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
- **Not a marketplace at v1.** Care packs and expert knowledge are
  monetization layers that come once we have real users and real signal.
- **Not cloud-first.** Local-first, user-owned markdown. Optional
  encrypted sync is a Pro feature, not a default.

## Two-year vision

Year 1: ship the compounding-memory loop and prove retention. The free
tier is functional but visibly limited (one pet, 30-day rolling memory,
3 reminders); Pro unlocks unlimited memory, unlimited pets, weekly
summary synthesis, and optional encrypted sync. By month 12, ten
species supported, three first-party care packs (Puppy, Senior, Reactive
Dog), 1,000 paying Pro subscribers.

Year 2: open the marketplace. Credentialed vets and behaviorists author
expert knowledge packs ($14.99–$39.99 one-time); a vet-supply affiliate
layer covers reorders. The defensibility shifts from feature parity
("we have chat too") to corpus depth ("PetPal knows three years of my
animal's life and which behaviorist I trust"). Lifetime tier ($99–$129,
local-only, no sync) for the privacy-first segment.

The moat compounds with use. Every entry the user writes makes the next
answer better, and makes leaving more painful — that's the business.
