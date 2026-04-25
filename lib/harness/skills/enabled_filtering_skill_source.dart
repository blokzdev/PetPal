import '../../data/repos/skill_repo.dart';
import 'skill_source.dart';

/// Decorator over an underlying [SkillSource] that drops any skill the
/// user has explicitly disabled (per [SkillRepo.disabledIds]). Default
/// state for unregistered skills is enabled.
///
/// Composes cleanly: the inner source still owns discovery (asset bundle
/// vs filesystem vs in-memory); this layer only adds the
/// "user-facing on/off switch" filter.
class EnabledFilteringSkillSource implements SkillSource {
  EnabledFilteringSkillSource({
    required SkillSource inner,
    required SkillRepo repo,
  })  : _inner = inner,
        _repo = repo;

  final SkillSource _inner;
  final SkillRepo _repo;

  @override
  Future<List<SkillSourceEntry>> list() async {
    final disabled = await _repo.disabledIds();
    final all = await _inner.list();
    return [
      for (final e in all)
        if (!disabled.contains(e.manifest.id)) e,
    ];
  }
}
