# Troubleshooting

> [!TIP]
> **Look at the server's log first.** The app only ever gets a generic message, but the server logs the real reason for each refused passkey, like this:
>
> ```text
> Passkey sign-in refused: Unexpected authentication response origin "android:apk-key-hash:boNIbF…", expected …
> ```
>
> It goes to `console.warn`, or to your own `log` option.

- [iOS](#ios)
- [Android](#android)
- [Server](#server)
- [In the app](#in-the-app)

## iOS

### The sheet never appears, and the app gets `domainNotAssociated`

The debug console says something like *"Application with identifier … is not associated with domain …"*. iOS doesn't think your app may use the RP ID's passkeys. Check each link of the chain:

1. **The file.** `curl -i https://<RP ID>/.well-known/apple-app-site-association` should answer `200` with JSON and no redirect, and list `TEAMID.bundle.id` under `webcredentials.apps`.
2. **The ids.** The Team ID and bundle id in that file match the app you're running, letter for letter. In the example, they come from `ios/Flutter/Local.xcconfig`.
3. **The entitlement.** It says `webcredentials:<RP ID>` with the same domain as the server's `rpID`, with no `https://` and no path.
4. **Apple's CDN.** iPhones get the file from Apple's CDN, not from your domain. See what it serves with `curl -s https://app-site-association.cdn-apple.com/a/v1/<RP ID>`. If it's old, wait for it to refresh, or add `?mode=developer` to the entitlement while you develop ([Domain setup](domain-setup.md#apples-cdn)).
5. **Reinstall the app.** iOS reads the associated domains when the app is installed.

### Xcode says personal teams don't support Associated Domains

The Associated Domains capability needs a team in the paid Apple Developer Program. Set `PASSKEYS_TEAM_ID` to that team.

### `register/verify` answers 422 after "Save a passkey?"

The phone made the passkey, but the server refused it. The log says why:

- **"Unexpected registration response origin"** or **RP ID**: the server's `rpID` and the app's entitlement name different domains.
- **The challenge**: more than `challengeTtlMs` (5 minutes) passed between the options and the verify, or the same options were used twice. Start again from `register/options`.

### Signing in says there's no passkey (`noPasskey`)

This phone has no passkey for the RP ID. The user adds one first, while signed in. On a real device, passkeys need iCloud Keychain turned on.

### The Simulator asks for a passcode, or nothing happens

Face ID isn't enrolled. Use **Features → Face ID → Enrolled**, then **Matching Face** when the sheet asks. [Testing](testing.md#end-to-end-on-the-ios-simulator) has the terminal commands.

## Android

### The sheet fails, or the app gets `domainNotAssociated`

Google doesn't think your app may use the RP ID's passkeys:

1. `curl -i https://<RP ID>/.well-known/assetlinks.json` answers `200` with JSON and no redirect.
2. The entry has `delegate_permission/common.get_login_creds`, your exact package name, and the SHA-256 of **the key that signed the build you're running**. A debug build is signed with your debug key. A build from Google Play is signed with the Play App Signing key, not your upload key.
3. Ask Google what it reads: `https://digitalassetlinks.googleapis.com/v1/statements:list?source.web.site=https://<RP ID>&relation=delegate_permission/common.get_login_creds`.

### Every sign-in or registration from Android gets refused

The log says *"Unexpected … origin "android:apk-key-hash:…""*. The app is signed with a key the server doesn't know. Add that key's SHA-256 to the server's origins (`passkeyOrigins({ androidSha256 })`, or `ANDROID_SHA256` in the example), and to `assetlinks.json`.

### `needsGoogleAccount`

Google Password Manager keeps the passkeys, so the phone needs a Google account. Add one in Settings.

### `notSupported`, or the passkey button never shows

Passkeys need Android 9 (API 28), Google Play services, and a screen lock. On an emulator, use a **Google Play** system image and set a PIN.

### The emulator can't reach the server

The emulator reaches your computer at `http://10.0.2.2:<port>`, which the example uses by default. Check that the server is running. Debug builds of the example may use plain `http`; release builds can't. For those, give the app an HTTPS URL with `--dart-define=SERVER_URL=https://…`.

## Server

### Everyone gets 429

The server is behind a proxy, so every request seems to come from the proxy's IP, and everyone shares one rate limit. Set `app.set("trust proxy", 1)` for one proxy hop. See [Rate limits](server.md#rate-limits).

### `register/options` answers 409

The user already has `maxPasskeysPerUser` passkeys, 10 by default. They can delete one, or you can raise the limit in `config`.

### The register routes or the list answer 401

Your `authenticate` middleware didn't find a signed-in user. In Flutter, check that `HttpPasskeyServerApi`'s `headers` returns the token.

### "User ids must be 64 bytes at most"

`users.id(user)` returned an id longer than 64 bytes, the most a user handle can hold. Use a short, stable id: an ObjectId or a UUID.

### Old challenges pile up in `passkey_challenges`

The TTL index is missing, usually because Mongoose's `autoIndex` is off. Build it once with `await PasskeyChallenge.syncIndexes()`. A few expired challenges sticking around for a minute is normal: MongoDB's TTL sweep runs about once a minute.

## In the app

### A deleted passkey still shows in the sheet

That's expected. Deleting a passkey removes it from your server. The phone keeps it in its password manager, because apps can't delete from there, but the server refuses it. Users can delete it in the **Passwords** app on iOS, or in Google Password Manager on Android.

### New passkeys are named "Passkey" instead of the phone's model

`device_info_plus` couldn't read the model. Pass a name yourself: `passkeys.register(name: 'My phone')`.

### Errors show up when the user closes the sheet

Check `error.isCancelled` and show nothing when it's true. See [Errors](flutter.md#errors).
