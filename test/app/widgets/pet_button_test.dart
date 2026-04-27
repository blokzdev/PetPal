import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/pet_button.dart';

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
    // The Stack-based design keeps both the label and the spinner in the
    // widget tree at all times — the label always lays out (controlling
    // the button's width) and the two cross-fade via `AnimatedOpacity`
    // so toggling `isLoading` never causes a layout shift. These tests
    // assert opacity values, which is the visually-meaningful invariant.

    testWidgets('label visible / spinner invisible when isLoading=false',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(label: 'Save', onPressed: () {}),
      ));
      // Advance past Motion.short so AnimatedOpacity reaches its target.
      // Don't pumpAndSettle — the spinner's CircularProgressIndicator
      // animates continuously and pumpAndSettle would time out.
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Save'), findsOneWidget);
      expect(_spinnerOpacity(tester), 0);
      expect(_labelOpacity(tester), 1);
    });

    testWidgets('spinner visible / label invisible when isLoading=true',
        (tester) async {
      await tester.pumpWidget(_wrap(
        PetButton(label: 'Save', onPressed: () {}, isLoading: true),
      ));
      // Advance past Motion.short so AnimatedOpacity reaches its target.
      // Don't pumpAndSettle — the spinner's CircularProgressIndicator
      // animates continuously and pumpAndSettle would time out.
      await tester.pump(const Duration(milliseconds: 250));
      expect(_spinnerOpacity(tester), 1);
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
      // Advance past Motion.short so AnimatedOpacity reaches its target.
      // Don't pumpAndSettle — the spinner's CircularProgressIndicator
      // animates continuously and pumpAndSettle would time out.
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
      final widthLabelled = tester.getSize(find.byKey(key)).width;
      await tester.pumpWidget(_wrap(
        PetButton(
          key: key,
          label: 'Save a memory about Loki',
          onPressed: () {},
          isLoading: true,
        ),
      ));
      // Advance past Motion.short so AnimatedOpacity reaches its target.
      // Don't pumpAndSettle — the spinner's CircularProgressIndicator
      // animates continuously and pumpAndSettle would time out.
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
        icon: Icons.add,
        onPressed: () {},
      ),
    ));
    expect(find.byIcon(Icons.add), findsOneWidget);
    expect(find.text('Add'), findsOneWidget);
  });
}

/// Returns the opacity of the AnimatedOpacity that wraps the spinner
/// in PetButton's content stack.
double _spinnerOpacity(WidgetTester tester) {
  final widget = tester.widget<AnimatedOpacity>(
    find
        .ancestor(
          of: find.byType(CircularProgressIndicator),
          matching: find.byType(AnimatedOpacity),
        )
        .first,
  );
  return widget.opacity;
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
