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

Three narrow exceptions where AI framing is **mandatory**:

1. **Onboarding privacy disclosure.** Plain language about which calls
   leave the device and what they carry. Required for trust and Play
   Store data-safety compliance.
2. **Anywhere the user is making a safety judgment** (red-flag
   escalations, medication-related answers): briefly remind them PetPal
   is software, not a vet, before the substantive content.
3. **Backend routing disclosure (onboarding, BYOK toggle, Settings).**
   Plain language about which path a chat call takes. By default,
   messages and the relevant memories about the pet route through
   PetPal's servers to Anthropic's Claude — that's how the monthly free
   allowance is metered. With BYOK on, calls go direct to Anthropic
   using the user's API key, and PetPal's servers never see them. Both
   paths are honest framing; the user picks.

Outside those three contexts, the words "AI", "LLM", "agent",
"assistant", and "chatbot" do not appear in body copy.

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

Also forbidden: **metering language in the chat surface itself**
("12/200 messages used", countdown badges on the composer, progress
bars draining as the user types). The monthly chat counter lives in
Settings as ambient information; chat is unmetered visually. See §7
for the underlying principle.

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

    Badge styling on the flagged assistant bubble:
      Live (the turn that just finished): the preamble itself is the
        alert — no separate badge or banner is needed. The bubble is
        the alert.
      Scrollback (historical): a small `Icons.warning_amber_rounded`
        icon on the bubble + muted "PetPal flagged this as urgent"
        subtitle. Persists forever — it is a historical record, not a
        current-state indicator. Survives any future edit-message or
        mark-resolved feature (Phase 5+).

11. Free-tier monthly chat row in Settings
    Bad:  "127/200 messages used. Upgrade to Pro for unlimited."
    After: "PetPal handles 200 chats a month on the free plan. You've
            had 127 so far this month — plenty of room. Pro lifts the
            limit if you'd rather not think about it."
                                          (counter is ambient, not a
                                          meter; never appears on the
                                          chat surface itself)

12. BYOK toggle in Settings
    Bad:  "Use your own API key to bypass the quota."
    After: "Bring your own Anthropic key
            By default, PetPal handles the connection to Claude and
            includes a monthly chat allowance. Switch this on if you'd
            rather use your own Anthropic API key — your messages then
            go directly to Anthropic without passing through PetPal's
            servers, and the monthly limits don't apply."
                                          (additive, not extractive;
                                          honest about the routing)

13. Photo credit pack purchase prompt (Pro user, vision cap reached)
    Bad:  "Out of vision credits. Buy 50 more for $2.99."
    After: "Photo analysis: 30 a month on Pro
            You've used this month's allowance. Top up with 50 more
            for $2.99 — they don't expire, so unused ones roll into
            next month."
                                          (cost-per-action framing fits
                                          vision; never used for chat)

14. Pro upgrade prompt at the monthly chat allowance
    Bad:  "You've hit the free limit. Subscribe now."
    After: "That's 200 messages this month
            You've used this month's free allowance. Pro lifts the
            limit, adds sync across devices, and unlocks photo
            analysis — or, if you'd rather, switch to your own
            Anthropic API key in Settings to keep chatting now."
                                          (offer both ladders: pay or
                                          BYOK; never strand the user)

15. Onboarding privacy disclosure (replaces the API-key entry page)
    Bad:  "Enter your Anthropic API key to begin."
    After: "How chat works
            When you ask PetPal something, your message and the
            relevant memories about your pet go to Anthropic's Claude.
            By default, PetPal routes that through our servers — this
            is how the free 200-message-a-month allowance works, and
            it's the only thing that leaves the phone. You can switch
            to your own Anthropic API key any time in Settings; with
            that on, calls go direct to Anthropic and our servers
            don't see them."
                                          (defaults to no-friction
                                          onboarding; surfaces BYOK as
                                          a Settings choice, not a
                                          required setup step)
```

## 7. Monetization voice principles

Three rules govern every string in a quota row, paywall screen, upsell
prompt, Settings row, or purchase confirmation:

1. **Additive framing.** Pro adds — never subtracts what was promised
   free. "Pro lifts the limit," not "you've hit the free cap." The free
   tier is functional and respected on its own terms.

2. **No metering language in chat.** Chat is an emotional, companion-
   positioned surface. A "12/200 used" badge on the composer breaks the
   warmth. The counter belongs in Settings only, framed as ambient
   information, not a meter ticking down. The reminder cap (5) and the
   pet count (1) follow the same rule — they're stated where you'd
   naturally encounter them, not surveilled.

3. **Credits only for vision.** The photo credit pack is the only
   credit-balance UI in the app. Vision is the only feature where "one
   photo, one analysis" is intuitive cost-per-call. Metering chat by
   credits would feel transactional and would conflict with the
   companion positioning — a rejected design we considered and
   deliberately walked away from (DECISIONS row 36).

The deeper rule: PetPal is a memory companion. Anything that makes a
user feel they're paying to access their own pet's memories breaks the
product. Quotas exist for cost-bounding, never for friction.

## 8. Process

- New copy goes through this file before it ships. Reviewers reject
  strings that fail §1–§5.
- When the harness gains a new tool (Phase 4 brings `schedule_reminder`),
  the migration table in §3 grows in the same commit.
- A grep CI lint enforces §4 against `lib/app/` (Phase 5 task; flagged
  in ROADMAP).
