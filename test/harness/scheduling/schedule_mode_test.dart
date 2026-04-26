import 'package:flutter_test/flutter_test.dart';
import 'package:petpal/harness/scheduling/schedule_mode.dart';

void main() {
  group('ScheduleMode (CLAUDE.md §8 / DECISIONS row 28)', () {
    test('all four modes round-trip through serialise / parseScheduleMode', () {
      for (final mode in ScheduleMode.values) {
        expect(parseScheduleMode(mode.serialise()), mode);
      }
    });

    test('canonical wire strings are stable — guard against accidental rename',
        () {
      // Stored as strings in `reminders.mode`; renaming any of these is
      // a database-on-disk break. If you genuinely need to change one,
      // ship a Drift migration.
      expect(ScheduleMode.notification.serialise(), 'notification');
      expect(ScheduleMode.script.serialise(), 'script');
      expect(ScheduleMode.synthesis.serialise(), 'synthesis');
      expect(ScheduleMode.synthesisNotify.serialise(), 'synthesisNotify');
    });

    test('parseScheduleMode rejects unknown input with ArgumentError', () {
      expect(
        () => parseScheduleMode('deterministic'),
        throwsA(isA<ArgumentError>()),
        reason:
            'pre-DECISIONS-row-28 value "deterministic" must not silently '
            'parse as notification — the schedule_reminder tool depends '
            'on rejecting unknown modes.',
      );
      expect(
        () => parseScheduleMode(''),
        throwsA(isA<ArgumentError>()),
      );
      expect(
        () => parseScheduleMode('NOTIFICATION'),
        throwsA(isA<ArgumentError>()),
        reason: 'parser is case-sensitive — wire form is camelCase enum-name',
      );
    });
  });
}
