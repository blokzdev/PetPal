import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../design/design.dart';

/// Phase 6 task 6.7 — subdued red-flag badge shared by chat, the photo
/// capture form preview, the photo timeline tile, and the photo entry
/// view. Mirrors the chat scrollback marker (see `_Bubble` in
/// `chat_screen.dart` line 402) — small `warningOctagon` icon + a
/// muted label.
///
/// CLAUDE.md §10 lock: the badge "persists forever — it's a historical
/// record, not a current-state indicator." So this widget is read-only
/// and never invalidates; the live preamble text on the chat surface
/// is where the urgency lives, and the saved-photo equivalent is the
/// extractor-found phrase that already appears in the caption / notable
/// objects body of the entry.
///
/// Two presentations:
///  - [RedFlagBadge.tile] — compact icon-only chip suitable for
///    overlaying a small grid cell (the photo timeline, 6.3).
///  - default — icon + label row, used in scrollback and on the form
///    preview / photo entry header.
class RedFlagBadge extends StatelessWidget {
  const RedFlagBadge({
    super.key,
    this.label = 'PetPal flagged this as urgent',
  }) : _tile = false;

  const RedFlagBadge.tile({super.key})
      : label = '',
        _tile = true;

  final String label;
  final bool _tile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // Phase 6.6 task 6.6.D.1 — wire coral (scheme.tertiary, the
    // system medical-attention register per DECISIONS row 64) to
    // the red-flag badge. The original `onSurfaceVariant` gray
    // looked incoherent next to card-level coral context (vet
    // EditorialCard left-border + MEDICAL NOTE callout). One
    // register wins; coral is medical-attention primary. The
    // 'subdued in stature' lock from CLAUDE.md §10 is preserved
    // by the small icon size + small label register — not by
    // muting the color.
    final coral = scheme.tertiary;
    if (_tile) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: scheme.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(
          PhosphorIconsRegular.warningOctagon,
          size: 16,
          color: coral,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          PhosphorIconsRegular.warningOctagon,
          size: 14,
          color: coral,
        ),
        const SizedBox(width: Spacing.xs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: coral,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}
