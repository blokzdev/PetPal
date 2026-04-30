import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/repos/wiki_repo.dart';
import '../../data/soul_file.dart';
import '../../data/wiki_io.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/red_flag_badge.dart';

/// Convert a wiki entry path into a user-facing AppBar title. Per
/// VOICE.md §3 + §4: the literal filename ("2026-04-25-carrot-trial.md")
/// exposes the file-system mechanic; we render a humane title instead.
/// Digest entries collapse to the locked vocabulary "Weekly summary"
/// (VOICE.md §6 example 5). Photo entries are titled "Memory" since
/// the sidecar's caption is the body, not the path-derived slug
/// (photo paths use UUIDs, not the `&lt;date&gt;-&lt;slug&gt;` shape).
String _humanEntryTitle(String path) {
  final parsed = parseEntryPath(path);
  if (parsed == null) {
    // Photo paths fall here: `wiki/<petId>/photos/<id>.md`. The
    // viewer renders the caption inline as the title-feeling
    // affordance; the AppBar title stays "Memory".
    if (RegExp(r'^wiki/\d+/photos/[^/]+\.md$').hasMatch(path)) {
      return 'Memory';
    }
    return 'Memory';
  }
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
            // Phase 6 task 6.3 — type-dispatch on the sidecar's
            // frontmatter. `type: photos` renders the photo viewer
            // (full-size image + structured fields + caption);
            // everything else falls through to the markdown render
            // path landed pre-Phase 6.
            final raw = snap.data ?? '';
            final parsed = parseSoul(raw);
            final type = parsed.frontmatter['type'];
            if (type == 'photos') {
              return _PhotoEntryView(
                wiki: wiki,
                sidecarPath: path,
                frontmatter: parsed.frontmatter,
                body: parsed.body.trimLeft(),
              );
            }
            return Markdown(
              data: parsed.body.trimLeft(),
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

/// Phase 6 task 6.3 — photo entry viewer. Reads the sidecar's
/// `image:` filename, resolves the binary path (sibling of the
/// sidecar), renders the image at full width (BoxFit.contain so
/// portrait shots aren't cropped) plus the structured frontmatter
/// fields PetPal cares about and the freeform caption body.
///
/// The structured-field section is additive — fields landed in 6.1
/// (ts, byte_size) always render; fields the 6.5 extractor adds
/// (setting, activity, demeanor, notable_objects, enrichment_hints,
/// red_flag_match) render only when present. No empty rows.
class _PhotoEntryView extends StatelessWidget {
  const _PhotoEntryView({
    required this.wiki,
    required this.sidecarPath,
    required this.frontmatter,
    required this.body,
  });

  final WikiIo wiki;
  final String sidecarPath;
  final Map<String, Object?> frontmatter;
  final String body;

  @override
  Widget build(BuildContext context) {
    final imageFilename = frontmatter['image'];
    final binaryPath = imageFilename is String
        ? sidecarPath.replaceFirst(
            RegExp(r'/[^/]+\.md$'),
            '/$imageFilename',
          )
        : null;
    final redFlagMatch = frontmatter['red_flag_match'];
    final redFlagId = redFlagMatch is String && redFlagMatch.isNotEmpty
        ? redFlagMatch
        : null;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(Spacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Phase 6 task 6.7 — historical urgency marker. The badge
          // sits above the image so it's the first thing the user
          // sees when they reopen a flagged memory; the live preamble
          // (the chat-side equivalent) was the prominent alert at
          // capture-time, this is the persistent record (CLAUDE.md
          // §10).
          if (redFlagId != null) ...[
            const RedFlagBadge(
              label: 'PetPal flagged something it noticed in this photo',
            ),
            const SizedBox(height: Spacing.s),
          ],
          if (binaryPath != null)
            ClipRRect(
              borderRadius: Corners.s,
              child: FutureBuilder<Uint8List>(
                future: wiki.readBytes(binaryPath),
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return AspectRatio(
                      aspectRatio: 1,
                      child: ColoredBox(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainer,
                      ),
                    );
                  }
                  if (snap.hasError || snap.data == null) {
                    return _ImageMissing();
                  }
                  return Image.memory(
                    snap.data!,
                    fit: BoxFit.contain,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _ImageMissing(),
                  );
                },
              ),
            ),
          if (body.isNotEmpty) ...[
            const SizedBox(height: Spacing.l),
            SelectableText(
              body,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ],
          const SizedBox(height: Spacing.l),
          _PhotoFields(frontmatter: frontmatter),
        ],
      ),
    );
  }
}

class _ImageMissing extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AspectRatio(
      aspectRatio: 1,
      child: ColoredBox(
        color: scheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            PhosphorIconsRegular.pawPrint,
            size: 48,
            color: scheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

/// Renders the additive frontmatter field rows. Each row is one
/// label + one value; rows for fields that aren't present (or are
/// empty / null) are skipped entirely so the section reads as a
/// "what we know about this photo" summary that grows with the
/// extractor (6.5) and screener (6.7).
class _PhotoFields extends StatelessWidget {
  const _PhotoFields({required this.frontmatter});
  final Map<String, Object?> frontmatter;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];

    void add(String label, String? value) {
      if (value == null || value.trim().isEmpty) return;
      rows.add(_FieldRow(label: label, value: value));
    }

    final tsRaw = frontmatter['ts'];
    if (tsRaw is String && tsRaw.isNotEmpty) {
      add('When', _humanTs(tsRaw));
    }
    add('Setting', frontmatter['setting'] as String?);
    add('Activity', frontmatter['activity'] as String?);
    add('Demeanor', frontmatter['demeanor'] as String?);
    final objects = frontmatter['notable_objects'];
    if (objects is List && objects.isNotEmpty) {
      add('Notable', objects.join(', '));
    }
    final hints = frontmatter['enrichment_hints'];
    if (hints is List && hints.isNotEmpty) {
      add('Follow-up', hints.join(' • '));
    }
    final byteSize = frontmatter['byte_size'];
    if (byteSize is int) {
      add('Size', _humanBytes(byteSize));
    }

    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: rows,
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}

String _humanTs(String iso) {
  // ISO-8601 timestamps from the sidecar look like
  // `2026-04-25T14:30:12`. Render as the date in the local register
  // — the time-of-day adds noise for a journal entry; if a future
  // task wants to surface it, format here.
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(iso);
  if (m == null) return iso;
  return '${m.group(1)}-${m.group(2)}-${m.group(3)}';
}

String _humanBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(0)} KB';
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}
