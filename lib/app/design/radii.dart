import 'package:flutter/widgets.dart';

/// Corner radii — PetPal-warmer rounded scale (DECISIONS row 38). Slightly
/// more generous than Material 3 defaults; small chips and CTAs use the
/// full pill via [pill] (StadiumBorder territory). The rounding is part of
/// the soft-modern visual identity locked in row 35.
abstract final class Radii {
  static const double xs = 8;
  static const double s = 12;
  static const double m = 16;
  static const double l = 24;

  /// Sentinel for full-pill / StadiumBorder rounding. Components that
  /// want a stadium (chips, small CTAs) read this and use a [StadiumBorder]
  /// rather than a fixed radius.
  static const double pill = -1;
}

abstract final class Corners {
  static const BorderRadius xs = BorderRadius.all(Radius.circular(Radii.xs));
  static const BorderRadius s = BorderRadius.all(Radius.circular(Radii.s));
  static const BorderRadius m = BorderRadius.all(Radius.circular(Radii.m));
  static const BorderRadius l = BorderRadius.all(Radius.circular(Radii.l));
}
