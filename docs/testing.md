# Testing

The kit has three layers of tests: the server against a real MongoDB with a virtual authenticator, the Flutter package with fakes, and the whole flow on a Simulator by hand.

- [Server tests](#server-tests)
- [The virtual authenticator](#the-virtual-authenticator)
- [Flutter tests](#flutter-tests)
- [End to end on the iOS Simulator](#end-to-end-on-the-ios-simulator)
- [End to end on an Android emulator](#end-to-end-on-an-android-emulator)

## Server tests

```bash
cd server
npm install
npm test        # 29 tests in 10 suites
npm run typecheck
```

The tests need a MongoDB at `mongodb://127.0.0.1:27017`. Point them somewhere else with `TEST_MONGODB_URI`.

> [!NOTE]
> The tests use a database of their own, `passkeys_kit_test`, and drop it before and after the run. They refuse to start on any database whose name doesn't end in `_test`, so they can't wipe a real one by mistake.

They run one file at a time (`--test-concurrency=1`) because they share that database. Here's what they cover:

| File | What it checks |
| --- | --- |
| `passkeys.test.ts` | Origins for iOS and Android. Adding a passkey: the options, saving it, the default name, excluding the user's passkeys, every way a challenge can be wrong (used, unknown, expired, another user's), unknown origins, `canRegister`, `authenticate`, the 10-passkey limit, and malformed bodies. Signing in: the options, the `signIn` hook, `lastUsedAt`, the single 401 for every failure, a deleted account, and a refusing hook. The list, delete, `removeAll`, the rate limits, and custom messages. |
| `example.test.ts` | The example API: password accounts, then adding a passkey, signing out and back in with it, like the Flutter app does. Also that a password change ends the other sessions and deletes every passkey. |
| `well-known.test.ts` | Both `.well-known` files: their contents, JSON, the cache header, and no redirect. |

## The virtual authenticator

[`tests/virtual-authenticator.ts`](../server/tests/virtual-authenticator.ts) plays the phone. A `VirtualPasskey` holds a real P-256 key pair. It builds the same answers a phone sends, and SimpleWebAuthn checks its signatures for real. Nothing in the crypto is mocked.

```ts
import { userHandleOf, VirtualPasskey } from "./virtual-authenticator.js";

const passkey = new VirtualPasskey("example.com", "https://example.com");

// Add it, as a signed-in user.
const options = (await call("POST", "/auth/passkeys/register/options", { token, body: {} })).json;
await call("POST", "/auth/passkeys/register/verify", {
  token,
  body: { response: passkey.register(options), name: "iPhone 17 Pro" },
});

// Sign in with it, signed out.
const login = (await call("POST", "/auth/passkeys/login/options", { body: {} })).json;
const session = await call("POST", "/auth/passkeys/login/verify", {
  body: { response: passkey.signIn(login, userHandleOf(user.id)) },
});
```

`register` and `signIn` take an optional origin as the last argument, to act as an Android app or an attacker's site. `counter` is public, to test the signature counter. Copy the file into your own backend's tests to test your integration the same way.

What only a phone does is tried on the phones themselves: Face ID, the password manager, and the check of your `.well-known` files.

## Flutter tests

```bash
cd flutter
flutter test           # 15 tests
flutter analyze

cd example
flutter test           # 2 widget tests
flutter analyze
```

- `passkey_client_test.dart` runs `PasskeyClient` with a fake device and a fake server: the order of the calls, a cancelled sheet stopping before the server is asked again, and naming a new passkey.
- `dio_passkey_server_api_test.dart` runs `DioPasskeyServerApi` on a Dio with a fake `HttpClientAdapter`: the paths, bodies and headers, a Dio of your own with its `baseUrl` and interceptors, and turning errors, timeouts, lost connections and cancelled requests into `PasskeyException`.
- The example's `widget_test.dart` signs in with a passkey, adds one, and checks that the passkey button is hidden where passkeys don't work.

## End to end on the iOS Simulator

This is how the README's screenshots were made: a real passkey in the Simulator's Passwords app, verified by the example server.

1. Set up the domain ([Domain setup](domain-setup.md)) with your App ID under `webcredentials`.
2. Start the server: `cd server && npm run dev`.
3. Set up the app: copy `ios/Flutter/Local.xcconfig.example` to `Local.xcconfig` and fill it in. Then run `flutter run` in `flutter/example` with a Simulator selected.
4. Enroll Face ID: **Features → Face ID → Enrolled**.
5. Create an account, tap **Add a passkey**, then **Features → Face ID → Matching Face** when the sheet asks.

The same steps from a terminal, handy for scripts:

```bash
# Enroll Face ID
xcrun simctl spawn booted notifyutil -s com.apple.BiometricKit.enrollmentChanged '1'
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit.enrollmentChanged

# A matching face, while the sheet is waiting
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.match

# A face that doesn't match
xcrun simctl spawn booted notifyutil -p com.apple.BiometricKit_Sim.pearl.nomatch

# Start over: deletes the Simulator's saved passwords and passkeys
xcrun simctl keychain booted reset
```

To see what the server saved:

```bash
mongosh passkeys_kit --eval 'db.passkeys.find({}, { name: 1, userId: 1, deviceType: 1, lastUsedAt: 1 })'
```

For screenshots like the README's, switch the Simulator to dark mode and pin the status bar:

```bash
xcrun simctl ui booted appearance dark
xcrun simctl status_bar booted override --time 9:41 --batteryState charged --batteryLevel 100
xcrun simctl io booted screenshot sign-in.png
```

## End to end on an Android emulator

> [!NOTE]
> This release hasn't been run on Android yet. These steps follow Google's Credential Manager requirements. If you try them, please report how it went.

1. Create an emulator with a **Google Play** system image. Sign in to a Google account, and set a PIN in **Settings → Security**. Enroll a fingerprint there too.
2. Get your debug key's SHA-256:

   ```bash
   keytool -list -v -keystore ~/.android/debug.keystore -alias androiddebugkey -storepass android -keypass android | grep SHA256
   ```

3. Put it in `server/.env` along with the example's package name, `ANDROID_PACKAGE=com.example.passkeys_kit_example`. The RP ID's `assetlinks.json` must list both: deploy the example server on that domain, or put the file there yourself ([Domain setup](domain-setup.md#3-android)).
4. Run the app with `flutter run` in `flutter/example`. On the emulator, it reaches the server at `http://10.0.2.2:3000`, your computer's `localhost`.
5. When the sheet asks for a fingerprint, touch the sensor from a terminal:

   ```bash
   adb -e emu finger touch 1
   ```
