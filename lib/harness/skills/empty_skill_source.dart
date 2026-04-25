import 'skill_source.dart';

/// Default [SkillSource] used until Phase 3.5 ships bundled skill packs.
/// Returns no skills, so [SkillLoader.match] always emits an empty list
/// — keeping the production wiring valid before assets exist.
class EmptySkillSource implements SkillSource {
  const EmptySkillSource();

  @override
  Future<List<SkillSourceEntry>> list() async => const [];
}
