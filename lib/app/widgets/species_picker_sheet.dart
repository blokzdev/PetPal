import 'package:flutter/material.dart';

import '../../data/species_catalog.dart';
import '../design/design.dart';

/// Outcome of a species picker session. Sealed via Dart records — null
/// from the caller's `await` means dismissed; non-null carries either a
/// picked entry or the sentinel "Other (type your own)" branch (5.5.6).
typedef SpeciesPickerOutcome = ({SpeciesEntry? entry, bool isOther});

/// Outcome of a breed sub-picker session for Tier 1 species. Same shape.
typedef BreedPickerOutcome = ({BreedEntry? breed, bool isOther});

/// Show the species picker bottom sheet for the given [category].
/// Returns the user's pick (entry or Other) or null on dismiss. Per the
/// 5.5.3 design lock (Decision 1 A): bottom sheet, not full-screen
/// modal, not inline expand.
Future<SpeciesPickerOutcome?> showSpeciesPickerSheet(
  BuildContext context, {
  required SpeciesCatalog catalog,
  required String category,
}) {
  return showModalBottomSheet<SpeciesPickerOutcome?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SpeciesPickerSheet(catalog: catalog, category: category),
  );
}

/// Show the breed picker bottom sheet for a Tier 1 species's [breeds]
/// list. Same UX shape as the species picker per 5.5.3 design lock
/// (Decision 3 A — separate field + separate modal).
Future<BreedPickerOutcome?> showBreedPickerSheet(
  BuildContext context, {
  required List<BreedEntry> breeds,
}) {
  return showModalBottomSheet<BreedPickerOutcome?>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _BreedPickerSheet(breeds: breeds),
  );
}

class _SpeciesPickerSheet extends StatefulWidget {
  const _SpeciesPickerSheet({required this.catalog, required this.category});

  final SpeciesCatalog catalog;
  final String category;

  @override
  State<_SpeciesPickerSheet> createState() => _SpeciesPickerSheetState();
}

class _SpeciesPickerSheetState extends State<_SpeciesPickerSheet> {
  final _query = TextEditingController();
  late Future<List<SpeciesEntry>> _entriesFuture;

  @override
  void initState() {
    super.initState();
    _entriesFuture = widget.catalog.entriesFor(widget.category);
    _query.addListener(_onQueryChanged);
  }

  void _onQueryChanged() => setState(() {});

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return SizedBox(
      // Fill ~85% of screen height — leaves the form visible behind the
      // sheet for context, fits ~150 entries comfortably with search.
      height: mq.size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.m,
                Spacing.s,
                Spacing.m,
                Spacing.s,
              ),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: FutureBuilder<List<SpeciesEntry>>(
                future: _entriesFuture,
                builder: (ctx, snap) {
                  if (!snap.hasData) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  final hits = _rankSpecies(snap.data!, _query.text);
                  return _ResultsList(
                    hits: hits,
                    query: _query.text,
                    onPick: (entry) =>
                        Navigator.of(context).pop((entry: entry, isOther: false)),
                    onOther: () =>
                        Navigator.of(context).pop((entry: null, isOther: true)),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BreedPickerSheet extends StatefulWidget {
  const _BreedPickerSheet({required this.breeds});

  final List<BreedEntry> breeds;

  @override
  State<_BreedPickerSheet> createState() => _BreedPickerSheetState();
}

class _BreedPickerSheetState extends State<_BreedPickerSheet> {
  final _query = TextEditingController();

  @override
  void initState() {
    super.initState();
    _query.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final hits = SpeciesCatalog.searchBreeds(
      breeds: widget.breeds,
      query: _query.text,
    );
    return SizedBox(
      height: mq.size.height * 0.85,
      child: Padding(
        padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Spacing.m,
                Spacing.s,
                Spacing.m,
                Spacing.s,
              ),
              child: TextField(
                controller: _query,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search breeds',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            Expanded(
              child: _BreedResultsList(
                hits: hits,
                query: _query.text,
                onPick: (breed) {
                  // "Other" sentinel detection — if the user picks the
                  // last "Other" row we treat it as the freeform fallback
                  // signal per 5.5.6. The breed-picker sentinel lives in
                  // the data file (the breeds[] array's last element).
                  if (breed.name.toLowerCase() == 'other') {
                    Navigator.of(context).pop((breed: null, isOther: true));
                  } else {
                    Navigator.of(context)
                        .pop((breed: breed, isOther: false));
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultsList extends StatelessWidget {
  const _ResultsList({
    required this.hits,
    required this.query,
    required this.onPick,
    required this.onOther,
  });

  final List<SpeciesSearchHit> hits;
  final String query;
  final ValueChanged<SpeciesEntry> onPick;
  final VoidCallback onOther;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.l),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              'No matches.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: Spacing.s),
            Text(
              'Try a different name, or tap "Other (type your own)" at the bottom.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
            const Spacer(),
            _OtherTile(onTap: onOther),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: hits.length + 1, // +1 for trailing "Other" tile
      itemBuilder: (ctx, i) {
        if (i == hits.length) return _OtherTile(onTap: onOther);
        final hit = hits[i];
        return _SpeciesTile(hit: hit, onTap: () => onPick(hit.entry));
      },
    );
  }
}

class _BreedResultsList extends StatelessWidget {
  const _BreedResultsList({
    required this.hits,
    required this.query,
    required this.onPick,
  });

  final List<BreedSearchHit> hits;
  final String query;
  final ValueChanged<BreedEntry> onPick;

  @override
  Widget build(BuildContext context) {
    if (hits.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(Spacing.l),
        child: Center(
          child: Text(
            'No matches. Tap "Other" at the bottom to type a breed.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: hits.length,
      itemBuilder: (ctx, i) {
        final hit = hits[i];
        return _BreedTile(hit: hit, onTap: () => onPick(hit.breed));
      },
    );
  }
}

class _SpeciesTile extends StatelessWidget {
  const _SpeciesTile({required this.hit, required this.onTap});

  final SpeciesSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Decision 2 A — append matched alternative to title; sci name stays
    // on the subtitle line.
    final title = hit.matchedAlternative != null
        ? '${hit.entry.displayName} (also: ${hit.matchedAlternative})'
        : hit.entry.displayName;
    return ListTile(
      title: Text(title),
      subtitle: Text(
        hit.entry.scientificName,
        style: theme.textTheme.bodySmall?.copyWith(
          fontStyle: FontStyle.italic,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _BreedTile extends StatelessWidget {
  const _BreedTile({required this.hit, required this.onTap});

  final BreedSearchHit hit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final title = hit.matchedAlternative != null
        ? '${hit.breed.name} (also: ${hit.matchedAlternative})'
        : hit.breed.name;
    return ListTile(
      title: Text(title),
      onTap: onTap,
    );
  }
}

class _OtherTile extends StatelessWidget {
  const _OtherTile({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.edit_outlined),
      title: const Text('Other (type your own)'),
      onTap: onTap,
    );
  }
}

List<SpeciesSearchHit> _rankSpecies(List<SpeciesEntry> entries, String query) {
  if (query.trim().isEmpty) {
    return [for (final e in entries) SpeciesSearchHit(entry: e, matchedAlternative: null)];
  }
  final q = query.toLowerCase().trim();
  final exact = <SpeciesSearchHit>[];
  final prefixName = <SpeciesSearchHit>[];
  final prefixAlt = <SpeciesSearchHit>[];
  final containsName = <SpeciesSearchHit>[];
  final containsAlt = <SpeciesSearchHit>[];
  for (final e in entries) {
    final name = e.displayName.toLowerCase();
    if (name == q) {
      exact.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    if (name.startsWith(q)) {
      prefixName.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    String? altPrefix;
    String? altContains;
    for (final a in e.commonAlternatives) {
      final al = a.toLowerCase();
      if (al == q || al.startsWith(q)) {
        altPrefix ??= a;
        break;
      }
      if (al.contains(q)) altContains ??= a;
    }
    if (altPrefix != null) {
      prefixAlt.add(SpeciesSearchHit(entry: e, matchedAlternative: altPrefix));
      continue;
    }
    if (name.contains(q)) {
      containsName.add(SpeciesSearchHit(entry: e, matchedAlternative: null));
      continue;
    }
    if (altContains != null) {
      containsAlt.add(SpeciesSearchHit(entry: e, matchedAlternative: altContains));
    }
  }
  return [...exact, ...prefixName, ...prefixAlt, ...containsName, ...containsAlt];
}
