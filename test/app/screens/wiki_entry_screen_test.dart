import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/wiki_entry_screen.dart';
import 'package:petpal/app/theme.dart';
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
}

Widget _wrap(WikiIo wiki) => ProviderScope(
      overrides: [
        wikiIoProvider.overrideWith((ref) async => wiki),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: const WikiEntryScreen(path: 'wiki/1/vet/2026-04-25-rabies.md'),
      ),
    );

void main() {
  testWidgets(
      'WikiEntryScreen renders the body as markdown — no raw "##" / '
      '"**" tokens leak through; the frontmatter `---` block is stripped',
      (tester) async {
    const raw = '''---
type: vet
date: 2026-04-25
---

## Visit Summary
**Clinic:** Maple Vet

- **Vaccines given:** rabies, DHPP
- **Next due:** 2027-04-25

Loki was calm throughout.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();

    // Markdown widget mounts (vs the pre-fix `SelectableText` with
    // monospace).
    expect(find.byType(Markdown), findsOneWidget);

    // Raw markdown source MUST NOT appear as literal text.
    expect(find.text('## Visit Summary'), findsNothing,
        reason: 'header marker must be parsed, not rendered as literal');
    expect(find.text('**Clinic:**'), findsNothing,
        reason: 'bold marker must be parsed');
    expect(find.text('- **Vaccines given:** rabies, DHPP'), findsNothing,
        reason: 'list+bold marker must be parsed');

    // Frontmatter delimiter / keys must not show in the rendered body.
    expect(find.text('---'), findsNothing,
        reason: 'frontmatter delimiter is stripped via parseSoul');
    expect(find.textContaining('type: vet'), findsNothing,
        reason: 'frontmatter content is stripped');

    // The rendered markdown body — header text, plain prose, and the
    // list bodies — should be findable as plain strings.
    expect(find.textContaining('Visit Summary'), findsOneWidget);
    expect(find.textContaining('Maple Vet'), findsOneWidget);
    expect(find.textContaining('Loki was calm throughout.'), findsOneWidget);
  });

  testWidgets(
      'WikiEntryScreen handles body-only files (no frontmatter) without '
      'eating the first line',
      (tester) async {
    const raw = '''# Just a body
This file has no frontmatter — parseSoul should pass it through
unchanged.
''';
    await tester.pumpWidget(_wrap(_StubWiki(raw)));
    await tester.pumpAndSettle();

    expect(find.byType(Markdown), findsOneWidget);
    expect(find.text('# Just a body'), findsNothing);
    expect(find.textContaining('Just a body'), findsOneWidget);
    expect(find.textContaining('parseSoul should pass it through'),
        findsOneWidget);
  });

  testWidgets('WikiEntryScreen for a digest path renders the locked '
      'AppBar title "Weekly summary" (VOICE.md §6 example 5)',
      (tester) async {
    const raw = '''---
type: digest
---

## Loki this week
A quiet week.
''';
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          wikiIoProvider.overrideWith((ref) async => _StubWiki(raw)),
        ],
        child: MaterialApp(
          theme: buildLightTheme(),
          home: const WikiEntryScreen(
            path: 'wiki/1/digest/2026-04-29-week.md',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Weekly summary'), findsOneWidget,
        reason: 'AppBar uses the locked digest title');
    expect(find.byType(Markdown), findsOneWidget);
    expect(find.textContaining('A quiet week.'), findsOneWidget);
  });
}
