import 'dart:convert';

import 'package:http/http.dart' as http;

/// The example server's own accounts (an email and a password). Your app
/// has its own; passkeys sit on top of it.
class AccountApi {
  AccountApi(this.baseUrl, {http.Client? client})
    : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;

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

  /// Ends the session on the server.
  Future<void> logout(String token) async {
    await _client.post(
      baseUrl.resolve('auth/logout'),
      headers: {'Authorization': 'Bearer $token'},
    );
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, Object?> body,
  ) async {
    final http.Response response;
    try {
      response = await _client.post(
        baseUrl.resolve(path),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } on http.ClientException {
      throw const ApiException("We couldn't reach the server. Is it running?");
    }
    final json = response.body.isEmpty ? null : jsonDecode(response.body);
    if (response.statusCode >= 400) {
      throw ApiException(
        json is Map && json['message'] is String
            ? json['message'] as String
            : 'Something went wrong. Please try again.',
      );
    }
    return json as Map<String, dynamic>;
  }
}

/// A server error, with its message ready to show.
class ApiException implements Exception {
  const ApiException(this.message);

  final String message;

  @override
  String toString() => message;
}
