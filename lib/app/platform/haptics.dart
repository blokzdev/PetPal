import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Tactile feedback abstraction. Wraps `HapticFeedback` from
/// `flutter/services` behind a small interface so tests can substitute
/// a counting fake — `HapticFeedback`'s static methods route through a
/// platform channel that's a no-op (and untestable) under
/// `flutter test`.
///
/// Task 5.8 wires `light()` at three completion points:
///
/// - chat layer, on a successful `write_wiki_entry` tool result
///   (the moment-of-save for a memory)
/// - reminders list, on swipe-to-dismiss confirming cancellation
///   (the user's "I've completed / no longer need this" gesture)
/// - add-reminder form, on successful schedule
///
/// Vocabulary lock: only `lightImpact` is wired in 5.8. Heavier impacts
/// and selection clicks are reserved so a tactile buzz consistently
/// means "something committed" — not "you tapped." (See task 5.7
/// chip-haptic decision.)
abstract class Haptics {
  void light();
}

class SystemHaptics implements Haptics {
  const SystemHaptics();

  @override
  void light() => HapticFeedback.lightImpact();
}

/// Default provider — production wiring. Tests override with a
/// [FakeHaptics] to assert call counts (or [NoOpHaptics] when the
/// haptic isn't relevant to the test's assertion).
final hapticsProvider = Provider<Haptics>((ref) => const SystemHaptics());

/// No-op stand-in. Use in non-widget tests (`test()` rather than
/// `testWidgets()`) where the binding isn't initialized so a call to
/// `HapticFeedback.lightImpact` would throw "Binding has not yet been
/// initialized."
@visibleForTesting
class NoOpHaptics implements Haptics {
  const NoOpHaptics();

  @override
  void light() {}
}

/// Counting fake. Use when a test wants to assert that a haptic
/// fired at the right moment (save-memory commit, reminder
/// schedule/cancel).
@visibleForTesting
class FakeHaptics implements Haptics {
  int lightCount = 0;

  @override
  void light() => lightCount++;
}
