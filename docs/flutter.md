# Flutter guide

`passkeys_kit` shows the system passkey sheet on iOS and Android and talks to the kit's server routes. Your app makes four calls: `signIn()`, `register()`, `list()` and `delete()`.

- [Install](#install)
- [Platform setup](#platform-setup)
- [Create the client](#create-the-client)
- [Sign in](#sign-in)
- [Add a passkey](#add-a-passkey)
- [List and delete](#list-and-delete)
- [Errors](#errors)
- [Use your own HTTP client](#use-your-own-http-client)
- [Test your screens](#test-your-screens)
- [API reference](#api-reference)
- [UX tips](#ux-tips)

## Install

The package isn't on pub.dev yet. Add it from this repository:

```yaml
dependencies:
  passkeys_kit:
    git:
      url: https://github.com/A7medking1/passkeys-kit.git
      path: flutter
      ref: main # or a release tag
```

It needs Flutter 3.41 or newer (Dart 3.11). It brings in [`passkeys`](https://pub.dev/packages/passkeys) for the system sheet, [`http`](https://pub.dev/packages/http) for the server, and [`device_info_plus`](https://pub.dev/packages/device_info_plus) to name new passkeys after the phone.

## Platform setup

Your app must be tied to the RP ID's domain. [Domain setup](domain-setup.md) covers the domain side. The app side is short:

**iOS**

- Passkeys need **iOS 16**. Your app can target older versions, and `isAvailable()` returns `false` there.
- Add the **Associated Domains** capability with `webcredentials:<your RP ID>`. It needs a team in the paid Apple Developer Program.
- You don't need an Info.plist entry for Face ID. The passkey sheet is system UI, and it asks for Face ID itself.

**Android**

- Passkeys need **Android 9 (API 28)** with Google Play services. The `passkeys` plugin needs `minSdk` 23. Below API 28, `isAvailable()` returns `false`.
- You don't need anything in the manifest for passkeys. What counts is the key that signs the app: its SHA-256 must be in the domain's `assetlinks.json` and in the server's origins.

## Create the client

Make one `PasskeyClient` for the app, next to your other services:

```dart
import 'package:passkeys_kit/passkeys_kit.dart';

final passkeys = PasskeyClient(
  server: HttpPasskeyServerApi(
    // Where the server's router is mounted.
    baseUrl: Uri.parse('https://api.example.com/auth/passkeys'),
    // Runs before every request. The public routes ignore it.
    headers: () async {
      final token = await tokens.read();
      return {if (token != null) 'Authorization': 'Bearer $token'};
    },
  ),
);
```

`HttpPasskeyServerApi` also takes your own `http.Client` (`client:`) and a `timeout` (20 seconds by default). To use Dio or another client instead, see [your own HTTP client](#use-your-own-http-client).

## Sign in

```dart
Future<void> signInWithPasskey() async {
  try {
    final session = await passkeys.signIn();
    // Whatever the server's signIn hook returned, like { token, user }.
    await auth.saveSession(session);
  } on PasskeyException catch (error) {
    if (error.isCancelled) return; // the user closed the sheet
    showMessage(error.message);
  }
}
```

`signIn()` asks the server for options, shows the sheet with every passkey the phone has for your RP ID, and sends the signed answer back. The user types nothing.

Show the button only where it can work:

```dart
FutureBuilder<bool>(
  future: passkeys.isAvailable(), // asked once, then cached
  builder: (context, snapshot) => snapshot.data == true
      ? FilledButton.icon(
          onPressed: signInWithPasskey,
          icon: const Icon(Icons.fingerprint),
          label: const Text('Sign in with a passkey'),
        )
      : const SizedBox.shrink(),
)
```

## Add a passkey

The user must be signed in: `headers` sends their token.

```dart
try {
  final passkey = await passkeys.register(); // named after the phone: "iPhone 17 Pro"
  showMessage('Passkey added. Use it to sign in next time.');
} on PasskeyException catch (error) {
  if (!error.isCancelled) showMessage(error.message);
}
```

Pass `name:` to choose the name yourself: `passkeys.register(name: 'Work phone')`.

## List and delete

```dart
final List<PasskeyInfo> list = await passkeys.list(); // the newest first

for (final passkey in list) {
  print('${passkey.name}: synced ${passkey.isSynced}, last used ${passkey.lastUsedAt}');
}

await passkeys.delete(list.first.id);
```

`PasskeyInfo` has `id`, `name`, `deviceType` (`singleDevice` or `multiDevice`), `backedUp`, `createdAt`, `lastUsedAt` (null until first used), and `isSynced`.

Deleting a passkey removes it from the server. It stays in the phone's password manager, because apps can't delete from there, but it can't sign in any more. Tell users they can delete it in their phone's settings too.

## Errors

Every call throws a `PasskeyException` when it fails. It tells you why in `reason`:

| `reason` | When | What to do |
| --- | --- | --- |
| `cancelled` | The user closed the sheet | Nothing. `isCancelled` is true, and `message` is empty. |
| `noPasskey` | Signing in, and the phone has no passkey for your RP ID | Offer the password sign-in |
| `alreadyRegistered` | Adding, and this phone already has a passkey for the account | Tell the user it's already set up |
| `needsGoogleAccount` | Android, with no Google account on the phone | Ask the user to add one |
| `notSupported` | An OS that's too old, or no screen lock | Hide the passkey options |
| `domainNotAssociated` | The app isn't tied to the RP ID's domain | Fix the [domain setup](domain-setup.md). Debug builds print a hint. |
| `server` | The server said no | Show `message`, the server's own. `statusCode` has the status. |
| `network` | The server couldn't be reached, or took longer than `timeout` | Offer to retry |
| `unknown` | Anything else | Show `message`, and log `cause` |

`message` is the server's message when there is one, otherwise an English default for the `reason`. `cause` keeps the original error for your logs.

To show your own words, switch on `reason`, and on `statusCode` for the server's answers:

```dart
String describe(PasskeyException error, AppLocalizations l10n) => switch (error.reason) {
  PasskeyFailure.noPasskey => l10n.noPasskeyOnThisPhone,
  PasskeyFailure.server when error.statusCode == 401 => l10n.passkeySignInFailed,
  PasskeyFailure.network => l10n.checkYourConnection,
  _ => error.message,
};
```

## Use your own HTTP client

`PasskeyClient` talks to the server through the `PasskeyServerApi` interface. `HttpPasskeyServerApi` is one implementation, and you can write your own, to reuse your Dio instance with its interceptors, for example:

```dart
import 'package:dio/dio.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

/// The kit's routes over Dio. Give it a Dio whose baseUrl is where the router
/// is mounted, with a trailing slash: https://api.example.com/auth/passkeys/
class DioPasskeyServerApi implements PasskeyServerApi {
  DioPasskeyServerApi(this._dio);

  final Dio _dio;

  @override
  Future<Map<String, dynamic>> registerOptions() =>
      _send<Map<String, dynamic>>(() => _dio.post('register/options', data: {}));

  @override
  Future<PasskeyInfo> registerVerify(
    Map<String, dynamic> response, {
    String? name,
  }) async => PasskeyInfo.fromJson(
    await _send<Map<String, dynamic>>(
      () => _dio.post('register/verify', data: {'response': response, 'name': ?name}),
    ),
  );

  @override
  Future<Map<String, dynamic>> loginOptions() =>
      _send<Map<String, dynamic>>(() => _dio.post('login/options', data: {}));

  @override
  Future<Map<String, dynamic>> loginVerify(Map<String, dynamic> response) =>
      _send<Map<String, dynamic>>(
        () => _dio.post('login/verify', data: {'response': response}),
      );

  @override
  Future<List<PasskeyInfo>> list() async {
    final items = await _send<List<dynamic>>(() => _dio.get(''));
    return [
      for (final item in items) PasskeyInfo.fromJson(item as Map<String, dynamic>),
    ];
  }

  @override
  Future<void> delete(String id) async {
    await _send<Object?>(() => _dio.delete(Uri.encodeComponent(id)));
  }

  /// Turns Dio's errors into the PasskeyException the app expects.
  Future<T> _send<T>(Future<Response<dynamic>> Function() request) async {
    try {
      return (await request()).data as T;
    } on DioException catch (error) {
      final response = error.response;
      if (response == null) {
        throw PasskeyException(PasskeyFailure.network, cause: error);
      }
      final data = response.data;
      throw PasskeyException(
        PasskeyFailure.server,
        message: data is Map ? data['message'] as String? : null,
        statusCode: response.statusCode,
        cause: error,
      );
    }
  }
}
```

```dart
final passkeys = PasskeyClient(server: DioPasskeyServerApi(dio));
```

## Test your screens

The phone's side is an interface too, `PasskeyDevice`, so widget tests can run without a phone. Give `PasskeyClient` a fake device and a fake server:

```dart
class FakeDevice implements PasskeyDevice {
  FakeDevice({this.cancel = false});

  final bool cancel;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Map<String, dynamic>> authenticate(Map<String, dynamic> options) async {
    if (cancel) throw const PasskeyException(PasskeyFailure.cancelled);
    return {'id': 'pk1'};
  }

  @override
  Future<Map<String, dynamic>> register(Map<String, dynamic> options) async => {'id': 'pk1'};

  @override
  Future<String?> name() async => 'iPhone 17 Pro';
}

final client = PasskeyClient(server: FakeServer(), device: FakeDevice());
```

The example's [`widget_test.dart`](../flutter/example/test/widget_test.dart) has a whole `FakeServer`, and [Testing](testing.md) covers the rest.

## API reference

| | |
| --- | --- |
| `PasskeyClient({required server, device})` | The entry point. `device` defaults to `SystemPasskeyDevice()`. |
| `Future<bool> isAvailable()` | Whether this phone can use passkeys. Asked once, then cached. |
| `Future<Map<String, dynamic>> signIn()` | The sheet, then `login/verify`. Returns your server's session. |
| `Future<PasskeyInfo> register({String? name})` | Makes a passkey on this phone for the signed-in user |
| `Future<List<PasskeyInfo>> list()` | The signed-in user's passkeys, the newest first |
| `Future<void> delete(String id)` | Deletes one on the server |
| `HttpPasskeyServerApi({required baseUrl, headers, client, timeout})` | `PasskeyServerApi` over `package:http` |
| `PasskeyServerApi` | The interface for your own HTTP client |
| `PasskeyDevice`, `SystemPasskeyDevice({authenticator})` | The phone's side, and its real implementation |
| `PasskeyInfo` | One passkey as the server lists it |
| `PasskeyException`, `PasskeyFailure`, `defaultPasskeyMessages` | Errors, their reasons, and the English defaults |

`SystemPasskeyDevice` creates the `passkeys` package's `PasskeyAuthenticator` with `debugMode` on in debug builds. In that mode, it checks your domain setup and prints what it finds.

## UX tips

These are the patterns the example app follows.

- **Put the passkey first.** Show **Sign in with a passkey** above the password form, and only where `isAvailable()` is true.
- **Offer a passkey right after a password sign-in.** The home screen in the example says "No passkeys yet" with an **Add a passkey** button.
- **Stay quiet on cancel.** Closing the sheet is a choice, not an error.
- **Name passkeys after the phone**, which `register()` does by default, and mark synced ones. Users recognize "iPhone 17 Pro · Synced".
- **Keep a way back in.** A passkey can be deleted or lost with a phone. Keep the password, or another recovery path, and let the server's message point users to it, as `signInFailed` does.
