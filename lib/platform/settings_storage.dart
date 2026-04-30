import 'package:shared_preferences/shared_preferences.dart';

/// At-rest storage for non-sensitive preferences (the weekly digest
/// toggle, the affective-observations toggle, the per-pet
/// affective-frequency-cap counter). Wraps [SharedPreferences] so the
/// rest of the app can be written against an interface that's
/// fakeable in tests.
abstract class SettingsStorage {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);

  /// Phase 6 task 6.8 — int storage for the affective observer's
  /// frequency-cap counter (`affective_count_at_last_fire_<petId>`).
  /// Generic enough for future int-keyed prefs.
  Future<int?> getInt(String key);
  Future<void> setInt(String key, int value);
}

class SharedPrefsSettingsStorage implements SettingsStorage {
  SharedPrefsSettingsStorage(this._prefs);

  /// Opens the platform default. Call once in `main()` and pass the
  /// instance into the [ProviderScope] override.
  static Future<SharedPrefsSettingsStorage> open() async {
    final prefs = await SharedPreferences.getInstance();
    return SharedPrefsSettingsStorage(prefs);
  }

  final SharedPreferences _prefs;

  @override
  Future<bool?> getBool(String key) async => _prefs.getBool(key);

  @override
  Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  @override
  Future<int?> getInt(String key) async => _prefs.getInt(key);

  @override
  Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }
}

/// In-memory [SettingsStorage] for tests.
class InMemorySettingsStorage implements SettingsStorage {
  InMemorySettingsStorage([Map<String, Object>? seed])
      : _bools = {
          for (final e in (seed ?? const {}).entries)
            if (e.value is bool) e.key: e.value as bool,
        },
        _ints = {
          for (final e in (seed ?? const {}).entries)
            if (e.value is int) e.key: e.value as int,
        };

  final Map<String, bool> _bools;
  final Map<String, int> _ints;

  @override
  Future<bool?> getBool(String key) async => _bools[key];

  @override
  Future<void> setBool(String key, bool value) async {
    _bools[key] = value;
  }

  @override
  Future<int?> getInt(String key) async => _ints[key];

  @override
  Future<void> setInt(String key, int value) async {
    _ints[key] = value;
  }
}
