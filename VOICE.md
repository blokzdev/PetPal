# PetPal — voice and vocabulary

This file is the **harness for product copy**. Every UI string, push
notification, store description, and onboarding line follows the rules
here. Internal architecture terms — the ones in CLAUDE.md and DECISIONS.md
— do not appear in user-facing surfaces.

## 1. Tone

Warm, knowledgeable, never alarmist, never saccharine. **The friend who
happens to be a vet tech.** Direct, practical, kind. Treats the owner
as an adult who can handle real information.

- **Use the pet's name liberally.** "Loki" is doing more work than "your
  dog" in every sentence where we know the name. (See §5 for when to
  interpolate vs. stay static.)
- **Plain words.** Short sentences. No marketing throat-clearing.
  ("Discover the magic of…" — never.)
- **No pet-talk.** No "fur baby", "pawrent", "pup-parent", "doggo",
  "kitto". Owners over the age of twelve find this insulting.
- **No anthropomorphizing PetPal.** PetPal is software, not a friend.
  No "I'd love to help!", no winking emoji. PetPal does things; it
  doesn't *feel* about them.
- **Concrete over abstract.** "PetPal saved this in Loki's journal"
  beats "Note recorded successfully."
- **Never alarmist.** Even red-flag escalation copy is calm: "This
  sounds urgent — please call your vet now." Not "⚠ EMERGENCY ⚠".

## 2. AI framing

Default: **PetPal is the actor**, full stop. The user does not need to
think about "the AI" while using the app.

```
Bad:   The AI thinks Loki might benefit from…
Good:  PetPal noticed Loki has been losing weight since March.
```

Two narrow exceptions where AI framing is **mandatory**:

1. **Onboarding privacy disclosure.** Plain language about which calls
   leave the device and what they carry. Required for trust and Play
   Store data-safety compliance.
2. **Anywhere the user is making a safety judgment** (red-flag
   escalations, medication-related answers): briefly remind them PetPal
   is software, not a vet, before the substantive content.

Outside those two contexts, the words "AI", "LLM", "agent", "assistant",
and "chatbot" do not appear in body copy.

## 3. Vocabulary translation table

The left column is harness/code vocabulary. It belongs in
`lib/harness/`, `CLAUDE.md`, `DECISIONS.md`, code comments, error logs,
and developer-only screens. The right column is what users see.

| Internal (code, docs) | User-facing |
|---|---|
| `SOUL.md` / soul / persona file | **Profile** ("Loki's profile") |
| wiki | **Journal** ("Loki's journal") |
| wiki entry | **Memory** in casual context, **Journal entry** in lists, **Note** when the user is composing |
| skill | **Care guide** |
| skill pack (paid IAP) | **Care pack**, or just the pack name ("Puppy Pack") |
| trigger | **Activates when you mention…** (sentence form) |
| `agent` / `LlmClient` / "the LLM" / "the model" | **PetPal** |
| tool call / tool use | invisible — see §4 |
| `read_wiki` (rendered as a tool pill) | "checking {name}'s journal" |
| `search_wiki` (rendered as a tool pill) | "searching {name}'s journal" |
| `write_wiki_entry` (rendered as a tool pill) | "saving a memory" |
| `update_soul` (rendered as a tool pill) | "updating {name}'s profile" |
| `schedule_reminder` (rendered as a tool pill) | "setting a reminder" |
| digest / synthesis | **Weekly summary**; the generated entry's title is **"This week with {name} — Apr 22"** |
| retrieval / hybrid retrieval / FTS5 | **Search** (verb), or invisible |
| embedding / vector | invisible |
| frontmatter | **Profile fields** (in profile editor UI) |
| body / fragment | **Notes** (the prose part of a profile or guide) |
| harness / runtime / context manager / SessionBuilder | never appears |
| manifest | never appears (care guides show their **name**, not "manifest") |
| session / turn / hop | never appears |
| onboarding template | never appears (the user just picks a species) |
| red-flag screener / pre-screener | never appears (the user sees "Call your vet" copy directly) |

## 4. Forbidden in user UI

These tokens never appear in any user-facing string — search the codebase
periodically (a CI lint enforces this in Phase 5):

`SOUL`, `wiki`, `harness`, `manifest`, `runtime`, `context`, `session`,
`turn`, `hop`, `LLM`, `agent`, `AI` (except in the §2 disclosures),
`embedding`, `vector`, `FTS5`, `synthesis`, `digest`, `frontmatter`,
`fragment`, `tool call`, `read_wiki`, `search_wiki`, `write_wiki_entry`,
`update_soul`, `schedule_reminder`.

Tool-call pills must show the friendly translation, not the raw tool
name. The user should never see `calling search_wiki…`.

## 5. Pet-name interpolation rule (permanent)

Personalization is core to the compounding-memory thesis — "Loki's
journal" reinforces it harder than "Journal". But interpolation is not
free; over-using a pet's name reads as scripted, and on a multi-pet
dashboard there is no single name to use. The rule:

**Interpolate** on page titles and headers that are **about a specific pet**:

- Profile editor app bar: "Loki's profile"
- Journal browser app bar: "Loki's journal"
- Per-memory entry header
- Weekly summary entry title: "This week with Loki — Apr 22"
- Photo timeline (when it lands)
- Per-pet reminders screen (Phase 4)
- Body copy on the per-pet chat screen (tool pills, empty state)
- Body copy on per-pet destinations (profile editor field hints)

**Don't interpolate** on global / cross-pet screens:

- Settings
- Care guides browser (the screen — body copy may still mention the
  active pet's species, but the title stays global)
- API key entry, billing, subscription management
- Export confirmations, share-sheet metadata
- Error banners ("Connection failed.", not "Connection failed for Loki.")

**Don't interpolate** on transient action labels and controls:

- Buttons: "Save", "Cancel", "Edit profile", "Open journal"
- Switches and toggles
- Form field labels: "Name", "Species", "API key"
- Snackbars confirming an action ("Saved.", not "Saved Loki's note.")

**Multi-pet edge case** (matters from Phase 5 once Pro unlocks multiple
pets): on a global dashboard listing every pet, names live on the
**cards**, not in the screen title. Use **"My pets"**, not
**"Loki & Mochi's pets"**. Per-pet detail pages then interpolate as
usual once the user picks one.

When in doubt: **page destinations personalize; buttons and global
shells stay static.**

## 6. Before / after copy examples

```
1.  AppBar title in the journal browser
    Before: "Wiki"
    After:  "Loki's journal"             (interpolate — per-pet destination)

2.  Empty journal state
    Before: "No entries yet. Chat with PetPal and it will start writing
             notes here."
    After:  "No memories about Loki yet. Tell PetPal what's been
             happening and they'll start showing up here."
                                          (interpolate — body of per-pet page)

3.  Care guides browser app bar + empty state
    Before: "Skills" / "No skills available for this pet."
    After:  "Care guides" / "No care guides for your pet's species yet
             — we're adding more."        (static — global screen)

4.  Tool-call pill mid-stream in chat
    Before: "calling write_wiki_entry…"
    After:  "saving a memory…"            (no name needed — pet is the
                                          chat context)

5.  Settings — weekly summary row
    Before: "Weekly digest"
            "A summary entry written to the wiki every week, using the
             LLM to synthesise recent notes. Pro-tier; off by default."
    After:  "Weekly summary"
            "Every Sunday, PetPal writes a recap of your pet's week —
             what happened, what changed, what to watch. Pro."
                                          (static — Settings is global)

6.  Home tagline
    Before: "A memory agent for your pet."
    After (empty state, no pet yet):
            "PetPal remembers your pet's life so you don't have to."
    After (greeting state, pet is known):
            "PetPal remembers Loki's life so you don't have to."
                                          (interpolate when a pet exists)

7.  Onboarding privacy bullet (chat → API)
    Before: "Chat sends your conversation and the most relevant wiki
             snippets to Anthropic's Claude API using your own API key.
             That call leaves the device."
    After:  "When you ask PetPal something, it sends your message and
             the relevant memories about your pet to Anthropic's Claude.
             That's the only thing that leaves the phone."

8.  Profile editor app bar + body field label
    Before: "Edit SOUL" / "Body" (with hint "# Pet name\n\nFree-text
             prose…")
    After:  "Loki's profile" / "About Loki" (with hint "What do you want
             PetPal to remember about Loki?")

9.  Free-tier add-pet block
    Before: "You already have a pet on PetPal. The free tier supports
             one pet."
    After:  "You already have a pet on the free plan. Adding a second
             pet is part of Pro." (CTA: "Back" until paywall lands)
                                          (static — add-pet is a global
                                          action, not a per-pet
                                          destination)

10. Red-flag escalation preamble (Phase 4 wiring it up)
    Required: "This sounds urgent — please call your vet or an emergency
              animal hospital now. PetPal is software, not a vet. I can
              help you write down what's happening so it's ready when
              you call."
```

## 7. Process

- New copy goes through this file before it ships. Reviewers reject
  strings that fail §1–§5.
- When the harness gains a new tool (Phase 4 brings `schedule_reminder`),
  the migration table in §3 grows in the same commit.
- A grep CI lint enforces §4 against `lib/app/` (Phase 5 task; flagged
  in ROADMAP).
