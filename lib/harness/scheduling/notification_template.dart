import 'package:flutter/services.dart' show rootBundle;
import 'package:yaml/yaml.dart';

import 'reminder_kinds.dart';

/// One rendered notification — title + body, both substituted with
/// the active pet's name (per VOICE.md §5 — per-pet body interpolates).
/// Ready to drop into `flutter_local_notifications.show()`.
class NotificationTemplate {
  const NotificationTemplate({required this.title, required this.body});

  final String title;
  final String body;

  /// Substitute `{pet_name}` placeholders in the template body. Title
  /// stays static (per VOICE.md — global notification surface; the
  /// per-pet detail lives in body).
  NotificationTemplate render({required String petName}) {
    return NotificationTemplate(
      title: title,
      body: body.replaceAll('{pet_name}', petName),
    );
  }
}

/// Source of notification templates. Production reads from Flutter
/// assets; tests inject an in-memory map so they don't need a Flutter
/// binding.
abstract class NotificationTemplates {
  Future<NotificationTemplate> load(ReminderKind kind);
}

class AssetNotificationTemplates implements NotificationTemplates {
  const AssetNotificationTemplates();

  @override
  Future<NotificationTemplate> load(ReminderKind kind) async {
    final raw = await rootBundle.loadString(
      'assets/reminders/${kind.id}.yaml',
    );
    final parsed = loadYaml(raw);
    if (parsed is! Map) {
      throw FormatException(
        'Reminder template ${kind.id} did not parse as a YAML map.',
      );
    }
    final title = parsed['title'];
    final body = parsed['body'];
    if (title is! String || body is! String) {
      throw FormatException(
        'Reminder template ${kind.id} must declare string `title:` and '
        '`body:` keys.',
      );
    }
    return NotificationTemplate(title: title, body: body);
  }
}

/// In-memory [NotificationTemplates] for tests.
class InMemoryNotificationTemplates implements NotificationTemplates {
  InMemoryNotificationTemplates(this._templates);
  final Map<ReminderKind, NotificationTemplate> _templates;

  @override
  Future<NotificationTemplate> load(ReminderKind kind) async {
    final t = _templates[kind];
    if (t == null) throw StateError('no template for ${kind.id}');
    return t;
  }
}
