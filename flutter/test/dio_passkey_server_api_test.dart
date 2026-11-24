import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

/// One request, as the server got it.
class SentRequest {
  SentRequest(this.options, this.body);

  final RequestOptions options;

  /// The JSON body, decoded. Null when there was none.
  final Object? body;

  String get method => options.method;
  Uri get url => options.uri;
  Map<String, dynamic> get headers => options.headers;
}

/// Dio's way to the server, faked: [answer] says what the server sends
/// back, as JSON with [status], or throws the error Dio would.
class FakeAdapter implements HttpClientAdapter {
  FakeAdapter(this.answer, {this.status = 200});

  final Object? Function(SentRequest request) answer;
  final int status;
  final List<SentRequest> requests = [];

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final bytes = await requestStream?.expand((chunk) => chunk).toList();
    final request = SentRequest(
      options,
      bytes == null ? null : jsonDecode(utf8.decode(bytes)),
    );
    requests.add(request);
    final body = answer(request);
    return ResponseBody.fromString(
      body == null ? '' : jsonEncode(body),
      status,
      headers: {
        Headers.contentTypeHeader: ['application/json; charset=utf-8'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  late FakeAdapter adapter;

  DioPasskeyServerApi api(
    Object? Function(SentRequest request) answer, {
    int status = 200,
  }) {
    adapter = FakeAdapter(answer, status: status);
    return DioPasskeyServerApi(
      // No trailing slash: the routes still go under /auth/passkeys/.
      baseUrl: Uri.parse('https://api.example.com/auth/passkeys'),
      headers: () => {'Authorization': 'Bearer token-1'},
      dio: Dio()..httpClientAdapter = adapter,
    );
  }

  Matcher failsWith(PasskeyFailure reason) => throwsA(
    isA<PasskeyException>().having((e) => e.reason, 'reason', reason),
  );

  test(
    'sends JSON to the routes under the base URL, with your headers',
    () async {
      final server = api((_) => {'challenge': 'abc'});

      final options = await server.loginOptions();

      expect(options, {'challenge': 'abc'});
      final request = adapter.requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.example.com/auth/passkeys/login/options',
      );
      expect(request.headers['Authorization'], 'Bearer token-1');
      expect(request.headers['Accept'], 'application/json');
      expect(request.options.contentType, startsWith('application/json'));
      expect(request.body, isEmpty);
    },
  );

  test(
    'registerVerify sends the answer and the name, and reads the passkey',
    () async {
      final server = api(
        (_) => {
          'id': 'pk1',
          'name': 'iPhone 17 Pro',
          'deviceType': 'multiDevice',
          'backedUp': true,
          'createdAt': '2026-11-21T10:00:00.000Z',
          'lastUsedAt': null,
        },
      );

      final passkey = await server.registerVerify({
        'id': 'pk1',
      }, name: 'iPhone 17 Pro');

      expect(adapter.requests.single.body, {
        'response': {'id': 'pk1'},
        'name': 'iPhone 17 Pro',
      });
      expect(passkey.id, 'pk1');
      expect(passkey.isSynced, isTrue);
      expect(passkey.createdAt, DateTime.utc(2026, 11, 21, 10).toLocal());
      expect(passkey.lastUsedAt, isNull);
    },
  );

  test('list reads every passkey', () async {
    final server = api(
      (_) => [
        {'id': 'pk2', 'name': 'iPad'},
        {'id': 'pk1', 'name': 'iPhone'},
      ],
    );

    final passkeys = await server.list();

    expect(adapter.requests.single.method, 'GET');
    expect(
      adapter.requests.single.url.toString(),
      'https://api.example.com/auth/passkeys/',
    );
    expect(passkeys.map((p) => p.id), ['pk2', 'pk1']);
  });

  test('delete puts the id in the path', () async {
    final server = api((_) => null);

    await server.delete('a/b');

    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.url.path, '/auth/passkeys/a%2Fb');
  });

  test("an error is a PasskeyException with the server's message", () async {
    final server = api((_) => {'message': 'Not this one.'}, status: 401);

    await expectLater(
      server.loginVerify({'id': 'x'}),
      throwsA(
        isA<PasskeyException>()
            .having((e) => e.reason, 'reason', PasskeyFailure.server)
            .having((e) => e.statusCode, 'statusCode', 401)
            .having((e) => e.message, 'message', 'Not this one.'),
      ),
    );
  });

  test('an error with no message gets the default one', () async {
    final server = api((_) => null, status: 500);

    await expectLater(
      server.list(),
      throwsA(
        isA<PasskeyException>().having(
          (e) => e.message,
          'message',
          defaultPasskeyMessages[PasskeyFailure.server],
        ),
      ),
    );
  });

  test('no connection, or no answer in time, is a network failure', () async {
    final offline = api(
      (request) => throw DioException.connectionError(
        requestOptions: request.options,
        reason: 'offline',
      ),
    );
    await expectLater(
      offline.loginOptions(),
      failsWith(PasskeyFailure.network),
    );

    final slow = api(
      (request) => throw DioException.receiveTimeout(
        timeout: const Duration(seconds: 30),
        requestOptions: request.options,
      ),
    );
    await expectLater(slow.loginOptions(), failsWith(PasskeyFailure.network));
  });

  test('a request your Dio cancelled is cancelled: nothing to show', () async {
    final server = api(
      (request) => throw DioException.requestCancelled(
        requestOptions: request.options,
        reason: 'signed out',
      ),
    );

    await expectLater(
      server.list(),
      throwsA(
        isA<PasskeyException>()
            .having((e) => e.isCancelled, 'isCancelled', isTrue)
            .having((e) => e.message, 'message', isEmpty),
      ),
    );
  });

  group('with your own Dio', () {
    test('a relative baseUrl goes under its baseUrl, through its '
        'interceptors', () async {
      final adapter = FakeAdapter((_) => []);
      final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/api/v1/'))
        ..httpClientAdapter = adapter
        ..interceptors.add(
          InterceptorsWrapper(
            onRequest: (options, handler) {
              options.headers['Authorization'] = 'Bearer from-interceptor';
              handler.next(options);
            },
          ),
        );
      final server = DioPasskeyServerApi(
        baseUrl: Uri.parse('auth/passkeys'),
        dio: dio,
      );

      await server.list();

      final request = adapter.requests.single;
      expect(
        request.url.toString(),
        'https://api.example.com/api/v1/auth/passkeys/',
      );
      // What your interceptors see, to match it against your own paths.
      expect(request.options.path, 'auth/passkeys/');
      expect(request.headers['Authorization'], 'Bearer from-interceptor');
    });

    test('an error is still an error when your Dio accepts 4xx', () async {
      final adapter = FakeAdapter(
        (_) => {'message': 'Sign in first.'},
        status: 401,
      );
      final dio = Dio(BaseOptions(validateStatus: (status) => status! < 500))
        ..httpClientAdapter = adapter;
      final server = DioPasskeyServerApi(
        baseUrl: Uri.parse('https://api.example.com/auth/passkeys/'),
        dio: dio,
      );

      await expectLater(
        server.registerOptions(),
        throwsA(
          isA<PasskeyException>()
              .having((e) => e.reason, 'reason', PasskeyFailure.server)
              .having((e) => e.statusCode, 'statusCode', 401)
              .having((e) => e.message, 'message', 'Sign in first.'),
        ),
      );
    });
  });
}
