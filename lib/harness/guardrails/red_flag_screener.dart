import 'red_flags.dart';

/// Result of a red-flag screen. Currently single-category (the first
/// match in [redFlagPatterns] iteration order); a future revision could
/// return all matches if the UI ever wants to display multiple
/// categories on one bubble.
class RedFlagMatch {
  const RedFlagMatch({required this.category});
  final RedFlagPattern category;
}

/// Deterministic regex/keyword screener over chat-turn input. Wraps
/// [redFlagPatterns] with explicit construction so tests can override
/// the table.
///
/// Per CLAUDE.md §10 and DECISIONS row 29 the screener is **chat input
/// only** — wiki-entry text the user types directly is never screened
/// (those are legitimately retrospective and would produce false
/// positives at exactly the wrong moment). Callers must enforce scope.
class RedFlagScreener {
  RedFlagScreener({List<RedFlagPattern>? patterns})
      : _patterns = patterns ?? redFlagPatterns;

  final List<RedFlagPattern> _patterns;

  /// Returns the first matching category in canonical iteration order,
  /// or null if no pattern matches. Empty/whitespace-only input never
  /// matches.
  RedFlagMatch? screen(String input) {
    if (input.trim().isEmpty) return null;
    for (final pattern in _patterns) {
      if (pattern.matches(input)) {
        return RedFlagMatch(category: pattern);
      }
    }
    return null;
  }
}

/// One-shot system-prompt directive injected by [SessionBuilder] when
/// the screener flags a turn. The escalation copy itself is locked
/// verbatim in VOICE.md §6 example 10 / CLAUDE.md §10 — the model is
/// instructed to open with that exact text before any other content.
String escalationDirective(RedFlagMatch match) {
  return '''
# Escalation directive (this turn only)

This turn was flagged as urgent (category: ${match.category.id} — ${match.category.aiSummary}).

You MUST open your response with this exact preamble before any other content:

"This sounds urgent — please call your vet or an emergency animal hospital now. PetPal is software, not a vet. I can help you write down what's happening so it's ready when you call."

After the preamble, offer to log what is happening as a journal entry. Do not diagnose. Do not delay the preamble.''';
}
