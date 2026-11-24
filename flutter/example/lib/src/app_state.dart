import 'package:flutter/widgets.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

import 'account_api.dart';
import 'dio_client.dart';

/// The signed-in account.
class Account {
  const Account({required this.id, required this.name, required this.email});

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    id: json['id'] as String,
    name: json['name'] as String,
    email: json['email'] as String,
  );

  final String id;
  final String name;
  final String email;
}

/// The session, and the two ways to open it: a password or a passkey. Both
/// answer `{ token, user }`, so they end the same way.
class AppState extends ChangeNotifier {
  AppState({
    required Uri serverUrl,
    AccountApi? accounts,
    PasskeyClient? passkeys,
  }) {
    // One Dio for every call. Its interceptor sends the token once signed in.
    final dio = createDio(serverUrl, token: () => _token);
    this.accounts = accounts ?? AccountApi(dio);
    this.passkeys =
        passkeys ??
        PasskeyClient(
          // Where the router is mounted, under the Dio's baseUrl.
          server: DioPasskeyServerApi(
            baseUrl: Uri.parse('auth/passkeys'),
            dio: dio,
          ),
        );
  }

  late final AccountApi accounts;
  late final PasskeyClient passkeys;

  String? _token;
  Account? _account;
  SignInMethod? _method;

  Account? get account => _account;
  bool get isSignedIn => _account != null;

  /// How this session was opened, for the badge on the home screen.
  SignInMethod? get method => _method;

  Future<void> signUp({
    required String name,
    required String email,
    required String password,
  }) async => _open(
    await accounts.register(name: name, email: email, password: password),
    SignInMethod.password,
  );

  Future<void> signIn({
    required String email,
    required String password,
  }) async => _open(
    await accounts.login(email: email, password: password),
    SignInMethod.password,
  );

  /// The passkey sheet, then the same session as [signIn].
  Future<void> signInWithPasskey() async =>
      _open(await passkeys.signIn(), SignInMethod.passkey);

  Future<void> signOut() async {
    final token = _token;
    _token = null;
    _account = null;
    _method = null;
    notifyListeners();
    if (token != null) {
      try {
        await accounts.logout(token);
      } catch (_) {
        // Signed out here already; the token expires on the server anyway.
      }
    }
  }

  void _open(Map<String, dynamic> session, SignInMethod method) {
    _token = session['token'] as String;
    _account = Account.fromJson(session['user'] as Map<String, dynamic>);
    _method = method;
    notifyListeners();
  }
}

/// A password or a passkey.
enum SignInMethod { password, passkey }

/// Puts [AppState] above the screens.
class AppScope extends InheritedNotifier<AppState> {
  const AppScope({super.key, required AppState state, required super.child})
    : super(notifier: state);

  static AppState of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AppScope>()!.notifier!;
}
