
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:petpal/app/byok/byok_validator.dart';

/// Phase 7 task F.1 — BYOK validator unit tests.
///
/// Pins the DECISIONS row 74 contract: format check first, live
/// ping `/v1/models` second, with status-code → result mapping
/// (200 = Accepted, 401 / 403 = RejectedAuth, anything else =
/// NetworkError soft-warning).
void main() {
  test('format check rejects keys missing the sk-ant- prefix',
      () async {
    final v = ByokValidator(httpClient: MockClient((_) async {
      throw StateError('http should not be called on a format-rejected key');
    }));
    expect(
      await v.validate('not-an-anthropic-key'),
      isA<ByokRejectedFormat>(),
    );
  });

  test('format check rejects sk-ant- keys shorter than 40 chars after the '
      'prefix', () async {
    final v = ByokValidator(httpClient: MockClient((_) async {
      throw StateError('http should not be called on a format-rejected key');
    }));
    expect(
      await v.validate('sk-ant-tooshort'),
      isA<ByokRejectedFormat>(),
    );
  });

  test('format check rejects keys with characters outside [A-Za-z0-9_-]',
      () async {
    final v = ByokValidator(httpClient: MockClient((_) async {
      throw StateError('http should not be called on a format-rejected key');
    }));
    final invalid = 'sk-ant-${'a' * 40}!';
    expect(
      await v.validate(invalid),
      isA<ByokRejectedFormat>(),
    );
  });

  test('format check trims surrounding whitespace before matching',
      () async {
    final captured = <Uri>[];
    final v = ByokValidator(
      httpClient: MockClient((req) async {
        captured.add(req.url);
        return http.Response('{}', 200);
      }),
    );
    final padded = '  sk-ant-${'a' * 40}  ';
    final result = await v.validate(padded);
    expect(result, isA<ByokAccepted>());
    expect(captured.single.toString(),
        'https://api.anthropic.com/v1/models');
  });

  test('200 from /v1/models → Accepted', () async {
    final v = ByokValidator(
      httpClient: MockClient((req) async {
        expect(req.headers['x-api-key'], 'sk-ant-${'a' * 40}');
        expect(req.headers['anthropic-version'], '2023-06-01');
        return http.Response('{"data": []}', 200);
      }),
    );
    expect(
      await v.validate('sk-ant-${'a' * 40}'),
      isA<ByokAccepted>(),
    );
  });

  test('401 → RejectedAuth', () async {
    final v = ByokValidator(
      httpClient: MockClient((_) async => http.Response('{}', 401)),
    );
    expect(
      await v.validate('sk-ant-${'a' * 40}'),
      isA<ByokRejectedAuth>(),
    );
  });

  test('403 → RejectedAuth', () async {
    final v = ByokValidator(
      httpClient: MockClient((_) async => http.Response('{}', 403)),
    );
    expect(
      await v.validate('sk-ant-${'a' * 40}'),
      isA<ByokRejectedAuth>(),
    );
  });

  test('500 → NetworkError (soft-warning per row 74)', () async {
    final v = ByokValidator(
      httpClient: MockClient((_) async => http.Response('boom', 500)),
    );
    final result = await v.validate('sk-ant-${'a' * 40}');
    expect(result, isA<ByokNetworkError>());
    expect((result as ByokNetworkError).message, contains('500'));
  });

  test('thrown http exception → NetworkError (soft-warning per row 74)',
      () async {
    final v = ByokValidator(
      httpClient: MockClient((_) async {
        throw const SocketException('no route to host');
      }),
    );
    expect(
      await v.validate('sk-ant-${'a' * 40}'),
      isA<ByokNetworkError>(),
    );
  });
}

/// Local SocketException stand-in. We can't import dart:io in a
/// unit test cleanly when MockClient is in play; this Exception
/// subtype is enough for the catch path to surface NetworkError.
class SocketException implements Exception {
  const SocketException(this.message);
  final String message;
  @override
  String toString() => 'SocketException: $message';
}
