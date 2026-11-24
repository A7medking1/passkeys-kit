import 'package:dio/dio.dart';

/// The example server's own accounts (an email and a password). Your app
/// has its own; passkeys sit on top of it.
class AccountApi {
  /// [_dio] is the app's, with the server as its baseUrl.
  AccountApi(this._dio);

  final Dio _dio;

  /// `{ token, user }`, signed in.
  Future<Map<String, dynamic>> register({
    required String name,
    required String email,
    required String password,
  }) => _post('auth/register', {
    'name': name,
    'email': email,
    'password': password,
  });

  /// `{ token, user }`, the same answer as a passkey sign-in.
  Future<Map<String, dynamic>> login({
    required String email,
    required String password,
  }) => _post('auth/login', {'email': email, 'password': password});

  /// Ends the session on the server. The app has dropped [token] already,
  /// so it's sent here rather than by the interceptor.
  Future<void> logout(String token) async {
    await _dio.post<void>(
      'auth/logout',
      options: Options(headers: {'Authorization': 'Bearer $token'}),
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    try {
      final response = await _dio.post<Map<String, dynamic>>(path, data: body);
      return response.data!;
    } on DioException catch (error) {
      throw ApiException.fromDio(error);
    }
  }
}

/// A server error, with its message ready to show.
class ApiException implements Exception {
  const ApiException(this.message);

  /// The server's own message when it gave one, or what went wrong on the
  /// way there.
  factory ApiException.fromDio(DioException error) {
    final data = error.response?.data;
    final message = data is Map ? data['message'] : null;
    return ApiException(switch (error.type) {
      DioExceptionType.badResponse when message is String => message,
      DioExceptionType.connectionError || DioExceptionType.connectionTimeout =>
        "We couldn't reach the server. Is it running?",
      DioExceptionType.sendTimeout || DioExceptionType.receiveTimeout =>
        'The server took too long to answer. Please try again.',
      _ => 'Something went wrong. Please try again.',
    });
  }

  final String message;

  @override
  String toString() => message;
}
