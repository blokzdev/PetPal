# PetPal

**A memory-first companion for pet owners.** Chat with PetPal about your
pet. PetPal quietly grows a private journal — vet visits, weight, food
trials, behavior notes, photos — in plain markdown you own. Months later,
when you ask "when did Loki last react to chicken?", the answer is right
there.

## What you get

- **A journal that compounds.** Every conversation adds to a per-pet
  journal you can search, browse, and export.
- **Calm, specific answers.** Grounded in your pet's own history.
  PetPal cites the entry it's drawing from.
- **Species-aware care guides.** Built-in guides for puppies, senior
  dogs, and new cats; reptile / bird / rabbit / fish / small-mammal
  profiles supported. PetPal never tries to apply dog advice to a cat.
- **Reminders that don't burn tokens.** Flea, vaccine, med schedules
  fire on time without an LLM in the loop.
- **A weekly recap (Pro).** Every Sunday, a summary of your pet's week
  written into the journal.
- **Yours to take with you.** Export the whole journal as a zip,
  any time. No telemetry. Optional encrypted sync — never the default.
- **Never a diagnosis.** Red-flag symptoms trigger an unmistakable
  "call your vet now" UI. PetPal is software, not a vet.

## Why this works

PetPal is a deliberate bet on **harness engineering** — the thesis that
as foundation models commoditize, the moat is the architecture *around*
the model, not the model itself. The agent loop, the per-pet markdown
journal, the species-filtered care guides, the deterministic safety
screener: these are the product. The model is a swappable component.

Background reading on the thesis:

- *SemaClaw* — [arxiv.org/abs/2604.11548](https://arxiv.org/abs/2604.11548)
- *Externalization in LLM Agents: a survey* — [arxiv.org/abs/2604.08224](https://arxiv.org/abs/2604.08224)

Two design choices that follow from it:

- **Markdown files are the source of truth.** SQLite is a rebuildable
  index. Lose the database, regenerate it from the files. (DECISIONS row 1)
- **Local-first, on-device retrieval.** A 23 MB embedding model ships
  with the app; semantic search runs offline. Only the chat call
  itself reaches Anthropic. (DECISIONS row 20)

## Screenshots

_TODO: add screenshots once the launch UI lands._

## Status

In active development; Phase 3 (care guides + weekly summary) just
shipped. Phase 4 (reminders + medical-safety pre-screener) is next.
Roadmap and phase-by-phase plan in [ROADMAP.md](./ROADMAP.md).

## Internal docs

- [PRODUCT.md](./PRODUCT.md) — product vision, target users, monetization.
- [VOICE.md](./VOICE.md) — brand voice and the internal-vs-user-facing
  vocabulary table. Read this before writing any UI string.
- [CLAUDE.md](./CLAUDE.md) — agent working guide; architecture, file
  layout, system-prompt structure.
- [ROADMAP.md](./ROADMAP.md) — six phases; current status at the top.
- [DECISIONS.md](./DECISIONS.md) — append-only log of non-obvious
  architectural and product decisions.

## Tech stack

Flutter (Android-first, min SDK 24) · Drift over `package:sqlite3` 3.x
· FTS5 + sqlite-vec for hybrid keyword + semantic retrieval · Snowflake
arctic-embed-xs (INT8 ONNX, 23 MB) running on-device via
`flutter_onnxruntime` · Anthropic Claude (Sonnet 4.6) for chat with
prompt caching · Riverpod for state · go_router for routing ·
flutter_secure_storage for the API key · share_plus for export.

## License

_TODO: pick a license before public launch (MIT vs Apache-2.0)._
