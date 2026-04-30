import 'red_flags.dart';

/// Where a [RedFlagMatch] originated. The chat preamble (CLAUDE.md §10
/// canonical escalation copy) reads identically regardless of source —
/// the model is told to escalate either way — but the post-hoc UI
/// badge can differentiate so a photo-only flag reads "PetPal noticed
/// something in this photo" vs the chat "you wrote something urgent".
enum RedFlagSource {
  /// Match came from the chat-turn user input (Phase 4 baseline).
  chat,

  /// Match came from the model-generated vision findings on a saved
  /// photo memory or a chat-attached image (Phase 6 task 6.7). The
  /// joined `freeform_caption + notable_objects` is the screened
  /// payload — `setting`/`activity` enums are too narrow to false-
  /// positive on, `demeanor` is too soft to true-positive on.
  vision,
}

/// Result of a red-flag screen. Currently single-category (the first
/// match in [redFlagPatterns] iteration order); a future revision could
/// return all matches if the UI ever wants to display multiple
/// categories on one bubble.
class RedFlagMatch {
  const RedFlagMatch({
    required this.category,
    this.source = RedFlagSource.chat,
  });
  final RedFlagPattern category;
  final RedFlagSource source;
}

/// Deterministic regex/keyword screener over chat-turn input + (Phase 6
/// task 6.7) photo-extractor vision findings. Wraps [redFlagPatterns]
/// with explicit construction so tests can override the table.
///
/// **Scope (CLAUDE.md §10, DECISIONS row 29 + 6.7's expansion).** The
/// screener runs on:
///   - chat-turn user input (the original Phase 4 scope), and
///   - the structured vision findings produced by the photo extractor
///     (Phase 6) — specifically `freeform_caption + notable_objects`,
///     because those are the only fields the extractor emits where a
///     red-flag phrase would land in natural English.
///
/// User-typed wiki-entry text is **still never screened**. Wiki entries
/// are legitimately retrospective; flagging "I called the vet at 3am
/// because Loki had a seizure" while the user is calmly journaling
/// would produce false positives at exactly the wrong moment.
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
        // source defaults to RedFlagSource.chat (this method is the
        // chat-only path).
        return RedFlagMatch(category: pattern);
      }
    }
    return null;
  }

  /// Phase 6 task 6.7 — chat-or-vision screen. Pass either or both of
  /// [chatInput] (the user's chat turn) and [visionExtracted] (the
  /// extractor's `freeform_caption + notable_objects` joined with
  /// newlines). Chat takes priority: if both flag, the chat match is
  /// returned (a flagged turn is the more decisive signal — the user
  /// actively typed the urgent phrase). Returns null when neither
  /// flags.
  RedFlagMatch? screenWithVision({
    String? chatInput,
    String? visionExtracted,
  }) {
    if (chatInput != null) {
      final chatMatch = screen(chatInput);
      if (chatMatch != null) return chatMatch;
    }
    if (visionExtracted != null && visionExtracted.trim().isNotEmpty) {
      for (final pattern in _patterns) {
        if (pattern.matches(visionExtracted)) {
          return RedFlagMatch(
            category: pattern,
            source: RedFlagSource.vision,
          );
        }
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
