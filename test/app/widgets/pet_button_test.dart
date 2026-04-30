import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_button.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: buildLightTheme(),
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  group('PetButton variants', () {
    testWidgets('filled variant renders a FilledButton', (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(label: 'Save', onPressed: () {}),
      ));
      expect(find.byType(FilledButton), findsOneWidget);
      expect(find.text('Save'), findsOneWidget);
    });

    testWidgets('outlined variant renders an OutlinedButton', (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(
          label: 'Cancel',
          variant: PetButtonVariant.outlined,
          onPressed: () {},
        ),
      ));
      expect(find.byType(OutlinedButton), findsOneWidget);
    });

    testWidgets('text variant renders a TextButton', (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(
          label: 'Skip',
          variant: PetButtonVariant.text,
          onPressed: () {},
        ),
      ));
      expect(find.byType(TextButton), findsOneWidget);
    });
  });

  group('PetButton loading state', () {
    // Design (post-task-5.7 follow-up to 5.2): the spinner is
    // conditionally mounted only when isLoading=true. The label
    // always lays out via opacity-only fade so the button width
    // doesn't change between states — preserving the no-layout-
    // shift guarantee — but the CircularProgressIndicator's
    // animation no longer runs when not in use, which keeps
    // `pumpAndSettle` working in widget tests for any surface that
    // includes a PetButton.

    testWidgets('label visible / spinner not mounted when isLoading=false',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(label: 'Save', onPressed: () {}),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Save'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_labelOpacity(tester), 1);
    });

    testWidgets('spinner mounted / label invisible when isLoading=true',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(label: 'Save', onPressed: () {}, isLoading: true),
      ));
      // Don't pumpAndSettle — the spinner's CircularProgressIndicator
      // animates continuously while loading, which is intentional and
      // expected during an in-flight operation.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(_labelOpacity(tester), 0);
    });

    testWidgets('isLoading=true disables the onPressed callback',
        (tester) async {
      var pressed = 0;
      await tester.pumpWidget(_wrap(
        PetButton(
          label: 'Save',
          onPressed: () => pressed++,
          isLoading: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 250));
      // The button is rendered but its onPressed should be null while
      // loading; tapping should not increment.
      await tester.tap(find.byType(FilledButton), warnIfMissed: false);
      expect(pressed, 0);
    });

    testWidgets('width is preserved when toggling loading state',
        (tester) async {
      final key = GlobalKey();
      await tester.pumpWidget(_wrap(
        PetButton(
          key: key,
          label: 'Save a memory about Loki',
          onPressed: () {},
        ),
      ));
      await tester.pumpAndSettle();
      final widthLabelled = tester.getSize(find.byKey(key)).width;
      await tester.pumpWidget(_wrap(
        PetButton(
          key: key,
          label: 'Save a memory about Loki',
          onPressed: () {},
          isLoading: true,
        ),
      ));
      await tester.pump(const Duration(milliseconds: 250));
      final widthLoading = tester.getSize(find.byKey(key)).width;
      expect(widthLoading, widthLabelled,
          reason: 'loading state must not shrink the button');
    });
  });

  testWidgets('icon slot renders a leading icon', (tester) async {
    await tester.pumpWidget(_wrap(
      PetButton(
        label: 'Add',
        icon: PhosphorIconsRegular.plus,
        onPressed: () {},
      ),
    ));
    expect(find.byIcon(PhosphorIconsRegular.plus), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });
}

/// Returns the opacity of the AnimatedOpacity that wraps the label.
double _labelOpacity(WidgetTester tester) {
  // The label-side AnimatedOpacity is the one whose direct child is an
  // IgnorePointer (the spinner side has no IgnorePointer wrapper).
  final widget = tester.widget<AnimatedOpacity>(
    find
        .ancestor(
          of: find.byType(IgnorePointer),
          matching: find.byType(AnimatedOpacity),
        )
        .first,
  );
  return widget.opacity;
}
