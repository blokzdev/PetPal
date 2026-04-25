import 'package:shared_preferences/shared_preferences.dart';

/// At-rest storage for non-sensitive boolean preferences (the weekly
/// digest toggle, future on/off switches). Wraps [SharedPreferences] so
/// the rest of the app can be written against an interface that's
/// fakeable in tests.
abstract class SettingsStorage {
  Future<bool?> getBool(String key);
  Future<void> setBool(String key, bool value);
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
}

/// In-memory [SettingsStorage] for tests.
class InMemorySettingsStorage implements SettingsStorage {
  InMemorySettingsStorage([Map<String, bool>? seed])
      : _values = {...?seed};

  final Map<String, bool> _values;

  @override
  Future<bool?> getBool(String key) async => _values[key];

  @override
  Future<void> setBool(String key, bool value) async {
    _values[key] = value;
  }
}
