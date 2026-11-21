import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

void main() {
  late List<http.Request> requests;

  HttpPasskeyServerApi api(
    Object? Function(http.Request request) answer, {
    int status = 200,
  }) {
    requests = [];
    return HttpPasskeyServerApi(
      // No trailing slash: the routes still go under /auth/passkeys/.
      baseUrl: Uri.parse('https://api.example.com/auth/passkeys'),
      headers: () => {'Authorization': 'Bearer token-1'},
      client: MockClient((request) async {
        requests.add(request);
        final body = answer(request);
        return http.Response(
          body == null ? '' : jsonEncode(body),
          status,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );
  }

  test(
    'sends JSON to the routes under the base URL, with your headers',
    () async {
      final server = api((_) => {'challenge': 'abc'});

      final options = await server.loginOptions();

      expect(options, {'challenge': 'abc'});
      final request = requests.single;
      expect(request.method, 'POST');
      expect(
        request.url.toString(),
        'https://api.example.com/auth/passkeys/login/options',
      );
      expect(request.headers['Authorization'], 'Bearer token-1');
      expect(jsonDecode(request.body), isEmpty);
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

      expect(jsonDecode(requests.single.body), {
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

    expect(requests.single.method, 'GET');
    expect(passkeys.map((p) => p.id), ['pk2', 'pk1']);
  });

  test('delete puts the id in the path', () async {
    final server = api((_) => null);

    await server.delete('a/b');

    expect(requests.single.method, 'DELETE');
    expect(requests.single.url.path, '/auth/passkeys/a%2Fb');
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

  test('no connection is a network failure', () async {
    final server = HttpPasskeyServerApi(
      baseUrl: Uri.parse('https://api.example.com/auth/passkeys/'),
      client: MockClient((_) async => throw http.ClientException('offline')),
    );

    await expectLater(
      server.loginOptions(),
      throwsA(
        isA<PasskeyException>().having(
          (e) => e.reason,
          'reason',
          PasskeyFailure.network,
        ),
      ),
    );
  });
}
