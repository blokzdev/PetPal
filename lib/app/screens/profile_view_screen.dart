import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../data/db/database.dart';
import '../../data/pet_name.dart';
import '../../data/soul_file.dart';
import '../design/design.dart';
import '../providers.dart';
import '../widgets/app_scaffold.dart';
import '../widgets/charts/symptom_chart.dart';
import '../widgets/charts/weight_chart.dart';
import '../widgets/editorial_card.dart';
import '../widgets/pet_card.dart';
import '../widgets/pet_section_header.dart';
import '../widgets/pet_switcher.dart';

/// Phase 6.6 task 6.6.C.4 — Pet profile layered restructure
/// (read-only sectioned view; edit pencil routes to the existing
/// editor at `/soul/edit`).
///
/// Five sections per DECISIONS row 63:
///
///   - **ABOUT** — name + species + breed + relationship +
///     sub-classification + freeform body prose.
///   - **DETAILS** — DOB + weight + allergies + meds + vet contact
///     + temperament.
///   - **HEALTH SUMMARY** — Phase 6.12 weight + symptom-frequency
///     charts.
///   - **RECENT MEMORIES** — top 3 entries via `wikiEntriesProvider`
///     as `EditorialCard`s (Group B primitive).
///   - **GUIDES & SKILLS** — entry to `/soul/guides` (Care guides
///     per row 62).
///
/// Header treatment: large circle profile photo (Phase 6.2) + serif
/// pet name (`weeklySummaryTitle` register) + small-caps subtitle
/// (relationship · species). Edit pencil in the AppBar pushes to
/// `/soul/edit` — the existing `SoulEditorScreen` lives there
/// unchanged (DECISIONS row 63 — layered, not full restructure).
class ProfileViewScreen extends ConsumerStatefulWidget {
  const ProfileViewScreen({super.key});

  @override
  ConsumerState<ProfileViewScreen> createState() =>
      _ProfileViewScreenState();
}

class _ProfileViewScreenState extends ConsumerState<ProfileViewScreen> {
  Map<String, Object?> _frontmatter = const {};
  String _body = '';
  bool _loaded = false;
  String? _loadError;
  // Phase 7 task E.2 — track which pet's SOUL is currently
  // hydrated. When the user picks a new pet via the switcher, the
  // build watcher notices the mismatch and triggers a reload.
  int? _hydratedPetId;

  @override
  void initState() {
    super.initState();
    // Defer the first load so we can read the resolved active pet
    // ID after the providers have rendered at least once.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final pet = ref.read(activePetProvider);
      if (pet != null) _load(pet.id);
    });
  }

  Future<void> _load(int petId) async {
    try {
      final wiki = await ref.read(wikiIoProvider.future);
      String raw;
      try {
        raw = await wiki.read(wiki.soulPath(petId));
      } catch (_) {
        raw = '';
      }
      final parsed = parseSoul(raw);
      if (!mounted) return;
      setState(() {
        _frontmatter = parsed.frontmatter;
        _body = parsed.body.trim();
        _loaded = true;
        _hydratedPetId = petId;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loaded = true;
        _loadError = "Couldn't load this pet's profile: $e";
        _hydratedPetId = petId;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Phase 7 task E.2 — the active pet drives the screen. When the
    // user picks a different pet via the switcher this rebuild
    // sees the mismatch and re-hydrates.
    final pet = ref.watch(activePetProvider);
    final activePetId = pet?.id;
    final petName = () {
      if (pet == null) return null;
      final n = pet.name.trim();
      return n.isEmpty ? null : n;
    }();
    final title = petName == null ? 'Profile' : "$petName's profile";

    if (activePetId != null && activePetId != _hydratedPetId) {
      // Schedule a reload — can't call setState during build.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _load(activePetId);
      });
    } else if (activePetId == null && !_loaded) {
      // Phase 7 task E.2 — no-pet path. Pre-E.2 the screen would
      // call _load() in initState, hit StateError, and surface a
      // "Couldn't load this pet's profile" error message. With
      // activePetProvider returning null on the no-pet path we
      // never call _load, so flip _loaded synchronously to render
      // the section scaffolding (the SOUL is empty, the
      // AboutCard / DetailsCard handle empty frontmatter).
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() => _loaded = true);
      });
    }

    return AppScaffold(
      title: title,
      titleWidget: PetSwitcherTitle(
        titleBuilder: (p) {
          final n = p.name.trim();
          return n.isEmpty ? 'Profile' : "$n's profile";
        },
        fallbackTitle: 'Profile',
      ),
      actions: [
        IconButton(
          tooltip: 'Edit profile',
          onPressed: () => GoRouter.of(context).push('/soul/edit'),
          icon: const Icon(PhosphorIconsRegular.pencilSimple),
        ),
      ],
      body: !_loaded
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                Spacing.m,
                Spacing.s,
                Spacing.m,
                Spacing.l,
              ),
              children: [
                if (_loadError != null) ...[
                  Text(
                    _loadError!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: Spacing.m),
                ],
                _ProfileHeader(
                  petId: activePetId,
                  petName: petName,
                  frontmatter: _frontmatter,
                ),
                const SizedBox(height: Spacing.m),
                const PetSectionHeader(title: 'About'),
                _AboutCard(frontmatter: _frontmatter, body: _body),
                const PetSectionHeader(title: 'Details'),
                _DetailsCard(frontmatter: _frontmatter),
                const PetSectionHeader(title: 'Health summary'),
                if (activePetId != null)
                  _HealthSummary(petId: activePetId)
                else
                  const SizedBox.shrink(),
                const PetSectionHeader(title: 'Recent memories'),
                if (activePetId != null)
                  const _RecentMemoriesCards()
                else
                  const SizedBox.shrink(),
                const PetSectionHeader(title: 'Guides & skills'),
                _GuidesCard(petName: petName),
              ],
            ),
    );
  }
}

/// Header: profile photo (Phase 6.2 dual-surface) + serif pet name
/// + small-caps subtitle ({RELATIONSHIP} · {SPECIES}). When the pet
/// has no profile photo, renders a sage-tinted placeholder circle.
class _ProfileHeader extends ConsumerWidget {
  const _ProfileHeader({
    required this.petId,
    required this.petName,
    required this.frontmatter,
  });

  final int? petId;
  final String? petName;
  final Map<String, Object?> frontmatter;

  String _subtitle() {
    final parts = <String>[];
    final relationship = frontmatter['relationship']?.toString().trim();
    if (relationship != null && relationship.isNotEmpty) {
      parts.add(relationship.replaceAll('-', ' ').toUpperCase());
    }
    final species = frontmatter['species']?.toString().trim();
    if (species != null && species.isNotEmpty) {
      parts.add(species.toUpperCase());
    } else {
      final category = frontmatter['category']?.toString().trim();
      if (category != null && category.isNotEmpty) {
        parts.add(category.toUpperCase());
      }
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final photoBytes = petId == null
        ? null
        : ref.watch(profilePhotoBytesProvider(petId!)).maybeWhen(
              data: (b) => b,
              orElse: () => null,
            );
    final displayName = displayPetName(petName);
    final subtitle = _subtitle();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.l),
      child: Column(
        children: [
          _Avatar(bytes: photoBytes, scheme: scheme),
          const SizedBox(height: Spacing.m),
          Text(
            displayName,
            style: JournalText.weeklySummaryTitle(color: scheme.onSurface),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(height: Spacing.xs),
            Text(
              subtitle,
              style: textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.bytes, required this.scheme});

  final Uint8List? bytes;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    const size = 120.0;
    if (bytes == null) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          PhosphorIconsRegular.pawPrint,
          size: 48,
          color: scheme.primary.withValues(alpha: 0.5),
        ),
      );
    }
    return ClipOval(
      child: Image.memory(
        bytes!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        gaplessPlayback: true,
      ),
    );
  }
}

class _AboutCard extends StatelessWidget {
  const _AboutCard({required this.frontmatter, required this.body});

  final Map<String, Object?> frontmatter;
  final String body;

  @override
  Widget build(BuildContext context) {
    final rows = <_FieldRowSpec>[];
    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        rows.add(_FieldRowSpec(label, value));
      }
    }

    add('Species', frontmatter['species']?.toString());
    add('Category', frontmatter['category']?.toString());
    add('Breed', frontmatter['breed']?.toString());
    add('Variety', frontmatter['variety']?.toString());
    add(
      'Relationship',
      frontmatter['relationship']?.toString().replaceAll('-', ' '),
    );
    final workingRole = frontmatter['working_role']?.toString();
    if (workingRole != null &&
        workingRole.isNotEmpty &&
        workingRole != 'none') {
      add('Working role', workingRole.replaceAll('-', ' '));
    }
    final rehabContext = frontmatter['rehab_context']?.toString();
    if (rehabContext != null &&
        rehabContext.isNotEmpty &&
        rehabContext != 'none') {
      add('Rehab context', rehabContext.replaceAll('-', ' '));
    }
    final careContext = frontmatter['care_context']?.toString();
    if (careContext != null &&
        careContext.isNotEmpty &&
        careContext != 'none') {
      add('Care context', careContext.replaceAll('-', ' '));
    }

    final hasBody = body.trim().isNotEmpty;
    if (rows.isEmpty && !hasBody) {
      return PetCard(
        child: Text(
          'Tap the edit pencil to fill in this profile.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
        ),
      );
    }
    return PetCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rows.isNotEmpty) ...[
            for (var i = 0; i < rows.length; i++) ...[
              _FieldRow(spec: rows[i]),
              if (i < rows.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: Spacing.xs),
                  child: Divider(height: 1),
                ),
            ],
          ],
          if (hasBody) ...[
            if (rows.isNotEmpty) const SizedBox(height: Spacing.m),
            Text(
              body,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _DetailsCard extends StatelessWidget {
  const _DetailsCard({required this.frontmatter});

  final Map<String, Object?> frontmatter;

  String? _list(String key) {
    final v = frontmatter[key];
    if (v is List) {
      final cleaned =
          v.map((e) => e.toString().trim()).where((s) => s.isNotEmpty);
      if (cleaned.isEmpty) return null;
      return cleaned.join(', ');
    }
    if (v is String && v.trim().isNotEmpty) return v.trim();
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final rows = <_FieldRowSpec>[];
    void add(String label, String? value) {
      if (value != null && value.isNotEmpty) {
        rows.add(_FieldRowSpec(label, value));
      }
    }

    add('Date of birth', frontmatter['dob']?.toString());
    final dobApprox = frontmatter['dob_approx']?.toString();
    if (dobApprox != null && dobApprox.isNotEmpty) {
      add('Approx. age', dobApprox);
    }
    final adoption = frontmatter['adoption_date']?.toString();
    if (adoption != null && adoption.isNotEmpty) {
      add('Adoption date', adoption);
    }
    final intake = frontmatter['intake_date']?.toString();
    if (intake != null && intake.isNotEmpty) {
      add('Intake date', intake);
    }
    final release = frontmatter['expected_release_date']?.toString();
    if (release != null && release.isNotEmpty) {
      add('Expected release', release);
    }
    final weight = frontmatter['weight_kg'];
    if (weight != null) {
      add('Weight', '$weight kg');
    }
    add('Allergies', _list('allergies'));
    add('Medications', _list('meds'));
    add('Vet contact', frontmatter['vet_contact']?.toString());
    add('Temperament', _list('temperament'));

    if (rows.isEmpty) {
      return PetCard(
        child: Text(
          'No structured details yet.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context)
                    .colorScheme
                    .onSurface
                    .withValues(alpha: 0.65),
              ),
        ),
      );
    }
    return PetCard(
      child: Column(
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            _FieldRow(spec: rows[i]),
            if (i < rows.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: Spacing.xs),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}

class _HealthSummary extends ConsumerWidget {
  const _HealthSummary({required this.petId});
  final int petId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final weightAsync = ref.watch(weightHistoryProvider(petId));
    final symptomsAsync = ref.watch(symptomFrequenciesProvider(petId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        weightAsync.when(
          data: (obs) => WeightChart(observations: obs),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
        const SizedBox(height: Spacing.s),
        symptomsAsync.when(
          data: (freq) => SymptomChart(frequencies: freq),
          loading: () => const SizedBox.shrink(),
          error: (_, _) => const SizedBox.shrink(),
        ),
      ],
    );
  }
}

class _RecentMemoriesCards extends ConsumerWidget {
  const _RecentMemoriesCards();

  static const _monthAbbrev = [
    'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN',
    'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
  ];

  static String _kickerFor(Entry e) {
    final type = _typeLabel(e.type).toUpperCase();
    final month = _monthAbbrev[e.ts.month - 1];
    return '$type · $month ${e.ts.day}';
  }

  static String _typeLabel(String t) {
    switch (t) {
      case 'digest':
        return 'Weekly summary';
      case 'vet':
        return 'Vet visit';
      case 'food':
        return 'Food';
      case 'weight':
        return 'Weight';
      case 'behavior':
        return 'Behavior';
      case 'photos':
        return 'Photo';
      default:
        return t.isEmpty
            ? t
            : '${t[0].toUpperCase()}${t.substring(1)}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final entriesAsync = ref.watch(wikiEntriesProvider);
    return entriesAsync.maybeWhen(
      data: (entries) {
        if (entries.isEmpty) {
          return PetCard(
            child: Text(
              'Recent memories will appear here as you log them.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .onSurface
                        .withValues(alpha: 0.65),
                  ),
            ),
          );
        }
        final top3 = entries.take(3).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final e in top3)
              EditorialCard(
                kicker: _kickerFor(e),
                title: e.title,
                // Phase 6.6 task 6.6.D.1 — vet entries carry the
                // coral medical-attention register on the card
                // level (DECISIONS row 64).
                flagged: e.type == 'vet',
                onTap: () => GoRouter.of(context).push(
                  '/wiki/entry',
                  extra: e.path,
                ),
              ),
          ],
        );
      },
      orElse: () => const SizedBox.shrink(),
    );
  }
}

class _GuidesCard extends StatelessWidget {
  const _GuidesCard({required this.petName});
  final String? petName;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final body = petName == null
        ? 'Species-filtered care guides for this pet.'
        : 'Species-filtered care guides for $petName.';
    return PetCard(
      padding: EdgeInsets.zero,
      child: ListTile(
        leading: Icon(
          PhosphorIconsRegular.bookOpen,
          color: scheme.onSurface.withValues(alpha: 0.8),
        ),
        title: const Text('Care guides'),
        subtitle: Text(body),
        trailing: Icon(
          PhosphorIconsRegular.caretRight,
          color: scheme.onSurface.withValues(alpha: 0.5),
        ),
        onTap: () => GoRouter.of(context).push('/soul/guides'),
      ),
    );
  }
}

class _FieldRowSpec {
  const _FieldRowSpec(this.label, this.value);
  final String label;
  final String value;
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.spec});
  final _FieldRowSpec spec;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Spacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              spec.label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
              ),
            ),
          ),
          Expanded(
            child: Text(
              spec.value,
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
