import 'dart:typed_data';

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

  @override
  Future<void> writeBytesAtomic(String relPath, Uint8List bytes) async =>
      throw UnimplementedError('photo write not used in this test');

  /// Returns valid 1x1 PNG bytes for any path. The 6.3 photo entry
  /// view feeds the FutureBuilder these bytes; image-decode runs
  /// inside the test binding and the field-row asserts can resolve
  /// regardless of the codec settling.
  @override
  Future<Uint8List> readBytes(String relPath) async => Uint8List.fromList([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53, 0xDE,
        0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41, 0x54,
        0x08, 0x99, 0x63, 0xF8, 0xCF, 0xC0, 0x00, 0x00,
        0x00, 0x03, 0x00, 0x01, 0x59, 0xF6, 0x29, 0xD2,
        0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44,
        0xAE, 0x42, 0x60, 0x82,
      ]);

  @override
  Future<void> deleteIfExists(String relPath) async {}
  @override
  Future<int> bytesForPet(int petId) async => 0;
  @override
  Future<void> deleteAll() async {}
}

Widget _wrap(
  WikiIo wiki, {
  String path = 'wiki/1/vet/2026-04-25-rabies.md',
}) =>
    ProviderScope(
      overrides: [
        wikiIoProvider.overrideWith((ref) async => wiki),
      ],
      child: MaterialApp(
        theme: buildLightTheme(),
        home: WikiEntryScreen(path: path),
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
    expect(find.byType(MarkdownBody), findsOneWidget);

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

    expect(find.byType(MarkdownBody), findsOneWidget);
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
    // Phase 6.6 task 6.6.C.2 — entry header in the body now also
    // renders the human title ("Weekly summary"), so the title
    // appears twice: once in the AppBar (the existing locked
    // VOICE.md §6 surface) and once in the body header (the new
    // editorial register).
    expect(find.text('Weekly summary'), findsNWidgets(2),
        reason: 'AppBar + body header both render the locked digest '
            'title');
    expect(find.byType(MarkdownBody), findsOneWidget);
    expect(find.textContaining('A quiet week.'), findsOneWidget);
  });

  group('Phase 6 task 6.3 — photo entry view dispatch', () {
    // A photo sidecar — type=photos, with the locked 6.1-minimum
    // frontmatter shape plus optional 6.5 extractor fields.
    const photoSidecar = '''---
type: photos
image: abc-123.jpg
ts: 2026-04-25T14:30:12
byte_size: 24576
setting: outdoors
activity: walking
demeanor: looks relaxed and curious
notable_objects:
  - leash
  - frozen carrot
enrichment_hints:
  - "Was Loki excited the whole walk or just at the trailhead?"
---

Loki at the trailhead.
''';

    testWidgets('dispatches to the photo entry view (NOT the markdown '
        'render path) when frontmatter has type: photos', (tester) async {
      await tester.pumpWidget(_wrap(_StubWiki(photoSidecar)));
      await tester.pumpAndSettle();

      // Markdown widget MUST NOT mount on the photo path — the type
      // dispatch routes to _PhotoEntryView instead.
      expect(find.byType(MarkdownBody), findsNothing,
          reason: 'photo entries skip the markdown render path');

      // The freeform caption from the sidecar body shows as plain
      // text (SelectableText), not as a markdown widget.
      expect(find.textContaining('Loki at the trailhead.'),
          findsOneWidget);
    });

    testWidgets('photo entry view surfaces the additive frontmatter '
        'fields (setting / activity / demeanor / notable_objects '
        '/ enrichment_hints) as label-value rows', (tester) async {
      await tester.pumpWidget(_wrap(_StubWiki(photoSidecar)));
      await tester.pumpAndSettle();

      expect(find.text('Setting'), findsOneWidget);
      expect(find.text('outdoors'), findsOneWidget);
      expect(find.text('Activity'), findsOneWidget);
      expect(find.text('walking'), findsOneWidget);
      expect(find.text('Demeanor'), findsOneWidget);
      expect(find.textContaining('looks relaxed and curious'),
          findsOneWidget);
      expect(find.text('Notable'), findsOneWidget);
      expect(find.textContaining('leash, frozen carrot'), findsOneWidget);
      expect(find.text('Follow-up'), findsOneWidget);
      // Bytes formatted as human-readable (24576 → 24 KB).
      expect(find.text('Size'), findsOneWidget);
      expect(find.textContaining('24 KB'), findsOneWidget);
    });

    testWidgets('photo entry view skips rows for absent fields — the '
        '6.1-minimum sidecar (no extractor fields yet) renders only '
        '"When" + "Size"', (tester) async {
      const minimalSidecar = '''---
type: photos
image: abc-123.jpg
ts: 2026-04-25T14:30:12
byte_size: 1536
---

''';
      await tester.pumpWidget(_wrap(_StubWiki(minimalSidecar)));
      await tester.pumpAndSettle();

      expect(find.byType(MarkdownBody), findsNothing);
      // No extractor fields render.
      expect(find.text('Setting'), findsNothing);
      expect(find.text('Activity'), findsNothing);
      expect(find.text('Demeanor'), findsNothing);
      expect(find.text('Notable'), findsNothing);
      expect(find.text('Follow-up'), findsNothing);
      // Always-present fields still render.
      expect(find.text('When'), findsOneWidget);
      expect(find.text('Size'), findsOneWidget);
    });

    testWidgets('AppBar title is "Memory" for photo entries (path-shape '
        'fallback — photo paths use UUIDs not <date>-<slug>)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        _StubWiki(photoSidecar),
        path: 'wiki/1/photos/abc-123.md',
      ));
      await tester.pumpAndSettle();
      expect(find.text('Memory'), findsOneWidget);
    });

    // Phase 6 task 6.7 — when the sidecar carries a non-empty
    // `red_flag_match` field (the screener flagged the extractor's
    // freeform_caption + notable_objects at save time), the photo
    // entry view shows the historical urgency badge above the photo.
    testWidgets('renders the red-flag badge when frontmatter has a '
        'non-empty red_flag_match', (tester) async {
      const flaggedSidecar = '''---
type: photos
image: abc-123.jpg
ts: 2026-04-25T14:30:12
byte_size: 24576
red_flag_match: collapse
---

Loki on the kitchen floor.
''';
      await tester.pumpWidget(_wrap(_StubWiki(flaggedSidecar)));
      await tester.pumpAndSettle();
      expect(
        find.text('PetPal flagged something it noticed in this photo'),
        findsOneWidget,
        reason: '6.7 historical badge on flagged photo entries',
      );
    });

    testWidgets('does NOT render the red-flag badge when red_flag_match is '
        'absent (the regular case)', (tester) async {
      // The default photoSidecar has no red_flag_match field.
      await tester.pumpWidget(_wrap(_StubWiki(photoSidecar)));
      await tester.pumpAndSettle();
      expect(
        find.text('PetPal flagged something it noticed in this photo'),
        findsNothing,
      );
    });
  });
}
