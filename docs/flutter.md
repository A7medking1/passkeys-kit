# Flutter guide

`passkeys_kit` shows the system passkey sheet on iOS and Android and talks to the kit's server routes. Your app makes four calls: `signIn()`, `register()`, `list()` and `delete()`.

- [Install](#install)
- [Platform setup](#platform-setup)
- [Create the client](#create-the-client)
- [Sign in](#sign-in)
- [Add a passkey](#add-a-passkey)
- [List and delete](#list-and-delete)
- [Errors](#errors)
- [Use your app's Dio](#use-your-apps-dio)
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

It needs Flutter 3.41 or newer (Dart 3.11). It brings in [`passkeys`](https://pub.dev/packages/passkeys) for the system sheet, [`dio`](https://pub.dev/packages/dio) for the server, and [`device_info_plus`](https://pub.dev/packages/device_info_plus) to name new passkeys after the phone.

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
  server: DioPasskeyServerApi(
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

`DioPasskeyServerApi` makes its own Dio, which waits 20 seconds to connect and 30 seconds for an answer. If your app has a Dio already, pass it as `dio:` instead: see [your app's Dio](#use-your-apps-dio).

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

The user must be signed in: `headers`, or your Dio's interceptor, sends their token.

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
| `cancelled` | The user closed the sheet, or your Dio cancelled the request | Nothing. `isCancelled` is true, and `message` is empty. |
| `noPasskey` | Signing in, and the phone has no passkey for your RP ID | Offer the password sign-in |
| `alreadyRegistered` | Adding, and this phone already has a passkey for the account | Tell the user it's already set up |
| `needsGoogleAccount` | Android, with no Google account on the phone | Ask the user to add one |
| `notSupported` | An OS that's too old, or no screen lock | Hide the passkey options |
| `domainNotAssociated` | The app isn't tied to the RP ID's domain | Fix the [domain setup](domain-setup.md). Debug builds print a hint. |
| `server` | The server said no | Show `message`, the server's own. `statusCode` has the status. |
| `network` | The server couldn't be reached, or took too long to answer (Dio's timeouts) | Offer to retry |
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

## Use your app's Dio

If your app already has a Dio, with its `baseUrl`, its timeouts and an interceptor that adds the token, pass it as `dio:`. The passkey routes then go through the same interceptors as your other calls: the token, a refresh on 401, your logger. `baseUrl` can then be the router's path under the Dio's `baseUrl`:

```dart
import 'package:dio/dio.dart';
import 'package:passkeys_kit/passkeys_kit.dart';

final dio = Dio(BaseOptions(baseUrl: 'https://api.example.com/api/v1/'))
  ..interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) async {
        final token = await tokens.read();
        if (token != null) options.headers['Authorization'] = 'Bearer $token';
        handler.next(options);
      },
    ),
  );

final passkeys = PasskeyClient(
  server: DioPasskeyServerApi(
    baseUrl: Uri.parse('auth/passkeys'), // https://api.example.com/api/v1/auth/passkeys/
    dio: dio,
  ),
);
```

There's no `headers` here, because the interceptor sends the token. Your interceptors see paths like `auth/passkeys/login/options`. If yours refreshes the token on a 401, skip `login/options` and `login/verify`: they're public, so their 401 means a failed sign-in, not an expired session.

The kit doesn't change your Dio. It sets only what the passkey routes need, on each request: JSON both ways, and any status other than 2xx is an error, even when your Dio accepts 4xx answers. Dio's errors become a `PasskeyException`: a timeout or no connection is `network`, an error status is `server` with the server's message, and a cancelled request is `cancelled`.

The example app does the same: one Dio for its account calls and its passkeys, in [`dio_client.dart`](../flutter/example/lib/src/dio_client.dart).

To use another HTTP client, implement `PasskeyServerApi`, one method per route. The `FakeServer` in the example's [`widget_test.dart`](../flutter/example/test/widget_test.dart) is a whole implementation.

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
| `DioPasskeyServerApi({required baseUrl, headers, dio})` | `PasskeyServerApi` over Dio: your app's Dio, or one of its own |
| `PasskeyServerApi` | The interface, to use another HTTP client |
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
