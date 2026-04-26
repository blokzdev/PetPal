# Phase 4 ProGuard / R8 keep rules for the scheduling stack
# (DECISIONS row 30). Minification is off by default in Phase 4
# debug builds, but Phase 6 turns it on for release; pre-emptive
# rules avoid debugging shrink-wrap surprises later.

# WorkManager fires callbacks reflectively into a Dart entry-point
# function. R8 must NOT strip the dispatcher's plugin glue; without
# this rule, release builds silently no-op every script /
# synthesis reminder.
-keep class be.tramckrijte.workmanager.** { *; }
-keepclassmembers class be.tramckrijte.workmanager.** { *; }

# AlarmManager fires `alarmCallback` likewise. The Dart entry-point
# annotation `@pragma('vm:entry-point')` is honoured by the Flutter
# build pipeline, but the surrounding plugin classes need an
# explicit keep so R8 doesn't strip the bridge.
-keep class dev.fluttercommunity.plus.androidalarmmanager.** { *; }

# flutter_local_notifications uses reflective lookups for action
# callbacks (notification taps, dismissals) — keep the public entry
# points intact.
-keep class com.dexterous.** { *; }
-keepclassmembers class com.dexterous.** { *; }

# Drift (and friends) generate code that's referenced by string
# names from runtime — minor risk of being stripped. Conservative
# keep until Phase 6 verifies a tighter rule set.
-keep class com.simolus3.** { *; }
