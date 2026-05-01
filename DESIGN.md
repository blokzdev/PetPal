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
  peach-coral. Reserved for medical-warning escalation, where its
  warmer-than-sage temperature reads as "draw attention, but with
  care." Resolved to system-wide wiring in Phase 6.6 task D.1 — see
  the Phase 6.6 amendment paragraph in the red-flag badge section
  below for the full resolution path.

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

Six steps, hand-tuned to step up from `warmOffWhite` without
M3-default lavender drift on a sage seed. Monotonic in warmth (R/G
channels rise as the band raises), so lifted surfaces read creamier,
not cooler:

- `lightSurfaceLowest` `#FFFFFF` — pure white. Used where containers
  recede from the warm background (input fill, chat-thread inset).
- `lightSurfaceLow` `#FBFAF7` — barely-visible lift above background.
- `lightSurface` `#F7F5F2` — canonical scaffold background.
- `lightSurfaceContainer` `#F2EFE9` — default Card / PetCard fill;
  journal entries + form sections sit here.
- `lightSurfaceContainerHigh` `#EDE9E1` — raised cards, dialogs,
  chat composer slab.
- `lightSurfaceContainerHighest` `#E7E2D7` — empty-state badge
  circles, high-contrast skeleton bars.

### Dark-mode warm-graphite scale

DECISIONS row 38 locked dark mode as **honest warm graphite**, not
sage-tinted dark and not pure black:

- `darkSurfaceLowest` `#161512` (deepest, chat thread) →
  `darkSurfaceLow` `#1F1E1C` → `darkSurface` `#23211E` (scaffold) →
  `darkSurfaceContainer` `#28261F` → `darkSurfaceContainerHigh`
  `#2D2B22` → `darkSurfaceContainerHighest` `#33302C`.
- `darkOnSurface` `#EEE9E0` — warm off-white text, mirroring the
  light-mode warmth.

Sage and coral remain accents in dark mode; surface bands stay
neutral-warm-graphite so content reads cleanly. **Do not propose
dark concepts that wash sage through the surface bands** — that's
the rejected "sage-tinted dark" direction.

### M3-derived semantic tokens

Where the brand explicitly diverges from M3 defaults (sage primary,
warm-cream surfaces, coral tertiary), the scheme is hand-set;
elsewhere FlexColorScheme's tonal harmony is used as-is.
**`scheme.error`** is M3-default red, used for save-error text and
the chat error banner — never repurposed as a brand color.
**Outline tones** carry hairline dividers at low alpha. **`onPrimary`
is manually pinned**: `warmOffWhite` in light mode (cream label on
sage button, not stark white), `graphite` in dark mode (legible dark
label on sage button against a warm-graphite surface).

### Color usage doctrine

Sage carries the brand (sparingly — hero moments, primary actions,
focus states, chart accents). Surfaces carry the warmth (the scale
is the dominant visual signal). Coral is reserved warning-
temperature attention; never large, never a CTA. Error red is
M3-default failure-only. Outline tones are atmospheric hairlines —
never borders that draw the eye.

---

## 4. Typography Pairing with Intent

PetPal pairs **Inter** (UI body) and **Source Serif 4** (journal
accent). DECISIONS row 38 locked both as bundled variable TTFs (`wght`
axis from 100 → 900) under `assets/fonts/`, with runtime weight
selection via `TextStyle.fontVariations: [FontVariation('wght', X)]`
so weight is continuous rather than stepped through static slots.

### Inter — the utility-functional choice

Inter is the default font for every Material 3 `TextTheme` slot.
That means Inter renders: AppBar titles, ListTile titles + subtitles,
form field labels + body text + hints, dialog content, snackbar
copy, button labels, chip labels, chat bubble body text, tool pill
labels, navigation destination labels, settings rows. The user's
hands-on operating surface is entirely Inter.

Type scale is M3 reference defaults (DECISIONS row 38) so platform
components inherit correct sizing automatically. The slots in use
across the app: `displaySmall` 36 for hero / home-greeting names;
`titleLarge` 22 for AppBar titles; `titleMedium` / `titleSmall`
weight-500 for section headers and ListTile titles; `bodyLarge` /
`bodyMedium` weight-400 for flowing text (positive M3 letter-spacing
keeps Inter warm, not tight); `labelLarge` / `labelMedium` /
`labelSmall` weight-500 for buttons, chips, and micro-labels
(timestamps, byte sizes, the "from {grounding-ref}" footer on the
affective observation card).

Weight-axis usage: theme uses 400 (regular) on body, 500 (medium) on
titles + labels. Bold is reserved — markdown `**bold**` resolves to
weight 600 (semibold), keeping emphasis visible without slamming into
a heavy slab. [INTENT-INFERRED] The 600-not-700 choice reads as
"deliberate journal emphasis," not marketing emphasis.

### Source Serif 4 — the literary-deliberate choice

Source Serif 4 is **scoped to journal-aesthetic surfaces**. The
helper class `JournalText` (in `lib/app/design/typography.dart`)
exposes two styles, deliberately not surfaced through the
`TextTheme` so callers must reach for the journal accent
explicitly:

- `JournalText.entryTitle` — 24 / weight 600 / line-height 1.25.
  Reads with weight; looks like a notebook heading, not a UI label.
  Used on individual journal entry titles in the entry view, the
  digest card on the journal browser, and the wiki entry markdown
  renderer's `h1` style.
- `JournalText.weeklySummaryTitle` — 28 / weight 600 / line-height
  1.2. Slightly larger than a regular entry title; the weekly
  summary is a cumulative artifact and the type signals that.

Markdown body headings inside an entry render Source Serif 4 too
(`h1` mirrors `entryTitle`, `h2` is the same family at 20pt), so
prose written by the agent or the user reads as journal copy
rather than UI text.

### The pairing logic

Serif when the user is meant to **slow down and engage with content
as content**: journal entries, weekly summaries, the per-pet greeting
on home (the name is in display Inter, but the cinematic-arrival
treatment + serif body headings inside the entry give the same
register on read). Sans when the user is **navigating or operating
the app**: settings rows, form fields, chat composer, AppBar titles,
buttons, chips, all chrome.

The scoping is enforced by the `TextTheme` itself being all-Inter —
serif requires an explicit `JournalText.*` call. Stitch concepts that
propose serif on chrome (AppBar titles, button labels, settings rows,
nav destinations) are drifting from this rule.

[INTENT-INFERRED] The home greeting pet name uses Inter `displaySmall`,
**not Source Serif 4**. Cinematic arrival comes from gradient + scale
+ space, not typeface. Concepts swapping to serif should be evaluated
for whether literary weight outweighs the drift from current treatment.

### Typography rhythm

Display signals "moment" (home greeting, weekly digest). Title signals
"section / object" (AppBar, list rows, card headers). Body signals
"content" (entries, chat bubbles, settings copy). Label signals
"metadata / control" (buttons, chips, micro-text). Concepts that
invert the rhythm — label on a hero, body in a chip — read as drift.

---

## 5. Motion Vocabulary

Motion serves the moment, never decorative. Spring-based for moments
that should feel **alive**; ease-out for moments that should feel
**deliberate**. DECISIONS row 38 locked the duration scale at M3
standard; row 50 added the custom spring curve as part of Phase 5.6
Feel Polish.

### Duration tokens

- `Motion.short` 200 ms — everyday navigation, AnimatedOpacity
  fades, AnimatedScale on press, snackbar enter/exit, dropdown
  reveals, the icon-button dispatch.
- `Motion.medium` 300 ms — AnimatedSwitcher cross-fades between
  empty / named-pet states on home, page transitions, the cross-
  fade on the home greeting hero between empty and pet-loaded.
- `Motion.long` 500 ms — hero moments only. The memory-saved bloom
  uses this; the per-pet greeting initial mount uses this; the
  weekly-summary editorial entrance uses this.

### Curves

- `Motion.standardCurve` = `Curves.easeOutCubic` — reads as "settles
  in." Used on every transition that should feel deliberate, not
  bouncy: snackbar landing, content fades, page transitions. The
  default unless a moment earns the spring.
- `Motion.heroCurve` = `Curves.easeOutCirc` — slightly more
  anticipatory than standard. Reserved for hero moments where a
  touch of personality is OK (the home greeting initial mount).
- `Motion.springCurve` — custom curve adapter over a `SpringSimulation`
  with stiffness 180, damping 22, mass 1. Damping ratio ≈ 0.82, one
  barely-visible oscillation, settles in ~600 ms. Reads as "alive
  but composed." Used on:
  - PetButton press physics (scale 1.0 → 0.98 on press, spring back
    on release; lives at the inner-content level so all three
    variants — filled / outlined / text — inherit).
  - JournalBloom moveY (0 → -24 dp rise during the memory-saved
    confirmation).
  - AnimatedSwitcher reveals on the add-pet form (relationship sub-
    classification, lifecycle date kind swap, rescue-rehab dates).
  - Home greeting hero AnimatedSwitcher between empty and named-pet
    states.

`Motion.springDescription` exposes the same physics as a raw
`SpringDescription` for callsites that drive an `AnimationController`
directly rather than passing a `Curve`.

### Hero moments as motion experiences

- **Memory-saved bloom** (`JournalBloom`, fires on
  `write_wiki_entry` success). A `bookOpen` Phosphor icon overlays
  the chat thread's bottom edge and runs a one-shot rise + fade:
  fade-in 150 ms, hold while moveY 0 → -24 with springCurve over
  350 ms, fade-out 200 ms. Pairs with a lightImpact haptic — the
  buzz precedes the visual, so the icon lands as confirmation, not
  anticipation. *Kinetic confirmation of capture.*
- **Home greeting** (`_PetGreetingHero`). Photo backdrop at 25%
  opacity (when present), sage `primaryContainer` → `surface`
  vertical gradient, pet name centered in `displaySmall` Inter,
  FittedBox-scaled. AnimatedSwitcher between empty and pet-loaded
  uses `Motion.medium` + `springCurve`. *The pet's name is already
  there waiting when the user arrives.*
- **Weekly summary editorial entrance** (`_DigestCard`, journal
  browser). Distinct card treatment — `JournalText.weeklySummaryTitle`
  + a different visual register from regular journal tiles. Mount
  motion is subtle; the visual lift carries the weight.
  *Publication-style break in the journal flow.*
- **Sub-classification picker reveal** (add-pet form). AnimatedSwitcher
  swaps the secondary picker on relationship change with springCurve
  so the swap feels physically connected to the tap.
- **PetButton press physics** — see §6's `PetButton` entry.
- **Modal sheet stretch overscroll** — `StretchingOverscrollIndicator`
  on the species + breed picker bottom sheets. Phase 5.6 Commit C
  lock; iOS-style bouncing rejected as wrong-platform, glow
  indicator rejected as dated.

### Motion philosophy

Spring for the alive (presses, reveals, captures — moments the user
should feel the app responding physically). Ease-out for the
deliberate (page transitions, snackbar landings, content fades —
composed, not reactive). Long durations are earned: default is short
/ medium; `long` is reserved for the three hero moments (memory
saved, home greeting, weekly summary entrance). Concepts that
propose long durations on everyday navigation have drifted.

---

## 6. Component Primitives

PetPal's primitives in `lib/app/widgets/` encode the warm-journal
register so every screen inherits the brand without re-deciding
component shape. DECISIONS row 51 rejected shadcn-style libraries
because PetPal already has the equivalent — these primitives ARE
the design system surface area.

- **`AppScaffold`** — shared layout chassis. Three constructors:
  default (`title:`, `body:`), `hero` (adds a 120 dp heroBuilder
  region between AppBar and body, used by home for the per-pet
  greeting), and `async<T>` (Riverpod-aware, default loading is a
  `PetSkeleton` stack, default error is a `PetEmptyState` with
  retry). AppBar treatment is flat at rest, `Elevation.low` when
  scrolled-under, sage `surfaceTint`. Optional `petAccent` blend at
  8% on the AppBar reserved for future per-pet palette
  pull-through.
- **`PetCard` / `PetCardButton`** — `surfaceContainer` fill,
  `Radii.m` (16 dp), `Elevation.low`. Structural unit for grouped
  content. Tappable variant clips an InkWell ripple inside the
  rounded corners.
- **`PetSectionHeader`** — `titleSmall` (Inter Medium 14) at
  `onSurface@0.65`, `letterSpacing 0.6`. Distinct from content rows
  without competing with the AppBar title. **The section-grouping
  pattern is canonical** (task 5.12): a `PetCard` holding a
  `PetSectionHeader` + grouped content is the structural rhythm for
  every form, editor, and settings surface. Concepts that propose
  full-bleed sections or standalone dividers are drifting.
- **`PetButton`** — three variants matching M3 emphasis levels
  (`filled` / `outlined` / `text`), pill shape (`StadiumBorder`).
  Filled = sage fill + warm-off-white label. Loading state uses
  `Stack` + `AnimatedOpacity` so width never changes (no layout
  shift on tap). Press physics from §5. Labels stay static
  (VOICE.md §1) — `label` is a plain `String`, not a builder.
- **`PetEmptyState`** — canonical "nothing here yet" surface. 96 dp
  `surfaceContainerHigh` circle around a 44 dp icon at
  `onSurface@0.7`, `titleLarge` heading, `bodyMedium` body at
  `onSurface@0.7` (the muted teaching tone VOICE.md §1 calls for),
  optional CTA slot. LayoutBuilder wraps the content in a
  centered scroll view so wrapping action chips don't overflow.
- **`PetSkeleton` / `PetSkeletonListRow`** — opacity-pulse loading
  primitive (~55% ↔ ~95% over 1500 ms, `Curves.easeInOut`). No
  horizontal shimmer; reads as "calmly waiting." Three shapes
  (`line` / `rectangle` / `circle`) compose into a ListTile-shaped
  `PetSkeletonListRow` (40 dp leading circle optional, 1–2 stacked
  lines, optional 56×28 trailing chip).
- **`PetIcon`** — theme-aware `Icon` wrapper, defaults to
  `onSurface@0.85`. Phosphor **regular weight** is the lock
  (DECISIONS row 50) with three exceptions: `warningOctagon` for
  medical red-flag escalation (visual weight for the medical
  context), `key` for API-key states, `bookOpen` for journal
  context (open-book reads as journal aesthetic; closed-book reads
  as library shelf).
- **`RedFlagBadge`** — subdued historical-record badge. Two
  presentations: default (icon + label row) on chat scrollback +
  photo entry headers + form previews; `.tile()` (icon-only chip)
  overlaying photo timeline grid cells. Persists forever
  (CLAUDE.md §10).
- **`JournalBloom`** — hero-moment overlay fired on
  `write_wiki_entry` success. See §5.

### Composition rules

- `PetCard` + `PetSectionHeader` is the structural rhythm for forms
  and editors. Don't nest cards.
- One primary `PetButton` per form / dialog. M3 emphasis says one
  primary action.
- `PetSkeletonListRow` matches the geometry of the real `ListTile`
  it previews — don't fudge widths.
- `AppScaffold` wraps every screen; never reach for a vanilla
  `Scaffold`.
