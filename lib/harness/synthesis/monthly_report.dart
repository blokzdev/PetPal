import 'package:drift/drift.dart' show OrderingTerm;

import '../../data/db/database.dart';
import '../../data/pet_name.dart';
import '../../data/repos/trends_repo.dart';
import '../../data/repos/wiki_repo.dart';
import '../../data/soul_file.dart';
import '../../data/wiki_io.dart';
import '../agent/llm_client.dart';
import '../agent/messages.dart' as msg;

/// Phase 6 task 6.14 — monthly health report runner.
///
/// Sister of [WeeklyDigestRunner] (6.13). Same shape, longer window,
/// different prompt scaffolding focused on longer-arc patterns:
///
/// - Multi-week weight trajectory (the weekly's two-window delta is
///   too short-arc for monthly framing).
/// - Vet-visit follow-up status — for every vet entry in the window,
///   flag whether `follow_up_date` is set and whether it's elapsed.
/// - Recurring patterns — symptom keyword counts over the month, not
///   per-week.
/// - Photo memory anchors — same shape as 6.13, but the model is
///   told to weave 3-4 across the month rather than 1-2 within the
///   week.
///
/// Outputs to `wiki/<petId>/digest/<YYYY-MM>-monthly.md`. Same `digest`
/// type so the journal browser surfaces weekly + monthly together
/// (the title prefix disambiguates: "Monthly report" vs
/// "Weekly digest"). The Phase 5.6 `_DigestCard` widget renders both
/// without modification.
///
/// **Pro-feature framing.** ROADMAP 6.14 + DECISIONS row 36 tag this
/// as Pro. Phase 6 ships without enforcement gating — Phase 7 task
/// 7.10 plugs in the entitlement check at the runner-invocation seam
/// (or the schedule-job seam, if monthly is wired to a WorkManager
/// task).
class MonthlyReportRunner {
  MonthlyReportRunner({
    required AppDatabase db,
    required WikiIo wiki,
    required WikiRepo wikiRepo,
    required LlmClient llm,
    TrendsRepo? trends,
  })  : _db = db,
        _wiki = wiki,
        _wikiRepo = wikiRepo,
        _llm = llm,
        _trends = trends ?? TrendsRepo(db: db, wiki: wiki);

  final AppDatabase _db;
  final WikiIo _wiki;
  final WikiRepo _wikiRepo;
  final LlmClient _llm;
  final TrendsRepo _trends;

  Future<MonthlyReportResult> run({
    required int petId,
    DateTime? now,
    Duration window = const Duration(days: 30),
  }) async {
    final asOf = now ?? DateTime.now();
    final since = asOf.subtract(window);

    final allForPet = await (_db.select(_db.entries)
          ..where((e) => e.petId.equals(petId))
          ..orderBy([(e) => OrderingTerm.asc(e.ts)]))
        .get();
    final entries = allForPet
        .where((e) => !e.ts.isBefore(since))
        .toList();

    if (entries.isEmpty) {
      return const MonthlyReportResult(
        skipped: true,
        reason: 'no entries in the report window',
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

    // Categorise entries for the prompt and the vet-follow-up block.
    final raw = StringBuffer();
    final photoEntries = <Entry>[];
    final vetEntries = <_VetEntryWithFollowUp>[];
    for (final entry in entries) {
      final body = await _wiki.read(entry.path);
      raw
        ..writeln('## ${entry.title} (${entry.path})')
        ..writeln(body.trim())
        ..writeln();
      if (entry.type == 'photos') photoEntries.add(entry);
      if (entry.type == 'vet') {
        try {
          final parsed = parseSoul(body);
          final fu = parsed.frontmatter['follow_up_date']?.toString();
          DateTime? followUp;
          if (fu != null && fu.isNotEmpty) {
            final m =
                RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(fu);
            if (m != null) {
              followUp = DateTime(
                int.parse(m.group(1)!),
                int.parse(m.group(2)!),
                int.parse(m.group(3)!),
              );
            }
          }
          vetEntries.add(_VetEntryWithFollowUp(
            entry: entry,
            reason: parsed.frontmatter['reason']?.toString(),
            followUpDate: followUp,
          ));
        } catch (_) {
          vetEntries.add(_VetEntryWithFollowUp(
            entry: entry,
            reason: null,
            followUpDate: null,
          ));
        }
      }
    }

    String trendBlock = '';
    try {
      final allWeight = await _trends.weightHistory(petId);
      final symptoms = await _trends.symptomFrequencies(petId);
      trendBlock = _buildMonthlyTrendBlock(
        allWeight: allWeight,
        symptoms: symptoms,
        photoEntries: photoEntries,
        vetEntries: vetEntries,
        windowDays: window.inDays,
        asOf: asOf,
      );
    } catch (_) {
      // Best-effort enrichment.
    }

    final categoryLabel = category.isEmpty ? 'pet' : category;
    final petName = displayPetNameLower(pet.name);
    final systemPrompt =
        'You are PetPal, generating a MONTHLY health report for '
        '$petName, a $categoryLabel. The user wrote the entries below '
        'over the past ${window.inDays} days. The monthly report is '
        'longer-arc than the weekly digest — focus on:\n'
        '- Multi-week trajectory. Weight curve over the month, not '
        'just delta vs last week. Mention direction and magnitude in '
        'the same sentence ("Loki has trended down ~3% over the last '
        'four weeks") — never one without the other.\n'
        '- Vet-visit follow-up status. For every vet entry this '
        'month, name what was flagged and whether the scheduled '
        'follow-up has been booked / kept / is still pending.\n'
        '- Recurring patterns. Symptoms that appeared more than '
        'three times in the month, food or behaviour shifts that '
        'held up week over week.\n'
        '- Photo memory anchors. When photos exist, weave 3 or 4 '
        'into the report at the right beats — name the setting / '
        "activity from the photo's frontmatter, never invented "
        'detail. Make the report read as "the month in $petName\'s '
        'life" not "a list of medical facts."\n'
        '- Gentle observations. Warm not alarmist. The user is the '
        'one who knows their pet; the report reflects the month back '
        'to them, not audits it.\n'
        '\n'
        'Output concise markdown with section headers. Cite entry '
        'paths in backticks where appropriate. Do not invent facts '
        'not present in the entries or trend signals. You are not a '
        'vet — flag escalation, do not diagnose. The report runs '
        'long-form (300-500 words is fine if the month justifies '
        "it); don't pad if the month was quiet.";

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
      return const MonthlyReportResult(
        skipped: true,
        reason: 'LLM returned no usable text',
      );
    }

    // Title shape: "Monthly report 2026-04" — calendar-month-stamped
    // even when the runner fires mid-month, since the prompt window
    // is the trailing N days. The disambiguator vs weekly digest is
    // the title prefix.
    final ym = '${asOf.year.toString().padLeft(4, '0')}-'
        '${asOf.month.toString().padLeft(2, '0')}';
    final title = 'Monthly report $ym';
    final entryId = await _wikiRepo.writeEntry(
      petId: petId,
      type: 'digest',
      title: title,
      body: summary,
      ts: asOf,
    );
    final path = entryPath(
      petId: petId,
      type: 'digest',
      title: title,
      ts: asOf,
    );

    return MonthlyReportResult(
      skipped: false,
      entryId: entryId,
      entryPath: path,
    );
  }

  /// Compose the structured signal block for the monthly prompt.
  /// Differs from the weekly's block by including the vet-follow-up
  /// status section + framing the weight delta over the full month
  /// rather than week-vs-week.
  static String _buildMonthlyTrendBlock({
    required List<WeightObservation> allWeight,
    required List<SymptomFrequency> symptoms,
    required List<Entry> photoEntries,
    required List<_VetEntryWithFollowUp> vetEntries,
    required int windowDays,
    required DateTime asOf,
  }) {
    final buf = StringBuffer()
      ..writeln('## Structured signal block (month-arc)');

    if (allWeight.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Weight trajectory (all-time, ascending)');
      for (final w in allWeight) {
        final iso = '${w.ts.year.toString().padLeft(4, '0')}-'
            '${w.ts.month.toString().padLeft(2, '0')}-'
            '${w.ts.day.toString().padLeft(2, '0')}';
        buf.writeln('- $iso: ${w.kg.toStringAsFixed(2)} kg');
      }
      // Month-arc delta — first vs last observation in the window.
      final since = asOf.subtract(Duration(days: windowDays));
      final inWindow =
          allWeight.where((w) => !w.ts.isBefore(since)).toList();
      if (inWindow.length >= 2) {
        final first = inWindow.first.kg;
        final last = inWindow.last.kg;
        final delta = last - first;
        final pct = (delta / first * 100).abs().toStringAsFixed(1);
        final dir = delta > 0
            ? 'up'
            : delta < 0
                ? 'down'
                : 'flat';
        buf
          ..writeln()
          ..writeln('### Month-arc weight delta')
          ..writeln('- Start of window: ${first.toStringAsFixed(2)} kg')
          ..writeln('- End of window: ${last.toStringAsFixed(2)} kg')
          ..writeln(
            '- Direction: $dir, $pct% '
            '(${delta.toStringAsFixed(2)} kg over $windowDays days)',
          );
      }
    }

    if (symptoms.any((s) => s.count > 0)) {
      buf
        ..writeln()
        ..writeln('### Symptom keyword counts (all-time journal)');
      for (final s in symptoms) {
        buf.writeln('- ${s.label}: ${s.count}');
      }
    }

    if (vetEntries.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Vet visits this month');
      for (final v in vetEntries) {
        final iso = '${v.entry.ts.year.toString().padLeft(4, '0')}-'
            '${v.entry.ts.month.toString().padLeft(2, '0')}-'
            '${v.entry.ts.day.toString().padLeft(2, '0')}';
        final reason = v.reason?.trim().isNotEmpty == true
            ? v.reason!
            : v.entry.title;
        var line = '- $iso: $reason (`${v.entry.path}`)';
        if (v.followUpDate != null) {
          final fuIso =
              '${v.followUpDate!.year.toString().padLeft(4, '0')}-'
              '${v.followUpDate!.month.toString().padLeft(2, '0')}-'
              '${v.followUpDate!.day.toString().padLeft(2, '0')}';
          final isPast = v.followUpDate!.isBefore(asOf);
          final status = isPast ? 'past-due' : 'pending';
          line += ' — follow-up $fuIso ($status)';
        } else {
          line += ' — no follow-up scheduled';
        }
        buf.writeln(line);
      }
    }

    if (photoEntries.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('### Photo memories this month');
      for (final p in photoEntries) {
        final iso = '${p.ts.year.toString().padLeft(4, '0')}-'
            '${p.ts.month.toString().padLeft(2, '0')}-'
            '${p.ts.day.toString().padLeft(2, '0')}';
        buf.writeln('- $iso: `${p.path}` — "${p.title}"');
      }
    }

    final out = buf.toString();
    if (!out.contains('### ')) return '';
    return out;
  }
}

class MonthlyReportResult {
  const MonthlyReportResult({
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

class _VetEntryWithFollowUp {
  const _VetEntryWithFollowUp({
    required this.entry,
    required this.reason,
    required this.followUpDate,
  });
  final Entry entry;
  final String? reason;
  final DateTime? followUpDate;
}
