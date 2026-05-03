import 'dart:math' as math;

import 'package:flutter/material.dart';

/// WCAG 2.1 relative luminance + contrast-ratio helpers.
///
/// Phase 7 task H.2.b — pure-Dart implementation so the contrast
/// assertions can run inside `flutter test` without spinning up the
/// full Material/`AccessibilityChecker` integration-test plumbing.
///
/// Reference: https://www.w3.org/TR/WCAG21/#dfn-relative-luminance
double relativeLuminance(Color c) {
  double channel(double v) {
    return v <= 0.03928
        ? v / 12.92
        : math.pow((v + 0.055) / 1.055, 2.4) as double;
  }

  return 0.2126 * channel(c.r) +
      0.7152 * channel(c.g) +
      0.0722 * channel(c.b);
}

/// WCAG 2.1 contrast ratio between two colors.
///
/// Returns a value in `[1.0, 21.0]`. AA body text requires ≥4.5; AA
/// large text (≥18pt or ≥14pt-bold) requires ≥3.0. AAA bumps those to
/// 7.0 and 4.5.
double wcagContrastRatio(Color a, Color b) {
  final la = relativeLuminance(a);
  final lb = relativeLuminance(b);
  final lighter = math.max(la, lb);
  final darker = math.min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}
