/// Red-flag pattern table — the deterministic source of truth for
/// medical-safety pre-screening (CLAUDE.md §10, DECISIONS row 29).
///
/// **Tradeoff direction (locked).** Bias toward false positives. A
/// nudged-but-not-urgent user loses thirty seconds; a missed real
/// emergency could lose the pet. Matches are case-insensitive,
/// word-bounded, and never gate the LLM call — they only prepend a
/// directive to the system prompt and surface a UI badge.
///
/// **Coverage rule.** Every category ships with ≥30 positive phrasings
/// and ≥20 negative phrasings in
/// `test/harness/guardrails/red_flags_fixture.dart` (task 4.11). New
/// patterns require new fixtures in the same commit.
library;

/// Severity is currently single-valued. Kept as an enum so future
/// categories (e.g. `informational` for "consider scheduling a vet
/// visit") can be added without breaking switches over severity.
enum RedFlagSeverity { urgent }

/// A single red-flag category. Patterns may be a flat OR list
/// ([triggers], any match wins) or a multi-symptom AND group ([all],
/// every regex must match the same input). Lethargy-with-anorexia is
/// the canonical AND case — neither symptom alone is urgent, both
/// together warrant escalation.
class RedFlagPattern {
  const RedFlagPattern({
    required this.id,
    required this.severity,
    required this.aiSummary,
    this.triggers = const [],
    this.all,
  });

  /// Stable identifier surfaced to the user via the chat-screen badge
  /// and used in DECISIONS row 29's audit trail. Snake-case ASCII;
  /// never localised.
  final String id;

  final RedFlagSeverity severity;

  /// Flat OR list. Any match flags the category. Used when [all] is
  /// null. May be empty if [all] is provided.
  final List<RegExp> triggers;

  /// Multi-symptom AND group. Non-null iff every regex must match the
  /// same input. When non-null, [triggers] is ignored.
  final List<RegExp>? all;

  /// One-line clinical-neutral phrase used in the system-prompt
  /// directive ("This turn was flagged as urgent — `aiSummary`"). Not
  /// user-facing.
  final String aiSummary;

  bool matches(String input) {
    final all = this.all;
    if (all != null) {
      return all.every((r) => r.hasMatch(input));
    }
    return triggers.any((r) => r.hasMatch(input));
  }
}

/// Case-insensitive regex shorthand. Word boundaries are written into
/// each pattern explicitly because alternations and lookarounds make
/// implicit boundaries unreliable.
RegExp _ci(String pattern) => RegExp(pattern, caseSensitive: false);

/// The eleven canonical red-flag categories from CLAUDE.md §10. Order
/// is the canonical iteration order — the screener returns the first
/// match. If two categories overlap (e.g. "vomiting blood" matches
/// both `blood_in_vomit` and `repeat_vomit` if the user wrote
/// "vomiting blood several times"), the order here decides which
/// wins. Higher-specificity categories come first.
final List<RedFlagPattern> redFlagPatterns = [
  RedFlagPattern(
    id: 'blood_in_stool',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Blood reported in stool',
    triggers: [
      _ci(r'\bblood\w*\s+in\s+(?:his\s+|her\s+|the\s+|a\s+)?(stool|poop|feces|faeces|diarrhea|diarrhoea)\b'),
      _ci(r'\bbloody\s+(stool|poop|diarrhe[ae])\b'),
      _ci(r'\b(red|dark|black|bloody|tarry)\s+(stool|poop|feces|faeces|diarrhea|diarrhoea)\b'),
      _ci(r'\b(stool|poop|feces|faeces|diarrhea|diarrhoea)\s+(is|looks|seems|appears)\s+(red|dark|black|bloody|tarry)\b'),
      _ci(r'\bmelena\b'),
    ],
  ),
  RedFlagPattern(
    id: 'blood_in_vomit',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Blood reported in vomit',
    triggers: [
      _ci(r'\bblood\w*\s+in\s+(?:his\s+|her\s+|the\s+|a\s+)?(vomit|throw[- ]?up|puke)\b'),
      _ci(r'\bvomit\w*\s+blood\b'),
      _ci(r'\b(throwing|threw|throw)\s+up\s+blood\b'),
      _ci(r'\bcoughing\s+up\s+blood\b'),
      _ci(r'\bhematemesis\b'),
    ],
  ),
  RedFlagPattern(
    id: 'repeat_vomit',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Repeated vomiting reported',
    triggers: [
      _ci(r'\bvomit\w*\s+(\d+\s+times?|several\s+times?|many\s+times?|multiple\s+times?|repeatedly|all\s+(day|morning|night|afternoon))\b'),
      _ci(r'\b(throwing|threw)\s+up\s+(\d+\s+times?|several\s+times?|many\s+times?|multiple\s+times?|repeatedly|all\s+(day|morning|night|afternoon))\b'),
      _ci(r'\bkeeps?\s+(throwing\s+up|vomiting)\b'),
      _ci(r"\b(can'?t|cannot)\s+stop\s+(throwing\s+up|vomiting)\b"),
    ],
  ),
  RedFlagPattern(
    id: 'seizure',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Seizure activity reported',
    triggers: [
      _ci(r'\bseizure(s|d)?\b'),
      _ci(r'\bseizing\b'),
      _ci(r'\bconvuls(ion|ions|ing|ed)\b'),
      _ci(r'\bhad\s+a\s+fit\b'),
      _ci(r'\bepileptic\s+(episode|fit|attack)\b'),
    ],
  ),
  RedFlagPattern(
    id: 'bloat',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Distended/bloated abdomen reported (potential GDV in dogs)',
    triggers: [
      _ci(r'\b(bloated|distended|swollen|hard|tight)\s+(belly|abdomen|stomach|tummy)\b'),
      _ci(r'\b(belly|abdomen|stomach|tummy)\s+(is|looks|seems|feels)\s+(bloated|distended|swollen|hard|tight)\b'),
      _ci(r'\bGDV\b'),
      _ci(r'\bgastric\s+dilatation\b'),
    ],
  ),
  RedFlagPattern(
    id: 'pale_gums',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Pale or abnormally coloured gums reported',
    triggers: [
      _ci(r'\b(pale|white|whitish|grey|gray|blue|bluish|yellow|yellowish)\s+gums\b'),
      _ci(r'\bgums\s+(are|look|seem)\s+(pale|white|whitish|grey|gray|blue|bluish|yellow|yellowish)\b'),
    ],
  ),
  RedFlagPattern(
    id: 'toxin_ingestion',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Possible toxin or foreign-body ingestion reported',
    triggers: [
      // Foods + plants toxic to dogs/cats; common sweeteners; common
      // human meds; recreational drugs; foreign bodies that warrant
      // escalation.
      _ci(r'\b(ate|ingested|swallowed|got\s+into|ate\s+some|ate\s+a)\s+(chocolate|cocoa|grape\w*|raisin\w*|onion\w*|garlic\w*|chive\w*|leek\w*|xylitol|gum|sugar[- ]?free|sweetener|lily|lilies|tulip\w*|daffodil\w*|antifreeze|rat\s+poison|rodenticide|mouse\s+poison|slug\s+pellets|tylenol|advil|ibuprofen|acetaminophen|paracetamol|aspirin|naproxen|marijuana|weed|cannabis|edible\w*|mushroom\w*|toadstool\w*)\b'),
      _ci(r'\bdrank\s+(antifreeze|coolant|cleaner|bleach|detergent|pool\s+chemicals?)\b'),
      _ci(r'\b(swallowed|ate)\s+(a\s+)?(string|sock|coin|battery|button\s+battery|magnet\w*|hair\s*tie|hairband|cord|ribbon|toy|sponge|fishhook)\b'),
      _ci(r'\bgot\s+into\s+(the\s+)?(trash|garbage|bin)\b'),
      _ci(r'\bpoisoned?\b'),
    ],
  ),
  RedFlagPattern(
    id: 'dyspnea',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Laboured or distressed breathing reported',
    triggers: [
      _ci(r'\blabou?red\s+breathing\b'),
      _ci(r'\b(trouble|difficulty|hard|struggling)\s+(to\s+)?breath(e|ing)\b'),
      _ci(r"\b(can'?t|cannot)\s+breathe\b"),
      _ci(r'\bgasping\s+(for\s+)?(air|breath)\b'),
      _ci(r'\bopen[- ]?mouth\s+breathing\b'),
      _ci(r'\bcyanot(ic|ic|ic-?looking)\b'),
      _ci(r'\b(blue|purple)\s+tongue\b'),
      _ci(r'\bwheez(ing|y)\s+(badly|severely|hard)\b'),
    ],
  ),
  RedFlagPattern(
    id: 'collapse',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Collapse or loss of consciousness reported',
    triggers: [
      _ci(r'\bcollapse(d|s)?\b'),
      _ci(r'\bpassed\s+out\b'),
      _ci(r'\blost\s+consciousness\b'),
      _ci(r'\b(unconscious|non[- ]?responsive|unresponsive)\b'),
      _ci(r'\bfainted?\b'),
      _ci(r"\bwon'?t\s+(wake\s+up|come\s+to|respond)\b"),
    ],
  ),
  RedFlagPattern(
    id: 'trauma_fracture',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Major trauma or suspected fracture reported',
    triggers: [
      _ci(r'\bbroken\s+(leg|bone|paw|tail|jaw|rib|hip|back)\b'),
      _ci(r'\bfractur(ed|e|es|ing)\b'),
      _ci(r"\bwon'?t\s+put\s+weight\s+on\b"),
      _ci(r'\b(hit|struck|run\s+over)\s+by\s+(a\s+)?(car|truck|vehicle|bike|bicycle)\b'),
      _ci(r'\bhit\s+by\s+a?\s*car\b'),
      _ci(r'\bfell\s+(from|off|down)\s+'),
      _ci(r'\battacked\s+by\s+(a\s+)?(dog|coyote|wild\s+animal)\b'),
      _ci(r'\bdeep\s+(wound|cut|laceration|gash)\b'),
      _ci(r"\bwon[’']t\s+stop\s+bleeding\b"),
    ],
  ),
  RedFlagPattern(
    id: 'lethargy_anorexia',
    severity: RedFlagSeverity.urgent,
    aiSummary: 'Lethargy and loss of appetite reported together',
    all: [
      _ci(r"\b(lethargic|listless|exhausted|very\s+tired|extremely\s+tired|won'?t\s+(get\s+up|move|stand|come\s+out))\b"),
      _ci(r"\b(won'?t\s+eat|not\s+eating|no\s+appetite|refus(ing|es)\s+food|anorexi(a|c)|hasn'?t\s+eaten)\b"),
    ],
  ),
];
