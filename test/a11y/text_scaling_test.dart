import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/design/design.dart';
import 'package:petpal/app/widgets/app_scaffold.dart';
import 'package:petpal/app/widgets/pet_button.dart';
import 'package:petpal/app/widgets/pet_card.dart';
import 'package:petpal/app/widgets/pet_empty_state.dart';

/// Phase 7 task H.2.b — text-scaling resilience.
///
/// Material 3 surfaces must survive Android's accessibility text-scale
/// at 1.5× and 2.0× without throwing `RenderFlex overflowed` or other
/// layout exceptions. The Play Console pre-launch scanner exercises
/// the app at multiple text scales; failures here surface as
/// launch-blocking signals there.
///
/// **Scope: shared chassis components, not full screens.** Pumping
/// every screen at three scales × two themes would require the
/// heavyweight Drift + scripted-LLM + Riverpod scaffolding from each
/// screen's existing test file — high overhead for what's mostly a
/// chassis-driven invariant. The Phase 5.6 design system constrains
/// most layout risk to these chassis components; if `AppScaffold` +
/// `PetButton` + `PetCard` + `PetEmptyState` survive 2.0× scaling,
/// the screens that compose them inherit that resilience.
///
/// Per-screen text-scaling sweeps live in TalkBack manual verification
/// (CLAUDE.md §14). The chat composer at 2.0× scale is the highest
/// remaining risk surface (composer + bubbles + scroll-to-bottom FAB
/// in 997 lines) — flagged in DECISIONS row 88's manual-verify list.
void main() {
  /// Pump [body] inside a MaterialApp + scaled `MediaQuery`. Uses
  /// `.copyWith` against the inherited MediaQueryData so size +
  /// padding + devicePixelRatio stay realistic; only `textScaler`
  /// is overridden. Builder pattern grabs the inherited context
  /// since MediaQueryData is not available at the top of pumpWidget.
  Future<void> pumpScaled(
    WidgetTester tester,
    Widget body, {
    required double scale,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildPetPalLightTheme(),
        home: Builder(
          builder: (ctx) => MediaQuery(
            data: MediaQuery.of(ctx).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: body,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final scale in const [1.0, 1.5, 2.0]) {
    group('AppScaffold @ ${scale}x text scale', () {
      testWidgets('basic constructor with title + body does not overflow',
          (tester) async {
        await pumpScaled(
          tester,
          const AppScaffold(
            title: 'Loki has been a very good boy this week',
            body: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.all(Spacing.m),
                child: Text(
                  'A long body paragraph that mimics a typical journal '
                  'entry — this needs to wrap rather than overflow when '
                  'the user has bumped their system font size up to the '
                  'maximum accessibility setting. The chat composer + '
                  'wiki entry detail screens are the highest-risk '
                  'surfaces; PetCard + PetEmptyState are the chassis.',
                ),
              ),
            ),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('hero variant survives long titles + tall hero',
          (tester) async {
        await pumpScaled(
          tester,
          AppScaffold.hero(
            title: 'Home',
            heroBuilder: (_) => const Center(
              child: Text(
                "Good morning! Here's what's on Loki's mind today",
                textAlign: TextAlign.center,
              ),
            ),
            body: const SizedBox(),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('PetButton @ ${scale}x text scale', () {
      testWidgets('long filled-button label does not overflow',
          (tester) async {
        await pumpScaled(
          tester,
          Scaffold(
            body: Center(
              child: PetButton(
                label: 'Save this entry to the journal',
                onPressed: () {},
              ),
            ),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });

      testWidgets('outlined + text variants with icons survive',
          (tester) async {
        await pumpScaled(
          tester,
          Scaffold(
            body: Column(
              children: [
                PetButton(
                  label: 'Edit profile',
                  icon: Icons.edit,
                  variant: PetButtonVariant.outlined,
                  onPressed: () {},
                ),
                PetButton(
                  label: 'Compare plans',
                  variant: PetButtonVariant.text,
                  onPressed: () {},
                ),
              ],
            ),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('PetCard @ ${scale}x text scale', () {
      testWidgets('card with multi-line body renders without overflow',
          (tester) async {
        await pumpScaled(
          tester,
          const Scaffold(
            body: Padding(
              padding: EdgeInsets.all(Spacing.m),
              child: PetCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Vet visit · 2026-04-12',
                      style: TextStyle(fontWeight: FontWeight.w600),
                    ),
                    SizedBox(height: Spacing.s),
                    Text(
                      'Annual checkup. Weight 14.3 kg (up from 14.0 in '
                      'January). Recommended switching to senior food '
                      'next year. Next vaccination due in October.',
                    ),
                  ],
                ),
              ),
            ),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    });

    group('PetEmptyState @ ${scale}x text scale', () {
      testWidgets('empty state with action button survives', (tester) async {
        await pumpScaled(
          tester,
          Scaffold(
            body: PetEmptyState(
              icon: Icons.notifications_off,
              heading: "No reminders yet for Loki",
              body: 'Add a reminder for the next flea treatment, vet '
                  'visit, or food refill — PetPal will surface it on '
                  'the day it matters.',
              action: PetButton(
                label: 'Add reminder',
                onPressed: () {},
              ),
            ),
          ),
          scale: scale,
        );
        expect(tester.takeException(), isNull);
      });
    });
  }
}
