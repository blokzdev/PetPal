/// Phase 8 task 8.3 — escalation resources per DECISIONS row 101.
/// Loaded from `assets/hazards/escalation.yaml` (US-first poison
/// control contacts; non-US locales degrade to a generic "Contact
/// your vet now" message).
///
/// **Numbers live in this asset, never in any LLM prompt** (row 101
/// lock — phone numbers in prompts are a hallucination surface; the
/// screener-rendered widget shows the asset value verbatim). The
/// canonical_copy + generic_suffix strings are also locked here so
/// the screener UI reads from one auditable source.
library;

import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

/// Per-contact poison-control entry. Every field is owner-auditable
/// and tested for non-emptiness (see
/// `test/harness/guardrails/escalation_resources_test.dart`).
class EscalationContact {
  const EscalationContact({
    required this.name,
    required this.phone,
    required this.notes,
    required this.verifiedAt,
    required this.source,
  });

  /// Display name, e.g. "ASPCA Animal Poison Control Center".
  final String name;

  /// Formatted phone number, e.g. "(888) 426-4435". Stored exactly
  /// as it should be displayed — the 8.4 UI does not reformat.
  final String phone;

  /// User-facing notes (e.g. "Available 24/7. A consultation fee may
  /// apply."). Short — fits under the phone number in the escalation
  /// surface.
  final String notes;

  /// ISO date string for the verification check. Updated whenever the
  /// number is re-verified against the source URL.
  final String verifiedAt;

  /// Canonical authoritative source the phone was verified from.
  /// Surfaced in audit logs; not user-facing.
  final String source;
}

/// Locked escalation copy + per-locale poison-control contacts.
class EscalationResources {
  const EscalationResources({
    required this.canonicalCopy,
    required this.genericSuffix,
    required this.locales,
  });

  /// The canonical "This may be hazardous — contact your vet or
  /// animal poison control now." copy from VOICE.md / row 100. The
  /// screener UI renders this verbatim.
  final String canonicalCopy;

  /// Fallback line for locales without specific poison-control
  /// entries (e.g. non-US). The 8.4 UI shows this in place of the
  /// contact list when [contactsFor] returns empty.
  final String genericSuffix;

  /// Locale code → contact list. Production keys are "US" and
  /// "default"; future locales add entries as their verification
  /// process completes.
  final Map<String, List<EscalationContact>> locales;

  /// Contacts for the requested [locale]. Falls back to the
  /// "default" locale (typically empty) when the locale is unknown.
  List<EscalationContact> contactsFor(String locale) {
    return locales[locale] ?? locales['default'] ?? const [];
  }
}

/// Source for the escalation resources. Production reads from the
/// Flutter asset bundle; tests inject an in-memory value (mirrors
/// the `notification_template.dart` Asset/InMemory split).
abstract class EscalationResourceSource {
  Future<EscalationResources> load();
}

class AssetEscalationResourceSource implements EscalationResourceSource {
  const AssetEscalationResourceSource();

  @override
  Future<EscalationResources> load() async {
    final raw = await rootBundle.loadString('assets/hazards/escalation.yaml');
    return parseEscalationYaml(raw);
  }
}

class InMemoryEscalationResourceSource implements EscalationResourceSource {
  const InMemoryEscalationResourceSource(this._resources);
  final EscalationResources _resources;

  @override
  Future<EscalationResources> load() async => _resources;
}

/// Parse the `assets/hazards/escalation.yaml` shape. Throws
/// [FormatException] on missing required keys. Unknown extra keys are
/// silently ignored (forward compatibility).
///
/// Exposed for tests that want to assert the asset YAML parses without
/// going through `rootBundle`.
EscalationResources parseEscalationYaml(String raw) {
  final parsed = loadYaml(raw);
  if (parsed is! Map) {
    throw const FormatException(
      'escalation.yaml: root must be a YAML map.',
    );
  }
  final canonicalCopy = parsed['canonical_copy'];
  final genericSuffix = parsed['generic_suffix'];
  final locales = parsed['locales'];
  if (canonicalCopy is! String || canonicalCopy.isEmpty) {
    throw const FormatException(
      'escalation.yaml: missing non-empty `canonical_copy`.',
    );
  }
  if (genericSuffix is! String || genericSuffix.isEmpty) {
    throw const FormatException(
      'escalation.yaml: missing non-empty `generic_suffix`.',
    );
  }
  if (locales is! Map) {
    throw const FormatException(
      'escalation.yaml: missing `locales:` map.',
    );
  }
  final parsedLocales = <String, List<EscalationContact>>{};
  for (final entry in locales.entries) {
    final localeKey = entry.key.toString();
    final localeBody = entry.value;
    if (localeBody is! Map) {
      throw FormatException(
        'escalation.yaml: locale `$localeKey` must be a YAML map.',
      );
    }
    final contactsRaw = localeBody['contacts'];
    if (contactsRaw is! List) {
      throw FormatException(
        'escalation.yaml: locale `$localeKey` needs `contacts:` as a list.',
      );
    }
    parsedLocales[localeKey] = [
      for (final c in contactsRaw) _parseContact(c, localeKey),
    ];
  }
  return EscalationResources(
    canonicalCopy: canonicalCopy.trim(),
    genericSuffix: genericSuffix.trim(),
    locales: parsedLocales,
  );
}

EscalationContact _parseContact(Object? raw, String localeKey) {
  if (raw is! Map) {
    throw FormatException(
      'escalation.yaml: locale `$localeKey` contact must be a YAML map.',
    );
  }
  final name = raw['name'];
  final phone = raw['phone'];
  final notes = raw['notes'];
  final verifiedAt = raw['verified_at'];
  final source = raw['source'];
  if (name is! String || name.isEmpty) {
    throw FormatException(
      'escalation.yaml: contact in locale `$localeKey` needs non-empty `name`.',
    );
  }
  if (phone is! String || phone.isEmpty) {
    throw FormatException(
      'escalation.yaml: contact `$name` needs non-empty `phone`.',
    );
  }
  if (verifiedAt is! String || verifiedAt.isEmpty) {
    throw FormatException(
      'escalation.yaml: contact `$name` needs non-empty `verified_at` '
      '(audit trail for the canonical-source verification check).',
    );
  }
  if (source is! String || source.isEmpty) {
    throw FormatException(
      'escalation.yaml: contact `$name` needs non-empty `source` URL.',
    );
  }
  return EscalationContact(
    name: name,
    phone: phone,
    notes: notes is String ? notes : '',
    verifiedAt: verifiedAt,
    source: source,
  );
}
