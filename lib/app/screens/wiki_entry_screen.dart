import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/wiki_repo.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';

/// Convert a wiki entry path into a user-facing AppBar title. Per
/// VOICE.md §3 + §4: the literal filename ("2026-04-25-carrot-trial.md")
/// exposes the file-system mechanic; we render a humane title instead.
/// Digest entries collapse to the locked vocabulary "Weekly summary"
/// (VOICE.md §6 example 5).
String _humanEntryTitle(String path) {
  final parsed = parseEntryPath(path);
  if (parsed == null) return 'Memory';
  if (parsed.type == 'digest') return 'Weekly summary';
  final t = parsed.title.trim();
  if (t.isEmpty) return 'Memory';
  return '${t[0].toUpperCase()}${t.substring(1)}';
}

class WikiEntryScreen extends ConsumerWidget {
  const WikiEntryScreen({super.key, required this.path});
  final String path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wikiAsync = ref.watch(wikiIoProvider);
    return AppScaffold(
      title: _humanEntryTitle(path),
      body: wikiAsync.when(
        data: (wiki) => FutureBuilder<String>(
          future: wiki.read(path),
          builder: (context, snap) {
            if (snap.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snap.hasError) {
              return const Center(
                child: Text("Couldn't load this entry."),
              );
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
        error: (e, _) => const Center(
          child: Text("Couldn't open the journal."),
        ),
      ),
    );
  }
}
