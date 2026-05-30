import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/guardrails/food_hazard_escalation.dart';

/// Phase 8 task 8.3 — asserts the locked DECISIONS row 101 contract
/// for `assets/hazards/escalation.yaml`:
///   - canonical_copy matches the locked VOICE.md/row 100 phrasing
///     verbatim
///   - US locale has both ASPCA APCC + Pet Poison Helpline
///   - ASPCA number is the locked (888) 426-4435 (row 101 fixed at
///     2026-05-30; refresh only with a documented re-verify)
///   - Both US contacts have verified_at + source URL (audit trail
///     for the canonical-source verification check)
///   - default locale has empty contacts (degrades to generic_suffix
///     for non-US)

const _kAssetPath = 'assets/hazards/escalation.yaml';

String _readAsset() => File(_kAssetPath).readAsStringSync();

void main() {
  group('Phase 8 task 8.3 — escalation.yaml contract', () {
    final resources = parseEscalationYaml(_readAsset());

    test('canonical_copy matches DECISIONS row 100/101 lock verbatim', () {
      expect(
        resources.canonicalCopy,
        'This may be hazardous — contact your vet or animal poison '
        'control now.',
      );
    });

    test('generic_suffix is the conservative non-US fallback', () {
      expect(resources.genericSuffix, 'Contact your vet now.');
    });

    test('US locale has both poison-control contacts', () {
      final usContacts = resources.contactsFor('US');
      expect(usContacts, hasLength(2));
      final names = usContacts.map((c) => c.name).toList();
      expect(names, contains('ASPCA Animal Poison Control Center'));
      expect(names, contains('Pet Poison Helpline'));
    });

    test('ASPCA APCC phone is the DECISIONS row 101 locked number '
        '(888) 426-4435', () {
      final aspca = resources
          .contactsFor('US')
          .firstWhere((c) => c.name == 'ASPCA Animal Poison Control Center');
      expect(aspca.phone, '(888) 426-4435');
    });

    test('Pet Poison Helpline has a non-placeholder verified phone '
        '(verified at implementation per row 101)', () {
      final pph = resources
          .contactsFor('US')
          .firstWhere((c) => c.name == 'Pet Poison Helpline');
      expect(pph.phone, isNotEmpty);
      expect(pph.phone, isNot(contains('FETCH')),
          reason: 'phone must be verified live, not left as a '
              'placeholder — see DECISIONS row 101');
      expect(pph.phone, matches(RegExp(r'^\(\d{3}\) \d{3}-\d{4}$')),
          reason: 'phone format: (XXX) XXX-XXXX');
    });

    test('every US contact carries verified_at + source URL', () {
      for (final contact in resources.contactsFor('US')) {
        expect(contact.verifiedAt, isNotEmpty,
            reason: '${contact.name} missing verified_at');
        expect(contact.verifiedAt, matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')),
            reason: '${contact.name} verified_at must be ISO date');
        expect(contact.source, isNotEmpty,
            reason: '${contact.name} missing source URL');
        expect(contact.source, startsWith('https://'),
            reason: '${contact.name} source must be HTTPS URL');
      }
    });

    test('default locale has empty contacts (degrades to generic_suffix)',
        () {
      expect(resources.contactsFor('default'), isEmpty);
    });

    test('contactsFor unknown locale falls back to default', () {
      // 'CA', 'GB', etc — no entry yet, so degrade to default.
      expect(resources.contactsFor('CA'), isEmpty);
      expect(resources.contactsFor('GB'), isEmpty);
    });

    test('parseEscalationYaml rejects missing canonical_copy', () {
      const malformed = '''
generic_suffix: "Contact your vet now."
locales:
  default:
    contacts: []
''';
      expect(
        () => parseEscalationYaml(malformed),
        throwsA(isA<FormatException>()),
      );
    });

    test('parseEscalationYaml rejects a contact with missing verified_at',
        () {
      const malformed = '''
canonical_copy: "x"
generic_suffix: "y"
locales:
  US:
    contacts:
      - name: "Test Contact"
        phone: "(555) 555-5555"
        source: "https://example.com"
  default:
    contacts: []
''';
      expect(
        () => parseEscalationYaml(malformed),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
