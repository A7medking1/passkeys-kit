import 'dart:async';

import 'package:dio/dio.dart';

import 'passkey_exception.dart';
import 'passkey_info.dart';

/// The server side of passkeys: the routes of the kit's Express router.
/// [DioPasskeyServerApi] implements it over Dio. Implement it yourself to
/// use another client.
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

/// [PasskeyServerApi] over Dio.
///
/// Give it your app's [Dio] to reuse it: its interceptors (your token, a
/// refresh on 401, a logger), timeouts and adapter apply to the passkey
/// routes too. Without one, it makes its own.
class DioPasskeyServerApi implements PasskeyServerApi {
  /// [baseUrl] is where the router is mounted, like
  /// `https://api.example.com/auth/passkeys`. With your own [dio], it can be
  /// a path under the Dio's `baseUrl` instead, like `auth/passkeys`.
  ///
  /// [headers] runs before every request: return your auth header there, or
  /// leave it out when an interceptor of your [dio] adds it.
  ///
  /// The Dio it makes waits 20 seconds to connect and 30 seconds for an
  /// answer. For other timeouts, pass your own [dio].
  DioPasskeyServerApi({
    required Uri baseUrl,
    FutureOr<Map<String, String>> Function()? headers,
    Dio? dio,
  }) : assert(
         baseUrl.hasScheme || dio != null,
         'A relative baseUrl goes under the baseUrl of your Dio: pass `dio`.',
       ),
       _baseUrl = baseUrl.path.endsWith('/')
           ? baseUrl
           : baseUrl.replace(path: '${baseUrl.path}/'),
       _headers = headers,
       _dio =
           dio ??
           Dio(
             BaseOptions(
               connectTimeout: const Duration(seconds: 20),
               receiveTimeout: const Duration(seconds: 30),
             ),
           );

  final Uri _baseUrl;
  final FutureOr<Map<String, String>> Function()? _headers;
  final Dio _dio;

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
    final headers = {'Accept': 'application/json', ...?await _headers?.call()};
    try {
      final response = await _dio.request<Object?>(
        _baseUrl.resolve(path).toString(),
        data: body,
        options: Options(
          method: method,
          headers: headers,
          contentType: body == null ? null : Headers.jsonContentType,
          responseType: ResponseType.json,
          // Set here, so a Dio that accepts 4xx answers still throws on them,
          // with the server's message.
          validateStatus: (status) =>
              status != null && status >= 200 && status < 300,
          receiveDataWhenStatusError: true,
        ),
      );
      return response.data;
    } on DioException catch (error) {
      throw _toPasskeyException(error);
    }
  }

  /// Dio's error, as the [PasskeyFailure] the app expects.
  static PasskeyException _toPasskeyException(DioException error) {
    switch (error.type) {
      case DioExceptionType.badResponse:
        final data = error.response?.data;
        final message = data is Map ? data['message'] : null;
        return PasskeyException(
          PasskeyFailure.server,
          message: message is String ? message : null,
          statusCode: error.response?.statusCode,
          cause: error,
        );
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
      case DioExceptionType.transformTimeout:
      case DioExceptionType.connectionError:
      case DioExceptionType.badCertificate:
        return PasskeyException(PasskeyFailure.network, cause: error);
      case DioExceptionType.cancel:
        // Your Dio cancelled it: there's nothing to show.
        return PasskeyException(PasskeyFailure.cancelled, cause: error);
      default:
        // DioExceptionType.unknown, and any type a newer Dio adds.
        return PasskeyException(PasskeyFailure.unknown, cause: error);
    }
  }
}
