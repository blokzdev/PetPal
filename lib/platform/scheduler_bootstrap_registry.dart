/// Process-global registry for the alarm/work-callback bootstrap
/// function. AlarmManager and WorkManager fire callbacks in a fresh
/// Dart isolate without our `ProviderScope`, so the callback's only
/// way to reach the dispatcher is through this registry — set once
/// at app startup in `main.dart` (production) or in a test's setUp
/// (unit tests).
///
/// Contract: the function takes a reminder id, looks the row up in
/// the database, and routes to the right engine via
/// `ReminderDispatcher.fire`. The registry is intentionally a
/// top-level mutable variable rather than a singleton class because
/// the alarm/work isolates have no persistent state of their own —
/// the variable is re-set on every isolate spawn.
library;

/// Currently-registered bootstrap function. Null until [setSchedulerBootstrap]
/// is called.
Future<void> Function(int reminderId)? schedulerBootstrap;

/// Register [fire] as the function the alarm/work callbacks should
/// invoke. Called from `main.dart` in production. Tests substitute a
/// fake by calling this in `setUp` and clearing it in `tearDown`.
void setSchedulerBootstrap(Future<void> Function(int reminderId) fire) {
  schedulerBootstrap = fire;
}

/// Clear the registry. Used in test `tearDown` to avoid bleed
/// between tests that install different fakes.
void clearSchedulerBootstrap() {
  schedulerBootstrap = null;
}
