import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'passkey_exception.dart';
import 'passkey_info.dart';

/// The server side of passkeys: the routes of the kit's Express router.
/// Implement it yourself to use Dio or your own client, or use
/// [HttpPasskeyServerApi].
abstract interface class PasskeyServerApi {
  /// `POST register/options`: what the phone needs to make a passkey.
  Future<Map<String, dynamic>> registerOptions();

  /// `POST register/verify` with the phone's answer.
  Future<PasskeyInfo> registerVerify(
    Map<String, dynamic> response, {
    String? name,
  });

  /// `POST login/options`: a challenge any passkey of the app can sign.
  Future<Map<String, dynamic>> loginOptions();

  /// `POST login/verify`: your server's session, as its `signIn` hook made it.
  Future<Map<String, dynamic>> loginVerify(Map<String, dynamic> response);

  /// `GET /`: the signed-in user's passkeys, the newest first.
  Future<List<PasskeyInfo>> list();

  /// `DELETE /:id`.
  Future<void> delete(String id);
}

/// [PasskeyServerApi] over `package:http`.
class HttpPasskeyServerApi implements PasskeyServerApi {
  /// [baseUrl] is where the router is mounted, like
  /// `https://api.example.com/auth/passkeys`. [headers] runs before every
  /// request: return your auth header there.
  HttpPasskeyServerApi({
    required Uri baseUrl,
    FutureOr<Map<String, String>> Function()? headers,
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
  }) : _baseUrl = baseUrl.path.endsWith('/')
           ? baseUrl
           : baseUrl.replace(path: '${baseUrl.path}/'),
       _headers = headers,
       _client = client ?? http.Client();

  final Uri _baseUrl;
  final FutureOr<Map<String, String>> Function()? _headers;
  final http.Client _client;

  /// How long one request may take.
  final Duration timeout;

  @override
  Future<Map<String, dynamic>> registerOptions() async =>
      await _send('POST', 'register/options', body: const {})
          as Map<String, dynamic>;

  @override
  Future<PasskeyInfo> registerVerify(
    Map<String, dynamic> response, {
    String? name,
  }) async => PasskeyInfo.fromJson(
    await _send(
          'POST',
          'register/verify',
          body: {'response': response, 'name': ?name},
        )
        as Map<String, dynamic>,
  );

  @override
  Future<Map<String, dynamic>> loginOptions() async =>
      await _send('POST', 'login/options', body: const {})
          as Map<String, dynamic>;

  @override
  Future<Map<String, dynamic>> loginVerify(
    Map<String, dynamic> response,
  ) async =>
      await _send('POST', 'login/verify', body: {'response': response})
          as Map<String, dynamic>;

  @override
  Future<List<PasskeyInfo>> list() async {
    final items = await _send('GET', '') as List<dynamic>;
    return [
      for (final item in items)
        PasskeyInfo.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> delete(String id) async {
    await _send('DELETE', Uri.encodeComponent(id));
  }

  Future<Object?> _send(String method, String path, {Object? body}) async {
    final request = http.Request(method, _baseUrl.resolve(path));
    request.headers.addAll({
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      ...?await _headers?.call(),
    });
    if (body != null) request.body = jsonEncode(body);

    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      );
    } on TimeoutException catch (error) {
      throw PasskeyException(PasskeyFailure.network, cause: error);
    } on http.ClientException catch (error) {
      throw PasskeyException(PasskeyFailure.network, cause: error);
    }

    final decoded = response.body.isEmpty ? null : _decode(response.body);
    if (response.statusCode >= 400) {
      throw PasskeyException(
        PasskeyFailure.server,
        message: decoded is Map ? decoded['message'] as String? : null,
        statusCode: response.statusCode,
      );
    }
    return decoded;
  }

  static Object? _decode(String body) {
    try {
      return jsonDecode(body);
    } on FormatException {
      return null;
    }
  }
}
