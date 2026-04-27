import 'package:flutter/animation.dart';

/// Motion durations — Material 3 standard scale (DECISIONS row 38). Hero
/// moments may selectively use [long]; everyday navigation should stay on
/// [short] / [medium].
abstract final class Motion {
  static const Duration short = Duration(milliseconds: 200);
  static const Duration medium = Duration(milliseconds: 300);
  static const Duration long = Duration(milliseconds: 500);

  /// Standard easing for surface transitions. `easeOutCubic` reads as
  /// "settles in" — well-suited to the memory-saved hero moment where
  /// the snackbar should land and rest, not bounce.
  static const Curve standardCurve = Curves.easeOutCubic;

  /// Used for entrances — slightly more anticipatory than the standard
  /// curve. Reserved for hero moments where a touch of personality is OK.
  static const Curve heroCurve = Curves.easeOutCirc;
}
