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

# Phase 5.6 on-device verification surfaced a P0 release-only crash
# (Bug 3 — `JNI DETECTED ERROR IN APPLICATION: java_class == null`,
# pending exception `ClassNotFoundException: ai.onnxruntime.TensorInfo`).
# The flutter_onnxruntime plugin (v1.7.0) bundles
# `com.microsoft.onnxruntime:onnxruntime-android:1.22.0` whose
# native libonnxruntime.so calls JNI `FindClass("ai/onnxruntime/...")`
# from convertToTensorInfo / Java_ai_onnxruntime_OrtSession_run.
# AGP 8.x's release pipeline runs R8 with obfuscation by default
# (visible in the crash log's `h1.a.onMethodCall` / `x0.e.i` /
# `o1.c.run` obfuscated names), so the renamed Java classes can't
# be found by their original string names from native code. Neither
# the plugin nor the upstream Microsoft AAR ships a
# `consumer-rules.pro` to propagate the keep rule, so we land it at
# the app level. The blanket `**` is intentional — every class +
# method on the ai.onnxruntime surface is a JNI candidate.
-keep class ai.onnxruntime.** { *; }
-keepclassmembers class ai.onnxruntime.** { *; }
# Plugin's Kotlin glue is also reflectively dispatched via the
# Flutter method channel; keep its public entry points.
-keep class com.masicai.flutteronnxruntime.** { *; }
