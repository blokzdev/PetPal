import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repos/wiki_repo.dart';
import '../../data/soul_file.dart';
import '../design/design.dart';
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

/// Builds the markdown style sheet that maps GFM elements onto
/// PetPal's design tokens. Source Serif 4 on body headings (the
/// journal aesthetic), Inter for paragraphs / lists / inline; bold
/// resolves to semibold (weight 600) per the variable-font rule
/// in PetPalTypography. Pre-Phase-6 polish — replaces the raw
/// monospace SelectableText render.
MarkdownStyleSheet _entryMarkdownStyle(BuildContext context) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final textTheme = theme.textTheme;
  return MarkdownStyleSheet.fromTheme(theme).copyWith(
    // Body headings render in Source Serif 4 — same family as the
    // journal entry / weekly summary titles. Sizes step down from
    // the AppBar title (which already names the entry); body
    // headings are section breaks within the entry, not page titles.
    h1: JournalText.entryTitle(color: scheme.onSurface),
    h2: JournalText.entryTitle(color: scheme.onSurface).copyWith(
      fontSize: 20,
    ),
    h3: textTheme.titleMedium,
    h4: textTheme.titleSmall,
    h5: textTheme.titleSmall,
    h6: textTheme.titleSmall,
    // Body / inline runs in Inter via the M3 textTheme.
    p: textTheme.bodyMedium,
    em: textTheme.bodyMedium?.copyWith(fontStyle: FontStyle.italic),
    // **bold** → semibold, per the typography lock in DECISIONS row 35
    // (variable-axis weights).
    strong: textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.w600,
      fontVariations: const [FontVariation('wght', 600)],
    ),
    listBullet: textTheme.bodyMedium,
    listIndent: Spacing.l,
    // Code spans + blocks: monospace, slightly smaller, with a
    // surfaceContainer chip background so they read as "literal
    // string" inside flowing prose.
    code: textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      fontSize: 13,
      backgroundColor: scheme.surfaceContainer,
    ),
    codeblockDecoration: BoxDecoration(
      color: scheme.surfaceContainer,
      borderRadius: Corners.s,
    ),
    codeblockPadding: Insets.s,
    // Blockquote — sage-tinted left border + slightly muted text,
    // mirrors the journal-aesthetic "pulled quote" treatment.
    blockquoteDecoration: BoxDecoration(
      border: Border(
        left: BorderSide(color: scheme.primary, width: 3),
      ),
    ),
    blockquotePadding: const EdgeInsets.only(left: Spacing.m),
    blockquote: textTheme.bodyMedium?.copyWith(
      color: scheme.onSurface.withValues(alpha: 0.85),
      fontStyle: FontStyle.italic,
    ),
    // Block spacing — slightly looser than the M3 default so the
    // entry reads like a journal page, not a dense doc.
    h1Padding: const EdgeInsets.only(top: Spacing.l, bottom: Spacing.s),
    h2Padding: const EdgeInsets.only(top: Spacing.m, bottom: Spacing.s),
    pPadding: const EdgeInsets.only(bottom: Spacing.s),
    blockSpacing: Spacing.s,
  );
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
            // Pre-Phase-6 polish — strip YAML frontmatter (`---`
            // header) before rendering so the entry body reads as
            // markdown, not a raw file dump. parseSoul handles
            // both presence and absence of frontmatter; if the
            // file is body-only it returns the body as-is.
            final raw = snap.data ?? '';
            final body = parseSoul(raw).body.trimLeft();
            return Markdown(
              data: body,
              selectable: true,
              styleSheet: _entryMarkdownStyle(context),
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
