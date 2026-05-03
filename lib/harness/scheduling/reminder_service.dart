import '../../app/entitlement/entitlement.dart';
import '../../app/entitlement/quota_exception.dart';
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
    Entitlement Function()? entitlementSource,
  })  : _repo = repo,
        _scheduler = scheduler,
        _templates = templates,
        _petName = petNameLookup,
        _entitlementSource = entitlementSource;

  final ReminderRepo _repo;
  final ReminderScheduler _scheduler;
  final NotificationTemplates _templates;
  final Future<String?> Function(int) _petName;

  /// Phase 7 task D.1 — pulls the active entitlement at create-time
  /// to enforce the 5-reminder free-tier cap. Optional so existing
  /// tests that don't care about quota can pass `null`; production
  /// wires this via the provider.
  final Entitlement Function()? _entitlementSource;

  /// Create + arm. For `notification` mode, renders a template into
  /// the payload so the dispatcher's fire-time post is purely
  /// data-driven (no template lookup at fire time — pet-name changes
  /// don't propagate to existing reminders, accepted tradeoff for
  /// Phase 4).
  ///
  /// Phase 7 task D.1 — throws [ReminderQuotaExceeded] when the
  /// entitlement caps reminders at 5 (free tier) and the pet
  /// already has 5. Pro + BYOK paths have `cap == null` and skip
  /// this gate. Existing tests pass `entitlementSource: null` and
  /// hit the no-gate path.
  Future<CreateReminderResult> create({
    required int petId,
    required String kind,
    required DateTime when,
    ScheduleMode mode = ScheduleMode.notification,
  }) async {
    final entSrc = _entitlementSource;
    if (entSrc != null) {
      final ent = entSrc();
      final cap = ent.reminderCap;
      if (cap != null) {
        final existing = await _repo.listForPet(petId);
        if (existing.length >= cap) {
          throw ReminderQuotaExceeded(ent);
        }
      }
    }

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
