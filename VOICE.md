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

## 5.5. Relationship picker labels and surface rule

PetPal asks every user about their relationship to the animal at
add-pet time. The picker is shown to everyone with **Pet** pre-selected
so casual owners tap through in two seconds; rehabbers and observers
see their use case named. Per DECISIONS row 44, the relationship is a
SOUL.md fact that shapes content — not a UI chrome modifier.

**Locked picker labels** (4-value `relationship` enum, frontmatter
key `relationship`):

- **Pet** — frontmatter value `pet`, default
- **Rescue / rehab** — frontmatter value `rescue-rehab`
- **Permanent wildlife** — frontmatter value `permanent-wildlife`
- **Wildlife observation** — frontmatter value `wildlife-observation`

All four read as situation-describing noun phrases, parallel
grammatical shape, picker-vertical-friendly. The slash in "Rescue /
rehab" makes the multi-purpose nature visual. "Permanent wildlife"
drops a redundant "care" (implicit when paired with the other three).

**Sub-classification labels** (three optional secondary fields per
DECISIONS row 45, each conditional on the relationship pick):

- *When relationship = Pet*, secondary picker `working_role`:
  None (default — "companion") / Service / Therapy / Working / Other
- *When relationship = Rescue / rehab*, secondary picker `rehab_context`:
  None (default) / Foster / Medical / Behavioral / Palliative /
  Conditioning / Quarantine / Other
- *When relationship = Permanent wildlife*, secondary picker
  `care_context`: None (default) / Sanctuary / Educational /
  Non-releasable / Other
- *When relationship = Wildlife observation*: no secondary picker

**Surface rule — relationship affects content, not destination labels.**

Relationship is a SOUL.md fact that shapes:

- Skill-pack filtering (rehab packs activate when relationship =
  rescue-rehab; service-dog packs activate when working_role = service)
- Profile editor field visibility (intake_date / expected_release_date
  appear conditionally when relationship = rescue-rehab)
- AI emphasis in chat ("track Loki's release readiness" vs. "track
  Loki's vet schedule")
- Weekly-summary phrasing
- The SOUL body template fork at onboarding (5.5.5)

It does **not** shape:

- App-bar titles (still "Loki's journal" — never "Loki's rehab journal")
- Button labels, navigation copy, scrollback
- Snackbars, error banners, toasts
- Pet switcher cards (still "Loki" — never "Loki (rescue)")

A rescue that becomes unreleasable transitions from rescue-rehab to
permanent-wildlife over its life, and the destination labels shouldn't
visibly mutate when that happens. The relationship is asked once at
onboarding, recorded in SOUL frontmatter, edited later in the profile
editor, and expressed through the body's opening paragraph and the
agent's behavior — not through running surface copy.

The §5 pet-name interpolation rule (DECISIONS row 27) stays exactly
as-is. Relationship is one layer deeper than chrome.

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
      Scrollback (historical): a small `PhosphorIconsRegular.warningOctagon`
        icon on the bubble + "PetPal flagged this as urgent" subtitle,
        rendered in the **coral primary** medical-attention register
        (CLAUDE.md §10 / DECISIONS rows 50 + 64 + 96 — coral is the
        systemic medical-warning primary; the original "muted gray"
        treatment was abandoned in Phase 6.6 once card-level coral
        context made an inner gray badge visually incoherent). The
        badge is subdued in stature (small icon, no large alert
        chrome) but primary in color. Persists forever — it is a
        historical record, not a current-state indicator. Survives
        any future edit-message or mark-resolved feature (post-launch
        scope; Phase 5 was renumbered to design system per DECISIONS
        row 34).

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

16. Settings — Account tile (signed out)
    Bad:  "Sign in to PetPal" / "Required for sync."
    After: "PetPal account"
           "Sign in to sync your journal across devices and pick up
            where you left off on a new phone. Free chat works
            without an account."
                                          (sign-in is additive, not
                                          required. Free use without
                                          sign-in is the brand
                                          promise — the copy must
                                          land that thesis instantly
                                          so users don't read the
                                          tile as a gated
                                          requirement.)

17. Settings — Account tile (signed in) + sign-out confirmation
    After (tile):
            Title:    "Signed in as alice@example.com"
            Subtitle: "Sync mirrors your journal end-to-end encrypted
                       across every device you sign in on."
            CTA:      "Sign out"

    After (confirmation dialog):
            Title:    "Sign out of PetPal?"
            Body:     "Your journal stays on this device — sign-out
                       only pauses sync. The next time you sign in,
                       sync picks back up where it left off."
            Buttons:  "Cancel" / "Sign out"
                                          (reassurance is the
                                          load-bearing fact: local
                                          data stays intact, sync
                                          pauses, no data loss. Users
                                          who hesitate at "Sign out"
                                          are usually worried about
                                          losing the journal — name
                                          the worry, dispel it.)

18. Sign-in screen (the magic-link flow)
    Title:    "Sign in to PetPal"
    Body:     "We'll email you a link. Tap it on this device to sign
               in — no password needed."
    Field:    "Email"
    Button:   "Send sign-in link"

    Privacy disclosure (small card below the button):
              "Your account links your devices for sync and the free
               monthly chat allowance. Your journal stays end-to-end
               encrypted — PetPal can't read it."

    After (confirmation state, post-send):
    Headline: "Check your inbox"
    Body:     "We sent a sign-in link to alice@example.com. Tap it on
               this device — PetPal will open signed in."
    Hint:     "The link expires in an hour. Didn't get it? Try a
               different email below."
    CTA:      "Try a different email"
                                          (passwordless framing;
                                          single-device flow named
                                          honestly — "tap it on this
                                          device" prevents the cross-
                                          device-tap edge case from
                                          becoming a support ticket.
                                          Privacy disclosure inline
                                          on the entry screen, not
                                          buried elsewhere.)

19. Sync card — "setup needed" gate register
    Bad:  "Pick a passphrase to encrypt your journal across devices.
           Only you can read it — PetPal can't."
    After:"Set up sync passphrase"
          "This passphrase encrypts your journal so PetPal can't read
           it. **PetPal cannot recover it if you forget.** Pick
           something you'll remember and write it down."
                                          (gate register, not warm
                                          continuation. The
                                          passphrase is the most
                                          consequential moment in the
                                          app — irrecoverable if
                                          lost. Copy primes the user
                                          to approach the three-stage
                                          modal with appropriate
                                          gravity. The bold sentence
                                          is load-bearing; it surfaces
                                          irrecoverability before the
                                          modal does.)

20. Account deletion — single-screen disclosure + typed gate
    Title: "Delete your PetPal account"
    Body:  "This permanently removes your account from PetPal. Here's
            what happens:

            • Your journal on this device is deleted
            • Your synced copy on PetPal's servers is deleted within
              30 days — sign in within that window to undo
            • Active subscriptions stay on your Google Play account;
              cancel them in Play Store before deleting if you want
              a refund
            • Your sync passphrase is removed and cannot be recovered
            • PetPal's records of your AI chat usage are deleted

            Want to keep a copy of your journal first? [Export to ZIP]

            Type DELETE below to confirm."
    Field: "DELETE"
    Button: "Delete account"  (disabled until field matches exactly)
                                          (single-screen disclosure
                                          per DECISIONS row 77's
                                          Option e. Friction-as-
                                          discipline lives in the
                                          typed-confirmation gate at
                                          the end, not in stretching
                                          the cascade across five
                                          screens. Export inline as a
                                          choice — never a forced
                                          step. The five points are
                                          listed in the order a user
                                          would worry about them:
                                          local data first, server
                                          data second, money third,
                                          irrecoverable secret fourth,
                                          server-side records last.)

21. Feeding capture — clean meal logged via photo
    User: [photographs Milo's evening kibble bowl, taps After]
    PetPal (form preview body):
              "Logged Milo's 6:42 PM meal — looks like kibble with what
               may be chicken."
    Saved as: wiki/milo/food/2026-05-30-evening-meal.md
                                          (hedged language per
                                          DECISIONS row 100 — "looks
                                          like" and "what may be"
                                          appear because the photo
                                          extractor is constrained to
                                          confident-only descriptions.
                                          Cite the entry path on
                                          confirmation so the user
                                          knows where the memory
                                          lives. After timestamp
                                          shown to the minute — meal
                                          times matter for Phase 10's
                                          mealPhaseCounts.)

22. Feeding capture — hazardous food, coral escalation fires
    User: [photographs a bunch of grapes on the kitchen counter, taps
           Before — "checking if Milo can have this"]
    PetPal opens with the escalation register (CLAUDE.md §10
    canonical copy, verbatim):
              "This may be hazardous — contact your vet or animal
               poison control now. PetPal is software, not a vet. I
               can help you write down what's happening so it's ready
               when you call."
    US locale: "Pet poison resources:
                 ASPCA Animal Poison Control: (888) 426-4435
                 Pet Poison Helpline: <number from
                 assets/hazards/escalation.yaml>"
    Other locale: "Contact your vet now."
    Then offers: "Want me to log this with a hazard flag so it's on
                  the record? [Save with flag]"
    Saved entry: wiki/milo/food/2026-05-30-grapes-check.md (carries a
    coral RedFlagBadge in the journal forever — see CLAUDE.md §10).
                                          (hazard escalation is the
                                          same coral register as
                                          symptom escalation —
                                          medical-attention register
                                          wins. Numbers come from
                                          assets/hazards/escalation
                                          .yaml never from the prompt
                                          per DECISIONS row 101.
                                          Offer to log AFTER the
                                          escalation copy fires, not
                                          before — the safety call
                                          comes first; the memory
                                          comes second.)
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
