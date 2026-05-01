import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/wiki_entry_screen.dart';
import 'package:petpal/app/theme.dart';
import 'package:petpal/app/widgets/editorial_card.dart';
import 'package:petpal/data/wiki_io.dart';

class _StubWiki implements WikiIo {
  _StubWiki(this.body);
  final String body;

  @override
  Future<String> read(String relPath) async => body;

  @override
  Future<void> writeAtomic(String relPath, String body) async {}

  @override
  Future<List<String>> listForPet(int petId) async => const [];

  @override
  String petDir(int petId) => 'wiki/$petId';

  @override
  String soulPath(int petId) => 'wiki/$petId/SOUL.md';

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) async =>
      throw UnimplementedError();

  @override
  Future<Uint8List> readBytes(String relPath) async => Uint8List(0);

  @override
  Future<void> deleteIfExists(String relPath) async {}

  @override
  Future<int> bytesForPet(int petId) async => 0;
}

Widget _wrap(WikiIo wiki) => ProviderScope(
      overrides: [
        wikiIoProvider.overrideWith((ref) async => wiki),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const WikiEntryScreen(
          path: 'wiki/1/digest/2026-04-29-week.md',
        ),
      ),
    );

/// Phase 6.6 task 6.6.C.3 — digest detail render tests. Pins:
///   - Editorial header uses weeklySummaryTitle for digest entries.
///   - INSIGHT callouts render for trend / anomaly / insight h2
///     sections (sage register).
///   - HIGHLIGHTS sections render bullet items as nested
///     EditorialCards.
///   - Other h2 sections fall through to default markdown render.
void main() {
  testWidgets('digest body — INSIGHT callout for "Trends" section',
      (tester) async {
    const raw = '''---
type: digest
---

## Trends
Loki's weight has trended down for 3 weeks.

## Notes
A quiet week otherwise.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();

    // Heading rendered uppercased (small caps register).
    expect(find.text('TRENDS'), findsOneWidget);
    // Body line shows.
    expect(
      find.textContaining("trended down for 3 weeks"),
      findsOneWidget,
    );
    // "Notes" section keeps default markdown rendering — h2 text is
    // mixed case as authored.
    expect(find.textContaining('Notes'), findsOneWidget);
  });

  testWidgets('digest body — INSIGHT callout for "Anomalies" section',
      (tester) async {
    const raw = '''---
type: digest
---

## Anomalies
Skateboard reactivity escalated this week.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();
    expect(find.text('ANOMALIES'), findsOneWidget);
    expect(
      find.textContaining('Skateboard reactivity'),
      findsOneWidget,
    );
  });

  testWidgets('digest body — HIGHLIGHTS section renders bullets as '
      'nested EditorialCards', (tester) async {
    const raw = '''---
type: digest
---

## Highlights
- Loki at the trailhead — three photos this week.
- Vet visit cleared the ear infection.
- Frozen carrots remain a top food.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();

    // Section header renders uppercased.
    expect(find.text('HIGHLIGHTS'), findsOneWidget);

    // Three bullet items become three EditorialCards. Each card's
    // title is the bullet text.
    expect(find.byType(EditorialCard), findsNWidgets(3));
    expect(
      find.text('Loki at the trailhead — three photos this week.'),
      findsOneWidget,
    );
    expect(
      find.text('Vet visit cleared the ear infection.'),
      findsOneWidget,
    );
    expect(
      find.text('Frozen carrots remain a top food.'),
      findsOneWidget,
    );
  });

  testWidgets('digest body — section without an INSIGHT or HIGHLIGHTS '
      'keyword falls through to default markdown render', (tester) async {
    const raw = '''---
type: digest
---

## Around the house
A quiet week otherwise. Plenty of naps on the couch.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();
    // Heading rendered as default markdown (mixed case preserved by
    // markdown rendering).
    expect(find.textContaining('Around the house'), findsOneWidget);
    expect(
      find.textContaining('Plenty of naps on the couch.'),
      findsOneWidget,
    );
    // No EditorialCard rendered (only used for HIGHLIGHTS bullets).
    expect(find.byType(EditorialCard), findsNothing);
  });

  testWidgets('digest body — mixed sections compose in order: INSIGHT, '
      'HIGHLIGHTS, default markdown', (tester) async {
    const raw = '''---
type: digest
---

## Trends
Weight steady this week.

## Highlights
- Two great park walks.
- New favourite chew toy.

## Notes
Otherwise quiet.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();
    expect(find.text('TRENDS'), findsOneWidget);
    expect(find.text('HIGHLIGHTS'), findsOneWidget);
    expect(find.byType(EditorialCard), findsNWidgets(2));
    expect(find.textContaining('Otherwise quiet'), findsOneWidget);
  });

  testWidgets('digest entry header uses weeklySummaryTitle (the larger '
      'serif register) — not entryTitle', (tester) async {
    const raw = '''---
type: digest
---

A quiet week.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();
    // The body header text — VOICE.md §6 lock for digest paths is
    // "Weekly summary" (mixed case). The bigger serif register
    // shows up via fontSize: 28 (weeklySummaryTitle) rather than
    // 24 (entryTitle).
    final headers = find.text('Weekly summary');
    expect(headers, findsNWidgets(2)); // AppBar + body header.
    // Find the body-header instance (it's inside the
    // SingleChildScrollView; the AppBar instance is in titleTextStyle
    // / Title widget). Pull its style and assert size == 28.
    final styles = tester
        .widgetList<Text>(headers)
        .where((t) => t.style != null && t.style!.fontSize != null)
        .map((t) => t.style!.fontSize!)
        .toSet();
    expect(styles.contains(28.0), isTrue,
        reason: 'digest body header uses weeklySummaryTitle (28pt)');
  });
}
