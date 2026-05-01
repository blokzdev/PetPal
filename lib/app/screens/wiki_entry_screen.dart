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
import '../widgets/editorial_card.dart';
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
            // Phase 6.6 task 6.6.C.2 — entry header (serif title +
            // small-caps date) above the markdown body, plus the
            // MEDICAL NOTE callout for vet entries. Body's leading
            // `# H1` (when present) is stripped so the explicit
            // header doesn't duplicate it. `MarkdownBody` (vs the
            // scrolling `Markdown`) lets the header scroll with
            // the content inside one SingleChildScrollView.
            //
            // Phase 6.6 task 6.6.C.3 — digest entries get the
            // editorial register: weeklySummaryTitle for the header
            // + INSIGHT callouts for trend/anomaly sections +
            // nested EditorialCards for highlight bullets. Non-
            // digest entries keep the default markdown body render.
            final isDigest = type == 'digest';
            final body = _stripLeadingH1IfMatchesTitle(
              parsed.body.trimLeft(),
              _humanEntryTitle(path),
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(Spacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _EntryHeader(path: path, type: type),
                  if (type == 'vet') ...[
                    const SizedBox(height: Spacing.m),
                    const _MedicalNoteCallout(),
                  ],
                  const SizedBox(height: Spacing.l),
                  if (isDigest)
                    _DigestBodyRender(body: body)
                  else
                    MarkdownBody(
                      data: body,
                      selectable: true,
                      styleSheet: _entryMarkdownStyle(context),
                    ),
                ],
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

/// Phase 6.6 task 6.6.C.2 — strips a leading `# {title}\n` line
/// from a markdown body when it matches the entry's resolved title
/// (case-insensitive, whitespace-tolerant). Vet entries from 6.10
/// always embed `# {reason}` at the top of the body; the new entry
/// header renders the title separately, so the matching H1 is
/// duplicate. Non-matching H1s are preserved — a body that opens
/// with an unrelated H1 (a freeform note titled "Just a body" on a
/// path-slug-titled "Rabies" entry) should still see its H1
/// rendered by the markdown body.
String _stripLeadingH1IfMatchesTitle(String body, String title) {
  final m = RegExp(r'^#\s+([^\n]*)\n+').firstMatch(body);
  if (m == null) return body;
  final headingText = m.group(1)?.trim() ?? '';
  if (headingText.toLowerCase() == title.trim().toLowerCase()) {
    return body.substring(m.end);
  }
  return body;
}

/// Phase 6.6 task 6.6.C.2 — entry header for the markdown render
/// path. Serif title (via `JournalText.entryTitle`) on top, small-
/// caps metadata row below (`{TYPE} · {MON DAY YYYY}`). Mirrors the
/// editorial register the journal-browser tiles + home recent-
/// memories cards use, applied to the detail view.
class _EntryHeader extends StatelessWidget {
  const _EntryHeader({required this.path, required this.type});

  final String path;
  final Object? type;

  static const _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  String _humanType(Object? t) {
    if (t is! String || t.isEmpty) return 'NOTE';
    switch (t) {
      case 'digest':
        return 'WEEKLY SUMMARY';
      case 'vet':
        return 'VET VISIT';
      case 'food':
        return 'FOOD';
      case 'weight':
        return 'WEIGHT';
      case 'behavior':
        return 'BEHAVIOR';
      case 'photos':
        return 'PHOTO';
      default:
        return t.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final title = _humanEntryTitle(path);
    final parsed = parseEntryPath(path);
    final ts = parsed?.ts;
    String? meta;
    if (ts != null) {
      meta = '${_humanType(type)} · '
          '${_monthAbbrev[ts.month - 1]} ${ts.day} ${ts.year}';
    } else {
      meta = _humanType(type);
    }
    // Phase 6.6 task 6.6.C.3 — digest entries get the larger
    // weeklySummaryTitle register; the weekly summary is a
    // cumulative artifact and earns the bigger serif.
    final titleStyle = type == 'digest'
        ? JournalText.weeklySummaryTitle(color: scheme.onSurface)
        : JournalText.entryTitle(color: scheme.onSurface);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: titleStyle),
        const SizedBox(height: Spacing.s),
        Text(
          meta,
          style: textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Phase 6.6 task 6.6.C.2 — MEDICAL NOTE callout for vet entries.
///
/// Renders below the entry header on `type: vet` entries. Coral
/// left-border (4 dp) + coral icon + small-caps "MEDICAL NOTE"
/// kicker + plain-language framing copy. Per DECISIONS row 64
/// coral is the systemic medical-attention register; this callout
/// is one of the five surfaces D.1 wires.
///
/// Copy register per VOICE.md §1: warm, direct, treats the user
/// as an adult. Not alarmist (vet entries are routine — a record,
/// not an alert).
class _MedicalNoteCallout extends StatelessWidget {
  const _MedicalNoteCallout();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.card,
      color: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: Corners.s),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: scheme.tertiary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.m),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      PhosphorIconsRegular.firstAidKit,
                      color: scheme.tertiary,
                      size: 20,
                    ),
                    const SizedBox(width: Spacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'MEDICAL NOTE',
                            style: textTheme.labelSmall?.copyWith(
                              color: scheme.tertiary,
                              letterSpacing: 1.4,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: Spacing.xs),
                          Text(
                            "Part of this pet's medical record. Hand "
                            'this entry to a new vet to bring them up '
                            'to speed.',
                            style: textTheme.bodyMedium?.copyWith(
                              color:
                                  scheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase 6.6 task 6.6.C.3 — digest body renderer.
///
/// Pre-passes the digest's markdown body, splits it into segments
/// at h2 boundaries, then classifies each segment by its heading:
///
///   - **INSIGHT** keywords (Trends / Anomalies / Insight /
///     Insights / Watch list / Watchlist) → renders as a
///     sage-bordered `_InsightCallout` with the heading + body
///     bullets/prose. Per DECISIONS row 58 — sage carries the
///     synthesis register; coral stays reserved for medical-
///     attention.
///   - **HIGHLIGHTS** keywords (Highlights / Notable / Recurring /
///     Recurring patterns) → bullet items become individual
///     `EditorialCard`s (Group B.1 primitive). Each bullet's
///     first sentence becomes the title; remaining text becomes
///     the body. Non-bullet body text gets surfaced inside the
///     section's leading EditorialCard as body content.
///   - Other sections → default `MarkdownBody` render, preserving
///     the standard markdown styling.
///
/// Sections are classified by case-insensitive keyword match on the
/// h2 heading text. Non-h2 prose at the top of the body (before any
/// h2) renders as default markdown. Empty bodies render nothing.
class _DigestBodyRender extends StatelessWidget {
  const _DigestBodyRender({required this.body});

  final String body;

  static final _h2 = RegExp(r'^##\s+(.+)$', multiLine: true);

  static const _insightKeywords = [
    'trends',
    'anomalies',
    'insight',
    'insights',
    'watch list',
    'watchlist',
  ];

  static const _highlightKeywords = [
    'highlights',
    'notable',
    'recurring',
    'recurring patterns',
  ];

  bool _isInsight(String h) {
    final lower = h.toLowerCase();
    return _insightKeywords.any((k) => lower.contains(k));
  }

  bool _isHighlight(String h) {
    final lower = h.toLowerCase();
    return _highlightKeywords.any((k) => lower.contains(k));
  }

  /// Splits the body into ordered (heading?, content) segments at
  /// h2 boundaries. The first segment carries any prose that
  /// appears before the first h2 (heading: null).
  List<({String? heading, String content})> _segment(String b) {
    final segments = <({String? heading, String content})>[];
    final matches = _h2.allMatches(b).toList();
    if (matches.isEmpty) {
      if (b.trim().isNotEmpty) {
        segments.add((heading: null, content: b.trim()));
      }
      return segments;
    }
    // Pre-h2 prose (if any).
    if (matches.first.start > 0) {
      final pre = b.substring(0, matches.first.start).trim();
      if (pre.isNotEmpty) {
        segments.add((heading: null, content: pre));
      }
    }
    for (var i = 0; i < matches.length; i++) {
      final m = matches[i];
      final heading = m.group(1)?.trim() ?? '';
      final contentStart = m.end;
      final contentEnd =
          i + 1 < matches.length ? matches[i + 1].start : b.length;
      final content = b.substring(contentStart, contentEnd).trim();
      segments.add((heading: heading, content: content));
    }
    return segments;
  }

  /// Extracts top-level bullets (`- text` or `* text`) from a
  /// section's content. Continuation lines (indented) join the
  /// preceding bullet. Non-bullet text becomes a leading "preamble"
  /// returned alongside the bullets. Static so `_HighlightSection`
  /// can reuse without constructing a `_DigestBodyRender`.
  static ({String preamble, List<String> bullets}) extractBullets(String c) {
    final lines = c.split('\n');
    final bullets = <String>[];
    final preambleBuf = StringBuffer();
    String? currentBullet;
    for (final line in lines) {
      final m = RegExp(r'^[-*]\s+(.+)$').firstMatch(line.trimRight());
      if (m != null) {
        if (currentBullet != null) bullets.add(currentBullet.trim());
        currentBullet = m.group(1)!.trim();
      } else if (currentBullet != null && line.startsWith(' ')) {
        currentBullet = '$currentBullet ${line.trim()}';
      } else if (currentBullet == null) {
        preambleBuf.writeln(line);
      } else {
        // Blank or non-indented line after a bullet — keeps the
        // bullet open; subsequent lines either continue or start
        // a new bullet.
        if (line.trim().isEmpty) {
          // commit whatever we have; reset
          bullets.add(currentBullet.trim());
          currentBullet = null;
        }
      }
    }
    if (currentBullet != null) bullets.add(currentBullet.trim());
    return (preamble: preambleBuf.toString().trim(), bullets: bullets);
  }

  @override
  Widget build(BuildContext context) {
    final segments = _segment(body);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final s in segments) ...[
          if (s.heading != null && _isInsight(s.heading!))
            _InsightCallout(heading: s.heading!, body: s.content)
          else if (s.heading != null && _isHighlight(s.heading!))
            _HighlightSection(heading: s.heading!, content: s.content)
          else
            // Default render: re-emit the heading (if any) and the
            // section content as standard markdown.
            MarkdownBody(
              data: s.heading != null
                  ? '## ${s.heading}\n\n${s.content}'
                  : s.content,
              selectable: true,
              styleSheet: _entryMarkdownStyle(context),
            ),
          const SizedBox(height: Spacing.m),
        ],
      ],
    );
  }
}

/// Phase 6.6 task 6.6.C.3 — INSIGHT callout for digest body
/// trend / anomaly / insight sections. Sage left-border (4 dp) +
/// sage icon + small-caps "{HEADING}" kicker + body content
/// rendered as markdown (so bullet lists keep their structure).
class _InsightCallout extends StatelessWidget {
  const _InsightCallout({required this.heading, required this.body});

  final String heading;
  final String body;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Material(
      type: MaterialType.card,
      color: scheme.surfaceContainer,
      shape: const RoundedRectangleBorder(borderRadius: Corners.s),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 4, color: scheme.primary),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(Spacing.m),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          PhosphorIconsRegular.sparkle,
                          size: 16,
                          color: scheme.primary,
                        ),
                        const SizedBox(width: Spacing.xs),
                        Text(
                          heading.toUpperCase(),
                          style: textTheme.labelSmall?.copyWith(
                            color: scheme.primary,
                            letterSpacing: 1.4,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: Spacing.s),
                    MarkdownBody(
                      data: body,
                      selectable: true,
                      styleSheet: _entryMarkdownStyle(context),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Phase 6.6 task 6.6.C.3 — HIGHLIGHTS section for digest bodies.
/// Bullet items become individual `EditorialCard`s (B.1 primitive)
/// stacked under the section heading. Non-bullet preamble text
/// renders as markdown above the cards.
class _HighlightSection extends StatelessWidget {
  const _HighlightSection({required this.heading, required this.content});

  final String heading;
  final String content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final extracted = _DigestBodyRender.extractBullets(content);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: Spacing.m),
          child: Text(
            heading.toUpperCase(),
            style: textTheme.labelSmall?.copyWith(
              color: scheme.primary.withValues(alpha: 0.85),
              letterSpacing: 1.2,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(height: Spacing.s),
        if (extracted.preamble.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Spacing.m),
            child: MarkdownBody(
              data: extracted.preamble,
              selectable: true,
              styleSheet: _entryMarkdownStyle(context),
            ),
          ),
        for (final bullet in extracted.bullets)
          EditorialCard(
            title: bullet,
          ),
      ],
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
            // Phase 6.6 task 6.6.C.2 — subtle sage frame around the
            // photo (no device-mockup framing per the user-locked
            // brief). Hairline sage border + the existing rounded
            // clip; reads as "framed photo on a journal page"
            // without the laptop-product-shot register a thicker
            // frame would imply.
            DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: Corners.s,
                border: Border.all(
                  color: Theme.of(context)
                      .colorScheme
                      .primary
                      .withValues(alpha: 0.25),
                ),
              ),
              child: ClipRRect(
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
