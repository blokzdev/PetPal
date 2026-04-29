/// Relationship the user has with the animal — locked at DECISIONS row 44
/// as a first-class onboarding question, shown to every user with `pet`
/// pre-selected. Frontmatter values are the row IDs; user-facing labels
/// are locked in VOICE.md §5.5.
enum Relationship {
  pet('pet', 'Pet'),
  rescueRehab('rescue-rehab', 'Rescue / rehab'),
  permanentWildlife('permanent-wildlife', 'Permanent wildlife'),
  wildlifeObservation('wildlife-observation', 'Wildlife observation');

  const Relationship(this.id, this.label);
  final String id;
  final String label;

  static Relationship? fromId(String? id) {
    if (id == null) return null;
    for (final r in Relationship.values) {
      if (r.id == id) return r;
    }
    return null;
  }
}

/// Sub-classification when relationship = pet. DECISIONS row 47 lock —
/// 7 values total. Default `none` reads as "companion" and is OMITTED
/// from disk per the row-45 default-omitted convention.
enum WorkingRole {
  none('none'),
  service('service'),
  esa('esa'),
  therapy('therapy'),
  working('working'),
  breeding('breeding'),
  other('other');

  const WorkingRole(this.id);
  final String id;

  /// Title-case label for picker rendering.
  String get label {
    switch (this) {
      case WorkingRole.none:
        return 'None (companion)';
      case WorkingRole.service:
        return 'Service';
      case WorkingRole.esa:
        return 'ESA';
      case WorkingRole.therapy:
        return 'Therapy';
      case WorkingRole.working:
        return 'Working';
      case WorkingRole.breeding:
        return 'Breeding';
      case WorkingRole.other:
        return 'Other';
    }
  }
}

/// Sub-classification when relationship = rescue-rehab. DECISIONS row 47
/// lock — 9 values total including `conditioning` (wildlife pre-release
/// reconditioning) and `quarantine` (intake isolation). Default `none`
/// is OMITTED from disk.
enum RehabContext {
  none('none'),
  foster('foster'),
  medical('medical'),
  behavioral('behavioral'),
  palliative('palliative'),
  neonatal('neonatal'),
  conditioning('conditioning'),
  quarantine('quarantine'),
  other('other');

  const RehabContext(this.id);
  final String id;

  String get label {
    switch (this) {
      case RehabContext.none:
        return 'None';
      case RehabContext.foster:
        return 'Foster';
      case RehabContext.medical:
        return 'Medical';
      case RehabContext.behavioral:
        return 'Behavioral';
      case RehabContext.palliative:
        return 'Palliative';
      case RehabContext.neonatal:
        return 'Neonatal';
      case RehabContext.conditioning:
        return 'Conditioning';
      case RehabContext.quarantine:
        return 'Quarantine';
      case RehabContext.other:
        return 'Other';
    }
  }
}

/// Sub-classification when relationship = permanent-wildlife. DECISIONS
/// row 45 lock — 5 values. Default `none` is OMITTED from disk.
enum CareContext {
  none('none'),
  sanctuary('sanctuary'),
  educational('educational'),
  nonReleasable('non-releasable'),
  other('other');

  const CareContext(this.id);
  final String id;

  String get label {
    switch (this) {
      case CareContext.none:
        return 'None';
      case CareContext.sanctuary:
        return 'Sanctuary';
      case CareContext.educational:
        return 'Educational';
      case CareContext.nonReleasable:
        return 'Non-releasable';
      case CareContext.other:
        return 'Other';
    }
  }
}

/// Pet sex — three-state ternary. `unknown` is the default and is OMITTED
/// from SOUL frontmatter on disk (not written as `sex: unknown`). Reading
/// code treats absent `sex:` as `unknown`. Same default-omitted pattern
/// as sub-classification fields per DECISIONS row 45.
enum PetSex {
  male('male'),
  female('female'),
  unknown('unknown');

  const PetSex(this.id);
  final String id;

  String get label {
    switch (this) {
      case PetSex.male:
        return 'Male';
      case PetSex.female:
        return 'Female';
      case PetSex.unknown:
        return 'Unknown';
    }
  }
}

/// Neutered status — three-state ternary. `unknown` is the default and is
/// OMITTED from disk. Reading code treats absent `neutered:` as unknown.
enum NeuteredStatus {
  yes('yes'),
  no('no'),
  unknown('unknown');

  const NeuteredStatus(this.id);
  final String id;

  String get label {
    switch (this) {
      case NeuteredStatus.yes:
        return 'Yes';
      case NeuteredStatus.no:
        return 'No';
      case NeuteredStatus.unknown:
        return 'Unknown';
    }
  }
}

/// Which lifecycle date the user is providing. Mutually exclusive — the
/// add-pet form requires exactly one of the three to be filled.
/// `intakeDate` and `expectedReleaseDate` are separate fields shown only
/// when relationship = rescue-rehab.
enum LifecycleDateKind {
  dob, // exact date of birth
  approxAge, // approximate age in years
  adoptionDate, // date they came home (no DOB known)
}
