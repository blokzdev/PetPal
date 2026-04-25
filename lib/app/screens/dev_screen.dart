import 'package:flutter/material.dart';

import '../../data/db/connection.dart';
import '../../data/db/database.dart';
import '../../data/repos/pet_repo.dart';
import '../../data/repos/wiki_repo.dart';
import '../../data/wiki_io_fs.dart';
import '../../harness/retrieval/embedding_provider.dart';
import '../../harness/retrieval/embedding_worker.dart';
import '../../harness/retrieval/hybrid_retriever.dart';
import '../../harness/retrieval/onnx_embedding_provider.dart';

/// Phase 1 verification screen — exercises the full harness end-to-end:
/// create a pet, write seed notes, run hybrid keyword + semantic retrieval,
/// show the ranked hits.
///
/// Reachable at `/dev`. Linked from Home behind `kDebugMode` so it doesn't
/// ship in release builds. CLAUDE.md §6 / §7 / §11 deliberately don't surface
/// retrieval to end users — this screen is for testing the harness.
class DevScreen extends StatefulWidget {
  const DevScreen({super.key});

  @override
  State<DevScreen> createState() => _DevScreenState();
}

class _DevScreenState extends State<DevScreen> {
  // Lazy-initialised on first frame; nullable so the build method can render
  // a loading shell while async deps spin up.
  AppDatabase? _db;
  PetRepo? _petRepo;
  WikiRepo? _wikiRepo;
  HybridRetriever? _retriever;
  EmbeddingProvider? _embeddings;

  Pet? _activePet;
  List<Hit> _hits = const [];

  final _queryController = TextEditingController(
    text: 'what treats does my dog like',
  );

  String _status = 'Initializing harness…';
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    try {
      final db = await openAppDatabase();
      final wiki = await WikiIoFs.openDefault();
      final embeddings = await OnnxEmbeddingProvider.fromAssets();
      final worker = EmbeddingWorker(db: db, provider: embeddings);
      final petRepo = PetRepo(db: db, wiki: wiki);
      final wikiRepo = WikiRepo(db: db, wiki: wiki, embeddings: worker);
      final retriever = HybridRetriever(db: db);

      // Pick up the most recently-created pet, if any. Lets the screen
      // survive hot reloads without re-seeding every time.
      final pets = await petRepo.listPets();
      final active = pets.isEmpty ? null : pets.last;

      if (!mounted) return;
      setState(() {
        _db = db;
        _embeddings = embeddings;
        _wikiRepo = wikiRepo;
        _petRepo = petRepo;
        _retriever = retriever;
        _activePet = active;
        _busy = false;
        _status = active == null
            ? 'Ready. Tap “Reset & seed Milo” to begin.'
            : 'Active pet: ${active.name} (id ${active.id}).';
      });
    } catch (e, st) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Bootstrap failed: $e\n$st';
      });
    }
  }

  Future<void> _resetAndSeed() async {
    if (_db == null) return;
    setState(() {
      _busy = true;
      _status = 'Seeding…';
      _hits = const [];
    });
    try {
      // Wipe any existing pet rows; FK cascades clear entries+embeddings.
      // Files on disk persist (deletePet is index-only).
      for (final p in await _petRepo!.listPets()) {
        await _petRepo!.deletePet(p.id);
      }
      final id = await _petRepo!.createPet(
        name: 'Milo',
        species: 'dog',
        breed: 'mixed',
        dob: DateTime(2022, 6, 12),
      );
      final pet = (await _petRepo!.getPet(id))!;
      final now = DateTime.now();
      await _wikiRepo!.writeEntry(
        petId: id,
        type: 'food',
        title: 'Frozen carrot trial',
        body: 'Milo loves frozen carrots. He naps for 20 minutes after.',
        ts: now,
      );
      await _wikiRepo!.writeEntry(
        petId: id,
        type: 'behavior',
        title: 'Skateboard fear',
        body: 'Milo bolts whenever a skateboard rolls past on the sidewalk.',
        ts: now,
      );
      await _wikiRepo!.writeEntry(
        petId: id,
        type: 'vet',
        title: 'Annual checkup',
        body: 'Routine visit at Maple Vet. Vitals normal; weight 14.2 kg.',
        ts: now,
      );

      if (!mounted) return;
      setState(() {
        _activePet = pet;
        _busy = false;
        _status = 'Seeded ${pet.name} (id ${pet.id}) with 3 entries.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Seed failed: $e';
      });
    }
  }

  Future<void> _runSearch() async {
    if (_activePet == null || _retriever == null || _embeddings == null) {
      return;
    }
    final query = _queryController.text.trim();
    if (query.isEmpty) return;

    setState(() {
      _busy = true;
      _status = 'Searching…';
    });
    try {
      final vec = await _embeddings!.embed(query, kind: EmbeddingKind.query);
      final hits = await _retriever!.search(
        petId: _activePet!.id,
        queryText: query,
        queryVector: vec,
        k: 6,
      );
      if (!mounted) return;
      setState(() {
        _hits = hits;
        _busy = false;
        _status = '${hits.length} hit(s) for "$query".';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Search failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final canSearch = !_busy && _activePet != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Harness · dev')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(_status, style: theme.textTheme.bodyMedium),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: _busy ? null : _resetAndSeed,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Reset & seed Milo'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _queryController,
                decoration: const InputDecoration(
                  labelText: 'Search query',
                  border: OutlineInputBorder(),
                ),
                onSubmitted: (_) => canSearch ? _runSearch() : null,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: canSearch ? _runSearch : null,
                icon: const Icon(Icons.search),
                label: const Text('Run hybrid search'),
              ),
              const SizedBox(height: 16),
              const Divider(),
              Expanded(
                child: _hits.isEmpty
                    ? Center(
                        child: Text(
                          _busy ? '…' : 'No hits yet.',
                          style: theme.textTheme.bodyMedium,
                        ),
                      )
                    : ListView.separated(
                        itemCount: _hits.length,
                        separatorBuilder: (_, _) => const Divider(),
                        itemBuilder: (context, i) {
                          final hit = _hits[i];
                          return ListTile(
                            title: Text(hit.title),
                            subtitle: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  hit.path,
                                  style: theme.textTheme.bodySmall,
                                ),
                                if (hit.snippet != null)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 4),
                                    child: Text(
                                      hit.snippet!,
                                      style: theme.textTheme.bodySmall,
                                    ),
                                  ),
                              ],
                            ),
                            trailing: Text(
                              hit.score.toStringAsFixed(4),
                              style: theme.textTheme.bodySmall,
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
