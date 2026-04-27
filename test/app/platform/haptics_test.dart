import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/app/platform/haptics.dart';

/// Task 5.8 — Haptics abstraction invariants. Production wiring
/// (SystemHaptics → HapticFeedback.lightImpact) is exercised on-device
/// and through `flutter_test`'s widget binding; the tests below pin
/// the testing seams (NoOpHaptics + FakeHaptics) since several non-
/// widget tests rely on them to substitute the platform channel.
void main() {
  test('NoOpHaptics.light is a no-op (does not throw without a binding)',
      () {
    const haptics = NoOpHaptics();
    expect(() => haptics.light(), returnsNormally);
  });

  test('FakeHaptics counts each light() call', () {
    final haptics = FakeHaptics();
    expect(haptics.lightCount, 0);
    haptics.light();
    haptics.light();
    haptics.light();
    expect(haptics.lightCount, 3);
  });
}
