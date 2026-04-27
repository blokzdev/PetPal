import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers.dart';
import '../widgets/app_scaffold.dart';

class WikiEntryScreen extends ConsumerWidget {
  const WikiEntryScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wikiAsync = ref.watch(wikiIoProvider);
    return AppScaffold(
      title: path.split('/').last,
      body: wikiAsync.when(
        data: (wiki) => FutureBuilder<String>(
          future: wiki.read(path),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return Center(child: Text('Could not read entry: ${snap.error}'));
            }
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: SelectableText(
                snap.data ?? '',
                style: const TextStyle(fontFamily: 'monospace'),
              ),
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Journal unavailable: $e')),
      ),
    );
  }
}
