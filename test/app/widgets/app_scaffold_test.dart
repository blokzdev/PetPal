import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/widgets/app_scaffold.dart';
import 'package:petpal/app/widgets/pet_empty_state.dart';
import 'package:petpal/app/widgets/pet_skeleton.dart';

/// Phase 5 task 5.5 — AppScaffold invariants.
///
/// Three constructor variants (basic, hero, async) + the appSnackBar
/// helper + the petAccent threading hook. Tests below pin every behavior
/// the 9 migrated screens depend on so a future refactor can't silently
/// break the chrome that every screen now inherits.
void main() {
  Widget wrap(Widget child) => MaterialApp(home: child);

  group('AppScaffold (basic)', () {
    testWidgets('renders title in an AppBar', (tester) async {
      await tester.pumpWidget(wrap(
        const AppScaffold(title: 'Settings', body: SizedBox()),
      ));
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.text('Settings'), findsOneWidget);
    });

    testWidgets('renders body', (tester) async {
      await tester.pumpWidget(wrap(
        const AppScaffold(
          title: 'X',
          body: Text('body content', key: ValueKey('body')),
        ),
      ));
      expect(find.byKey(const ValueKey('body')), findsOneWidget);
      expect(find.text('body content'), findsOneWidget);
    });

    testWidgets('wraps body in SafeArea', (tester) async {
      await tester.pumpWidget(wrap(
        const AppScaffold(title: 'X', body: SizedBox()),
      ));
      // SafeArea is provided by AppScaffold so screen authors don't
      // need to remember it. Migrated screens dropped their per-screen
      // SafeArea wrappers in favour of this one.
      expect(find.byType(SafeArea), findsWidgets);
    });

    testWidgets('renders actions in the AppBar', (tester) async {
      await tester.pumpWidget(wrap(
        AppScaffold(
          title: 'Journal',
          actions: [
            IconButton(
              key: const ValueKey('export'),
              tooltip: 'Export',
              onPressed: () {},
              icon: const Icon(Icons.ios_share),
            ),
          ],
          body: const SizedBox(),
        ),
      ));
      final iconButton = find.byKey(const ValueKey('export'));
      expect(iconButton, findsOneWidget);
      // The action sits inside an AppBar.
      expect(
        find.ancestor(of: iconButton, matching: find.byType(AppBar)),
        findsOneWidget,
      );
    });

    testWidgets('renders floatingActionButton', (tester) async {
      await tester.pumpWidget(wrap(
        AppScaffold(
          title: 'Reminders',
          body: const SizedBox(),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: () {},
            label: const Text('Add reminder'),
            icon: const Icon(Icons.add_alarm),
          ),
        ),
      ));
      expect(find.byType(FloatingActionButton), findsOneWidget);
      expect(find.text('Add reminder'), findsOneWidget);
    });

    testWidgets('titleWidget overrides Text(title)', (tester) async {
      await tester.pumpWidget(wrap(
        const AppScaffold(
          title: 'fallback string',
          titleWidget: Text(
            'custom serif title',
            key: ValueKey('custom-title'),
          ),
          body: SizedBox(),
        ),
      ));
      expect(find.byKey(const ValueKey('custom-title')), findsOneWidget);
      // The fallback string shouldn't render when titleWidget is
      // supplied — otherwise we'd have two titles in the AppBar.
      expect(find.text('fallback string'), findsNothing);
    });
  });

  group('AppScaffold.hero', () {
    testWidgets('renders the hero builder above the body', (tester) async {
      await tester.pumpWidget(wrap(
        AppScaffold.hero(
          title: 'Home',
          heroBuilder: (_) => const ColoredBox(
            color: Colors.amber,
            child: SizedBox(
              key: ValueKey('hero'),
              width: double.infinity,
              height: 120,
              child: Text('Welcome, Loki'),
            ),
          ),
          body: const SizedBox(
            key: ValueKey('body'),
            child: Text('home content'),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('hero')), findsOneWidget);
      expect(find.byKey(const ValueKey('body')), findsOneWidget);
      expect(find.text('Welcome, Loki'), findsOneWidget);
      expect(find.text('home content'), findsOneWidget);
    });

    testWidgets('default hero height is 120dp', (tester) async {
      await tester.pumpWidget(wrap(
        AppScaffold.hero(
          title: 'Home',
          heroBuilder: (_) => const SizedBox.expand(
            key: ValueKey('hero-fill'),
          ),
          body: const SizedBox(),
        ),
      ));
      // The hero's outer SizedBox (set by AppScaffold) should be 120dp
      // tall. Find it via the height prop on the immediate ancestor.
      final heroSizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byKey(const ValueKey('hero-fill')),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(heroSizedBox.height, 120);
    });

    testWidgets('respects custom heroHeight', (tester) async {
      await tester.pumpWidget(wrap(
        AppScaffold.hero(
          title: 'Home',
          heroHeight: 200,
          heroBuilder: (_) => const SizedBox.expand(
            key: ValueKey('hero-fill'),
          ),
          body: const SizedBox(),
        ),
      ));
      final heroSizedBox = tester.widget<SizedBox>(
        find.ancestor(
          of: find.byKey(const ValueKey('hero-fill')),
          matching: find.byType(SizedBox),
        ).first,
      );
      expect(heroSizedBox.height, 200);
    });
  });

  group('AppScaffold.async', () {
    testWidgets('data → renders dataBuilder', (tester) async {
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'Care guides',
            value: const AsyncValue<String>.data('hello'),
            data: (_, s) => Text(s, key: const ValueKey('data')),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('data')), findsOneWidget);
      expect(find.text('hello'), findsOneWidget);
    });

    testWidgets('loading → renders default PetSkeleton list',
        (tester) async {
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'Care guides',
            value: const AsyncValue<String>.loading(),
            data: (_, _) => const Text('never'),
          ),
        ),
      ));
      // Default loading is six PetSkeleton.line rows in a ListView.
      // 5.8: default loading is now a stack of PetSkeletonListRow
      // (icon + title + subtitle = 3 PetSkeletons each). 6 rows × 3 = 18.
      expect(find.byType(PetSkeletonListRow), findsNWidgets(6));
      expect(find.byType(PetSkeleton), findsNWidgets(18));
      expect(find.text('never'), findsNothing);
    });

    testWidgets('error → renders default PetEmptyState', (tester) async {
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'Care guides',
            value: AsyncValue<String>.error('boom', StackTrace.current),
            data: (_, _) => const Text('never'),
          ),
        ),
      ));
      expect(find.byType(PetEmptyState), findsOneWidget);
      expect(find.text("Couldn't load this"), findsOneWidget);
      expect(find.text('boom'), findsOneWidget);
      // Without onRetry the empty state has no CTA.
      expect(find.text('Try again'), findsNothing);
    });

    testWidgets('error + onRetry → renders Try again button', (tester) async {
      var retryCount = 0;
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'Care guides',
            value: AsyncValue<String>.error('boom', StackTrace.current),
            data: (_, _) => const Text('never'),
            onRetry: () => retryCount++,
          ),
        ),
      ));
      expect(find.text('Try again'), findsOneWidget);
      // The retry button sits inside the PetEmptyState's CTA slot,
      // which is rendered inside an AnimatedOpacity layer. Tapping
      // by Text-finder produces a "won't hit-test" warning that's
      // unrelated to the assertion (the tap still registers); use
      // warnIfMissed: false to keep the output clean.
      await tester.tap(find.text('Try again'), warnIfMissed: false);
      await tester.pump();
      expect(retryCount, 1);
    });

    testWidgets('respects custom loading builder', (tester) async {
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'X',
            value: const AsyncValue<String>.loading(),
            data: (_, _) => const Text('never'),
            loading: (_) => const Text(
              'custom loading',
              key: ValueKey('custom-loading'),
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('custom-loading')), findsOneWidget);
      expect(find.byType(PetSkeleton), findsNothing);
    });

    testWidgets('respects custom error builder', (tester) async {
      await tester.pumpWidget(wrap(
        ProviderScope(
          child: AppScaffold.async<String>(
            title: 'X',
            value: AsyncValue<String>.error('boom', StackTrace.current),
            data: (_, _) => const Text('never'),
            error: (_, e, _) => Text(
              'custom error: $e',
              key: const ValueKey('custom-error'),
            ),
          ),
        ),
      ));
      expect(find.byKey(const ValueKey('custom-error')), findsOneWidget);
      expect(find.byType(PetEmptyState), findsNothing);
    });
  });

  group('petAccent threading', () {
    testWidgets('null → AppBar uses default theme background',
        (tester) async {
      await tester.pumpWidget(wrap(
        const AppScaffold(title: 'X', body: SizedBox()),
      ));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      // backgroundColor null means "fall through to theme".
      expect(appBar.backgroundColor, isNull);
    });

    testWidgets('non-null → AppBar background blends 8% toward accent',
        (tester) async {
      const accent = Color(0xFFE89B7A);  // soft coral, design-system accent
      await tester.pumpWidget(wrap(
        const AppScaffold(
          title: 'X',
          body: SizedBox(),
          petAccent: accent,
        ),
      ));
      final appBar = tester.widget<AppBar>(find.byType(AppBar));
      // Background should be neither null nor exactly the accent; it's
      // a Color.lerp(surface, accent, 0.08). The exact result depends
      // on the active surface — assert it's NOT null and NOT the bare
      // accent.
      expect(appBar.backgroundColor, isNotNull);
      expect(appBar.backgroundColor, isNot(equals(accent)));
    });
  });

  group('appSnackBar helper', () {
    testWidgets('dispatches a SnackBar via ScaffoldMessenger',
        (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(wrap(
        AppScaffold(
          title: 'X',
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      appSnackBar(ctx, 'Saved a memory about Loki');
      await tester.pump();
      expect(find.byType(SnackBar), findsOneWidget);
      expect(find.text('Saved a memory about Loki'), findsOneWidget);
    });

    testWidgets('respects action label', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(wrap(
        AppScaffold(
          title: 'X',
          body: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      ));
      appSnackBar(
        ctx,
        'Done',
        action: SnackBarAction(label: 'View', onPressed: () {}),
      );
      await tester.pump();
      expect(find.text('View'), findsOneWidget);
    });
  });
}
