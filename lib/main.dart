import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/routing.dart';
import 'app/theme.dart';

void main() {
  runApp(const ProviderScope(child: PetPalApp()));
}

class PetPalApp extends StatelessWidget {
  const PetPalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'PetPal',
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      routerConfig: buildRouter(),
      debugShowCheckedModeBanner: false,
    );
  }
}
