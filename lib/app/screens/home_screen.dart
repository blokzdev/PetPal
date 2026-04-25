import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pets = ref.watch(petsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('PetPal')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: pets.when(
            data: (list) =>
                list.isEmpty ? const _EmptyState() : _Greeting(pets: list),
            loading: () => const CircularProgressIndicator(),
            error: (e, _) => Text('Could not read pets: $e'),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.pets, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Text('PetPal', style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A memory agent for your pet.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => GoRouter.of(context).push('/pets/add'),
          icon: const Icon(Icons.add),
          label: const Text('Add your pet'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Open harness · dev screen'),
          ),
        ],
      ],
    );
  }
}

class _Greeting extends ConsumerWidget {
  const _Greeting({required this.pets});
  final List<dynamic> pets;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Free tier (DECISIONS row 8) — chat with the most recently-created pet.
    final pet = pets.last;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(Icons.pets, size: 72, color: scheme.primary),
        const SizedBox(height: 16),
        Text(pet.name as String, style: text.headlineMedium),
        const SizedBox(height: 8),
        Text(
          'A memory agent for your pet.',
          textAlign: TextAlign.center,
          style: text.bodyMedium,
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: () => GoRouter.of(context).push('/chat'),
          icon: const Icon(Icons.chat_bubble),
          label: Text('Chat with ${pet.name}'),
        ),
        if (kDebugMode) ...[
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => GoRouter.of(context).push('/dev'),
            icon: const Icon(Icons.science_outlined),
            label: const Text('Open harness · dev screen'),
          ),
        ],
      ],
    );
  }
}
