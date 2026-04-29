import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';

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

  /// Spring physics for app-wide motion polish (Phase 5.6 — DECISIONS
  /// row 50). Underdamped (damping ratio ≈ 0.82) — settles cleanly
  /// with one barely-visible oscillation that reads as "alive but
  /// composed." Stiffness 180, damping 22, mass 1 → settles in
  /// ~600 ms; the [springCurve] maps normalized `t ∈ [0,1]` over
  /// that settle window so `Curves.springCurve.transform(1.0)` is
  /// effectively rest position.
  ///
  /// Use [springDescription] when handing physics to API surfaces
  /// that want raw `SpringDescription` (e.g. flutter_animate's
  /// `.scale(curve: Motion.springCurve)` accepts a `Curve`, but the
  /// `Listener`-based `AnimationController.animateWith` path uses
  /// `SpringSimulation(springDescription, ...)`).
  static const SpringDescription springDescription = SpringDescription(
    mass: 1,
    stiffness: 180,
    damping: 22,
  );

  /// Curve adapter over [springDescription]. Suitable for any callsite
  /// taking a `Curve` (AnimatedSwitcher, AnimatedScale, AnimatedOpacity,
  /// CurvedAnimation, flutter_animate effect builders).
  static const Curve springCurve = _SpringCurve(springDescription);
}

/// Curve that evaluates a [SpringSimulation] from rest at 0 to 1.
/// Normalized time `t ∈ [0,1]` maps to simulation time in seconds via
/// the empirical settle window for [Motion.springDescription]
/// (~0.6 s for damping ratio ≈ 0.82). Past the settle window the
/// simulation is at rest at 1; clamp ensures the curve reads `1.0`
/// at `t == 1` (Flutter requires `transform(1.0) == 1.0`).
class _SpringCurve extends Curve {
  const _SpringCurve(this.description);
  final SpringDescription description;

  /// Normalized time → simulation seconds. Calibrated so the spring
  /// has settled (velocity < 0.001, x ≈ 1) by `t == 1`. Re-tuning the
  /// physics requires re-checking this constant — set high enough to
  /// avoid clipping the trailing oscillation, low enough to match
  /// Motion.long visually for hero callsites.
  static const double _settleSeconds = 0.6;

  @override
  double transformInternal(double t) {
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    final sim = SpringSimulation(description, 0, 1, 0);
    return sim.x(t * _settleSeconds);
  }
}
