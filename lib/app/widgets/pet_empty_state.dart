import 'package:flutter/material.dart';

import '../design/design.dart';

/// Empty-state primitive: a soft circular badge holding a Material icon,
/// a heading, body copy, and an optional CTA slot. Used by every list
/// screen via task 5.6 (journal browser, reminders, care guides, chat).
///
/// Visual recipe (DECISIONS row 38 follow-up): the icon sits inside a
/// surfaceContainer-filled circle so the empty state reads as a
/// deliberately-designed surface, not "we forgot to render anything".
/// Heading uses titleLarge; body uses bodyMedium with onSurface@0.7 for
/// the muted teaching tone VOICE.md §1 calls for.
///
/// VOICE.md §1: copy is direct and warm, not apologetic. Per VOICE.md §5
/// the per-pet body copy on per-pet screens may interpolate the pet
/// name; global screens stay static. The component takes plain strings
/// — it is the screen's job to resolve interpolation before passing in.
class PetEmptyState extends StatelessWidget {
  const PetEmptyState({
    super.key,
    required this.icon,
    required this.heading,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String heading;
  final String body;

  /// Optional CTA — typically a [PetButton]. Leave null when the empty
  /// state is purely informational (chat with no messages, where the
  /// composer is the action).
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: Insets.l,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  color: scheme.surfaceContainerHigh,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: 44,
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: Spacing.l),
              Text(
                heading,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: Spacing.s),
              Text(
                body,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              if (action != null) ...[
                const SizedBox(height: Spacing.l),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}
