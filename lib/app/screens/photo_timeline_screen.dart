import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/pet_button.dart';
import '../widgets/pet_empty_state.dart';
import '../widgets/red_flag_badge.dart';

/// Phase 6 task 6.3 — photo timeline. A 3-column square grid of every
/// photo across the active pet's wiki, time-ordered (newest first).
/// Each tile loads its thumbnail bytes via the wiki IO layer; tap →
/// `/wiki/entry` with the sidecar path, where `WikiEntryScreen` type-
/// dispatches on `type: photos` to render the full-size image + the
/// sidecar's extracted fields + freeform caption.
///
/// The 6.6 home-grid camera CTA will provide the primary entry-point
/// to this screen post-save; for 6.3 the screen is reachable from the
/// wiki browser's Photos type-header "View all in timeline" link.
class PhotoTimelineScreen extends ConsumerWidget {
  const PhotoTimelineScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(wikiEntriesProvider);
    final petsAsync = ref.watch(petsProvider);
    // Bug-2 defense: empty/whitespace name → treat as null so the
    // title falls back to "Photos" rather than "'s photos".
    final petName = petsAsync.maybeWhen(
      data: (pets) {
        if (pets.isEmpty) return null;
        final name = pets.last.name.trim();
        return name.isEmpty ? null : name;
      },
      orElse: () => null,
    );
    final title = petName == null ? 'Photos' : "$petName's photos";
    return AppScaffold.async<List<Entry>>(
      title: title,
      value: entriesAsync,
      onRetry: () => ref.invalidate(wikiEntriesProvider),
      data: (context, entries) {
        final photos = entries.where((e) => e.type == 'photos').toList();
        if (photos.isEmpty) {
          return _PhotosEmpty(petName: petName);
        }
        return _PhotoGrid(entries: photos);
      },
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.entries});
  final List<Entry> entries;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(Spacing.s),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        crossAxisSpacing: Spacing.xs,
        mainAxisSpacing: Spacing.xs,
      ),
      itemCount: entries.length,
      itemBuilder: (context, i) => _PhotoTile(entry: entries[i]),
    );
  }
}

/// Single grid tile. Reads the binary bytes via wiki IO on first
/// build; caches via `gaplessPlayback` so re-scroll doesn't flash.
/// On tap → push `/wiki/entry` with the sidecar's `.md` path.
class _PhotoTile extends ConsumerWidget {
  const _PhotoTile({required this.entry});
  final Entry entry;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wikiAsync = ref.watch(wikiIoProvider);
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainer,
      borderRadius: Corners.s,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => GoRouter.of(context).push(
          '/wiki/entry',
          extra: entry.path,
        ),
        child: wikiAsync.when(
          data: (wiki) => FutureBuilder<_TilePayload>(
            future: _resolveTilePayload(wiki, entry.path),
            builder: (context, snap) {
              if (snap.connectionState != ConnectionState.done) {
                return const ColoredBox(color: Colors.transparent);
              }
              if (snap.hasError || snap.data == null) {
                return _TileFallback();
              }
              final payload = snap.data!;
              // Phase 6 task 6.7 — flagged photos carry a small icon
              // chip in the top-right corner. Subdued treatment per
              // CLAUDE.md §10 (badge is a historical record, not a
              // current-state alert).
              return Stack(
                fit: StackFit.expand,
                children: [
                  Image.memory(
                    payload.bytes,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                    errorBuilder: (_, _, _) => _TileFallback(),
                  ),
                  if (payload.flagged)
                    const Positioned(
                      top: 4,
                      right: 4,
                      child: RedFlagBadge.tile(),
                    ),
                ],
              );
            },
          ),
          loading: () => const ColoredBox(color: Colors.transparent),
          error: (_, _) => _TileFallback(),
        ),
      ),
    );
  }
}

class _TileFallback extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surfaceContainerHighest,
      child: Icon(
        PhosphorIconsRegular.pawPrint,
        color: scheme.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}

class _PhotosEmpty extends StatelessWidget {
  const _PhotosEmpty({required this.petName});
  final String? petName;

  @override
  Widget build(BuildContext context) {
    final body = petName == null
        ? 'Photos saved as memories will land here.'
        : 'Photos of $petName saved as memories will land here.';
    return PetEmptyState(
      icon: PhosphorIconsRegular.pawPrint,
      heading: 'No photos yet.',
      body: body,
      action: PetButton(
        label: 'Open chat',
        onPressed: () => GoRouter.of(context).go('/chat'),
        icon: PhosphorIconsRegular.chatCircle,
      ),
    );
  }
}

/// Bytes + flag for a single grid tile.
class _TilePayload {
  const _TilePayload({required this.bytes, required this.flagged});
  final Uint8List bytes;
  final bool flagged;
}

/// Resolve a sidecar `.md` path to its image bytes plus the red-flag
/// state. Reads the sidecar once, extracts both `image:` and (Phase 6
/// task 6.7) `red_flag_match:` from the same parse, then reads the
/// binary via wiki IO. Two reads per tile is fine for v1; a future
/// enhancement could thumbnail-cache the binary at write time.
Future<_TilePayload> _resolveTilePayload(
    dynamic wiki, String sidecarPath) async {
  final sidecarBody = await wiki.read(sidecarPath) as String;
  final imageFilename = _extractImageFilename(sidecarBody);
  if (imageFilename == null) {
    throw StateError('sidecar missing image: pointer');
  }
  // sidecarPath = wiki/<petId>/photos/<id>.md → binary lives at
  // wiki/<petId>/photos/<image>. Replace the trailing filename.
  final binaryPath = sidecarPath.replaceFirst(
    RegExp(r'/[^/]+\.md$'),
    '/$imageFilename',
  );
  final bytes = await wiki.readBytes(binaryPath) as Uint8List;
  return _TilePayload(
    bytes: bytes,
    flagged: _hasRedFlagMatch(sidecarBody),
  );
}

/// Hand-parse the sidecar's `image:` line. Avoids importing
/// soul_file just for this — the sidecar is small and the field is
/// always on its own line in 6.1's minimum frontmatter.
String? _extractImageFilename(String sidecarBody) {
  final m = RegExp(r'^image:\s*(\S+)\s*$', multiLine: true)
      .firstMatch(sidecarBody);
  return m?.group(1)?.trim();
}

/// Phase 6 task 6.7 — does the sidecar carry a `red_flag_match:`
/// frontmatter field with a non-empty value? Same hand-parse approach
/// as `_extractImageFilename` — the field is always on its own line
/// when present.
bool _hasRedFlagMatch(String sidecarBody) {
  final m = RegExp(r'^red_flag_match:\s*(\S+.*?)\s*$', multiLine: true)
      .firstMatch(sidecarBody);
  final raw = m?.group(1)?.trim();
  return raw != null && raw.isNotEmpty;
}
