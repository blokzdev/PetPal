import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/screens/chat_screen.dart';
import 'package:petpal/app/screens/reminders_screen.dart';
import 'package:petpal/app/screens/skill_browser_screen.dart';
import 'package:petpal/app/screens/wiki_browser_screen.dart';
import 'package:petpal/app/widgets/pet_empty_state.dart';

/// Empty-state design invariants — task 5.7.
///
/// Each of the four empty states landed under a user-locked design
/// pick. These tests pin the picked direction via the unique copy
/// + structural choices that distinguish it from the alternatives,
/// so a future "let's just rewrite the empty state" change has to
/// either consciously update this file or stay within the locked
/// direction.
///
/// These don't replicate the existing screen-level integration tests
/// (those cover navigation + AsyncValue resolution); they're pure
/// per-component renders with the minimum context to draw the empty
/// state.
void main() {
  Widget wrap(Widget child) => ProviderScope(
        child: MaterialApp(
          home: Scaffold(body: child),
        ),
      );

  group('journal empty state — Stitch register (per-pet)', () {
    testWidgets('renders pet-name-first present-fact + warm reframe',
        (tester) async {
      await tester.pumpWidget(wrap(
        const _JournalEmptyHarness(petName: 'Loki'),
      ));
      await tester.pumpAndSettle();

      // Phase 6.6 task 6.6.C.5 — Stitch register: pet-name-first
      // possessive + present-tense state-of-the-surface, followed
      // by a warm forward-action reframe (the journal builds itself).
      expect(
        find.text("Loki's journal hasn't begun yet."),
        findsOneWidget,
      );
      // Body teaches by enumerating concretes (vet visits, weight,
      // small wins) and frames the build as something the user
      // helps PetPal do.
      expect(
        find.textContaining('the journal builds itself here'),
        findsOneWidget,
      );
      // CTA opens chat (not a generic "Add memory" or no-CTA).
      expect(find.widgetWithText(FilledButton, 'Open chat'), findsOneWidget);
    });

    testWidgets('falls back gracefully when no pet name is available',
        (tester) async {
      await tester.pumpWidget(wrap(
        const _JournalEmptyHarness(petName: null),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text("Your pet's journal hasn't begun yet."),
        findsOneWidget,
      );
      expect(
        find.textContaining('the journal builds itself here'),
        findsOneWidget,
      );
    });
  });

  group('reminders empty state — Stitch register (reference shape)', () {
    testWidgets('renders the locked Stitch reference register',
        (tester) async {
      var addPressed = 0;
      await tester.pumpWidget(wrap(
        RemindersEmptyForTesting(
          petName: 'Loki',
          onAdd: () => addPressed++,
        ),
      ));
      await tester.pumpAndSettle();

      // Phase 6.6 task 6.6.C.5 — Stitch reference register:
      // "$petName's schedule is clear. Enjoy the quiet moments
      // together." Heading interpolates name (VOICE.md §5);
      // body opens with the warm reframe.
      expect(find.text("Loki's schedule is clear."), findsOneWidget);
      expect(
        find.textContaining('Enjoy the quiet moments together.'),
        findsOneWidget,
      );
      // Category teaching (heartworm / flea / vaccines) carries
      // forward inside the body so the empty state still teaches
      // what kinds of reminders are useful.
      expect(
        find.textContaining('heartworm, flea treatment, vaccines'),
        findsOneWidget,
      );
      // CTA mirrors the FAB so the empty state has its own primary
      // affordance.
      expect(find.widgetWithText(FilledButton, 'Add reminder'), findsOneWidget);

      await tester.tap(
        find.widgetWithText(FilledButton, 'Add reminder'),
        warnIfMissed: false,
      );
      expect(addPressed, 1);
    });
  });

  group('care guides empty state — Stitch register (global)', () {
    testWidgets('reads as static (no pet name in heading or body)',
        (tester) async {
      await tester.pumpWidget(wrap(const CareGuidesEmptyForTesting()));
      await tester.pumpAndSettle();

      // Phase 6.6 task 6.6.C.5 — global variant of Stitch register:
      // present-fact + how-it-works reframe, no name interpolation
      // (VOICE.md §5 — care guides browser is cross-pet).
      expect(find.text('Care guides are quiet for now.'), findsOneWidget);
      // Body explains how care guides activate during chat — sets
      // expectations for the user.
      expect(
        find.textContaining('activate during chat'),
        findsOneWidget,
      );
      // Global screen → no CTA (the user can't author a guide in v1;
      // waiting for more bundled packs is the only legitimate path).
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('chat empty state — suggested prompts (tappable chips)', () {
    testWidgets('three name-interpolated prompts render as ActionChips',
        (tester) async {
      await tester.pumpWidget(wrap(
        EmptyChatForTesting(
          petName: 'Loki',
          onSuggest: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Chat with PetPal about Loki.'), findsOneWidget);
      // Three chips, all interpolating Loki's name (third chip uses
      // the name in a question form).
      expect(find.byType(ActionChip), findsNWidgets(3));
      expect(find.text('Loki had vaccines today'), findsOneWidget);
      expect(
        find.text('Loki has been scratching since yesterday'),
        findsOneWidget,
      );
      expect(find.text('What food works for Loki?'), findsOneWidget);
    });

    testWidgets('tapping a chip invokes onSuggest with the prompt text',
        (tester) async {
      String? lastSuggestion;
      await tester.pumpWidget(wrap(
        EmptyChatForTesting(
          petName: 'Loki',
          onSuggest: (prompt) => lastSuggestion = prompt,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Loki had vaccines today'));
      await tester.pumpAndSettle();
      expect(lastSuggestion, 'Loki had vaccines today');
    });

    testWidgets('falls back to species-agnostic prompts when no pet is named',
        (tester) async {
      await tester.pumpWidget(wrap(
        EmptyChatForTesting(
          petName: 'PetPal',
          onSuggest: (_) {},
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text('Chat with PetPal about your pet.'),
        findsOneWidget,
      );
      // Generic prompts — no Loki, no species assumptions.
      expect(find.text('My pet had vaccines today'), findsOneWidget);
      expect(find.text('What food should I avoid?'), findsOneWidget);
    });
  });

  group('PetEmptyState scroll-safety (regression for chat chip wrap)', () {
    testWidgets(
        'tall content on a short viewport does not RenderFlex-overflow',
        (tester) async {
      // Force a short viewport — without the LayoutBuilder + scroll
      // pattern in PetEmptyState, the chat empty state with three
      // chips overflows by ~28dp here.
      tester.view.physicalSize = const Size(400, 350);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(wrap(
        EmptyChatForTesting(petName: 'Loki', onSuggest: (_) {}),
      ));
      await tester.pumpAndSettle();

      // Heading still renders; SingleChildScrollView lets the rest
      // scroll into view. No "RenderFlex overflowed" exception.
      expect(find.text('Chat with PetPal about Loki.'), findsOneWidget);
      expect(find.byType(PetEmptyState), findsOneWidget);
    });
  });
}

// ---------------------------------------------------------------------------
// Test harnesses — minimal wrappers that pump just the empty-state widget
// without dragging in the screen's full Riverpod stack. The screens'
// integration tests cover the full path.
// ---------------------------------------------------------------------------

/// Wraps the journal empty state so we can pump it without spinning up
/// the wiki repository providers. Mirrors the production widget's
/// structure exactly via the same source file's exported helper.
class _JournalEmptyHarness extends StatelessWidget {
  const _JournalEmptyHarness({required this.petName});
  final String? petName;

  @override
  Widget build(BuildContext context) {
    return JournalEmptyForTesting(petName: petName);
  }
}
