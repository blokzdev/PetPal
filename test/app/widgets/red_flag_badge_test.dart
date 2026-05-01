import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/red_flag_badge.dart';

/// Phase 6.6 task 6.6.D.1 — coral wiring regression guard for the
/// RedFlagBadge. The badge migrated from `onSurfaceVariant` (gray)
/// to `scheme.tertiary` (coral) so it lines up with card-level coral
/// context (vet EditorialCard left-border, MEDICAL NOTE callout) per
/// DECISIONS row 64. The 'subdued in stature' lock from CLAUDE.md
/// §10 is preserved by the small icon size + small label register —
/// not by muting the color.
void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: buildLightTheme(),
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('default RedFlagBadge — icon + label both render coral '
      '(scheme.tertiary)', (tester) async {
    await tester.pumpWidget(wrap(const RedFlagBadge()));
    await tester.pumpAndSettle();

    final coral = buildLightTheme().colorScheme.tertiary;

    final icon = tester.widget<Icon>(
      find.byIcon(PhosphorIconsRegular.warningOctagon),
    );
    expect(icon.color, coral, reason: 'warning icon must use coral');

    final labelText = tester.widget<Text>(
      find.text('PetPal flagged this as urgent'),
    );
    expect(
      labelText.style?.color,
      coral,
      reason: 'badge label must use coral',
    );
  });

  testWidgets('RedFlagBadge.tile — icon renders coral '
      '(scheme.tertiary)', (tester) async {
    await tester.pumpWidget(wrap(const RedFlagBadge.tile()));
    await tester.pumpAndSettle();

    final coral = buildLightTheme().colorScheme.tertiary;

    final icon = tester.widget<Icon>(
      find.byIcon(PhosphorIconsRegular.warningOctagon),
    );
    expect(icon.color, coral);
  });
}
