import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../platform/schedule_health.dart';
import '../../platform/settings_storage.dart';

/// SharedPrefs key — once set, the prompt never reappears.
const _seenKey = 'battery_exemption_prompt_seen';

/// First-schedule prompt walking the user through Android's
/// "ignore battery optimizations" toggle. Without it, Doze mode can
/// delay reminders indefinitely. We show this exactly once — the
/// first time the user creates a reminder — and only if the
/// permission is currently denied. Subsequent reminders never
/// re-prompt; the Reminders screen surfaces a banner if the
/// permission is later revoked, so the user always has a path back.
///
/// Per VOICE.md §5 this is a global modal — copy stays static, no
/// pet-name interpolation. Per VOICE.md §1 tone — direct, not
/// alarmist; treats the owner as an adult who can handle real
/// information.
class BatteryExemptionPrompt extends StatelessWidget {
  const BatteryExemptionPrompt({super.key, required this.health});

  final ScheduleHealthService health;

  static Future<void> maybeShow({
    required BuildContext context,
    required SettingsStorage settings,
    required ScheduleHealthService health,
  }) async {
    final seen = await settings.getBool(_seenKey) ?? false;
    if (seen) return;
    final snapshot = await health.check();
    if (snapshot.batteryOptimizationDisabled) {
      // Already exempted — record the flag so we never bother the
      // user later when they revisit a fresh device.
      await settings.setBool(_seenKey, true);
      return;
    }
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => BatteryExemptionPrompt(health: health),
    );
    await settings.setBool(_seenKey, true);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      icon: Icon(PhosphorIconsRegular.batteryWarning, color: scheme.primary),
      title: const Text('Let reminders fire on time'),
      content: const Text(
        'Android may delay reminders to save battery. To make sure '
        "PetPal's reminders fire when you set them, allow PetPal to "
        'run in the background.\n\n'
        "We'll open Settings — find PetPal in the list and tap "
        'Allow.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Not now'),
        ),
        FilledButton(
          onPressed: () async {
            await health.requestBatteryOptimizationExemption();
            if (!context.mounted) return;
            Navigator.of(context).pop();
          },
          child: const Text('Open settings'),
        ),
      ],
    );
  }
}
