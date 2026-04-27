import 'package:flutter/material.dart';

import 'design/design.dart';

/// Public theme entry points. Implementations live in
/// `lib/app/design/` — this file is the stable import surface for
/// `main.dart` and any future test/widget callsite.
ThemeData buildLightTheme() => buildPetPalLightTheme();

ThemeData buildDarkTheme() => buildPetPalDarkTheme();
