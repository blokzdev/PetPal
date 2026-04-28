import 'package:drift/drift.dart' show OrderingTerm;

import '../../data/db/database.dart';
import '../../data/repos/wiki_repo.dart';
import '../../data/soul_file.dart';
import '../../data/wiki_io.dart';
import '../agent/llm_client.dart';
import '../agent/messages.dart' as msg;

/// Result of one [WeeklyDigestRunner.run] call. `skipped: true` when no
/// digest was needed (no entries in the window); otherwise `entryId` is
/// the id of the digest entry just written.
class DigestResult {
  const DigestResult({
    required this.skipped,
    this.reason,
    this.entryId,
    this.entryPath,
  });
  final bool skipped;
  final String? reason;
  final int? entryId;
  final String? entryPath;
}

/// Runs the **synthesis-mode** weekly digest task per CLAUDE.md §8.
/// Gathers a pet's last-7-days of wiki entries, asks the LLM to
/// summarise them, and writes the synthesis back as a new wiki entry
/// under `wiki/<petId>/digest/<YYYY-MM-DD>-weekly.md`.
///
/// Synthesis-mode (vs deterministic-mode) reminders are Pro-tier and
/// user-toggleable per CLAUDE.md §8 — that toggle wires up in 3.8;
/// 3.7 just builds the runner so it can be invoked manually now and
/// scheduled by WorkManager in Phase 4.
class WeeklyDigestRunner {
  WeeklyDigestRunner({
    required AppDatabase db,
    required WikiIo wiki,
    required WikiRepo wikiRepo,
    required LlmClient llm,
  })  : _db = db,
        _wiki = wiki,
        _wikiRepo = wikiRepo,
        _llm = llm;

  final AppDatabase _db;
  final WikiIo _wiki;
  final WikiRepo _wikiRepo;
  final LlmClient _llm;

  Future<DigestResult> run({
    required int petId,
    DateTime? now,
    Duration window = const Duration(days: 7),
  }) async {
    final asOf = now ?? DateTime.now();
    final since = asOf.subtract(window);

    // Drift's typed date comparisons vary by version — filter in Dart
    // after a pet-id query. Per-pet entry counts are bounded; the cost
    // is negligible vs. the LLM call this digest is about to make.
    final allForPet = await (_db.select(_db.entries)
          ..where((e) => e.petId.equals(petId))
          ..orderBy([(e) => OrderingTerm.asc(e.ts)]))
        .get();
    final entries = allForPet
        .where((e) => !e.ts.isBefore(since))
        .toList();

    // Don't generate a digest for a pet with no recent activity.
    if (entries.isEmpty) {
      return const DigestResult(
        skipped: true,
        reason: 'no entries in the digest window',
      );
    }

    final pet = await (_db.select(_db.pets)
          ..where((p) => p.id.equals(petId)))
        .getSingle();

    String category = '';
    try {
      final soul = await _wiki.read(_wiki.soulPath(petId));
      category = parseSoul(soul).frontmatter['category']?.toString() ?? '';
    } catch (_) {
      // No SOUL.md yet — proceed with empty category.
    }

    final raw = StringBuffer();
    for (final entry in entries) {
      final body = await _wiki.read(entry.path);
      raw
        ..writeln('## ${entry.title} (${entry.path})')
        ..writeln(body.trim())
        ..writeln();
    }

    final categoryLabel = category.isEmpty ? 'pet' : category;
    final systemPrompt =
        'You are PetPal, generating a weekly digest for ${pet.name}, '
        'a $categoryLabel. The user wrote the entries below this week. '
        'Summarise: trends in weight / food / behaviour, anything that '
        'warrants vet attention, open questions to follow up. Output '
        'concise markdown with section headers. Cite entry paths in '
        'backticks where appropriate. Do not invent facts not present '
        'in the entries. You are not a vet — flag escalation, do not '
        'diagnose.';

    final assistantMessage = await _llm.turn(
      systemPrompt: systemPrompt,
      history: [
        msg.Message(
          role: msg.Message.userRole,
          content: [
            msg.TextBlock(
              'Last ${window.inDays} days of entries for ${pet.name}:\n\n'
              '${raw.toString().trimRight()}\n',
            ),
          ],
        ),
      ],
    );

    final summary = assistantMessage.content
        .whereType<msg.TextBlock>()
        .map((b) => b.text)
        .join('\n')
        .trim();
    if (summary.isEmpty) {
      return const DigestResult(
        skipped: true,
        reason: 'LLM returned no usable text',
      );
    }

    final iso = '${asOf.year.toString().padLeft(4, '0')}-'
        '${asOf.month.toString().padLeft(2, '0')}-'
        '${asOf.day.toString().padLeft(2, '0')}';
    final entryId = await _wikiRepo.writeEntry(
      petId: petId,
      type: 'digest',
      title: 'Weekly digest $iso',
      body: summary,
      ts: asOf,
    );
    final path = entryPath(
      petId: petId,
      type: 'digest',
      title: 'Weekly digest $iso',
      ts: asOf,
    );

    return DigestResult(
      skipped: false,
      entryId: entryId,
      entryPath: path,
    );
  }
}
