import 'package:drift/drift.dart' as drift;

import '../db/database.dart';
import '../soul_file.dart';
import '../wiki_io.dart';

/// One weight observation — the parsed `weight_kg:` value out of a
/// type=weight entry's frontmatter, plus the entry's timestamp.
class WeightObservation {
  const WeightObservation({required this.ts, required this.kg});
  final DateTime ts;
  final double kg;
}

/// One symptom-frequency bucket — a known symptom keyword and the
/// count of entries that match it. Lives in calendar-month time
/// buckets in v1; counts across all-time for the SOUL profile chart
/// since most users have at most a few months of journal at v1
/// launch.
class SymptomFrequency {
  const SymptomFrequency({required this.label, required this.count});
  final String label;
  final int count;
}

/// Phase 6 task 6.12 — Read-only repository for trend charts on the
/// SOUL profile.
///
/// **Weight observations** — scans all `type=weight` entries for the
/// pet, reads each entry's body, and parses the `weight_kg:` field
/// from its frontmatter. Entries without a `weight_kg:` field are
/// skipped (the user may have written a freeform weight note without
/// a structured value; the chart shows what it can).
///
/// **Symptom frequency** — runs FTS5 MATCH queries over the pet's
/// journal for a small fixed set of known symptom keywords. Returns
/// each keyword's hit count, sorted descending. Per CLAUDE.md §10's
/// chat-only screener constraint, this is **not** the same code path
/// as the red-flag screener — it's a lighter keyword index that won't
/// produce false-positives on retrospective journaling because nothing
/// here gates an LLM call or surfaces a vet-escalation badge; the
/// chart just visualises "what concerns has the user written about
/// recently."
class TrendsRepo {
  TrendsRepo({required AppDatabase db, required WikiIo wiki})
      : _db = db,
        _wiki = wiki;

  final AppDatabase _db;
  final WikiIo _wiki;

  /// Locked symptom keyword set — five common owner-flagged concerns
  /// across dog/cat/rabbit-class pets. Each pair is a label + the
  /// FTS5 query string that catches it. The query strings use FTS5
  /// prefix syntax (`vomit*` matches "vomit", "vomiting", "vomited")
  /// joined OR-style across synonyms. Adding new keywords requires a
  /// fixture in [SymptomFrequency] tests.
  static const Map<String, String> symptomKeywords = {
    'Vomiting': 'vomit* OR threw OR throwing OR puk*',
    'Diarrhea': 'diarr* OR stool',
    'Lethargy': 'lethargic OR listless OR tired OR exhausted',
    'Scratching': 'scratch* OR itch*',
    'Limping': 'limp* OR lame OR favouring OR favoring',
  };

  /// Returns weight observations for [petId], ordered by timestamp
  /// ascending. Entries without a parseable `weight_kg:` field are
  /// silently skipped — the chart degrades gracefully when weight
  /// data is partial.
  Future<List<WeightObservation>> weightHistory(int petId) async {
    final rows = await (_db.select(_db.entries)
          ..where((e) => e.petId.equals(petId) & e.type.equals('weight'))
          ..orderBy([(e) => drift.OrderingTerm.asc(e.ts)]))
        .get();
    final result = <WeightObservation>[];
    for (final row in rows) {
      try {
        final body = await _wiki.read(row.path);
        final parsed = parseSoul(body);
        final raw = parsed.frontmatter['weight_kg'];
        final kg = _parseDouble(raw);
        if (kg == null) continue;
        result.add(WeightObservation(ts: row.ts, kg: kg));
      } catch (_) {
        // File missing / unparseable — skip; the chart shows what
        // it can find.
      }
    }
    return result;
  }

  /// Returns symptom-frequency hits for [petId], descending by
  /// count. Always returns one row per [symptomKeywords] entry,
  /// including 0-count rows so the chart can render an "all clear"
  /// state without a separate code path.
  Future<List<SymptomFrequency>> symptomFrequencies(int petId) async {
    final result = <SymptomFrequency>[];
    for (final entry in symptomKeywords.entries) {
      final rows = await _db.customSelect(
        '''
        SELECT COUNT(*) AS c
        FROM entries_fts5
        JOIN entries e ON e.id = entries_fts5.rowid
        WHERE entries_fts5 MATCH ?
          AND e.pet_id = ?
        ''',
        variables: [
          drift.Variable<String>(entry.value),
          drift.Variable<int>(petId),
        ],
      ).get();
      final count = rows.isEmpty ? 0 : rows.single.read<int>('c');
      result.add(SymptomFrequency(label: entry.key, count: count));
    }
    result.sort((a, b) => b.count.compareTo(a.count));
    return result;
  }

  /// Tolerant numeric parser. The frontmatter may have stored the
  /// weight as a YAML number (double / int), as a string ("14.2"),
  /// or as a unit-suffixed string ("14.2kg"). Returns null when the
  /// value can't be parsed as a finite positive number.
  static double? _parseDouble(Object? raw) {
    if (raw == null) return null;
    if (raw is num) {
      final d = raw.toDouble();
      return d.isFinite && d > 0 ? d : null;
    }
    if (raw is String) {
      final cleaned = raw.replaceAll(RegExp(r'[^0-9.\-]'), '');
      final d = double.tryParse(cleaned);
      if (d == null || !d.isFinite || d <= 0) return null;
      return d;
    }
    return null;
  }
}
