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
    if (_tile) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          // Subdued — matches the scrollback marker treatment, not a
          // ripe-red alert. The intent is "leave a historical mark",
          // not "draw attention every time the user scrolls past".
          color: scheme.surface.withValues(alpha: 0.85),
          shape: BoxShape.circle,
        ),
        child: Icon(
          PhosphorIconsRegular.warningOctagon,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          PhosphorIconsRegular.warningOctagon,
          size: 14,
          color: scheme.onSurfaceVariant,
        ),
        const SizedBox(width: Spacing.xs),
        Flexible(
          child: Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  fontWeight: FontWeight.w500,
                ),
          ),
        ),
      ],
    );
  }
}
