import 'package:flutter/widgets.dart';

/// Spacing scale used everywhere in `lib/app/`. Five steps mapped to the
/// 4-pt grid Material 3 publishes — small enough to stay disciplined,
/// large enough to express hierarchy.
abstract final class Spacing {
  static const double xs = 4;
  static const double s = 8;
  static const double m = 16;
  static const double l = 24;
  static const double xl = 32;
}

abstract final class Insets {
  static const EdgeInsets xs = EdgeInsets.all(Spacing.xs);
  static const EdgeInsets s = EdgeInsets.all(Spacing.s);
  static const EdgeInsets m = EdgeInsets.all(Spacing.m);
  static const EdgeInsets l = EdgeInsets.all(Spacing.l);
  static const EdgeInsets xl = EdgeInsets.all(Spacing.xl);

  static const EdgeInsets hM = EdgeInsets.symmetric(horizontal: Spacing.m);
  static const EdgeInsets vM = EdgeInsets.symmetric(vertical: Spacing.m);
  static const EdgeInsets hL = EdgeInsets.symmetric(horizontal: Spacing.l);
}

abstract final class Gaps {
  static const SizedBox xs = SizedBox(height: Spacing.xs, width: Spacing.xs);
  static const SizedBox s = SizedBox(height: Spacing.s, width: Spacing.s);
  static const SizedBox m = SizedBox(height: Spacing.m, width: Spacing.m);
  static const SizedBox l = SizedBox(height: Spacing.l, width: Spacing.l);
  static const SizedBox xl = SizedBox(height: Spacing.xl, width: Spacing.xl);
}
