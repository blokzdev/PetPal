import 'package:flutter/material.dart';

ThemeData buildLightTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF4F7CFF)),
      useMaterial3: true,
    );

ThemeData buildDarkTheme() => ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xFF4F7CFF),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    );
