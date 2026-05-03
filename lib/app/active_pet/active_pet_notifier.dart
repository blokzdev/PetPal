import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../platform/settings_storage.dart';
import '../providers.dart';

/// Phase 7 task E.2 — persisted active-pet selection.
///
/// Holds the user's explicitly chosen pet ID across app launches.
/// `null` = no selection persisted yet (callers fall back to
/// `pets.last.id`). Backed by [SettingsStorage] under
/// `active_pet_id`. The fallback semantics live in
/// `activePetIdProvider` / `activePetProvider` — this notifier only
/// owns the persisted preference.
class ActivePetNotifier extends AsyncNotifier<int?> {
  static const _key = 'active_pet_id';

  @override
  Future<int?> build() async {
    return ref.read(settingsStorageProvider).getInt(_key);
  }

  /// Persist + emit a new selection.
  Future<void> select(int petId) async {
    await ref.read(settingsStorageProvider).setInt(_key, petId);
    state = AsyncData(petId);
  }
}

/// Phase 7 task E.2 — provider for the persisted selection. UI code
/// should usually read [activePetProvider] (resolved Pet) or
/// [activePetIdProvider] (callable int with fallback) instead;
/// this provider is the raw stored preference.
final activePetSelectionProvider =
    AsyncNotifierProvider<ActivePetNotifier, int?>(ActivePetNotifier.new);
