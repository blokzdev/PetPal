import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/entitlement/entitlement.dart';
import 'package:petpal/app/entitlement/quota_exception.dart';

/// Phase 7 task D.1 — QuotaExceededException sealed class.
///
/// Pins the discriminator (`kind`) for each subtype + the
/// entitlement carry-through. Paywall dispatcher / settings
/// scrolls to the right ladder based on `kind`.
void main() {
  final ent = Entitlement.freeAnonymous();

  test('TextQuotaExceeded.kind = text', () {
    expect(TextQuotaExceeded(ent).kind, 'text');
  });

  test('VisionQuotaExceeded.kind = vision', () {
    expect(VisionQuotaExceeded(ent).kind, 'vision');
  });

  test('ReminderQuotaExceeded.kind = reminder', () {
    expect(ReminderQuotaExceeded(ent).kind, 'reminder');
  });

  test('PetQuotaExceeded.kind = pet', () {
    expect(PetQuotaExceeded(ent).kind, 'pet');
  });

  test('SyncQuotaExceeded.kind = sync', () {
    expect(SyncQuotaExceeded(ent).kind, 'sync');
  });

  test('all subtypes carry the triggering entitlement', () {
    final pro = Entitlement(
      state: EntitlementState.proMonthly,
      userId: 'u',
      counterPeriodStart: DateTime(2026, 5),
    );
    expect(TextQuotaExceeded(pro).entitlement, pro);
    expect(VisionQuotaExceeded(pro).entitlement, pro);
    expect(ReminderQuotaExceeded(pro).entitlement, pro);
    expect(PetQuotaExceeded(pro).entitlement, pro);
    expect(SyncQuotaExceeded(pro).entitlement, pro);
  });

  test('toString includes the kind and state for log-grep ergonomics', () {
    final s = TextQuotaExceeded(ent).toString();
    expect(s, contains('text'));
    expect(s, contains('freeAnonymous'));
  });

  test('all subtypes are pattern-matchable on the sealed parent', () {
    QuotaExceededException pickKind(QuotaExceededException e) =>
        switch (e) {
          TextQuotaExceeded() => e,
          VisionQuotaExceeded() => e,
          ReminderQuotaExceeded() => e,
          PetQuotaExceeded() => e,
          SyncQuotaExceeded() => e,
        };

    expect(pickKind(TextQuotaExceeded(ent)).kind, 'text');
    expect(pickKind(VisionQuotaExceeded(ent)).kind, 'vision');
    expect(pickKind(ReminderQuotaExceeded(ent)).kind, 'reminder');
    expect(pickKind(PetQuotaExceeded(ent)).kind, 'pet');
    expect(pickKind(SyncQuotaExceeded(ent)).kind, 'sync');
  });
}
