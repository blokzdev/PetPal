import 'package:flutter/material.dart';

import '../design/design.dart';

/// Lightweight section header for grouping related rows on Settings,
/// Profile editor, and similar list-of-groups surfaces.
///
/// Phase 6.6 task 6.6.B.0 — small-caps + sage-tint refresh per
/// DECISIONS row 58. The title renders **uppercased** with
/// `letterSpacing 1.2` and `weight 600` against `scheme.primary`
/// (sage) at alpha 0.85. Sage carries the brand register so section
/// chrome inherits the same calm-deliberate signal the home greeting
/// hero gradient uses; small caps signal "this is a section, not
/// content."
///
/// Section headers earn the sage tint because they're the navigation-
/// flavoured chrome of a long-form surface; the closely-related
/// editorial-card **kicker** (inside `EditorialCard`) stays on
/// `onSurfaceVariant` because it's metadata-flavoured, not section
/// chrome. Two registers, one design system.
///
/// Callers pass the title in any case ("About Loki", "Settings"); the
/// widget renders uppercase. An optional trailing widget slot
/// accommodates a section-level action (e.g. an "Edit" text button
/// or a chevron when the header is tap-targeted).
class PetSectionHeader extends StatelessWidget {
  const PetSectionHeader({
    super.key,
    required this.title,
    this.trailing,
  });

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(
        left: Spacing.m,
        right: Spacing.m,
        top: Spacing.m,
        bottom: Spacing.s,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary.withValues(alpha: 0.85),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.2,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
