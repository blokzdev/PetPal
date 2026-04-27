import 'package:flutter/material.dart';

import '../design/design.dart';

/// Lightweight section header for grouping related rows on Settings,
/// Profile editor, and similar list-of-groups surfaces.
///
/// Uses titleSmall (Inter Medium 14) — visually distinct from the
/// content rows (bodyMedium 14) without competing with the AppBar
/// title. An optional trailing widget slot accommodates a section-
/// level action (e.g. an "Edit" text button).
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
              title,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
                letterSpacing: 0.6,
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}
