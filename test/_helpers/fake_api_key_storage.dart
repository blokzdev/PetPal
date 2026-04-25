import 'package:petpal/platform/api_key_storage.dart';

/// In-memory [ApiKeyStorage] for widget tests. Construct with [initial] to
/// preload a key (simulates an onboarded user).
class FakeApiKeyStorage implements ApiKeyStorage {
  FakeApiKeyStorage({String? initial}) : _key = initial;
  String? _key;

  @override
  Future<String?> read() async => _key;

  @override
  Future<void> write(String apiKey) async => _key = apiKey;

  @override
  Future<void> clear() async => _key = null;
}
