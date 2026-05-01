import 'package:flutter/material.dart';

import '../design/design.dart';

/// Phase 6.6 task 6.6.B.1 — editorial card primitive.
///
/// Productizes the serif-title-card pattern that lived ad-hoc in
/// `_DigestCard` (journal browser weekly-summary tile). Group B.2–B.4
/// consume this primitive across the journal browser, the Home
/// "Recent memories" section, and the weekly-summary HIGHLIGHTS
/// section.
///
/// **Locked composition** (per DECISIONS rows 58 + 64):
///
///   - Optional **leading thumbnail** — square, `Radii.s` (12 dp)
///     clip. Used by photo memories. The card layout swaps from
///     "thumbnail + column" to "column only" automatically when
///     `thumbnail` is null.
///   - Optional **kicker** — small-caps metadata above the title
///     (e.g. "FOOD · APR 25", "WEEKLY SUMMARY", "PHOTO"). Renders in
///     `labelSmall` weight 600, `letterSpacing 1.4`, in
///     `onSurfaceVariant` by default; in `scheme.tertiary` (coral)
///     when the card is flagged.
///   - Required **title** — serif, `JournalText.entryTitle` by
///     default. Weekly summary callers pass `titleStyle:
///     JournalText.weeklySummaryTitle(...)` for the larger
///     "this is a cumulative artifact" register.
///   - Optional **body** — truncated to 3 lines via `maxLines` +
///     `overflow: TextOverflow.ellipsis`. Reads as a "preview line"
///     on the journal browser.
///   - Optional **trailing widget** — small slot to the right of the
///     metadata column (badges, time ago, etc.).
///   - `flagged: true` adds a **4 dp coral left-border** accent and
///     tints the kicker coral. The card-level coral context is the
///     medical-attention primary per DECISIONS row 64; `RedFlagBadge`
///     can still be passed in `trailing:` if the screen wants the
///     historical marker AND the card-level treatment.
///
/// `onTap` makes the card tappable via an InkWell that clips inside
/// the rounded corners; null `onTap` renders a non-tappable card
/// (used when the editorial card is illustrative — e.g. embedded in
/// a HIGHLIGHTS section that doesn't deep-link).
class EditorialCard extends StatelessWidget {
  const EditorialCard({
    super.key,
    required this.title,
    this.kicker,
    this.body,
    this.thumbnail,
    this.trailing,
    this.titleStyle,
    this.flagged = false,
    this.onTap,
  });

  final String title;
  final String? kicker;
  final String? body;
  final Widget? thumbnail;
  final Widget? trailing;
  final TextStyle? titleStyle;
  final bool flagged;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final kickerColor = flagged ? scheme.tertiary : scheme.onSurfaceVariant;
    final resolvedTitleStyle =
        titleStyle ?? JournalText.entryTitle(color: scheme.onSurface);

    final card = Material(
      type: MaterialType.card,
      color: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: Corners.m),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Coral left-border accent on flagged cards (DECISIONS
              // row 64 — medical-context primary). 4 dp wide; spans
              // the card's full height via IntrinsicHeight.
              if (flagged)
                Container(
                  width: 4,
                  color: scheme.tertiary,
                ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(
                    flagged ? Spacing.m : Spacing.l,
                    Spacing.m,
                    Spacing.m,
                    Spacing.m,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (thumbnail != null) ...[
                        ClipRRect(
                          borderRadius: Corners.s,
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: thumbnail,
                          ),
                        ),
                        const SizedBox(width: Spacing.m),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (kicker != null) ...[
                              Text(
                                kicker!,
                                style: textTheme.labelSmall?.copyWith(
                                  color: kickerColor,
                                  letterSpacing: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: Spacing.xs),
                            ],
                            Text(
                              title,
                              style: resolvedTitleStyle,
                            ),
                            if (body != null && body!.isNotEmpty) ...[
                              const SizedBox(height: Spacing.s),
                              Text(
                                body!,
                                style: textTheme.bodyMedium?.copyWith(
                                  color: scheme.onSurface
                                      .withValues(alpha: 0.75),
                                ),
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (trailing != null) ...[
                        const SizedBox(width: Spacing.s),
                        trailing!,
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Spacing.m,
        vertical: Spacing.s,
      ),
      child: card,
    );
  }
}
