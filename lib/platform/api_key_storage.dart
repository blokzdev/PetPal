import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// At-rest storage for the user's Anthropic API key. Wraps
/// [FlutterSecureStorage] so the rest of the app can be written against an
/// interface that's also fakeable in widget tests.
abstract class ApiKeyStorage {
  Future<String?> read();
  Future<void> write(String apiKey);
  Future<void> clear();
}

class SecureApiKeyStorage implements ApiKeyStorage {
  SecureApiKeyStorage({FlutterSecureStorage? storage})
      : _storage = storage ?? const FlutterSecureStorage();

  static const _key = 'anthropic_api_key';
  final FlutterSecureStorage _storage;

  @override
  Future<String?> read() => _storage.read(key: _key);

  @override
  Future<void> write(String apiKey) =>
      _storage.write(key: _key, value: apiKey);

  @override
  Future<void> clear() => _storage.delete(key: _key);
}
