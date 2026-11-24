import 'package:dio/dio.dart';

/// The app's one [Dio], for the account calls and the passkeys alike: the
/// server's URL, timeouts, and [AppInterceptors].
Dio createDio(Uri serverUrl, {required String? Function() token}) => Dio(
  BaseOptions(
    baseUrl: serverUrl.toString(),
    connectTimeout: const Duration(seconds: 20),
    receiveTimeout: const Duration(seconds: 30),
  ),
)..interceptors.add(AppInterceptors(token));

/// What every request needs: JSON, and the session's token once signed in.
class AppInterceptors extends Interceptor {
  AppInterceptors(this._token);

  final String? Function() _token;

  @override
  void onRequest(RequestOptions options, RequestInterceptorHandler handler) {
    options.headers['Accept'] = 'application/json';
    final token = _token();
    if (token != null) options.headers['Authorization'] = 'Bearer $token';
    handler.next(options);
  }
}
