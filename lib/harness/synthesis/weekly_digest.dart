import 'package:drift/drift.dart' show OrderingTerm;

import '../../data/db/database.dart';
import '../../data/pet_name.dart';
import '../../data/repos/trends_repo.dart';
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
    TrendsRepo? trends,
  })  : _db = db,
        _wiki = wiki,
        _wikiRepo = wikiRepo,
        _llm = llm,
        // Phase 6 task 6.13 — the trends repo enriches the digest's
        // structured signal block (weight series + symptom-keyword
        // counts). Default-constructed against the same db + wiki
        // when not supplied so existing callers don't need to update.
        _trends = trends ?? TrendsRepo(db: db, wiki: wiki);

  final AppDatabase _db;
  final WikiIo _wiki;
  final WikiRepo _wikiRepo;
  final LlmClient _llm;
  final TrendsRepo _trends;

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
    final photoEntries = <Entry>[];
    for (final entry in entries) {
      final body = await _wiki.read(entry.path);
      raw
        ..writeln('## ${entry.title} (${entry.path})')
        ..writeln(body.trim())
        ..writeln();
      // Phase 6 task 6.13 — track photo memories so the prompt can
      // explicitly reference them ("Loki spent more time at the park
      // — three photos at the trailhead this week").
      if (entry.type == 'photos') photoEntries.add(entry);
    }

    // Phase 6 task 6.13 — pull trend signals so the digest can
    // highlight anomalies / shifts the model wouldn't reliably spot
    // from the raw entry text alone. Best-effort: if either query
    // throws, the digest still ships with the entries-only view.
    String trendBlock = '';
    try {
      final allWeight = await _trends.weightHistory(petId);
      final symptoms = await _trends.symptomFrequencies(petId);
      trendBlock = _buildTrendBlock(
        allWeight: allWeight,
        symptoms: symptoms,
        photoEntries: photoEntries,
        windowDays: window.inDays,
        asOf: asOf,
      );
    } catch (_) {
      // Trend signal is enrichment, not load-bearing. Skip silently.
    }

    final categoryLabel = category.isEmpty ? 'pet' : category;
    // Bug-2 defense: an empty pet.name in the synthesis prompt would
    // produce "generating a weekly digest for , a dog." with an
    // orphan comma. Lowercase fallback matches the harness register.
    final petName = displayPetNameLower(pet.name);
    final systemPrompt =
        'You are PetPal, generating a weekly digest for $petName, '
        'a $categoryLabel. The user wrote the entries below this week. '
        'Summarise the week with these in mind:\n'
        '- Trends. Weight direction, food / behaviour patterns. '
        'Mention multi-week trends ONLY if the structured signal '
        'block below shows them; never invent a trend from one or '
        'two entries.\n'
        '- Anomalies. Symptoms that appeared more than twice in the '
        'week, sudden weight shifts (>5%), missed reminders, the kind '
        'of thing the owner might want to ask their vet about.\n'
        '- Photo memories. When photos exist this week, weave one or '
        'two in as anchor moments — name the setting / activity from '
        "the photo's frontmatter, not invented detail.\n"
        '- Gentle observations. Warm not alarmist. The user is the '
        'one who knows their pet; you\'re reflecting their week back '
        'to them, not auditing it.\n'
        '\n'
        'Output concise markdown with section headers. Cite entry '
        'paths in backticks where appropriate. Do not invent facts '
        'not present in the entries or trend signals. You are not a '
        'vet — flag escalation, do not diagnose.';

    final userTurnBuf = StringBuffer()
      ..writeln('Last ${window.inDays} days of entries for $petName:')
      ..writeln()
      ..write(raw.toString().trimRight());
    if (trendBlock.isNotEmpty) {
      userTurnBuf
        ..writeln()
        ..writeln()
        ..write(trendBlock);
    }

    final assistantMessage = await _llm.turn(
      systemPrompt: systemPrompt,
      history: [
        msg.Message(
          role: msg.Message.userRole,
          content: [msg.TextBlock(userTurnBuf.toString())],
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

  /// Phase 6 task 6.13 — compose the structured-signal block the
  /// digest prompt enriches the raw-entries with. Returns the empty
  /// string when no signal is worth surfacing (the prompt then falls
  /// back to entries-only).
  ///
  /// Signals:
  ///   - **Weight series.** All-time weight observations, plus an
  ///     explicit "this-week vs prior-week" delta when both windows
  ///     have at least one observation. Lets the model claim a
  ///     multi-week trend only when the underlying numbers carry it.
  ///   - **Symptom counts.** Total counts per known symptom keyword
  ///     across the entire journal — gives the model a sense of
  ///     baseline so a normal week of "Loki coughing once" doesn't
  ///     read as alarming.
  ///   - **Photo memory list.** Per-photo {date, type=photos path}
  ///     so the model can reference specific photos by path/date in
  ///     the digest narrative.
  static String _buildTrendBlock({
    required List<WeightObservation> allWeight,
    required List<SymptomFrequency> symptoms,
    required List<Entry> photoEntries,
    required int windowDays,
    required DateTime asOf,
  }) {
    final buf = StringBuffer()..writeln('## Structured signal block');

    if (allWeight.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Weight observations (all-time, ascending)');
      for (final w in allWeight) {
        final iso = '${w.ts.year.toString().padLeft(4, '0')}-'
            '${w.ts.month.toString().padLeft(2, '0')}-'
            '${w.ts.day.toString().padLeft(2, '0')}';
        buf.writeln('- $iso: ${w.kg.toStringAsFixed(2)} kg');
      }

      // Two-window delta — this-week vs prior-week mean. Avoids
      // "trended down for 3 weeks" from a single noisy point.
      final since = asOf.subtract(Duration(days: windowDays));
      final priorSince = asOf.subtract(Duration(days: windowDays * 2));
      final thisWeek = allWeight.where((w) => !w.ts.isBefore(since));
      final priorWeek = allWeight.where(
        (w) => w.ts.isBefore(since) && !w.ts.isBefore(priorSince),
      );
      if (thisWeek.isNotEmpty && priorWeek.isNotEmpty) {
        final thisAvg =
            thisWeek.map((w) => w.kg).reduce((a, b) => a + b) /
                thisWeek.length;
        final priorAvg =
            priorWeek.map((w) => w.kg).reduce((a, b) => a + b) /
                priorWeek.length;
        final delta = thisAvg - priorAvg;
        final pct = (delta / priorAvg * 100).abs().toStringAsFixed(1);
        final dir = delta > 0
            ? 'up'
            : delta < 0
                ? 'down'
                : 'flat';
        buf
          ..writeln()
          ..writeln('### Weight delta')
          ..writeln(
            '- This week mean: ${thisAvg.toStringAsFixed(2)} kg '
            '(n=${thisWeek.length})',
          )
          ..writeln(
            '- Prior week mean: ${priorAvg.toStringAsFixed(2)} kg '
            '(n=${priorWeek.length})',
          )
          ..writeln(
            '- Direction: $dir, $pct% '
            '(${delta.toStringAsFixed(2)} kg)',
          );
      }
    }

    final hasSymptoms = symptoms.any((s) => s.count > 0);
    if (hasSymptoms) {
      buf
        ..writeln()
        ..writeln('### Symptom keyword counts (all-time journal)');
      for (final s in symptoms) {
        buf.writeln('- ${s.label}: ${s.count}');
      }
    }

    if (photoEntries.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Photo memories this week');
      for (final p in photoEntries) {
        final iso = '${p.ts.year.toString().padLeft(4, '0')}-'
            '${p.ts.month.toString().padLeft(2, '0')}-'
            '${p.ts.day.toString().padLeft(2, '0')}';
        buf.writeln('- $iso: `${p.path}` — "${p.title}"');
      }
    }

    // Empty if neither weight nor symptoms nor photos provided
    // anything worth surfacing.
    final out = buf.toString();
    if (!out.contains('### ')) return '';
    return out;
  }
}
