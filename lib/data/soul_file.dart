import 'package:yaml/yaml.dart';

/// Parsed view of a SOUL.md: the YAML frontmatter map and the markdown body
/// after it. The body intentionally retains its original whitespace so a
/// round-trip leaves it byte-identical (modulo emitted frontmatter ordering).
class ParsedSoul {
  ParsedSoul({required this.frontmatter, required this.body});
  final Map<String, Object?> frontmatter;
  final String body;
}

/// Parse a SOUL.md. Recognises the canonical CLAUDE.md §5 layout:
///
///     ---
///     <yaml frontmatter>
///     ---
///     <markdown body>
///
/// Files without leading `---` are treated as body-only (frontmatter empty).
ParsedSoul parseSoul(String text) {
  final lines = text.split('\n');
  if (lines.isEmpty || lines.first.trim() != '---') {
    return ParsedSoul(frontmatter: const {}, body: text);
  }
  // Find the closing `---`.
  var closeAt = -1;
  for (var i = 1; i < lines.length; i++) {
    if (lines[i].trim() == '---') {
      closeAt = i;
      break;
    }
  }
  if (closeAt < 0) {
    // Malformed — no closing marker. Treat as body-only.
    return ParsedSoul(frontmatter: const {}, body: text);
  }
  final frontmatterText = lines.sublist(1, closeAt).join('\n');
  final body = lines.sublist(closeAt + 1).join('\n');
  final fm = _yamlToMap(loadYaml(frontmatterText));
  return ParsedSoul(frontmatter: fm, body: body);
}

/// Re-emit a SOUL.md from a frontmatter map and body string. Keys are
/// emitted in [keyOrder] first (when present), then any remaining keys
/// in insertion order — matching the canonical layout in CLAUDE.md §5.
///
/// The default [keyOrder] is the canonical SOUL key order locked at
/// DECISIONS row 45 + 5.5.5: identity (`category, species, variety,
/// breed`), classification (`sex, neutered, relationship, working_role,
/// rehab_context, care_context`), lifecycle dates (`dob, dob_approx,
/// adoption_date, intake_date, expected_release_date`), then the
/// existing `weight_kg, allergies, meds, vet_contact, temperament`
/// block. Category-specific extension keys (e.g. `hay_type`,
/// `tank_litres`, `enclosure_size`) trail by virtue of not appearing
/// in [keyOrder] — they fall through to insertion order.
String serializeSoul({
  required Map<String, Object?> frontmatter,
  required String body,
  List<String> keyOrder = const [
    'category',
    'species',
    'variety',
    'breed',
    'sex',
    'neutered',
    'relationship',
    'working_role',
    'rehab_context',
    'care_context',
    'dob',
    'dob_approx',
    'adoption_date',
    'intake_date',
    'expected_release_date',
    'weight_kg',
    'allergies',
    'meds',
    'vet_contact',
    'temperament',
  ],
}) {
  final ordered = <String, Object?>{};
  for (final k in keyOrder) {
    if (frontmatter.containsKey(k)) ordered[k] = frontmatter[k];
  }
  for (final entry in frontmatter.entries) {
    if (!ordered.containsKey(entry.key)) ordered[entry.key] = entry.value;
  }

  final buf = StringBuffer('---\n');
  for (final entry in ordered.entries) {
    buf
      ..write(entry.key)
      ..write(': ')
      ..writeln(_emitValue(entry.value));
  }
  buf.write('---\n');
  if (!body.startsWith('\n')) buf.write('\n');
  buf.write(body);
  return buf.toString();
}

/// Merge [patch] into [base], **replacing** lists rather than concatenating
/// them — the agent's intent is "set allergies to [chicken, beef]", not
/// "append beef to existing allergies".
Map<String, Object?> mergeFrontmatter(
  Map<String, Object?> base,
  Map<String, Object?> patch,
) {
  final out = Map<String, Object?>.of(base);
  for (final entry in patch.entries) {
    out[entry.key] = entry.value;
  }
  return out;
}

// ─── helpers ────────────────────────────────────────────────────────────────

Map<String, Object?> _yamlToMap(Object? yaml) {
  if (yaml is YamlMap) {
    return {
      for (final entry in yaml.entries)
        entry.key.toString(): _normalize(entry.value),
    };
  }
  if (yaml is Map) {
    return {
      for (final entry in yaml.entries)
        entry.key.toString(): _normalize(entry.value),
    };
  }
  return const {};
}

Object? _normalize(Object? v) {
  if (v is YamlList) return [for (final e in v) _normalize(e)];
  if (v is YamlMap) return _yamlToMap(v);
  return v;
}

String _emitValue(Object? v) {
  if (v == null) return '';
  if (v is String) {
    // Quote when ambiguous (contains special chars, leading/trailing space,
    // or looks like a YAML scalar of another type).
    return _shouldQuote(v) ? "'${_escapeQuoted(v)}'" : v;
  }
  if (v is num || v is bool) return v.toString();
  if (v is List) {
    return '[${v.map(_emitValue).join(', ')}]';
  }
  // Fall back to a stringified form for unsupported types.
  return v.toString();
}

bool _shouldQuote(String s) {
  if (s.isEmpty) return true;
  if (s.trim() != s) return true;
  if (RegExp(r'[:#,\[\]\{\}&\*!\|>%@`"]').hasMatch(s)) return true;
  // Don't quote bare values that are clearly identifiers / words / dates.
  return false;
}

String _escapeQuoted(String s) => s.replaceAll("'", "''");
