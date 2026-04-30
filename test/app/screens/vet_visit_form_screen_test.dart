import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/providers.dart';
import 'package:petpal/app/screens/vet_visit_form_screen.dart';
import 'package:petpal/data/db/sqlite_vec.dart';
import 'package:petpal/data/soul_file.dart';
import 'package:petpal/main.dart';

import '../../_helpers/fake_api_key_storage.dart';
import '../../_helpers/scripted_llm_client.dart';
import '../../_helpers/test_provider_scope.dart';

/// Phase 6 task 6.10 — vet-visit structured entry creator.
///
/// The form fills a fixed set of fields and writes a structured-
/// frontmatter markdown file to `wiki/<petId>/vet/<date>-<slug>.md`.
/// The tests below exercise:
///   - the form renders all locked fields,
///   - Save composes a valid YAML frontmatter with the expected keys
///     and writes the file via WikiRepo,
///   - the freeform notes textarea content lands in the body,
///   - empty `reason` falls back to "Vet visit".
void main() {
  setUpAll(() {
    registerSqliteVec(
      extensionPath: '${Directory.current.path}/test/native/libvec0.so',
    );
  });

  testWidgets('renders the locked field set: visit date, vet name, reason, '
      'diagnosis, prescriptions, follow-up, notes', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Date of visit'), findsOneWidget);
    expect(find.text('Vet name (optional)'), findsOneWidget);
    expect(find.text('Reason for visit'), findsOneWidget);
    expect(find.text('Diagnosis (what the vet said)'), findsOneWidget);
    expect(find.text('Prescriptions (one per line)'), findsOneWidget);
    expect(find.text('Follow-up (optional)'), findsOneWidget);
    expect(find.text('Notes'), findsOneWidget);
  });

  testWidgets('Save writes a vet entry whose frontmatter carries the '
      'locked structured keys (type, date, vet_name, reason, diagnosis, '
      'prescriptions, follow_up_date)', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, 'Vet name (optional)'),
      'Dr. Patel',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Reason for visit'),
      'Annual checkup',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Diagnosis (what the vet said)'),
      'No issues found.',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Prescriptions (one per line)'),
      'Frontline Plus monthly\nApoquel 16mg, twice daily',
    );

    // Notes field is the last TextField; locate by hint text.
    await tester.enterText(
      find.widgetWithText(
        TextField,
        "Anything else worth remembering — owner's notes go here, in your voice.",
      ),
      "He was nervous in the waiting room but settled in the exam.",
    );

    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    // Find the written file. Path shape: wiki/1/vet/<YYYY-MM-DD>-annual-checkup.md
    final petWikiKeys = stack.wiki.writes.keys.where(
      (k) => k.startsWith('wiki/${stack.petId}/vet/'),
    );
    expect(petWikiKeys, hasLength(1));
    final path = petWikiKeys.single;
    expect(path, contains('-annual-checkup.md'));

    final body = stack.wiki.writes[path]!;
    final parsed = parseSoul(body);

    expect(parsed.frontmatter['type'], 'vet');
    expect(parsed.frontmatter['date'], isA<String>());
    expect(parsed.frontmatter['vet_name'], 'Dr. Patel');
    expect(parsed.frontmatter['reason'], 'Annual checkup');
    expect(parsed.frontmatter['diagnosis'], 'No issues found.');
    expect(parsed.frontmatter['prescriptions'], [
      'Frontline Plus monthly',
      'Apoquel 16mg, twice daily',
    ]);
    // Follow-up was not set; key must be absent from frontmatter.
    expect(parsed.frontmatter.containsKey('follow_up_date'), isFalse);

    // Body carries the heading + freeform notes.
    expect(parsed.body, contains('# Annual checkup'));
    expect(parsed.body, contains('He was nervous'));
  });

  testWidgets('empty reason falls back to "Vet visit" title (path slug + '
      'body heading)', (tester) async {
    final stack = await buildChatTestStack(
      llm: ScriptedLlmClient(scripts: const []),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          apiKeyStorageProvider.overrideWithValue(
            FakeApiKeyStorage(initial: 'sk-ant-test'),
          ),
          ...stack.overrides,
        ],
        child: const MaterialApp(home: VetVisitFormScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // No reason entered — Save anyway.
    await tester.ensureVisible(find.text('Save vet visit'));
    await tester.tap(find.text('Save vet visit'));
    await tester.pumpAndSettle();

    final paths = stack.wiki.writes.keys.where(
      (k) => k.startsWith('wiki/${stack.petId}/vet/'),
    );
    expect(paths, hasLength(1));
    expect(paths.single, endsWith('-vet-visit.md'),
        reason: 'empty-reason fallback uses "Vet visit" → vet-visit slug');

    final body = stack.wiki.writes[paths.single]!;
    final parsed = parseSoul(body);
    expect(parsed.frontmatter['type'], 'vet');
    expect(parsed.frontmatter.containsKey('reason'), isFalse,
        reason: 'empty reason is omitted from frontmatter');
    expect(parsed.body, contains('# Vet visit'));
  });
}
