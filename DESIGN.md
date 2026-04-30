# DESIGN.md — PetPal design system

This document is the input to Stitch (stitch.withgoogle.com) for
generative UI concept exploration. It captures intent, not
implementation. Stitch outputs are curated, not implemented wholesale;
see Phase 6.5 in `ROADMAP.md` for the three-stage workflow.

---

## 1. Brand Thesis

PetPal is a warm, journal-aesthetic pet care companion. The product
thesis is that **the memory is the moat** — every conversation, vet
visit, behavior note, and photo accumulates into a per-pet wiki that
the AI builds over months and years. The visual language exists in
service of this thesis: it should feel like a journal a person would
actually want to write in, not a utility app for tracking pet
logistics.

The intended emotional register is **warm without being saccharine,
intentional without being clinical, journal-aesthetic without being
precious**. PetPal is for the user who treats their pet's life as
something worth chronicling — pet owners who feel a real bond, rescue
volunteers caring for foster animals, wildlife rehabbers documenting
orphaned creatures through release. The visual language should
communicate "this is a record worth keeping" across all four user
relationships (Pet / Rescue or rehab / Permanent wildlife / Wildlife
observation).

Specific choices serve this thesis: the sage palette is calming and
natural, suggesting growth and patience rather than urgency; Source
Serif 4 in display contexts (greetings, journal entries, weekly
summaries) carries the literary weight of a written record; the home
greeting is composed as an arrival (cinematic gradient + pet name
held in display type) rather than a header; hero moments like the
memory-saved bloom make the act of capturing a moment feel like a
small ceremony.

PetPal is **not a chatbot interface** (the AI stays in service, not
in personality). It is **not a medical tracker** (clinical accuracy
matters, but PetPal is a journal that includes medical context, not
a vet portal). It is **not a photo-sharing app** (photos are
memories, not posts). It is **not a productivity tool** (entries
compound; they don't get checked off).

---

## 2. Anti-Patterns

PetPal is explicitly NOT:

- **Material 3 default aesthetic.** The sage palette, custom motion
  curves, Phosphor icons, and Source Serif 4 are deliberate
  departures from Material's defaults. Stitch outputs that look like
  generic Google apps should be treated as failures.
- **Minimal-utility / SaaS aesthetic** (shadcn, Linear, Notion).
  Clinical neutrality conflicts with the warm-journal thesis. Pure
  grayscale with strong typography hierarchy is wrong for this
  product, even though it's currently fashionable.
- **Playful pet-app aesthetic** (Rover, Petco, Chewy). Cartoon
  illustrations, bright primary colors, paw-print patterns
  everywhere, exclamation marks, and "fur baby" voice are wrong.
  PetPal treats users as adults whose relationship with their animal
  is dignified and complete.
- **Clinical / medical aesthetic** (vet portals, pet health
  trackers). White-coat sterility, dense data dashboards, and
  chart-first hierarchies miss the point — medical context lives
  within a journal, not the other way around.
- **Chatbot-companion aesthetic** (Replika, Pi, Character.AI).
  PetPal's AI does not have a personality that introduces itself. It
  does not greet the user. It does not narrate. The AI surfaces in
  tool pills and synthesis cards, never as an avatar or character.
- **Social / sharing aesthetic.** No likes, no follower counts, no
  public profiles. Photos are memories, not posts. Weekly summaries
  are personal synthesis, not feed content.
- **Productivity / task aesthetic.** Entries are not tasks.
  Reminders are utility but they don't define the product. There are
  no completion percentages, no streak counters, no gamification.
- **Loud or aggressive contrast.** Coral is reserved for
  medical-warning escalation (the red-flag screener); it does not
  appear as a primary action color. Dark mode is sage-tinted dark,
  not pure black.
- **Decorative whitespace as polish.** PetPal's polish comes from
  typography rhythm, motion calibration, and intentional component
  composition — not from huge blank canvases that signal "luxury app."

---

## 3. Color Tokens with Intent

The locked palette is "soft modern" (DECISIONS row 35). FlexColorScheme
generates the M3 tonal derivatives from a sage-primary + coral-tertiary
seed (DECISIONS row 50); manual surface overrides land last to pin the
exact hex values and neutralise M3-default lavender drift on a sage
seed (DECISIONS rows 35, 38). The intent annotations below describe
how each token participates in the warm-journal register, not just
where it lives in the scheme.

### Anchor colors

- **Sage `#5C8A7A` (`PetPalColors.sage` → `scheme.primary`).** Muted,
  vegetal, slightly cool-warm. Communicates calm, growth, patience.
  This is PetPal's identity color — used for the hero gradient sweep
  in the home greeting, the journal-bloom icon when a memory saves,
  the focused-input border, the FilledButton fill, the weight-chart
  line + symptom-bars, the "pawPrint" empty-state icons. **Never used
  as a warning color.** Where M3 defaults would tint surfaces with
  the seed (the lavender drift), the manual surface overrides
  neutralise that pull-through so the sage stays an accent, not a
  wash. `scheme.surfaceTint` is set to sage so M3-aware widgets that
  scrolled-under-tint inherit the brand color subtly without
  flooding.

- **Coral `#E89B7A` (`PetPalColors.coral` → `scheme.tertiary`).** Warm
  peach-coral. The brand thesis reserves it for medical-warning
  escalation, where its warmer-than-sage temperature reads as "draw
  attention, but with care." [INTENT-INFERRED — see "Implementation
  drift" below; coral is wired into the scheme as `tertiary` but no
  widget currently reads it. The red-flag escalation badge today
  uses `scheme.onSurfaceVariant` (muted gray) and the chat error
  banner uses `scheme.error` (M3-default red), so coral's medical-
  warning role is currently aspirational. This is one of the
  documented thesis-vs-implementation conflicts the commit message
  flags.]

- **Warm off-white `#F7F5F2` (`PetPalColors.warmOffWhite` →
  `scheme.surface` in light mode).** The single most visible token.
  Distinct from `#FFFFFF` — the slight warmth carries through every
  light surface. Evokes paper or journal page, not screen pixels.
  Stitch should treat any concept that lands light surfaces on pure
  white as drifting from the brand.

- **Graphite `#2D3436` (`PetPalColors.graphite` → `scheme.onSurface`
  in light mode + the foreground tone of the journal-+-paw adaptive
  launcher icon).** The ink color. Nearly black but with a faint
  green-blue cast that pairs with sage rather than fighting it.

### Light-mode warm surface scale

A six-step warm-cream scale, hand-tuned to step up from `warmOffWhite`
without M3-default lavender drift on a sage seed:

- `lightSurfaceLowest` `#FFFFFF` — pure white, used only when
  containers need to recede from the warm-off-white background
  (input field fill, the chat thread's inset surface).
- `lightSurfaceLow` `#FBFAF7` — one notch warmer than white; barely-
  visible lift.
- `lightSurface` `#F7F5F2` — the canonical scaffold background
  (`warmOffWhite`).
- `lightSurfaceContainer` `#F2EFE9` — default Card / PetCard fill.
  This is where journal entries and form sections sit.
- `lightSurfaceContainerHigh` `#EDE9E1` — raised cards, dialogs,
  chat composer slab.
- `lightSurfaceContainerHighest` `#E7E2D7` — empty-state badge
  circles, skeleton-loading high-contrast bars.

The scale is monotonic in warmth (R/G channels rise as the band
raises), giving "lifted" surfaces a slightly creamier feel rather
than the M3-default cooler gray.

### Dark-mode warm-graphite scale

DECISIONS row 38 locked the dark mode as **honest warm graphite**, not
sage-tinted dark and not pure black:

- `darkSurfaceLowest` `#161512` — deepest band; chat thread
  background.
- `darkSurfaceLow` `#1F1E1C` — Cards behind cards.
- `darkSurface` `#23211E` — scaffold background.
- `darkSurfaceContainer` `#28261F` — default card fill.
- `darkSurfaceContainerHigh` `#2D2B22` — raised cards.
- `darkSurfaceContainerHighest` `#33302C` — high-contrast chrome
  (empty-state badge circles, dialogs).
- `darkOnSurface` `#EEE9E0` — text-on-dark; warm off-white,
  mirroring the warmth of the light theme's text-on-surface
  relationship.

Sage and coral remain accent colors in dark mode; the surface bands
stay neutral-warm-graphite so journal/chat content reads cleanly. **Do
not propose dark concepts that wash sage through the surface bands** —
that's the rejected "sage-tinted dark" direction from row 38.

### M3-derived semantic tokens

Where the brand explicitly diverges from M3 defaults (sage primary,
warm-cream surfaces, coral tertiary), the scheme is hand-set. Where
the brand has no opinion (error, scrim, outline, on-tone derivatives),
FlexColorScheme's tonal harmony output is used as-is:

- **`scheme.error`** — M3-default red. Used by save-error text in
  forms, the chat error banner background. **Not** repurposed as a
  brand color; PetPal's "warning" semantics live on coral
  (aspirationally) or on the subdued `onSurfaceVariant` warning-
  octagon (currently). Stitch should treat error-red as
  failure-only, never as a CTA or accent.
- **`scheme.outline` / `scheme.outlineVariant`** — derived; used for
  hairline dividers (the chat composer top-edge divider, list-item
  separators, chart grid lines).
- **On-tones** (`onPrimary`, `onSurface`, etc.) — `onPrimary` is
  manually pinned to `warmOffWhite` in light mode so FilledButton
  labels read warm-cream against sage, not stark white. In dark
  mode, `onPrimary` is `graphite` so a sage button on a dark surface
  retains a legible dark label.

### Color usage doctrine

- **Sage carries the brand.** It's the only color that recurs across
  hero moments, primary actions, focus states, and chart accents.
- **Surfaces carry the warmth.** The scale is the dominant visual
  signal; sage is sparing.
- **Coral is reserved.** Even in light mode, coral never renders
  large; the brand thesis treats it as warning-temperature attention.
- **Error red is M3-default.** Failures are failures; PetPal does
  not invent a brand-flavored error color.
- **Outline tones are atmospheric.** Hairline dividers at low alpha;
  never used as borders that draw the eye.
