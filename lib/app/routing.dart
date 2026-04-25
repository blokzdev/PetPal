import 'package:go_router/go_router.dart';

import 'screens/dev_screen.dart';
import 'screens/home_screen.dart';

GoRouter buildRouter() => GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => const HomeScreen(),
        ),
        // Phase 1 verification screen — exercises the full harness. Linked
        // from Home only in debug builds (see HomeScreen).
        GoRoute(
          path: '/dev',
          builder: (context, state) => const DevScreen(),
        ),
      ],
    );
