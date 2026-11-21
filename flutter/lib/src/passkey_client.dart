import 'passkey_device.dart';
import 'passkey_exception.dart';
import 'passkey_info.dart';
import 'passkey_server_api.dart';

/// Passkeys for your app: signing in, adding one, and the user's list.
///
/// Every call can throw a [PasskeyException]. When
/// [PasskeyException.isCancelled], the user closed the sheet: show nothing.
///
/// ```dart
/// final passkeys = PasskeyClient(
///   server: HttpPasskeyServerApi(
///     baseUrl: Uri.parse('https://api.example.com/auth/passkeys'),
///     headers: () => {'Authorization': 'Bearer $token'},
///   ),
/// );
///
/// if (await passkeys.isAvailable()) {
///   final session = await passkeys.signIn();
/// }
/// ```
class PasskeyClient {
  /// [device] defaults to the real phone ([SystemPasskeyDevice]).
  PasskeyClient({required PasskeyServerApi server, PasskeyDevice? device})
    : _server = server,
      _device = device ?? SystemPasskeyDevice();

  final PasskeyServerApi _server;
  final PasskeyDevice _device;

  /// iOS 16+, or Android 9+ with Google Play services and a screen lock.
  /// Hide your passkey buttons when it's false.
  Future<bool> isAvailable() => _device.isAvailable();

  /// Shows the passkey sheet and signs the user in: no email, no password.
  /// Returns your server's session, as its `signIn` hook made it.
  Future<Map<String, dynamic>> signIn() async {
    final options = await _server.loginOptions();
    final response = await _device.authenticate(options);
    return _server.loginVerify(response);
  }

  /// Makes a passkey on this phone for the signed-in user, named [name] or
  /// after the phone ("iPhone 17 Pro").
  Future<PasskeyInfo> register({String? name}) async {
    final options = await _server.registerOptions();
    final response = await _device.register(options);
    return _server.registerVerify(response, name: name ?? await _device.name());
  }

  /// The signed-in user's passkeys, the newest first.
  Future<List<PasskeyInfo>> list() => _server.list();

  /// Deletes one on the server. The phone keeps it in its password manager
  /// until the user deletes it there too, but it can't sign in any more.
  Future<void> delete(String id) => _server.delete(id);
}
