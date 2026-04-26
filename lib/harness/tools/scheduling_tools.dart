import 'dart:convert';

import '../agent/messages.dart';
import '../agent/tool_dispatcher.dart';
import '../guardrails/red_flag_screener.dart';
import '../scheduling/reminder_service.dart';
import '../scheduling/schedule_mode.dart';

/// Register the canonical scheduling + safety tools on [dispatcher]:
/// `schedule_reminder`, `list_reminders`, and `red_flag_check`. Each
/// tool closes over its repos / services so the agent loop only sees
/// JSON in/out (matching the wiki-tools pattern in
/// `lib/harness/tools/wiki_tools.dart`).
///
/// `schedule_reminder` defaults `mode` to `notification` when the LLM
/// omits it (the overwhelmingly common case — flea, heartworm, vaccine,
/// weight-check reminders) and rejects unknown modes with
/// [ArgumentError] rather than silently downgrading. See DECISIONS row
/// 28.
void registerSchedulingTools(
  ToolDispatcher dispatcher, {
  required ReminderService reminders,
  required RedFlagScreener screener,
  required int Function() activePetId,
}) {
  dispatcher.register(
    const ToolDefinition(
      name: 'schedule_reminder',
      description:
          'Schedule a reminder for the active pet. `kind` should be '
          'one of: flea_treatment, heartworm_dose, vaccine_due, '
          'weight_check (these have curated notification templates). '
          'Other strings are accepted with a generic fallback body.\n\n'
          '`when_iso` is the local-time ISO-8601 timestamp '
          '(`YYYY-MM-DDTHH:mm:ss`).\n\n'
          '`mode` defaults to `notification` (zero-token system '
          'notification, the common case). Other valid modes: `script` '
          '(zero-token Dart task), `synthesis` (LLM-backed journal '
          'entry). `synthesisNotify` is reserved for Phase 5+.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'kind': {'type': 'string'},
          'when_iso': {
            'type': 'string',
            'description':
                'ISO-8601 local-time stamp, e.g. `2026-05-26T09:00:00`.',
          },
          'mode': {
            'type': 'string',
            'enum': ['notification', 'script', 'synthesis'],
            'default': 'notification',
          },
        },
        'required': ['kind', 'when_iso'],
      },
    ),
    (input) async {
      final kind = input['kind'];
      if (kind is! String || kind.trim().isEmpty) {
        throw ArgumentError('schedule_reminder: `kind` must be a non-empty '
            'string.');
      }
      final whenRaw = input['when_iso'];
      if (whenRaw is! String) {
        throw ArgumentError(
            'schedule_reminder: `when_iso` must be an ISO-8601 string.');
      }
      final when = DateTime.parse(whenRaw);
      final modeRaw = input['mode'] as String? ?? 'notification';
      // Reject unknown modes rather than silently downgrade —
      // DECISIONS row 28.
      final mode = parseScheduleMode(modeRaw);

      final result = await reminders.create(
        petId: activePetId(),
        kind: kind,
        when: when,
        mode: mode,
      );
      return jsonEncode({
        'reminder_id': result.id,
        'kind': kind,
        'when_iso': when.toIso8601String(),
        'mode': mode.serialise(),
        if (result.armResult != null)
          'arm_result': result.armResult!.name,
      });
    },
  );

  dispatcher.register(
    const ToolDefinition(
      name: 'list_reminders',
      description:
          'List active reminders for the active pet, sorted by fire '
          'time ascending.',
      inputSchema: {
        'type': 'object',
        'properties': {},
      },
    ),
    (input) async {
      final rows = await reminders.listForPet(activePetId());
      return jsonEncode([
        for (final r in rows)
          {
            'reminder_id': r.id,
            'kind': r.kind,
            'when_iso': r.whenTs.toIso8601String(),
            'mode': r.mode.serialise(),
          },
      ]);
    },
  );

  dispatcher.register(
    const ToolDefinition(
      name: 'red_flag_check',
      description:
          'Run the red-flag screener over a list of symptom phrases. '
          'Returns the matched category id (e.g. `blood_in_stool`) or '
          'null. Useful when the model wants to second-guess the '
          'pre-screener — the deterministic check is what gates UI '
          'escalation.',
      inputSchema: {
        'type': 'object',
        'properties': {
          'symptoms': {
            'type': 'array',
            'items': {'type': 'string'},
            'description': 'Free-text symptom phrases. They are joined '
                'with newlines and matched against the same eleven '
                'categories the pre-screener uses.',
          },
        },
        'required': ['symptoms'],
      },
    ),
    (input) async {
      final raw = input['symptoms'];
      if (raw is! List) {
        throw ArgumentError(
            'red_flag_check: `symptoms` must be a JSON array of strings.');
      }
      final joined = raw.map((s) => s.toString()).join('\n');
      final match = screener.screen(joined);
      return jsonEncode({
        'flagged': match != null,
        if (match != null) ...{
          'category': match.category.id,
          'summary': match.category.aiSummary,
        },
      });
    },
  );
}
