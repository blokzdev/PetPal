import '../../data/repos/reminder_repo.dart';
import '../../platform/alarm_scheduler.dart';
import 'notification_template.dart';
import 'reminder_kinds.dart';
import 'reminder_scheduler.dart';
import 'schedule_mode.dart';

/// Result of [ReminderService.create] — the new reminder row id plus,
/// for `notification` mode, the alarm-arm result so the UI can decide
/// whether to surface the inexact-fallback banner. null means a non-
/// notification mode that doesn't have an alarm-arm result to share.
class CreateReminderResult {
  const CreateReminderResult({required this.id, this.armResult});
  final int id;
  final AlarmArmResult? armResult;
}

/// Per-kind result wrapper used by [ReminderService] internally to
/// hide whether the kind matched [ReminderKind] or fell through to a
/// generic body.
class _RenderedNotification {
  const _RenderedNotification({required this.title, required this.body});
  final String title;
  final String body;
}

/// One-stop facade for the create + arm + cancel flow. Exposed at
/// the harness layer because the orchestration is mode-driven (a
/// harness concept), not platform-driven. Sits on top of:
///
/// * [ReminderRepo] — DB row creation/lookup/deletion
/// * [ReminderScheduler] — picks AlarmScheduler vs WorkScheduler
/// * [NotificationTemplates] — renders title/body for known kinds
///
/// Used by both the agent's `schedule_reminder` tool (task 4.9) and
/// the user-facing reminders screen (task 4.10).
class ReminderService {
  ReminderService({
    required ReminderRepo repo,
    required ReminderScheduler scheduler,
    required NotificationTemplates templates,
    required Future<String?> Function(int petId) petNameLookup,
  })  : _repo = repo,
        _scheduler = scheduler,
        _templates = templates,
        _petName = petNameLookup;

  final ReminderRepo _repo;
  final ReminderScheduler _scheduler;
  final NotificationTemplates _templates;
  final Future<String?> Function(int) _petName;

  /// Create + arm. For `notification` mode, renders a template into
  /// the payload so the dispatcher's fire-time post is purely
  /// data-driven (no template lookup at fire time — pet-name changes
  /// don't propagate to existing reminders, accepted tradeoff for
  /// Phase 4).
  Future<CreateReminderResult> create({
    required int petId,
    required String kind,
    required DateTime when,
    ScheduleMode mode = ScheduleMode.notification,
  }) async {
    Map<String, Object?> payload = const {};
    if (mode == ScheduleMode.notification) {
      final rendered = await _renderForKind(petId: petId, kind: kind);
      payload = {'title': rendered.title, 'body': rendered.body};
    }

    final id = await _repo.create(
      petId: petId,
      kind: kind,
      whenTs: when,
      mode: mode,
      payload: payload,
    );
    final row = await _repo.getById(id);
    if (row == null) {
      // Should never happen — we just inserted. Return the id without
      // arming so the caller doesn't get a stale reference.
      return CreateReminderResult(id: id);
    }
    final armResult = await _scheduler.arm(row);
    return CreateReminderResult(id: id, armResult: armResult);
  }

  /// Cancel + delete. Cancels the platform trigger first so a delayed
  /// fire after delete can't no-op into a missing row.
  Future<void> cancel(int reminderId) async {
    final row = await _repo.getById(reminderId);
    if (row == null) return;
    await _scheduler.cancel(row);
    await _repo.delete(reminderId);
  }

  /// List for the active pet. Pass-through to [ReminderRepo.listForPet]
  /// so the agent tool surface is symmetric (one service, one set of
  /// methods) rather than splitting across two collaborators.
  Future<List<ReminderRow>> listForPet(int petId) =>
      _repo.listForPet(petId);

  Future<_RenderedNotification> _renderForKind({
    required int petId,
    required String kind,
  }) async {
    final petName = await _petName(petId) ?? 'your pet';
    final knownKind = ReminderKind.fromId(kind);
    if (knownKind != null) {
      final tpl = await _templates.load(knownKind);
      final rendered = tpl.render(petName: petName);
      return _RenderedNotification(title: rendered.title, body: rendered.body);
    }
    // Unknown kind from the agent — generic but pet-aware fallback.
    return _RenderedNotification(
      title: 'Reminder',
      body: 'Reminder for $petName',
    );
  }
}
